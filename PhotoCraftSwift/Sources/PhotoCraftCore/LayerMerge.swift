import Foundation

public enum LayerMergeOperation: String, CaseIterable, Sendable {
  case down = "Merge Down"
  case selected = "Merge Layers"
  case visible = "Merge Visible"
}

/// Raster merge transactions. Rich layers, masks, clipping, groups and Background
/// need their own independently qualified semantics before entering this path.
public enum LayerMerge {
  private struct Plan {
    var layers: [Layer]
    var base: Layer
    var removed: Set<UUID>
    var bounds: IntRect
  }

  public static func canApply(
    _ operation: LayerMergeOperation, layerIDs: Set<UUID>, in document: CraftDocument
  ) -> Bool {
    (try? plan(operation, layerIDs: layerIDs, in: document)) != nil
  }

  private static func plan(
    _ operation: LayerMergeOperation, layerIDs: Set<UUID>, in d: CraftDocument
  ) throws -> Plan {
    guard !d.layers.contains(where: { $0.isGroup || $0.isClipped || $0.parentID != nil }) else {
      throw CraftError.unsupported("Merging grouped or clipped layers is not available yet.")
    }
    let members: [Layer]
    let base: Layer
    switch operation {
    case .down:
      guard layerIDs.count == 1, let id = layerIDs.first,
        let index = d.layers.firstIndex(where: { $0.id == id }), index > 0,
        d.layers[index].visible, d.layers[index - 1].visible
      else {
        throw CraftError.invalid("Select a visible layer immediately above another visible layer.")
      }
      members = Array(d.layers[(index - 1)...index])
      base = members[0]
    case .selected:
      members = d.layers.filter { layerIDs.contains($0.id) }
      guard members.count == layerIDs.count, members.count > 1,
        let top = members.last, top.visible
      else {
        throw CraftError.invalid("Select two or more layers with the top selected layer visible.")
      }
      base = top
    case .visible:
      members = d.layers.filter(\.visible)
      guard members.count > 1, let active = members.first(where: { $0.id == d.activeLayerID })
      else {
        throw CraftError.invalid(
          "Select a visible layer with at least two visible layers in the document.")
      }
      base = active
    }
    for layer in members {
      guard case .raster = layer.content, !layer.locked, layer.blendMode == .normal,
        layer.mask == nil, layer.vectorMask == nil, layer.affine == nil
      else {
        throw CraftError.unsupported(
          "This merge currently supports unlocked Normal pixel layers without masks or transforms.")
      }
    }
    let visible = members.filter(\.visible)
    var left = Int.max
    var top = Int.max
    var right = Int.min
    var bottom = Int.min
    for layer in visible {
      guard case .raster(let surface) = layer.content else { continue }
      left = min(left, layer.x)
      top = min(top, layer.y)
      right = max(right, layer.x + surface.width)
      bottom = max(bottom, layer.y + surface.height)
    }
    var bounds = IntRect(x: left, y: top, width: right - left, height: bottom - top)
    if operation == .visible { bounds = bounds.clipped(toWidth: d.width, height: d.height) }
    guard bounds.width > 0, bounds.height > 0,
      bounds.width <= Surface.maxDimension, bounds.height <= Surface.maxDimension,
      bounds.width * bounds.height <= Surface.maxPixels
    else {
      throw CraftError.unsupported(
        "The merged layer exceeds the supported raster bounds or lies outside the canvas.")
    }
    return Plan(layers: visible, base: base, removed: Set(members.map(\.id)), bounds: bounds)
  }

  public static func apply(
    _ operation: LayerMergeOperation, layerIDs: Set<UUID>, to document: inout CraftDocument
  ) throws {
    try document.validate()
    let p = try plan(operation, layerIDs: layerIDs, in: document)
    try Task.checkCancellation()
    let bounds = p.bounds
    // Keep Float32 input, arithmetic and committed pixels in linear storage.
    var pixels = try Surface(
      width: bounds.width, height: bounds.height, depth: document.depth,
      fill: Pixel(1, 1, 1, 0),
      colorEncoding: document.depth == .f32 ? .linearRGB : .sRGB)
    var occupied = [Bool](repeating: false, count: bounds.width * bounds.height)
    for layer in p.layers {
      guard case .raster(let surface) = layer.content else { continue }
      let x0 = max(bounds.x, layer.x)
      let y0 = max(bounds.y, layer.y)
      let x1 = min(bounds.x + bounds.width, layer.x + surface.width)
      let y1 = min(bounds.y + bounds.height, layer.y + surface.height)
      guard x0 < x1, y0 < y1 else { continue }
      for y in y0..<y1 {
        try Task.checkCancellation()
        for x in x0..<x1 {
          let px = x - bounds.x
          let py = y - bounds.y
          let index = py * bounds.width + px
          let source = document.depth == .f32
            ? surface.linearPixel(x: x - layer.x, y: y - layer.y)
            : surface.pixel(x: x - layer.x, y: y - layer.y)
          let storedBackdrop = document.depth == .f32
            ? pixels.linearPixel(x: px, y: py) : pixels.pixel(x: px, y: py)
          let backdrop = occupied[index] ? storedBackdrop : Pixel(source.r, source.g, source.b, 0)
          let result = NormalLayerComposite.composite(
            backdrop: backdrop, source: source, opacity: layer.opacity, depth: document.depth)
          guard result.isFinite else {
            throw CraftError.invalid("Merged colors exceed the floating-point range.")
          }
          if document.depth == .f32 {
            pixels.setLinearPixel(x: px, y: py, result)
          } else {
            pixels.setPixel(x: px, y: py, result)
          }
          occupied[index] = true
        }
      }
    }
    guard let contentBounds = try pixels.contentBounds() else {
      throw CraftError.unsupported("Merging entirely transparent layers is not available yet.")
    }
    pixels = try pixels.cropped(to: contentBounds)
    var merged = Layer(name: p.base.name, content: .raster(pixels))
    merged.id = p.base.id
    merged.x = bounds.x + contentBounds.x
    merged.y = bounds.y + contentBounds.y
    var candidate = document
    candidate.layers = document.layers.compactMap { layer in
      if layer.id == p.base.id { return merged }
      return p.removed.contains(layer.id) ? nil : layer
    }
    candidate.activeLayerID = merged.id
    try candidate.validate()
    try Task.checkCancellation()
    document = candidate
  }
}
