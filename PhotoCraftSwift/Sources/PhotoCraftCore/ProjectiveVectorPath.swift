import Foundation

/// Converts a homography's rational cubics to editable native and PSD path knots.
enum ProjectiveVectorPath {
  static let tolerance = 1.0 / 64
  private static let maximumDepth = 24
  private typealias Point = SIMD2<Double>
  private typealias HomogeneousPoint = SIMD3<Double>

  static func apply(_ path: VectorPath, matrix: ProjectiveTransform) throws -> VectorPath {
    try path.validate()
    let scale = matrix.values.map(abs).max()!
    let m = matrix.values.map { $0 / scale }
    func map(_ p: PathPoint) -> HomogeneousPoint {
      .init(
        m[0] * p.x + m[1] * p.y + m[2],
        m[3] * p.x + m[4] * p.y + m[5],
        m[6] * p.x + m[7] * p.y + m[8])
    }

    var result = path
    var remaining = VectorPath.maxKnots
    for index in path.components.indices {
      try Task.checkCancellation()
      let source = path.components[index]
      guard let first = source.knots.first else { continue }
      guard remaining > 0 else { throw knotLimit }
      remaining -= 1
      let start = map(first.anchor)
      let beginning = try position(start)
      var knots = [PathKnot(pathPoint(beginning), smooth: first.smooth)]
      if !source.closed || source.knots.count == 1 {
        knots[0].incoming = pathPoint(tangentHandle(map(first.incoming), at: start, position: beginning))
      }
      if source.knots.count == 1 {
        knots[0].outgoing = pathPoint(tangentHandle(map(first.outgoing), at: start, position: beginning))
      }
      if source.knots.count > 1 {
        let segmentCount = source.closed ? source.knots.count : source.knots.count - 1
        for segment in 0..<segmentCount {
          let nextIndex = (segment + 1) % source.knots.count
          let a = source.knots[segment], b = source.knots[nextIndex]
          let closing = nextIndex == 0
          let control = [map(a.anchor), map(a.outgoing), map(b.incoming), map(b.anchor)]
          let epsilon = max(Double.leastNormalMagnitude, control.map { abs($0.z) }.max()! * 1e-12)
          var pieces: [[Point]] = []
          try fit(
            control, epsilon: epsilon, depth: 0, limit: remaining + (closing ? 1 : 0),
            pieces: &pieces)
          for (pieceIndex, piece) in pieces.enumerated() {
            let last = pieceIndex == pieces.count - 1
            knots[knots.count - 1].outgoing = pathPoint(piece[1])
            if last && closing {
              knots[0].incoming = pathPoint(piece[2])
            } else {
              knots.append(PathKnot(pathPoint(piece[3]), incoming: pathPoint(piece[2]),
                                    smooth: last ? b.smooth : true))
              remaining -= 1
            }
          }
        }
        if !source.closed, let last = source.knots.last {
          let endpoint = map(last.anchor)
          let position = try self.position(endpoint)
          knots[knots.count - 1].outgoing = pathPoint(
            tangentHandle(map(last.outgoing), at: endpoint, position: position))
        }
      }
      result.components[index].knots = knots
    }
    try result.validate()
    return result
  }

  private static var knotLimit: CraftError {
    .invalid("The projected vector mask exceeds the editable path knot limit.")
  }

  private static var horizon: CraftError {
    .invalid("The projective horizon crosses the linked vector mask.")
  }

  private static func fit(
    _ c: [HomogeneousPoint], epsilon: Double, depth: Int, limit: Int, pieces: inout [[Point]]
  ) throws {
    try Task.checkCancellation()
    guard pieces.count < limit else { throw knotLimit }
    let firstWeight = c[0].z, lastWeight = c[3].z
    guard abs(firstWeight) > epsilon, abs(lastWeight) > epsilon,
          firstWeight.sign == lastWeight.sign else { throw horizon }
    let p0 = try position(c[0]), p3 = try position(c[3])

    if c.allSatisfy({ abs($0.z) > epsilon && $0.z.sign == firstWeight.sign }) {
      // Repeated endpoint controls yield exactly the same straight edge under projection.
      if c[0] == c[1] && c[2] == c[3] {
        pieces.append([p0, p0, p3, p3])
        return
      }
      let p1 = tangentHandle(c[1], at: c[0], position: p0)
      let p2 = tangentHandle(c[2], at: c[3], position: p3)
      let cubic = [p0, p1, p2, p3]
      if supported(p1), supported(p2), boundedError(c, cubic: cubic) <= tolerance {
        pieces.append(cubic)
        return
      }
    }

    guard depth < maximumDepth else {
      throw CraftError.invalid("The linked vector mask could not be projected as an editable path at the required precision.")
    }
    let a = (c[0] + c[1]) * 0.5, b = (c[1] + c[2]) * 0.5, d = (c[2] + c[3]) * 0.5
    let e = (a + b) * 0.5, f = (b + d) * 0.5
    let midpoint = (e + f) * 0.5
    guard abs(midpoint.z) > epsilon, midpoint.z.sign == firstWeight.sign else { throw horizon }
    try fit([c[0], a, e, midpoint], epsilon: epsilon, depth: depth + 1, limit: limit, pieces: &pieces)
    try fit([midpoint, f, d, c[3]], epsilon: epsilon, depth: depth + 1, limit: limit, pieces: &pieces)
  }

  /// With one sign of W, its smallest absolute Bernstein coefficient bounds
  /// the denominator from below. The degree-six coefficients of N - WQ
  /// bound the numerator because the Bernstein basis is a partition of unity.
  private static func boundedError(_ c: [HomogeneousPoint], cubic: [Point]) -> Double {
    let origin = cubic[0]
    let points = cubic.map { $0 - origin }
    let numerators = c.map { Point($0.x, $0.y) - origin * $0.z }
    let degreeThree = [1.0, 3, 3, 1]
    let degreeSix = [1.0, 6, 15, 20, 15, 6, 1]
    var coefficients = Array(repeating: Point.zero, count: 7)
    for i in 0..<4 {
      for j in 0..<4 {
        let weight = degreeThree[i] * degreeThree[j] / degreeSix[i + j]
        coefficients[i + j] += (numerators[i] - points[j] * c[i].z) * weight
      }
    }
    let minWeight = c.map { abs($0.z) }.min()!
    return coefficients.map { hypot($0.x, $0.y) }.max()! / minWeight
  }

  private static func position(_ h: HomogeneousPoint) throws -> Point {
    guard abs(h.z) > Double.leastNormalMagnitude else { throw horizon }
    let result = Point(h.x, h.y) / h.z
    guard supported(result) else {
      throw CraftError.invalid("The projected vector mask exceeds the supported coordinates.")
    }
    return result
  }

  /// One third of the rational cubic's endpoint derivative, added to the anchor.
  private static func tangentHandle(
    _ control: HomogeneousPoint, at endpoint: HomogeneousPoint, position: Point
  ) -> Point {
    position + (Point(control.x, control.y) - position * control.z) / endpoint.z
  }

  private static func supported(_ p: Point) -> Bool {
    abs(p.x) <= 1_000_000 && abs(p.y) <= 1_000_000
  }

  private static func pathPoint(_ p: Point) -> PathPoint { .init(p.x, p.y) }
}
