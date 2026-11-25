import Foundation

/// A rectangle in a rectified Vanishing Point plane. Bounds are plane fractions.
public struct VanishingMarquee: Codable, Equatable, Sendable {
  public var plane: Int
  public var lower: PathPoint
  public var upper: PathPoint

  public init(plane: Int, lower: PathPoint, upper: PathPoint) {
    self.plane = plane
    self.lower = lower
    self.upper = upper
  }

  public var center: PathPoint { lower.interpolated(to:upper,at:0.5) }
  var width: Double { upper.x-lower.x }
  var height: Double { upper.y-lower.y }
  var hasValidBounds: Bool {
    VanishingSettings.validPoint(lower) && VanishingSettings.validPoint(upper) && width > 0 && height > 0
  }

  public func translated(_ delta: PathPoint) -> Self {
    .init(plane:plane,lower:.init(lower.x+delta.x,lower.y+delta.y),upper:.init(upper.x+delta.x,upper.y+delta.y))
  }

  public func scaled(by factor: Double) -> Self {
    .init(plane:plane,lower:center.interpolated(to:lower,at:factor),upper:center.interpolated(to:upper,at:factor))
  }

  public func point(_ unit: PathPoint) -> PathPoint {
    .init(lower.x+unit.x*width,lower.y+unit.y*height)
  }

  /// Movement between planes keeps physical extent and the pointer's offset within the rectangle.
  public func moved(from: PathPoint, to: PathPoint, plane newPlane: Int, scene: VanishingScene,
    constrained: Bool = false, angle: Double = 0) -> Self?
  {
    guard scene.frames.indices.contains(plane),scene.frames.indices.contains(newPlane) else { return nil }
    let frame = scene.frames[plane], target = scene.frames[newPlane]
    if plane == newPlane {
      let a = frame.metric(from), b = frame.metric(to)
      var dx = b.x-a.x, dy = b.y-a.y
      if constrained {
        if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 }
      }
      let result = translated(.init(dx/frame.width,dy/frame.height))
      return result.projectedCorners(in:scene,angle:angle) == nil ? nil : result
    }

    let start = frame.uv(from), end = target.uv(to)
    let originalScale = scene.measurementMetric(for:plane), newScale = scene.measurementMetric(for:newPlane)
    let sx = originalScale.x/newScale.x, sy = originalScale.y/newScale.y
    let rect = Self(plane:newPlane,lower:.init(end.x+(lower.x-start.x)*sx,end.y+(lower.y-start.y)*sy),
      upper:.init(end.x+(upper.x-start.x)*sx,end.y+(upper.y-start.y)*sy))
    return rect.projectedCorners(in:scene,angle:angle) == nil ? nil : rect
  }

  public func projectedCorners(in scene: VanishingScene, angle: Double = 0) -> [PathPoint]? {
    guard hasValidBounds,scene.frames.indices.contains(plane),angle.isFinite else { return nil }
    let frame = scene.frames[plane]
    let map = frame.map.m
    let corners = [lower,.init(upper.x,lower.y),upper,.init(lower.x,upper.y)]
      .map { rotated($0,frame:frame,angle:angle) }
    for corner in corners {
      let visibleSide = (map[6]*0.5+map[7]*0.5+map[8]).sign
      let denominator = map[6]*corner.x+map[7]*corner.y+map[8]
      guard abs(denominator) > 1e-10,denominator.sign == visibleSide else { return nil }
    }
    let projected = corners.map(frame.point)
    return PerspectiveSettings.validQuad(projected) ? projected : nil
  }

  public func contains(_ point: PathPoint, in scene: VanishingScene, angle: Double = 0) -> Bool {
    guard scene.frames.indices.contains(plane) else { return false }
    let unit = unitPoint(point,frame:scene.frames[plane],angle:angle)
    return (0...1).contains(unit.x) && (0...1).contains(unit.y)
  }

  func unitPoint(_ point: PathPoint, frame: VanishingScene.Frame, angle: Double) -> PathPoint {
    let uv = rotated(frame.uv(point),frame:frame,angle:-angle)
    return .init((uv.x-lower.x)/width,(uv.y-lower.y)/height)
  }

  private func rotated(_ point: PathPoint, frame: VanishingScene.Frame, angle: Double) -> PathPoint {
    guard angle != 0 else { return point }
    let radians = angle * .pi / 180, c = cos(radians), s = sin(radians)
    let midpoint = center
    let x = (point.x-midpoint.x)*frame.width, y = (point.y-midpoint.y)*frame.height
    return .init(midpoint.x+(x*c-y*s)/frame.width,midpoint.y+(x*s+y*c)/frame.height)
  }
}

extension VanishingScene {
  public func marquee(plane: Int, from start: PathPoint, to end: PathPoint, square: Bool) -> VanishingMarquee? {
    guard frames.indices.contains(plane) else { return nil }
    let frame = frames[plane]
    let a = frame.metric(start)
    var b = frame.metric(end)
    if square {
      let dx = b.x-a.x, dy = b.y-a.y, extent = max(abs(dx),abs(dy))
      b = .init(a.x+(dx < 0 ? -extent : extent),a.y+(dy < 0 ? -extent : extent))
    }
    let rect = VanishingMarquee(plane:plane,lower:.init(min(a.x,b.x)/frame.width,min(a.y,b.y)/frame.height),
      upper:.init(max(a.x,b.x)/frame.width,max(a.y,b.y)/frame.height))
    return rect.projectedCorners(in:self) == nil ? nil : rect
  }
}

public struct VanishingMarqueeTransfer: Codable, Equatable, Sendable {
  public var source: VanishingMarquee
  public var destination: VanishingMarquee
  public var feather: Double

  public init(source: VanishingMarquee, destination: VanishingMarquee, feather: Double = 1) {
    self.source = source
    self.destination = destination
    self.feather = feather
  }

  public static let featherRange = 0.0...200.0
}
