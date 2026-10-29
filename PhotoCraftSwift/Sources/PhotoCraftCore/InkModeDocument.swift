import Foundation

extension CraftDocument {
  /// A Duotone has one editable gray plane. Multichannel has independent printing
  /// plates and no layers; ordinary alpha masks remain separate auxiliary channels.
  public var colorChannelNames: [String] {
    if case .multichannel(let raster) = inkMode { return raster.plates.map(\.name) }
    return colorMode.componentNames
  }

  /// The imaging adapter performs compositing and obtains merge consent first.
  /// This method installs already-prepared authoritative ink data atomically.
  public func replacingInkMode(_ raster: InkModeRaster) throws -> Self {
    try validate(); try raster.validate(); try Task.checkCancellation()
    guard raster.width == width, raster.height == height, !hasArtboards, !hasFrames else {
      throw CraftError.invalid("Prepare a single canvas with matching dimensions before ink-mode conversion.")
    }
    var result = self
    result.inkMode = raster; result.restrictedMode = nil; result.modeDescriptor = nil
    result.workingICC = nil; result.depth = raster.depth
    switch raster {
    case .duotone(let duotone):
      var layer = Layer(name: "Duotone", content: .raster(try duotone.gray.surface()))
      layer.id = activeLayerID ?? id
      result.layers = [layer]; result.activeLayerID = layer.id
    case .multichannel:
      result.layers = []; result.activeLayerID = nil
    }
    try result.convertAuxiliaryChannelDepth(to: raster.depth)
    try result.validate(); return result
  }

  public func replacingDuotoneSettings(_ settings: DuotoneSettings) throws -> Self {
    try validate()
    guard case .duotone(let raster) = inkMode else { throw CraftError.invalid("Duotone Options requires a Duotone document.") }
    var result = self; result.inkMode = .duotone(try raster.replacing(settings: settings))
    try result.validate(); return result
  }

  /// Replaces numeric ink, not a rendered RGB approximation. Identity/order of all
  /// other plates and every auxiliary channel remain unchanged.
  public func replacingInkPlate(_ plate: InkPlate) throws -> Self {
    try validate(); try plate.validate()
    guard case .multichannel(var raster) = inkMode,
      let index = raster.plates.firstIndex(where: { $0.id == plate.id }) else {
      throw CraftError.invalid("Choose an existing Multichannel ink plate.")
    }
    raster.plates[index] = plate
    var result = self; result.inkMode = .multichannel(raster)
    try result.validate(); return result
  }

  func validateInkModeStorage() throws {
    guard let raster = inkMode else { return }
    try raster.validate()
    guard restrictedMode == nil, modeDescriptor == nil, workingICC == nil,
      depth == raster.depth, width == raster.width, height == raster.height,
      !hasArtboards, !hasFrames else {
      throw CraftError.invalid("Ink documents require matching dimensions, depth and exclusive ink storage.")
    }
    switch raster {
    case .duotone:
      guard layers.count == 1, let layer = layers.first,
        case .raster(let cache) = layer.content, cache.width == width, cache.height == height,
        cache.depth == .u8, cache.colorEncoding == .sRGB,
        layer.nativeMode == nil, layer.x == 0, layer.y == 0, layer.affine == nil,
        layer.visible, layer.opacity == 1, layer.blendMode == .normal,
        layer.mask == nil, layer.maskProperties == nil, layer.vectorMask == nil,
        layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil, layer.warp == nil,
        layer.parentID == nil, layer.clipped != true else {
        throw CraftError.invalid("Duotone requires one flat grayscale editing plane. Convert to RGB or Grayscale for layered editing.")
      }
    case .multichannel(let raster):
      let otherIDs = Set((alphaChannels ?? []).map(\.id) + (quickMask.map { [$0.id] } ?? []))
      guard layers.isEmpty, activeLayerID == nil,
        raster.plates.count + (alphaChannels?.count ?? 0) <= MultichannelRaster.maximumChannels,
        raster.plates.allSatisfy({ !otherIDs.contains($0.id) }) else {
        throw CraftError.invalid("Multichannel uses up to56 distinct ink/alpha channels and has no layers.")
      }
    }
  }

  mutating func reconcileInkModeStorage(from old: Self) throws {
    try validateInkModeStorage()
    guard case .duotone(var raster) = inkMode else { return }
    if inkMode != old.inkMode {
      layers[0].content = .raster(try raster.gray.surface()); return
    }
    guard old.layers.count == 1, case .raster(let previous) = old.layers[0].content,
      case .raster(let edited) = layers[0].content else { throw CraftError.invalid("Duotone requires its grayscale editing cache.") }
    if edited != previous {
      raster.gray = try raster.gray.reconciled(with: edited, previous: previous)
      inkMode = .duotone(raster); layers[0].content = .raster(try raster.gray.surface())
    }
  }

  mutating func convertAuxiliaryChannelDepth(to outputDepth: PixelDepth) throws {
    if var channels = alphaChannels {
      for i in channels.indices { channels[i].pixels = try channels[i].pixels.converted(to: outputDepth) }
      alphaChannels = channels
    }
    if var channel = quickMask { channel.pixels = try channel.pixels.converted(to: outputDepth); quickMask = channel }
  }

  /// PhotoCraft's matching-channel conversion interprets plate samples as target
  /// components. Otherwise conversion preserves the printed ink appearance.
  /// Duotone -> Gray recovers its original gray data, independent of ink colors.
  func convertingInkMode(_ request: DocumentModeConversion) throws -> Self {
    guard let inkMode, DocumentColorMode.componentModes.contains(request.mode) else {
      throw CraftError.invalid("Use ink-mode conversion settings for Duotone and Multichannel.")
    }
    let descriptor = try DocumentModeDescriptor(mode: request.mode, depth: request.depth,
      profile: request.profile, intent: request.intent)
    let native: NativeModeRaster
    switch inkMode {
    case .duotone(let raster) where request.mode == .grayscale:
      var gray = try NativeModeRaster(width: width, height: height, mode: .grayscale,
        depth: .u8, intent: request.intent)
      for i in 0..<width * height {
        if i % 4096 == 0 { try Task.checkCancellation() }
        try gray.set(raster.gray.value(at: i), component: 0, index: i)
        try gray.set(1, component: 1, index: i)
      }
      native = try gray.converted(to: request.mode, depth: request.depth,
        profile: descriptor.profile, intent: request.intent)
    case .multichannel(let raster) where raster.plates.count == request.mode.componentCount:
      // First interpret integer plates in the target's integer space, then
      // perform any requested profile/depth conversion (including linear32).
      let inputProfile = request.depth == .f32 ? nil : request.profile
      var components = try NativeModeRaster(width: width, height: height, mode: request.mode,
        depth: raster.depth, profile: inputProfile, intent: request.intent)
      for i in 0..<width * height {
        if i % 4096 == 0 { try Task.checkCancellation() }
        for c in raster.plates.indices {
          let v = raster.plates[c].samples.value(at: i)
          try components.set(request.mode == .cmyk ? v : 1 - v, component: c, index: i)
        }
        try components.set(1, component: request.mode.componentCount, index: i)
      }
      native = try components.converted(to: request.mode, depth: request.depth,
        profile: descriptor.profile, intent: request.intent)
    default:
      native = try NativeModeRaster.converting(inkMode.surface(), to: request.mode,
        depth: request.depth, profile: descriptor.profile, intent: request.intent)
    }
    var result = self
    var layer = Layer(name: "Background", content: .raster(try native.surface()))
    layer.id = activeLayerID ?? id; layer.nativeMode = native
    result.layers = [layer]; result.activeLayerID = layer.id
    result.inkMode = nil; result.restrictedMode = nil; result.workingICC = nil
    result.modeDescriptor = descriptor; result.depth = request.depth
    try result.convertAuxiliaryChannelDepth(to: request.depth)
    try result.validate(); return result
  }
}
