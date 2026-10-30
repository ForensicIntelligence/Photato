import Foundation

/// Affine mapping in image coordinates (positive Y points down). Multiplication applies the RHS first.
public struct Transform2D: Codable, Equatable, Sendable {
  public var a: Double
  public var b: Double
  public var c: Double
  public var d: Double
  public var tx: Double
  public var ty: Double
  public init(
    a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0
  ) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }
  public static let identity = Transform2D()
  public static func translation(_ x: Double, _ y: Double) -> Self { Self(tx: x, ty: y) }
  public static func scale(_ x: Double, _ y: Double) -> Self { Self(a: x, d: y) }
  public static func rotation(_ degrees: Double) -> Self {
    let radians = degrees * .pi / 180
    func snap(_ n: Double) -> Double {
      abs(n) < 1e-12 ? 0 : abs(n - 1) < 1e-12 ? 1 : abs(n + 1) < 1e-12 ? -1 : n
    }
    return Self(
      a: snap(cos(radians)), b: snap(sin(radians)), c: -snap(sin(radians)), d: snap(cos(radians)))
  }
  public static func * (l: Self, r: Self) -> Self {
    Self(
      a: l.a * r.a + l.c * r.b, b: l.b * r.a + l.d * r.b,
      c: l.a * r.c + l.c * r.d, d: l.b * r.c + l.d * r.d,
      tx: l.a * r.tx + l.c * r.ty + l.tx, ty: l.b * r.tx + l.d * r.ty + l.ty)
  }
  public func point(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
    (a * x + c * y + tx, b * x + d * y + ty)
  }
  public func validated() throws {
    guard [a, b, c, d, tx, ty].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
      abs(a * d - b * c) >= 1e-8
    else { throw CraftError.invalid("Transform is invalid or too small.") }
  }
  public func inverted() throws -> Self {
    try validated()
    let det = a * d - b * c
    return Self(
      a: d / det, b: -b / det, c: -c / det, d: a / det,
      tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
  }
  public func bounds(width: Int, height: Int) throws -> IntRect {
    try validated()
    let corners = [
      point(0, 0), point(Double(width), 0), point(0, Double(height)),
      point(Double(width), Double(height)),
    ]
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    let x0 = floor((xs.min() ?? 0) + 1e-9)
    let y0 = floor((ys.min() ?? 0) + 1e-9)
    let x1 = ceil((xs.max() ?? 0) - 1e-9)
    let y1 = ceil((ys.max() ?? 0) - 1e-9)
    guard [x0, y0, x1, y1].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }), x1 > x0, y1 > y0,
      x1 - x0 <= Double(Surface.maxDimension), y1 - y0 <= Double(Surface.maxDimension),
      (x1 - x0) * (y1 - y0) <= Double(Surface.maxPixels)
    else { throw CraftError.invalid("Transformed image exceeds the supported dimensions.") }
    return IntRect(x: Int(x0), y: Int(y0), width: Int(x1 - x0), height: Int(y1 - y0))
  }
}

public enum Resampling: String, CaseIterable, Codable, Sendable {
  case nearest = "Nearest Neighbor"
  case bilinear = "Bilinear"
  case bicubic = "Bicubic"
}
public enum CanvasAnchor: String, CaseIterable, Sendable, Codable {
  case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
  public var fractions: (Double, Double) {
    switch self {
    case .topLeft: (0, 0)
    case .top: (0.5, 0)
    case .topRight: (1, 0)
    case .left: (0, 0.5)
    case .center: (0.5, 0.5)
    case .right: (1, 0.5)
    case .bottomLeft: (0, 1)
    case .bottom: (0.5, 1)
    case .bottomRight: (1, 1)
    }
  }
}
public enum CanvasTurn: String, CaseIterable, Sendable, Codable {
  case clockwise = "90° Clockwise"
  case counterclockwise = "90° Counter Clockwise"
  case half = "180°"
  case horizontal = "Flip Canvas Horizontal"
  case vertical = "Flip Canvas Vertical"
  public func transform(width: Int, height: Int) -> Transform2D {
    switch self {
    case .clockwise: Transform2D(a: 0, b: 1, c: -1, d: 0, tx: Double(height))
    case .counterclockwise: Transform2D(a: 0, b: -1, c: 1, d: 0, ty: Double(width))
    case .half: Transform2D(a: -1, d: -1, tx: Double(width), ty: Double(height))
    case .horizontal: Transform2D(a: -1, tx: Double(width))
    case .vertical: Transform2D(d: -1, ty: Double(height))
    }
  }
}

public enum RasterGeometry {
  /// Samples at pixel centers, interpolating premultiplied alpha to avoid color fringes.
  public static func sample(
    _ s: Surface, x: Double, y: Double, method: Resampling, clampEdges: Bool = false
  ) -> Pixel {
    guard x.isFinite, y.isFinite, abs(x) < 10_000_000, abs(y) < 10_000_000 else { return .clear }
    func pixel(_ ix: Int, _ iy: Int) -> Pixel {
      s.pixel(
        x: clampEdges ? min(s.width - 1, max(0, ix)) : ix,
        y: clampEdges ? min(s.height - 1, max(0, iy)) : iy)
    }
    if method == .nearest { return pixel(Int(floor(x)), Int(floor(y))) }
    let sx = x - 0.5
    let sy = y - 0.5
    let ix = Int(floor(sx))
    let iy = Int(floor(sy))
    func pm(_ p: Pixel) -> SIMD4<Float> { SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a) }
    let fx = Float(sx - Double(ix))
    let fy = Float(sy - Double(iy))
    let value: SIMD4<Float>
    if method == .bilinear {
      value =
        (pm(pixel(ix, iy)) * (1 - fx) + pm(pixel(ix + 1, iy)) * fx) * (1 - fy)
        + (pm(pixel(ix, iy + 1)) * (1 - fx) + pm(pixel(ix + 1, iy + 1)) * fx) * fy
    } else {
      func weight(_ n: Float) -> Float {
        let v = abs(n)
        if v <= 1 { return 1.5 * v * v * v - 2.5 * v * v + 1 }
        if v < 2 { return -0.5 * v * v * v + 2.5 * v * v - 4 * v + 2 }
        return 0
      }
      var sum = SIMD4<Float>.zero
      for j in -1...2 {
        for i in -1...2 {
          sum += pm(pixel(ix + i, iy + j)) * weight(Float(i) - fx) * weight(Float(j) - fy)
        }
      }
      value = sum
    }
    guard value.w > 1e-8 else { return .clear }
    return Pixel(value.x / value.w, value.y / value.w, value.z / value.w, unit(value.w))
  }
  public static func render(
    _ surface: Surface, transform: Transform2D, bounds: IntRect, method: Resampling,
    clampEdges: Bool = false
  ) throws -> Surface {
    let inverse = try transform.inverted()
    guard bounds.width > 0, bounds.height > 0, bounds.width <= Surface.maximumDensePixels / bounds.height else {
      throw CraftError.unsupported("Large raster resampling needs tiled geometry processing, which is not yet available.")
    }
    var output = try Surface(width: bounds.width, height: bounds.height, depth: surface.depth)
    for y in 0..<bounds.height {
      try Task.checkCancellation()
      for x in 0..<bounds.width {
        let p = inverse.point(
          Double(x) + Double(bounds.x) + 0.5, Double(y) + Double(bounds.y) + 0.5)
        // Never stretch edge pixels outside the transformed source rectangle.
        guard p.x >= 0, p.y >= 0, p.x < Double(surface.width), p.y < Double(surface.height) else {
          continue
        }
        let pixel = sample(surface, x: p.x, y: p.y, method: method, clampEdges: clampEdges)
        if pixel != .clear { output.setPixel(x: x, y: y, pixel) }
      }
    }
    return output
  }
}

extension Layer {
  public var coordinateTransform: Transform2D {
    .translation(Double(x), Double(y)) * (affine ?? .identity)
  }
  public var canTransform: Bool {
    switch content {
    case .raster, .shape, .text, .group: !locked
    default: false
    }
  }
}

public enum DocumentGeometry {
  static func freezeTextLayout(_ layer: inout Layer, document: CraftDocument) {
    if case .text(var t) = layer.content {
      t.layoutWidth = t.layoutWidth ?? document.width
      t.layoutHeight = t.layoutHeight ?? document.height
      layer.content = .text(t)
    }
  }
  public static func transformLayer(
    _ layer: Layer, by delta: Transform2D, in document: CraftDocument,
    method: Resampling = .bicubic,
    includingUnlinkedMasks: Bool = false
  ) throws -> Layer {
    try delta.validated()
    var result = layer
    if case .patternFill(var fill) = result.content, fill.linked || includingUnlinkedMasks {
      try fill.transform(by: delta)
      result.content = .patternFill(fill)
    }
    if case .gradientFill(var fill) = result.content {
      try fill.transform(by: delta)
      result.content = .gradientFill(fill)
    }
    result.smartFilters?.transformPuppetPins(delta)
    result.smartFilters?.transformPerspectivePlanes(delta)
    if let stack = layer.smartFilters, stack.mask != nil, stack.maskProperties.linked || includingUnlinkedMasks {
      result.smartFilters?.maskProperties.transform = delta * stack.maskProperties.transform
    }
    freezeTextLayout(&result, document: document)
    let full = delta * layer.coordinateTransform
    try full.validated()
    if var group = layer.group, var board = group.artboard {
      guard abs(delta.a * delta.c) < 1e-9, abs(delta.b * delta.d) < 1e-9 else { throw CraftError.unsupported("Artboards support axis-aligned resizing and canvas quarter turns.") }
      let bounds = try full.bounds(width: board.width, height: board.height)
      board.width = bounds.width; board.height = bounds.height; board.preset = ""
      board.guides = board.guides.map { guide in
        var guide = guide
        let horizontal = guide.axis == .horizontal
        let p = full.point(horizontal ? 0 : guide.position, horizontal ? guide.position : 0)
        let swapped = abs(delta.a) < 1e-9 && abs(delta.d) < 1e-9
        if swapped { guide.axis = horizontal ? .vertical : .horizontal }
        guide.position = guide.axis == .horizontal ? p.y - Double(bounds.y) : p.x - Double(bounds.x)
        return guide
      }
      group.artboard = board; result.content = .group(group)
      result.x = bounds.x; result.y = bounds.y; result.affine = nil
    } else if case .raster(let surface) = layer.content, layer.smartObject == nil, layer.video == nil, !layer.hasGeometryKeyframes {
      let bounds = try full.bounds(width: surface.width, height: surface.height)
      result.content = .raster(
        try RasterGeometry.render(
          surface, transform: full, bounds: bounds, method: method, clampEdges: true))
      if let native = layer.nativeMode {
        let transformed = try native.transformed(by: full, bounds: bounds, method: method, clampEdges: true)
        result.nativeMode = transformed; result.content = .raster(try transformed.surface())
      }
      if let mask = layer.mask, layer.maskProperties == nil {
        result.mask = try RasterGeometry.render(
          mask, transform: full, bounds: bounds, method: method, clampEdges: true)
      }
      result.x = bounds.x
      result.y = bounds.y
      result.affine = nil
    } else {
      // Keep text and vector geometry editable. Masks use the same local coordinate transform.
      result.x = Int(floor(full.tx))
      result.y = Int(floor(full.ty))
      result.affine = Transform2D.translation(-Double(result.x), -Double(result.y)) * full
    }
    if layer.mask != nil, layer.maskProperties != nil {
      var properties = layer.effectiveMaskProperties
      let target =
        properties.linked || includingUnlinkedMasks
        ? delta * layer.maskCoordinateTransform : layer.maskCoordinateTransform
      properties.transform = try result.coordinateTransform.inverted() * target
      result.maskProperties = properties
    }
    if let mask = layer.vectorMask, mask.linked || includingUnlinkedMasks {
      result.vectorMask?.path = mask.path.transformed(delta)
    }
    return result
  }
  public static func mapSelection(_ selection: IntRect?, by t: Transform2D, width: Int, height: Int)
    throws -> IntRect?
  {
    guard let s = selection else { return nil }
    let b = try (t * .translation(Double(s.x), Double(s.y))).bounds(
      width: s.width, height: s.height)
    let x = max(0, b.x)
    let y = max(0, b.y)
    let right = min(width, b.x + b.width)
    let bottom = min(height, b.y + b.height)
    return right > x && bottom > y ? IntRect(x: x, y: y, width: right - x, height: bottom - y) : nil
  }
}
