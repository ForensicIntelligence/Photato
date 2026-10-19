import Foundation
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class GradientLibrary {
  static let shared = GradientLibrary(
    persistenceURL: FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first?
    .appendingPathComponent("Photato/Gradients.pclibrary"))
  private(set) var state = GradientPresetState.builtins()
  private(set) var busy = false
  var error: String?
  @ObservationIgnored var loadTask: Task<Void, Never>?
  @ObservationIgnored let persistenceURL: URL?
  @ObservationIgnored private var loadFailed = false
  var selectedPreset: GRDPreset? { state.activePreset.flatMap { state.presets[$0] } }
  init(persistenceURL: URL? = nil, initialState: GradientPresetState? = nil) {
    self.persistenceURL = persistenceURL
    if let initialState { state = initialState }
    if let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) {
      busy = true
      loadTask = Task { [weak self] in
        do {
          let next = try await Task.detached(priority: .userInitiated) {
            try GradientPresetState.decode(Self.readFile(url, limit: GradientPresetState.maxBytes))
          }.value
          self?.state = next
        } catch {
          self?.loadFailed = true
          self?.error = "Could not load saved gradients: \(error.localizedDescription)"
        }
        self?.busy = false
      }
    }
  }
  nonisolated static func readFile(_ url: URL, limit: Int) throws -> Data {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= limit else { throw CraftError.invalid("Gradient file is too large.") }
    return try Data(contentsOf: url, options: .mappedIfSafe)
  }
  func edit(_ operation: @escaping @Sendable (inout GradientPresetState) throws -> Void)
    async throws
  {
    guard !loadFailed else {
      throw CraftError.invalid(
        "The saved gradient library could not be read. Its file has been preserved; repair it before saving presets."
      )
    }
    guard !busy else {
      throw CraftError.invalid("Wait for the current gradient library operation to finish.")
    }
    try Task.checkCancellation()
    busy = true
    defer { busy = false }
    let original = state
    let url = persistenceURL
    let worker = Task.detached(priority: .userInitiated) {
      var next = original
      try operation(&next)
      try next.rebuild()
      let data = try next.encoded()
      try Task.checkCancellation()
      if let url {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      }
      return next
    }
    let next = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    // The file replacement is the commit point; publish even if cancellation arrives afterward.
    state = next
    error = nil
  }
  func select(_ ids: Set<UUID>, active: UUID?) async throws {
    try await edit { state in
      guard ids.allSatisfy({ state.node($0) != nil }),
        active == nil || state.presets[active!] != nil
      else {
        throw CraftError.invalid("Gradient selection is no longer available.")
      }
      state.selected = ids
      if let active { state.activePreset = active }
    }
  }
  func importFile(_ url: URL, into parent: UUID?) async throws {
    try await edit { state in
      let data = try Self.readFile(url, limit: GRDCodec.maxBytes)
      try state.install(data, name: url.deletingPathExtension().lastPathComponent, into: parent)
    }
  }
  func exportFile(_ url: URL, selected: Bool) async throws {
    let captured = state
    let worker = Task.detached(priority: .userInitiated) {
      let data = try captured.exported(selected ? captured.selected : nil)
      try Task.checkCancellation()
      try data.write(to: url, options: .atomic)
    }
    try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
  }
}
