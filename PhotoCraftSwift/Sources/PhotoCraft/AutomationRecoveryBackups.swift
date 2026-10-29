import Foundation

extension AutomationService {
  var recoveryBackupsState: [String: Any] {
    let manager = controller.recoveryMaintenance, index = controller.recoveryIndex
    let ready = recoveryBackupsEnabled && manager.canStart && !manager.isStale
    return [
      "revision": index.revision.uuidString,
      "inspectedRevision": manager.inspectedRevision?.uuidString as Any? ?? NSNull(),
      "isPersistent": index.directoryURL != nil, "isBusy": manager.isBusy,
      "isStale": manager.isStale, "canInspect": recoveryBackupsEnabled && manager.canStart,
      "entryCount": index.entries.count, "maximumEntries": RecoveryIndexStore.maximumEntries,
      "availableEntries": max(0, RecoveryIndexStore.maximumEntries - index.entries.count),
      "lastError": manager.lastError as Any? ?? NSNull(),
      "loadError": index.loadError as Any? ?? NSNull(),
      "items": manager.items.map { item -> [String: Any] in
        let open = manager.isOpen(item.id), valid = item.status == .available
        return [
          "id": item.id.uuidString, "snapshotID": item.entry.snapshotID.uuidString,
          "name": item.name, "registration": item.registration.rawValue, "status": item.status.rawValue,
          "bytes": item.bytes as Any? ?? NSNull(),
          "modifiedAt": item.modified.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(),
          "isOpen": open, "canOpenCopy": ready && valid, "canDownload": ready && valid,
          "canTrash": ready && valid && !open, "canForget": ready && !open,
        ]
      },
    ]
  }
  func validateRecoveryBackups(_ expected: UUID) throws {
    guard isRunning, recoveryBackupsEnabled, recoveryBackupsGeneration == expected else {
      throw AutomationFailure(status: 403, message: "Recovery-backup access ended.")
    }
  }
  func handleRecoveryBackups(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let base = "/v1/recovery/backups"
    let actions = ["inspect", "open-copy", "download", "trash", "forget", "remove-missing"]
    guard request.path == base || actions.contains(where: { request.path == base + "/" + $0 })
    else { return nil }
    guard recoveryBackupsEnabled else {
      throw AutomationFailure(status: 403, message: "Allow recovery-backup access in the native API window first.")
    }
    if request.path == base, request.method == "GET" { return .json(recoveryBackupsState) }
    guard request.method == "POST", request.path != base else {
      throw AutomationFailure(status: 404, message: "Unknown recovery-backup operation.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    let action = String(request.path.dropFirst(base.count + 1))
    let usesID = !["inspect", "remove-missing"].contains(action)
    let needsConfirmation = ["trash", "forget"].contains(action)
    var required: Set<String> = ["revision"]
    if usesID { required.insert("id") }
    if needsConfirmation { required.insert("confirmed") }
    guard let body = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      Set(body.keys) == required, case .string(let raw) = body["revision"],
      let revision = UUID(uuidString: raw) else {
      throw AutomationFailure(status: 400, message: "Supply the exact fields and current revision UUID.")
    }
    var id: UUID?
    if usesID {
      guard case .string(let value) = body["id"], let parsed = UUID(uuidString: value) else {
        throw AutomationFailure(status: 400, message: "id must be a recovery group UUID.")
      }
      id = parsed
      guard controller.recoveryIndex.entries.contains(where: { $0.recoveryID == parsed }) else {
        throw AutomationFailure(status: 404, message: "Recovery backup not found.")
      }
    }
    if needsConfirmation {
      guard case .bool(true) = body["confirmed"] else {
        throw AutomationFailure(status: 400, message: "confirmed:true is required for this cleanup operation.")
      }
    }
    let generation = recoveryBackupsGeneration
    let manager = controller.recoveryMaintenance
    func validate() throws { try validateRecoveryBackups(generation) }
    do {
      switch action {
      case "inspect": try await manager.refresh(revision: revision, validate: validate)
      case "open-copy":
        let document = try await manager.openCopy(id!, revision: revision, display: true, validate: validate)
        return .json(["documentID": document.store.document.id.uuidString, "shared": false], status: 201)
      case "download":
        let bytes = try await manager.download(id!, revision: revision,
          maximumBytes: DocumentIO.maximumDownloadBytes, validate: validate)
        return .init(status: 200, contentType: DocumentIO.Format.native.mediaType, body: bytes)
      case "trash": try await manager.trash(id!, revision: revision, validate: validate)
      case "forget": try await manager.forget(id!, revision: revision, validate: validate)
      default: try await manager.removeMissing(revision: revision, validate: validate)
      }
    } catch let error as AutomationFailure { throw error }
    catch let error as RecoveryIndexFailure {
      throw AutomationFailure(status: error == .busy || error == .changed ? 409 : 422,
        message: error.localizedDescription)
    } catch is CancellationError {
      throw AutomationFailure(status: 409, message: "Recovery-backup operation cancelled.")
    } catch {
      throw AutomationFailure(status: 422,
        message: "The backup operation did not finish. Refresh the list to review its current state.")
    }
    try validate()
    return .json(recoveryBackupsState)
  }
  static var recoveryBackupsCapabilities: [String: Any] {
    let uuid: [String: Any] = ["type": "string", "format": "uuid"]
    let boolean: [String: Any] = ["type": "boolean"]
    let error: [String: Any] = ["type": ["string", "null"]]
    let count: [String: Any] = ["type": "integer", "minimum": 0]
    func request(_ id: Bool, _ confirmed: Bool = false) -> [String: Any] {
      var fields: [String: Any] = ["revision": uuid]
      if id { fields["id"] = uuid }
      if confirmed { fields["confirmed"] = ["const": true] }
      return ["type": "object", "additionalProperties": false,
        "required": fields.keys.sorted(), "properties": fields]
    }
    let item: [String: Any] = [
      "id": uuid, "snapshotID": uuid, "name": ["type": "string"],
      "registration": ["enum": ["intent", "ready", "retired"]],
      "status": ["enum": ["available", "missing", "invalid", "unavailable"]],
      "bytes": ["type": ["integer", "null"], "minimum": 0],
      "modifiedAt": ["type": ["string", "null"], "format": "date-time"],
      "isOpen": boolean, "canOpenCopy": boolean, "canDownload": boolean,
      "canTrash": boolean, "canForget": boolean,
    ]
    let state: [String: Any] = [
      "revision": uuid, "inspectedRevision": ["type": ["string", "null"], "format": "uuid"],
      "isPersistent": boolean, "isBusy": boolean, "isStale": boolean, "canInspect": boolean,
      "entryCount": count, "maximumEntries": ["const": RecoveryIndexStore.maximumEntries],
      "availableEntries": count, "lastError": error, "loadError": error,
      "items": ["type": "array", "maxItems": RecoveryIndexStore.maximumEntries,
        "items": ["type": "object", "additionalProperties": false,
          "required": item.keys.sorted(), "properties": item]],
    ]
    return [
      "statePath": "/v1/recovery/backups", "stateMethod": "GET",
      "permission": "Separate Allow recovery-backup access, off every API session. Exposes backup names, native content, independent copy opening and explicit cleanup. Does not grant arbitrary path access or share recovered copies.",
      "operations": ["inspect", "open-copy", "download", "trash", "forget", "remove-missing"].map {
        ["method": "POST", "path": "/v1/recovery/backups/" + $0]
      },
      "inspectSchema": request(false), "removeMissingSchema": request(false),
      "openCopySchema": request(true), "downloadSchema": request(true),
      "trashSchema": request(true, true), "forgetSchema": request(true, true),
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": state.keys.sorted(), "properties": state],
      "openCopyResultSchema": ["type": "object", "additionalProperties": false,
        "required": ["documentID", "shared"], "properties": ["documentID": uuid, "shared": ["const": false]]],
      "inspection": "Explicit asynchronous metadata inspection, one row per recovery group; chooses a matching committed snapshot over a newer unfinished intent. available verifies metadata only; opening/download performs full decoding. GET returns the cached list and isStale; refresh after mutations or external changes.",
      "copy": "Open Copy creates an unsaved document with a fresh document ID, unchanged layer/content values, no source/recovery association and no implicit sharing. Download returns ordinary native11 without private recovery context, bounded to128MiB.",
      "trash": "Requires confirmed:true and an inactive group with matching archive metadata/identity. Atomically retires its matching registration before a coordinated native Move to Trash, then removes registration. Once the move starts it completes cleanup even if permission ends. Failures may leave a retired or missing record; inspect and retry/remove missing. Never permanently deletes an archive.",
      "forget": "Requires confirmed:true and an inactive group. Removes all group registrations, preventing automatic recovery through this index; archive bytes remain untouched. Useful for missing/unrecognized/unavailable records. Cannot restore forgotten registration through this API.",
      "removeMissing": "Removes only still-missing inactive groups, without deleting any file. Frees index capacity; active documents are protected.",
      "lifecycle": "Maintenance, startup discovery, native opening/closing and autosave writes exclude one another. Revision/session/permission are checked before publication; explicit cleanup rechecks ownership. Existing discovery counts/retry permission remains separate.",
      "errors": ["400": "Invalid fields/UUID/confirmation", "401": "Authentication",
        "403": "Backup access disabled/revoked", "404": "Unknown group/route",
        "409": "Busy/stale/cancelled", "415": "Content type", "422": "Read/decode/output limit/index/Trash failure"],
      "limits": "This indexed list does not adopt orphan archives. Separate recoverySalvage routes provide explicit private-folder copies and confirmed damaged-index reset. Coordinated identity checks are not filesystem compare-and-swap. Full live/platform/sandbox/power-loss and Photoshop parity remain open.",
      "adobe": "No corresponding desktop backup-maintenance endpoint in the pinned Adobe v2 contract.",
    ]
  }
}
