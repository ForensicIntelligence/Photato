import Foundation
import PhotoCraftCore

/// Shared desktop/API preparation. Destructive flattening is explicit and every
/// prepared result retains its source snapshot for atomic stale-request rejection.
public enum RestrictedModeInput {
  public static func needsMerge(_ document: CraftDocument) -> Bool {
    guard document.layers.count == 1, let layer = document.layers.first,
      case .raster(let pixels) = layer.content else { return true }
    return pixels.width != document.width || pixels.height != document.height
      || layer.x != 0 || layer.y != 0 || layer.affine != nil || layer.parentID != nil
      || !layer.visible || layer.opacity != 1 || layer.blendMode != .normal
      || layer.mask != nil || layer.vectorMask != nil || layer.style != nil
      || layer.smartObject != nil || layer.smartFilters != nil || layer.warp != nil
      || layer.clipped == true || !(document.alphaChannels ?? []).isEmpty || document.quickMask != nil
  }
  private static func validate(_ document: CraftDocument, mergeVisible: Bool) throws {
    try document.validate(); try Task.checkCancellation()
    guard !document.layers.isEmpty, !document.hasArtboards, !document.hasFrames,
      document.width <= PaletteQuantization.maximumPixels / document.height else {
      throw CraftError.unsupported("Restricted color modes require one canvas of at most 8,388,608 pixels without artboards or frames.")
    }
    if needsMerge(document), !mergeVisible {
      throw CraftError.unsupported("Enable Merge Visible Layers to flatten this stack and discard hidden layers and auxiliary channels before conversion.")
    }
  }
  private static func rgb8(_ document: CraftDocument) throws -> Surface {
    guard [.rgb, .grayscale].contains(document.colorMode), document.depth == .u8 else {
      throw CraftError.unsupported("Convert to RGB or Grayscale 8-bit before Indexed Color.")
    }
    return try Renderer.composite(document).converted(to: .u8)
  }
  public static func indexed(_ settings: IndexedColorSettings, in document: CraftDocument,
    mergeVisible: Bool = false, masterDocuments: [CraftDocument] = [], previousPalette: [PaletteColor]? = nil) throws -> Command {
    try validate(document, mergeVisible: mergeVisible); try settings.validate()
    // RGB mode caches use standard RGB; ordinary RGB documents can retain an
    // embedded working profile. Master images must share those coordinates.
    let profile = document.workingICC, pixels = try rgb8(document)
    var sources = [Surface](), total = document.width * document.height
    for master in masterDocuments {
      try master.validate()
      guard master.width <= (PaletteQuantization.maximumPixels - total) / master.height else {
        throw CraftError.unsupported("Master palette sources exceed the combined pixel limit.")
      }
      total += master.width * master.height
      let input = try rgb8(master)
      if master.workingICC == profile { sources.append(input) }
      else {
        let target = try NativeModeRaster.converting(input, to: .rgb, depth: .u8,
          profile: profile, sourceProfile: master.workingICC)
        // NativeModeRaster.surface() is a standard-RGB cache. Read the actual
        // converted working components so the target profile is not applied twice.
        var converted = try Surface(width: input.width, height: input.height)
        for y in 0..<input.height { try Task.checkCancellation(); for x in 0..<input.width {
          let c = target.components(index: y * input.width + x)
          converted.setPixel(x: x, y: y, Pixel(c[0], c[1], c[2], c[3]))
        } }; sources.append(converted)
      }
    }
    let raster = try IndexedRaster.converting(pixels, settings: settings, profile: profile,
      masterSources: sources, previousPalette: previousPalette)
    let result = try document.replacingRestrictedMode(.indexed(raster))
    var request = RestrictedModeRequest(.indexed); request.indexed = settings; request.mergeVisible = mergeVisible; request.previousPalette = settings.palette == .previous ? previousPalette : nil
    return .preparedDocumentMode(.init(source: document, result: result, title: "Indexed Color", recording: .restrictedMode(request)))
  }
  public static func bitmap(_ settings: BitmapConversionSettings, in document: CraftDocument,
    mergeVisible: Bool = false) throws -> Command {
    try validate(document, mergeVisible: mergeVisible); try settings.validate()
    guard document.colorMode == .grayscale, document.depth == .u8 else {
      throw CraftError.unsupported("Convert to Grayscale 8-bit before Bitmap.")
    }
    let ratio = settings.outputResolution / document.pixelsPerInch
    let width = (Double(document.width) * ratio).rounded(), height = (Double(document.height) * ratio).rounded()
    guard width >= 1, height >= 1, width <= Double(Surface.maxDimension), height <= Double(Surface.maxDimension),
      width * height <= Double(PaletteQuantization.maximumPixels) else {
      throw CraftError.unsupported("The output resolution would exceed the supported Bitmap dimensions or pixel limit.")
    }
    var input = document
    if needsMerge(document) {
      let request = DocumentModeRequest(.init(mode: .grayscale, depth: .u8, profile: document.modeDescriptor?.profile), mergeVisible: true)
      try DocumentModeInput.command(request, in: document).apply(to: &input)
    }
    if input.width != Int(width) || input.height != Int(height) {
      // Native gray samples, paths and selection share one resolution transform.
      // Adobe's exact mode-conversion resampler remains a separate parity check.
      try Command.imageSize(Int(width), Int(height), settings.outputResolution, .bilinear).apply(to: &input)
    } else { input.resolution = settings.outputResolution }
    guard let native = input.layers.first?.nativeMode, native.mode == .grayscale,
      native.width == input.width, native.height == input.height else {
      throw CraftError.invalid("Prepare one native grayscale plane before Bitmap conversion.")
    }
    var gray = [Float](); gray.reserveCapacity(input.width * input.height)
    for i in 0..<input.width * input.height {
      if i % 4096 == 0 { try Task.checkCancellation() }
      let alpha = native.value(component: 1, index: i)
      gray.append(unit(native.value(component: 0, index: i) * alpha + 1 - alpha))
    }
    let raster = try BitmapRaster.converting(gray, width: input.width, settings: settings)
    let result = try input.replacingRestrictedMode(.bitmap(raster))
    var request = RestrictedModeRequest(.bitmap); request.bitmap = settings; request.mergeVisible = mergeVisible
    return .preparedDocumentMode(.init(source: document, result: result, title: "Bitmap", recording: .restrictedMode(request)))
  }
  public static func colorTable(_ colors: [PaletteColor], transparentIndex: Int?, in document: CraftDocument) throws -> Command {
    let result = try document.replacingColorTable(colors, transparentIndex: transparentIndex)
    var request = RestrictedModeRequest(.colorTable); request.colors = colors; request.transparentIndex = transparentIndex
    return .preparedDocumentMode(.init(source: document, result: result, title: "Color Table", recording: .restrictedMode(request)))
  }
}
