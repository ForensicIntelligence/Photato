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
    let region = try resolve(path)
    guard !region.inverted else {
      throw CraftError.unsupported("This path has an unbounded filled exterior; use vector coverage instead of a finite shape outline.")
    }
    return region.path
  }
  /// A complemented region remains unbounded without adding a synthetic canvas
  /// rectangle or rewriting the user's editable knots and component order.
  public struct FilledRegion {
    public let path: CGPath
    public let inverted: Bool
  }
  public static func filledRegion(_ path: VectorPath) throws -> FilledRegion {
    let region = try resolve(path)
    return FilledRegion(path: region.path, inverted: region.inverted != path.inverted)
  }
  /// PSD stores even/odd contours, without an editable winding-rule field.
  /// Keep equivalent native rules unchanged and detect real transport loss.
  public static func fillRulesDiffer(_ path: VectorPath) throws -> Bool {
    var winding = path
    winding.fillRule = .nonZero
    var evenOdd = path
    evenOdd.fillRule = .evenOdd
    let a = try resolve(winding), b = try resolve(evenOdd)
    return a.inverted != b.inverted || !a.path.symmetricDifference(b.path).isEmpty
  }
  private static func resolve(_ path: VectorPath) throws -> FilledRegion {
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
    guard let first = groups.first else {
      return FilledRegion(path: CGMutablePath(), inverted: false)
    }
    var result = first.1.normalized(using: rule)
    var inverted = first.0 == .subtract
    for (operation, raw) in groups.dropFirst() {
      try Task.checkCancellation()
      let next = raw.normalized(using: rule)
      if inverted {
        switch operation {
        case .combine, .join: result = result.subtracting(next)
        case .subtract: result = result.union(next)
        case .intersect:
          result = next.subtracting(result)
          inverted = false
        case .exclude: result = result.symmetricDifference(next)
        }
      } else {
        switch operation {
        case .combine, .join: result = result.union(next)
        case .subtract: result = result.subtracting(next)
        case .intersect: result = result.intersection(next)
        case .exclude: result = result.symmetricDifference(next)
        }
      }
    }
    return FilledRegion(path: result, inverted: inverted)
  }
}
