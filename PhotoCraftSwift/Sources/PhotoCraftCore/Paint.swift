import Foundation

public struct StrokePoint: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var pressure: Float
  public init(x: Double, y: Double, pressure: Float = 1) {
    self.x = x
    self.y = y
    self.pressure = pressure
  }
}
public struct Brush: Codable, Equatable, Sendable {
  public var size: Double = 30
  public var hardness: Float = 0.8
  public var opacity: Float = 1
  public var color: Pixel = Pixel(0.3, 0.45, 0.95)
  public var erase = false
  public init() {}
}
public enum Painter {
  public static func stroke(
    surface: inout Surface, points: [StrokePoint], brush: Brush, selection: IntRect? = nil,
    selectionMask: SelectionMask? = nil, offsetX: Int = 0, offsetY: Int = 0,
    transform: Transform2D? = nil, grayscaleMask: Bool = false
  ) throws {
    guard brush.size.isFinite, (0.5...2048).contains(brush.size), brush.hardness.isFinite,
      (0...1).contains(brush.hardness), brush.opacity.isFinite, (0...1).contains(brush.opacity),
      brush.color.isFinite, points.count <= 100_000
    else { throw CraftError.invalid("Invalid brush settings or stroke size.") }
    for p in points {
      guard p.x.isFinite, p.y.isFinite, abs(p.x) <= 1_000_000, abs(p.y) <= 1_000_000,
        p.pressure.isFinite, (0...1).contains(p.pressure)
      else { throw CraftError.invalid("Invalid stroke sample.") }
    }
    let matrix = transform ?? .translation(Double(offsetX), Double(offsetY))
    let inverse = try matrix.inverted()
    let original = surface
    var coverage: [Int: Float] = [:]
    func dab(_ p: StrokePoint) {
      guard p.pressure > 0 else { return }
      let radius = max(0.25, brush.size * Double(p.pressure) / 2)
      let center = inverse.point(p.x, p.y)
      let rx = radius * hypot(inverse.a, inverse.c)
      let ry = radius * hypot(inverse.b, inverse.d)
      let x0 = Int(max(0, min(Double(surface.width), floor(center.x - rx))))
      let x1 = Int(max(-1, min(Double(surface.width - 1), ceil(center.x + rx))))
      let y0 = Int(max(0, min(Double(surface.height), floor(center.y - ry))))
      let y1 = Int(max(-1, min(Double(surface.height - 1), ceil(center.y + ry))))
      guard x0 <= x1, y0 <= y1 else { return }
      for y in y0...y1 {
        for x in x0...x1 {
          let point = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
          let dx = Int(floor(point.x))
          let dy = Int(floor(point.y))
          if let selection, !selection.contains(dx, dy) { continue }
          let selectionCoverage = selectionMask?.coverage(x: dx, y: dy) ?? 1
          guard selectionCoverage > 0 else { continue }
          let d = Float(hypot(point.x - p.x, point.y - p.y) / radius)
          guard d <= 1 else { continue }
          let edge =
            brush.hardness >= 0.999
            ? Float(min(1, max(0, (1 - Double(d)) * radius + 0.5)))
            : unit((1 - d) / max(0.001, 1 - brush.hardness))
          let key = y * surface.width + x
          let alpha = max(
            coverage[key] ?? 0, edge * brush.opacity * brush.color.a * selectionCoverage)
          coverage[key] = alpha
          var before = original.pixel(x: x, y: y)
          if grayscaleMask {
            let v = unit(before.r)
            before = Pixel(v, v, v)
          }
          if brush.erase {
            surface.setPixel(
              x: x, y: y, Pixel(before.r, before.g, before.b, before.a * (1 - alpha)))
          } else {
            var ink = brush.color
            ink.a = alpha
            surface.setPixel(x: x, y: y, BlendMode.normal.composite(backdrop: before, source: ink))
          }
        }
      }
    }
    guard let first = points.first else { return }
    dab(first)
    var previous = first
    var dabCount = 1
    for p in points.dropFirst() {
      let distance = hypot(p.x - previous.x, p.y - previous.y)
      let count = max(1, Int(ceil(distance / max(0.5, brush.size * 0.12))))
      dabCount += count
      guard dabCount <= 200_000 else { throw CraftError.invalid("Stroke is too long.") }
      for i in 1...count {
        let t = Double(i) / Double(count)
        dab(
          StrokePoint(
            x: previous.x + (p.x - previous.x) * t, y: previous.y + (p.y - previous.y) * t,
            pressure: previous.pressure + (p.pressure - previous.pressure) * Float(t)))
      }
      previous = p
    }
  }
}
