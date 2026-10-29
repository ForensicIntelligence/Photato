import Foundation

extension AutomationService {
  var recoverySalvageState: [String: Any] {
    let salvage = controller.recoveryMaintenance.salvage
    let ready = recoveryBackupsEnabled && salvage.canScan && !salvage.isStale
    return [
      "revision": salvage.revision.uuidString, "isBusy": salvage.manager.isBusy,
      "isStale": salvage.isStale, "canScan": recoveryBackupsEnabled && salvage.canScan,
      "canResetIndex": recoveryBackupsEnabled && salvage.canResetIndex,
      "examinedEntries": salvage.examined, "maximumEntries": RecoverySalvageScan.maximumEntries,
      "lastError": salvage.lastError as Any? ?? NSNull(),
      "indexError": controller.recoveryIndex.loadError as Any? ?? NSNull(),
      "items": salvage.items.map {
        ["id": $0.id.uuidString, "name": $0.name, "metadata": $0.contextKind,
         "registration": $0.registration, "bytes": $0.stamp.size,
         "canOpenCopy": ready, "canDownload": ready] as [String: Any]
      },
    ]
  }
  func handleRecoverySalvage(_ request: AutomationRequest) async throws -> AutomationResponse? {
    let base = "/v1/recovery/salvage", actions = ["scan", "open-copy", "download", "reset-index"]
    guard request.path == base || actions.contains(where: { request.path == base + "/" + $0 }) else { return nil }
    guard recoveryBackupsEnabled else {
      throw AutomationFailure(status: 403, message: "Allow recovery-backup access in the native API window first.")
    }
    if request.method == "GET", request.path == base { return .json(recoverySalvageState) }
    guard request.method == "POST", request.path != base else {
      throw AutomationFailure(status: 404, message: "Unknown recovery salvage operation.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    let action = String(request.path.dropFirst(base.count + 1))
    let usesID = action == "open-copy" || action == "download"
    var fields: Set<String> = ["revision"]
    if usesID { fields.insert("id") }
    if action == "reset-index" { fields.insert("confirmed") }
    guard let body = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      Set(body.keys) == fields, case .string(let raw) = body["revision"],
      let revision = UUID(uuidString: raw) else {
      throw AutomationFailure(status: 400, message: "Supply the exact fields and current salvage revision UUID.")
    }
    if action == "reset-index" {
      guard case .bool(true) = body["confirmed"] else {
        throw AutomationFailure(status: 400, message: "confirmed:true is required to reset the index.")
      }
    }
    let salvage = controller.recoveryMaintenance.salvage
    var id: UUID?
    if usesID {
      guard case .string(let rawID) = body["id"], let value = UUID(uuidString: rawID) else {
        throw AutomationFailure(status: 400, message: "id must be a scanned item UUID.")
      }
      guard salvage.items.contains(where: { $0.id == value }) else {
        throw AutomationFailure(status: 404, message: "Scanned recovery file not found.")
      }
      id = value
    }
    let generation = recoveryBackupsGeneration
    func validate() throws { try validateRecoveryBackups(generation) }
    do {
      switch action {
      case "scan": try await salvage.scan(revision: revision, validate: validate)
      case "open-copy":
        let document = try await salvage.openCopy(id!, revision: revision, display: true, validate: validate)
        return .json(["documentID": document.store.document.id.uuidString, "shared": false], status: 201)
      case "download":
        let bytes = try await salvage.download(id!, revision: revision,
          maximumBytes: DocumentIO.maximumDownloadBytes, validate: validate)
        return .init(status: 200, contentType: DocumentIO.Format.native.mediaType, body: bytes)
      default: try await salvage.resetIndex(revision: revision, validate: validate)
      }
      try validate()
      return .json(recoverySalvageState)
    } catch let error as AutomationFailure { throw error }
    catch let error as RecoveryIndexFailure {
      throw AutomationFailure(status: error == .busy || error == .changed ? 409 : 422,
        message: error == .limit ? "The recovery scan or index exceeds its size limit." : error.localizedDescription)
    } catch is CancellationError {
      throw AutomationFailure(status: 409, message: "Recovery salvage cancelled.")
    } catch {
      throw AutomationFailure(status: 422, message: "Recovery salvage did not finish. Scan again to review current files.")
    }
  }
  static var recoverySalvageCapabilities: [String: Any] {
    let uuid: [String: Any] = ["type": "string", "format": "uuid"]
    let boolean: [String: Any] = ["type": "boolean"]
    func object(_ properties: [String: Any]) -> [String: Any] {
      ["type": "object", "additionalProperties": false,
       "properties": properties, "required": properties.keys.sorted()]
    }
    let item = object(["id": uuid, "name": ["type": "string"],
      "metadata": ["enum": ["current", "legacy", "none", "unverified"]],
      "registration": ["enum": ["registered", "retired", "unregistered", "unknown"]],
      "bytes": ["type": "integer", "minimum": 0], "canOpenCopy": boolean, "canDownload": boolean])
    return [
      "statePath": "/v1/recovery/salvage", "stateMethod": "GET",
      "operations": ["scan", "open-copy", "download", "reset-index"].map {
        ["method": "POST", "path": "/v1/recovery/salvage/" + $0]
      },
      "scanSchema": object(["revision": uuid]),
      "copySchema": object(["revision": uuid, "id": uuid]),
      "resetIndexSchema": object(["revision": uuid, "confirmed": ["const": true]]),
      "stateSchema": object(["revision": uuid, "isBusy": boolean, "isStale": boolean,
        "canScan": boolean, "canResetIndex": boolean,
        "examinedEntries": ["type": "integer", "minimum": 0, "maximum": RecoverySalvageScan.maximumEntries],
        "maximumEntries": ["const": RecoverySalvageScan.maximumEntries],
        "lastError": ["type": ["string", "null"]], "indexError": ["type": ["string", "null"]],
        "items": ["type": "array", "maxItems": RecoverySalvageScan.maximumEntries, "items": item]]),
      "openCopyResultSchema": object(["documentID": uuid, "shared": ["const": false]]),
      "permission": "Uses the separate session-off recovery-backup access permission, including GET. No arbitrary local path or automatic document sharing.",
      "scan": "Explicit, nonrecursive private Archives scan, at most1024 directory entries including skipped files. Only regular .photato files are listed. Symlinks/subdirectories are skipped. Current, legacy, absent or damaged recovery metadata never authorizes automatic restoration. Oversized scans publish no partial result.",
      "copy": "Full background native decoding and identity checks; recovery provenance is discarded. Open Copy creates a fresh unsaved document ID; download returns ordinary native11 capped at128MiB. Damaged image data still rejects.",
      "resetIndex": "Requires confirmed:true, a fresh scan, no open documents and an unreadable regular index up to2MiB. Preserves exact old index bytes in the private recovery folder before atomically writing an empty index. Archives/originals remain untouched and are not re-registered. Failure may leave an additional preserved index copy. No registration Undo.",
      "lifecycle": "Shared maintenance exclusion guards native opening/closing/recovery/autosave/import. Scan revision, filesystem metadata and session permission are checked before publishing. Rescan after changes; IDs are scan-local.",
      "errors": ["400": "Fields/UUID/confirmation", "401": "Authentication", "403": "Backup permission revoked/disabled",
        "404": "Unknown scanned item/route", "409": "Busy/stale/cancelled or open documents prevent reset",
        "415": "Content type", "422": "Read/decode/scan or index limit/reset failure"],
      "limits": "Private Archives folder only; no scan of arbitrary/legacy external locations. No filesystem compare-and-swap, complete platform or Photoshop parity claim.",
      "adobe": "No equivalent desktop recovery-salvage operation in the pinned Adobe v2 contract.",
    ]
  }
}
