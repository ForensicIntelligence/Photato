import Foundation

public struct DocumentModeDescriptor: Codable, Equatable, Sendable {
  public var mode: DocumentColorMode
  public var profile: Data
  public var intent: ModeRenderingIntent
  public init(mode: DocumentColorMode, depth: PixelDepth, profile: Data? = nil,
    intent: ModeRenderingIntent = .relativeColorimetric) throws {
    self.mode = mode; self.profile = try profile ?? NativeModeProfile.standard(mode, depth: depth)
    self.intent = intent
    try NativeModeProfile.validate(self.profile, mode: mode, depth: depth)
  }
}

public struct DocumentModeConversion: Codable, Equatable, Sendable {
  public var mode: DocumentColorMode
  public var depth: PixelDepth
  public var profile: Data?
  public var intent: ModeRenderingIntent
  public init(mode: DocumentColorMode, depth: PixelDepth, profile: Data? = nil,
    intent: ModeRenderingIntent = .relativeColorimetric) {
    self.mode = mode; self.depth = depth; self.profile = profile; self.intent = intent
  }
}

public struct ModeChannelEdit: Sendable {
  public var layerID: UUID
  public var component: Int
  public var pixels: Surface
  public init(layerID: UUID, component: Int, pixels: Surface) {
    self.layerID = layerID; self.component = component; self.pixels = pixels
  }
}

/// A prepared compositor conversion remains one atomic, source-checked history edit.
public struct DocumentModeEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public let title: String
  public let recording: ActionOperation?
  public init(source: CraftDocument, result: CraftDocument, title: String = "Convert Color Mode", recording: ActionOperation? = nil) {
    self.source = source; self.result = result; self.title = title; self.recording = recording
  }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard document == source, result.id == source.id, result.hasAuthoritativeModeStorage else {
      throw CraftError.invalid("The document changed during color conversion.")
    }
    try result.validate(); return result
  }
}

extension CraftDocument {
  public var colorMode: DocumentColorMode { isChannelOnly ? .multichannel:(inkMode?.mode ?? restrictedMode?.mode ?? modeDescriptor?.mode ?? .rgb) }
  public var hasNativeModeStorage: Bool { modeDescriptor != nil }

  /// The retained planes define document colors. Existing RGB algorithms operate
  /// on an sRGB cache; mode-specific compositing remains a separate parity gate.
  public func convertingMode(_ request: DocumentModeConversion) throws -> CraftDocument {
    try validate(); try Task.checkCancellation()
    guard !isChannelOnly else{throw CraftError.unsupported("Load this mask into an image document before changing its color mode.")}
    if inkMode != nil { return try convertingInkMode(request) }
    let descriptor = try DocumentModeDescriptor(mode: request.mode, depth: request.depth,
      profile: request.profile, intent: request.intent)
    if modeDescriptor == descriptor, depth == request.depth { return self }
    var result = self; result.restrictedMode = nil
    for i in layers.indices {
      let source = layers[i]
      switch source.content {
      case .raster(let pixels):
        let native: NativeModeRaster
        if let retained = source.nativeMode {
          native = try retained.converted(to: request.mode, depth: request.depth,
            profile: descriptor.profile, intent: request.intent)
        } else {
          native = try NativeModeRaster.converting(pixels, to: request.mode, depth: request.depth,
            profile: descriptor.profile, intent: request.intent, sourceProfile: workingICC)
        }
        result.layers[i].nativeMode = native
        result.layers[i].content = .raster(try native.surface())
      case .group: break
      default:
        throw CraftError.unsupported("Merge or rasterize type, shape, fill and adjustment layers before this mode conversion.")
      }
      if let mask = source.mask { result.layers[i].mask = try mask.converted(to: request.depth) }
      if let mask = source.smartFilters?.mask { result.layers[i].smartFilters?.mask = try mask.converted(to: request.depth) }
    }
    if var channels = alphaChannels {
      for i in channels.indices { channels[i] = try channels[i].convertedCoverage(to:request.depth) }
      result.alphaChannels = channels
    }
    if let channel = quickMask { result.quickMask = try channel.convertedCoverage(to:request.depth) }
    result.depth = request.depth; result.modeDescriptor = descriptor
    // The existing rendering/editing cache is always in standard RGB coordinates.
    // Source profile provenance is retained independently.
    result.workingICC = nil
    try result.validate(); return result
  }

  public func modeChannel(layerID: UUID, component: Int) throws -> Surface {
    guard let native = layers.first(where: { $0.id == layerID })?.nativeMode else {
      throw CraftError.invalid("Choose a pixel layer with native color components.")
    }
    return try native.channel(component)
  }

  mutating func editModeChannel(_ edit: ModeChannelEdit) throws {
    guard let i = layers.firstIndex(where: { $0.id == edit.layerID }),
      !isImageLocked(edit.layerID), layers[i].smartObject == nil,
      let native = layers[i].nativeMode else {
      throw CraftError.invalid("Choose an unlocked raster layer before editing a color component.")
    }
    let changed = try native.replacingChannel(edit.component, with: edit.pixels)
    layers[i].nativeMode = changed; layers[i].content = .raster(try changed.surface())
  }

  /// Reconcile ordinary tool mutations without reseparating untouched CMYK ink.
  /// Geometry operations set transformed native planes before reaching this hook.
  mutating func reconcileModeStorage(from old: CraftDocument) throws {
    if inkMode != nil { try reconcileInkModeStorage(from: old); return }
    if restrictedMode != nil { try reconcileRestrictedModeStorage(from: old); return }
    guard let descriptor = modeDescriptor else {
      for i in layers.indices { layers[i].nativeMode = nil }; return
    }
    for i in layers.indices {
      guard case .raster(let edited) = layers[i].content else { layers[i].nativeMode = nil; continue }
      let prior = old.layers.first(where: { $0.id == layers[i].id })
      if let retained = layers[i].nativeMode, retained != prior?.nativeMode,
        retained.mode == descriptor.mode, retained.depth == depth,
        retained.profile == descriptor.profile, retained.width == edited.width, retained.height == edited.height {
        // A native component/geometry operation already supplied authoritative samples.
        layers[i].content = .raster(try retained.surface()); continue
      }
      let native: NativeModeRaster
      if let prior, case .raster(let before) = prior.content, let retained = prior.nativeMode,
        old.modeDescriptor == descriptor, old.depth == depth,
        before.width == edited.width, before.height == edited.height {
        if before == edited { layers[i].nativeMode = retained; continue }
        native = try retained.reconciled(with: edited, previous: before)
      } else {
        native = try NativeModeRaster.converting(edited, to: descriptor.mode, depth: depth,
          profile: descriptor.profile, intent: descriptor.intent)
      }
      layers[i].nativeMode = native; layers[i].content = .raster(try native.surface())
    }
  }

  func validateModeStorage() throws {
    if isChannelOnly {try validateChannelOnly();return}
    if inkMode != nil { try validateInkModeStorage(); return }
    if restrictedMode != nil { try validateRestrictedModeStorage(); return }
    guard let descriptor = modeDescriptor else {
      guard layers.allSatisfy({ $0.nativeMode == nil }) else { throw CraftError.invalid("Native components require document mode metadata.") }
      return
    }
    try NativeModeProfile.validate(descriptor.profile, mode: descriptor.mode, depth: depth)
    guard workingICC == nil else { throw CraftError.invalid("Mode display caches use standard RGB coordinates.") }
    for layer in layers {
      guard case .raster(let pixels) = layer.content else {
        guard layer.nativeMode == nil else { throw CraftError.invalid("Only raster layers own mode samples.") }; continue
      }
      guard let native = layer.nativeMode, native.mode == descriptor.mode, native.depth == depth,
        native.profile == descriptor.profile, native.intent == descriptor.intent,
        native.width == pixels.width, native.height == pixels.height, pixels.depth == depth else {
        throw CraftError.invalid("Native mode samples and layer cache layout differ.")
      }
      try native.validate()
    }
  }

  /// Ignore serialized display caches after validating their allocation/layout.
  /// Native component bytes remain authoritative across native file recovery.
  mutating func restoreModeCaches() throws {
    try validateModeStorage()
    if let inkMode {
      if case .duotone(let raster) = inkMode { layers[0].content = .raster(try raster.gray.surface()) }; return
    }
    if let restrictedMode { layers[0].content = .raster(try restrictedMode.surface()); return }
    guard modeDescriptor != nil else { return }
    for i in layers.indices { if let native = layers[i].nativeMode { layers[i].content = .raster(try native.surface()) } }
  }
}
