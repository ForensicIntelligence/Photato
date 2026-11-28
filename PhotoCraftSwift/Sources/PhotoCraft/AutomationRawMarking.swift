import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension RawPhotoMarking {
  var apiValue: [String: Any] {
    ["rating": rating as Any? ?? NSNull(), "label": label as Any? ?? NSNull()]
  }
}

enum RawMarkingAPI {
  static let name = "raw.markPhoto"
  static let definition = AutomationCommand.Definition(name: name, parameters: [
    "layerID": "The single RAW original layer UUID",
    "rating": "Zero through five stars",
    "label": "XMP color label, or null to clear",
  ], description: "Change the photo’s XMP rating or label in one Undo step. Save Source Settings writes the original metadata.",
    optionalParameters: ["rating", "label"])

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "rating": ["type": "integer", "minimum": 0, "maximum": 5]
    case "label": ["anyOf": [["type": "string", "maxLength": 128], ["type": "null"]]]
    default: VariablesAPI.uuid
    }
  }

  static func isSingleOriginal(_ id: UUID, in document: CraftDocument) -> Bool {
    document.layers.count == 1 && document.layers[0].id == id && document.layers[0].smartObject?.rawDevelopment != nil
  }

  static func edit(_ command: AutomationCommand, document: CraftDocument) throws -> Command? {
    guard isSingleOriginal(try command.actionUUID("layerID"), in: document) else {
      throw AutomationFailure(status: 422, message: "Select a document with one RAW original layer.")
    }
    var patch = RawPhotoMarking()
    if let rating = command.parameters["rating"] {
      guard case .number(let value) = rating, let number = Int(exactly: value), (0...5).contains(number) else {
        throw AutomationFailure(status: 400, message: "Rating must be an integer from zero through five.")
      }
      patch.rating = number
    }
    if let label = command.parameters["label"] {
      switch label {
      case .string(let title) where title.utf8.count <= 128 &&
          !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains):
        patch.label = title
      case .null: patch.label = ""
      default: throw AutomationFailure(status: 400, message: "Use an XMP label of up to 128 bytes or null.")
      }
    }
    guard !patch.isEmpty else {
      throw AutomationFailure(status: 400, message: "Supply a rating or a label.")
    }
    let updated = try patch.applying(to: document)
    return updated.sourceMetadata == document.sourceMetadata ? nil : .documentMetadata(updated.sourceMetadata)
  }
}
