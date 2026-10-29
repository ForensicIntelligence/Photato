import Foundation

public enum RestrictedModeRaster: Codable, Equatable, Sendable {
  case indexed(IndexedRaster)
  case bitmap(BitmapRaster)
  public var mode: DocumentColorMode { switch self { case .indexed: .indexed; case .bitmap: .bitmap } }
  public var width: Int { switch self { case .indexed(let r): r.width; case .bitmap(let r): r.width } }
  public var height: Int { switch self { case .indexed(let r): r.height; case .bitmap(let r): r.height } }
  public var estimatedBytes: Int { switch self { case .indexed(let r): r.estimatedBytes; case .bitmap(let r): r.estimatedBytes } }
  public var profile: Data? { if case .indexed(let r) = self { r.profile } else { nil } }
  public func validate() throws { switch self { case .indexed(let r): try r.validate(); case .bitmap(let r): try r.validate() } }
  public func surface() throws -> Surface { switch self { case .indexed(let r): try r.surface(); case .bitmap(let r): try r.surface() } }
  func reconciled(with edited: Surface, previous: Surface) throws -> Self {
    switch self {
    case .indexed(let r): .indexed(try r.reconciled(with: edited, previous: previous))
    case .bitmap(let r): .bitmap(try r.reconciled(with: edited, previous: previous))
    }
  }
}

extension CraftDocument {
  public var bitsPerChannel: Int { colorMode == .bitmap ? 1 : depth == .u8 ? 8 : depth == .u16 ? 16 : 32 }
  public var hasAuthoritativeModeStorage: Bool { hasNativeModeStorage || restrictedMode != nil || inkMode != nil }

  /// Install a prepared flattened raster with stable document/layer identity.
  /// Compositing, destructive-merge consent and resolution resampling are performed
  /// by the imaging adapter before preparing this atomic history edit.
  public func replacingRestrictedMode(_ raster: RestrictedModeRaster) throws -> Self {
    try validate(); try raster.validate()
    guard raster.width == width, raster.height == height, !hasArtboards, !hasFrames else {
      throw CraftError.invalid("Prepare a single canvas with matching dimensions before restricted-mode conversion.")
    }
    var result = self
    var layer = Layer(name: raster.mode == .indexed ? "Index" : "Background", content: .raster(try raster.surface()))
    layer.id = activeLayerID ?? id
    result.layers = [layer]; result.activeLayerID = layer.id; result.depth = .u8
    result.modeDescriptor = nil; result.inkMode = nil; result.restrictedMode = raster; result.workingICC = raster.profile
    result.alphaChannels = nil; result.quickMask = nil
    try result.validate(); return result
  }
  public func replacingColorTable(_ colors: [PaletteColor], transparentIndex: Int?) throws -> Self {
    try validate()
    guard case .indexed(let indexed) = restrictedMode else { throw CraftError.invalid("Color Table requires an Indexed Color document.") }
    var result = self
    let raster = try indexed.replacingPalette(colors, transparentIndex: transparentIndex)
    result.restrictedMode = .indexed(raster); result.layers[0].content = .raster(try raster.surface())
    try result.validate(); return result
  }
  func validateRestrictedModeStorage() throws {
    guard let raster = restrictedMode else { return }
    try raster.validate()
    guard modeDescriptor == nil, inkMode == nil, depth == .u8, raster.width == width, raster.height == height,
      layers.count == 1, let layer = layers.first, case .raster(let cache) = layer.content,
      cache.width == width, cache.height == height, cache.depth == .u8,
      layer.nativeMode == nil, layer.x == 0, layer.y == 0, layer.affine == nil,
      layer.visible, layer.opacity == 1, layer.blendMode == .normal,
      layer.mask == nil, layer.maskProperties == nil, layer.vectorMask == nil,
      layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil, layer.warp == nil,
      layer.parentID == nil, layer.clipped != true,
      (alphaChannels ?? []).isEmpty, quickMask == nil, workingICC == raster.profile else {
      throw CraftError.invalid("Indexed Color and Bitmap require one flat raster, matching storage and no layer effects or auxiliary channels. Convert to RGB or Grayscale for layered editing.")
    }
  }
  mutating func reconcileRestrictedModeStorage(from old: Self) throws {
    guard let raster = restrictedMode else { return }
    try validateRestrictedModeStorage()
    if old.restrictedMode != raster {
      layers[0].content = .raster(try raster.surface()); return
    }
    guard old.layers.count == 1, case .raster(let previous) = old.layers[0].content,
      case .raster(let edited) = layers[0].content else { throw CraftError.invalid("Restricted-mode editing requires a flat raster.") }
    if edited != previous {
      let updated = try raster.reconciled(with: edited, previous: previous)
      restrictedMode = updated; layers[0].content = .raster(try updated.surface())
    }
  }
}
