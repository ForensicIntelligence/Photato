import AppKit
import Foundation
import PhotoCraftCore

public struct ColorProfileRequest: Equatable, Sendable {
  public enum Operation: String, CaseIterable, Sendable { case assign, convert }
  public var operation: Operation
  public var profile: Data
  public var removeProfile = false
  public var intent: ModeRenderingIntent = .relativeColorimetric
  public var blackPointCompensation = true
  public var mergeVisible = false
  public init(_ operation: Operation, profile: Data) { self.operation = operation; self.profile = profile }
}

public enum ColorProfileInput {
  public static func effectiveProfile(_ document: CraftDocument) throws -> Data {
    try document.modeDescriptor?.profile ?? document.workingICC ?? NativeModeProfile.standard(document.colorMode, depth: document.depth)
  }
  public static func name(_ document: CraftDocument) -> String {
    let profile = try? effectiveProfile(document)
    let name = profile.flatMap { CGColorSpace(iccData: $0 as CFData) }
      .flatMap { NSColorSpace(cgColorSpace: $0)?.localizedName } ?? document.colorMode.title
    return document.profileIsUntagged == true ? "Untagged (\(name))" : name
  }
  public static func needsMerge(_ document: CraftDocument, destination: DocumentColorMode) -> Bool {
    document.layers.contains { layer in
      if layer.smartObject != nil || layer.smartFilters != nil || layer.style != nil { return true }
      switch layer.content {
      case .raster, .group: return false
      case .fill, .text: return document.modeDescriptor != nil || destination != .rgb
      case .shape(let shape):
        if document.modeDescriptor != nil || destination != .rgb { return true }
        guard let definition = shape.definition else { return false }
        return ![.none, .solid].contains(definition.fill.kind) || ![.none, .solid].contains(definition.stroke.paint.kind)
      default: return true
      }
    }
  }
  public static func command(_ request: ColorProfileRequest, in document: CraftDocument) throws -> Command {
    try document.validate(); try Task.checkCancellation()
    guard DocumentColorMode.componentModes.contains(document.colorMode), !document.layers.isEmpty,
      document.width <= NativeModeRaster.maximumPixels / document.height else {
      throw CraftError.unsupported("Profile operations require RGB, CMYK, Grayscale or Lab, up to 8,388,608 canvas pixels.")
    }
    let destination = try ProofSettings.mode(of: request.profile)
    try NativeModeProfile.validate(request.profile, mode: destination, depth: document.depth)
    if request.operation == .assign {
      guard destination == document.colorMode else { throw CraftError.invalid("Assign a profile for the current color mode.") }
      var result = document
      if var descriptor = result.modeDescriptor {
        guard result.layers.allSatisfy({ if case .raster = $0.content { return true }; if case .group = $0.content { return true }; return false }) else {
          throw CraftError.unsupported("Profile assignment to native component documents with live non-pixel layers is not supported yet.")
        }
        descriptor.profile = request.profile; result.modeDescriptor = descriptor
        for i in result.layers.indices { if let raster = result.layers[i].nativeMode {
          let assigned = try raster.assigning(profile: request.profile)
          result.layers[i].nativeMode = assigned; result.layers[i].content = .raster(try assigned.surface())
        } }
      } else { result.workingICC = request.profile }
      result.profileIsUntagged = request.removeProfile ? true : nil
      result.variables = try VariableGraphicsInput.imagesForWorkingProfile(in: result)
      try result.validate()
      return .preparedColorProfile(.init(source: document, result: result, title: "Assign Profile"))
    }
    guard !request.removeProfile else { throw CraftError.invalid("Convert to Profile requires a destination profile.") }
    guard request.mergeVisible || !needsMerge(document, destination: destination) else {
      throw CraftError.unsupported("Enable Flatten Image to Preserve Appearance for this layer stack, or cancel and prepare a copy.")
    }
    var result = document
    if request.mergeVisible {
      guard !document.hasArtboards, !document.hasFrames else { throw CraftError.unsupported("Prepare a rendered copy of artboards or frames first.") }
      var layer = Layer(name: "Merged", content: .raster(try Renderer.composite(document)))
      layer.id = document.activeLayerID ?? document.id
      result.layers = [layer]; result.activeLayerID = layer.id; result.modeDescriptor = nil
    }
    let sourceProfile = try request.mergeVisible && document.modeDescriptor != nil
      ? NativeModeProfile.standard(.rgb, depth: document.depth) : effectiveProfile(document)
    let sourceMode: DocumentColorMode = request.mergeVisible ? .rgb : document.colorMode
    let transform = try ProofTransform(sourceProfile, request.profile, intent: request.intent, bpc: request.blackPointCompensation)
    // Ordinary RGB keeps editable text/solid vector/fill layers and its working-coordinate buffer.
    let nativeOutput = document.modeDescriptor != nil || destination != .rgb
    for i in result.layers.indices {
      try Task.checkCancellation()
      switch result.layers[i].content {
      case .raster(let pixels):
        let sourceNative = request.mergeVisible ? nil : result.layers[i].nativeMode
        var output = try NativeModeRaster(width: pixels.width, height: pixels.height, mode: destination,
          depth: document.depth, profile: request.profile, intent: request.intent)
        for y in 0..<pixels.height {
          try Task.checkCancellation()
          var row: [Float] = []; row.reserveCapacity(pixels.width * sourceMode.componentCount)
          for x in 0..<pixels.width {
            if let sourceNative {
              var values = Array(sourceNative.components(index: y * pixels.width + x).prefix(sourceMode.componentCount))
              if sourceMode == .lab { values[1] *= 255 / 256; values[2] *= 255 / 256 }
              row += values
            } else {
              let p = document.depth == .f32 ? pixels.linearPixel(x: x, y: y) : pixels.pixel(x: x, y: y)
              row += [p.r, p.g, p.b]
            }
          }
          let converted = sourceProfile == request.profile && sourceMode == destination ? row : try transform.apply(row)
          for x in 0..<pixels.width {
            let at = y * pixels.width + x
            for c in 0..<destination.componentCount {
              let value = converted[x * destination.componentCount + c] * (destination == .lab && c > 0 ? 256 / 255 : 1)
              try output.set(value, component: c, index: at)
            }
            let alpha = sourceNative?.value(component: sourceMode.componentCount, index: at) ?? pixels.pixel(x: x, y: y).a
            try output.set(alpha, component: destination.componentCount, index: at)
          }
        }
        if nativeOutput { result.layers[i].nativeMode = output; result.layers[i].content = .raster(try output.surface()) }
        else {
          var surface = try Surface(width: pixels.width, height: pixels.height, depth: document.depth,
            colorEncoding: document.depth == .f32 ? .linearRGB : .sRGB)
          for y in 0..<surface.height { try Task.checkCancellation(); for x in 0..<surface.width {
            let values = output.components(index: y * surface.width + x), p = Pixel(values[0], values[1], values[2], values[3])
            if document.depth == .f32 { surface.setLinearPixel(x: x, y: y, p) } else { surface.setPixel(x: x, y: y, p) }
          } }
          result.layers[i].content = .raster(surface)
        }
      case .fill(let p): result.layers[i].content = .fill(try convertColor(p, transform, depth: document.depth))
      case .text(var text): text.color = try convertColor(text.color, transform, depth: document.depth); result.layers[i].content = .text(text)
      case .shape(var shape):
        shape.color = try convertColor(shape.color, transform, depth: document.depth)
        if var definition = shape.definition {
          definition.fill.color = try convertColor(definition.fill.color, transform, depth: document.depth)
          definition.stroke.paint.color = try convertColor(definition.stroke.paint.color, transform, depth: document.depth)
          shape.definition = definition
        }
        result.layers[i].content = .shape(shape)
      case .group: break
      default: throw CraftError.unsupported("Flatten this layer stack before converting profiles.")
      }
    }
    result.profileIsUntagged = nil
    if nativeOutput {
      result.modeDescriptor = try .init(mode: destination, depth: document.depth, profile: request.profile, intent: request.intent)
      result.workingICC = nil
    } else { result.workingICC = request.profile }
    result.variables = try VariableGraphicsInput.imagesForWorkingProfile(in: result)
    try result.validate()
    return .preparedColorProfile(.init(source: document, result: result, title: "Convert to Profile"))
  }
  private static func convertColor(_ pixel: Pixel, _ transform: ProofTransform, depth: PixelDepth) throws -> Pixel {
    let p = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    let values = try transform.apply([p.r, p.g, p.b])
    let output = Pixel(values[0], values[1], values[2], p.a)
    return depth == .f32 ? SRGBTransfer.encoded(output) : output
  }
}
