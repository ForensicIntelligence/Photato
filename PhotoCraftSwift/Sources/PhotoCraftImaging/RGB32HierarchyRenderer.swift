import PhotoCraftCore

/// Normal raster groups retain straight linear samples throughout evaluation.
/// Non-Normal/rich/affine layers and independent clipping blending use the
/// general renderer until their independently measured arithmetic is qualified.
enum RGB32HierarchyRenderer {
  private struct Node {
    let layer: Layer
    let pixels: Surface?
    let mask: LayerMaskSampler?
    var children: [Node]
    var clips: [Node] = []
    let opaque: Bool
    var copiesSource: Bool
    let rasterAlpha: Float?
  }

  static func composite(_ document: CraftDocument, region: IntRect, facts: CompositionFacts? = nil,
    emptySample: Pixel = .clear) throws -> Surface?
  {
    guard !document.hasArtboards && !document.hasFrames, !document.layers.contains(where: { $0.style != nil && $0.style?.isChannelBlendingOnly != true }), document.depth == .f32,
      var nodes = try nodes(document.children(of: nil), document: document, region: region,facts:facts)
    else { return nil }
    var result = try Renderer.emptyCanvas(document, fill: emptySample)
    let opaque = nodes.first?.opaque ?? false
    _ = prepareCopyRules(&nodes, over: 0, seeded: false, opaque: opaque)
    for y in region.y..<region.y + region.height {
      try Task.checkCancellation()
      for x in region.x..<region.x + region.width {
        let pixel = try stack(nodes, over: emptySample, seeded: false, opaque: opaque, x: x, y: y,
          emptySample: emptySample)
        guard pixel.isFinite else {
          throw CraftError.invalid("Group composition exceeds the floating-point range.")
        }
        result.setLinearPixel(x: x, y: y, pixel)
      }
    }
    return result
  }

  private static func nodes(
    _ layers: [Layer], document: CraftDocument, region: IntRect, facts:CompositionFacts?
  ) throws -> [Node]? {
    var result: [Node] = []
    var index = 0
    while index < layers.count {
      let layer = layers[index]
      index += 1
      if layer.isClipped { continue }
      let firstClip = index
      while index < layers.count && layers[index].isClipped { index += 1 }
      guard layer.visible && layer.opacity > 0 && layer.style?.restrictedChannels?.count != 3 else { continue }
      guard var built = try node(layer, document: document, region: region,facts:facts) else { return nil }
      if built.pixels == nil && built.children.isEmpty { continue }
      let clips = layers[firstClip..<index].filter { $0.visible && $0.opacity > 0 }
      if !clips.isEmpty {
        // Clipping a group, or blending clipped layers independently, has a
        // different Photoshop calculation from an ordinary raster chain.
        guard !layer.isGroup && layer.clipsBlendAsGroup else { return nil }
        for clip in clips {
          guard !clip.isGroup,
            let child = try node(clip, document: document, region: region,facts:facts)
          else { return nil }
          built.clips.append(child)
        }
      }
      result.append(built)
    }
    return result
  }

  private static func node(
    _ layer: Layer, document: CraftDocument, region: IntRect,facts:CompositionFacts?
  ) throws -> Node? {
    guard layer.affine == nil && layer.blendMode == .normal else { return nil }
    let mask = try facts.map {try $0.mask(layer,region:region)} ?? LayerMaskSampler.make(layer: layer, document: document, pixelRegion: region)
    let pixels: Surface?
    let children: [Node]
    let opaque: Bool
    let copiesSource: Bool
    let rasterAlpha: Float?
    if layer.isGroup {
      guard
        let built = try nodes(
          document.children(of: layer.id), document: document, region: region,facts:facts)
      else { return nil }
      pixels = nil
      children = built
      var covered = layer.opacity == 1 && built.first?.opaque == true
      if let facts {covered=try facts.opaqueGroup(layer,firstChildOpaque:built.first?.opaque ?? false)}
      else if covered,
        let fullMask = try LayerMaskSampler.make(layer: layer, document: document)
      {
        scan: for y in 0..<document.height {
          try Task.checkCancellation()
          for x in 0..<document.width {
            if fullMask.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) != 1 {
              covered = false
              break scan
            }
          }
        }
      }
      opaque = covered
      copiesSource = false
      rasterAlpha = nil
    } else if case .raster(let surface) = layer.content {
      pixels = surface
      children = []
      opaque = try facts.map {try $0.opaqueBase(layer)} ?? RGB32NormalRenderer.hasOpaqueBase(layer, document: document)
      copiesSource = opaque && mask == nil
        && RGB32NormalRenderer.canCopyOpaqueRaster(layer, source: surface, in: document)
      if opaque {
        rasterAlpha = 1
      } else if mask == nil {
        rasterAlpha = try RGB32NormalRenderer.uniformAlpha(layer, source: surface, in: document, facts: facts)
      } else {
        rasterAlpha = nil
      }
    } else {
      return nil
    }
    return Node(layer: layer, pixels: pixels, mask: mask, children: children, opaque: opaque,
      copiesSource: copiesSource, rasterAlpha: rasterAlpha)
  }

  // Decide once per stack, using whole-canvas coverage even for regional output.
  private static func prepareCopyRules(_ nodes: inout [Node], over backdrop: Float?,
    seeded: Bool, opaque: Bool) -> Float? {
    var alpha = backdrop
    var seeded = seeded
    for i in nodes.indices {
      let opacity = RGB32NormalRenderer.expandedOpacity(nodes[i].layer.opacity, opaque: opaque)
      if let group = nodes[i].layer.group {
        let after: Float?
        if group.passThrough {
          after = prepareCopyRules(&nodes[i].children, over: alpha, seeded: seeded, opaque: opaque)
        } else {
          let childOpaque = nodes[i].children.first?.opaque ?? false
          let isolated = prepareCopyRules(&nodes[i].children, over: 0, seeded: false, opaque: childOpaque)
          after = RGB32NormalRenderer.compositeUniformAlpha(backdrop: alpha, source: isolated,
            seeded: seeded, opaque: opaque && seeded, copiesSource: false)
        }
        if nodes[i].mask != nil {
          alpha = nil
        } else if opacity == 1 {
          alpha = after
        } else if let before = alpha, let after {
          alpha = unit(RGB32NormalRenderer.multiplyAdd(before, 1 - opacity, to: after * opacity))
        } else {
          alpha = nil
        }
      } else {
        // Clips retain the base's alpha. Their copy eligibility is local to the clip.
        nodes[i].copiesSource = nodes[i].copiesSource && alpha != nil
        alpha = RGB32NormalRenderer.compositeUniformAlpha(backdrop: alpha,
          source: nodes[i].rasterAlpha.map { unit($0 * opacity) }, seeded: seeded,
          opaque: opaque, copiesSource: nodes[i].copiesSource)
      }
      seeded = true
    }
    return alpha
  }

  private static func sample(_ node: Node, x: Int, y: Int, emptySample: Pixel = .clear) -> Pixel {
    guard let surface = node.pixels else { return .clear }
    let localX = x - node.layer.x, localY = y - node.layer.y
    guard localX >= 0, localY >= 0, localX < surface.width, localY < surface.height else { return emptySample }
    var value = surface.linearPixel(x: localX, y: localY)
    value.a *= node.mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
    return value
  }

  private static func stack(
    _ nodes: [Node], over backdrop: Pixel, seeded: Bool, opaque: Bool, x: Int, y: Int,
    emptySample: Pixel
  ) throws -> Pixel {
    var output = backdrop
    var seeded = seeded
    for node in nodes {
      let before = output
      if let group = node.layer.group {
        let after: Pixel
        if group.passThrough {
          after = try stack(
            node.children, over: output, seeded: seeded, opaque: opaque, x: x, y: y,
            emptySample: emptySample)
        } else {
          let isolated = try stack(
            node.children, over: emptySample, seeded: false,
            opaque: node.children.first?.opaque ?? false, x: x, y: y, emptySample: emptySample)
          after =
            seeded ? try RGB32NormalRenderer.blend(output, isolated, opaque: opaque) : isolated
        }
        let amount = unit(
          RGB32NormalRenderer.expandedOpacity(node.layer.opacity, opaque: opaque)
            * (node.mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1))
        output = try mix(before, after, amount: amount, opaque: opaque)
      } else {
        var source = sample(node, x: x, y: y, emptySample: seeded ? .clear : emptySample)
        if source.a > 0 {
          for clip in node.clips {
            var clipped = sample(clip, x: x, y: y)
            clipped.a = unit(clipped.a * clip.layer.opacity)
            let alpha = source.a
            let prior = source
            let blended = try RGB32NormalRenderer.blend(source, clipped, opaque: true,
              copiesSource: clip.copiesSource)
            source = BlendChannelRestrictions.applying(clip.layer.style?.restrictedChannels,
              after: blended, before: prior)
            source.a = alpha
          }
        }
        source.a = unit(
          source.a * RGB32NormalRenderer.expandedOpacity(node.layer.opacity, opaque: opaque))
        output = seeded ? try RGB32NormalRenderer.blend(output, source, opaque: opaque,
          copiesSource: node.copiesSource) : source
      }
      output=BlendChannelRestrictions.applying(node.layer.style?.restrictedChannels,after:output,before:before)
      seeded = true
    }
    return output
  }

  private static func mix(_ before: Pixel, _ after: Pixel, amount: Float, opaque: Bool) throws
    -> Pixel
  {
    if amount == 0 { return before }
    if amount == 1 { return after }
    let remainder = 1 - amount
    let weightedAlpha = after.a * amount
    let alpha = RGB32NormalRenderer.multiplyAdd(before.a, remainder, to: weightedAlpha)
    guard alpha > 0 else { return .clear }
    let ratio = unit(weightedAlpha / alpha)
    func channel(_ b: Float, _ a: Float) -> Float {
      opaque ? RGB32NormalRenderer.multiplyAdd(a, amount, to: b * remainder)
        : RGB32NormalRenderer.multiplyAdd(a - b, ratio, to: b)
    }
    let result = Pixel(
      channel(before.r, after.r), channel(before.g, after.g), channel(before.b, after.b), alpha)
    guard result.isFinite else {
      throw CraftError.invalid("Group composition exceeds the floating-point range.")
    }
    return result
  }
}
