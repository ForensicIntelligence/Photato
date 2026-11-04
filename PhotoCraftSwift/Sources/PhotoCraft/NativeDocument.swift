import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor final class CraftNSDocument: NSDocument {
  nonisolated static let nativeType = "local.photocraft.swift.document"
  var smartObjectEditLink: SmartObjectEditLink?
  let store: EditorStore
  var rememberedPrintInfo: NSPrintInfo?
  var printJob: NativePrintJob?
  var printTask: Task<Void, Never>?
  var printRunner: ((PreparedPrint, NSPrintInfo, @escaping @MainActor (Bool) -> Void) -> Void)?
  var fileOperationBusy = false
  var fileOperationTask: Task<Void, Never>?
  var closeWorkflowID: UUID?
  weak var closeSavePanel: NSSavePanel?
  var recoveryWriteBusy = false
  var lastRecoveryWriteFailed = false
  var recoverySnapshotRequested = false
  private var closeAfterRecovery = false
  private var recoveryContentGeneration: UInt64 = 0
  private var activeRecoveryGeneration: UInt64?
  private var savedRecoveryGeneration: UInt64?
  var recoveryEncoder: RecoveryEncoder?
  var recoveryGroupID = UUID()
  var recoverySnapshotContext: RecoverySnapshotContext?
  var recoveryRegistrationError: String?
  var recoverySourceRecord: RecoverySourceRecord?
  var pendingRecoveryContext: Data?
  var recoverySourceStatus: RecoverySourceStatus = .none
  var isRecoveredSource = false
  var sourceVerificationTask: Task<Void, Never>?
  var sourceVerificationGeneration = UUID()
  var recoverySourceAccessURL: URL?
  nonisolated let recoveryWrites = RecoveryWriteState()
  var copyPanel: NSSavePanel?
  var sourceSaveNeedsReview = false
  var preparedSaveOutput: (type: String, output: PreparedDocumentOutput, hidden: Bool)?
  var saveAccessory: DocumentCopyAccessory?
  var rememberedEncodingOptions: [DocumentIO.Format: RasterEncodingOptions] = [:]
  var saveEncoder: DocumentIO.Encoder?
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
    name: String = "Untitled-1", mode: DocumentColorMode? = nil,
    profile: Data? = nil, resolution: Double? = nil
  ) throws -> CraftDocument {
    try DocumentCreation.blank(width: width, height: height, depth: depth,
      background: background, name: name, mode: mode, profile: profile, resolution: resolution)
  }
  /// AppKit's autosave/reopen factories initialize first, then call read(from:ofType:).
  /// This bounded placeholder is replaced before the recovered document is presented.
  override convenience init() {
    self.init(model: try! CraftDocument(width: 1, height: 1))
  }
  init(
    model: CraftDocument, actions: ActionLibrary? = nil, brushes: BrushLibrary? = nil, skies:SkyLibrary? = nil, shapes:ShapeLibrary? = nil,
    prepareHistory: @escaping HistoryPreparation = NativeHistoryNavigation.prepare
  ) {
    store = EditorStore(document: model, actions: actions, brushes: brushes, skies:skies, shapes:shapes, prepareHistory: prepareHistory)
    super.init()
    fileType = Self.nativeType
    hasUndoManager = false
    displayName = model.name
    store.onChange = { [weak self] kind in self?.updateChangeCount(kind); self?.store.synchronizeLinkedArtwork() }
  }
  // Recovery must not replace the last explicit Save used by File > Revert.
  override class var autosavesInPlace: Bool { false }
  override func makeWindowControllers() {
    ownerController?.documentWindows.present(self)
  }
  var openRawDevelopmentOnDisplay = false
  override func showWindows() {
    ownerController?.documentWindows.present(self)
    if openRawDevelopmentOnDisplay { openRawDevelopmentOnDisplay = false; store.beginRawDevelopment() }
  }
  override func restoreWindow(
    withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
    completionHandler: @escaping @Sendable (NSWindow?, (any Error)?) -> Void
  ) {
    makeWindowControllers()
    completionHandler(ownerController?.documentWindows.group(for: self)?.window, nil)
  }
  override var windowForSheet: NSWindow? {
    ownerController?.documentWindows.group(for: self)?.window ?? super.windowForSheet
  }
  override var hasUnautosavedChanges: Bool {
    (recoveryRegistrationError != nil && isDocumentEdited) || super.hasUnautosavedChanges
      || (autosavedContentsFileURL != nil
        && savedRecoveryGeneration.map { $0 != recoveryContentGeneration } == true)
  }
  override func updateChangeCount(_ change: NSDocument.ChangeType) {
    // Legacy autosavesElsewhere reports changeAutosaved, without a change token.
    // Its default count reset would otherwise mark edits made during writing as
    // already backed up. Retain the generation of the actual captured value.
    if change == .changeAutosaved {
      if let activeRecoveryGeneration { savedRecoveryGeneration = activeRecoveryGeneration }
    } else {
      recoveryContentGeneration &+= 1
      if change == .changeCleared { savedRecoveryGeneration = nil }
    }
    super.updateChangeCount(change)
    if !isDocumentEdited, !recoveryWriteBusy { retireRecoveryRegistration() }
    ownerController?.documentWindows.group(for: self)?.updateDocumentPresentation()
  }
  var photatoWindowTitle: String { "Photato - " + (displayName ?? store.document.name) }
  override var displayName: String! {
    didSet { ownerController?.documentWindows.group(for: self)?.updateDocumentPresentation() }
  }
  override var fileURL: URL? {
    didSet {
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.fileURL != nil { self.smartObjectEditLink = nil }
        if fileURL != nil { importedURL = nil }
        ownerController?.documentWindows.group(for: self)?.updateDocumentPresentation()
      }
    }
  }
  override func data(ofType typeName: String) throws -> Data {
    if let preparedSaveOutput, preparedSaveOutput.type == typeName,
      case .data(let bytes) = preparedSaveOutput.output
    {
      return bytes
    }
    guard let format = DocumentIO.Format(typeIdentifier: typeName) else {
      throw CraftError.unsupported("Unsupported save format.")
    }
    store.finishNumericField()
    store.finishLayerName()
    return try DocumentIO.encodeForPersistence(store.document, format: format,
      options: effectiveEncodingOptions(compatibleRememberedEncodingOptions[format] ?? .init(), format: format, persistence: true))
  }
  override nonisolated func write(to url: URL, ofType typeName: String) throws {
    let prepared: (type: String, output: PreparedDocumentOutput, hidden: Bool)?
    if Thread.isMainThread {
      prepared = MainActor.assumeIsolated { preparedSaveOutput }
    } else {
      prepared = DispatchQueue.main.sync { preparedSaveOutput }
    }
    if let prepared, prepared.type == typeName {
      try prepared.output.write(to: url, destinationHidden: prepared.hidden)
    } else if typeName == Self.nativeType {
      // Direct native writes outside the coordinated recovery path.
      let snapshot: CraftDocument
      if Thread.isMainThread {
        snapshot = MainActor.assumeIsolated {
          return store.document
        }
      } else {
        snapshot = DispatchQueue.main.sync {
          return store.document
        }
      }
      try NativeArchive.write(snapshot, to: url)
    } else {
      try super.write(to: url, ofType: typeName)
    }
  }
  override func canAsynchronouslyWrite(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType
  ) -> Bool {
    typeName == Self.nativeType && NativeRecoveryWriting.isRecovery(saveOperation)
  }
  override nonisolated func write(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    originalContentsURL: URL?
  ) throws {
    guard typeName == Self.nativeType, NativeRecoveryWriting.isRecovery(saveOperation) else {
      try super.write(
        to: url, ofType: typeName, for: saveOperation, originalContentsURL: originalContentsURL)
      return
    }
    let snapshot = recoveryWrites.current()
    // The immutable value was captured on the main actor before super.save.
    // Release AppKit's main-thread wait before serialization or any test encoder.
    unblockUserInteraction()
    guard let snapshot else { throw CocoaError(.userCancelled) }
    defer { recoveryWrites.finish(snapshot.id) }
    try snapshot.encode(snapshot.document, url, snapshot.context)
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
    if NativeRecoveryWriting.isRecovery(saveOperation) { return [Self.nativeType] }
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
    if closeWorkflowID != nil { closeSavePanel = panel }
    let accessory = DocumentCopyAccessory(
      panel: panel, initial: persistenceFormat,
      availableFormats: saveFormats, saving: true, initialOptions: compatibleRememberedEncodingOptions,
      uncompressedPhotoshopDefault: fileHandlingPreferences.disablePSDCompression
        && store.document.depth != .u8, depth: store.document.depth, mode: store.document.colorMode)
    saveAccessory = accessory
    panel.accessoryView = accessory.view
    return super.prepareSavePanel(panel)
  }
  override func autosave(
    withImplicitCancellability autosavingIsImplicitlyCancellable: Bool,
    completionHandler: @escaping ((any Error)?) -> Void
  ) {
    guard ownerController?.recoveryIndex.isBusy != true, closeWorkflowID == nil, !recoveryWriteBusy, !fileOperationBusy || recoverySnapshotRequested,
      ownerController?.recoveryPreferences.value.enabled != false || recoverySnapshotRequested
    else {
      completionHandler(CocoaError(.userCancelled))
      return
    }
    do {
      if hasUnautosavedChanges, let index = ownerController?.recoveryIndex,
        let target = try index.backupURL(for: recoveryGroupID)
      {
        autosavedContentsFileURL = target
      }
    } catch {
      recoveryRegistrationError = "The private recovery location could not be prepared."
      lastRecoveryWriteFailed = true
      completionHandler(error)
      return
    }
    super.autosave(withImplicitCancellability: autosavingIsImplicitlyCancellable,
      completionHandler: completionHandler)
  }
  override func save(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    completionHandler: @escaping (Error?) -> Void
  ) {
    // Recovery autosaves arrive inside AppKit's file-access activity. Deferring
    // that call to a new Task loses its reentrant context and deadlocks AppKit.
    // Invoke super synchronously in that context; AppKit dispatches the captured
    // recovery value to its background writer and owns file coordination.
    // Recovery generations separately retain edits made during legacy autosaving.
    guard !NativeRecoveryWriting.isRecovery(saveOperation) else {
      // A previously scheduled AppKit autosave can arrive after the timer is disabled.
      guard ownerController?.recoveryPreferences.value.enabled != false || recoverySnapshotRequested
      else {
        completionHandler(CocoaError(.userCancelled))
        return
      }
      guard ownerController?.recoveryIndex.isBusy != true, closeWorkflowID == nil, !recoveryWriteBusy, !fileOperationBusy || recoverySnapshotRequested else {
        completionHandler(CocoaError(.userCancelled))
        return
      }
      let snapshotContext = RecoverySnapshotContext(recoveryID: recoveryGroupID,
        snapshotID: UUID(), documentID: store.document.id, sourceURL: fileURL,
        source: recoverySourceRecord)
      let context: Data
      do {
        context = try snapshotContext.encoded()
        try ownerController?.recoveryIndex.begin(snapshotContext, backupURL: url)
        recoveryRegistrationError = nil
      } catch {
        recoveryRegistrationError = "Recovery registration could not be saved. Existing backups are preserved."
        lastRecoveryWriteFailed = true
        completionHandler(error)
        return
      }
      let recoveryID = recoveryWrites.begin(store.document, context: context,
        encoder: recoveryEncoder ?? NativeRecoveryWriting.write)
      activeRecoveryGeneration = recoveryContentGeneration
      recoveryWriteBusy = true
      super.save(
        to: url, ofType: Self.nativeType, for: saveOperation
      ) { [weak self, recoveryID] error in
        var result = error
        if let self {
          self.recoveryWrites.finish(recoveryID)
          if error == nil {
            self.savedRecoveryGeneration = self.activeRecoveryGeneration
            self.recoverySnapshotContext = snapshotContext
            do {
              if self.isDocumentEdited, self.autosavedContentsFileURL != nil {
                try self.ownerController?.recoveryIndex.finish(snapshotContext.snapshotID)
              } else {
                try self.ownerController?.recoveryIndex.retire(self.recoveryGroupID)
              }
              self.recoveryRegistrationError = nil
            } catch {
              self.recoveryRegistrationError = "The backup was written, but recovery registration needs attention."
              result = error
            }
          }
          self.activeRecoveryGeneration = nil
          self.recoveryWriteBusy = false
          self.lastRecoveryWriteFailed = result != nil
          if self.closeAfterRecovery {
            self.closeAfterRecovery = false
            self.close()
          }
        }
        completionHandler(result)
      }
      return
    }
    guard let format = DocumentIO.Format(typeIdentifier: typeName) else {
      completionHandler(CraftError.unsupported("Unsupported save format."))
      return
    }
    let options = saveOperation == .saveAsOperation && saveAccessory?.format == format
      ? saveAccessory?.encodingOptions : compatibleRememberedEncodingOptions[format]
    fileOperationTask = Task { [weak self] in
      guard let self else {
        completionHandler(CancellationError())
        return
      }
      defer { self.fileOperationTask = nil }
      do {
        try await self.persistDocument(
          to: url, format: format, operation: saveOperation, options: options, encoder: self.saveEncoder)
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
    try applyDecodedDocument(model)
  }
  override nonisolated func read(from url: URL, ofType typeName: String) throws {
    // The declared type also covers recovery files without a visible extension.
    if typeName == Self.nativeType {
      let prepared = Thread.isMainThread
        ? MainActor.assumeIsolated { RecoveryReadHandoff.consume(url) } : nil
      let result = try prepared ?? NativeArchive.readRecovery(url)
      if prepared == nil { _ = try ColorManagement.space(for: result.document) }
      try applyDecodedDocument(result.document, recoveryContext: result.context)
    } else {
      try applyDecodedDocument(DocumentIO.read(url))
    }
  }
  private nonisolated func applyDecodedDocument(_ model: CraftDocument, recoveryContext: Data? = nil) throws {
    if Thread.isMainThread {
      try MainActor.assumeIsolated {
        guard !recoveryWriteBusy else {
          throw CraftError.invalid("Wait for the recovery backup before replacing this document.")
        }
        resetRecoverySource()
        pendingRecoveryContext = recoveryContext
        recoverySnapshotContext = RecoverySnapshotContext.decode(recoveryContext)
        if let recoverySnapshotContext { recoveryGroupID = recoverySnapshotContext.recoveryID }
        recoveryContentGeneration &+= 1
        store.layerOpacityDraft = nil
        store.finishNumericField(cancel: true)
        store.finishLayerName(cancel: true)
        store.layerVisibilityDraft = nil
        store.layerVisibilityIsolation = nil
        store.alphaEditingID = nil
        store.nonQuickMaskDocumentID = nil; store.nonQuickMaskID = nil
        store.alphaOverlay = false
        store.componentTarget = .composite; store.modeComponentTargets = []; store.modeComponentVisibility = nil
        store.channelView = RGBChannelView()
        store.session = EditorSession(document: model)
        store.timelineVisible = model.animation != nil || model.videoTimeline != nil
        store.cancelRegionRetouch(); store.cancelCrop(); store.clearContentAwareScale(); store.cancelEmbeddedPlacement(); store.closePDFSourceEditors(); store.cancelSelectionTransform();store.transformDraft = nil
    resetPrintWorkspace()
    store.backgroundLayerDraft=nil
    store.proofWorkspace = nil
    store.inkChannelOptions = nil
    store.inkModeWorkspace?.close(); store.inkModeWorkspace = nil
    store.restrictedModeWorkspace?.close(); store.restrictedModeWorkspace = nil
    store.documentModeWorkspace?.close(); store.documentModeWorkspace = nil
    store.skyWorkspace?.close(); store.skyWorkspace = nil
    store.contentAwareDraft?.close(); store.contentAwareDraft = nil
    store.cancelSelectionModify();store.selectionRecall=nil
    store.cancelMagneticLasso()
    store.colorRangeDraft?.close(); store.colorRangeDraft = nil
    store.selectMaskDraft?.close(); store.selectMaskDraft = nil
    store.stopBrushPreview();store.brushGesture = nil
    store.objectFinder.cancel(); store.peopleWorkspace.close()
    store.layerPanelGeneration = UUID()
        store.invalidateHistory()
        store.geometryTask?.cancel()
        store.geometryBusy = false
        store.clearMaskView()
        store.maskEditingLayerID = nil
        store.layerPanelOptionsDraft = nil
        store.cancelChannelDialog()
        store.channelPanelOptionsDraft = nil
        store.render()
      }
    } else {
      try DispatchQueue.main.sync {
        guard !recoveryWriteBusy else {
          throw CraftError.invalid("Wait for the recovery backup before replacing this document.")
        }
        resetRecoverySource()
        pendingRecoveryContext = recoveryContext
        recoverySnapshotContext = RecoverySnapshotContext.decode(recoveryContext)
        if let recoverySnapshotContext { recoveryGroupID = recoverySnapshotContext.recoveryID }
        recoveryContentGeneration &+= 1
        store.layerOpacityDraft = nil
        store.finishNumericField(cancel: true)
        store.finishLayerName(cancel: true)
        store.layerVisibilityDraft = nil
        store.layerVisibilityIsolation = nil
        store.alphaEditingID = nil
        store.nonQuickMaskDocumentID = nil; store.nonQuickMaskID = nil
        store.alphaOverlay = false
        store.componentTarget = .composite; store.modeComponentTargets = []; store.modeComponentVisibility = nil
        store.channelView = RGBChannelView()
        store.session = EditorSession(document: model)
        store.timelineVisible = model.animation != nil || model.videoTimeline != nil
        store.cancelRegionRetouch(); store.cancelCrop(); store.clearContentAwareScale(); store.cancelEmbeddedPlacement(); store.closePDFSourceEditors(); store.cancelSelectionTransform();store.transformDraft = nil
    resetPrintWorkspace()
    store.backgroundLayerDraft=nil
    store.proofWorkspace = nil
    store.inkChannelOptions = nil
    store.inkModeWorkspace?.close(); store.inkModeWorkspace = nil
    store.restrictedModeWorkspace?.close(); store.restrictedModeWorkspace = nil
    store.documentModeWorkspace?.close(); store.documentModeWorkspace = nil
    store.skyWorkspace?.close(); store.skyWorkspace = nil
    store.contentAwareDraft?.close(); store.contentAwareDraft = nil
    store.cancelSelectionModify();store.selectionRecall=nil
    store.cancelMagneticLasso()
    store.colorRangeDraft?.close(); store.colorRangeDraft = nil
    store.selectMaskDraft?.close(); store.selectMaskDraft = nil
    store.stopBrushPreview();store.brushGesture = nil
    store.objectFinder.cancel(); store.peopleWorkspace.close()
    store.layerPanelGeneration = UUID()
        store.invalidateHistory()
        store.geometryTask?.cancel()
        store.geometryBusy = false
        store.clearMaskView()
        store.maskEditingLayerID = nil
        store.layerPanelOptionsDraft = nil
        store.cancelChannelDialog()
        store.channelPanelOptionsDraft = nil
        store.render()
      }
    }
  }
  override func close() {
    store.stopTimelinePlayback(render: false)
    if recoveryWriteBusy {
      closeAfterRecovery = true
      return
    }
    retireRecoveryRegistration()
    resetRecoverySource()
    store.invalidateHistory()
    fileOperationTask?.cancel()
    copyPanel?.cancel(nil)
    store.cancelRegionRetouch(); store.cancelCrop(); store.clearContentAwareScale(); store.cancelEmbeddedPlacement(); store.closePDFSourceEditors(); store.cancelSelectionTransform();store.transformDraft = nil
    resetPrintWorkspace()
    store.backgroundLayerDraft=nil
    store.proofWorkspace = nil
    store.inkChannelOptions = nil
    store.inkModeWorkspace?.close(); store.inkModeWorkspace = nil
    store.restrictedModeWorkspace?.close(); store.restrictedModeWorkspace = nil
    store.documentModeWorkspace?.close(); store.documentModeWorkspace = nil
    store.skyWorkspace?.close(); store.skyWorkspace = nil
    store.contentAwareDraft?.close(); store.contentAwareDraft = nil
    store.cancelSelectionModify();store.selectionRecall=nil
    store.cancelMagneticLasso()
    store.colorRangeDraft?.close(); store.colorRangeDraft = nil
    store.selectMaskDraft?.close(); store.selectMaskDraft = nil
    store.stopBrushPreview();store.brushGesture = nil
    store.objectFinder.cancel(); store.peopleWorkspace.close()
    store.layerPanelGeneration = UUID()
    store.clearMaskView()
    store.maskEditingLayerID = nil
    store.layerPanelOptionsDraft = nil
    store.cancelChannelDialog()
        store.channelPanelOptionsDraft = nil
    store.layerOpacityDraft = nil
        store.finishNumericField(cancel: true)
    store.finishLayerName(cancel: true)
    store.colorLookupDraft = nil
    store.classicAdjustmentDraft = nil
    store.shapedTypeDraft?.close();store.shapedTypeDraft=nil
    store.textFindWorkspace?.task?.cancel();store.textFindWorkspace=nil
    store.typeEditingDraft = nil
    store.typeEditor?.delegate = nil
    store.typeEditor = nil
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
  private(set) var paintPalette = PaintPalette()
  var movieFramesWorkspace: MovieFramesWorkspace?
  var movieFramesWindow: MovieFramesWindow?
  var scanCropOperationID: UUID?
  var contactSheetWorkspace: ContactSheetWorkspace?
  var contactSheetWindow: ContactSheetWindow?
  var imageStackWorkspace: ImageStackWorkspace?
  var imageStackWindow: ImageStackWindow?
  var hdrMergeWorkspace: HDRMergeWorkspace?
  var hdrMergeWindow: HDRMergeWindow?
  var photomergeWorkspace: PhotomergeWorkspace?
  var photomergeWindow: PhotomergeWindow?
  lazy var documentClosing = DocumentCloseCoordinator(controller: self)
  lazy var documentOpening = DocumentOpening(controller: self)
  lazy var recoveryMaintenance = RecoveryMaintenance(controller: self)
  lazy var recoveryDiscovery = RecoveryDiscovery(controller: self)
  var recoveryMaintenanceWindow: RecoveryMaintenanceWindowController?
  var recoverySalvageWindow: RecoverySalvageWindowController?
  var documentOpenPanel: NSOpenPanel?
  var documentOpenAccessory: DocumentOpenAccessory?
  private(set) var workspaces = WorkspaceLibrary()
  private(set) var recoveryPreferences = RecoveryPreferencesStore()
  private(set) var colorSettings = ColorSettingsStore()
  private(set) var recoveryIndex = RecoveryIndexStore()
  var initialRecoveryTask: Task<Void, Never>?
  var initialRecoveryFinished = false
  var recoveryDiscoveryGeneration = UUID()
  var pendingUntitledRequest = false
  convenience init(
    workspaces: WorkspaceLibrary, recoveryPreferences: RecoveryPreferencesStore? = nil,
    recoveryIndex: RecoveryIndexStore? = nil, colorSettings: ColorSettingsStore? = nil,
    paintPalette: PaintPalette? = nil
  ) {
    self.init()
    // AppKit may return its existing document-controller singleton from init().
    // Configure the returned instance, not storage allocated before super.init().
    self.workspaces = workspaces
    self.paintPalette = paintPalette ?? PaintPalette()
    self.recoveryPreferences = recoveryPreferences ?? RecoveryPreferencesStore()
    self.colorSettings = colorSettings ?? ColorSettingsStore()
    self.recoveryIndex = recoveryIndex ?? RecoveryIndexStore()
    self.recoveryMaintenance = RecoveryMaintenance(controller: self)
    self.recoveryDiscovery = RecoveryDiscovery(controller: self)
    initialRecoveryFinished = false
    autosavingDelay = self.recoveryPreferences.value.delay
    for case let document as CraftNSDocument in documents {
      document.store.workspaceLibrary = workspaces
      document.store.adoptPaintPalette(self.paintPalette)
    }
  }
  override var currentDocument: NSDocument? {
    documentWindows.activeDocument ?? super.currentDocument
  }
  override func closeAllDocuments(
    withDelegate delegate: Any?, didCloseAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
  ) {
    let reply = NativeDocumentControllerCloseReply(delegate, selector: didCloseAllSelector, context: contextInfo)
    requestDocumentClose(closeTargets(), scope: .all) { [weak self] result in
      if let self { reply.deliver(self, completed: result?.phase == .completed) }
    }
  }
  override func reviewUnsavedDocuments(
    withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
    didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
  ) {
    let reply = NativeDocumentControllerCloseReply(delegate, selector: didReviewAllSelector, context: contextInfo)
    requestDocumentClose(closeTargets(), scope: .quit, cancellable: cancellable) { [weak self] result in
      if let self { reply.deliver(self, completed: result?.phase == .completed) }
    }
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
    (document as? CraftNSDocument)?.store.adoptPaintPalette(paintPalette)
    (document as? CraftNSDocument)?.store.workspaceLibrary = workspaces
    (document as? CraftNSDocument)?.store.synchronizeLinkedArtwork()
  }
  override func removeDocument(_ document: NSDocument) {
    if let document = document as? CraftNSDocument {
      documentWindows.remove(document)
      document.store.linkedSourceController?.stop()
      document.store.linkedSourceController = nil
      document.ownerController = nil
      document.store.documentController = nil
      document.store.detachPaintPalette()
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
  override func makeDocument(
    for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String
  ) throws -> NSDocument {
    let document = try super.makeDocument(
      for: urlOrNil, withContentsOf: contentsURL, ofType: typeName)
    guard let document = document as? CraftNSDocument, let source = urlOrNil,
      source.standardizedFileURL != contentsURL.standardizedFileURL
    else { return document }
    // AppKit passes the snapshot's native type, even when its explicit Save source
    // is PSD/PSB/raster. Never adopt that type for writing back to the original.
    let format: DocumentIO.Format?
    if let hint = RecoveryReadHandoff.sourceHint(source) { format = hint.sourceFormat }
    else {
      let regular = (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      format = regular ? DocumentIO.sourceFormat(source) : nil
    }
    document.fileType =
      (format ?? DocumentIO.Format(fileExtension: source.pathExtension.lowercased()) ?? .native)
      .typeIdentifier
    document.restoreRecoverySource(registeredURL: source)
    return document
  }
  override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument
  {
    try PreparedLocalDocument.read(url, format: .automatic).makeDocument(url: url)
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
    documentOpening.enqueue(url, display: displayDocument, completion: completionHandler)
  }
  override func openDocument(_ sender: Any?) {
    guard documentOpenPanel == nil, documentOpening.canStart else { return }
    let panel = NSOpenPanel()
    DocumentIO.configureOpenPanel(panel)
    let accessory = DocumentOpenAccessory(panel: panel)
    panel.accessoryView = accessory.view
    panel.isAccessoryViewDisclosed = true
    documentOpenPanel = panel; documentOpenAccessory = accessory
    panel.begin { [weak self] result in
      guard let self else { return }
      self.documentOpenPanel = nil; self.documentOpenAccessory = nil
      guard result == .OK else { return }
      Task { @MainActor in
      var lastError: Error?
      do {
        try self.documentOpening.begin(panel.urls, format: accessory.format, display: true,
          showProgress: true, completion: { _, _, error in
            if let error, (error as NSError).code != NSUserCancelledError { lastError = error }
          }, finished: { _ in
            if let error = lastError {
              RunLoop.main.perform { MainActor.assumeIsolated { NSApp.presentError(error) } }
            }
          })
      } catch { NSApp.presentError(error) }
      }
    }
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
