import Foundation
import PhotoCraftCore

final class GroupRenderCache {
  let inputTarget: UUID?
  let region: IntRect?
  let video: VideoTransitionRenderContext?
  let disabledTransitions: Set<UUID>
  func suppressing(_ id:UUID)->GroupRenderCache {GroupRenderCache(inputTarget:inputTarget,region:region,video:video,disabledTransitions:disabledTransitions.union([id]))}
  func fullCanvas()->GroupRenderCache {GroupRenderCache(inputTarget:inputTarget,video:video,disabledTransitions:disabledTransitions)}
  func crossfade(from id:UUID)->VideoTransitionRenderContext.Active? {video?.active.first{$0.transition.kind == .crossFade && $0.transition.previousLayerID==id && !disabledTransitions.contains($0.transition.id)}}
  func fade(on id:UUID)->VideoTransitionRenderContext.Active? {video?.active.first{$0.transition.kind != .crossFade && $0.transition.layerID==id && !disabledTransitions.contains($0.transition.id)}}
  init(inputTarget: UUID? = nil, region: IntRect? = nil, video:VideoTransitionRenderContext?=nil, disabledTransitions:Set<UUID>=[]) {
    self.inputTarget = inputTarget
    self.region = region;self.video=video;self.disabledTransitions=disabledTransitions
  }
  func bounds(_ d: CraftDocument) -> IntRect {
    (region ?? IntRect(x: 0, y: 0, width: d.width, height: d.height))
      .clipped(toWidth: d.width, height: d.height)
  }
  var rawGroups: [UUID: Surface] = [:]
  var bytes = 0
  func insert(_ surface: Surface, for id: UUID) throws {
    guard rawGroups[id] == nil else { return }
    guard bytes + surface.allocatedBytes <= 512 * 1024 * 1024 else {
      throw CraftError.unsupported(
        "Group composition exceeds the current 512 MiB temporary cache budget.")
    }
    rawGroups[id] = surface
    bytes += surface.allocatedBytes
  }
}

extension Renderer {
  public static func clippingCoverage(_ layer: Layer, in document: CraftDocument) throws -> Surface
  {
    try isolatedContent(layer, in: document, cache: GroupRenderCache())
  }
  static func compositeStack(
    _ layers: [Layer], in d: CraftDocument, over backdrop: Surface,
    cache: GroupRenderCache = GroupRenderCache()
  ) throws -> Surface {
    let region = cache.bounds(d)
    var output = backdrop
    var index = 0
    while index < layers.count {
      try Task.checkCancellation()
      let base = layers[index]
      index += 1
      // Orphan clipping layers have no coverage source.
      if base.isClipped { continue }
      let start = index
      while index < layers.count && layers[index].isClipped { index += 1 }
      if let pair=cache.crossfade(from:base.id),index<layers.count,layers[index].id==pair.transition.layerID {
        let outgoing=Array(layers[(start-1)..<index]);let incomingStart=index;index+=1
        while index<layers.count && layers[index].isClipped{index+=1}
        let incoming=Array(layers[incomingStart..<index]),branch=cache.suppressing(pair.transition.id)
        let first=try compositeStack(outgoing,in:d,over:output,cache:branch)
        let last=try compositeStack(incoming,in:d,over:output,cache:cache.suppressing(pair.transition.id))
        output=try mixTransition(first,last,progress:pair.progress,in:d,region:region)
        continue
      }
      guard base.visible && base.opacity > 0 else { continue }
      let transitionBackdrop=output
      if base.id == cache.inputTarget { throw AdjustmentInputReached(surface: output) }
      let clips = Array(layers[start..<index].filter { $0.visible && $0.opacity > 0 })
      if base.style != nil {
        output = try LayerStyleRenderer.composite(base, clips: clips, in: d, over: output, region: region, cache:cache.fullCanvas())
      } else if let group = base.group, group.passThrough, group.artboard == nil, group.frame == nil {
        let before = output
        output = try compositeStack(d.children(of: base.id), in: d, over: output, cache: cache)
        if !clips.isEmpty {
          let coverage = try rawGroupContent(base, in: d, cache: cache)
          var extracted = output
          try extracted.mapPixels(in: region) { x, y, p in
            let alpha = coverage.pixel(x: x, y: y).a
            guard alpha > 0 else { return .clear }
            let after = working(p, d)
            let prior = working(before.pixel(x: x, y: y), d)
            let passColor = (after.rgb * after.a - prior.rgb * prior.a * (1 - alpha)) / alpha
            let isolated = working(coverage.pixel(x: x, y: y), d)
            // Photoshop's clipped Pass Through folders attenuate the backdrop's
            // blending contribution at fractional coverage. The denominator is
            // the union of two equal coverage values divided by that coverage.
            // Pinned by two independent Photoshop-saved 16-case alpha matrices.
            let color = isolated.rgb + (passColor - isolated.rgb) / (2 - alpha)
            return encoded(Pixel(color.x, color.y, color.z, alpha), d)
          }
          let clipped = try compositeClips(clips, onto: extracted, in: d, cache: cache)
          var normal = base
          normal.opacity = 1
          normal.blendMode = .normal
          output = try blendCanvas(clipped, over: before, layer: normal, in: d, region: region)
        }
        output = try mixGroup(before: before, after: output, layer: base, in: d, region: region)
      } else if case .adjustment = base.content {
        var full = base
        full.opacity = 1
        full.mask = nil
        full.maskProperties = nil
        full.vectorMask = nil
        var adjusted = try compositeFlat(
          [full], in: d, over: output, inputTarget: cache.inputTarget, region: cache.region)
        adjusted = try compositeClips(clips, onto: adjusted, in: d, cache: cache)
        output = try mixGroup(before: output, after: adjusted, layer: base, in: d, region: region)
      } else if clips.isEmpty && !base.isGroup {
        output = try compositeFlat(
          [base], in: d, over: output, inputTarget: cache.inputTarget, region: cache.region)
      } else {
        let source = try isolatedContent(base, in: d, cache: cache)
        if base.clipsBlendAsGroup {
          let clipped = try compositeClips(clips, onto: source, in: d, cache: cache)
          output = try blendCanvas(clipped, over: output, layer: base, in: d, region: region)
        } else {
          var preblended = source
          try preblended.mapPixels(in: region) { x, y, p in
            var opaque = p
            opaque.a = 1
            var blended = compositePixel(
              base.blendMode, backdrop: output.pixel(x: x, y: y), source: opaque,
              opacity: 1, depth: d.depth, x: x, y: y)
            blended.a = p.a
            return blended
          }
          let clipped = try compositeClips(clips, onto: preblended, in: d, cache: cache)
          var normal = base
          normal.blendMode = .normal
          output = try blendCanvas(clipped, over: output, layer: normal, in: d, region: region)
        }
      }
      if let fade=cache.fade(on:base.id) {output=try fadeTransition(fade,layer:base,clips:clips,before:transitionBackdrop,after:output,in:d,cache:cache)}
    }
    return output
  }

  static func rawGroupContent(_ layer: Layer, in d: CraftDocument, cache: GroupRenderCache) throws
    -> Surface
  {
    if let pixels = cache.rawGroups[layer.id] { return pixels }
    let pixels: Surface
    if layer.frame != nil {
      let children = try compositeStack(d.children(of: layer.id), in: d, over: emptyCanvas(d), cache: cache)
      pixels = try FrameRenderer.render(children, frame: layer, document: d, region: cache.bounds(d))
    } else if let board = layer.artboard, let bounds = layer.artboardBounds {
      let requested = cache.bounds(d)
      let x = max(requested.x, bounds.x), y = max(requested.y, bounds.y)
      let region = IntRect(x: x, y: y, width: max(0, min(requested.x + requested.width, bounds.x + bounds.width) - x), height: max(0, min(requested.y + requested.height, bounds.y + bounds.height) - y))
      var backdrop = try emptyCanvas(d)
      if board.background.a > 0, region.width > 0, region.height > 0 {
        try backdrop.mapPixels(in: region) { _, _, _ in board.background }
      }
      pixels = try compositeStack(d.children(of: layer.id), in: d, over: backdrop,
        cache: GroupRenderCache(inputTarget: cache.inputTarget, region: region))
    } else {
      pixels = try compositeStack(d.children(of: layer.id), in: d, over: emptyCanvas(d), cache: cache)
    }
    try cache.insert(pixels, for: layer.id)
    return pixels
  }
  static func isolatedContent(_ layer: Layer, in d: CraftDocument, cache: GroupRenderCache) throws
    -> Surface
  {
    if layer.isGroup {
      var result = try rawGroupContent(layer, in: d, cache: cache)
      let sampler = try LayerMaskSampler.make(layer: layer, document: d)
      if let sampler {
        try result.mapPixels(in: cache.bounds(d)) { x, y, p in
          var p = p
          p.a *= sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5)
          return p
        }
      }
      return result
    }
    var source = layer
    source.opacity = 1
    source.blendMode = .normal
    return try compositeFlat(
      [source], in: d, over: emptyCanvas(d), inputTarget: cache.inputTarget, region: cache.region)
  }
  static func compositeClips(
    _ clips: [Layer], onto base: Surface, in d: CraftDocument, cache: GroupRenderCache
  ) throws -> Surface {
    let region = cache.bounds(d)
    var result = base
    for clip in clips {
      try Task.checkCancellation()
      if case .adjustment = clip.content {
        result = try compositeFlat(
          [clip], in: d, over: result, inputTarget: cache.inputTarget, region: cache.region)
        continue
      }
      let source = try isolatedContent(clip, in: d, cache: cache)
      for y in region.y..<region.y + region.height {
        try Task.checkCancellation()
        for x in region.x..<region.x + region.width {
          if d.depth == .f32 {
            var b = result.linearPixel(x: x, y: y)
            let alpha = b.a
            guard alpha > 0 else { continue }
            b.a = 1
            var p = compositeLinearPixel(
              clip.blendMode, backdrop: b,
              source: source.linearPixel(x: x, y: y), opacity: clip.opacity, x: x, y: y)
            p.a = alpha
            result.setLinearPixel(x: x, y: y, p)
            continue
          }
          var b = result.pixel(x: x, y: y)
          let alpha = b.a
          guard alpha > 0 else { continue }
          b.a = 1
          var p = compositePixel(
            clip.blendMode, backdrop: b, source: source.pixel(x: x, y: y),
            opacity: clip.opacity, depth: d.depth, x: x, y: y)
          p.a = alpha
          result.setPixel(x: x, y: y, p)
        }
      }
    }
    return result
  }
  static func blendCanvas(
    _ source: Surface, over backdrop: Surface, layer: Layer, in d: CraftDocument, region: IntRect
  ) throws -> Surface {
    var result = backdrop
    for y in region.y..<region.y + region.height {
      try Task.checkCancellation()
      for x in region.x..<region.x + region.width {
        if d.depth == .f32 {
          let p = source.linearPixel(x: x, y: y)
          guard p.a > 0 else { continue }
          result.setLinearPixel(
            x: x, y: y,
            compositeLinearPixel(
              layer.blendMode, backdrop: backdrop.linearPixel(x: x, y: y),
              source: p, opacity: layer.opacity, x: x, y: y))
          continue
        }
        let p = source.pixel(x: x, y: y)
        guard p.a > 0 else { continue }
        result.setPixel(
          x: x, y: y,
          compositePixel(
            layer.blendMode, backdrop: backdrop.pixel(x: x, y: y),
            source: p, opacity: layer.opacity, depth: d.depth, x: x, y: y))
      }
    }
    return result
  }
  static func working(_ p: Pixel, _ d: CraftDocument) -> Pixel {
    d.depth == .f32 ? SRGBTransfer.linear(p) : p
  }
  static func encoded(_ p: Pixel, _ d: CraftDocument) -> Pixel {
    d.depth == .f32 ? SRGBTransfer.encoded(p) : p
  }
  static func mixed(_ a: Pixel, _ b: Pixel, amount: Float, in d: CraftDocument) -> Pixel {
    let a = working(a, d)
    let b = working(b, d)
    let alpha = a.a * (1 - amount) + b.a * amount
    guard alpha > 0 else { return .clear }
    let rgb = (a.rgb * a.a * (1 - amount) + b.rgb * b.a * amount) / alpha
    return encoded(Pixel(rgb.x, rgb.y, rgb.z, alpha), d)
  }
  static func mixGroup(
    before: Surface, after: Surface, layer: Layer, in d: CraftDocument, region: IntRect
  ) throws
    -> Surface
  {
    let mask = try LayerMaskSampler.make(layer: layer, document: d)
    if layer.opacity == 1 && mask == nil { return after }
    var result = before
    for y in region.y..<region.y + region.height {
      try Task.checkCancellation()
      for x in region.x..<region.x + region.width {
        let amount = layer.opacity * (mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1)
        if d.depth == .f32 {
          let a = before.linearPixel(x: x, y: y)
          let b = after.linearPixel(x: x, y: y)
          if amount == 0 { continue }
          if amount == 1 {
            result.setLinearPixel(x: x, y: y, b)
            continue
          }
          let alpha = a.a * (1 - amount) + b.a * amount
          if alpha <= 0 {
            result.setLinearPixel(x: x, y: y, .clear)
            continue
          }
          let rgb = (a.rgb * a.a * (1 - amount) + b.rgb * b.a * amount) / alpha
          result.setLinearPixel(x: x, y: y, Pixel(rgb.x, rgb.y, rgb.z, alpha))
          continue
        }
        result.setPixel(
          x: x, y: y,
          mixed(before.pixel(x: x, y: y), after.pixel(x: x, y: y), amount: amount, in: d))
      }
    }
    return result
  }
}
