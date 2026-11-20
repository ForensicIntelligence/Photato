import Foundation
import PhotoCraftCore

public enum SpotChannelMerge {
  public static func unavailableReason(_ source: CraftDocument, channelID: UUID?) -> String? {
    guard source.colorMode == .rgb || source.colorMode == .cmyk, !source.layers.isEmpty else {
      return "Merge Spot Channel requires an RGB or CMYK image."
    }
    guard source.animation == nil, source.videoTimeline == nil, !source.hasArtboards, !source.hasFrames else {
      return "Merge a still image with one canvas."
    }
    guard source.quickMask == nil else { return "Exit Quick Mask before merging a spot channel." }
    guard let channelID, source.alphaChannels?.contains(where: { $0.id == channelID && $0.spot != nil }) == true else {
      return "Choose a saved spot channel."
    }
    return nil
  }

  public static func command(_ source: CraftDocument, channelID: UUID, discardHiddenLayers: Bool = false) throws -> Command {
    try Task.checkCancellation()
    try source.validate()
    if let reason = unavailableReason(source, channelID: channelID) { throw CraftError.unsupported(reason) }
    guard discardHiddenLayers || FlattenImageEdit.hiddenLayerIDs(in: source).isEmpty else {
      throw CraftError.invalid("Discarding hidden layers requires confirmation.")
    }
    let channel = try source.channel(.alpha(channelID))
    guard let ink = channel.spot else { throw CraftError.invalid("Select a spot ink.") }
    let native: NativeModeRaster?, pixels: Surface
    if source.colorMode == .cmyk {
      let merged = try mergeCMYK(source, channel: channel, ink: ink)
      native = merged
      pixels = try merged.surface()
    } else {
      let merged = try mergeRGB(source, channel: channel, ink: ink)
      native = merged.native
      pixels = merged.pixels
    }

    var result = source
    var layer = Layer(name: "Background", content: .raster(pixels))
    layer.id = source.layers.first(where: \.isBackground)?.id ?? source.activeLayerID ?? source.id
    layer.nativeMode = native
    layer.background = true
    layer.sourceTags = ["lyid": Data(repeating: 0, count: 4)]
    result.layers = [layer]
    result.activeLayerID = layer.id
    result.artboardOrigin = nil
    result.alphaChannels?.removeAll { $0.id == channelID }
    if result.alphaChannels?.isEmpty == true { result.alphaChannels = nil }
    try result.validate()
    try Task.checkCancellation()
    return .mergeSpotChannel(.init(source: source, result: result, channelID: channelID))
  }

  private static func mergeRGB(_ source: CraftDocument, channel: AlphaChannel, ink: SpotInk) throws
    -> (native: NativeModeRaster?, pixels: Surface) {
    let descriptor = source.modeDescriptor
    let working = descriptor?.profile ?? source.workingICC
    let base: Surface
    if let descriptor {
      let merged = try DocumentModeInput.mergedSource(source)
      if let retained = merged.layers.first?.nativeMode {
        base = try retained.retainedRGBSurface()
      } else if case .raster(let composite) = merged.layers.first?.content {
        let converted = try NativeModeRaster.converting(composite, to: .rgb, depth: source.depth,
          profile: descriptor.profile, intent: descriptor.intent, sourceProfile: merged.workingICC, pagedOutput: true)
        base = try converted.retainedRGBSurface()
      } else {
        throw CraftError.invalid("The RGB composite is missing.")
      }
    } else {
      base = try Renderer.compositePaged(source)
    }

    // Spot colors are retained in sRGB coordinates. Convert the single ink
    // color into the destination profile once, never the existing RGB pixels.
    let swatch = try Surface(width: 1, height: 1, depth: .f32, fill: ink.color)
    let inkComponents = try NativeModeRaster.converting(swatch, to: .rgb, depth: source.depth,
      profile: working).components(index: 0)
    let workingInk = SpotInk(color: Pixel(inkComponents[0], inkComponents[1], inkComponents[2]), solidity: ink.solidity)
    let opaque = try BackgroundLayer.opaque(base, over: .white)
    let density = try channel.pixels.interpretingSamples(as: opaque.colorEncoding)
    let baked = try opaque.combiningStoredSamples(with: density) { backdrop, sample in
      sample.r == 0 ? backdrop : workingInk.preview(density: sample.r, over: backdrop)
    }.quantizedStoredDepth(source.depth)
    guard let descriptor else { return (nil, baked) }
    let retained = try NativeModeRaster.converting(baked, to: .rgb, depth: source.depth, profile: descriptor.profile,
      intent: descriptor.intent, sourceProfile: descriptor.profile, pagedOutput: true)
    return (retained, try retained.surface())
  }

  private static func mergeCMYK(_ source: CraftDocument, channel: AlphaChannel, ink: SpotInk) throws -> NativeModeRaster {
    guard let descriptor = source.modeDescriptor else { throw CraftError.invalid("The CMYK profile is missing.") }
    let processInk: [Float]
    if let retained = try PSDInkChannels.retainedCMYKSwatch(channel) {
      processInk = retained
    } else {
      let swatch = try Surface(width: 1, height: 1, depth: .f32, fill: ink.color)
      processInk = try NativeModeRaster.converting(swatch, to: .cmyk, depth: source.depth,
        profile: descriptor.profile, intent: descriptor.intent).components(index: 0)
    }
    let visible = source.layers.filter { $0.visible && $0.opacity > 0 }
    let retained = visible.count == 1 && visible.first.map { InkModeInput.isAlignedRaster($0, in: source) } == true
      ? visible.first?.nativeMode : nil
    var result = try retained ?? NativeModeRaster(width: source.width, height: source.height, mode: .cmyk,
      depth: source.depth, profile: descriptor.profile, intent: descriptor.intent)
    let alpha = try retained.flatMap { $0.isOpaque ? nil : try $0.opacityChannel() }
    for component in 0..<DocumentColorMode.cmyk.componentCount {
      let baseline: Surface
      if let retained {
        if let alpha {
          baseline = try retained.channel(component).combiningStoredSamples(with: alpha) { p, a in
            let value = p.r * a.r
            return Pixel(value, value, value)
          }
        } else {
          baseline = try retained.channel(component)
        }
      } else {
        let preview = try ModeChannelPresentation.singleComponent(source, component: component)
        let paper = try BackgroundLayer.opaque(preview, over: .white)
        baseline = try paper.mappedStoredSamples { pixel in
          let density = 1 - pixel.r
          return Pixel(density, density, density)
        }
      }
      let tint = processInk[component]
      let baked = try baseline.combiningStoredSamples(with: channel.pixels) { backdrop, sample in
        let density = unit(sample.r)
        if density == 0 { return backdrop }
        // Process density is the complement of reflected light. Overprint in
        // that space, then interpolate toward opaque ink using solidity.
        let cover = density * ink.solidity
        let overprint = backdrop.r + (1 - backdrop.r) * density * tint
        let value = overprint * (1 - cover) + tint * cover
        return Pixel(value, value, value)
      }.quantizedStoredDepth(source.depth)
      result = try result.replacingChannel(component, with: baked)
    }
    if !result.isOpaque {
      result = try result.replacingOpacity(with: Surface(width: source.width, height: source.height, depth: source.depth, fill: .white))
    }
    return result
  }
}
