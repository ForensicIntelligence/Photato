import CoreGraphics
import Foundation

/// Common native vector construction used by image coverage and shape kernels.
public enum VectorPathGeometry {
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
}
