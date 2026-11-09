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
  public static let maximumDocumentPixels = Surface.maxPixels
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
      case .fill, .text, .gradientFill: return document.modeDescriptor != nil || destination != .rgb
      case .shape(let shape):
        if document.modeDescriptor != nil || destination != .rgb { return true }
        guard let definition = shape.definition else { return false }
        return definition.fill.kind == .pattern || definition.stroke.paint.kind == .pattern
      default: return true
      }
    }
  }
  /// Raster exports preserve the source composite before a nonlinear profile transform.
  /// Keeping editable stop controls is a separate choice from preserving raster appearance.
  public static func needsRasterMerge(_ document: CraftDocument, destination: DocumentColorMode) -> Bool {
    needsMerge(document, destination: destination) || document.layers.contains { layer in
      switch layer.content {
      case .gradientFill: return true
      case .shape(let shape):
        return shape.definition?.fill.kind == .gradient || shape.definition?.stroke.paint.kind == .gradient
      default: return false
      }
    }
  }
  public static func command(_ request: ColorProfileRequest, in document: CraftDocument) throws -> Command {
    try document.validate(); try Task.checkCancellation()
    guard DocumentColorMode.componentModes.contains(document.colorMode), !document.layers.isEmpty else {
      throw CraftError.unsupported("Profile operations require RGB, CMYK, Grayscale or Lab.")
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
    let rasterConversion = ColorProfileRasterConversion(request: request, depth: document.depth,
      sourceProfile: sourceProfile, sourceMode: sourceMode, destination: destination,
      nativeOutput: nativeOutput, transform: transform)
    for i in result.layers.indices {
      try Task.checkCancellation()
      switch result.layers[i].content {
      case .raster(let pixels):
        let sourceNative = request.mergeVisible ? nil : result.layers[i].nativeMode
        let output = try rasterConversion.apply(pixels, native: sourceNative)
        result.layers[i].nativeMode = output.native
        result.layers[i].content = .raster(output.pixels)
      case .fill(let p): result.layers[i].content = .fill(try convertColor(p, transform, depth: document.depth))
      case .text(var text): text.color = try convertColor(text.color, transform, depth: document.depth); result.layers[i].content = .text(text)
      case .gradientFill(let fill):
        result.layers[i].content = .gradientFill(try convertGradient(fill, transform, depth: document.depth,
          identity: sourceProfile == request.profile))
      case .shape(var shape):
        let originalDefinition = shape.definition
        shape.color = try convertColor(shape.color, transform, depth: document.depth)
        if var definition = shape.definition {
          definition.fill = try convertPaint(definition.fill, transform, depth: document.depth,
            identity: sourceProfile == request.profile)
          definition.stroke.paint = try convertPaint(definition.stroke.paint, transform, depth: document.depth,
            identity: sourceProfile == request.profile)
          shape.definition = definition
          if var appearance = shape.importedAppearance,
            sourceProfile != request.profile || definition != originalDefinition {
            // Raw source paint records are provenance, not a converted definition.
            // Preserve the original bytes/profile outside the active appearance cache.
            if let record = appearance.vectorRecord {
              let bytes = try JSONSerialization.data(withJSONObject:
                ["version": 1, "profileBase64": sourceProfile.base64EncodedString(),
                 "recordBase64": record.base64EncodedString()], options: [.sortedKeys])
              var tags = result.layers[i].sourceTags ?? [:]
              guard tags["PtVP"] == nil || tags["PtVP"] == bytes else {
                throw CraftError.unsupported("Existing vector profile provenance cannot be replaced. Keep a copy or flatten before conversion.")
              }
              tags["PtVP"] = bytes; result.layers[i].sourceTags = tags
              appearance.vectorRecord = nil
            }
            if appearance.definition == originalDefinition {
              appearance.definition = definition
              if let pixels = appearance.pixels {
                appearance.pixels = try rasterConversion.apply(pixels, native: nil).pixels
              }
              shape.importedAppearance = appearance.pixels == nil ? nil : appearance
            } else {
              // A stale cache must not become current accidentally after conversion.
              shape.importedAppearance = nil
            }
          }
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
  private static func convertGradient(_ original: GradientFill, _ transform: ProofTransform,
    depth: PixelDepth, identity: Bool) throws -> GradientFill {
    if identity { return original }
    var result = original
    for i in result.gradient.colors.indices {
      try Task.checkCancellation()
      let color = original.gradient.colors[i].color.resolved(foreground: .black, background: .white)
      let converted = try convertColor(color, transform, depth: depth)
      guard converted.isFinite else { throw CraftError.invalid("Invalid converted gradient color.") }
      // GradientDefinition represents bounded SDR stops, including in RGB/32 documents.
      // Clip to that storage domain explicitly; raster RGB/32 keeps extended samples.
      // This also handles native CMM white values above one without an epsilon rule.
      result.gradient.colors[i].color = .rgb(Pixel(unit(converted.r), unit(converted.g), unit(converted.b)))
    }
    try result.validate(); return result
  }
  private static func convertPaint(_ original: ShapePaint, _ transform: ProofTransform,
    depth: PixelDepth, identity: Bool) throws -> ShapePaint {
    guard original.kind != .pattern else { throw CraftError.unsupported("Flatten pattern-painted shapes before converting profiles.") }
    var result = original
    result.color = try convertColor(original.color, transform, depth: depth)
    if let gradient = original.gradient {
      result.gradient = try convertGradient(gradient, transform, depth: depth, identity: identity)
    }
    return result
  }
  private static func convertColor(_ pixel: Pixel, _ transform: ProofTransform, depth: PixelDepth) throws -> Pixel {
    let p = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    let values = try transform.apply([p.r, p.g, p.b])
    let output = Pixel(values[0], values[1], values[2], p.a)
    return depth == .f32 ? SRGBTransfer.encoded(output) : output
  }
}
