import Foundation
import CoreGraphics
import Vision
import PhotoCraftCore

public protocol PeopleDetecting: Sendable {
  func people(in image: Surface) async throws -> [DetectedObjectMask]
}

/// Person instances, rather than generic foreground objects. All inference stays on device.
public struct VisionPeopleDetector: PeopleDetecting {
  public init() {}
  private final class Request: @unchecked Sendable { let value = VNGeneratePersonInstanceMaskRequest() }
  public func people(in image: Surface) async throws -> [DetectedObjectMask] {
    try ForegroundSelection.checkSize(image.width,image.height)
    let request = Request()
    let worker = Task.detached(priority:.userInitiated) {
      try Task.checkCancellation()
      let handler = VNImageRequestHandler(cgImage:try RasterIO.displayImage(image),options:[:])
      do { try handler.perform([request.value]) } catch {
        try Task.checkCancellation()
        throw CraftError.unavailable("Apple's on-device person model could not run: \(error.localizedDescription)")
      }
      try Task.checkCancellation()
      guard let observation = request.value.results?.first, !observation.allInstances.isEmpty else { return [DetectedObjectMask]() }
      try MaskAllObjectsEdit.checkBudget(width:image.width,height:image.height,count:observation.allInstances.count)
      return try observation.allInstances.map { id in
        try Task.checkCancellation()
        let buffer = try observation.generateScaledMaskForImage(forInstances:IndexSet(integer:id),from:handler)
        return DetectedObjectMask(instanceID:id,mask:try VisionForegroundDetector.coverage(buffer,width:image.width,height:image.height))
      }
    }
    return try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel();request.value.cancel()})
  }
}

public struct PeopleScene: Sendable {
  public let source: ObjectFinderSource
  public let people: [FoundObject]
  public let thumbnails: [Int:CGImage]
  public let featureMap: PeopleFeatureMap?
  public let featureError: String?
  public var availableFeatures: [PeopleFeature] { featureMap == nil ? [.wholePerson]:PeopleFeature.allCases }
  public init(source: ObjectFinderSource, input: Surface, masks: [DetectedObjectMask], featureMap: PeopleFeatureMap? = nil, featureError: String? = nil) throws {
    try ForegroundSelection.checkSize(source.document.width,source.document.height)
    guard input.width == source.document.width, input.height == source.document.height else { throw CraftError.invalid("Person source size changed.") }
    self.source = source
    self.featureMap=featureMap;self.featureError=featureError
    people = masks.isEmpty ? [] : try ObjectFinderScene(source:source,masks:masks).objects
    let image = try RasterIO.displayImage(input)
    var thumbnails: [Int:CGImage] = [:]
    for person in people {
      try Task.checkCancellation()
      let r = person.bounds
      guard let crop = image.cropping(to:CGRect(x:r.x,y:r.y,width:r.width,height:r.height)) else { continue }
      let scale = min(96.0/Double(r.width),96.0/Double(r.height))
      let w = max(1,Int(Double(r.width)*scale)), h = max(1,Int(Double(r.height)*scale))
      guard let context = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
        space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CraftError.invalid("Cannot create person thumbnail.") }
      context.interpolationQuality = .high; context.draw(crop,in:CGRect(x:0,y:0,width:w,height:h))
      thumbnails[person.instanceID] = context.makeImage()
    }
    self.thumbnails = thumbnails
  }
  public static func detect(_ document: CraftDocument, layerID: UUID?, sampleAllLayers: Bool,
    detector: any PeopleDetecting = VisionPeopleDetector(), featuresDetector: (any PeopleFeaturesDetecting)? = nil) async throws -> PeopleScene {
    try ForegroundSelection.checkSize(document.width,document.height)
    let input = try SelectionToolPreparation.input(document,layerID:layerID,allLayers:sampleAllLayers)
    let masks = try await detector.people(in:input)
    try Task.checkCancellation()
    var features:PeopleFeatureMap?,error:String?
    if let featuresDetector, !masks.isEmpty {
      do { features=try await featuresDetector.features(in:input) }
      catch is CancellationError { throw CancellationError() }
      catch let failure { error=failure.localizedDescription }
    }
    try Task.checkCancellation()
    return try .init(source:.init(document,layerID:layerID,sampleAllLayers:sampleAllLayers),input:input,masks:masks,featureMap:features,featureError:error)
  }
  public func coverage(instanceIDs: [Int], hardEdge: Bool, features: [PeopleFeature] = [.wholePerson]) throws -> SelectionMask {
    guard !instanceIDs.isEmpty, instanceIDs.count <= 64, Set(instanceIDs).count == instanceIDs.count,
      instanceIDs.allSatisfy({id in people.contains{$0.instanceID == id}}) else { throw CraftError.invalid("Choose one or more detected people from the current image.") }
    guard !features.isEmpty,Set(features).count==features.count else { throw CraftError.invalid("Choose unique person features.") }
    guard features.allSatisfy({availableFeatures.contains($0)}) else { throw CraftError.unavailable(featureError ?? "The person feature model is not installed.") }
    var bytes = [UInt8](repeating:0,count:source.document.width*source.document.height)
    for person in people where instanceIDs.contains(person.instanceID) {
      for y in 0..<person.mask.height {
        try Task.checkCancellation()
        for x in 0..<person.mask.width { let i = y*person.mask.width+x; bytes[i] = max(bytes[i],person.mask.bytes[i]) }
      }
    }
    let whole=try SelectionMask(width:source.document.width,height:source.document.height,bytes:bytes)
    return try ObjectFinderScene.coverage(featureMap?.restricting(whole,to:features) ?? whole,hardEdge:hardEdge)
  }
  public func command(instanceIDs: [Int], mode: SelectionMode, hardEdge: Bool, features: [PeopleFeature] = [.wholePerson]) throws -> Command {
    .selectionCoverage(try coverage(instanceIDs:instanceIDs,hardEdge:hardEdge,features:features),mode)
  }
}
