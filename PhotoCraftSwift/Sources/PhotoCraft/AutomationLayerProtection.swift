import Foundation
import PhotoCraftCore

extension AutomationCommand {
  func protectionCommand(document: CraftDocument) throws -> Command {
    guard case .array(let rawIDs) = parameters["layerIDs"], (1...LayerLimits.maximumLayers).contains(rawIDs.count),
      case .array(let rawNames) = parameters["protection"], (1...6).contains(rawNames.count) else {
      throw AutomationFailure(status: 400, message: "Nonempty layerIDs and protection arrays are required.")
    }
    let ids = try rawIDs.map { value -> UUID in
      guard case .string(let text) = value, let id = UUID(uuidString: text) else {
        throw AutomationFailure(status: 400, message: "Invalid layer UUID.")
      }
      return id
    }
    let names = try rawNames.map { value -> String in
      guard case .string(let name) = value else {
        throw AutomationFailure(status: 400, message: "Invalid protection flag.")
      }
      return name
    }
    guard Set(ids).count == ids.count, Set(names).count == names.count else {
      throw AutomationFailure(status: 400, message: "Duplicate layers or protection flags.")
    }
    guard Set(ids).isSubset(of: Set(document.layers.map(\.id))) else {
      throw AutomationFailure(status: 404, message: "Layer not found.")
    }
    var descendants = false
    if let raw = parameters["includeDescendants"] {
      guard case .bool(let value) = raw else {
        throw AutomationFailure(status: 400, message: "includeDescendants must be boolean.")
      }
      descendants = value
    }
    let value: LayerProtection
    do {
      guard case .replace(let parsed) = try AdobeLayerProtection.parse(names, addingLayer: false) else {
        throw AutomationFailure(status: 400, message: "Use none to remove protection.")
      }
      value = parsed
    } catch let error as AdobeAPIError {
      throw AutomationFailure(status: error.status, message: error.message)
    }
    let targets = descendants ? LayerHierarchyIndex(document).subtreeIDs(Set(ids)) : Set(ids)
    return .protection(Dictionary(uniqueKeysWithValues: targets.map { ($0, value) }))
  }
}

extension AutomationService {
  static var protectionStateSchema: [String: Any] {
    ["type": "object", "required": ["protection", "effectiveProtection", "imageLocked",
      "positionLocked", "transparencyLocked"], "properties": [
        "protection": ["type": "array", "items": ["type": "string", "enum": AdobeLayerProtection.names]],
        "effectiveProtection": ["type": "array", "items": ["type": "string", "enum": AdobeLayerProtection.names]],
        "imageLocked": ["type": "boolean"], "positionLocked": ["type": "boolean"],
        "transparencyLocked": ["type": "boolean"],
      ]]
  }
}
