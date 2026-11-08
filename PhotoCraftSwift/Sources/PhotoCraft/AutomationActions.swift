import Foundation
import PhotoCraftCore

extension AutomationCommand {
  static let actionOperations = ["list", "record", "stop", "cancel", "rename", "duplicate", "delete", "import", "export", "step.enable", "step.delete", "step.move"]
  static func actionSchema(_ key: String) -> [String: Any] {
    switch key {
    case "clipboardPayloadBase64": return ClipboardAPI.schema("payloadBase64")
    case "sources": return RestrictedModeAPI.schema("sources", command: "")
    case "operation": return ["type": "string", "enum": actionOperations]
    case "actionID", "stepID": return ["type": "string", "format": "uuid"]
    case "enabled": return ["type": "boolean"]
    case "index": return ["type": "integer", "minimum": 0, "maximum": 511]
    case "data": return ["type": "string", "contentEncoding": "base64", "maxLength": 60_000, "description": "Version 1–\(ActionLibraryFile.maximumVersion) Photato action library JSON encoded as base64; not an Adobe .atn file."]
    default: return ["type": "string", "minLength": 1, "maxLength": 256]
    }
  }
  func actionUUID(_ key: String) throws -> UUID {
    guard let id = UUID(uuidString: try string(key)) else { throw AutomationFailure(status: 400, message: "\(key) must be a UUID.") }; return id
  }
}
extension AutomationService {
  func manageActions(_ command: AutomationCommand, store: EditorStore) throws -> [String: Any] {
    let operation = try command.string("operation")
    let required: Set<String>
    let optional: Set<String>
    switch operation {
    case "list", "stop", "cancel": required = []; optional = []
    case "record": required = ["name"]; optional = ["set"]
    case "rename": required = ["actionID", "name", "set"]; optional = []
    case "duplicate": required = ["actionID"]; optional = ["name", "set"]
    case "delete": required = ["actionID"]; optional = []
    case "import": required = ["data"]; optional = []
    case "export": required = []; optional = ["actionID"]
    case "step.enable": required = ["actionID", "stepID", "enabled"]; optional = []
    case "step.delete": required = ["actionID", "stepID"]; optional = []
    case "step.move": required = ["actionID", "stepID", "index"]; optional = []
    default: throw AutomationFailure(status: 400, message: "Unknown action library operation.")
    }
    let keys = Set(command.parameters.keys).subtracting(["operation"])
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw AutomationFailure(status: 400, message: "Missing or irrelevant action parameters.") }
    if ["rename", "delete", "step.enable", "step.delete", "step.move"].contains(operation),
      store.actions === controller.scriptEvents.actions {
      let id = try command.actionUUID("actionID")
      if controller.scriptEvents.configuration.bindings.contains(where: { $0.actionID == id }), !scriptEventChangesEnabled {
        throw AutomationFailure(status: 403,
          message: "Allow app-wide event configuration before changing an Action registered for automatic events.")
      }
    }
    if store.session.actionRecording != nil && !["list", "stop", "cancel"].contains(operation) {
      throw AutomationFailure(status: 409, message: "Stop recording before changing the action library.")
    }
    switch operation {
    case "record": try store.startRecordingAction(name: command.string("name"), set: command.parameters["set"] == nil ? "My Actions" : command.string("set"))
    case "stop": _ = try store.stopRecordingAction()
    case "cancel": _ = try store.stopRecordingAction(save: false)
    case "delete": try store.actions.remove(command.actionUUID("actionID"))
    case "rename":
      var action = try store.actions.action(command.actionUUID("actionID")); action.name = try command.string("name"); action.set = try command.string("set"); try store.actions.save(action)
    case "duplicate":
      let source = try command.actionUUID("actionID")
      let copy = try store.duplicateAction(source,
        name: command.parameters["name"].map { _ in try command.string("name") },
        set: command.parameters["set"].map { _ in try command.string("set") })
      return ["state": store.actionState, "revision": revision(store), "sourceActionID": source.uuidString, "action": EditorStore.actionInfo(copy)]
    case "import":
      guard case .string(let encoded) = command.parameters["data"], encoded.utf8.count <= 60_000, let data = Data(base64Encoded: encoded) else { throw AutomationFailure(status: 400, message: "data must be a bounded base64 Photato action library.") }
      try store.actions.importFile(data)
    case "export":
      let id = try command.parameters["actionID"].map { _ in try command.actionUUID("actionID") }
      return ["state": store.actionState, "revision": revision(store), "format": "photatoactions", "version": store.actions.file.version, "data": try store.actions.exportFile(id).base64EncodedString()]
    case "step.enable", "step.delete", "step.move":
      var action = try store.actions.action(command.actionUUID("actionID")); let stepID = try command.actionUUID("stepID")
      guard let index = action.steps.firstIndex(where: { $0.id == stepID }) else { throw AutomationFailure(status: 404, message: "Action step not found.") }
      if operation == "step.enable" {
        guard case .bool(let enabled) = command.parameters["enabled"] else { throw AutomationFailure(status: 400, message: "enabled must be boolean.") }; action.steps[index].enabled = enabled
      } else if operation == "step.delete" { action.steps.remove(at: index) }
      else { let destination = try command.integer("index", range: 0...Double(action.steps.count - 1)); let step = action.steps.remove(at: index); action.steps.insert(step, at: destination) }
      try store.actions.save(action)
    default: break
    }
    return ["state": store.actionState, "revision": revision(store)]
  }
}

enum ActionDuplicationAPI {
  static var actionSchema: [String: Any] {
    let uuid: [String: Any] = ["type":"string", "format":"uuid"]
    let step = BrushAPI.object(["id":uuid, "name":["type":"string"], "enabled":BrushAPI.flag,
      "unsupportedReason":["type":["string","null"]]], required:["id","name","enabled","unsupportedReason"])
    return BrushAPI.object(["id":uuid, "name":["type":"string"], "set":["type":"string"],
      "steps":["type":"array", "maxItems":512, "items":step]], required:["id","name","set","steps"])
  }
  static var resultSchema: [String: Any] {
    BrushAPI.object(["state":["type":"object"], "revision":["type":"string"],
      "sourceActionID":["type":"string","format":"uuid"], "action":actionSchema],
      required:["state","revision","sourceActionID","action"])
  }
  static var capabilities: [String: Any] {
    ["command":"actions.manage", "operation":"duplicate", "required":["actionID"], "optional":["name","set"],
      "resultSchema":resultSchema, "maximumActions":128, "maximumSteps":512, "maximumLibraryBytes":ActionLibraryFile.maximumBytes,
      "behavior":"Copy one saved action immediately after its source with new action/step IDs and unchanged ordered names, enabled flags and semantic operation payloads. Optional name/set override the copy only. Both copies remain independently editable and playable.",
      "defaultName":"Source name plus copy, then numbered suffixes unique in the destination set, trimmed by whole characters to256UTF-8bytes. Exact Photoshop naming/order remains unqualified.",
      "history":"Library revision/persistence only; no document pixels, dirty state, Undo, recording or clipboard changes. Atomic save failure retains prior memory and disk.",
      "availability":"Stop recording and finish active interactions; corrupt/full libraries reject. Existing API authorization/sharing/revision guards apply.",
      "native":"Actions panel menu Duplicate for whole saved-action selection; unavailable while a command is selected. Command/set copies and Option-drag remain unimplemented.",
      "adobe":"No new published Adobe route or unqualified actionJSON descriptor. Photato action files are not Adobe ATN files."]
  }
}
