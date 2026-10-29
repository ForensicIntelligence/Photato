import Foundation

extension AutomationService {
  var recentDocumentsState: [String: Any] {
    let preferences = controller.recoveryPreferences
    return [
      "revision": preferences.recentRevision.uuidString,
      "limit": preferences.value.recentFileLimit, "isPersistent": preferences.isPersistent,
      "entries": preferences.recentDocuments.map { ["id": $0.id.uuidString, "name": $0.url.lastPathComponent] },
      "canOpen": recentFilesEnabled && controller.documentOpening.canStart && preferences.loadError == nil,
      "canManage": recentFilesEnabled && !controller.recentFilesBusy && preferences.loadError == nil,
      "loadError": preferences.loadError == nil ? NSNull() : "The File Handling settings file could not be loaded." as Any,
      "lastWriteError": preferences.recentWriteError as Any? ?? NSNull(),
    ]
  }
  func handleRecentDocuments(_ request: AutomationRequest) throws -> AutomationResponse? {
    let paths = ["/v1/recent-documents", "/v1/recent-documents/limit",
      "/v1/recent-documents/clear", "/v1/recent-documents/open"]
    guard paths.contains(request.path) else { return nil }
    guard recentFilesEnabled else {
      throw AutomationFailure(status: 403, message: "Allow recent-file access in the native API window first.")
    }
    if request.path == paths[0], request.method == "GET" { return .json(recentDocumentsState) }
    guard request.method == "POST", request.path != paths[0] else {
      throw AutomationFailure(status: 404, message: "Unknown recent-file operation.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard let body = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      case .string(let revision) = body["revision"], let expected = UUID(uuidString: revision) else {
      throw AutomationFailure(status: 400, message: "Required: revision UUID.")
    }
    let keys: Set<String> = request.path == paths[1] ? ["revision", "limit"]
      : request.path == paths[3] ? ["revision", "id"] : ["revision"]
    guard Set(body.keys) == keys else { throw AutomationFailure(status: 400, message: "Unexpected recent-file fields.") }
    do {
      try controller.recoveryPreferences.validateRecentRevision(expected)
      switch request.path {
      case paths[1]:
        guard case .number(let count) = body["limit"], count.isFinite, count.rounded() == count,
          (0...100).contains(count) else { throw AutomationFailure(status: 400, message: "limit must be an integer from 0 to 100.") }
        try controller.setRecentFileLimit(Int(count), revision: expected)
      case paths[2]: try controller.clearRecentFiles(revision: expected)
      default:
        guard case .string(let raw) = body["id"], let id = UUID(uuidString: raw) else {
          throw AutomationFailure(status: 400, message: "id must be a recent document UUID.")
        }
        guard controller.recoveryPreferences.recentDocuments.contains(where: { $0.id == id }) else {
          throw AutomationFailure(status: 404, message: "Recent document not found.")
        }
        guard controller.documentOpening.canStart else {
          throw AutomationFailure(status: 409, message: "Finish the current document operation.")
        }
        let generation = recentFilesGeneration
        let operation = try controller.openRecentFile(id, revision: expected, display: true,
          validate: { [weak self] in
            guard let self, self.isRunning, self.recentFilesEnabled, self.recentFilesGeneration == generation else {
              throw CancellationError()
            }
          }, finished: { [weak self] state in
            if self?.ownedRecentOpening == state.id { self?.ownedRecentOpening = nil }
          })
        ownedRecentOpening = operation
        return .json(["operationID": operation.uuidString, "statusPath": "/v1/document-opening",
          "shared": false], status: 202)
      }
    } catch let error as AutomationFailure { throw error }
    catch let error as RecoveryPreferencesFailure {
      throw AutomationFailure(status: error == .unreadable ? 422 : 409, message: error.localizedDescription)
    } catch {
      throw AutomationFailure(status: 422, message: "The recent-file operation could not finish. Review File Handling or use File > Open.")
    }
    return .json(recentDocumentsState)
  }
  static var recentDocumentsCapabilities: [String: Any] {
    let revision: [String: Any] = ["type": "string", "format": "uuid"]
    let limit: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 100]
    func request(_ additional: [String: Any]) -> [String: Any] {
      var properties: [String: Any] = ["revision": revision]
      properties.merge(additional) { _, new in new }
      return ["type": "object", "additionalProperties": false,
        "required": properties.keys.sorted(), "properties": properties]
    }
    return [
      "statePath": "/v1/recent-documents", "readMethod": "GET",
      "clearPath": "/v1/recent-documents/clear", "clearMethod": "POST",
      "limitPath": "/v1/recent-documents/limit", "limitMethod": "POST",
      "openPath": "/v1/recent-documents/open", "openMethod": "POST",
      "permission": "Separate native Allow recent-file access; off every API session. Allows filenames, known-ID opening, clear and limit changes. No arbitrary local paths or automatic document sharing.",
      "defaultLimit": 20, "limitSchema": limit,
      "clearSchema": request([:]), "limitUpdateSchema": request(["limit": limit]),
      "openSchema": request(["id": revision]),
      "openResultSchema": ["type": "object", "additionalProperties": false,
        "required": ["operationID", "statusPath", "shared"],
        "properties": ["operationID": revision, "statusPath": ["const": "/v1/document-opening"],
          "shared": ["const": false]]],
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": ["revision", "limit", "isPersistent", "entries", "canOpen", "canManage", "loadError", "lastWriteError"],
        "properties": ["revision": revision, "limit": limit, "isPersistent": ["type": "boolean"],
          "entries": ["type": "array", "maxItems": 100,
            "items": ["type": "object", "additionalProperties": false, "required": ["id", "name"],
              "properties": ["id": revision, "name": ["type": "string"]]]],
          "canOpen": ["type": "boolean"], "canManage": ["type": "boolean"],
          "loadError": ["type": ["string", "null"]], "lastWriteError": ["type": ["string", "null"]]]],
      "lifecycle": "Successful native Open/reopen/Save/Save As update a bounded most-recent-first list with canonical deduplication and bookmark relocation. Failed/cancelled opens, recovery-only opens, unsaved uploads and copies do not add entries. Limit0 clears/stops recording; decreasing the limit trims oldest records atomically with preferences. Clear deletes references, never images.",
      "reopen": "Returns202 and opens through the native coordinator; poll document-opening. Existing dirty documents retain identity. Permission/session/recent-list revision are rechecked before publication. Disabling recent access cancels its pending reopen; already-opened documents remain.",
      "cancellation": "The document-opening cancel route additionally accepts an operation owned by this enabled recent-file session, without requiring transfer permission.",
      "storage": "One bounded atomic version3 File Handling archive retains recovery, recent files and Photoshop compression preferences. Legacy version1 recovery settings load with empty history/default20; versions1/2 retain prior compression defaults. Older readers reject version3 rather than discard preferences. Successful image operations stay successful if recent-history persistence fails; lastWriteError reports the failure. External archive changes reject rather than overwrite; restart reloads external state.",
      "errors": ["400": "Invalid fields/limit/UUID", "401": "Authentication", "403": "Recent access disabled",
        "404": "Missing recent ID/route", "409": "Busy/stale/external change", "415": "Content type", "422": "Settings/resolve failure"],
      "limits": "Bookmarks may fail across sandbox/volume changes; use Open to reauthorize. Live Photoshop preference/default/menu and physical Intel/macOS14 qualification remain open.",
      "adobe": "No corresponding desktop recent-file/history/settings endpoint in the pinned Adobe v2 contract.",
    ]
  }
}
