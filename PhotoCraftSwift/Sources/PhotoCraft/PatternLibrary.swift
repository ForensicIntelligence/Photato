import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PatternLibrary {
  static let shared = PatternLibrary(
    persistenceURL: FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first?
    .appendingPathComponent("Photato/Patterns.pclibrary"))
  private(set) var items: [RasterPattern] = []
  var selectedID: String?
  private(set) var busy = false
  var error: String?
  @ObservationIgnored var loadTask: Task<Void, Never>?
  @ObservationIgnored let persistenceURL: URL?
  @ObservationIgnored private var loadFailed = false
  var selected: RasterPattern? { items.first { $0.id == selectedID } ?? items.first }
  init(persistenceURL: URL? = nil) {
    self.persistenceURL = persistenceURL
    do {
      items = try PatternPresets.make()
      selectedID = items.first?.id
    } catch { self.error = error.localizedDescription }
    if let persistenceURL, FileManager.default.fileExists(atPath: persistenceURL.path) {
      busy = true
      loadTask = Task { [weak self] in
        let worker = Task.detached(priority: .userInitiated) {
          let size = try persistenceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          guard size <= PatternArchive.maxBytes else {
            throw CraftError.invalid("Pattern library file is too large.")
          }
          return try PatternArchive.decodeState(
            Data(contentsOf: persistenceURL, options: .mappedIfSafe))
        }
        do {
          let state = try await worker.value
          self?.items = state.patterns
          self?.selectedID = state.selectedID ?? state.patterns.first?.id
        } catch {
          self?.loadFailed = true
          self?.error = "Could not load saved patterns: \(error.localizedDescription)"
        }
        self?.busy = false
      }
    }
  }
  private func commit(_ next: [RasterPattern], selectedID: String?) async throws {
    guard !loadFailed else {
      throw CraftError.invalid(
        "The saved pattern library could not be read. Its file has been preserved; repair it before saving new presets."
      )
    }
    guard !busy else {
      throw CraftError.invalid("Wait for the current pattern operation to finish.")
    }
    try Task.checkCancellation()
    busy = true
    defer { busy = false }
    let url = persistenceURL
    let worker = Task.detached(priority: .userInitiated) {
      try PatternArchive.validate(next)
      if let url {
        let data = try PatternArchive.encode(next, selectedID: selectedID)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      } else {
        try Task.checkCancellation()
      }
    }
    try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    // Once the atomic file replacement succeeds, publish the matching in-memory state.
    items = next
    self.selectedID = selectedID
    error = nil
  }
  func install(_ patterns: [RasterPattern]) async throws {
    var next = items
    for pattern in patterns {
      if let i = next.firstIndex(where: { $0.id == pattern.id }) {
        next[i] = pattern
      } else {
        next.append(pattern)
      }
    }
    try await commit(next, selectedID: patterns.last?.id ?? selectedID)
  }
  func rename(_ id: String, to name: String) async throws {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      throw CraftError.invalid("Pattern no longer exists.")
    }
    var next = items
    next[index].name = name
    try await commit(next, selectedID: id)
  }
  func remove(_ id: String) async throws {
    let next = items.filter { $0.id != id }
    try await commit(next, selectedID: selectedID == id ? next.first?.id : selectedID)
  }
  func resetBuiltins() async throws { try await install(PatternPresets.make()) }
}
