import AppKit
import Observation
import PhotoCraftCore

@MainActor @Observable final class RecoveryDiscovery {
  struct State {
    let id: UUID
    let totalEntries: Int
    var completedEntries = 0
    var phase = "inspecting"
    var active = true
    var cancellationRequested = false
    var memory: RecoveryMemoryUsage
    var deferredByReason = ["aggregate": 0, "metadata": 0, "raster": 0, "workspaceGrowth": 0]
  }
  typealias Reader = @Sendable (RecoveryIndexEntry, RecoveryReadAllowance) throws -> PreparedIndexedRecovery
  unowned let controller: CraftDocumentController
  private(set) var state: State?
  private(set) var generation = UUID()
  @ObservationIgnored var reader: Reader = PreparedIndexedRecovery.read
  @ObservationIgnored var accountant: @Sendable ([RecoveryMemoryInput]) throws -> Int = RecoveryMemoryInput.used
  @ObservationIgnored var memoryLimitBytes = RecoveryMemoryPolicy.defaultLimit
  @ObservationIgnored private var cancelWorker: (() -> Void)?
  @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
  @ObservationIgnored private var progress: RecoveryDiscoveryWindowController?
  init(controller: CraftDocumentController) { self.controller = controller }
  var canStart: Bool {
    !controller.recoveryIndex.isBusy && !controller.documentOpening.isActive
      && controller.documentOpenPanel == nil && !controller.documentClosing.isActive
      && !controller.recoveryPreferencesBusy && controller.documentWindows.canChangeDocument
      && NSApp?.modalWindow == nil
  }
  @discardableResult func cancel(_ id: UUID) -> Bool {
    guard state?.id == id, state?.active == true else { return false }
    state?.cancellationRequested = true
    cancelWorker?()
    return true
  }
  func waitUntilIdle() async {
    // A new retry can start before a resumed caller gets MainActor again.
    while state?.active == true {
      await withCheckedContinuation { waiters.append($0) }
    }
  }
  func dismissProgress() {
    guard state?.active != true else { return }
    progress?.close(); progress = nil
  }
  private func memoryUsage(limit: Int) async throws -> RecoveryMemoryUsage {
    // AppKit can restore several documents while initial discovery is starting.
    // Allow that finite startup work to settle, but never publish stale accounting
    // or wait indefinitely for a workspace that is continually changing.
    for attempt in 0..<8 {
      try Task.checkCancellation()
      guard state?.cancellationRequested != true else { throw CancellationError() }
      let signature = controller.recoveryMemorySignature
      let values = controller.recoveryMemoryInputs
      let accountant = self.accountant
      let worker = Task.detached(priority: .utility) { try accountant(values) }
      cancelWorker = { worker.cancel() }
      let used = try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
      cancelWorker = nil
      if controller.recoveryMemorySignature == signature {
        return .init(limitBytes: limit, estimatedUsedBytes: used)
      }
      if attempt < 7 { try await Task.sleep(for: .milliseconds(20)) }
    }
    throw RecoveryMemoryFailure.workspaceChanged
  }
  func run(display: Bool, expectedRevision: UUID?, validate: () throws -> Void,
    started: (UUID) -> Void) async throws
  {
    let index = controller.recoveryIndex
    guard canStart else { throw RecoveryIndexFailure.busy }
    try validate()
    index.reload()
    guard index.loadError == nil else { throw RecoveryIndexFailure.unreadable }
    if let expectedRevision { try index.validateCurrentRevision(expectedRevision) }
    let entries = index.entries.sorted { $0.sequence > $1.sequence }
    let memoryLimit = max(0, memoryLimitBytes)
    progress?.close(); progress = nil
    state = .init(id: UUID(), totalEntries: entries.count,
      memory: .init(limitBytes: memoryLimit, estimatedUsedBytes: 0))
    generation = UUID()
    let session = controller.recoveryDiscoveryGeneration
    var revision = index.revision
    index.isDiscovering = true
    index.lastDiscovered = 0; index.lastAlreadyOpen = 0
    index.lastMissing = 0; index.lastInvalid = 0; index.lastUnavailable = 0
    index.lastDeferred = 0
    index.discoveryError = nil
    started(state!.id)
    if display && !entries.isEmpty {
      progress = RecoveryDiscoveryWindowController(discovery: self)
      progress?.showWindow(nil)
    }
    defer {
      cancelWorker = nil; state?.active = false; index.isDiscovering = false
      if index.lastDeferred == 0 { progress?.close(); progress = nil }
      let pending = waiters; waiters = []
      for waiter in pending { waiter.resume() }
    }
    func check() throws {
      try validate()
      try Task.checkCancellation()
      guard state?.cancellationRequested != true else { throw CancellationError() }
      guard controller.recoveryDiscoveryGeneration == session else { throw RecoveryIndexFailure.changed }
      try index.validateCurrentRevision(revision)
    }
    func alreadyOpen(_ entry: RecoveryIndexEntry) -> Bool {
      controller.documents.contains {
        ($0 as? CraftNSDocument)?.recoverySnapshotContext?.recoveryID == entry.recoveryID
      }
    }
    var groups: Set<UUID> = [], missing: [RecoveryIndexEntry] = []
    func deferEntry(_ entry: RecoveryIndexEntry, reason: String) {
      groups.insert(entry.recoveryID)
      index.lastDeferred += 1
      state?.deferredByReason[reason, default: 0] += 1
    }
    do {
      state?.phase = "accounting"
      let initialUsage = try await memoryUsage(limit: memoryLimit)
      try check()
      state?.memory = initialUsage
      for entry in entries {
        try check()
        defer { state?.completedEntries += 1 }
        if groups.contains(entry.recoveryID) { continue }
        if entry.state != .retired && alreadyOpen(entry) {
          groups.insert(entry.recoveryID); index.lastAlreadyOpen += 1; continue
        }
        if entry.state == .retired {
          let worker = Task.detached(priority: .utility) { try RecoveryFileStamp.read(entry.backupURL) }
          cancelWorker = { worker.cancel() }
          let result = await withTaskCancellationHandler(operation: { await worker.result },
            onCancel: { worker.cancel() })
          cancelWorker = nil
          try check()
          groups.insert(entry.recoveryID)
          // Distinguish an actual missing path from an unreadable path.
          if case .success(nil) = result { missing.append(entry) }
          continue
        }
        state?.phase = "accounting"
        let usage = try await memoryUsage(limit: memoryLimit)
        try check()
        state?.memory = usage
        if usage.availableBytes == 0 {
          deferEntry(entry, reason: "aggregate"); continue
        }
        state?.phase = "inspecting"
        let inspector = Task.detached(priority: .utility) {
          IndexedRecoveryCandidate.inspect(entry, maximumMetadataBytes: usage.metadataReadLimitBytes)
        }
        cancelWorker = { inspector.cancel() }
        let candidate = await withTaskCancellationHandler(operation: { await inspector.value },
          onCancel: { inspector.cancel() })
        cancelWorker = nil
        try check()
        if alreadyOpen(entry) { groups.insert(entry.recoveryID); index.lastAlreadyOpen += 1; continue }
        if candidate.capacityLimited {
          deferEntry(entry, reason: "metadata"); continue
        }
        if let issue = candidate.issue {
          switch issue {
          case .missing: missing.append(entry); index.lastMissing += 1
          case .invalid: index.lastInvalid += 1
          case .unavailable: index.lastUnavailable += 1
          }
          continue
        }
        guard let metadata = candidate.metadata,
          let allowance = RecoveryMemoryPolicy.allowance(metadata, usage: usage) else {
          deferEntry(entry, reason: "aggregate"); continue
        }
        do {
          state?.phase = "decoding"
          let reader = self.reader
          let worker = Task.detached(priority: .utility) { try reader(entry, allowance) }
          cancelWorker = { worker.cancel() }
          let prepared = try await withTaskCancellationHandler(operation: { try await worker.value },
            onCancel: { worker.cancel() })
          cancelWorker = nil
          try check()
          if alreadyOpen(entry) { groups.insert(entry.recoveryID); index.lastAlreadyOpen += 1; continue }
          state?.phase = "accounting"
          let currentUsage = try await memoryUsage(limit: memoryLimit)
          try check()
          state?.memory = currentUsage
          if alreadyOpen(entry) { groups.insert(entry.recoveryID); index.lastAlreadyOpen += 1; continue }
          if RecoveryMemoryPolicy.documentCost(prepared.contents.document) > currentUsage.availableBytes {
            deferEntry(entry, reason: currentUsage.estimatedUsedBytes > usage.estimatedUsedBytes
              ? "workspaceGrowth" : "aggregate")
            continue
          }
          try prepared.validateUnchanged()
          state?.phase = "publishing"
          let collision = entry.sourceURL.flatMap { controller.document(for: $0) } != nil
          let document = try RecoveryReadHandoff.makeDocument(prepared, controller: controller,
            source: collision ? nil : entry.sourceURL)
          controller.addDocument(document)
          do {
            try index.finish(entry.snapshotID); revision = index.revision
            document.recoveryRegistrationError = nil
          } catch { document.recoveryRegistrationError = "The backup was recovered, but registration needs attention." }
          if collision {
            document.sourceSaveNeedsReview = true
            document.store.status = "Recovered copy: the original is already open. Use Save As."
          }
          if display { document.makeWindowControllers(); document.showWindows() }
          groups.insert(entry.recoveryID); index.lastDiscovered += 1
        } catch {
          cancelWorker = nil
          try check()
          if error is CancellationError { throw error }
          if error is RecoveryMemoryFailure { throw error }
          if let limit = error as? NativeArchiveMemoryLimit {
            switch limit {
            case .metadata: deferEntry(entry, reason: "metadata")
            case .raster: deferEntry(entry, reason: "raster")
            }
            continue
          }
          if let failure = error as? RecoveryIndexFailure {
            if failure == .changed || failure == .busy { throw failure }
            if failure == .invalid { index.lastInvalid += 1; continue }
          }
          index.lastUnavailable += 1
        }
      }
      try check()
      state?.phase = "accounting"
      let finalUsage = try await memoryUsage(limit: memoryLimit)
      try check()
      state?.memory = finalUsage
      let stillMissing = try missing.filter { try RecoveryFileStamp.read($0.backupURL) == nil }
      try index.remove(Set(stillMissing.map(\.snapshotID)))
      state?.phase = "completed"
    } catch {
      var failure = error
      // Revoked API permission takes precedence even when the accounting worker
      // acknowledges cancellation before the next normal validation checkpoint.
      do { try validate() } catch { failure = error }
      let cancelled = failure is CancellationError || state?.cancellationRequested == true
      state?.phase = cancelled ? "cancelled" : "failed"
      throw failure
    }
  }
}
