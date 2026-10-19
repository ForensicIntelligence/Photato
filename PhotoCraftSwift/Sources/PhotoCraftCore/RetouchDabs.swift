import Foundation

/// Carried-spacing round-tip sequence shared by the native retouch tools.
/// Advanced PhotoCraft/Photoshop brush dynamics and timed airbrush dabs remain separate work.
enum RetouchDabs {
  static func forEach(brush: CloneBrush, points: [StrokePoint], body: (StrokePoint) throws -> Void)
    throws
  {
    guard !points.isEmpty else { return }
    var count = 0
    func emit(_ point: StrokePoint) throws {
      try Task.checkCancellation()
      count += 1
      guard count <= 200_000 else { throw CraftError.invalid("Retouching stroke is too long.") }
      try body(point)
    }
    func step(_ p: StrokePoint) -> Double {
      max(0.5, brush.size * (brush.pressureSize ? Double(p.pressure) : 1) * brush.spacing)
    }
    let first = points[0]
    try emit(first)
    var previous = first
    var next = step(first)
    for p in points.dropFirst() {
      let distance = hypot(p.x - previous.x, p.y - previous.y)
      if distance > 1e-9 {
        while next <= distance + 1e-9 {
          let t = min(1, next / distance)
          let q = StrokePoint(
            x: previous.x + (p.x - previous.x) * t, y: previous.y + (p.y - previous.y) * t,
            pressure: previous.pressure + (p.pressure - previous.pressure) * Float(t))
          try emit(q)
          next += step(q)
        }
        next -= distance
      }
      previous = p
    }
  }
}
