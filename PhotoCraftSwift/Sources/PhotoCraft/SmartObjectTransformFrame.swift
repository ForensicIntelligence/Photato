import AppKit
import PhotoCraftCore

/// The artwork's source rectangle and its coordinate system when a draft opens.
struct SmartObjectTransformFrame: Equatable {
  let artwork: SmartObjectGeometry
  let basis: Transform2D
  let inverseBasis: Transform2D
  let documentToSource: Transform2D

  init(_ artwork: SmartObjectGeometry) throws {
    self.artwork = artwork
    let transform = artwork.transform
    basis = Transform2D(a: transform.a, b: transform.b, c: transform.c, d: transform.d)
    inverseBasis = try basis.inverted()
    documentToSource = try transform.inverted()
  }

  func point(_ xFraction: Double, _ yFraction: Double) -> PathPoint {
    let point = artwork.transform.point(Double(artwork.width) * xFraction, Double(artwork.height) * yFraction)
    return .init(point.x, point.y)
  }
}

extension TransformDraft {
  var hasAffineArtworkFrame: Bool { artworkFrame != nil && selectionQuad == nil }

  var artworkOrientation: Transform2D {
    .rotation(angle) * .scale(artworkReflected ? -1 : 1, 1)
  }

  var artworkAngleOffset: Double {
    guard let frame = artworkFrame else { return 0 }
    return artworkReflected ? 180 - frame.basis.rotationDegrees : frame.basis.rotationDegrees
  }

  var displayedAngle: Double { (angle + artworkAngleOffset).truncatingRemainder(dividingBy: 360) }

  func artworkDelta(_ frame: SmartObjectTransformFrame) -> Transform2D {
    let center = frame.point(0.5, 0.5)
    let scale = Transform2D.scale(scaleX / 100, scaleY / 100)
    // Uniform scale commutes with the basis. This also keeps an untouched
    // draft bit-exact, with no matrix/inverse round trip before Apply.
    let scaleInDocument = scaleX == scaleY ? scale : frame.basis * scale * frame.inverseBasis
    return .translation(centerX, centerY) * artworkOrientation * scaleInDocument
      * .translation(-center.x, -center.y)
  }

  func draggingArtwork(_ frame: SmartObjectTransformFrame, direction: (Double, Double),
                       from start: CGPoint, to end: CGPoint, shift: Bool, option: Bool) -> Self {
    guard start != end else { return self }
    let (x, y) = direction
    let reference = option ? sourceReferencePoint : frame.point((1 - x) / 2, (1 - y) / 2)
    let pivot = frame.documentToSource.point(reference.x, reference.y)
    let h = (Double(frame.artwork.width) * (1 + x) / 2, Double(frame.artwork.height) * (1 + y) / 2)
    let unrotate = Transform2D.scale(artworkReflected ? -1 : 1, 1) * .rotation(-angle)
    let movement = (frame.inverseBasis * unrotate).point(end.x - start.x, end.y - start.y)
    let distanceX = (h.0 - pivot.x) * scaleX / 100
    let distanceY = (h.1 - pivot.y) * scaleY / 100
    var factorX = x == 0 || abs(distanceX) < 1e-9 ? 1 : 1 + movement.x / distanceX
    var factorY = y == 0 || abs(distanceY) < 1e-9 ? 1 : 1 + movement.y / distanceY
    let width = Double(frame.artwork.width) * hypot(frame.basis.a, frame.basis.b) * abs(scaleX) / 100
    let height = Double(frame.artwork.height) * hypot(frame.basis.c, frame.basis.d) * abs(scaleY) / 100
    let minimumX = min(1, 0.1 / width)
    let minimumY = min(1, 0.1 / height)
    if proportional != shift {
      let factor = x == 0 ? factorY : y == 0 ? factorX : abs(factorX) > abs(factorY) ? factorX : factorY
      factorX = boundedArtworkFactor(factor, minimum: max(minimumX, minimumY))
      factorY = factorX
    } else {
      factorX = boundedArtworkFactor(factorX, minimum: minimumX)
      factorY = boundedArtworkFactor(factorY, minimum: minimumY)
    }
    var next = self
    next.scaleX *= factorX
    next.scaleY *= factorY
    let fixed = delta.point(reference.x, reference.y)
    let moved = next.delta.point(reference.x, reference.y)
    next.centerX += fixed.x - moved.x
    next.centerY += fixed.y - moved.y
    return next
  }

  private func boundedArtworkFactor(_ factor: Double, minimum: Double) -> Double {
    if !allowsFlips { return max(minimum, factor) }
    return abs(factor) < minimum ? (factor < 0 ? -minimum : minimum) : factor
  }

  func turningArtwork(_ degrees: Double, horizontal: Bool, vertical: Bool) -> Self {
    var next = self
    let pivot = transformReferencePoint
    let turn = Transform2D.translation(pivot.x, pivot.y) * .rotation(degrees)
      * .scale(horizontal ? -1 : 1, vertical ? -1 : 1) * .translation(-pivot.x, -pivot.y)
    let center = turn.point(centerX, centerY)
    if horizontal != vertical {
      next.artworkReflected.toggle()
      next.angle = degrees - angle + (vertical ? 180 : 0)
    } else {
      next.angle = angle + degrees + (horizontal ? 180 : 0)
    }
    next.centerX = center.x
    next.centerY = center.y
    return next
  }
}
