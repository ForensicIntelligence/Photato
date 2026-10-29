import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

@MainActor final class SmartObjectEditLink {
  weak var parent: CraftNSDocument?
  let layerID: UUID
  let sourceID: UUID
  var revision: String
  init(parent: CraftNSDocument, layerID: UUID, source: SmartObject) {
    self.parent = parent; self.layerID = layerID; sourceID = source.sourceID; revision = source.revision
  }
}

extension EditorStore {
  var canEditSmartObject: Bool {
    clipboardTargetAvailable && activeLayer?.smartObject != nil
      && activeLayer.map { !document.isImageLocked($0.id) } == true
  }
  var canEditSmartObjectContents: Bool {canEditSmartObject && activeLayer?.smartObject?.pdfSource == nil}
  var canConvertSmartObject: Bool {
    clipboardTargetAvailable && !groupSelectionIDs.isEmpty
      && groupSelectionIDs.allSatisfy { !document.isLocked($0) }
  }
  func convertSmartObject() {
    guard canConvertSmartObject else { return }
    let ids = groupSelectionIDs
    performGeometry(label: "Convert to Smart Object", prepare: { original in
      try SmartObjectIO.convert(in: original, selected: ids)
    }, onSuccess: { [weak self] in
      self?.selectedLayerIDs = Set(self?.document.activeLayerID.map { [$0] } ?? [])
    })
  }
  func placeEmbedded(replacing: Bool = false) {
    guard clipboardTargetAvailable, !replacing || canEditSmartObject else { return }
    let lifecycle = layerPanelGeneration,sessionID = sessionGeneration
    let layerID = replacing ? activeLayer?.id : nil
    let frameID = replacing ? nil : selectedFrame?.id
    let panel = NSOpenPanel()
    panel.title = replacing ? "Replace Contents" : "Place Embedded"
    panel.allowedContentTypes = [.pdf, RawSourceIO.contentType, .png, .jpeg, .tiff, .heic, .bmp, .gif, UTType(filenameExtension: "psd") ?? .data,
      UTType(filenameExtension: "psb") ?? .data, UTType(filenameExtension: "photato") ?? .data]
    panel.canChooseDirectories = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url, let self, self.clipboardTargetAvailable,
        self.layerPanelGeneration == lifecycle,self.sessionGeneration == sessionID else { return }
      self.placeEmbeddedSource(url,replacing:layerID,frame:frameID)
    }
  }
  func editSmartObjectContents() {
    if activeLayer?.smartObject?.rawDevelopment != nil { beginRawDevelopment(); return }
    guard canEditSmartObjectContents, let layer = activeLayer, let source = layer.smartObject,
      let controller = documentController,
      let parent = controller.documents.compactMap({ $0 as? CraftNSDocument }).first(where: { $0.store === self }) else { return }
    if let existing = controller.documents.compactMap({ $0 as? CraftNSDocument }).first(where: {
      $0.smartObjectEditLink?.parent === parent && $0.smartObjectEditLink?.sourceID == source.sourceID
    }) { existing.showWindows(); return }
    geometryBusy = true
    geometryTask = Task { [weak self, weak parent] in
      guard let self else { return }
      defer { self.geometryBusy = false; self.geometryTask = nil }
      do {
        let worker = Task.detached(priority: .userInitiated) { try SmartObjectIO.sourceDocument(source) }
        let model = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let parent, controller.documents.contains(where: { $0 === parent }),
          self.document.layers.first(where: { $0.id == layer.id })?.smartObject == source else {
          throw CraftError.invalid("The parent Smart Object changed before its contents opened.")
        }
        let child = CraftNSDocument(model: model)
        child.smartObjectEditLink = SmartObjectEditLink(parent: parent, layerID: layer.id, source: source)
        child.displayName = layer.name + " — Contents"
        controller.addDocument(child); child.makeWindowControllers(); child.showWindows()
      } catch { self.error = error.localizedDescription }
    }
  }
  func exportSmartObjectContents() {
    guard clipboardTargetAvailable, let source = activeLayer?.smartObject else { return }
    let panel = NSSavePanel(); panel.title = "Export Contents"; panel.nameFieldStringValue = source.fileName
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      do { try source.data.write(to: url, options: .atomic) }
      catch { self?.error = error.localizedDescription }
    }
  }
}

extension CraftNSDocument {
  /// Saving an embedded editor updates all ordinary instances in its parent in one Undo step.
  func commitSmartObjectContents() async throws {
    guard let link = smartObjectEditLink, let parent = link.parent,
      parent.ownerController?.documents.contains(where: { $0 === parent }) == true,
      parent.store.clipboardTargetAvailable, !fileOperationBusy,
      let current = parent.store.document.layers.first(where: { $0.id == link.layerID })?.smartObject,
      current.sourceID == link.sourceID, current.revision == link.revision else {
      throw CraftError.invalid("The parent Smart Object is unavailable or changed. Use Save As to keep an independent copy.")
    }
    let original = parent.store.document, contents = store.document
    fileOperationBusy = true; parent.store.geometryBusy = true
    defer { fileOperationBusy = false; parent.store.geometryBusy = false; parent.store.render() }
    let targetID = link.layerID
    let worker = Task.detached(priority: .userInitiated) {
      let command = try SmartObjectIO.replacement(in: original, layerID: targetID,
        source: contents, preserveSize: false)
      return try PreparedEdit(command: command, document: original)
    }
    let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    guard parent.ownerController != nil, parent.store.document == original, store.document == contents else {
      throw CraftError.invalid("The parent or contents changed during Save. Retry the save.")
    }
    try parent.store.executeCompositePreparedEdit(prepared)
    if parent.store.document != original { parent.updateChangeCount(.changeDone) }
    link.revision = parent.store.document.layers.first(where: { $0.id == link.layerID })!.smartObject!.revision
    updateChangeCount(.changeCleared)
    store.status = "Smart Object contents saved to parent"
  }
}

extension AppDelegate {
  @objc func placeEmbedded() { store?.placeEmbedded() }
  @objc func convertSmartObject() { store?.convertSmartObject() }
  @objc func editSmartObjectContents() { store?.editSmartObjectContents() }
  @objc func replaceSmartObjectContents() { store?.placeEmbedded(replacing: true) }
  @objc func exportSmartObjectContents() { store?.exportSmartObjectContents() }
  @objc func independentSmartObjectCopy() {
    if let store, store.canEditSmartObject, let id = store.activeLayer?.id { store.perform(.independentSmartObjectCopy(id)) }
  }
  @objc func resetSmartObjectTransform() {
    if let store, store.canEditSmartObject, let id = store.activeLayer?.id { store.perform(.resetSmartObjectTransform(id)) }
  }
}
