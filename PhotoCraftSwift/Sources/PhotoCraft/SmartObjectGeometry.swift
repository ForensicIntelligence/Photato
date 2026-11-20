import Foundation
import PhotoCraftCore

/// The editable affine placement of the original artwork in document pixels.
struct SmartObjectGeometry: Equatable {
  let transform: Transform2D
  let width: Int
  let height: Int

  func bounds() throws -> IntRect {
    try transform.bounds(width: width, height: height)
  }
}

extension Transform2D {
  var rotationDegrees: Double { atan2(b, a) * 180 / .pi }
}

extension Layer {
  func smartObjectGeometry() throws -> SmartObjectGeometry? {
    guard let source = smartObject, sourceProjection == nil, importedSmartAppearance == nil,
          warp == nil, frame == nil else { return nil }
    let placement = try smartObjectSourceTransform()
    try placement.validated()
    return .init(transform: placement, width: source.width, height: source.height)
  }
}
