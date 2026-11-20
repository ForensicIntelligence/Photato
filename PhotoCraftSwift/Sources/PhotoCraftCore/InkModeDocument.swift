import Foundation

extension CraftDocument {
  public var multichannelChannelOrder: [UUID] {
    guard case .multichannel(let raster) = inkMode else { return [] }
    return raster.channelOrder ?? (raster.plates.map(\.id) + (alphaChannels ?? []).map(\.id))
  }

  public var hasInterleavedMultichannelChannels: Bool {
    if case .multichannel(let raster) = inkMode { return raster.channelOrder != nil }
    return false
  }

  public mutating func setMultichannelChannelOrder(_ order: [UUID]) throws {
    guard case .multichannel(var raster) = inkMode else { throw CraftError.invalid("Channel order requires Multichannel mode.") }
    let alpha = alphaChannels ?? []
    let available = raster.plates.map(\.id) + alpha.map(\.id)
    guard available.count == order.count, Set(available) == Set(order), Set(order).count == order.count else {
      throw CraftError.invalid("The order must include every saved channel and printing plate exactly once.")
    }
    let plates = Dictionary(uniqueKeysWithValues: raster.plates.map { ($0.id, $0) })
    let selections = Dictionary(uniqueKeysWithValues: alpha.map { ($0.id, $0) })
    raster.plates = order.compactMap { plates[$0] }
    let orderedAlpha = order.compactMap { selections[$0] }
    raster.channelOrder = order == raster.plates.map(\.id) + orderedAlpha.map(\.id) ? nil : order
    inkMode = .multichannel(raster)
    if !orderedAlpha.isEmpty { alphaChannels = orderedAlpha }
  }

  mutating func moveMultichannelChannel(_ id: UUID, to destination: Int) throws {
    var order = multichannelChannelOrder
    guard let source = order.firstIndex(of: id), order.indices.contains(destination) else {
      throw CraftError.invalid("Choose a printing plate or saved channel and a valid destination.")
    }
    guard source != destination else { return }
    order.remove(at: source)
    order.insert(id, at: destination)
    try setMultichannelChannelOrder(order)
  }

  /// The older group-relative commands keep the positions occupied by that group.
  /// New rows append, and a removed row releases its own position.
  mutating func reconcileMultichannelChannelOrder() throws {
    guard case .multichannel(let raster) = inkMode, let previous = raster.channelOrder else { return }
    let plates = raster.plates.map(\.id), alpha = (alphaChannels ?? []).map(\.id)
    let plateIDs = Set(plates), alphaIDs = Set(alpha), previousIDs = Set(previous)
    var retainedPlates = plates.filter(previousIDs.contains).makeIterator()
    var retainedAlpha = alpha.filter(previousIDs.contains).makeIterator()
    var resolved = previous.compactMap { id -> UUID? in
      if plateIDs.contains(id) { return retainedPlates.next() }
      if alphaIDs.contains(id) { return retainedAlpha.next() }
      return nil
    }
    resolved.append(contentsOf: plates.filter { !previousIDs.contains($0) })
    resolved.append(contentsOf: alpha.filter { !previousIDs.contains($0) })
    try setMultichannelChannelOrder(resolved)
  }

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
      if let order = raster.channelOrder {
        let plates = raster.plates.map(\.id), alpha = (alphaChannels ?? []).map(\.id)
        let plateIDs = Set(plates), alphaIDs = Set(alpha)
        guard order.count == plates.count + alpha.count,
          order.filter(plateIDs.contains) == plates, order.filter(alphaIDs.contains) == alpha,
          order != plates + alpha else { throw CraftError.invalid("Invalid order of Multichannel ink and saved channels.") }
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
      for i in channels.indices { channels[i] = try channels[i].convertedCoverage(to:outputDepth) }
      alphaChannels = channels
    }
    if let channel = quickMask { quickMask = try channel.convertedCoverage(to:outputDepth) }
  }

  private func returningCMYKPlates(_ raster: MultichannelRaster) -> ArraySlice<InkPlate>? {
    let expected = InkPlate.processSwatches
    guard raster.plates.count > expected.count else { return nil }
    let process = raster.plates.prefix(expected.count)
    // Names and the encoded 16-bit swatches survive the normal PSD/PSB writer.
    // A custom ink set needs an explicit component mapping.
    guard zip(process, expected).allSatisfy({ pair in
      let (plate, swatch) = pair
      return plate.name == swatch.name && plate.solidity == 0
        && plate.color.quantized(.u16) == swatch.color.quantized(.u16)
    }) else { return nil }
    return process
  }

  private func returningSpotChannels(_ plates: ArraySlice<InkPlate>) throws -> [AlphaChannel] {
    var channels = Dictionary(uniqueKeysWithValues: (alphaChannels ?? []).map { ($0.id, $0) })
    for plate in plates {
      var spot = AlphaChannel(id: plate.id, name: plate.name, pixels: try plate.samples.surface(),
        spot: SpotInk(color: plate.color, solidity: plate.solidity))
      if let record = sourceMetadata?[InkPlate.psdDisplayKey(plate.id)], record.count == 13 {
        spot.psdDisplay = record
      }
      if let id = sourceMetadata?[InkPlate.psdIdentifierKey(plate.id)], id.count == 4 {
        spot.psdIdentifier = id.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      }
      channels[spot.id] = spot
    }
    return multichannelChannelOrder.compactMap { channels[$0] }
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
    var direct: NativeModeRaster?
    var outputChannels = alphaChannels
    switch inkMode {
    case .duotone(let raster) where request.mode == .grayscale:
      var gray = try NativeModeRaster(width: width, height: height, mode: .grayscale,
        depth: .u8, intent: request.intent)
      for i in 0..<width * height {
        if i % 4096 == 0 { try Task.checkCancellation() }
        try gray.set(raster.gray.value(at: i), component: 0, index: i)
        try gray.set(1, component: 1, index: i)
      }
      direct = try gray.converted(to: request.mode, depth: request.depth,
        profile: descriptor.profile, intent: request.intent)
    case .multichannel(let raster):
      var process = raster
      if request.mode == .cmyk, let plates = returningCMYKPlates(raster) {
        process = try MultichannelRaster(plates: Array(plates))
        outputChannels = try returningSpotChannels(raster.plates.dropFirst(plates.count))
      }
      if process.plates.count == request.mode.componentCount {
        let components = try NativeModeRaster.interpretingPrintingPlates(process, as: request.mode,
          profile: request.depth == .f32 ? nil : request.profile, intent: request.intent)
        direct = try components.converted(to: request.mode, depth: request.depth,
          profile: descriptor.profile, intent: request.intent, pagedOutput: inkMode.requiresPagedArchive)
      }
    default: break
    }
    let native = try direct ?? NativeModeRaster.converting(inkMode.surface(), to: request.mode,
      depth: request.depth, profile: descriptor.profile, intent: request.intent, pagedOutput: inkMode.requiresPagedArchive)
    var result = self
    var layer = Layer(name: "Background", content: .raster(try native.surface()))
    layer.id = activeLayerID ?? id; layer.nativeMode = native
    result.layers = [layer]; result.activeLayerID = layer.id
    result.inkMode = nil; result.restrictedMode = nil; result.workingICC = nil
    result.modeDescriptor = descriptor; result.depth = request.depth
    result.alphaChannels = outputChannels
    try result.convertAuxiliaryChannelDepth(to: request.depth)
    try result.validate(); return result
  }
}
