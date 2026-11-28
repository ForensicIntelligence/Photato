import Foundation

/// Manual Camera Raw corrections in the units used by the editor and XMP.
public struct RawGeometrySettings: Codable, Equatable, Sendable {
  public var vertical: Float = 0
  public var horizontal: Float = 0
  public var rotation: Float = 0
  public var aspect: Float = 0
  public var scale: Float = 100
  public var offsetX: Float = 0
  public var offsetY: Float = 0
  public var constrainCrop = false

  public init() {}

  package struct Control: Identifiable, Sendable {
    package let id: String
    package let title: String
    package let xmp: String
    package let key: WritableKeyPath<RawGeometrySettings, Float> & Sendable
    package let range: ClosedRange<Float>
  }

  package static let controls: [Control] = [
    .init(id: "vertical", title: "Vertical", xmp: "PerspectiveVertical", key: \.vertical, range: -100...100),
    .init(id: "horizontal", title: "Horizontal", xmp: "PerspectiveHorizontal", key: \.horizontal, range: -100...100),
    .init(id: "rotation", title: "Rotate", xmp: "PerspectiveRotate", key: \.rotation, range: -10...10),
    .init(id: "aspect", title: "Aspect", xmp: "PerspectiveAspect", key: \.aspect, range: -100...100),
    .init(id: "scale", title: "Scale", xmp: "PerspectiveScale", key: \.scale, range: 50...150),
    .init(id: "offsetX", title: "Offset X", xmp: "PerspectiveX", key: \.offsetX, range: -100...100),
    .init(id: "offsetY", title: "Offset Y", xmp: "PerspectiveY", key: \.offsetY, range: -100...100),
  ]

  package var isIdentity: Bool {
    let neutral = Self()
    return Self.controls.allSatisfy { self[keyPath: $0.key] == neutral[keyPath: $0.key] }
  }

  package func validate() throws {
    for control in Self.controls {
      let value = self[keyPath: control.key]
      guard value.isFinite, control.range.contains(value) else {
        throw CraftError.invalid("Camera Raw \(control.title) must be between \(control.range.lowerBound) and \(control.range.upperBound).")
      }
    }
  }

  static func decode(_ value: Any, base: Self) throws -> Self {
    guard let fields = value as? [String: Any],
      Set(fields.keys).isSubset(of: Set(controls.map(\.id) + ["constrainCrop"])) else {
      throw CraftError.invalid("Invalid Camera Raw Geometry settings.")
    }
    var result = base
    for control in controls {
      guard let field = fields[control.id] else { continue }
      guard let number = field as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
        throw CraftError.invalid("Camera Raw \(control.title) must be numeric.")
      }
      result[keyPath: control.key] = number.floatValue
    }
    if let field = fields["constrainCrop"] {
      guard let number = field as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw CraftError.invalid("Camera Raw Constrain Crop must be a boolean.")
      }
      result.constrainCrop = number.boolValue
    }
    try result.validate()
    return result
  }
}
