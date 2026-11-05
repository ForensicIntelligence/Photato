import Foundation
import Observation
import PhotoCraftCore

/// Content queries never run in SwiftUI row evaluation or on the main actor.
/// A session-generation cache is deliberately conservative: metadata-only session
/// changes can rescan, but can never publish stale pixel membership.
@MainActor @Observable final class LayerContentFilterWorkspace {
  enum Phase: String { case idle, running, ready, cancelled, failed }
  private(set) var phase = Phase.idle
  private(set) var operationID: UUID?
  private(set) var candidate: LayerPanelFilter?
  private(set) var message: String?
  private(set) var revision = UUID()
  @ObservationIgnored private var task: Task<Bool, Never>?
  @ObservationIgnored private var resolvedGeneration: UUID?
  @ObservationIgnored private var emptyIDs: Set<UUID>?
  @ObservationIgnored private var closed = false
  @ObservationIgnored var publishingSelection = false
  @ObservationIgnored var evaluate: @Sendable (LayerContentSource) async throws -> Set<UUID> = { try $0.emptyLayerIDs() }

  func waitForCurrent() async -> Bool { await task?.value ?? false }
  func isResolved(in store: EditorStore) -> Bool { resolvedGeneration == store.sessionGeneration && emptyIDs != nil }
  func resolvedIDs(in store: EditorStore) -> Set<UUID>? { isResolved(in: store) ? emptyIDs : nil }
  func cancel() {
    task?.cancel(); task = nil; operationID = nil; candidate = nil
    phase = .cancelled; message = "Layer content filtering cancelled."; revision = UUID()
  }
  func reset() {
    cancel(); emptyIDs = nil; resolvedGeneration = nil; phase = .idle; message = nil
  }
  func close() { reset(); closed = true }
  func sourceChanged(in store: EditorStore) {
    if publishingSelection {
      if emptyIDs != nil { resolvedGeneration = store.sessionGeneration }
      return
    }
    reset()
    refreshIfNeeded(in: store)
  }
  func refreshIfNeeded(in store: EditorStore) {
    guard !closed, store.layerPanelFilter.requiresContentEvaluation,
      !isResolved(in: store), phase != .running else { return }
    _ = start(store.layerPanelFilter, in: store, refresh: true)
  }
  @discardableResult func start(_ filter: LayerPanelFilter, in store: EditorStore,
    refresh: Bool = false, admission: @escaping @MainActor () throws -> Void = {}) -> Task<Bool, Never> {
    guard !closed else { return Task { false } }
    task?.cancel()
    let id = UUID(), generation = store.sessionGeneration, lifecycle = store.layerPanelGeneration
    let source = LayerContentSource(store.document), prepare = evaluate
    operationID = id; candidate = filter; phase = .running; message = nil; revision = UUID()
    let request = Task { [weak self, weak store] in
      do {
        try filter.validate()
        if refresh { try await Task.sleep(for: .milliseconds(75)) }
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) { try await prepare(source) }
        let ids = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self, let store, self.operationID == id else { return false }
        guard !self.closed, store.sessionGeneration == generation,
          store.layerPanelGeneration == lifecycle else { throw CancellationError() }
        // A derived refresh may finish while an edit is committing. Wait for that
        // interaction to end; generation changes/cancellation invalidate this task.
        while refresh && !store.canChangeLayerFilter {
          try await Task.sleep(for: .milliseconds(50))
          try Task.checkCancellation()
          guard store.sessionGeneration == generation, self.operationID == id,
            store.layerPanelGeneration == lifecycle else { throw CancellationError() }
        }
        guard store.canChangeLayerFilter else { throw CraftError.invalid("The editing context changed during layer filtering.") }
        try admission()
        self.emptyIDs = ids; self.resolvedGeneration = generation
        try store.setLayerFilter(filter)
        self.candidate = nil; self.phase = .ready; self.message = nil; self.task = nil; self.revision = UUID()
        return true
      } catch {
        guard let self, self.operationID == id else { return false }
        self.candidate = nil; self.task = nil
        self.phase = error is CancellationError ? .cancelled : .failed
        self.message = error.localizedDescription; self.revision = UUID()
        return false
      }
    }
    task = request
    return request
  }
}
