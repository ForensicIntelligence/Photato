import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ActionPlaybackAPI {
  static var resultSchema: [String: Any] {
    ["type": "object", "description": "Standard shared-document state, with an optional clipboard payload when playback performs Copy or Cut.",
     "properties": ["clipboardPayloadBase64": ClipboardAPI.schema("payloadBase64")], "additionalProperties": true]
  }
}

extension AutomationCommand {
  func actionClipboardBytes() throws -> Data? {
    guard let raw = parameters["clipboardPayloadBase64"] else { return nil }
    guard case .string(let text) = raw, text.utf8.count <= ClipboardAPI.maximumBase64,
      let bytes = Data(base64Encoded: text), bytes.count <= ClipboardAPI.maximumBytes else {
      throw AutomationFailure(status: 400, message: "Initial action clipboard must be a native payload up to2MiB.")
    }
    return bytes
  }
}

extension AutomationService {
  func executeRecordedAction(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    let store = document.store, action = try store.actions.action(command.actionUUID("actionID"))
    let initial = try command.actionClipboardBytes()
    var inputs: [(UUID, String, CraftNSDocument)] = []
    if let raw = command.parameters["sources"] {
      guard action.usesMasterPalette || action.usesExternalRetouchSources else { throw AutomationFailure(status: 400, message: "Additional sources require a master-palette or external retouch Action step.") }
      _ = try BrushAPI.merge(raw, schema: RestrictedModeAPI.schema("sources", command: ""), base: [])
      guard case .array(let sources) = raw else { throw AutomationFailure(status: 400, message: "Invalid master sources.") }
      for source in sources {
        guard case .object(let fields) = source, case .string(let text) = fields["id"], let id = UUID(uuidString: text), id != share.id,
          !inputs.contains(where: { $0.0 == id }), case .string(let expected) = fields["revision"],
          let input = shares.first(where: { $0.id == id })?.document else { throw AutomationFailure(status: 400, message: "Each master source must be a distinct shared document.") }
        try preflight(input)
        guard revision(input.store) == expected else { throw AutomationFailure(status: 409, message: "A master source revision is stale.") }
        inputs.append((id, expected, input))
      }
    }
    if action.isLayerSelectionOnly {
      if let initial { _ = try ClipboardAPI.decode(initial) }
      _ = try store.applyLayerSelectionAction(action)
      return .json(state(share, document: document))
    }
    let captured = inputs, snapshots = inputs.map { $0.2.store.document }
    let playback: (Data?, [PaletteColor]?) = try await executePreparedResult(document: document, shareID: share.id, revision: command.revision, validateCommit: { [self] in
      for (index, input) in captured.enumerated() {
        guard shares.contains(where: { $0.id == input.0 && $0.document === input.2 }), revision(input.2.store) == input.1,
          input.2.store.document == snapshots[index] else { throw AutomationFailure(status: 409, message: "A master source changed or sharing ended.") }
        try preflight(input.2)
      }
    }) { source in
      let result = try RecordedActionRenderer.prepare(action, in: source, clipboard: initial.map(ClipboardAPI.decode), masters: snapshots, validateClipboard: ClipboardAPI.validate, validate: Self.checkLimits)
      let bytes = try result.clipboard?.encoded()
      if let bytes, bytes.count > ClipboardAPI.maximumBytes { throw AutomationFailure(status: 413, message: "Action clipboard output exceeds2MiB. The document was not changed.") }
      if let bytes { _ = try ClipboardAPI.decode(bytes) }
      return (result.command, (bytes, result.lastIndexedPalette))
    }
    if let palette = playback.1 { store.previousIndexedPalette = palette }
    var result = state(share, document: document)
    if let output = playback.0 { result["clipboardPayloadBase64"] = output.base64EncodedString() }
    return .json(result)
  }
}
