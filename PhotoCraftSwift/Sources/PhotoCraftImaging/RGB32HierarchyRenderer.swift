import PhotoCraftCore

/// Normal raster groups retain straight linear samples throughout evaluation.
/// Non-Normal/rich/affine layers and independent clipping blending use the
/// general renderer until their independently measured arithmetic is qualified.
enum RGB32HierarchyRenderer {
  private struct Node {
    let layer: Layer
    let pixels: Surface?
    let mask: LayerMaskSampler?
    let children: [Node]
    var clips: [Node] = []
    let opaque: Bool
  }

  static func composite(_ document: CraftDocument, region: IntRect) throws -> Surface? {
    guard !document.hasArtboards && !document.hasFrames, !document.layers.contains(where: { $0.style != nil }), document.depth == .f32,
      let nodes = try nodes(document.children(of: nil), document: document, region: region)
    else { return nil }
    var result = try Renderer.emptyCanvas(document)
    let opaque = nodes.first?.opaque ?? false
    for y in region.y..<region.y + region.height {
      try Task.checkCancellation()
      for x in region.x..<region.x + region.width {
        let pixel = try stack(nodes, over: .clear, seeded: false, opaque: opaque, x: x, y: y)
        guard pixel.isFinite else {
          throw CraftError.invalid("Group composition exceeds the floating-point range.")
        }
        result.setLinearPixel(x: x, y: y, pixel)
      }
    }
    return result
  }

  private static func nodes(
    _ layers: [Layer], document: CraftDocument, region: IntRect
  ) throws -> [Node]? {
    var result: [Node] = []
    var index = 0
    while index < layers.count {
      let layer = layers[index]
      index += 1
      if layer.isClipped { continue }
      let firstClip = index
      while index < layers.count && layers[index].isClipped { index += 1 }
      guard layer.visible && layer.opacity > 0 else { continue }
      guard var built = try node(layer, document: document, region: region) else { return nil }
      if built.pixels == nil && built.children.isEmpty { continue }
      let clips = layers[firstClip..<index].filter { $0.visible && $0.opacity > 0 }
      if !clips.isEmpty {
        // Clipping a group, or blending clipped layers independently, has a
        // different Photoshop calculation from an ordinary raster chain.
        guard !layer.isGroup && layer.clipsBlendAsGroup else { return nil }
        for clip in clips {
          guard !clip.isGroup,
            let child = try node(clip, document: document, region: region)
          else { return nil }
          built.clips.append(child)
        }
      }
      result.append(built)
    }
    return result
  }

  private static func node(
    _ layer: Layer, document: CraftDocument, region: IntRect
  ) throws -> Node? {
    guard layer.affine == nil && layer.blendMode == .normal else { return nil }
    let mask = try LayerMaskSampler.make(layer: layer, document: document, pixelRegion: region)
    let pixels: Surface?
    let children: [Node]
    let opaque: Bool
    if layer.isGroup {
      guard
        let built = try nodes(
          document.children(of: layer.id), document: document, region: region)
      else { return nil }
      pixels = nil
      children = built
      var covered = layer.opacity == 1 && built.first?.opaque == true
      if covered,
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
    } else if case .raster(let surface) = layer.content {
      pixels = surface
      children = []
      opaque = try RGB32NormalRenderer.hasOpaqueBase(layer, document: document)
    } else {
      return nil
    }
    return Node(layer: layer, pixels: pixels, mask: mask, children: children, opaque: opaque)
  }

  private static func sample(_ node: Node, x: Int, y: Int) -> Pixel {
    guard let surface = node.pixels else { return .clear }
    var value = surface.linearPixel(x: x - node.layer.x, y: y - node.layer.y)
    value.a *= node.mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
    return value
  }

  private static func stack(
    _ nodes: [Node], over backdrop: Pixel, seeded: Bool, opaque: Bool, x: Int, y: Int
  ) throws -> Pixel {
    var output = backdrop
    var seeded = seeded
    for node in nodes {
      let before = output
      if let group = node.layer.group {
        let after: Pixel
        if group.passThrough {
          after = try stack(
            node.children, over: output, seeded: seeded, opaque: opaque, x: x, y: y)
        } else {
          let isolated = try stack(
            node.children, over: .clear, seeded: false,
            opaque: node.children.first?.opaque ?? false, x: x, y: y)
          after =
            seeded ? try RGB32NormalRenderer.blend(output, isolated, opaque: opaque) : isolated
        }
        let amount = unit(
          RGB32NormalRenderer.expandedOpacity(node.layer.opacity, opaque: opaque)
            * (node.mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1))
        output = try mix(before, after, amount: amount, opaque: opaque)
      } else {
        var source = sample(node, x: x, y: y)
        if source.a > 0 {
          for clip in node.clips {
            var clipped = sample(clip, x: x, y: y)
            clipped.a = unit(clipped.a * clip.layer.opacity)
            let alpha = source.a
            source = try RGB32NormalRenderer.blend(source, clipped, opaque: true)
            source.a = alpha
          }
        }
        source.a = unit(
          source.a * RGB32NormalRenderer.expandedOpacity(node.layer.opacity, opaque: opaque))
        output = seeded ? try RGB32NormalRenderer.blend(output, source, opaque: opaque) : source
      }
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
    let alpha = weightedAlpha.addingProduct(before.a, remainder)
    guard alpha > 0 else { return .clear }
    let ratio = unit(weightedAlpha / alpha)
    func channel(_ b: Float, _ a: Float) -> Float {
      opaque ? (b * remainder).addingProduct(a, amount) : b.addingProduct(a - b, ratio)
    }
    let result = Pixel(
      channel(before.r, after.r), channel(before.g, after.g), channel(before.b, after.b), alpha)
    guard result.isFinite else {
      throw CraftError.invalid("Group composition exceeds the floating-point range.")
    }
    return result
  }
}
