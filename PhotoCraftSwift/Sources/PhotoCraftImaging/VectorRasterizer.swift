import CoreGraphics
import Foundation
import PhotoCraftCore

public enum VectorRasterizer {
  public static func outline(_ path: VectorPath) throws -> CGPath {
    try path.validate()
    let result = CGMutablePath()
    for component in path.components { append(component, to: result) }
    return result
  }
  private static func append(_ component: PathComponent, to path: CGMutablePath) {
    guard let first = component.knots.first else { return }
    func point(_ p: PathPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    path.move(to: point(first.anchor))
    let count = component.knots.count
    guard count > 1 else { return }
    for i in 0..<(component.closed ? count : count - 1) {
      let a = component.knots[i]
      let b = component.knots[(i + 1) % count]
      path.addCurve(to: point(b.anchor), control1: point(a.outgoing), control2: point(b.incoming))
    }
    if component.closed { path.closeSubpath() }
  }
  /// Joined contours share a fill rule; boolean components are resolved before antialiasing.
  public static func filledPath(_ path: VectorPath) throws -> CGPath {
    try path.validate()
    let rule: CGPathFillRule = path.fillRule == .evenOdd ? .evenOdd : .winding
    var groups: [(PathOperation, CGMutablePath)] = []
    for component in path.components where component.knots.count > 1 {
      try Task.checkCancellation()
      if component.operation != .join || groups.isEmpty {
        groups.append((component.operation, CGMutablePath()))
      }
      append(component, to: groups[groups.count - 1].1)
    }
    guard let first = groups.first else { return CGMutablePath() }
    var result = first.1.normalized(using: rule)
    for (operation, raw) in groups.dropFirst() {
      try Task.checkCancellation()
      let next = raw.normalized(using: rule)
      switch operation {
      case .combine, .join: result = result.union(next)
      case .subtract: result = result.subtracting(next)
      case .intersect: result = result.intersection(next)
      case .exclude: result = result.symmetricDifference(next)
      }
    }
    return result
  }
  public static func coverage(
    _ path: VectorPath, width: Int, height: Int,
    origin: PathPoint = PathPoint(0, 0), antiAlias: Bool = true,
    emptyRevealsAll: Bool = false
  ) throws -> SelectionMask {
    _ = try Surface(width: width, height: height)
    try path.validate()
    if path.isEmpty {
      let value: UInt8 = (emptyRevealsAll != path.inverted) ? 255 : 0
      return try SelectionMask(
        width: width, height: height,
        bytes: [UInt8](repeating: value, count: width * height))
    }
    guard
      let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue), let data = context.data
    else {
      throw CraftError.invalid("Could not rasterize the path.")
    }
    context.setShouldAntialias(antiAlias)
    context.setAllowsAntialiasing(antiAlias)
    context.translateBy(x: 0, y: Double(height))
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: -origin.x, y: -origin.y)
    context.setFillColor(gray: 1, alpha: 1)
    context.addPath(try filledPath(path))
    context.fillPath()
    var bytes = Array(
      UnsafeBufferPointer(
        start: data.assumingMemoryBound(to: UInt8.self),
        count: width * height))
    if path.inverted { for i in bytes.indices { bytes[i] = 255 - bytes[i] } }
    return try SelectionMask(width: width, height: height, bytes: bytes)
  }
}

/// Pixel and vector masks retain independent density/feather controls and multiply coverage.
public struct LayerMaskSampler: Sendable {
  private var pixel: MaskSampler?
  private var vector: MaskSampler?
  /// `pixelRegion` permits identity elision only for integer pixel-center renders.
  /// General callers (hit testing, for example) retain continuous edge coverage.
  public static func make(layer: Layer, document: CraftDocument, pixelRegion: IntRect? = nil) throws
    -> Self?
  {
    guard layer.mask != nil || layer.vectorMask != nil else { return nil }
    let sampler = try Self(layer: layer, document: document)
    if let region = pixelRegion,
      (sampler.pixel?.isIdentity(over: region) ?? true)
        && (sampler.vector?.isIdentity(over: region) ?? true)
    {
      return nil
    }
    return sampler
  }
  public init(layer: Layer, document: CraftDocument) throws {
    pixel = try layer.mask.map { _ in
      try MaskSampler(layer: layer, canvasSize: (document.width, document.height))
    }
    guard let mask = layer.vectorMask, mask.enabled else { return }
    try mask.validate()
    let pad = Int(ceil(mask.feather * 3))
    let width = document.width + 2 * pad
    let height = document.height + 2 * pad
    let coverage = try VectorRasterizer.coverage(
      mask.path, width: width, height: height,
      origin: PathPoint(-Double(pad), -Double(pad)), emptyRevealsAll: true)
    let outside: Float =
      mask.path.isEmpty ? (mask.path.inverted ? 0 : 1) : (mask.path.inverted ? 1 : 0)
    var surface = try Surface(
      width: width, height: height, depth: .u8,
      fill: Pixel(outside, outside, outside))
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let value = coverage.coverage(x: x, y: y)
        if value != outside { surface.setPixel(x: x, y: y, Pixel(value, value, value)) }
      }
    }
    var prepared = Layer(name: "Vector coverage", content: .fill(.clear))
    prepared.x = -pad
    prepared.y = -pad
    prepared.mask = surface
    var properties = MaskProperties()
    properties.density = mask.density
    properties.feather = mask.feather
    properties.outside = outside
    prepared.maskProperties = properties
    vector = try MaskSampler(layer: prepared)
  }
  public func coverage(x: Double, y: Double) -> Float {
    (pixel?.coverage(x: x, y: y) ?? 1) * (vector?.coverage(x: x, y: y) ?? 1)
  }
}
