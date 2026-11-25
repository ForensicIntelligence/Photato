import Foundation

/// A single camera and the scene reconstructed from the same perspective frames
/// used by the editing tools. Coordinates are expressed in the first plane's axes.
public struct VanishingSceneGeometry: Sendable {
  public let planes: [[SIMD3<Double>]]
  public let camera: SIMD3<Double>
  public let target: SIMD3<Double>
  public let rollDegrees: Double
  public let horizontalAngleOfView: Double
}

extension VanishingScene {
  public func exportGeometry(settings: VanishingSettings, canvasWidth: Int) throws -> VanishingSceneGeometry {
    guard let first = frames.first, frames.count == settings.planes.count, canvasWidth > 0 else {
      throw CraftError.invalid("Create a perspective plane before exporting a scene.")
    }
    var sizes = Array(repeating:0.0,count:frames.count)
    var points: [[SIMD3<Double>]] = []
    for (index,frame) in frames.enumerated() {
      let hinge: (parentA: Int, parentB: Int, childA: Int, childB: Int)?
      if let parent = settings.planes[index].parent {
        let edge = settings.planes[index].edge
        let (a,b,_) = Self.edgeIndices(edge)
        let (u,v) = Self.outsideIndices(edge)
        hinge = (a,b,(u+3)%4,(v+1)%4)
        sizes[index] = points[parent][a].z / frame.points[(u+3)%4].z
      } else {
        hinge = nil
        sizes[index] = measurementMetric(for:index).x / frame.width
      }
      var projected = frame.points.map { $0*sizes[index] }
      if let hinge, let parent = settings.planes[index].parent {
        projected[hinge.childA] = points[parent][hinge.parentA]
        projected[hinge.childB] = points[parent][hinge.parentB]
      }
      points.append(projected)
    }
    let origin = points[0][2]
    let right = Self.unit(first.points[1]-first.points[0])
    let forward = Self.unit(Self.cross(right,first.points[3]-first.points[0]))
    let down = Self.unit(Self.cross(forward,right))
    func vector(_ point: SIMD3<Double>) -> SIMD3<Double> {
      .init(Self.dot(point,right),Self.dot(point,down),Self.dot(point,forward))
    }
    func position(_ point: SIMD3<Double>) -> SIMD3<Double> { vector(point-origin) }
    let camera = position(.zero)
    let direction = vector(.init(0,0,1))
    let lookingUp = vector(.init(0,-1,0))
    var standardUp = SIMD3<Double>(0,-1,0)
    if abs(Self.dot(standardUp,direction)) > 0.999999 { standardUp = .init(0,0,-1) }
    standardUp = Self.unit(standardUp-direction*Self.dot(standardUp,direction))
    let bank = atan2(Self.dot(Self.cross(standardUp,lookingUp),direction),Self.dot(standardUp,lookingUp))
    let depth = points[0].reduce(0) { $0+$1.z } / 4
    let target = position(.init(0,0,depth))
    let angle = 2 * atan(Double(canvasWidth)/2/focal) * 180 / .pi
    let output = points.map { $0.map(position) }
    let coordinates = output.flatMap { $0 } + [camera,target]
    guard abs(bank).isFinite, angle.isFinite, angle > 0, 2400/angle < Double(Float.greatestFiniteMagnitude),
      coordinates.allSatisfy({
        max(abs($0.x),abs($0.y),abs($0.z)) < Double(Float.greatestFiniteMagnitude)/4
      }) else { throw CraftError.invalid("Vanishing Point scene exceeds the supported camera range.") }
    return .init(planes:output,camera:camera,target:target,rollDegrees:bank * 180 / .pi,horizontalAngleOfView:angle)
  }
}
