import AppKit
import CryptoKit

extension AutomationService {
  var documentClosingRevision: String {
    let values = controller.documents.compactMap { $0 as? CraftNSDocument }.map {
      [$0.store.identity.uuidString, revision($0.store,includeBrush:false), $0.isDocumentEdited ? "1" : "0",
        $0.fileURL?.absoluteString ?? "", $0.fileType ?? ""].joined(separator: "\u{0}")
    }.sorted().joined(separator: "\u{1}")
    return SHA256.hash(data: Data(values.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  var documentClosingState: [String: Any] {
    let coordinator = controller.documentClosing
    var operation: Any = NSNull()
    if let state = coordinator.state {
      operation = [
        "id": state.id.uuidString, "scope": state.scope.rawValue, "mode": state.mode.rawValue,
        "phase": state.phase.rawValue, "total": state.total, "closed": state.closed,
        "cancellationRequested": state.cancellationRequested,
        "error": state.error as Any? ?? NSNull(),
        "canCancel": documentClosingEnabled && ownedCloseOperation == state.id && state.phase.isActive,
      ] as [String: Any]
    }
    return [
      "revision": documentClosingRevision, "openDocuments": controller.documents.count,
      "enabled": documentClosingEnabled,
      "canStart": documentClosingEnabled && coordinator.canStart(controller.closeTargets()),
      "operation": operation,
    ]
  }
  func handleDocumentClosing(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == "/v1/document-closing" || request.path == "/v1/document-closing/cancel"
    else { return nil }
    if request.method == "GET", request.path == "/v1/document-closing" {
      return .json(documentClosingState)
    }
    guard request.method == "POST" else {
      throw AutomationFailure(status: 404, message: "Unknown document closing operation.")
    }
    guard documentClosingEnabled else {
      throw AutomationFailure(status: 403, message: "Allow document closing and Quit in the native API window first.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json"
    else { throw AutomationFailure(status: 415, message: "Content-Type must be application/json.") }
    guard let body = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body)
    else { throw AutomationFailure(status: 400, message: "Expected a JSON closing request.") }
    let coordinator = controller.documentClosing
    if request.path == "/v1/document-closing/cancel" {
      guard Set(body.keys) == ["operationID"], case .string(let value) = body["operationID"],
        let id = UUID(uuidString: value) else {
        throw AutomationFailure(status: 400, message: "Required: operationID UUID.")
      }
      guard ownedCloseOperation == id, coordinator.state?.id == id, coordinator.isActive else {
        throw AutomationFailure(status: 409, message: "That API close operation is no longer active.")
      }
      coordinator.cancel(id)
      return .json(documentClosingState)
    }
    guard case .string(let expectedRevision) = body["revision"],
      case .string(let scopeValue) = body["scope"], let scope = DocumentCloseScope(rawValue: scopeValue),
      scope != .window, case .string(let modeValue) = body["mode"],
      let mode = DocumentCloseMode(rawValue: modeValue)
    else { throw AutomationFailure(status: 400, message: "Required: revision, scope and mode.") }
    let usesDocument = scope == .document || scope == .others
    let keys: Set<String> = usesDocument
      ? ["revision", "scope", "mode", "sharedDocumentID"] : ["revision", "scope", "mode"]
    guard Set(body.keys) == keys else { throw AutomationFailure(status: 400, message: "Unexpected or missing closing fields.") }
    var selected: CraftNSDocument?
    if usesDocument {
      guard case .string(let rawID) = body["sharedDocumentID"], let id = UUID(uuidString: rawID),
        let document = shares.first(where: { $0.id == id })?.document
      else { throw AutomationFailure(status: 404, message: "Shared document not found.") }
      selected = document
    }
    guard expectedRevision == documentClosingRevision else {
      throw AutomationFailure(status: 409, message: "Stale closing revision. Refresh before retrying.")
    }
    let targets: [CraftNSDocument]
    if scope == .document { targets = selected.map { [$0] } ?? [] }
    else { targets = controller.closeTargets(excluding: scope == .others ? selected : nil) }
    guard coordinator.canStart(targets), targets.allSatisfy({
      $0.store.numericEditor == nil && $0.store.layerNameDraft == nil
    }), selected?.store.numericEditor == nil, selected?.store.layerNameDraft == nil
    else { throw AutomationFailure(status: 409, message: "Finish the current document operation before closing.") }
    let sharesByDocument = Dictionary(uniqueKeysWithValues: shares.compactMap { share in
      share.document.map { (ObjectIdentifier($0), share.id) }
    })
    if mode == .save {
      guard documentSavesEnabled else {
        throw AutomationFailure(status: 403, message: "Allow local document saving before automatic save-and-close.")
      }
      for document in targets where document.isDocumentEdited {
        guard sharesByDocument[ObjectIdentifier(document)] != nil else {
          throw AutomationFailure(status: 403, message: "Automatic saving requires every modified target to be shared. Use review for native save decisions.")
        }
        guard document.fileURL != nil, !document.sourceSaveNeedsReview else {
          throw AutomationFailure(status: 409, message: "Use Save As first, or review the destination in the native app.")
        }
      }
    }
    let permission = documentClosingGeneration
    let savePermission = documentSaveGeneration
    let snapshots = Dictionary(uniqueKeysWithValues: targets.map {
      (ObjectIdentifier($0), revision($0.store,includeBrush:false))
    })
    let originalDocuments = Set(controller.documents.map(ObjectIdentifier.init))
    func validate(_ document: CraftNSDocument?) throws {
      guard self.isRunning, self.documentClosingEnabled,
        self.documentClosingGeneration == permission else {
        throw AutomationFailure(status: 409, message: "Closing permission ended.")
      }
      if mode == .save {
        guard self.documentSavesEnabled, self.documentSaveGeneration == savePermission else {
          throw AutomationFailure(status: 409, message: "Saving permission ended.")
        }
      }
      guard self.controller.documents.allSatisfy({ originalDocuments.contains(ObjectIdentifier($0)) })
      else { throw DocumentCloseFailure.changed }
      if let document {
        guard snapshots[ObjectIdentifier(document)] == self.revision(document.store,includeBrush:false) else {
          throw DocumentCloseFailure.changed
        }
        if usesDocument, let selected {
          guard self.shares.contains(where: { $0.document === selected }) else {
            throw AutomationFailure(status: 409, message: "Document sharing ended.")
          }
        }
      }
    }
    let saver: DocumentCloseCoordinator.Saver? = mode == .save ? { document in
      guard let shareID = sharesByDocument[ObjectIdentifier(document)] else {
        throw AutomationFailure(status: 403, message: "Document sharing ended.")
      }
      let bytes = try JSONSerialization.data(withJSONObject: [
        "command": "document.save", "revision": self.revision(document.store),
        "parameters": [:] as [String: Any],
      ])
      return try await self.handleDocumentSave(AutomationCommand(data: bytes),
        document: document, shareID: shareID)
    } : nil
    let id: UUID
    do {
      id = try coordinator.prepare(targets, scope: scope, mode: mode,
        retained: scope == .others ? selected : nil, commitFields: false,
        validate: validate, save: saver) { [weak self] result in
          guard let self else { return }
          self.prune()
          if result.phase == .completed, scope == .quit, self.documentClosingEnabled,
            self.documentClosingGeneration == permission { self.applicationTerminator() }
        }
    } catch let error as DocumentCloseFailure {
      throw AutomationFailure(status: 409, message: error.localizedDescription)
    }
    ownedCloseOperation = id
    var response = AutomationResponse.json(documentClosingState, status: 202)
    response.didSend = { [weak self, weak coordinator] sent in
      guard let coordinator else { return }
      guard sent, let self, self.isRunning, self.documentClosingEnabled,
        self.documentClosingGeneration == permission else { coordinator.cancel(id); return }
      coordinator.start(id)
    }
    return response
  }
  static var documentClosingCapabilities: [String: Any] {
    let text: [String: Any] = ["type": "string", "minLength": 1]
    let uuid: [String: Any] = ["type": "string", "format": "uuid"]
    let boolean: [String: Any] = ["type": "boolean"]
    let count: [String: Any] = ["type": "integer", "minimum": 0]
    let operation: [String: Any] = [
      "type": ["object", "null"], "additionalProperties": false,
      "required": ["id", "scope", "mode", "phase", "total", "closed", "cancellationRequested", "error", "canCancel"],
      "properties": [
        "id": uuid, "scope": ["type": "string", "enum": DocumentCloseScope.allCases.map(\.rawValue)],
        "mode": ["type": "string", "enum": DocumentCloseMode.allCases.map(\.rawValue)],
        "phase": ["type": "string", "enum": ["queued", "reviewing", "saving", "closing", "completed", "cancelled", "failed"]],
        "total": count, "closed": count, "cancellationRequested": boolean, "canCancel": boolean,
        "error": ["type": ["string", "null"]],
      ]]
    return [
      "statePath": "/v1/document-closing", "readMethod": "GET", "startMethod": "POST",
      "cancelPath": "/v1/document-closing/cancel", "cancelMethod": "POST",
      "permission": "Separate native Allow document closing and Quit switch, off on API start/stop. All/others/quit can close unshared documents; discard explicitly loses unsaved changes.",
      "scope": "document closes sharedDocumentID; others preserves that shared document; all closes the current document set; quit closes that set and terminates only after success with no new documents.",
      "modes": "review uses native Save/Don’t Save/Cancel and Apply to All; discard explicitly discards unsaved changes; save requires local-saving permission and shared, already-associated modified targets. Use existing Save As first for unsaved/review-required files.",
      "completion": "202 queues work until the response is transmitted. Poll state while the app runs. Failed delivery/revocation cancels queued work. Quit can end the server after acceptance. Only the latest operation state is retained.",
      "cancellation": "Stops remaining work and dismisses its own review/save panel. An in-progress coordinated save finishes; saved files and already-closed documents are not rolled back.",
      "privacy": "Application counts and opaque revisions/operation IDs only. No unshared document names, paths or pixels. Recovered/remaining documents are not automatically shared.",
      "startSchema": [
        "type": "object", "additionalProperties": false,
        "required": ["revision", "scope", "mode"],
        "properties": ["revision": text, "scope": ["type": "string", "enum": ["document", "others", "all", "quit"]],
          "mode": ["type": "string", "enum": DocumentCloseMode.allCases.map(\.rawValue)], "sharedDocumentID": uuid],
        "oneOf": [
          ["properties": ["scope": ["enum": ["document", "others"]]], "required": ["sharedDocumentID"]],
          ["properties": ["scope": ["enum": ["all", "quit"]]], "not": ["required": ["sharedDocumentID"]]],
        ],
      ],
      "cancelSchema": ["type": "object", "additionalProperties": false,
        "required": ["operationID"], "properties": ["operationID": uuid]],
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": ["revision", "openDocuments", "enabled", "canStart", "operation"],
        "properties": ["revision": text, "openDocuments": count, "enabled": boolean,
          "canStart": boolean, "operation": operation]],
      "documentState": ["closeOperationID": ["type": ["string", "null"], "format": "uuid"]],
      "errors": ["400": "Invalid fields.", "401": "Invalid session token.",
        "403": "Closing/saving permission or sharing missing.", "404": "Shared document or route missing.",
        "409": "Busy/stale/unavailable, or Save As required.", "415": "Content-Type must be application/json."],
      "adobe": "No corresponding desktop Close/Close Others/Quit endpoint in the pinned Adobe v2 contract.",
    ]
  }
}
