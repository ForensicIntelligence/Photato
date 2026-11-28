import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension RawDevelopment {
  func synchronizing(_ source: Self, groups: Set<RawSettingsGroup>, sensor: RawSourceIO.Info?,
    changesFrom baseline: Self? = nil) -> Self {
    var result = synchronizing(source, groups: groups, changesFrom: baseline)
    if sensor?.lensCorrectionSupported == false { result.lensCorrection = lensCorrection }
    if sensor?.highlightRecoverySupported == false { result.highlightRecovery = highlightRecovery }
    return result
  }
}

enum RawSynchronizationAPI {
  static let name = "raw.synchronize"
  static let maximumTargets = 64
  static let definition = AutomationCommand.Definition(name: name, parameters: [
    "sourceLayerID": "RAW Smart Object UUID supplying current settings",
    "settings": "Settings from an external RAW source",
    "targetLayerIDs": "RAW Smart Object layer UUIDs",
    "groups": "Settings groups to copy",
  ], description: "Synchronize selected settings across RAW layers in one Undo step. Provide a source layer or explicit settings.",
    optionalParameters: ["sourceLayerID", "settings"])

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "sourceLayerID": ["type": "string", "format": "uuid"]
    case "settings": RawDevelopment.apiSchema
    case "targetLayerIDs": ["type": "array", "minItems": 1, "maxItems": maximumTargets, "uniqueItems": true,
      "items": ["type": "string", "format": "uuid"]]
    default: ["type": "array", "minItems": 1, "maxItems": RawSettingsGroup.allCases.count, "uniqueItems": true,
      "items": ["type": "string", "enum": RawSettingsGroup.allCases.map(\.rawValue)]]
    }
  }

  struct Request: Sendable {
    let sourceID: UUID?
    let supplied: RawDevelopment?
    let targets: [UUID]
    let groups: Set<RawSettingsGroup>

    init(_ command: AutomationCommand) throws {
      let inputSourceID = try command.parameters["sourceLayerID"].map { _ in try command.actionUUID("sourceLayerID") }
      sourceID = inputSourceID
      if let settings = command.parameters["settings"] {
        do { supplied = try RawDevelopment.decodeJSON(JSONSerialization.data(withJSONObject: settings.jsonValue)) }
        catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
      } else { supplied = nil }
      guard (sourceID == nil) != (supplied == nil),
        case .array(let ids) = command.parameters["targetLayerIDs"], (1...maximumTargets).contains(ids.count),
        case .array(let inputGroups) = command.parameters["groups"],
        (1...RawSettingsGroup.allCases.count).contains(inputGroups.count) else {
        throw AutomationFailure(status: 400, message: "Provide a source, target RAW layers and at least one settings group.")
      }
      targets = try ids.map { value in
        guard case .string(let text) = value, let id = UUID(uuidString: text), id != inputSourceID else {
          throw AutomationFailure(status: 400, message: "Target layers require UUIDs distinct from the source.")
        }
        return id
      }
      let parsed = try inputGroups.map { value in
        guard case .string(let name) = value, let group = RawSettingsGroup(rawValue: name) else {
          throw AutomationFailure(status: 400, message: "Unknown Camera Raw settings group.")
        }
        return group
      }
      groups = Set(parsed)
      guard groups.count == parsed.count, Set(targets).count == targets.count else {
        throw AutomationFailure(status: 400, message: "Target layers and settings groups must be unique.")
      }
    }

    func prepare(in original: CraftDocument) throws -> Command {
      func object(_ id: UUID) throws -> SmartObject {
        guard let object = original.layers.first(where: { $0.id == id })?.smartObject, object.rawDevelopment != nil else {
          throw AutomationFailure(status: 422, message: "Choose an embedded Camera Raw layer.")
        }
        return object
      }
      let source = try supplied ?? sourceID.flatMap { try object($0).rawDevelopment }
      guard let source else { throw AutomationFailure(status: 422, message: "Choose a Camera Raw settings source.") }
      var result = original
      for id in targets {
        try Task.checkCancellation()
        let target = try object(id)
        guard let previous = target.rawDevelopment else { continue }
        let sensor = groups.contains(.sensor) ? try RawSourceIO.inspect(target.data, decoderVersion: previous.decoderVersion) : nil
        let settings = previous.synchronizing(source, groups: groups, sensor: sensor)
        if settings != previous {
          try RawSourceIO.command(in: result, layerID: id, settings: settings, allInstances: false).apply(to: &result)
        }
      }
      return .preparedAction(.init(source: original, result: result, title: "Synchronize Camera Raw Settings"))
    }
  }
}
