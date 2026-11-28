import Foundation

public enum LayerMergeOperation: String, CaseIterable, Sendable, Codable {
  case down = "Merge Down"
  case clippingMask = "Merge Clipping Mask"
  case selected = "Merge Layers"
  case visible = "Merge Visible"
  case stampDown = "Stamp Down"
  case stampGroup = "Stamp Group"
  case stampSelected = "Stamp Layers"
  case stampVisible = "Stamp Visible"

  public var preservesSources: Bool { self == .stampSelected || self == .stampVisible }

  package var inPlaceMergeOperation: LayerMergeOperation? {
    switch self {
    case .stampDown: return .down
    case .stampGroup: return .clippingMask
    default: return nil
    }
  }
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
    (try? LayerMergePlan(operation, layerIDs: layerIDs, in: document)) != nil
  }

  public static func isClippingBase(_ ids: Set<UUID>, in document: CraftDocument) -> Bool {
    guard ids.count == 1, let id = ids.first,
      let index = document.layers.firstIndex(where: { $0.id == id }) else { return false }
    let base = document.layers[index]
    guard base.visible, !base.isClipped else { return false }
    return document.layers.dropFirst(index + 1).first { $0.parentID == base.parentID }?.isClipped == true
  }

  /// Validate the operation and expose its allocation bounds before starting work.
  public static func outputBounds(
    _ operation: LayerMergeOperation, layerIDs: Set<UUID>, in document: CraftDocument
  ) throws -> IntRect {
    try plan(operation, layerIDs: layerIDs, in: document).bounds
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
    case .stampDown, .stampGroup, .stampSelected, .stampVisible:
      throw CraftError.unsupported("Stamping layers requires the document compositor.")
    case .clippingMask:
      throw CraftError.unsupported("Merging a clipping mask requires the document compositor.")
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
        layer.mask == nil, layer.vectorMask == nil, layer.affine == nil, layer.style == nil, layer.smartObject == nil
      else {
        throw CraftError.unsupported(
          "This merge currently supports unlocked Normal pixel layers without masks, transforms or layer styles.")
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
      bounds.width * bounds.height <= Surface.maximumDensePixels
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
    var pixels = try compositeNormalPixels(p.layers, depth: document.depth, bounds: bounds)
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
    try candidate.reconcileModeStorage(from: document)
    try candidate.validate()
    try Task.checkCancellation()
    document = candidate
  }

  /// Use the measured integer Normal merge for ordinary working-coordinate data.
  /// Keep the full canvas for the subsequent color-mode conversion.
  public static func integerModeComposite(_ document: CraftDocument, region: IntRect? = nil,
    emptySample: Pixel = .clear, promoteRGB16Opacity: Bool = false) throws -> Surface?
  {
    let bounds = region ?? IntRect(x: 0, y: 0, width: document.width, height: document.height)
    guard document.depth != .f32, bounds.width > 0, bounds.height > 0,
      bounds.width <= 4_194_304 / bounds.height else { return nil }
    let layers = document.layers.filter { $0.visible && $0.opacity > 0 }
    guard !layers.isEmpty, layers.allSatisfy({
      if case .raster = $0.content {
        return $0.blendMode == .normal && $0.mask == nil && $0.vectorMask == nil
      }
      return false
    }) else { return nil }
    return try compositeNormalPixels(layers, depth: document.depth, bounds: bounds, fill: emptySample,
      promoteRGB16Opacity: promoteRGB16Opacity)
  }

  private static func compositeNormalPixels(_ layers: [Layer], depth: PixelDepth, bounds: IntRect,
    fill: Pixel = Pixel(1, 1, 1, 0), promoteRGB16Opacity: Bool = false) throws -> Surface
  {
    // Keep Float32 input, arithmetic and committed pixels in linear storage.
    var pixels = try Surface(
      width: bounds.width, height: bounds.height, depth: depth, fill: fill,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    var occupied = [Bool](repeating: false, count: bounds.width * bounds.height)
    for layer in layers {
      guard case .raster(let surface) = layer.content else { continue }
      let x0 = max(bounds.x, layer.x)
      let y0 = max(bounds.y, layer.y)
      let x1 = min(bounds.x + bounds.width, layer.x + surface.width)
      let y1 = min(bounds.y + bounds.height, layer.y + surface.height)
      guard x0 < x1, y0 < y1 else { continue }
      let promotedOpacity = promoteRGB16Opacity && depth == .u16 ? NormalLayerComposite.clippingOpacity(layer.opacity, depth: depth) : nil
      for y in y0..<y1 {
        try Task.checkCancellation()
        for x in x0..<x1 {
          let px = x - bounds.x
          let py = y - bounds.y
          let index = py * bounds.width + px
          let source =
            depth == .f32
            ? surface.linearPixel(x: x - layer.x, y: y - layer.y)
            : surface.pixel(x: x - layer.x, y: y - layer.y)
          let storedBackdrop =
            depth == .f32
            ? pixels.linearPixel(x: px, y: py) : pixels.pixel(x: px, y: py)
          let backdrop = occupied[index] ? storedBackdrop : Pixel(source.r, source.g, source.b, 0)
          let result: Pixel
          if let promotedOpacity {
            result = NormalLayerComposite.compositeWithRGB16Opacity(backdrop: backdrop, source: source, opacity: promotedOpacity)
          } else {
            result = NormalLayerComposite.composite(backdrop: backdrop, source: source, opacity: layer.opacity, depth: depth)
          }
          guard result.isFinite else {
            throw CraftError.invalid("Merged colors exceed the floating-point range.")
          }
          if depth == .f32 {
            pixels.setLinearPixel(x: px, y: py, result)
          } else {
            pixels.setPixel(x: px, y: py, result)
          }
          occupied[index] = true
        }
      }
    }
    return pixels
  }
}
