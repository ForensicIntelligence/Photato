import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ProcessChannelDeletionAPI {
  static let name = "channel.deleteProcess"

  static func schema(_ key: String) -> [String: Any] {
    if key == "mergeVisible" { return ["type": "boolean", "default": false] }
    return ["type": "array", "minItems": 1, "maxItems": 3, "uniqueItems": true,
      "items": ["type": "integer", "minimum": 0, "maximum": 3]]
  }

  static var stateSchema: [String: Any] {
    BrushAPI.object([
      "available": BrushAPI.flag, "selectionAvailable": BrushAPI.flag,
      "requiresMerge": BrushAPI.flag, "selectedComponents": ["type": "array", "items": ["type": "integer", "minimum": 0, "maximum": 3]],
      "reason": ["type": ["string", "null"]]
    ], required: ["available", "selectionAvailable", "requiresMerge", "selectedComponents", "reason"])
  }

  static var capabilities: [String: Any] {
    ["command": name, "state": "selectionChannels.processDeletion", "stateSchema": stateSchema,
     "parameters": ["components": schema("components"), "mergeVisible": schema("mergeVisible")],
     "result": "HTTP 200 returns the resulting Multichannel document state.",
     "behavior": "Delete one or more distinct zero-based RGB, CMYK or Lab process components at 8 or 16 bits. Retain at least one. The existing process separations become editable Multichannel plates. Complex stacks require mergeVisible:true to flatten visible layers and discard hidden layers. Saved alpha, spot and selection data are retained. PSD and PSB writes keep spots as printable separations. Desktop and API share one prepared Undo.",
     "limits": "Single still canvas with no Quick Mask. Large sparse plates use native archive 93 and the existing PSD and PSB writers. Existing compositor and scratch limits apply. Full numerical Photoshop output remains unqualified.",
     "actions": "Photato Actions 75 records component positions in the required color mode.",
     "adobe": "There is no dedicated published Firefly process-channel deletion operation or route."]
  }
}

extension EditorStore {
  var processChannelDeletionState: [String: Any] {
    let reason = ProcessChannelDeletion.unavailableReason(document)
    let components = selectedProcessChannelsForDeletion
    return ["available": reason == nil && canEditChannels, "selectionAvailable": canDeleteProcessChannels(components),
      "requiresMerge": reason == nil && InkModeInput.needsMerge(document), "selectedComponents": components,
      "reason": reason as Any? ?? NSNull()]
  }
}

extension AutomationService {
  func deleteProcessChannels(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    guard case .array(let values) = command.parameters["components"], (1...3).contains(values.count) else {
      throw AutomationFailure(status: 400, message: "Specify one to three distinct process component indices.")
    }
    let components = try values.map { value -> Int in
      guard case .number(let number) = value, (0...3).contains(number), number.rounded() == number else {
        throw AutomationFailure(status: 400, message: "Process component indices must be integers from zero to three.")
      }
      return Int(number)
    }
    guard Set(components).count == components.count else {
      throw AutomationFailure(status: 400, message: "Process component indices must be distinct.")
    }
    let store = document.store
    guard store.canEditChannels else {
      throw AutomationFailure(status: 409, message: "Finish the current interaction before deleting process channels.")
    }
    let merge = try command.pathFlag("mergeVisible", false)
    let request = ProcessChannelDeletion(mode: store.document.colorMode, components: components, mergeVisible: merge)
    _ = try request.retainedComponents(in: store.document)
    guard merge || !InkModeInput.needsMerge(store.document) else {
      throw AutomationFailure(status: 422, message: "Set mergeVisible:true to flatten the visible artwork and discard hidden layers.")
    }
    try await executePreparedOperation(document: document, shareID: share.id, revision: command.revision,
      allowAuxiliary: true) { original in try InkModeInput.deleteProcess(request, in: original) }
    store.showProcessChannelDeletionResult()
    return .json(state(share, document: document))
  }
}
