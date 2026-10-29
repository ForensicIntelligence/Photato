import Foundation

extension AutomationService {
  var recoveryDiscoveryState: [String: Any] {
    let index = controller.recoveryIndex
    return [
      "revision": index.revision.uuidString,
      "isPersistent": index.directoryURL != nil,
      "registeredCount": Set(index.entries.filter { $0.state != .retired }.map(\.recoveryID)).count,
      "isDiscovering": index.isDiscovering,
      "canRetry": recoveryManagementEnabled && controller.recoveryDiscovery.canStart,
      "operation": controller.recoveryDiscovery.state.map { state -> [String: Any] in
        ["id": state.id.uuidString, "active": state.active, "phase": state.phase,
         "totalEntries": state.totalEntries, "completedEntries": state.completedEntries,
         "cancellationRequested": state.cancellationRequested,
         "canCancel": recoveryManagementEnabled && state.active && !state.cancellationRequested,
         "memory": ["limitBytes": state.memory.limitBytes,
           "estimatedUsedBytes": state.memory.estimatedUsedBytes,
           "availableBytes": state.memory.availableBytes,
           "metadataReadLimitBytes": state.memory.metadataReadLimitBytes],
         "deferredByReason": state.deferredByReason]
      } as Any? ?? NSNull(),
      "lastDiscovered": index.lastDiscovered, "lastAlreadyOpen": index.lastAlreadyOpen,
      "lastMissing": index.lastMissing, "lastInvalid": index.lastInvalid,
      "lastUnavailable": index.lastUnavailable,
      "lastDeferred": index.lastDeferred,
      "loadError": index.loadError as Any? ?? NSNull(),
      "writeError": index.writeError as Any? ?? NSNull(),
      "discoveryError": index.discoveryError as Any? ?? NSNull(),
    ]
  }
  func validateRecoveryManagement(_ expected: UUID) throws {
    guard isRunning, recoveryManagementEnabled, recoveryManagementGeneration == expected else {
      throw AutomationFailure(status: 403, message: "Recovery management permission ended.")
    }
  }
  func handleRecoveryDiscovery(_ request: AutomationRequest) async throws -> AutomationResponse? {
    if request.path == "/v1/recovery", request.method == "GET" {
      return .json(recoveryDiscoveryState)
    }
    guard ["/v1/recovery/retry", "/v1/recovery/cancel"].contains(request.path) else { return nil }
    guard request.method == "POST" else {
      throw AutomationFailure(status: 404, message: "Unknown recovery operation.")
    }
    guard recoveryManagementEnabled else {
      throw AutomationFailure(status: 403, message: "Allow recovery management in the native API window first.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json"
    else { throw AutomationFailure(status: 415, message: "Content-Type must be application/json.") }
    let cancelling = request.path.hasSuffix("/cancel")
    let key = cancelling ? "operationID" : "revision"
    guard let values = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      Set(values.keys) == [key], case .string(let value) = values[key], let revision = UUID(uuidString: value)
    else { throw AutomationFailure(status: 400, message: "Supply the required UUID with no additional fields.") }
    if cancelling {
      guard controller.recoveryDiscovery.cancel(revision) else {
        throw AutomationFailure(status: 409, message: "That recovery operation is no longer active.")
      }
      return .json(recoveryDiscoveryState)
    }
    let generation = recoveryManagementGeneration
    var owned: UUID?
    defer {
      if ownedRecoveryDiscovery == owned { ownedRecoveryDiscovery = nil }
    }
    do {
      try controller.recoveryIndex.validateRevision(revision)
      try await controller.discoverIndexedRecovery(display: true, expectedRevision: revision, started: {
        owned = $0; self.ownedRecoveryDiscovery = $0
      }) {
        try self.validateRecoveryManagement(generation)
      }
    } catch let error as RecoveryIndexFailure {
      throw AutomationFailure(status: error == .busy || error == .changed ? 409 : 422,
        message: error.localizedDescription)
    } catch let error as RecoveryMemoryFailure {
      throw AutomationFailure(status: 409, message: error.localizedDescription)
    } catch let error as AutomationFailure { throw error }
    catch is CancellationError {
      throw AutomationFailure(status: 409, message: "Recovery cancelled. Existing backups remain available for retry.")
    }
    catch {
      throw AutomationFailure(status: 422, message: "Recovery discovery could not finish. Existing backups are preserved.")
    }
    return .json(recoveryDiscoveryState)
  }
  static var recoveryRegistrationSchema: [String: Any] {
    ["type": "object", "additionalProperties": false,
      "required": ["status", "isPersistent", "lastError"],
      "properties": [
        "status": ["type": "string", "enum": ["none", "intent", "ready", "retired", "failed"]],
        "isPersistent": ["type": "boolean"], "lastError": ["type": ["string", "null"]],
      ]]
  }
  static var recoveryDiscoveryCapabilities: [String: Any] {
    let boolean: [String: Any] = ["type": "boolean"]
    let count: [String: Any] = ["type": "integer", "minimum": 0]
    let revision: [String: Any] = ["type": "string", "format": "uuid"]
    let error: [String: Any] = ["type": ["string", "null"]]
    let operation: [String: Any] = [
      "id": revision, "active": boolean,
      "phase": ["enum": ["accounting", "inspecting", "decoding", "publishing", "completed", "cancelled", "failed"]],
      "totalEntries": count, "completedEntries": count,
      "cancellationRequested": boolean, "canCancel": boolean,
      "memory": ["type": "object", "additionalProperties": false,
        "required": ["limitBytes", "estimatedUsedBytes", "availableBytes", "metadataReadLimitBytes"],
        "properties": ["limitBytes": count, "estimatedUsedBytes": count,
          "availableBytes": count, "metadataReadLimitBytes": count]],
      "deferredByReason": ["type": "object", "additionalProperties": false,
        "required": ["aggregate", "metadata", "raster", "workspaceGrowth"],
        "properties": ["aggregate": count, "metadata": count, "raster": count, "workspaceGrowth": count]],
    ]
    let properties: [String: Any] = [
      "revision": revision, "isPersistent": boolean, "registeredCount": count,
      "isDiscovering": boolean, "canRetry": boolean, "lastDiscovered": count,
      "lastAlreadyOpen": count, "lastMissing": count, "lastInvalid": count,
      "lastUnavailable": count, "lastDeferred": count, "loadError": error, "writeError": error, "discoveryError": error,
      "operation": ["type": ["object", "null"], "additionalProperties": false,
        "required": operation.keys.sorted(), "properties": operation],
    ]
    return [
      "statePath": "/v1/recovery", "stateMethod": "GET",
      "retryPath": "/v1/recovery/retry", "retryMethod": "POST",
      "cancelPath": "/v1/recovery/cancel", "cancelMethod": "POST",
      "permission": "Native Allow recovery management toggle, off on API start/stop. Permits retry and cancellation of any active indexed recovery, including native startup. Revocation cancels this session's own retry, not an unrelated native recovery. Recovery does not share documents.",
      "scope": "Application-wide recovery discovery, independent of document shares and Undo history.",
      "storage": "Private native archives with a bounded atomic index and per-snapshot tokens. Intent records precede archive publication; valid backups can recover before finalization.",
      "privacy": "Counts, estimated capacity and sanitized errors only; no source paths, names, bookmarks or document contents.",
      "completion": "Retry waits and returns200 on completion, including partial completion with lastDeferred greater than zero. Workspace accounting, metadata, full native decoding, color validation, fingerprint and source-format preparation run off MainActor. A scoped prepared-read handoff keeps AppKit recovery bookkeeping. Original verification may still be checking. Missing entries are rechecked before pruning; invalid/unavailable/deferred backups remain.",
      "cancellation": "POST cancel takes operationID and returns current state; active may stay true until the worker acknowledges. Earlier recovered documents stay open, remaining backups stay registered, and queued File Open requests resume. Cancelled retry returns409; revoked session retry returns403. Decoder cancellation is cooperative.",
      "memoryPolicy": "Automatic indexed recovery uses one quarter of physical RAM, clamped256MiB..4GiB. This is original Photato admission policy, not a Photoshop preference. Estimated use includes current document payload, additional resident history, metadata allowance and a canvas render allowance (two Float32 RGBA and two 8-bit buffers rounded to tile edges), or larger measured retained render buffers. The memory object is the latest stable accounting snapshot, not live RSS. Metadata reads are capped before allocation at min64MiB/one quarter remaining allowance, with four times actual manifest bytes reserved during preparation. Raster expansion uses the remaining allowance up to the existing1GiB per-file limit. Publication recounts workspace use. Deferrals preserve the latest recovery group without restoring an older snapshot instead; closing documents and retrying recalculates capacity.",
      "lifecycle": "Snapshot token, archive identity, index bytes/revision, generation, permission and workspace capacity are rechecked before publication. Accounting snapshots recheck document/session/render identity; repeated concurrent changes return409. Index I/O, AppKit bookkeeping, construction and window presentation remain on MainActor. Admission estimates do not cap total process/GPU/draft allocations or implement paging; external AppKit restoration and explicit Open/Review Backup retain existing per-file behavior. Complete memory/platform/Photoshop parity remains open.",
      "retrySchema": ["type": "object", "additionalProperties": false,
        "required": ["revision"], "properties": ["revision": revision]],
      "cancelSchema": ["type": "object", "additionalProperties": false,
        "required": ["operationID"], "properties": ["operationID": revision]],
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": properties.keys.sorted(), "properties": properties],
      "errors": ["400": "Invalid body.", "401": "Invalid session token.",
        "403": "Permission disabled or revoked.", "409": "Busy, stale, cancelled or changed workspace/index/operation.",
        "415": "Content-Type must be application/json.", "422": "Recovery read/write failure."],
      "adobe": "No corresponding desktop recovery endpoint in the pinned Adobe v2 contract.",
    ]
  }
}
