import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor final class CraftNSDocument: NSDocument {
  nonisolated static let nativeType = "local.photocraft.swift.document"
  let store: EditorStore
  var fileOperationBusy = false
  var fileOperationTask: Task<Void, Never>?
  var copyPanel: NSSavePanel?
  var sourceSaveNeedsReview = false
  var preparedSaveData: (type: String, bytes: Data)?
  var saveAccessory: DocumentCopyAccessory?
  var saveEncoder: @Sendable (CraftDocument, DocumentIO.Format) throws -> Data = DocumentIO
    .encodeForPersistence
  // Imported images are currently saved as native documents. Keep their open
  // identity separately so opening the source again focuses the existing edit.
  private var importedURL: URL?
  var importedSourceURL: URL? {
    get { fileURL == nil ? importedURL : nil }
    set { importedURL = newValue }
  }
  weak var ownerController: CraftDocumentController?
  static func blankModel(
    width: Int = 1200, height: Int = 800, depth: PixelDepth = .u8, background: Pixel = .white,
    name: String = "Untitled-1"
  ) throws -> CraftDocument {
    var model = try CraftDocument(width: width, height: height, depth: depth, name: name)
    model.layers[0].content = .raster(
      try Surface(width: width, height: height, depth: depth, fill: background))
    model.layers[0].name = background.a == 0 ? "Layer 1" : "Background"
    return model
  }
  init(model: CraftDocument) {
    store = EditorStore(document: model)
    super.init()
    fileType = Self.nativeType
    hasUndoManager = false
    displayName = model.name
    store.onChange = { [weak self] kind in self?.updateChangeCount(kind) }
  }
  // Recovery must not replace the last explicit Save used by File > Revert.
  override class var autosavesInPlace: Bool { false }
  override func makeWindowControllers() {
    ownerController?.documentWindows.present(self)
  }
  override func showWindows() { ownerController?.documentWindows.present(self) }
  override var windowForSheet: NSWindow? {
    ownerController?.documentWindows.group(for: self)?.window ?? super.windowForSheet
  }
  override func updateChangeCount(_ change: NSDocument.ChangeType) {
    super.updateChangeCount(change)
    ownerController?.documentWindows.group(for: self)?.updateDocumentPresentation()
  }
  override var fileURL: URL? {
    didSet {
      Task { @MainActor [weak self] in
        guard let self else { return }
        if fileURL != nil { importedURL = nil }
        ownerController?.documentWindows.group(for: self)?.updateDocumentPresentation()
      }
    }
  }
  override func data(ofType typeName: String) throws -> Data {
    if let preparedSaveData, preparedSaveData.type == typeName { return preparedSaveData.bytes }
    guard let format = DocumentIO.Format(typeIdentifier: typeName) else {
      throw CraftError.unsupported("Unsupported save format.")
    }
    store.finishNumericField()
    store.finishLayerName()
    return try DocumentIO.encodeForPersistence(store.document, format: format)
  }
  override class var readableTypes: [String] { DocumentIO.readableTypes }
  override class var writableTypes: [String] { DocumentIO.Format.allCases.map(\.typeIdentifier) }
  override class func isNativeType(_ type: String) -> Bool {
    DocumentIO.Format(typeIdentifier: type) != nil
  }
  override nonisolated var autosavingFileType: String? { Self.nativeType }
  override nonisolated func writableTypes(for saveOperation: NSDocument.SaveOperationType)
    -> [String]
  {
    if Thread.isMainThread { return MainActor.assumeIsolated { saveFormats.map(\.typeIdentifier) } }
    return DispatchQueue.main.sync { saveFormats.map(\.typeIdentifier) }
  }
  @available(macOS 15.0, *)
  override var savePanelShowsFileFormatsControl: Bool { false }
  override nonisolated var fileTypeFromLastRunSavePanel: String? {
    if Thread.isMainThread {
      return MainActor.assumeIsolated { saveAccessory?.format.typeIdentifier }
    }
    return DispatchQueue.main.sync { saveAccessory?.format.typeIdentifier }
  }
  override func prepareSavePanel(_ panel: NSSavePanel) -> Bool {
    let accessory = DocumentCopyAccessory(
      panel: panel, initial: persistenceFormat,
      availableFormats: saveFormats, saving: true)
    saveAccessory = accessory
    panel.accessoryView = accessory.view
    return super.prepareSavePanel(panel)
  }
  override func save(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    completionHandler: @escaping (Error?) -> Void
  ) {
    // Recovery autosaves arrive inside AppKit's file-access activity. Deferring
    // that call to a new Task loses its reentrant context and deadlocks AppKit.
    // Keep this native archive callback synchronous; ordinary saves pre-encode.
    guard [.saveOperation, .saveAsOperation, .saveToOperation].contains(saveOperation) else {
      super.save(
        to: url, ofType: Self.nativeType, for: saveOperation, completionHandler: completionHandler)
      return
    }
    guard let format = DocumentIO.Format(typeIdentifier: typeName) else {
      completionHandler(CraftError.unsupported("Unsupported save format."))
      return
    }
    fileOperationTask = Task { [weak self] in
      guard let self else {
        completionHandler(CancellationError())
        return
      }
      defer { self.fileOperationTask = nil }
      do {
        try await self.persistDocument(
          to: url, format: format, operation: saveOperation, encoder: self.saveEncoder)
        completionHandler(nil)
      } catch { completionHandler(error) }
    }
  }
  func writePreparedDocument(to url: URL, type: String, operation: NSDocument.SaveOperationType)
    async throws
  {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      super.save(to: url, ofType: type, for: operation) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
  override nonisolated func fileNameExtension(
    forType typeName: String, saveOperation: NSDocument.SaveOperationType
  ) -> String? {
    if saveOperation == .saveOperation {
      let existing: String?
      if Thread.isMainThread {
        existing = MainActor.assumeIsolated {
          fileType == typeName ? fileURL?.pathExtension : nil
        }
      } else {
        existing = DispatchQueue.main.sync {
          fileType == typeName ? fileURL?.pathExtension : nil
        }
      }
      if let existing, !existing.isEmpty { return existing }
    }
    if let format = DocumentIO.Format(typeIdentifier: typeName) { return format.rawValue }
    return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
  }
  override nonisolated func read(from data: Data, ofType typeName: String) throws {
    let model = try DocumentIO.decode(
      data, native: typeName == Self.nativeType, name: "Imported Image")
    if Thread.isMainThread {
      MainActor.assumeIsolated {
        store.finishNumericField(cancel: true)
        store.finishLayerName(cancel: true)
        store.layerVisibilityDraft = nil
        store.layerVisibilityIsolation = nil
        store.componentTarget = .composite
        store.channelView = RGBChannelView()
        store.session = EditorSession(document: model)
        store.layerPanelGeneration = UUID()
        store.geometryTask?.cancel()
        store.geometryBusy = false
        store.clearMaskView()
        store.maskEditingLayerID = nil
        store.layerPanelOptionsDraft = nil
        store.channelPanelOptionsDraft = nil
        store.render()
      }
    } else {
      DispatchQueue.main.sync {
        store.finishNumericField(cancel: true)
        store.finishLayerName(cancel: true)
        store.layerVisibilityDraft = nil
        store.layerVisibilityIsolation = nil
        store.componentTarget = .composite
        store.channelView = RGBChannelView()
        store.session = EditorSession(document: model)
        store.layerPanelGeneration = UUID()
        store.geometryTask?.cancel()
        store.geometryBusy = false
        store.clearMaskView()
        store.maskEditingLayerID = nil
        store.layerPanelOptionsDraft = nil
        store.channelPanelOptionsDraft = nil
        store.render()
      }
    }
  }
  override func close() {
    fileOperationTask?.cancel()
    copyPanel?.cancel(nil)
    store.layerPanelGeneration = UUID()
    store.clearMaskView()
    store.maskEditingLayerID = nil
    store.layerPanelOptionsDraft = nil
    store.channelPanelOptionsDraft = nil
    store.finishNumericField(cancel: true)
    store.finishLayerName(cancel: true)
    store.layerVisibilityDraft = nil
    store.layerVisibilityIsolation = nil
    store.renderTask?.cancel()
    store.aiTask?.cancel()
    store.geometryTask?.cancel()
    store.duplicateTask?.cancel()
    ownerController?.removeDocument(self)
    super.close()
  }
}
@MainActor final class CraftDocumentController: NSDocumentController {
  let documentWindows = DocumentWindows()
  private(set) var workspaces = WorkspaceLibrary()
  convenience init(workspaces: WorkspaceLibrary) {
    self.init()
    // AppKit may return its existing document-controller singleton from init().
    // Configure the returned instance, not storage allocated before super.init().
    self.workspaces = workspaces
    for case let document as CraftNSDocument in documents {
      document.store.workspaceLibrary = workspaces
    }
  }
  override var currentDocument: NSDocument? {
    documentWindows.activeDocument ?? super.currentDocument
  }
  override func document(for window: NSWindow) -> NSDocument? {
    if let group = documentWindows.groups.first(where: { $0.window === window }) {
      return group.workspace.floating
        ? group.workspace.activeDocument : documentWindows.activeDocument
    }
    return super.document(for: window)
  }
  override func addDocument(_ document: NSDocument) {
    super.addDocument(document)
    (document as? CraftNSDocument)?.ownerController = self
    (document as? CraftNSDocument)?.store.documentController = self
    (document as? CraftNSDocument)?.store.workspaceLibrary = workspaces
  }
  override func removeDocument(_ document: NSDocument) {
    if let document = document as? CraftNSDocument {
      documentWindows.remove(document)
      document.ownerController = nil
      document.store.documentController = nil
    }
    super.removeDocument(document)
  }
  var nextUntitledName: String {
    let names = Set(documents.compactMap { ($0 as? CraftNSDocument)?.store.document.name })
    var number = 1
    while names.contains("Untitled-\(number)") { number += 1 }
    return "Untitled-\(number)"
  }
  override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
    CraftNSDocument(model: try CraftNSDocument.blankModel(name: nextUntitledName))
  }
  override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument
  {
    let native = DocumentIO.isNativeFile(url)
    let model = try DocumentIO.read(url)
    let doc = CraftNSDocument(model: model)
    let format = DocumentIO.sourceFormat(url)
    doc.fileType = (format ?? .native).typeIdentifier
    if native || format != nil {
      doc.fileURL = url
      if !native {
        let sourceSpace = model.sourceICC.flatMap { CGColorSpace(iccData: $0 as CFData) }
        doc.sourceSaveNeedsReview =
          (format == .psd && model.depth == .f32)
          || (sourceSpace != nil && sourceSpace != CGColorSpace(name: CGColorSpace.sRGB)
            && sourceSpace != CGColorSpace(name: CGColorSpace.linearSRGB))
      }
      doc.fileModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
    } else {
      doc.importedSourceURL = url.standardizedFileURL.resolvingSymlinksInPath()
    }
    return doc
  }
  override func document(for url: URL) -> NSDocument? {
    if let existing = super.document(for: url) { return existing }
    let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
    return documents.first {
      guard let document = $0 as? CraftNSDocument else { return false }
      return document.revertSourceURL?.standardizedFileURL.resolvingSymlinksInPath() == canonical
    }
  }
  override func beginOpenPanel(
    _ openPanel: NSOpenPanel, forTypes inTypes: [String]?,
    completionHandler: @escaping (Int) -> Void
  ) {
    DocumentIO.configureOpenPanel(openPanel)
    super.beginOpenPanel(
      openPanel, forTypes: DocumentIO.readableTypes, completionHandler: completionHandler)
  }
  override func openDocument(
    withContentsOf url: URL, display displayDocument: Bool,
    completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
  ) {
    if let existing = document(for: url) {
      if displayDocument { existing.showWindows() }
      completionHandler(existing, true, nil)
      return
    }
    do {
      let doc = try makeDocument(
        withContentsOf: url,
        ofType: DocumentIO.isNativeFile(url)
          ? CraftNSDocument.nativeType : "Raster Image")
      addDocument(doc)
      if displayDocument {
        doc.makeWindowControllers()
        doc.showWindows()
      }
      completionHandler(doc, false, nil)
    } catch { completionHandler(nil, false, error) }
  }
  override func documentClass(forType typeName: String) -> AnyClass? { CraftNSDocument.self }
  override var defaultType: String? { CraftNSDocument.nativeType }
  func showDemo() throws {
    let doc = CraftNSDocument(model: try DemoDocument.make())
    doc.fileType = CraftNSDocument.nativeType
    addDocument(doc)
    doc.makeWindowControllers()
    doc.showWindows()
  }
  func showBlank() throws {
    let doc = CraftNSDocument(model: try CraftNSDocument.blankModel(name: nextUntitledName))
    doc.fileType = CraftNSDocument.nativeType
    addDocument(doc)
    doc.makeWindowControllers()
    doc.showWindows()
  }
}
