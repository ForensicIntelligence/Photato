import Foundation

enum ScriptEventsAPI {
  static let path = "/v1/automation/events"
  static var configurationSchema: [String: Any] {
    let binding = BrushAPI.object(["id": ["type": "string", "format": "uuid"],
      "event": ["type": "string", "enum": ScriptEventKind.allCases.map(\.rawValue)],
      "actionID": ["type": "string", "format": "uuid"]], required: ["id", "event", "actionID"])
    return BrushAPI.object(["version": ["type": "integer", "const": 1], "enabled": BrushAPI.flag,
      "bindings": ["type": "array", "maxItems": ScriptEventsConfiguration.maximumBindings, "items": binding]],
      required: ["version", "enabled", "bindings"])
  }
  static var stateSchema: [String: Any] {
    let nullableText: [String: Any] = ["type": ["string", "null"]]
    let result = BrushAPI.object([
      "event": ["type": "string", "enum": ScriptEventKind.allCases.map(\.rawValue)],
      "documentID": ["type": "string", "format": "uuid"],
      "completedActions": ["type": "integer", "minimum": 0, "maximum": ScriptEventsConfiguration.maximumBindings],
      "error": nullableText], required: ["event", "documentID", "completedActions", "error"])
    let fields: [String: Any] = ["revision": ["type": "string", "format": "uuid"],
      "configuration": configurationSchema, "libraryRevision": ["type": "integer", "minimum": 0],
      "actions": ["type": "array", "maxItems": 128, "items": ActionDuplicationAPI.actionSchema],
      "isPersistent": BrushAPI.flag, "isRunning": BrushAPI.flag,
      "pendingEvents": ["type": "integer", "minimum": 0, "maximum": 64],
      "lastResult": ["anyOf": [["type": "null"], result]],
      "loadError": nullableText, "actionsLoadError": nullableText]
    return BrushAPI.object(fields, required: Array(fields.keys).sorted())
  }
  static var capabilities: [String: Any] {
    ["path": path, "methods": ["GET", "POST"], "requiresPermission": "scriptEventChangesEnabled",
     "configurationSchema": configurationSchema,
     "stateSchema": stateSchema, "resultSchema": stateSchema,
     "requestSchema": BrushAPI.object(["revision": ["type": "string", "format": "uuid"],
       "configuration": configurationSchema], required: ["revision", "configuration"]),
     "events": ScriptEventKind.allCases.map(\.rawValue), "scripts": false,
     "registeredActionEditing": "actions.manage rename/delete/step.enable/step.delete/step.move requires the app-wide event permission for registered Action IDs, including temporarily disabled registrations. Unbound Actions and list/export/duplicate retain their existing permission rules.",
     "behavior": "Configure persistent native event Actions for New Document and Open Document. Disabled by default. Configuration is app-wide and can affect unshared documents. The separate native API permission turns off with the API; saved event configuration persists.",
     "execution": "Publication queues Actions asynchronously after document opening finishes. Each Action uses normal prepared playback/history. State exposes running/pending/result. Changed configuration, library, document, interaction or lifecycle rejects pending work before commit. An earlier successfully committed Action remains undoable if a later Action fails.",
     "limits": "128 registrations,64 pending events. No script runtime, startup/save/close/export/print/custom event, existing-open focus, recovery replay or Photoshop notifier/plug-in compatibility claim.",
     "adobe": "No event-configuration route is defined in the pinned Firefly v2 contract. No Adobe endpoint or action descriptor invented."]
  }
}

extension AutomationService {
  var scriptEventsState: [String: Any] {
    let store = controller.scriptEvents, dispatcher = controller.scriptEventsDispatcher
    let configuration = (try? store.configuration.encoded()).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
    return ["revision": store.revision.uuidString, "configuration": configuration,
      "libraryRevision": store.actions.revision, "actions": store.actions.file.actions.map(EditorStore.actionInfo),
      "isRunning": dispatcher.isRunning, "pendingEvents": dispatcher.pendingCount,
      "isPersistent": store.persistenceURL != nil,
      "lastResult": dispatcher.lastResult.map { ["event": $0.event.rawValue, "documentID": $0.documentID.uuidString,
        "completedActions": $0.completedActions, "error": $0.error as Any? ?? NSNull()] } as Any? ?? NSNull(),
      "loadError": store.loadError as Any? ?? NSNull(),
      "actionsLoadError": store.actions.loadError as Any? ?? NSNull()]
  }
  func handleScriptEvents(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == ScriptEventsAPI.path else { return nil }
    guard scriptEventChangesEnabled else { throw AutomationFailure(status: 403, message: "Allow app-wide event configuration in the native API window first.") }
    if request.method == "GET" { return .json(scriptEventsState) }
    guard request.method == "POST" else { throw AutomationFailure(status: 404, message: "Unknown event configuration operation.") }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
      Set(body.keys) == ["revision", "configuration"], let raw = body["revision"] as? String, let revision = UUID(uuidString: raw),
      let value = body["configuration"] as? [String: Any], Set(value.keys) == ["version", "enabled", "bindings"],
      let bindings = value["bindings"] as? [[String: Any]],
      bindings.allSatisfy({ Set($0.keys) == ["id", "event", "actionID"] }) else {
      throw AutomationFailure(status: 400, message: "Supply only revision and the complete event configuration.")
    }
    guard revision == controller.scriptEvents.revision else { throw AutomationFailure(status: 409, message: "Event configuration changed. Refresh and try again.") }
    let configuration: ScriptEventsConfiguration
    do { configuration = try .decode(JSONSerialization.data(withJSONObject: value)) }
    catch { throw AutomationFailure(status: 400, message: "Invalid event configuration.") }
    do { try controller.scriptEvents.replace(configuration, expectedRevision: revision) }
    catch { throw AutomationFailure(status: 422, message: error.localizedDescription) }
    return .json(scriptEventsState)
  }
}
