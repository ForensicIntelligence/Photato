import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class InkModeWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  var request: InkModeRequest
  var image: CGImage?
  var originalImage: CGImage?
  var preview = true
  var rendering = false
  var committing = false
  var error: String?
  var undoStates: [InkModeRequest] = []
  var redoStates: [InkModeRequest] = []
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var commitTask: Task<Void, Never>?
  private var generation = 0
  private var closed = false
  init(document: CraftDocument, kind: InkModeRequest.Kind) {
    source = document; request = .init(kind, document: document)
  }
  var ready: Bool { image != nil && !rendering && !committing && !closed && error == nil }
  func change(_ next: InkModeRequest, remember: Bool = true) {
    guard !closed, !committing, next != request else { return }
    if remember { undoStates.append(request); if undoStates.count > 100 { undoStates.removeFirst() }; redoStates = [] }
    request = next; refresh()
  }
  func update(_ edit: (inout InkModeRequest) -> Void) { var next = request; edit(&next); change(next) }
  func undo() { guard !committing, let previous = undoStates.popLast() else { return }; redoStates.append(request); change(previous, remember: false) }
  func redo() { guard !committing, let next = redoStates.popLast() else { return }; undoStates.append(request); change(next, remember: false) }
  func refresh() {
    guard !closed, !committing else { return }
    task?.cancel(); generation += 1
    let token = generation, source = source, request = request, needOriginal = originalImage == nil
    rendering = true; error = nil
    task = Task { [weak self] in
      do {
        let worker = Task.detached(priority: .userInitiated) { () throws -> (CGImage, CGImage?) in
          var result = source
          try request.command(in: source).apply(to: &result)
          return (try ColorManagement.displayImage(Renderer.composite(result), in: result),
            needOriginal ? try ColorManagement.displayImage(Renderer.composite(source), in: source) : nil)
        }
        let images = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, !self.closed, self.generation == token else { return }
        self.image = images.0; if let original = images.1 { self.originalImage = original }; self.rendering = false
      } catch {
        guard let self, !self.closed, self.generation == token else { return }
        self.rendering = false; if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  func setInkCount(_ count: Int) {
    guard (1...4).contains(count) else { return }
    update { request in
      while request.settings.inks.count < count {
        request.settings.inks.append(.init(name: "Ink \(request.settings.inks.count + 1)", color: .black))
      }
      request.settings.inks = Array(request.settings.inks.prefix(count))
      request.settings.overprints.removeAll { $0.mask >= 1 << count }
    }
  }
  func settingsData() throws -> Data {
    try request.settings.validate()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(request.settings)
  }
  func loadSettings(_ data: Data) throws {
    guard data.count <= 262_144 else { throw CraftError.invalid("Ink settings exceed 256 KiB.") }
    let settings = try JSONDecoder().decode(DuotoneSettings.self, from: data); try settings.validate()
    update { $0.settings = settings }
  }
  func close() { closed = true; generation += 1; task?.cancel(); commitTask?.cancel(); task = nil; commitTask = nil; rendering = false }
}

extension EditorStore {
  func canBeginInkMode(_ kind: InkModeRequest.Kind) -> Bool {
    guard canBeginDocumentMode, !document.hasArtboards, !document.hasFrames,
      document.width <= InkPlane.maximumPixels / document.height else { return false }
    switch kind {
    case .duotone: return document.depth == .u8 && [.grayscale, .duotone].contains(document.colorMode)
    case .multichannel: return document.depth != .f32 && !document.colorMode.isRestricted && document.colorMode != .multichannel
    }
  }
  func beginInkMode(_ kind: InkModeRequest.Kind) {
    guard canBeginInkMode(kind) else { return }
    let draft = InkModeWorkspace(document: document, kind: kind)
    inkModeWorkspace = draft; draft.refresh()
  }
  func cancelInkMode() { inkModeWorkspace?.close(); inkModeWorkspace = nil; render() }
  func commitInkMode() {
    guard let draft = inkModeWorkspace, draft.ready else { return }
    let original = draft.source, request = draft.request; draft.committing = true
    draft.commitTask = Task { [weak self, weak draft] in
      do {
        let worker = Task.detached(priority: .userInitiated) {
          try PreparedEdit(command: request.command(in: original), document: original)
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let draft, self.inkModeWorkspace === draft, self.document == original else {
          throw CraftError.invalid("The source changed during color conversion.")
        }
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        if self.document != original { self.onChange?(.changeDone) }
        self.inkModeWorkspace = nil; self.status = request.title; draft.close(); self.render()
      } catch { if !Task.isCancelled { draft?.error = error.localizedDescription } }
      draft?.committing = false
    }
  }
}

extension AppDelegate {
  static let inkModeMenus: [String: InkModeRequest.Kind] = ["Image > Mode > Duotone": .duotone, "Image > Mode > Multichannel": .multichannel]
  @objc func inkModeDialog(_ item: NSMenuItem) {
    guard let kind = Self.inkModeMenus[item.identifier?.rawValue ?? ""] else { return }
    store?.beginInkMode(kind)
  }
  func validateInkModeMenu(_ item: NSMenuItem) -> Bool {
    guard let store, let kind = Self.inkModeMenus[item.identifier?.rawValue ?? ""] else { return false }
    item.state = store.document.colorMode.rawValue == kind.rawValue ? .on : .off
    return store.canBeginInkMode(kind)
  }
}
