import Foundation
import PhotoCraftCore

/// Parser for the pinned v2 create-composite layer protection field. This is an
/// shared parser for the explicitly limited protection-edit endpoint.
enum AdobeLayerProtection {
  enum Update: Equatable {
    case unchanged
    case replace(LayerProtection)
  }
  static let names = ["none", "all", "transparency", "composite", "position", "artboard_autonest"]

  static func parse(_ value: Any?, addingLayer: Bool) throws -> Update {
    if value == nil || value is NSNull {
      return addingLayer ? .replace([]) : .unchanged
    }
    guard let values = value as? [String] else {
      throw AdobeAPIError.invalid("Layer protection must be an array of flag names.")
    }
    if values.isEmpty { return addingLayer ? .replace([]) : .unchanged }
    guard values.allSatisfy({ names.contains($0) }) else {
      throw AdobeAPIError.invalid("Unknown layer protection flag.")
    }
    if values.contains("none") || values.contains("all") {
      guard values.count == 1 else {
        throw AdobeAPIError.invalid("Layer protection none and all must be used alone.")
      }
      return .replace(values[0] == "all" ? .fullyLocked : [])
    }
    // The published schema does not require uniqueItems; repeated partial flags
    // are idempotent. Do not invent a stricter transport contract.
    var result = LayerProtection()
    for value in values {
      switch value {
      case "transparency": result.insert(.transparency)
      case "composite": result.insert(.image)
      case "position": result.insert(.position)
      case "artboard_autonest": result.insert(.autoNest)
      default: preconditionFailure("Names validated above")
      }
    }
    return .replace(result)
  }
}
