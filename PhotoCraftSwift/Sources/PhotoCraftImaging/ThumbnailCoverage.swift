import Foundation
import PhotoCraftCore

/// Integrates premultiplied pixel coverage for minified previews. This is preview-only:
/// it does not change the editor's image-resampling or document rendering algorithms.
struct ThumbnailCoverage {
  enum Channels {
    case rgba
    /// Mask previews show editable grayscale values regardless of the surface alpha.
    case mask(outside: Float, inverted: Bool)
  }
  struct Point {
    var x: Double
    var y: Double
  }
  let mapping: Transform2D
  let minifies: Bool
  let axisAligned: Bool
  let area: Double
  let channels: Channels
  private(set) var remainingSamples: Int

  init(mapping: Transform2D, channels: Channels = .rgba, maximumSamples: Int = 128_000_000) {
    self.mapping = mapping
    self.channels = channels
    remainingSamples = max(0, maximumSamples)
    let xx = mapping.a * mapping.a + mapping.b * mapping.b
    let yy = mapping.c * mapping.c + mapping.d * mapping.d
    let xy = mapping.a * mapping.c + mapping.b * mapping.d
    let largest = (xx + yy + hypot(xx - yy, 2 * xy)) / 2
    minifies = largest > 1 + 1e-9
    axisAligned = (mapping.b == 0 && mapping.c == 0) || (mapping.a == 0 && mapping.d == 0)
    area = abs(mapping.a * mapping.d - mapping.b * mapping.c)
  }

  mutating func sample(_ source: Surface, x: Int, y: Int) throws -> Pixel {
    if !minifies {
      let p = mapping.point(Double(x) + 0.5, Double(y) + 0.5)
      switch channels {
      case .rgba: return RasterGeometry.sample(source, x: p.x, y: p.y, method: .bilinear)
      case .mask(let outside, let inverted):
        let raw = unit(MaskSampler.sample(source, x: p.x, y: p.y, outside: outside))
        let v = inverted ? 1 - raw : raw
        return Pixel(v, v, v)
      }
    }
    func point(_ x: Double, _ y: Double) -> Point {
      let p = mapping.point(x, y)
      return Point(x: p.x, y: p.y)
    }
    let x = Double(x)
    let y = Double(y)
    if axisAligned {
      let a = point(x, y)
      let b = point(x + 1, y + 1)
      return try rectangle(
        source, left: min(a.x, b.x), top: min(a.y, b.y),
        right: max(a.x, b.x), bottom: max(a.y, b.y))
    }
    var polygon = [point(x, y), point(x + 1, y), point(x + 1, y + 1), point(x, y + 1)]
    polygon = Self.clip(polygon, axisX: true, edge: 0, keepGreater: true)
    polygon = Self.clip(polygon, axisX: true, edge: Double(source.width), keepGreater: false)
    polygon = Self.clip(polygon, axisX: false, edge: 0, keepGreater: true)
    polygon = Self.clip(polygon, axisX: false, edge: Double(source.height), keepGreater: false)
    guard polygon.count >= 3 else { return outsidePixel }
    let covered = Self.polygonArea(polygon)
    let background = Self.premultiplied(outsidePixel) * max(0, area - covered)
    if source.tileCount == 0 {
      return Self.pixel(
        Self.premultiplied(displayPixel(source.defaultPixel)) * covered + background, area: area)
    }
    let top = max(0, Int(floor(polygon.map(\.y).min()!)))
    let bottom = min(source.height, Int(ceil(polygon.map(\.y).max()!)))
    var sum = background
    for sy in top..<bottom {
      try Task.checkCancellation()
      var strip = Self.clip(polygon, axisX: false, edge: Double(sy), keepGreater: true)
      strip = Self.clip(strip, axisX: false, edge: Double(sy + 1), keepGreater: false)
      guard strip.count >= 3 else { continue }
      let left = max(0, Int(floor(strip.map(\.x).min()!)))
      let right = min(source.width, Int(ceil(strip.map(\.x).max()!)))
      try reserve(max(0, right - left))
      for sx in left..<right {
        let p = displayPixel(source.pixel(x: sx, y: sy))
        guard p.a > 0 else { continue }
        var cell = Self.clip(strip, axisX: true, edge: Double(sx), keepGreater: true)
        cell = Self.clip(cell, axisX: true, edge: Double(sx + 1), keepGreater: false)
        sum += Self.premultiplied(p) * Self.polygonArea(cell)
      }
    }
    return Self.pixel(sum, area: area)
  }

  private mutating func rectangle(
    _ source: Surface, left: Double, top: Double, right: Double, bottom: Double
  ) throws -> Pixel {
    if case .rgba = channels, source.width * source.height > Surface.maximumDensePixels {
      let sampled = try source.sparseAreaSample(left: left, top: top, right: right, bottom: bottom, maximumSamples: remainingSamples)
      remainingSamples -= sampled.samples
      return sampled.pixel
    }
    let left = max(0, left)
    let top = max(0, top)
    let right = min(Double(source.width), right)
    let bottom = min(Double(source.height), bottom)
    guard right > left, bottom > top else { return outsidePixel }
    let covered = (right - left) * (bottom - top)
    let background = Self.premultiplied(outsidePixel) * max(0, area - covered)
    if source.tileCount == 0 {
      return Self.pixel(
        Self.premultiplied(displayPixel(source.defaultPixel)) * covered + background, area: area)
    }
    let x0 = Int(floor(left))
    let x1 = Int(ceil(right))
    let y0 = Int(floor(top))
    let y1 = Int(ceil(bottom))
    var sum = background
    for sy in y0..<y1 {
      try Task.checkCancellation()
      try reserve(x1 - x0)
      let dy = min(bottom, Double(sy + 1)) - max(top, Double(sy))
      for sx in x0..<x1 {
        let dx = min(right, Double(sx + 1)) - max(left, Double(sx))
        sum += Self.premultiplied(displayPixel(source.pixel(x: sx, y: sy))) * (dx * dy)
      }
    }
    return Self.pixel(sum, area: area)
  }

  private mutating func reserve(_ count: Int) throws {
    guard count <= remainingSamples else {
      throw CraftError.invalid("This thumbnail transform exceeds the preview sampling budget.")
    }
    remainingSamples -= count
  }
  private var outsidePixel: Pixel {
    switch channels {
    case .rgba: return .clear
    case .mask(let outside, let inverted):
      let value = inverted ? 1 - unit(outside) : unit(outside)
      return Pixel(value, value, value)
    }
  }
  private func displayPixel(_ p: Pixel) -> Pixel {
    switch channels {
    case .rgba: return p
    case .mask(_, let inverted):
      let value = inverted ? 1 - unit(p.r) : unit(p.r)
      return Pixel(value, value, value)
    }
  }
  private static func premultiplied(_ p: Pixel) -> SIMD4<Double> {
    let alpha = Double(p.a)
    return SIMD4(Double(p.r) * alpha, Double(p.g) * alpha, Double(p.b) * alpha, alpha)
  }
  private static func pixel(_ sum: SIMD4<Double>, area: Double) -> Pixel {
    guard sum.w > 0, area > 0 else { return .clear }
    return Pixel(
      Float(sum.x / sum.w), Float(sum.y / sum.w), Float(sum.z / sum.w), Float(min(1, sum.w / area)))
  }
  private static func polygonArea(_ points: [Point]) -> Double {
    guard points.count >= 3 else { return 0 }
    let origin = points[0]
    var twice = 0.0
    for index in 1..<(points.count - 1) {
      let a = points[index]
      let b = points[index + 1]
      twice += (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
    }
    return abs(twice) / 2
  }
  private static func clip(_ input: [Point], axisX: Bool, edge: Double, keepGreater: Bool)
    -> [Point]
  {
    guard var previous = input.last else { return [] }
    func coordinate(_ p: Point) -> Double { axisX ? p.x : p.y }
    func inside(_ p: Point) -> Bool { keepGreater ? coordinate(p) >= edge : coordinate(p) <= edge }
    var wasInside = inside(previous)
    var output: [Point] = []
    output.reserveCapacity(input.count + 1)
    for current in input {
      let isInside = inside(current)
      if isInside != wasInside {
        let t = (edge - coordinate(previous)) / (coordinate(current) - coordinate(previous))
        output.append(
          axisX
            ? Point(x: edge, y: previous.y + t * (current.y - previous.y))
            : Point(x: previous.x + t * (current.x - previous.x), y: edge))
      }
      if isInside { output.append(current) }
      previous = current
      wasInside = isInside
    }
    return output
  }
}
