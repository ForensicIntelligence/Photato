import Foundation

/// Coordinates map the stored mask rectangle into the layer's local coordinate system.
/// The outside value is independent of the surface's in-bounds default pixel.
public struct MaskProperties: Codable, Equatable, Sendable {
  public var transform = Transform2D.identity
  public var outside: Float = 0
  public var enabled = true
  public var linked = true
  public var inverted = false
  public var density: Float = 1
  public var feather: Double = 0
  public init() {}
  public func validate() throws {
    try transform.validated()
    guard outside.isFinite, (0...1).contains(outside), density.isFinite, (0...1).contains(density),
      feather.isFinite, (0...100).contains(feather)
    else {
      throw CraftError.invalid("Invalid mask properties; feather currently supports 0–100 pixels.")
    }
  }
}

extension Layer {
  public var effectiveMaskProperties: MaskProperties { maskProperties ?? MaskProperties() }
  public var maskCoordinateTransform: Transform2D {
    coordinateTransform * effectiveMaskProperties.transform
  }
  /// Keep an unlinked mask in document space when only its layer changes position/geometry.
  public mutating func preserveUnlinkedMask(from old: Layer) throws {
    guard mask != nil, !old.effectiveMaskProperties.linked else { return }
    var properties = old.effectiveMaskProperties
    properties.transform = try coordinateTransform.inverted() * old.maskCoordinateTransform
    maskProperties = properties
  }
}

/// Prepared once per rendered layer. Samples grayscale coverage, never mask alpha.
public struct MaskSampler: Sendable {
  private let mask: Surface
  private let feathered: FeatheredMask?
  private let inverse: Transform2D
  private let properties: MaskProperties
  public init(
    layer: Layer, feather: Bool = true, canvasSize: (width: Int, height: Int)? = nil,
    usesLayerFeather: Bool = true
  ) throws {
    guard let source = layer.mask else { throw CraftError.invalid("Layer has no mask.") }
    properties = layer.effectiveMaskProperties
    try properties.validate()
    mask = source
    var matrix = layer.maskCoordinateTransform
    if feather && properties.enabled && properties.feather > 0 {
      var edges = FeatheredMask.ClampedEdges()
      if let canvasSize,
        matrix.a == 1, matrix.b == 0, matrix.c == 0, matrix.d == 1
      {
        // Photoshop extends a coincident canvas edge only when the raster does
        // not continue beyond it. Otherwise the mask's outside coverage must
        // participate in feathering, even when its stored rectangle starts at 0.
        if matrix.tx == 0 { edges.insert(.left) }
        if matrix.ty == 0 { edges.insert(.top) }
        if matrix.tx + Double(source.width) == Double(canvasSize.width) { edges.insert(.right) }
        if matrix.ty + Double(source.height) == Double(canvasSize.height) { edges.insert(.bottom) }
        let pixelsToDocument = layer.coordinateTransform
        if case .raster(let pixels) = layer.content,
          pixelsToDocument.a == 1, pixelsToDocument.b == 0,
          pixelsToDocument.c == 0, pixelsToDocument.d == 1
        {
          if pixelsToDocument.tx < 0 { edges.remove(.left) }
          if pixelsToDocument.ty < 0 { edges.remove(.top) }
          if pixelsToDocument.tx + Double(pixels.width) > Double(canvasSize.width) {
            edges.remove(.right)
          }
          if pixelsToDocument.ty + Double(pixels.height) > Double(canvasSize.height) {
            edges.remove(.bottom)
          }
        }
      }
      try Task.checkCancellation()
      let radius = properties.feather
      let area = usesLayerFeather ? canvasSize.flatMap {
        AreaMaskFeather(layer: layer, source: source, radius: radius, canvas: $0)
      } : nil
      let result = FeatheredMask(source: source, radius: properties.feather,
        outside: properties.outside, edges: edges, area: area)
      feathered = result
      matrix = matrix * .translation(Double(result.origin.x), Double(result.origin.y))
    } else {
      feathered = nil
    }
    inverse = try matrix.inverted()
  }
  @inline(__always) public func coverage(x: Double, y: Double) -> Float {
    if !properties.enabled { return 1 }
    let p = inverse.point(x, y)
    var v: Float
    if let feathered {
      v = Self.sample(width: feathered.width, height: feathered.height,
        x: p.x, y: p.y, outside: properties.outside, value: feathered.value)
    } else {
      v = Self.sample(mask, x: p.x, y: p.y, outside: properties.outside)
    }
    if properties.inverted { v = 1 - v }
    // Full density is an identity operation. Subtracting twice from white
    // changes Float32 mask samples and therefore the resulting RGB32 composite.
    if properties.density == 1 { return v }
    return 1 - properties.density * (1 - v)
  }
  /// Proves unit coverage at every pixel center in this rectangle. Fractional
  /// constant masks are deliberately excluded: bilinear evaluation can round
  /// their samples by one Float ULP, so folding them would change stored pixels.
  public func isIdentity(over region: IntRect) -> Bool {
    if !properties.enabled || properties.density == 0 { return true }
    let value: Float = properties.inverted ? 0 : 1
    guard mask.tileCount == 0 else { return false }
    if let feathered { return feathered.isConstantOutside && properties.outside == value }
    guard mask.defaultPixel.r == value else { return false }
    if properties.outside == value { return true }
    guard region.width > 0, region.height > 0 else { return true }
    let x0 = Double(region.x) + 0.5
    let y0 = Double(region.y) + 0.5
    let x1 = Double(region.x) + Double(region.width) - 0.5
    let y1 = Double(region.y) + Double(region.height) - 0.5
    // Affine maps preserve convexity. All sample centers, including fractional
    // transformed positions, are inside if the four corners are inside.
    return [
      inverse.point(x0, y0), inverse.point(x1, y0),
      inverse.point(x0, y1), inverse.point(x1, y1),
    ].allSatisfy {
      $0.x >= 0.5 && $0.y >= 0.5
        && $0.x <= Double(mask.width) - 0.5 && $0.y <= Double(mask.height) - 0.5
    }
  }
  public static func sample(_ surface: Surface, x: Double, y: Double, outside: Float) -> Float {
    sample(width: surface.width, height: surface.height, x: x, y: y, outside: outside) {
      unit(surface.pixel(x: $0, y: $1).r)
    }
  }

  @inline(__always) private static func sample(
    width: Int, height: Int, x: Double, y: Double, outside: Float, value: (Int, Int) -> Float
  ) -> Float {
    guard x.isFinite, y.isFinite else { return outside }
    let px = x - 0.5
    let py = y - 0.5
    guard px >= -1, py >= -1, px <= Double(width), py <= Double(height) else { return outside }
    let ix = Int(floor(px))
    let iy = Int(floor(py))
    let fx = Float(px - floor(px))
    let fy = Float(py - floor(py))
    func sampleAt(_ x: Int, _ y: Int) -> Float {
      if x < 0 || y < 0 || x >= width || y >= height { return outside }
      return value(x, y)
    }
    let a = sampleAt(ix, iy) * (1 - fx) + sampleAt(ix + 1, iy) * fx
    let b = sampleAt(ix, iy + 1) * (1 - fx) + sampleAt(ix + 1, iy + 1) * fx
    return unit(a * (1 - fy) + b * fy)
  }

  /// Includes both the legacy Gaussian footprint and any staged box windows.
  public static func featherDamageRadius(_ radius: Double) -> Double {
    let gaussian = ceil(3 * max(0.05, radius))
    let area = AreaMaskFeather.widths(at: radius)?.reduce(0) { $0 + $1 / 2 } ?? 0
    return max(gaussian, Double(area))
  }

  /// Upper bound for retained derived Float32 samples in one feather sampler.
  public static let maximumFeatherCacheBytes = FeatheredMask.maximumCacheBytes
}

extension Layer {
  /// A PSD mask may be tightly cropped. Painting beyond that stored rectangle must create
  /// samples there, filled with the mask's outside value, without shifting existing coverage.
  mutating func expandMask(toDocumentBounds rect: IntRect) throws {
    guard let source = mask else { throw CraftError.invalid("Layer has no mask.") }
    let local = try
      (maskCoordinateTransform.inverted() * .translation(Double(rect.x), Double(rect.y)))
      .bounds(width: rect.width, height: rect.height)
    let x = min(0, local.x)
    let y = min(0, local.y)
    let right = max(source.width, local.x + local.width)
    let bottom = max(source.height, local.y + local.height)
    guard x != 0 || y != 0 || right != source.width || bottom != source.height else { return }
    var p = effectiveMaskProperties
    var expanded = try Surface(
      width: right - x, height: bottom - y, depth: source.depth,
      fill: Pixel(p.outside, p.outside, p.outside))
    for sy in 0..<source.height {
      try Task.checkCancellation()
      for sx in 0..<source.width {
        expanded.setPixel(x: sx - x, y: sy - y, source.pixel(x: sx, y: sy))
      }
    }
    p.transform = p.transform * .translation(Double(x), Double(y))
    mask = expanded
    maskProperties = p
  }
  mutating func expandMask(for points: [StrokePoint], brush: Brush, clipping: IntRect? = nil) throws
  {
    guard brush.size.isFinite, brush.supportedDiameterRange.contains(brush.size), points.count <= 100_000,
      points.allSatisfy({
        $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000
          && $0.pressure.isFinite && (0...1).contains($0.pressure)
      })
    else {
      throw CraftError.invalid("Invalid mask stroke bounds.")
    }
    if brush.settings != nil {
      if var bounds=try BrushPainter.strokeBounds(points:points,brush:brush) {
        if let clipping {
          let x=max(bounds.x,clipping.x),y=max(bounds.y,clipping.y),r=min(bounds.x+bounds.width,clipping.x+clipping.width),b=min(bounds.y+bounds.height,clipping.y+clipping.height)
          guard r>x,b>y else { return };bounds = .init(x:x,y:y,width:r-x,height:b-y)
        }
        try expandMask(toDocumentBounds:bounds)
      };return
    }
    let points = points.filter { $0.pressure > 0 }
    guard !points.isEmpty else { return }
    let radius = brush.size / 2
    var x = Int(floor(points.map(\.x).min()! - radius))
    var y = Int(floor(points.map(\.y).min()! - radius))
    var right = Int(ceil(points.map(\.x).max()! + radius))
    var bottom = Int(ceil(points.map(\.y).max()! + radius))
    if let clipping {
      x = max(x, clipping.x)
      y = max(y, clipping.y)
      right = min(right, clipping.x + clipping.width)
      bottom = min(bottom, clipping.y + clipping.height)
      guard right > x, bottom > y else { return }
    }
    try expandMask(
      toDocumentBounds: IntRect(x: x, y: y, width: max(1, right - x), height: max(1, bottom - y)))
  }
}

/// Mask paint normalization shared with the retained owner; keep legacy color/erase semantics.
enum MaskStrokePreparation {
  static func normalized(_ input: Brush) throws -> Brush {
    var brush = input
    let value = brush.erase ? Float(1) : unit(0.2126 * brush.color.r + 0.7152 * brush.color.g + 0.0722 * brush.color.b)
    guard brush.color.isFinite else { throw CraftError.invalid("Invalid mask brush color.") }
    brush.color = Pixel(value, value, value, brush.color.a)
    brush.erase = false
    return brush
  }
}
