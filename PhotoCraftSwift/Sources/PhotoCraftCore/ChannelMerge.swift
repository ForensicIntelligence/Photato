import Foundation

public struct PreparedChannelMerge: Sendable {
  public let sources: [CraftDocument]
  public let document: CraftDocument
}

public enum ChannelMergeMode: String, CaseIterable, Sendable {
  case rgb, cmyk, lab, multichannel
  public var title: String { switch self { case .rgb: "RGB Color"; case .cmyk: "CMYK Color"; case .lab: "Lab Color"; case .multichannel: "Multichannel" } }
  public var components: [String] { switch self { case .rgb: ["Red", "Green", "Blue"]; case .cmyk: ["Cyan", "Magenta", "Yellow", "Black"]; case .lab: ["Lightness", "a", "b"]; case .multichannel: [] } }
  public var colorMode: DocumentColorMode { switch self { case .rgb: .rgb; case .cmyk: .cmyk; case .lab: .lab; case .multichannel: .multichannel } }
  public func canChoose(sourceCount: Int, depth: PixelDepth) -> Bool {
    sourceCount >= (self == .multichannel ? 2 : components.count)
      && accepts(count:self == .multichannel ? min(56,sourceCount) : components.count,depth:depth)
  }
  public func accepts(count: Int, depth: PixelDepth) -> Bool {
    (depth != .f32 || self == .rgb) && (self == .multichannel ? (2...56).contains(count) : count == components.count)
  }
}

public enum ChannelMerge {
  public static func unavailableReason(_ document: CraftDocument) -> String? {
    guard document.colorMode == .grayscale, document.inkMode == nil, !document.isChannelOnly,
      document.quickMask == nil, !document.hasAuxiliaryChannels,
      !document.hasArtboards, !document.hasFrames, document.animation == nil, document.videoTimeline == nil,
      document.layers.count == 1, let layer = document.layers.first,
      case .raster(let pixels) = layer.content, layer.visible, layer.opacity == 1, layer.blendMode == .normal,
      layer.x == 0, layer.y == 0, layer.affine == nil, layer.parentID == nil, layer.clipped != true,
      layer.mask == nil, layer.vectorMask == nil, layer.style == nil, layer.smartObject == nil,
      layer.smartFilters == nil, layer.warp == nil, layer.sourceProjection == nil,
      pixels.width == document.width, pixels.height == document.height else {
      return "Merge Channels requires flat grayscale documents with one image channel."
    }
    do {
      if let native = layer.nativeMode { if !native.isOpaque { return "Flatten transparency before merging channels." } }
      else if try !pixels.isOpaque() { return "Flatten transparency before merging channels." }
    } catch { return error.localizedDescription }
    return nil
  }
  public static func matches(_ source: CraftDocument, anchor: CraftDocument) -> Bool {
    source.width == anchor.width && source.height == anchor.height && source.depth == anchor.depth && unavailableReason(source) == nil
  }
  /// Native Gray samples define destination components, without an ICC conversion.
  public static func prepare(_ sources: [CraftDocument], mode: ChannelMergeMode,
    profile: Data? = nil, name: String = "Untitled") throws -> PreparedChannelMerge {
    try Task.checkCancellation()
    guard let first = sources.first, mode.accepts(count: sources.count, depth: first.depth),
      Set(sources.map(\.id)).count == sources.count else { throw CraftError.invalid("Choose a different grayscale document for each output channel, with the required channel count.") }
    var planes = [Surface]()
    for source in sources {
      try Task.checkCancellation(); try source.validate()
      guard matches(source, anchor: first) else { throw CraftError.invalid("Source dimensions, depth or flattened grayscale content disagree.") }
      let native = try ModeComponentEdit.raster(source.layers[0], in: source)
      let plane = try native.channel(0)
      // Photoshop's complete 65,536-word reference grid uses a 15-bit working grid.
      let canonical = first.depth == .u16 ? try plane.mappedStoredSamples { p in
        let word = Int((unit(p.r) * 65535).rounded()), q = (word * 32768 + 32767) / 65535
        let value = Float((q * 65535 + 16384) / 32768) / 65535
        return Pixel(value, value, value)
      }.retaggedCoverageStorage(depth: .u16) : plane
      planes.append(canonical)
    }
    var result = try CraftDocument(width: first.width, height: first.height, depth: first.depth, name: name)
    result.resolution = first.resolution; result.profileIsUntagged = true
    if mode == .multichannel {
      result.layers = []; result.activeLayerID = nil; result.channelOnly = true
      result.alphaChannels = planes.enumerated().map { AlphaChannel(name: "Alpha \($0.offset + 1)", pixels: $0.element) }
    } else {
      let profile = try profile ?? NativeModeProfile.standard(mode.colorMode, depth: first.depth)
      try NativeModeProfile.validate(profile, mode: mode.colorMode, depth: first.depth)
      if mode == .rgb {
        let rg = try planes[0].combiningStoredSamples(with: planes[1]) { Pixel($0.r, $1.r, 0) }
        let rgb = try rg.combiningStoredSamples(with: planes[2]) { Pixel($0.r, $0.g, $1.r) }
          .retaggedCoverageStorage(depth: first.depth, encoding: first.depth == .f32 ? .linearRGB : .sRGB)
        result.workingICC = profile; result.layers[0].content = .raster(rgb)
      } else {
        var raster = try NativeModeRaster(width: first.width, height: first.height, mode: mode.colorMode, depth: first.depth, profile: profile)
        for (index, plane) in planes.enumerated() {
          let value: Surface
          if mode == .cmyk {
            let maximum: Float = first.depth == .u8 ? 255 : 65535
            value = try plane.mappedStoredSamples { p in
              let v = (maximum - (unit(p.r) * maximum).rounded()) / maximum
              return Pixel(v, v, v)
            }.retaggedCoverageStorage(depth: first.depth)
          } else { value = plane }
          raster = try raster.replacingChannel(index, with: value)
        }
        raster = try raster.replacingOpacity(with: Surface(width: first.width, height: first.height, depth: first.depth, fill: .white))
        result.modeDescriptor = try .init(mode: mode.colorMode, depth: first.depth, profile: profile)
        result.layers[0].nativeMode = raster; result.layers[0].content = .raster(try raster.surface())
      }
      result.layers[0].background = true
    }
    try Task.checkCancellation(); try result.validate()
    return .init(sources: sources, document: result)
  }
}
