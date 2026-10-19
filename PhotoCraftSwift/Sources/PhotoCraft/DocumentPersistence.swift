import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum DocumentPersistenceConflict: LocalizedError {
  case changed
  var errorDescription: String? { "The document changed while reading its saved version." }
}

@MainActor final class DocumentCopyAccessory: NSObject {
  let view = NSStackView()
  let formats = NSPopUpButton(frame: .zero, pullsDown: false)
  let explanation = NSTextField(wrappingLabelWithString: "")
  weak var panel: NSSavePanel?
  let availableFormats: [DocumentIO.Format]
  let saving: Bool
  var format: DocumentIO.Format { availableFormats[formats.indexOfSelectedItem] }

  init(
    panel: NSSavePanel, initial: DocumentIO.Format,
    availableFormats: [DocumentIO.Format] = DocumentIO.Format.allCases, saving: Bool = false
  ) {
    self.panel = panel
    self.availableFormats = availableFormats.isEmpty ? [.native] : availableFormats
    self.saving = saving
    super.init()
    formats.addItems(withTitles: self.availableFormats.map(\.title))
    formats.selectItem(at: self.availableFormats.firstIndex(of: initial) ?? 0)
    formats.target = self
    formats.action = #selector(updateFormat)
    formats.setAccessibilityLabel("File format")
    explanation.textColor = .secondaryLabelColor
    explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    view.orientation = .vertical
    view.alignment = .leading
    view.spacing = 8
    view.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "Format:"), formats]))
    view.addArrangedSubview(explanation)
    view.widthAnchor.constraint(equalToConstant: 420).isActive = true
    updateFormat()
  }
  @objc func updateFormat() {
    panel?.allowedContentTypes = [format.contentType]
    explanation.stringValue = saving ? format.saveNotice : format.copyDescription
    if let panel {
      let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
      panel.nameFieldStringValue = base + "." + format.rawValue
    }
  }
}

@MainActor extension CraftNSDocument {
  var revertSourceURL: URL? { fileURL ?? importedSourceURL }
  var canRunFileCommand: Bool {
    !fileOperationBusy && copyPanel == nil && !store.geometryBusy && !store.aiBusy
      && !store.hasToneDraft && store.transformDraft == nil && !store.coalescingChanges
      && store.pathGesture == nil && store.geometrySheet == nil && !store.showFeatherSelection
      && store.patternNameDraft == nil && store.gradientNameDraft == nil && !store.showAI
      && !store.showImagePlayground && store.error == nil
      && windowForSheet?.attachedSheet == nil && NSApp?.modalWindow == nil
  }
  var canRevertDocument: Bool { revertSourceURL != nil && canRunFileCommand }

  /// Encodes the same snapshot as API file downloads; the copy never takes ownership
  /// of the document, clears its dirty state, or alters its history.
  func copyDocument(
    to url: URL, format: DocumentIO.Format, allowReplacingSource: Bool = false,
    encoder: @escaping @Sendable (CraftDocument, DocumentIO.Format) throws -> Data = DocumentIO
      .encode
  ) async throws {
    guard canRunFileCommand else {
      throw CraftError.invalid("Finish the current document operation.")
    }
    guard url.isFileURL else { throw CraftError.invalid("Choose a local file for the copy.") }
    if !allowReplacingSource, let source = revertSourceURL {
      let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath()
      let targetPath = url.standardizedFileURL.resolvingSymlinksInPath()
      let a = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey])
        .fileResourceIdentifier
      let b = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
      let sameResource =
        (a as? NSObject).flatMap { first in
          (b as? NSObject).map { first.isEqual($0) }
        } ?? false
      guard sourcePath != targetPath, !sameResource else {
        throw CraftError.invalid("Choose a different file for Save a Copy.")
      }
    }
    store.finishNumericField()
    store.finishLayerName()
    let snapshot = store.document
    let source = revertSourceURL
    let generation = store.layerPanelGeneration
    fileOperationBusy = true
    defer { fileOperationBusy = false }
    let worker = Task.detached(priority: .userInitiated) { try encoder(snapshot, format) }
    let bytes = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard store.layerPanelGeneration == generation, store.document == snapshot,
      revertSourceURL == source
    else {
      throw CraftError.invalid(
        "The document changed while preparing the copy. Save the copy again.")
    }
    let writer = Task.detached(priority: .utility) {
      try Task.checkCancellation()
      try bytes.write(to: url, options: .atomic)
    }
    try await withTaskCancellationHandler(
      operation: { try await writer.value }, onCancel: { writer.cancel() })
  }

  /// Reload only this document's associated file, keeping the previous edit in history.
  /// API callers add session/share checks and tighter decode limits via these closures.
  func revertDocument(
    reader: @escaping @Sendable (URL) throws -> CraftDocument = DocumentIO.read,
    validate: (CraftDocument) throws -> Void = { _ in }
  ) async throws {
    guard canRevertDocument, let source = revertSourceURL else {
      throw CraftError.invalid(
        "Open or save a document and finish the current operation before reverting.")
    }
    store.finishNumericField()
    store.finishLayerName()
    let original = store.document
    let generation = store.layerPanelGeneration
    fileOperationBusy = true
    defer { fileOperationBusy = false }
    let worker = Task.detached(priority: .userInitiated) { try reader(source) }
    let saved = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard generation == store.layerPanelGeneration, source == revertSourceURL,
      original == store.document, !store.geometryBusy, !store.aiBusy,
      store.transformDraft == nil, !store.hasToneDraft, !store.coalescingChanges,
      store.numericEditor == nil, store.layerNameDraft == nil, store.pathGesture == nil,
      windowForSheet?.attachedSheet == nil, NSApp?.modalWindow == nil
    else { throw DocumentPersistenceConflict.changed }
    try validate(saved)
    let prepared = try PreparedEdit(restoring: saved, over: original)
    store.session.endCoalescing()
    try store.session.executePrepared(prepared)
    store.layerVisibilityDraft = nil
    store.layerVisibilityIsolation = nil
    store.componentTarget = .composite
    store.channelView = RGBChannelView()
    store.clearMaskView()
    store.maskEditingLayerID = nil
    store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? [])
    updateChangeCount(.changeCleared)
    store.render()
    store.status = "Revert"
  }

  func showSaveCopy() {
    guard canRunFileCommand else { return }
    store.finishNumericField()
    store.finishLayerName()
    let panel = NSSavePanel()
    panel.title = "Save a Copy"
    panel.nameFieldStringValue =
      (revertSourceURL?.deletingPathExtension().lastPathComponent
        ?? store.document.name) + " copy." + DocumentIO.Format.native.rawValue
    panel.directoryURL = revertSourceURL?.deletingLastPathComponent()
    panel.canCreateDirectories = true
    let initial = persistenceFormat
    let accessory = DocumentCopyAccessory(panel: panel, initial: initial)
    panel.accessoryView = accessory.view
    copyPanel = panel
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self, accessory] response in
      guard let self else { return }
      self.copyPanel = nil
      guard response == .OK, let url = panel.url else { return }
      self.fileOperationTask = Task { [weak self] in
        guard let self else { return }
        defer { self.fileOperationTask = nil }
        do {
          try await self.copyDocument(to: url, format: accessory.format, allowReplacingSource: true)
        } catch is CancellationError {} catch { self.store.error = error.localizedDescription }
      }
    }
    if let window = windowForSheet {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      finish(panel.runModal())
    }
  }

  func showRevert() {
    guard canRevertDocument else { return }
    let alert = NSAlert()
    alert.messageText =
      "Revert to the last saved version of “\(displayName ?? store.document.name)”?"
    alert.informativeText = "Your current changes will be replaced. You can undo Revert."
    alert.addButton(withTitle: "Revert")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    fileOperationTask = Task { [weak self] in
      guard let self else { return }
      defer { self.fileOperationTask = nil }
      do { try await self.revertDocument() } catch is CancellationError {} catch {
        self.store.error = error.localizedDescription
      }
    }
  }
}
