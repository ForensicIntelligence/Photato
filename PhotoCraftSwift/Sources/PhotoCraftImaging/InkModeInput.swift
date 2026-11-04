import Foundation
import PhotoCraftCore

/// Shared preparation for desktop previews, API commands and recorded workflows.
/// Native component samples are read directly when a single plain layer exists.
public enum InkModeInput {
  public static func needsMerge(_ document: CraftDocument) -> Bool {
    if document.inkMode != nil { return false }
    guard document.layers.count == 1, let layer = document.layers.first,
      case .raster(let pixels) = layer.content else { return true }
    return pixels.width != document.width || pixels.height != document.height
      || layer.x != 0 || layer.y != 0 || layer.affine != nil || layer.parentID != nil
      || !layer.visible || layer.opacity != 1 || layer.blendMode != .normal
      || layer.mask != nil || layer.vectorMask != nil || layer.style != nil
      || layer.smartObject != nil || layer.smartFilters != nil || layer.warp != nil || layer.clipped == true
  }
  private static func validate(_ document: CraftDocument, mergeVisible: Bool) throws {
    try document.validate(); try Task.checkCancellation()
    guard !document.hasArtboards, !document.hasFrames,
      document.width <= InkPlane.maximumPixels / document.height else {
      throw CraftError.unsupported("Ink conversion requires one canvas of at most8,388,608 pixels without artboards or frames.")
    }
    guard document.depth != .f32, !document.colorMode.isRestricted else {
      throw CraftError.unsupported("Convert Indexed Color, Bitmap or32-bit images to RGB/Grayscale8 or16-bit before ink conversion.")
    }
    if needsMerge(document), !mergeVisible {
      throw CraftError.unsupported("Enable Merge Visible Layers to flatten the visible artwork and discard hidden layers. Saved alpha channels are retained.")
    }
  }
  /// Obtain components in the document's own coordinates. Do not reseparate an
  /// opaque flat CMYK layer through an RGB preview and destroy its black plate.
  private static func components(_ document: CraftDocument) throws -> NativeModeRaster {
    if !needsMerge(document), let retained = document.layers.first?.nativeMode { return retained }
    let pixels = try Renderer.composite(document)
    var opaque = try Surface(width: document.width, height: document.height, depth: .f32, colorEncoding: .sRGB)
    for y in 0..<document.height { try Task.checkCancellation(); for x in 0..<document.width {
      let p = pixels.pixel(x: x, y: y), a = unit(p.a)
      opaque.setPixel(x: x, y: y, Pixel(p.r * a + 1 - a, p.g * a + 1 - a, p.b * a + 1 - a))
    } }
    return try NativeModeRaster.converting(opaque, to: document.colorMode, depth: document.depth,
      profile: document.modeDescriptor?.profile ?? document.workingICC,
      intent: document.modeDescriptor?.intent ?? .relativeColorimetric, sourceProfile: document.workingICC)
  }
  private static func plane(_ component: Int, in native: NativeModeRaster, inverted: Bool) throws -> InkPlane {
    let source = try InkPlane(width: native.width, height: native.height, depth: native.depth, bytes: native.planeBytes(component))
    if native.isOpaque {
      return try source.converted(to: native.depth, inverted: inverted)
    }
    let white = try NativeModeRaster.converting(Surface(width: 1, height: 1, depth: native.depth, fill: .white),
      to: native.mode, depth: native.depth, profile: native.profile, intent: native.intent)
    let paper = white.value(component: component, index: 0)
    var values = [Float](); values.reserveCapacity(source.count)
    for i in 0..<source.count {
      if i % 4096 == 0 { try Task.checkCancellation() }
      let alpha = native.value(component: native.mode.componentCount, index: i)
      let sample = unit(source.value(at: i) * alpha + paper * (1 - alpha))
      values.append(inverted ? 1 - sample : sample)
    }
    return try source.replacing(offset: 0, values: values)
  }
  public static func duotone(_ settings: DuotoneSettings, in document: CraftDocument,
    mergeVisible: Bool = false) throws -> Command {
    try validate(document, mergeVisible: mergeVisible); try settings.validate()
    let result: CraftDocument
    if case .duotone = document.inkMode { result = try document.replacingDuotoneSettings(settings) }
    else {
      guard document.colorMode == .grayscale, document.depth == .u8 else {
        throw CraftError.unsupported("Duotone requires an8-bit Grayscale image.")
      }
      let gray = try plane(0, in: components(document), inverted: false)
      result = try document.replacingInkMode(.duotone(.init(gray: gray, settings: settings)))
    }
    return .preparedDocumentMode(.init(source: document, result: result, title: document.colorMode == .duotone ? "Duotone Options" : "Duotone"))
  }
  public static func multichannel(in document: CraftDocument, mergeVisible: Bool = false) throws -> Command {
    try validate(document, mergeVisible: mergeVisible)
    let raster: MultichannelRaster
    switch document.inkMode {
    case .multichannel(let existing): raster = existing
    case .duotone(let source): raster = try source.separations()
    case nil:
      let native = try components(document)
      let definitions: [(String, Pixel)]
      // Display colors are from the licensed PhotoCraft process-ink definitions.
      let process: [(String, Pixel)] = [("Cyan", Pixel(0, 0.682, 0.937)),
        ("Magenta", Pixel(0.925, 0, 0.549)), ("Yellow", Pixel(1, 0.949, 0)), ("Black", Pixel(0.137, 0.122, 0.125))]
      switch native.mode {
      case .rgb: definitions = Array(process.prefix(3))
      case .cmyk: definitions = process
      case .lab: definitions = [("Alpha 1", .black), ("Alpha 2", .black), ("Alpha 3", .black)]
      case .grayscale: definitions = [("Black", .black)]
      default: throw CraftError.unsupported("This mode cannot be converted to Multichannel.")
      }
      let plates = try definitions.enumerated().map { index, item in
        InkPlate(name: item.0, color: item.1, samples: try plane(index, in: native, inverted: native.mode != .cmyk))
      }
      raster = try .init(plates: plates)
    }
    let result = try document.replacingInkMode(.multichannel(raster))
    return .preparedDocumentMode(.init(source: document, result: result, title: "Multichannel"))
  }
}

extension InkModeRequest {
  public func command(in document: CraftDocument) throws -> Command {
    try validate()
    let base: Command = kind == .duotone
      ? try InkModeInput.duotone(settings, in: document, mergeVisible: mergeVisible)
      : try InkModeInput.multichannel(in: document, mergeVisible: mergeVisible)
    guard case .preparedDocumentMode(let edit) = base else { throw CraftError.invalid("Missing prepared ink conversion.") }
    var result = edit.result
    if kind == .multichannel, case .multichannel(var raster) = result.inkMode {
      guard plateIDs.count == raster.plates.count else { throw CraftError.invalid("Plate identities do not match the resulting channels.") }
      // Existing ink identities survive conversion. A component document uses the
      // identities captured when this request was created, not new preview UUIDs.
      if document.inkMode == nil {
        for index in raster.plates.indices { raster.plates[index].id = plateIDs[index] }
        result.inkMode = .multichannel(raster)
      } else if raster.plates.map(\.id) != plateIDs {
        throw CraftError.invalid("Existing ink identities must be retained.")
      }
    }
    try result.validate()
    return .preparedDocumentMode(.init(source: document, result: result, title: title, recording: .inkMode(self)))
  }
}
