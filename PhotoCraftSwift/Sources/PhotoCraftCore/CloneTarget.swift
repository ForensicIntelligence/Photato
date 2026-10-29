import Foundation

extension ClonePainter {
  /// Paint an expandable layer target atomically. Existing off-canvas storage is retained,
  /// while new paint is limited to the document canvas and active selection.
  @discardableResult public static func paint(
    _ stroke: CloneStroke, on layer: inout Layer, canvasWidth: Int, canvasHeight: Int,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil,
    preserveTransparency: Bool = false
  ) throws -> Bool {
    let preserve = !stroke.mask && (preserveTransparency || layer.protection.locksTransparency)
    let sourceMapping = try prepare(stroke)
    return try paintTarget(
      stroke, on: &layer, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, selection: selection, preserveTransparency: preserve
    ) { pixels, transform, clipping in
      try paintPrepared(
        stroke, on: &pixels, transform: transform, sourceMapping: sourceMapping,
        selection: clipping, selectionMask: selectionMask, preserveTransparency: preserve)
    }
  }

  /// Reframe either retouch tool's storage and commit only after its renderer succeeds.
  static func paintTarget(
    _ stroke: CloneStroke, on layer: inout Layer,
    canvasWidth: Int, canvasHeight: Int, selection: IntRect?,
    preserveTransparency: Bool = false,
    render: (inout Surface, Transform2D, IntRect) throws -> Bool
  ) throws -> Bool {
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    let clipping = (selection ?? IntRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
      .clipped(toWidth: canvasWidth, height: canvasHeight)
    let bounds =
      stroke.brush.opacity > 0 && stroke.brush.flow > 0
      ? footprint(stroke, clipping: clipping) : nil
    return try paintTarget(
      mask: stroke.mask, bounds: bounds, on: &layer,
      clipping: clipping, preserveTransparency: preserveTransparency, render: render)
  }

  /// Shared storage expansion for a bounded paint operation, including region fills.
  static func paintTarget(
    mask: Bool, bounds: IntRect?, on layer: inout Layer, clipping: IntRect,
    preserveTransparency: Bool = false,
    render: (inout Surface, Transform2D, IntRect) throws -> Bool
  ) throws -> Bool {
    let original: Surface
    let transform: Transform2D
    if mask {
      guard let mask = layer.mask else { throw CraftError.invalid("This layer has no pixel mask.") }
      original = mask
      transform = layer.maskCoordinateTransform
    } else {
      guard case .raster(let surface) = layer.content else {
        throw CraftError.unsupported("Rasterize this layer before retouching.")
      }
      original = surface
      transform = layer.coordinateTransform
    }
    let inverse = try transform.inverted()
    guard let bounds else { return false }
    let local = try (inverse * .translation(Double(bounds.x), Double(bounds.y)))
      .bounds(width: bounds.width, height: bounds.height)
    let preserve = !mask && (preserveTransparency || layer.protection.locksTransparency)
    let x = preserve ? 0 : min(0, local.x)
    let y = preserve ? 0 : min(0, local.y)
    let right = preserve ? original.width : max(original.width, local.x + local.width)
    let bottom = preserve ? original.height : max(original.height, local.y + local.height)
    let storage = IntRect(x: x, y: y, width: right - x, height: bottom - y)
    let outside = mask ? layer.effectiveMaskProperties.outside : 0
    let fill = mask ? Pixel(outside, outside, outside) : Pixel.clear
    var pixels = try original.expanded(to: storage, fill: fill, preservingFillBits: mask)
    let offset = Transform2D.translation(Double(x), Double(y))
    let grownTransform = transform * offset
    guard try render(&pixels, grownTransform, clipping) else { return false }
    var result = layer
    if mask {
      result.mask = pixels
      if x != 0 || y != 0 {
        var properties = result.effectiveMaskProperties
        properties.transform = properties.transform * offset
        result.maskProperties = properties
      }
    } else {
      result.content = .raster(pixels)
      if x != 0 || y != 0 {
        try grownTransform.validated()
        result.x = Int(floor(grownTransform.tx))
        result.y = Int(floor(grownTransform.ty))
        let affine = Transform2D.translation(-Double(result.x), -Double(result.y)) * grownTransform
        result.affine = affine == .identity ? nil : affine
        // Reframing storage is not moving the layer. Linked and unlinked masks must
        // both retain their document positions; vector masks already use document space.
        if result.mask != nil {
          var properties = result.effectiveMaskProperties
          properties.transform = .translation(-Double(x), -Double(y)) * properties.transform
          result.maskProperties = properties
        }
      }
    }
    try Task.checkCancellation()
    layer = result
    return true
  }

  /// Conservative coverage bounds include the half-pixel antialiasing fringe. All points
  /// participate because an interpolated dab can lie between a zero-pressure endpoint and
  /// its positive-pressure neighbor. Validation precedes every call.
  static func footprint(_ stroke: CloneStroke, clipping: IntRect) -> IntRect? {
    let pressure = stroke.points.map(\.pressure).max() ?? 0
    guard pressure > 0, clipping.width > 0, clipping.height > 0 else { return nil }
    let radius =
      max(0.25, stroke.brush.size * (stroke.brush.pressureSize ? Double(pressure) : 1) / 2)
      + 0.5
    let x0 = max(Double(clipping.x), floor((stroke.points.map(\.x).min() ?? 0) - radius))
    let y0 = max(Double(clipping.y), floor((stroke.points.map(\.y).min() ?? 0) - radius))
    let x1 = min(
      Double(clipping.x + clipping.width), ceil((stroke.points.map(\.x).max() ?? 0) + radius))
    let y1 = min(
      Double(clipping.y + clipping.height), ceil((stroke.points.map(\.y).max() ?? 0) + radius))
    guard x1 > x0, y1 > y0 else { return nil }
    return IntRect(x: Int(x0), y: Int(y0), width: Int(x1 - x0), height: Int(y1 - y0))
  }
}
