import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ColorProfileWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  let workingSettings: ColorSettings
  let sourceSession: UUID?
  let sourceLifecycle: UUID?
  var request: ColorProfileRequest
  var image: CGImage?
  var originalImage: CGImage?
  var preview = true
  var rendering = false
  var committing = false
  var error: String?
  var undoStates: [ColorProfileRequest] = []
  var redoStates: [ColorProfileRequest] = []
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var commitTask: Task<Void, Never>?
  private var generation = 0
  private var closed = false
  init(document: CraftDocument, operation: ColorProfileRequest.Operation, settings: ColorSettings = .init(),
    session: UUID? = nil, lifecycle: UUID? = nil) throws {
    source = document; workingSettings = settings
    sourceSession = session; sourceLifecycle = lifecycle
    let profile = try operation == .convert ? settings.profile(document.colorMode, depth: document.depth)
      : ColorProfileInput.effectiveProfile(document)
    request = .init(operation, profile: profile)
    request.intent = settings.intent; request.blackPointCompensation = settings.blackPointCompensation
  }
  var title: String { request.operation == .assign ? "Assign Profile" : "Convert to Profile" }
  var ready: Bool { image != nil && !rendering && !committing && !closed && error == nil }
  func change(_ next: ColorProfileRequest, remember: Bool = true) {
    guard !closed, !committing, next != request else { return }
    if remember { undoStates.append(request); if undoStates.count > 100 { undoStates.removeFirst() }; redoStates = [] }
    request = next; refresh()
  }
  func update(_ edit: (inout ColorProfileRequest) -> Void) { var next = request; edit(&next); change(next) }
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
          try ColorProfileInput.command(request, in: source).apply(to: &result)
          let bounds = try RasterPreviewRequest.overview(width: source.width, height: source.height)
          return (try ColorManagement.displayImage(bounds.reducing(Renderer.composite(result)), in: result),
            needOriginal ? try ColorManagement.displayImage(bounds.reducing(Renderer.composite(source)), in: source) : nil)
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
  func loadProfile(_ data: Data) throws {
    let mode = try ProofSettings.mode(of: data)
    guard request.operation == .convert || mode == source.colorMode else { throw CraftError.invalid("Choose a profile for the current color mode.") }
    let profile = try NativeModeProfile.atDepth(data, mode: mode, depth: source.depth)
    update { $0.profile = profile; $0.removeProfile = false }
  }
  func close() { closed = true; generation += 1; task?.cancel(); commitTask?.cancel(); task = nil; commitTask = nil; rendering = false }
}

extension EditorStore {
  var canBeginColorProfile: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && historyOperation == nil
      && transformDraft == nil && !editingComponent && !editingMask && !smartFilterMaskEditing
      && DocumentColorMode.componentModes.contains(document.colorMode) && !document.layers.isEmpty
  }
  func beginColorProfile(_ operation: ColorProfileRequest.Operation) {
    guard canBeginColorProfile else { return }
    do {
      let draft = try ColorProfileWorkspace(document: document, operation: operation, settings: workingColorSettings,
        session: sessionGeneration, lifecycle: layerPanelGeneration)
      colorProfileWorkspace = draft; draft.refresh()
    } catch { status = error.localizedDescription }
  }
  func cancelColorProfile() { colorProfileWorkspace?.close(); colorProfileWorkspace = nil; render() }
  func commitColorProfile() {
    guard let draft = colorProfileWorkspace, draft.ready else { return }
    guard draft.sourceSession == sessionGeneration, draft.sourceLifecycle == layerPanelGeneration,
      draft.source == document else { draft.error = "The source changed during color conversion."; return }
    let original = draft.source, request = draft.request; draft.committing = true
    draft.commitTask = Task { [weak self, weak draft] in
      do {
        let worker = Task.detached(priority: .userInitiated) {
          try PreparedEdit(command: ColorProfileInput.command(request, in: original), document: original)
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let draft, self.colorProfileWorkspace === draft, self.document == original,
          self.sessionGeneration == draft.sourceSession, self.layerPanelGeneration == draft.sourceLifecycle else {
          throw CraftError.invalid("The source changed during color conversion.")
        }
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        if self.document != original { self.onChange?(.changeDone) }
        self.colorProfileWorkspace = nil; self.status = "Color Profile"; draft.close(); self.render()
      } catch { if !Task.isCancelled { draft?.error = error.localizedDescription } }
      draft?.committing = false
    }
  }
}

extension AppDelegate {
  @objc func colorProfileDialog(_ item: NSMenuItem) {
    store?.beginColorProfile(item.identifier?.rawValue == "Edit > Assign Profile…" ? .assign : .convert)
  }
}
