import AppKit
import Foundation
import Observation
import PhotoCraftCore

enum ScriptEventKind: String, Codable, CaseIterable, Sendable {
  case newDocument, openDocument
  var title: String { self == .newDocument ? "New Document" : "Open Document" }
}

struct ScriptEventBinding: Codable, Equatable, Identifiable, Sendable {
  var id = UUID()
  var event: ScriptEventKind
  var actionID: UUID
}

struct ScriptEventsConfiguration: Codable, Equatable, Sendable {
  var version = 1
  var enabled = false
  var bindings: [ScriptEventBinding] = []
  static let maximumBindings = 128
  static let maximumBytes = 128 * 1024
  func validate() throws {
    guard version == 1, bindings.count <= Self.maximumBindings,
      Set(bindings.map(\.id)).count == bindings.count else {
      throw CraftError.invalid("Invalid event configuration (version 1, at most 128 unique registrations).")
    }
  }
  func encoded() throws -> Data {
    try validate()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw CraftError.invalid("Event configuration exceeds 128 KiB.") }
    return data
  }
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumBytes else { throw CraftError.invalid("Event configuration exceeds 128 KiB.") }
    let value = try JSONDecoder().decode(Self.self, from: data)
    try value.validate(); return value
  }
}

@MainActor @Observable final class ScriptEventsStore {
  static let shared: ScriptEventsStore = {
    let isolated = ProcessInfo.processInfo.environment["PHOTATO_ISOLATED_UI_SESSION"] == "1"
      || CommandLine.arguments.contains { $0.hasPrefix("--snapshot") }
    return ScriptEventsStore(persistenceURL: isolated ? nil : FileManager.default.urls(for: .applicationSupportDirectory,
      in: .userDomainMask).first?.appendingPathComponent("Photato/ScriptEvents.json"))
  }()
  private(set) var configuration = ScriptEventsConfiguration()
  private(set) var revision = UUID()
  private(set) var loadError: String?
  let actions: ActionLibrary
  @ObservationIgnored let persistenceURL: URL?
  @ObservationIgnored private let writer: (Data, URL) throws -> Void
  init(persistenceURL: URL? = nil, actions: ActionLibrary = .shared,
    writer: @escaping (Data, URL) throws -> Void = { data, url in
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    }) {
    self.persistenceURL = persistenceURL; self.actions = actions; self.writer = writer
    if let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) {
      do {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= ScriptEventsConfiguration.maximumBytes else {
          throw CraftError.invalid("Saved event configuration is too large.")
        }
        configuration = try .decode(Data(contentsOf: url))
      } catch { loadError = "Saved events could not be read. The original file is preserved. \(error.localizedDescription)" }
    }
  }
  func replace(_ value: ScriptEventsConfiguration, expectedRevision: UUID) throws {
    guard loadError == nil, actions.loadError == nil else { throw CraftError.invalid(loadError ?? actions.loadError!) }
    guard revision == expectedRevision else { throw CraftError.invalid("Event configuration changed. Refresh and try again.") }
    try value.validate()
    // Retain orphaned registrations from a saved file, but never introduce one.
    for binding in value.bindings where !configuration.bindings.contains(binding) {
      _ = try actions.action(binding.actionID)
    }
    guard value != configuration else { return }
    let data = try value.encoded()
    if let url = persistenceURL { try writer(data, url) }
    configuration = value; revision = UUID()
  }
  func setEnabled(_ enabled: Bool) throws {
    var next = configuration; next.enabled = enabled
    try replace(next, expectedRevision: revision)
  }
  func add(event: ScriptEventKind, actionID: UUID) throws {
    var next = configuration; next.bindings.append(.init(event: event, actionID: actionID))
    try replace(next, expectedRevision: revision)
  }
  func remove(_ id: UUID?) throws {
    var next = configuration
    if let id {
      guard next.bindings.contains(where: { $0.id == id }) else { throw CraftError.invalid("Event registration no longer exists.") }
      next.bindings.removeAll { $0.id == id }
    } else { next.bindings = [] }
    try replace(next, expectedRevision: revision)
  }
}

@MainActor @Observable final class ScriptEventDispatcher {
  struct ResultInfo {
    let event: ScriptEventKind
    let documentID: UUID
    let completedActions: Int
    let error: String?
  }
  @MainActor private final class Request {
    weak var document: CraftNSDocument?
    let event: ScriptEventKind
    let original: CraftDocument
    let generation: UUID
    let revision: UUID
    let libraryRevision: Int
    let actions: [RecordedAction]
    init(document: CraftNSDocument, event: ScriptEventKind, store: ScriptEventsStore) throws {
      self.document = document; self.event = event; original = document.store.document
      generation = document.store.layerPanelGeneration; revision = store.revision
      libraryRevision = store.actions.revision
      guard document.store.actions === store.actions else { throw CraftError.invalid("The document uses a different Actions library.") }
      actions = try store.configuration.bindings.filter { $0.event == event }.map { try store.actions.action($0.actionID) }
    }
  }
  let store: ScriptEventsStore
  @ObservationIgnored weak var controller: CraftDocumentController?
  @ObservationIgnored private var pending: [Request] = []
  @ObservationIgnored private(set) var task: Task<Void, Never>?
  private(set) var pendingCount = 0
  private(set) var isRunning = false
  private(set) var lastResult: ResultInfo?
  init(store: ScriptEventsStore, controller: CraftDocumentController) { self.store = store; self.controller = controller }
  func cancel() { task?.cancel(); pending = []; pendingCount = 0 }
  func enqueue(_ event: ScriptEventKind, document: CraftNSDocument) {
    guard store.configuration.enabled, store.loadError == nil,
      store.configuration.bindings.contains(where: { $0.event == event }), !document.isRecoveredSource else { return }
    do {
      guard pending.count < 64 else { throw CraftError.invalid("The event queue is full. The document was not changed.") }
      pending.append(try Request(document: document, event: event, store: store)); pendingCount = pending.count
    } catch { lastResult = .init(event: event, documentID: document.store.document.id, completedActions: 0, error: error.localizedDescription) }
    schedule()
  }
  private func schedule() {
    guard task == nil, !pending.isEmpty else { return }
    task = Task { [weak self] in
      guard let self else { return }
      isRunning = true
      defer { isRunning = false; task = nil; schedule() }
      while !pending.isEmpty, !Task.isCancelled {
        let request = pending.removeFirst(); pendingCount = pending.count
        await run(request)
      }
    }
  }
  private func validate(_ request: Request) throws -> CraftNSDocument {
    try Task.checkCancellation()
    guard let controller, let document = request.document,
      store.configuration.enabled, store.loadError == nil, store.revision == request.revision,
      store.actions.revision == request.libraryRevision, document.store.actions === store.actions,
      document.ownerController === controller, controller.documents.contains(where: { $0 === document }),
      document.store.layerPanelGeneration == request.generation, !document.isRecoveredSource,
      !document.fileOperationBusy, document.closeWorkflowID == nil,
      !controller.documentClosing.isActive, !controller.recoveryIndex.isBusy else {
      throw CraftError.invalid("Event action cancelled: document, configuration, Actions library or lifecycle changed.")
    }
    return document
  }
  private func run(_ request: Request) async {
    var completed = 0
    do {
      // Publication occurs inside the native opening task. Let it finish first;
      // never block that task waiting for its own event callback.
      if let opening = controller?.documentOpening.task { await opening.value }
      let document = try validate(request)
      guard document.store.document == request.original else { throw CraftError.invalid("The document changed before its event action started.") }
      for action in request.actions {
        _ = try validate(request)
        guard document.store.canPlayAction(action) else { throw CraftError.invalid("Finish the current document interaction before event playback.") }
        try await document.store.playEventAction(action) { [weak self] in
          guard let self else { throw CancellationError() }
          _ = try self.validate(request)
        }
        completed += 1
      }
      lastResult = .init(event: request.event, documentID: request.original.id, completedActions: completed, error: nil)
    } catch {
      lastResult = .init(event: request.event, documentID: request.original.id, completedActions: completed, error: error.localizedDescription)
    }
  }
}

@MainActor private final class EventPlaybackLifetime {
  var active = true
  var task: Task<Void, Never>?
}

extension EditorStore {
  func playEventAction(_ action: RecordedAction, validate: @escaping @MainActor () throws -> Void) async throws {
    try Task.checkCancellation()
    guard canPlayAction(action) else { throw CraftError.invalid("Finish the current interaction before event playback.") }
    let lifetime = EventPlaybackLifetime()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        playPreparedAction(action, validate: validate) {
          lifetime.active = false; lifetime.task = nil; continuation.resume(with: $0)
        }
        if lifetime.active { lifetime.task = geometryTask }
      }
    } onCancel: {
      Task { @MainActor in if lifetime.active { lifetime.task?.cancel() } }
    }
  }
}
