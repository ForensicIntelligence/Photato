import Foundation

/// The matrices before and after Warp operate on document coordinates.
public struct PathWarpRequest: Equatable, Sendable {
  public let choices: [PathTransformChoice]
  public let matrix: ProjectiveTransform
  public let settings: WarpDefinition
  public let matrixAfter: ProjectiveTransform

  public init(choices: [PathTransformChoice], matrix: ProjectiveTransform = .identity,
              settings: WarpDefinition, matrixAfter: ProjectiveTransform = .identity) {
    self.choices = choices
    self.matrix = matrix
    self.settings = settings
    self.matrixAfter = matrixAfter
  }
}

public struct PathWarpEdit: Sendable {
  public let request: PathWarpRequest
  public let source: CraftDocument
  public let result: CraftDocument
  public let geometry: [PathTransformGeometry]
  private let warpedGeometry: [PathTransformGeometry]

  public static func prepare(_ request: PathWarpRequest, in source: CraftDocument) throws -> Self {
    let warped = try PathWarp.warpGeometry(request, in: source)
    return try finish(request, warped: warped, source: source)
  }

  /// Apply an additional transform while keeping the fitted Warp curves as the input.
  public func followed(by delta: ProjectiveTransform) throws -> Self {
    if delta == .identity { return self }
    let after = try request.matrixAfter == .identity ? delta : request.matrixAfter.followed(by: delta)
    let combined = PathWarpRequest(choices: request.choices, matrix: request.matrix,
                                   settings: request.settings, matrixAfter: after)
    return try Self.finish(combined, warped: warpedGeometry, source: source)
  }

  public func bounds() throws -> IntRect { try PathTransform.bounds(geometry) }

  private static func finish(_ request: PathWarpRequest, warped: [PathTransformGeometry],
                             source: CraftDocument) throws -> Self {
    let geometry = try PathWarp.finishGeometry(warped, matrix: request.matrixAfter)
    var result = source
    try PathTransform.install(geometry, in: &result)
    return .init(request: request, source: source, result: result, geometry: geometry, warpedGeometry: warped)
  }

  func applied(to document: CraftDocument) throws -> CraftDocument {
    guard document == source else { throw CraftError.invalid("The path Warp source changed.") }
    return result
  }
}

public enum PathWarp {
  public static func sourceBounds(_ choices: [PathTransformChoice], matrix: ProjectiveTransform,
                                  in document: CraftDocument) throws -> WarpSourceBounds {
    let box: IntRect
    if matrix == .identity {
      box = try PathTransform.bounds(choices, in: document)
    } else {
      box = try PathTransform.bounds(PathTransform.geometry(.init(choices: choices, matrix: matrix), in: document))
    }
    return frame(box)
  }

  public static func geometry(_ request: PathWarpRequest, in document: CraftDocument) throws -> [PathTransformGeometry] {
    try finishGeometry(warpGeometry(request, in: document), matrix: request.matrixAfter)
  }

  fileprivate static func warpGeometry(_ request: PathWarpRequest, in document: CraftDocument) throws -> [PathTransformGeometry] {
    var settings = request.settings
    try settings.validate()
    let projected = try PathTransform.geometry(.init(choices: request.choices, matrix: request.matrix), in: document)
    if settings.isIdentity { return projected }
    let bounds = try settings.sourceBounds ?? frame(PathTransform.bounds(projected))
    settings.sourceBounds = bounds
    if let mesh = settings.mesh, identity(mesh, bounds: bounds),
       try frame(PathTransform.bounds(projected)) == bounds { return projected }
    let warp = VectorPathWarp(settings: settings, bounds: bounds)
    return try projected.map { item in
      let (path, selection) = try warp.apply(item.path, selection: item.choice.selection)
      return .init(choice: .init(item.choice.target, selection: selection), path: path, original: item.original)
    }
  }

  fileprivate static func finishGeometry(_ warped: [PathTransformGeometry], matrix: ProjectiveTransform) throws -> [PathTransformGeometry] {
    if matrix == .identity { return warped }
    if warped.count > 1, try matrix.affineValue() == nil {
      let bounds = try PathTransform.bounds(warped)
      try matrix.validateSharedHorizon(left: bounds.x, top: bounds.y,
                                       right: bounds.x + bounds.width, bottom: bounds.y + bounds.height)
    }
    return try warped.map { item in
      let transformed = try PathTransform.geometry(item.path, selection: item.choice.selection, matrix: matrix)
      return .init(choice: .init(item.choice.target, selection: transformed.selection),
                   path: transformed.path, original: item.original)
    }
  }

  private static func frame(_ box: IntRect) -> WarpSourceBounds {
    .init(x: Double(box.x), y: Double(box.y), width: Double(box.width), height: Double(box.height))
  }

  private static func identity(_ mesh: WarpMesh, bounds: WarpSourceBounds) -> Bool {
    func coordinates(_ knots: [Double], origin: Double, width: Double) -> [Double] {
      var result: [Double] = []
      for (start, end) in zip(knots, knots.dropFirst()) {
        for column in 0..<3 {
          let fraction = Double(column) / 3
          let coordinate = start + (end - start) * fraction
          result.append(origin + coordinate * width)
        }
      }
      result.append(origin + width)
      return result
    }
    let xs = coordinates(mesh.us, origin: bounds.x, width: bounds.width)
    let ys = coordinates(mesh.vs, origin: bounds.y, width: bounds.height)
    return mesh.points.enumerated().allSatisfy { index, point in
      abs(point.x - xs[index % xs.count]) <= 1e-8 && abs(point.y - ys[index / xs.count]) <= 1e-8
    }
  }
}

private struct VectorPathWarp {
  private typealias Point = SIMD2<Double>
  let settings: WarpDefinition
  let bounds: WarpSourceBounds

  func apply(_ path: VectorPath, selection: PathTransformSelection) throws -> (VectorPath, PathTransformSelection) {
    let selected = try selection.indices(in: path)
    var result = path
    var remaining = VectorPath.maxKnots - path.knotCount
    var anchors: [PathTransformAnchor] = []
    for componentIndex in path.components.indices where !selected[componentIndex].isEmpty {
      try Task.checkCancellation()
      let source = path.components[componentIndex]
      let indices = selected[componentIndex]
      func mappedKnot(_ index: Int) throws -> PathKnot {
        let knot = source.knots[index]
        guard indices.contains(index) else { return knot }
        let anchor = point(knot.anchor)
        let destination = try map(anchor)
        return PathKnot(pathPoint(destination),
                        incoming: pathPoint(try handle(point(knot.incoming), at: anchor, to: destination)),
                        outgoing: pathPoint(try handle(point(knot.outgoing), at: anchor, to: destination)),
                        smooth: knot.smooth)
      }
      var knots = [try mappedKnot(0)]
      if indices.contains(0) { anchors.append(.init(component: componentIndex, knot: 0)) }
      let segments = source.knots.count > 1 ? source.knots.count - (source.closed ? 0 : 1) : 0
      for index in 0..<segments {
        try Task.checkCancellation()
        let next = (index + 1) % source.knots.count
        let closing = next == 0
        let selectedEdge = indices.contains(index) && indices.contains(next)
        guard selectedEdge else {
          if !closing {
            if indices.contains(next) { anchors.append(.init(component: componentIndex, knot: knots.count)) }
            knots.append(try mappedKnot(next))
          }
          continue
        }
        let a = source.knots[index], b = source.knots[next]
        let cubic = Cubic(point(a.anchor), point(a.outgoing), point(b.incoming), point(b.anchor))
        let pieces = try fit(cubic, limit: remaining + 1)
        for (pieceIndex, piece) in pieces.enumerated() {
          let last = pieceIndex == pieces.count - 1
          knots[knots.count - 1].outgoing = pathPoint(piece.b)
          if last && closing {
            knots[0].incoming = pathPoint(piece.c)
          } else {
            anchors.append(.init(component: componentIndex, knot: knots.count))
            var end = try last ? mappedKnot(next) : PathKnot(pathPoint(piece.d))
            end.incoming = pathPoint(piece.c)
            knots.append(end)
          }
        }
        remaining -= pieces.count - 1
      }
      result.components[componentIndex].knots = knots
    }
    try result.validate()
    if case .anchors = selection { return (result, .anchors(anchors)) }
    return (result, selection)
  }

  private struct Cubic {
    let a: Point, b: Point, c: Point, d: Point
    init(_ a: Point, _ b: Point, _ c: Point, _ d: Point) {
      self.a = a
      self.b = b
      self.c = c
      self.d = d
    }

    func at(_ t: Double) -> Point {
      let u = 1 - t
      return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
    }

    /// Partition into monotone intervals before looking for split knots. A curve may cross one mesh line three times.
    func crossings(_ levels: [Double], axis: Int) -> [Double] {
      let coordinates = [a[axis], b[axis], c[axis], d[axis]]
      let first = coordinates[1] - coordinates[0]
      let second = coordinates[2] - coordinates[1]
      let third = coordinates[3] - coordinates[2]
      let quadratic = first - 2 * second + third, linear = 2 * (second - first)
      var extrema: [Double] = []
      if quadratic == 0 {
        if linear != 0 { extrema.append(-first / linear) }
      } else {
        let discriminant = linear * linear - 4 * quadratic * first
        if discriminant >= 0 {
          let root = sqrt(discriminant)
          let stable = -0.5 * (linear + (linear.sign == .minus ? -root : root))
          extrema = stable == 0 ? [-linear / (2 * quadratic)] : [stable / quadratic, first / stable]
        }
      }
      let cuts = [0] + extrema.filter { 0 < $0 && $0 < 1 }.sorted() + [1]
      var crossings: [Double] = []
      for (start, end) in zip(cuts, cuts.dropFirst()) {
        let atStart = at(start)[axis], atEnd = at(end)[axis]
        let minimum = min(atStart, atEnd), maximum = max(atStart, atEnd)
        for level in levels where minimum <= level && level <= maximum {
          if atStart == level { crossings.append(start); continue }
          if atEnd == level { crossings.append(end); continue }
          var left = start, right = end
          let increasing = atStart < atEnd
          for _ in 0..<48 {
            let middle = (left + right) / 2
            if (at(middle)[axis] < level) == increasing { left = middle } else { right = middle }
          }
          crossings.append((left + right) / 2)
        }
      }
      return crossings
    }
  }

  private func fit(_ input: Cubic, limit: Int) throws -> [Cubic] {
    var cuts = [0.0, 1.0]
    if let mesh = settings.mesh {
      cuts += input.crossings(mesh.us.map { bounds.x + $0 * bounds.width }, axis: 0)
      cuts += input.crossings(mesh.vs.map { bounds.y + $0 * bounds.height }, axis: 1)
    }
    var pieces: [Cubic] = []
    let mapped: (Double) throws -> Point = { try map(input.at($0)) }
    let boundaries = cuts.sorted().reduce(into: [Double]()) { values, next in
      if let last = values.last, next - last <= 1e-12 {
        if next == 1 { values[values.count - 1] = next }
      } else { values.append(next) }
    }
    for (start, end) in zip(boundaries, boundaries.dropFirst()) {
      try fit(mapped, from: start, to: end, depth: 0, limit: limit, pieces: &pieces)
    }
    return pieces
  }

  private func fit(_ mapped: (Double) throws -> Point, from start: Double, to end: Double,
                   depth: Int, limit: Int, pieces: inout [Cubic]) throws {
    try Task.checkCancellation()
    guard pieces.count < limit else { throw CraftError.invalid("Warp exceeds the editable path knot limit.") }
    let a = try mapped(start), d = try mapped(end)
    let span = end - start
    let step = span / 1024
    // One-sided derivatives keep each patch's tangent at a split, including a cusp.
    let b = a + (try derivative(mapped, at: start, point: a, step: step)) * (1024.0 / 3)
    let c = d + (try derivative(mapped, at: end, point: d, step: -step)) * (1024.0 / 3)
    let candidate = Cubic(a, b, c, d)
    var withinTolerance = supported(b) && supported(c)
    if withinTolerance {
      for i in 1..<16 {
        let fraction = Double(i) / 16
        let difference = try mapped(start + fraction * span) - candidate.at(fraction)
        if hypot(difference.x, difference.y) > 1.0 / 128 {
          withinTolerance = false
          break
        }
      }
    }
    if withinTolerance { pieces.append(candidate); return }
    guard depth < 20 else { throw CraftError.invalid("Warp could not fit editable path curves at the required precision.") }
    let middle = start + span * 0.5
    try fit(mapped, from: start, to: middle, depth: depth + 1, limit: limit, pieces: &pieces)
    try fit(mapped, from: middle, to: end, depth: depth + 1, limit: limit, pieces: &pieces)
  }

  private func derivative(_ f: (Double) throws -> Point, at t: Double, point: Point, step: Double) throws -> Point {
    let one = try f(t + step) - point
    let two = try f(t + 2 * step) - point
    let three = try f(t + 3 * step) - point
    return 3 * one - 1.5 * two + three / 3
  }

  private func handle(_ handle: Point, at anchor: Point, to destination: Point) throws -> Point {
    if handle == anchor { return destination }
    let alongHandle: (Double) throws -> Point = { try map(anchor + (handle - anchor) * $0) }
    return destination + (try derivative(alongHandle, at: 0, point: destination, step: 1.0 / 1024)) * 1024
  }

  private func map(_ value: Point) throws -> Point {
    let mapped = point(settings.point(value.x, value.y, width: bounds.width, height: bounds.height))
    guard supported(mapped) else { throw CraftError.invalid("Warp exceeds the supported path coordinates.") }
    return mapped
  }

  private func supported(_ value: Point) -> Bool {
    abs(value.x) <= 1_000_000 && abs(value.y) <= 1_000_000
  }

  private func point(_ value: PathPoint) -> Point { .init(value.x, value.y) }
  private func pathPoint(_ value: Point) -> PathPoint { .init(value.x, value.y) }
}
