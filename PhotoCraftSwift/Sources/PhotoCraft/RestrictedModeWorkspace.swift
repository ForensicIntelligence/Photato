import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class RestrictedModeWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  var request: RestrictedModeRequest
  var image: CGImage?
  var originalImage: CGImage?
  var preview = true
  var rendering = false
  var committing = false
  var error: String?
  var undoStates: [RestrictedModeRequest] = []
  var redoStates: [RestrictedModeRequest] = []
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var commitTask: Task<Void, Never>?
  private var generation = 0
  private var closed = false
  let masters: [CraftDocument]
  init(document: CraftDocument, kind: RestrictedModeRequest.Kind, masters: [CraftDocument] = [], previous: [PaletteColor]? = nil) {
    source = document; self.masters = masters; request = .init(kind)
    request.bitmap.outputResolution = document.pixelsPerInch; request.previousPalette = previous
    if case .indexed(let raster) = document.restrictedMode { request.colors = raster.palette; request.transparentIndex = raster.transparentIndex }
  }
  var ready: Bool { image != nil && !rendering && !committing && !closed && error == nil }
  func change(_ next: RestrictedModeRequest, remember: Bool = true) {
    guard !closed, !committing, next != request else { return }
    if remember { undoStates.append(request); if undoStates.count > 100 { undoStates.removeFirst() }; redoStates = [] }
    request = next; refresh()
  }
  func update(_ edit: (inout RestrictedModeRequest) -> Void) { var next = request; edit(&next); change(next) }
  func undo() { guard !committing, let previous = undoStates.popLast() else { return }; redoStates.append(request); change(previous, remember: false) }
  func redo() { guard !committing, let next = redoStates.popLast() else { return }; undoStates.append(request); change(next, remember: false) }
  func refresh() {
    guard !closed, !committing else { return }
    task?.cancel(); generation += 1
    let token = generation, source = source, request = request, masters = masters, needOriginal = originalImage == nil
    rendering = true; error = nil
    task = Task { [weak self] in
      do {
        let worker = Task.detached(priority: .userInitiated) { () throws -> (CGImage, CGImage?) in
          var result = source
          try request.command(in: source, masters: masters).apply(to: &result)
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
  func close() { closed = true; generation += 1; task?.cancel(); commitTask?.cancel(); task = nil; commitTask = nil; rendering = false }
}

extension EditorStore {
  func canBeginRestrictedMode(_ kind: RestrictedModeRequest.Kind) -> Bool {
    guard canBeginDocumentMode, !document.hasArtboards, !document.hasFrames else { return false }
    switch kind {
    case .indexed: return document.depth == .u8 && [.rgb, .grayscale].contains(document.colorMode)
    case .bitmap: return document.depth == .u8 && document.colorMode == .grayscale
    case .colorTable: return document.colorMode == .indexed
    }
  }
  func beginRestrictedMode(_ kind: RestrictedModeRequest.Kind, masters: [CraftDocument] = []) {
    guard canBeginRestrictedMode(kind) else { return }
    let draft = RestrictedModeWorkspace(document: document, kind: kind, masters: masters, previous: previousIndexedPalette)
    restrictedModeWorkspace = draft; draft.refresh()
  }
  func cancelRestrictedMode() { restrictedModeWorkspace?.close(); restrictedModeWorkspace = nil; render() }
  func commitRestrictedMode() {
    guard let draft = restrictedModeWorkspace, draft.ready else { return }
    let source = draft.source, request = draft.request, masters = draft.masters
    draft.committing = true
    draft.commitTask = Task { [weak self, weak draft] in
      do {
        let worker = Task.detached(priority: .userInitiated) { try PreparedEdit(command: request.command(in: source, masters: masters), document: source) }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let draft, self.restrictedModeWorkspace === draft, self.document == source else { throw CraftError.invalid("The source changed during conversion. Cancel and reopen the dialog.") }
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        if case .indexed(let raster) = self.document.restrictedMode { self.previousIndexedPalette = raster.palette }
        if self.document != source { self.onChange?(.changeDone) }
        self.restrictedModeWorkspace = nil; self.status = request.title; draft.close(); self.render()
      } catch { if !Task.isCancelled { draft?.error = error.localizedDescription } }
      draft?.committing = false
    }
  }
}

extension AppDelegate {
  static let restrictedModeMenus: [String: RestrictedModeRequest.Kind] = [
    "Image > Mode > Indexed Color…": .indexed, "Image > Mode > Bitmap": .bitmap, "Image > Mode > Color Table…": .colorTable]
  @objc func restrictedModeDialog(_ item: NSMenuItem) {
    guard let store, let kind = Self.restrictedModeMenus[item.identifier?.rawValue ?? ""] else { return }
    let masters = NSDocumentController.shared.documents.compactMap { $0 as? CraftNSDocument }
      .map { $0.store.document }.filter { $0.id != store.document.id && $0.depth == .u8 && [.rgb, .grayscale].contains($0.colorMode) }
    store.beginRestrictedMode(kind, masters: masters)
  }
  func validateRestrictedModeMenu(_ item: NSMenuItem) -> Bool {
    guard let store, let kind = Self.restrictedModeMenus[item.identifier?.rawValue ?? ""] else { return false }
    item.state = (kind == .indexed && store.document.colorMode == .indexed) || (kind == .bitmap && store.document.colorMode == .bitmap) ? .on : .off
    return store.canBeginRestrictedMode(kind)
  }
}
