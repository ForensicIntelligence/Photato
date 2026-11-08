import CoreVideo
import Foundation
import PhotoCraftCore
import Vision

/// Injectable only for validation; production always uses Apple's local Vision model.
public protocol ForegroundDetecting: Sendable {
  func mask(for image: Surface) async throws -> SelectionMask
}

/// Distinguishes a valid image with no foreground subject from a failed model request.
public protocol OptionalForegroundDetecting: ForegroundDetecting {
  func maskIfPresent(for image: Surface) async throws -> SelectionMask?
}

public protocol ObjectDetecting: Sendable {
  func mask(for image:Surface,at point:PathPoint) async throws -> SelectionMask
}

public struct VisionForegroundDetector: OptionalForegroundDetecting, ObjectDetecting, AllObjectsDetecting {
  public init() {}
  // Vision explicitly supports cancelling requests while perform is in progress.
  private final class Request: @unchecked Sendable {
    let value = VNGenerateForegroundInstanceMaskRequest()
  }
  public func mask(for image: Surface) async throws -> SelectionMask {try await detect(image, point:nil, allObjects:false)[0].mask}
  public func mask(for image:Surface,at point:PathPoint) async throws -> SelectionMask {try await detect(image, point:point, allObjects:false)[0].mask}
  public func masks(for image:Surface) async throws -> [DetectedObjectMask] {try await detect(image,point:nil,allObjects:true)}
  public func maskIfPresent(for image: Surface) async throws -> SelectionMask? {
    try await detect(image, point: nil, allObjects: false, allowEmpty: true).first?.mask
  }
  private func detect(_ image:Surface,point:PathPoint?,allObjects:Bool,allowEmpty:Bool = false) async throws -> [DetectedObjectMask] {
    try ForegroundSelection.checkSize(image.width, image.height)
    if let point {guard point.x.isFinite,point.y.isFinite,point.x>=0,point.y>=0,point.x<Double(image.width),point.y<Double(image.height) else {throw CraftError.invalid("Click inside the image to select an object.")}}
    let request = Request()
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let handler = VNImageRequestHandler(cgImage: try RasterIO.displayImage(image), options: [:])
      do { try handler.perform([request.value]) } catch {
        try Task.checkCancellation()
        throw CraftError.unavailable("Apple's on-device subject model could not run: \(error.localizedDescription)")
      }
      try Task.checkCancellation()
      guard let observation = request.value.results?.first, !observation.allInstances.isEmpty else {
        if allowEmpty { return [DetectedObjectMask]() }
        throw CraftError.invalid("No foreground subject was found. Try an image with a distinct subject.")
      }
      let instances:IndexSet
      if let point {
        let label=try Self.instance(at:point,in:observation.instanceMask,imageWidth:image.width,imageHeight:image.height)
        guard label>0,observation.allInstances.contains(label) else {throw CraftError.invalid("No foreground object at this point. Choose a distinct object or paint its mask manually.")}
        instances=IndexSet(integer:label)
      } else {instances=observation.allInstances}
      if allObjects {try MaskAllObjectsEdit.checkBudget(width:image.width,height:image.height,count:instances.count)}
      let sets = allObjects ? instances.map { IndexSet(integer:$0) } : [instances]
      var result:[DetectedObjectMask]=[]
      for labels in sets {
        try Task.checkCancellation()
        let buffer=try observation.generateScaledMaskForImage(forInstances:labels,from:handler)
        result.append(.init(instanceID:labels.first!,mask:try Self.coverage(buffer,width:image.width,height:image.height)))
      }
      return result
    }
    return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: {
      worker.cancel()
      request.value.cancel()
    })
  }
  static func coverage(_ buffer:CVPixelBuffer,width:Int,height:Int)throws->SelectionMask {
      guard CVPixelBufferGetWidth(buffer) == width,
        CVPixelBufferGetHeight(buffer) == height,
        CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
        CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
      else { throw CraftError.unavailable("Apple Vision returned an unsupported foreground mask.") }
      defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
      guard let base = CVPixelBufferGetBaseAddress(buffer) else {
        throw CraftError.unavailable("Apple Vision returned an empty mask buffer.")
      }
      let stride = CVPixelBufferGetBytesPerRow(buffer)
      var bytes = [UInt8](repeating: 0, count: width * height)
      for y in 0..<height {
        try Task.checkCancellation()
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
        for x in 0..<width {
          let value = row[x]
          guard value.isFinite else { throw CraftError.invalid("Invalid foreground mask sample.") }
          bytes[y * width + x] = UInt8((min(1, max(0, value)) * 255).rounded())
        }
      }
      return try SelectionMask(width: width, height: height, bytes: bytes)
  }
  public static func instance(at point:PathPoint,in buffer:CVPixelBuffer,imageWidth:Int,imageHeight:Int)throws->Int {
    let w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer)
    guard imageWidth>0,imageHeight>0,w>0,h>0,point.x.isFinite,point.y.isFinite,point.x>=0,point.y>=0,point.x<Double(imageWidth),point.y<Double(imageHeight),CVPixelBufferGetPixelFormatType(buffer)==kCVPixelFormatType_OneComponent8,CVPixelBufferLockBaseAddress(buffer,.readOnly)==kCVReturnSuccess else {throw CraftError.invalid("Unsupported object label mask or point.")}
    defer {CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
    guard let base=CVPixelBufferGetBaseAddress(buffer) else {throw CraftError.invalid("Empty object label mask.")}
    // Document coordinates and Vision pixel-buffer rows both start at the top left.
    let x=min(w-1,Int(point.x/Double(imageWidth)*Double(w))),y=min(h-1,Int(point.y/Double(imageHeight)*Double(h)))
    return Int(base.assumingMemoryBound(to:UInt8.self)[y*CVPixelBufferGetBytesPerRow(buffer)+x])
  }
}

public enum ForegroundSelection {
  public static let maximumPixels = 8_388_608
  public static func checkSize(_ width: Int, _ height: Int) throws {
    guard width > 0, height > 0, width <= 6000, height <= 6000,
      width <= maximumPixels / height else {
      throw CraftError.unsupported("Subject detection supports up to 6000 pixels per side and 8,388,608 canvas pixels.")
    }
  }
  public static func command(document: CraftDocument, layerID: UUID, removeBackground: Bool,
    sampleAllLayers: Bool = false, mode: SelectionMode = .replace,
    detector: any ForegroundDetecting = VisionForegroundDetector()) async throws -> Command {
    try checkSize(document.width, document.height)
    guard let layer = document.layers.first(where: { $0.id == layerID }),
      case .raster = layer.content else {
      throw CraftError.invalid("Select a pixel layer for automatic subject detection.")
    }
    if removeBackground {
      guard !document.isLocked(layerID), layer.mask == nil else {
        throw CraftError.invalid("Unlock the pixel layer and delete or apply its existing mask first.")
      }
    }
    let input: Surface
    if sampleAllLayers { input = try Renderer.composite(document) }
    else {
      var source = layer
      source.visible = true
      source.style = nil
      input = try Renderer.clippingCoverage(source, in: document)
    }
    let proxy = try ColorManagement.converted(input, from: document, to: CraftDocument(width: 1, height: 1))
    let mask = try await detector.mask(for: proxy)
    try Task.checkCancellation()
    return removeBackground ? .removeBackground(layerID, mask) : .selectSubject(mask, mode)
  }
}
