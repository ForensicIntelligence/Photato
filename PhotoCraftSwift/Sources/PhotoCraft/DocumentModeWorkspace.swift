import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class DocumentModeWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  let workingSettings: ColorSettings
  var request: DocumentModeRequest
  var image: CGImage?
  var originalImage: CGImage?
  var preview = true
  var rendering = false
  var committing = false
  var error: String?
  var undoStates: [DocumentModeRequest] = []
  var redoStates: [DocumentModeRequest] = []
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var commitTask: Task<Void, Never>?
  private var generation = 0
  private var closed = false
  init(document: CraftDocument, mode: DocumentColorMode, depth: PixelDepth, settings: ColorSettings = .init()) throws {
    source = document; workingSettings = settings
    request = .init(.init(mode: mode, depth: depth,
      profile: try settings.conversionProfile(from: document, to: mode, depth: depth), intent: settings.intent))
  }
  var ready: Bool { image != nil && !rendering && !committing && !closed && error == nil }
  func change(_ next: DocumentModeRequest, remember: Bool = true) {
    guard !closed, !committing, next != request else { return }
    if remember { undoStates.append(request); if undoStates.count > 100 { undoStates.removeFirst() }; redoStates = [] }
    request = next; refresh()
  }
  func update(_ edit: (inout DocumentModeRequest) -> Void) { var next = request; edit(&next); change(next) }
  func chooseMode(_ mode: DocumentColorMode) {
    do {
      var next = request
      next.conversion.mode = mode
      if !mode.depths.contains(next.conversion.depth) { next.conversion.depth = .u16 }
      next.conversion.profile = try workingSettings.conversionProfile(from: source, to: mode, depth: next.conversion.depth)
      change(next)
    } catch { self.error = error.localizedDescription }
  }
  func chooseDepth(_ depth: PixelDepth) {
    do {
      var next = request
      next.conversion.profile = try next.conversion.profile.map {
        try NativeModeProfile.atDepth($0, mode: next.conversion.mode, depth: depth)
      } ?? workingSettings.profile(next.conversion.mode, depth: depth)
      next.conversion.depth = depth; change(next)
    } catch { self.error = error.localizedDescription }
  }
  func useWorkingProfile() {
    do {
      let profile = try workingSettings.profile(request.conversion.mode, depth: request.conversion.depth)
      update { $0.conversion.profile = profile }
    } catch { self.error = error.localizedDescription }
  }
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
          try DocumentModeInput.command(request, in: source).apply(to: &result)
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
  func loadProfile(_ data: Data) throws {
    try NativeModeProfile.validate(data, mode: request.conversion.mode, depth: request.conversion.depth)
    update { $0.conversion.profile = data }
  }
  func close() { closed = true; generation += 1; task?.cancel(); commitTask?.cancel(); task = nil; commitTask = nil; rendering = false }
}

extension EditorStore {
  var canBeginDocumentMode: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && historyOperation == nil
      && transformDraft == nil && !editingComponent && !editingMask && !smartFilterMaskEditing
      && (!document.layers.isEmpty || document.inkMode != nil) && document.width <= NativeModeRaster.maximumPixels / document.height
  }
  func beginDocumentMode(_ mode: DocumentColorMode, depth: PixelDepth? = nil) {
    guard canBeginDocumentMode, DocumentColorMode.componentModes.contains(mode) else { return }
    let precision = depth ?? (mode.depths.contains(document.depth) ? document.depth : .u16)
    guard mode.depths.contains(precision) else { return }
    do {
      let draft = try DocumentModeWorkspace(document: document, mode: mode, depth: precision, settings: workingColorSettings)
      documentModeWorkspace = draft; draft.refresh()
    } catch { status = error.localizedDescription }
  }
  func cancelDocumentMode() { documentModeWorkspace?.close(); documentModeWorkspace = nil; render() }
  func commitDocumentMode() {
    guard let draft = documentModeWorkspace, draft.ready else { return }
    let original = draft.source, request = draft.request; draft.committing = true
    draft.commitTask = Task { [weak self, weak draft] in
      do {
        let worker = Task.detached(priority: .userInitiated) {
          try PreparedEdit(command: DocumentModeInput.command(request, in: original), document: original)
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let draft, self.documentModeWorkspace === draft, self.document == original else {
          throw CraftError.invalid("The source changed during color conversion.")
        }
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        if self.document != original { self.onChange?(.changeDone) }
        self.documentModeWorkspace = nil; self.status = "Convert Color Mode"; draft.close(); self.render()
      } catch { if !Task.isCancelled { draft?.error = error.localizedDescription } }
      draft?.committing = false
    }
  }
}

extension AppDelegate {
  static let documentModeMenus = Dictionary(uniqueKeysWithValues: DocumentColorMode.componentModes.map { ("Image > Mode > " + $0.title, $0) })
  static let documentDepthMenus: [String: PixelDepth] = ["Image > Mode > 8 Bits/Channel": .u8, "Image > Mode > 16 Bits/Channel": .u16, "Image > Mode > 32 Bits/Channel": .f32]
  @objc func documentModeDialog(_ item: NSMenuItem) {
    guard let store else { return }
    let path = item.identifier?.rawValue ?? ""
    if let mode = Self.documentModeMenus[path] { store.beginDocumentMode(mode) }
    else if let depth = Self.documentDepthMenus[path] { store.beginDocumentMode(store.document.colorMode, depth: depth) }
  }
  func validateDocumentModeMenu(_ item: NSMenuItem) -> Bool {
    guard let store else { item.state = .off; return false }
    let path = item.identifier?.rawValue ?? ""
    if let mode = Self.documentModeMenus[path] {
      item.state = store.document.colorMode == mode ? .on : .off; return store.canBeginDocumentMode
    }
    if let depth = Self.documentDepthMenus[path] {
      item.state = store.document.bitsPerChannel == DocumentModeAPI.bits(depth) ? .on : .off
      return store.canBeginDocumentMode && DocumentColorMode.componentModes.contains(store.document.colorMode) && store.document.colorMode.depths.contains(depth)
    }
    return false
  }
}
