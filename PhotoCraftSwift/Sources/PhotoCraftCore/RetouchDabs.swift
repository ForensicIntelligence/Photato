import Foundation

/// Carried spacing is retained across input batches. A complete stroke and any
/// partition of that stroke emit the same ordered round-tip dabs.
struct RetouchDabGenerator {
  private var previous: StrokePoint?
  private var next = 0.0
  private var count = 0
  mutating func append(_ points: [StrokePoint], brush: CloneBrush,
    body: (StrokePoint) throws -> Void) throws {
    func step(_ p: StrokePoint) -> Double {
      max(0.5, brush.size * (brush.pressureSize ? Double(p.pressure) : 1) * brush.spacing)
    }
    for point in points {
      guard let previous else {
        try emit(point, body: body); next = step(point); self.previous = point; continue
      }
      let distance = hypot(point.x - previous.x, point.y - previous.y)
      if distance > 1e-9 {
        while next <= distance + 1e-9 {
          let t = min(1, next / distance)
          let q = StrokePoint(x: previous.x + (point.x - previous.x) * t,
            y: previous.y + (point.y - previous.y) * t,
            pressure: previous.pressure + (point.pressure - previous.pressure) * Float(t))
          try emit(q, body: body); next += step(q)
        }
        next -= distance
      }
      self.previous = point
    }
  }
  private mutating func emit(_ point: StrokePoint, body: (StrokePoint) throws -> Void) throws {
    try Task.checkCancellation(); count += 1
    guard count <= 200_000 else { throw CraftError.invalid("Retouching stroke is too long.") }
    try body(point)
  }
}

enum RetouchDabs {
  static func forEach(brush: CloneBrush, points: [StrokePoint], body: (StrokePoint) throws -> Void) throws {
    var generator = RetouchDabGenerator()
    try generator.append(points, brush: brush, body: body)
  }
}
