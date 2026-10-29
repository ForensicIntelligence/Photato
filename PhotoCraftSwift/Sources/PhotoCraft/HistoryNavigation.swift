import AppKit
import PhotoCraftCore

typealias HistoryPreparation = @Sendable (EditorSession, Bool) throws -> EditorSession

enum NativeHistoryNavigation {
  static func prepare(_ session: EditorSession, redo: Bool) throws -> EditorSession {
    var candidate = session
    if redo { try candidate.redo() } else { try candidate.undo() }
    return candidate
  }
}

enum HistoryNavigationConflict: LocalizedError {
  case busy, changed
  var errorDescription: String? {
    switch self {
    case .busy: "Finish or cancel the current operation before navigating history."
    case .changed: "The document changed while restoring history. The result was not applied."
    }
  }
}

/// The immutable value-copy worker owns its scratch snapshots until it finishes.
/// Cancellation never publishes a partially restored session.
struct HistoryOperation {
  let id = UUID()
  let redo: Bool
  let authorizationID: UUID?
  let storageState: [String: Int]
  let worker: Task<EditorSession, Error>
  var cancellationRequested = false
}

extension EditorStore {
  /// Busy requests read committed accounting without waiting on a worker's scratch-write lock.
  var historyStorageState: [String: Int] {
    if let operation = historyOperation { return operation.storageState }
    return [
      "undoStates": session.undoStack.count, "redoStates": session.redoStack.count,
      "spilledStates": session.historySpilledStates,
      "residentPayloadBytes": session.residentHistoryBytes,
      "reusableCurrentRasterBytes": session.historyReusableCurrentRasterBytes,
      "sharedScratchBytes": session.historyDiskBytes,
      "residentPayloadLimitBytes": session.historyByteLimit,
      "scratchLimitBytes": session.historyDiskByteLimit,
      "cleanupFailures": session.historyCleanupFailures,
    ]
  }

  /// Synchronous menu/button entry point. Awaiting callers use undo/redo directly.
  @discardableResult func requestHistory(redo: Bool) -> Task<Bool, Never> {
    let lifecycle = layerPanelGeneration
    let generation = sessionGeneration
    return Task { [weak self] in
      guard let self, self.layerPanelGeneration == lifecycle,
        self.sessionGeneration == generation
      else { return false }
      return await (redo ? self.redo() : self.undo())
    }
  }

  func cancelActiveOperation() {
    stopObjectFinder(); stopPeopleDetection()
    geometryTask?.cancel()
    cancelHistory()
  }

  func cancelHistory() {
    guard var operation = historyOperation else { return }
    operation.cancellationRequested = true
    operation.worker.cancel()
    historyOperation = operation
  }

  /// Called when replacing/closing the document, before another operation can begin.
  func invalidateHistory() {
    guard let operation = historyOperation else { return }
    operation.worker.cancel()
    historyOperation = nil
    geometryBusy = false
  }

  @discardableResult func navigateHistory(
    redo: Bool, authorizationID: UUID? = nil,
    validate: @escaping @Sendable (CraftDocument) throws -> Void = { _ in },
    validateCommit: () throws -> Void = {}
  ) async throws -> Bool {
    guard !geometryBusy, historyOperation == nil else { throw HistoryNavigationConflict.busy }
    try Task.checkCancellation()
    guard !(redo ? session.redoStack : session.undoStack).isEmpty else { return false }
    let original = session
    let expectedSession = sessionGeneration
    let expectedLifecycle = layerPanelGeneration
    let expectedRevision = revision
    let prepare = prepareHistory
    let storage = historyStorageState
    let worker = Task.detached(priority: .userInitiated) {
      let candidate = try prepare(original, redo)
      try validate(candidate.document)
      try Task.checkCancellation()
      return candidate
    }
    let operation = HistoryOperation(
      redo: redo, authorizationID: authorizationID, storageState: storage, worker: worker)
    historyOperation = operation
    geometryBusy = true
    status = redo ? "Restoring Redo…" : "Restoring Undo…"
    var published = false
    defer {
      if historyOperation?.id == operation.id {
        historyOperation = nil
        geometryBusy = false
        // Do not render on failure: rendering increments the externally visible revision.
        if !published { status = "Ready" }
      }
    }
    let candidate = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard !worker.isCancelled, historyOperation?.cancellationRequested == false else {
      throw CancellationError()
    }
    guard historyOperation?.id == operation.id, sessionGeneration == expectedSession,
      layerPanelGeneration == expectedLifecycle, revision == expectedRevision
    else { throw HistoryNavigationConflict.changed }
    try validateCommit()
    session = candidate
    published = true
    resetPathGesture()
    selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? [])
    onChange?(redo ? .changeRedone : .changeUndone)
    render()
    status = redo ? "Redo" : "Undo"
    return true
  }
}
