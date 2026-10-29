import AppKit
import CryptoKit
import ImageIO
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import Security
import UniformTypeIdentifiers

@MainActor @Observable final class AutomationService {
  var liquifyFaceDetector: any LiquifyFaceDetecting = VisionLiquifyFaces()
  struct Share: Identifiable {
    let id = UUID()
    weak var document: CraftNSDocument?
    let generation: UUID
  }
  let controller: CraftDocumentController
  private let server = AutomationHTTPServer()
  @ObservationIgnored let actionJobs: AdobeActionJobs
  private(set) var resourceJobsEnabled = false
  var videoSequenceTask: Task<CraftDocument,Error>?
  var videoSequenceOperationID: UUID?
  var videoSequenceSourceIDs = Set<UUID>()
  @ObservationIgnored var videoRenderShares = Set<UUID>()
  @ObservationIgnored var variableExportShares = Set<UUID>()
  @ObservationIgnored var sequenceExportShares = Set<UUID>()
  private(set) var documentTransfersEnabled = false
  private(set) var documentSavesEnabled = false
  var printingEnabled = false
  @ObservationIgnored var printingGeneration = UUID()
  @ObservationIgnored var ownedPrints: [UUID: UUID] = [:]
  private(set) var preferenceChangesEnabled = false
  private(set) var photoshopPreferenceChangesEnabled = false
  private(set) var colorSettingsChangesEnabled = false
  private(set) var recoveryManagementEnabled = false
  private(set) var recoveryBackupsEnabled = false
  @ObservationIgnored var recoveryBackupsGeneration = UUID()
  private(set) var documentClosingEnabled = false
  private(set) var recentFilesEnabled = false
  @ObservationIgnored var recentFilesGeneration = UUID()
  @ObservationIgnored var ownedRecentOpening: UUID?
  @ObservationIgnored var documentClosingGeneration = UUID()
  @ObservationIgnored var ownedCloseOperation: UUID?
  @ObservationIgnored let applicationTerminator: @MainActor () -> Void
  @ObservationIgnored var recoveryManagementGeneration = UUID()
  @ObservationIgnored var ownedRecoveryDiscovery: UUID?
  private(set) var saveDirectoryURL: URL?
  @ObservationIgnored var documentSaveGeneration = UUID()
  @ObservationIgnored private var saveDirectoryScoped = false
  @ObservationIgnored var documentTransferGeneration = UUID()
  @ObservationIgnored var documentTransferBusy = false
  @ObservationIgnored var movieFramesImportTask: Task<CraftDocument,Error>?
  @ObservationIgnored var movieFramesImportOperationID: UUID?
  @ObservationIgnored var pdfImportTask: Task<PDFImportAPI.Prepared,Error>?
  @ObservationIgnored var pdfImportOperationID: UUID?
  @ObservationIgnored var pdfImageDecoder: @Sendable (Data,String,PDFImageImportSettings,String?) throws -> [CraftDocument] = {data,name,settings,password in
    try PDFImages.documents(data,name:name,settings:settings,password:password,maximumPixels:4_194_304,maximumBytes:128*1024*1024)
  }
  @ObservationIgnored var pdfPageDecoder: @Sendable (Data,String,PDFImportSettings,String?) throws -> [CraftDocument] = {data,name,settings,password in
    try PDFImport.pages(data,name:name,settings:settings,password:password,maximumPixels:4_194_304,maximumBytes:128*1024*1024)
  }
  @ObservationIgnored var imageProcessorTask: Task<Data,Error>?
  @ObservationIgnored var imageProcessorOperationID: UUID?
  @ObservationIgnored var imageProcessorSourceIDs = Set<UUID>()
  @ObservationIgnored var scanCropTask: Task<ScanCropAPI.Prepared,Error>?
  @ObservationIgnored var scanCropOperationID: UUID?
  @ObservationIgnored var scanCropSourceID: UUID?
  @ObservationIgnored var contactSheetTask: Task<ContactSheet.Result,Error>?
  @ObservationIgnored var contactSheetOperationID: UUID?
  @ObservationIgnored var contactSheetSourceIDs = Set<UUID>()
  @ObservationIgnored var imageStackTask: Task<ImageStack.Result,Error>?
  @ObservationIgnored var actionBatchTask: Task<[ActionBatchResult], Error>?
  var actionBatchOperationID: UUID?
  var actionBatchSourceIDs = Set<UUID>()
  var actionBatchResults: [ActionBatchResult] = []
  @ObservationIgnored var imageStackOperationID: UUID?
  @ObservationIgnored var imageStackSourceIDs = Set<UUID>()
  @ObservationIgnored var hdrMergeTask: Task<HDRMerge.Result,Error>?
  @ObservationIgnored var hdrMergeOperationID: UUID?
  @ObservationIgnored var hdrMergeSourceIDs = Set<UUID>()
  @ObservationIgnored var photomergeTask: Task<Photomerge.Result,Error>?
  @ObservationIgnored var photomergeOperationID: UUID?
  @ObservationIgnored var photomergeSourceIDs = Set<UUID>()
  @ObservationIgnored var luts: [UUID: ColorLUT] = [:]
  @ObservationIgnored var lutCacheGeneration = UUID()
  @ObservationIgnored let documentDecoder: @Sendable (Data, Bool, String) throws -> CraftDocument
  @ObservationIgnored private let pressedMouseButtons: @MainActor () -> Int
  @ObservationIgnored private(set) var token: String?
  var generation = UUID()
  var previewBusy = false
  @ObservationIgnored var audioImportOperations: [UUID:UUID] = [:]
  @ObservationIgnored var audioPreviewWorkers: [UUID:Task<Data?,Error>] = [:]
  private(set) var shares: [Share] = []
  private(set) var endpoint: String?
  private(set) var starting = false
  var message = "Stopped. Start the API and explicitly share a document to connect a client."
  var isRunning: Bool { endpoint != nil }
  init(
    controller: CraftDocumentController,
    pressedMouseButtons: @escaping @MainActor () -> Int = { NSEvent.pressedMouseButtons },
    resourceTransport: any AdobeResourceTransport = NativeAdobeResourceTransport(),
    foregroundDetector: any ForegroundDetecting = VisionForegroundDetector(),
    documentDecoder: @escaping @Sendable (Data, Bool, String) throws -> CraftDocument = {
      try DocumentIO.decodeUpload($0, native: $1, name: $2)
    },
    applicationTerminator: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
  ) {
    self.actionJobs = AdobeActionJobs(transport: resourceTransport, detector: foregroundDetector)
    self.controller = controller
    self.pressedMouseButtons = pressedMouseButtons
    self.documentDecoder = documentDecoder
    self.applicationTerminator = applicationTerminator
  }

  func start() {
    stop()
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      message = "Could not create an authentication token."
      return
    }
    token = Data(bytes).base64EncodedString()
    let expected = generation
    starting = true
    do {
      try server.start(
        onState: { [weak self] port, error in
          guard let self, self.generation == expected else { return }
          self.starting = false
          if let port {
            self.endpoint = "http://127.0.0.1:\(port)"
            self.message = "Running on this Mac. Only shared documents are accessible."
          } else {
            self.stop()
            self.message = error ?? "Stopped."
          }
        },
        handler: { [weak self] request in
          guard let self, self.generation == expected, !Task.isCancelled else {
            return .failure(.init(status: 503, message: "Session ended."))
          }
          return await self.handle(request)
        })
    } catch {
      stop()
      message = "Could not start the local API."
    }
  }
  func stop() {
    for share in shares { cancelSharedHistory(share); cancelSharedPrint(share) }
    setDocumentTransfersEnabled(false)
    setDocumentSavesEnabled(false)
    setPrintingEnabled(false)
    setPreferenceChangesEnabled(false)
    setPhotoshopPreferenceChangesEnabled(false)
    setColorSettingsChangesEnabled(false)
    setRecoveryManagementEnabled(false)
    setRecoveryBackupsEnabled(false)
    setDocumentClosingEnabled(false)
    setRecentFilesEnabled(false)
    setSaveDirectory(nil)
    resourceJobsEnabled = false
    actionJobs.revoke()
    generation = UUID()
    token = nil
    endpoint = nil
    starting = false
    shares.removeAll()
    server.stop()
    message = "Stopped. All tokens and document shares have been revoked."
  }
  func setResourceJobsEnabled(_ enabled: Bool) {
    resourceJobsEnabled = enabled && isRunning
    if !resourceJobsEnabled { actionJobs.revoke() }
  }
  func setRecentFilesEnabled(_ enabled: Bool) {
    recentFilesGeneration = UUID()
    recentFilesEnabled = enabled && isRunning
    if !recentFilesEnabled, let id = ownedRecentOpening {
      controller.documentOpening.cancel(id); ownedRecentOpening = nil
    }
  }
  func setDocumentTransfersEnabled(_ enabled: Bool) {
    documentTransferGeneration = UUID()
    documentTransfersEnabled = enabled && isRunning
    if !documentTransfersEnabled { pdfImportTask?.cancel();movieFramesImportTask?.cancel();imageProcessorTask?.cancel();scanCropTask?.cancel();contactSheetTask?.cancel();photomergeTask?.cancel();hdrMergeTask?.cancel();imageStackTask?.cancel();videoSequenceTask?.cancel();for share in shares {cancelSharedVideoRender(share);cancelSharedSequenceExport(share);cancelSharedVariableExport(share);cancelSharedAudio(share)};luts.removeAll(); lutCacheGeneration = UUID() }
  }
  func setDocumentSavesEnabled(_ enabled: Bool) {
    documentSaveGeneration = UUID()
    documentSavesEnabled = enabled && isRunning
    if !documentSavesEnabled { actionBatchTask?.cancel() }
  }
  func setPreferenceChangesEnabled(_ enabled: Bool) {
    preferenceChangesEnabled = enabled && isRunning
  }
  func setPhotoshopPreferenceChangesEnabled(_ enabled: Bool) {
    photoshopPreferenceChangesEnabled = enabled && isRunning
  }
  func setColorSettingsChangesEnabled(_ enabled: Bool) {
    colorSettingsChangesEnabled = enabled && isRunning
  }
  func setRecoveryManagementEnabled(_ enabled: Bool) {
    recoveryManagementGeneration = UUID()
    recoveryManagementEnabled = enabled && isRunning
    if !recoveryManagementEnabled, let ownedRecoveryDiscovery {
      controller.recoveryDiscovery.cancel(ownedRecoveryDiscovery)
      self.ownedRecoveryDiscovery = nil
    }
  }
  func setRecoveryBackupsEnabled(_ enabled: Bool) {
    recoveryBackupsGeneration = UUID()
    recoveryBackupsEnabled = enabled && isRunning
  }
  func setDocumentClosingEnabled(_ enabled: Bool) {
    documentClosingGeneration = UUID()
    documentClosingEnabled = enabled && isRunning
    if !documentClosingEnabled, let ownedCloseOperation {
      controller.documentClosing.cancel(ownedCloseOperation)
    }
  }
  func setSaveDirectory(_ url: URL?) {
    documentSaveGeneration = UUID()
    if saveDirectoryScoped { saveDirectoryURL?.stopAccessingSecurityScopedResource() }
    saveDirectoryURL = isRunning ? url?.standardizedFileURL.resolvingSymlinksInPath() : nil
    saveDirectoryScoped = saveDirectoryURL?.startAccessingSecurityScopedResource() ?? false
  }
  func copyToken() {
    guard let token, isRunning else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(token, forType: .string)
    message = "Token copied. Treat it as a password; stopping the API invalidates it."
  }
  func share(_ document: CraftNSDocument) throws {
    guard isRunning, controller.documents.contains(where: { $0 === document }) else {
      throw AutomationFailure(
        status: 409, message: "Start the API and select an open document first.")
    }
    try Self.checkLimits(document.store.document)
    prune()
    guard !shares.contains(where: { $0.document === document }) else { return }
    guard shares.count < 8 else {
      throw AutomationFailure(status: 429, message: "Share up to eight documents at once.")
    }
    shares.append(Share(document: document, generation: document.store.layerPanelGeneration))
    message =
      "Shared \(document.displayName ?? "Untitled"). Clients may read and edit this document."
  }
  private func cancelSharedHistory(_ share: Share) {
    guard let store = share.document?.store,
      store.historyOperation?.authorizationID == share.id
    else { return }
    store.cancelHistory()
  }
  func revoke(_ id: UUID) {
    if imageProcessorSourceIDs.contains(id) {imageProcessorTask?.cancel()}
    if scanCropSourceID == id {scanCropTask?.cancel()}
    if contactSheetSourceIDs.contains(id) {contactSheetTask?.cancel()}
    for share in shares where share.id == id { cancelSharedHistory(share); cancelSharedPrint(share);cancelSharedVideoRender(share);cancelSharedSequenceExport(share);cancelSharedVariableExport(share);cancelSharedAudio(share) }
    shares.removeAll { $0.id == id }
  }
  func prune() {
    shares.removeAll { share in
      guard let document = share.document else { return true }
      let expired =
        !controller.documents.contains(where: { $0 === document })
        || document.store.layerPanelGeneration != share.generation
      if expired { cancelSharedHistory(share); cancelSharedPrint(share);cancelSharedVideoRender(share);cancelSharedSequenceExport(share);cancelSharedVariableExport(share);cancelSharedAudio(share) }
      return expired
    }
  }
  nonisolated static func checkLimits(_ document: CraftDocument) throws {
    guard document.width * document.height <= 4_194_304, document.layers.count <= 64,
      document.estimatedBytes <= 128 * 1024 * 1024
    else {
      throw AutomationFailure(
        status: 413,
        message:
          "API v1 supports canvases up to 4,194,304 pixels, 64 layers and 128 MiB of document data."
      )
    }
  }
  func revision(_ store: EditorStore, includeBrush:Bool=true) -> String {
    let document="\(store.printRevision):\(store.layerPanelGeneration.uuidString):\(store.revision - store.timelinePlaybackRenderCount):\(store.timelinePlaybackRevision):\(store.timelineVisible):\(store.document.activeLayerID?.uuidString ?? "none"):\(store.actionRevision):\(store.actions.revision)"
    let view=document+":\(store.videoTimelinePixelsPerSecond):\(store.videoSelectedTransitionID?.uuidString ?? "none"):\(store.videoTransitionEditorVisible):\(store.timelineAudioViewRevision)"
    return includeBrush ? view+":\(store.brushRevision):\(store.brushes.revision):\(store.skies.revision):\(store.shapes.revision):\(store.shapeRevision):\(store.pathSettingsRevision)":view
  }
  func state(_ share: Share, document: CraftNSDocument) -> [String: Any] {
    let store = document.store
    let saveFormats = document.saveFormats
    return [
      "id": share.id.uuidString, "name": document.displayName ?? "Untitled",
      "windowTitle": document.photatoWindowTitle,
      "video": store.videoState,
      "audio": TimelineAudioAPI.state(store),
      "videoSequenceCreation": videoSequenceCreationState,
      "videoRender": ["operationID":store.videoRenderID?.uuidString as Any? ?? NSNull()],
      "variables": VariablesAPI.state(store.document, exportID: store.variableExportID),
      "sequenceExport": ["operationID":store.sequenceExportID?.uuidString as Any? ?? NSNull()],
      "animation": store.animationState,
      "colorProfile": store.colorProfileState,
      "proofing": store.proofState,
      "printing": store.printState,
      "revision": revision(store),
      "brush":store.brushState,
      "sky":store.skyState,
      "peopleSelection":store.peopleState,
      "objectFinder":store.objectFinderState,
      "maskAllObjects":store.maskAllObjectsState,
      "focusArea":store.focusAreaState,
      "actions": store.actionState, "batch": actionBatchState,
      "width": store.document.width, "height": store.document.height,
      "depth": store.document.colorMode == .bitmap ? "1-bit" : store.document.depth.rawValue,
      "workingProfile": [
        "name": ColorManagement.name(store.document),
        "embedded": store.document.workingICC != nil,
        "sampleEncoding": store.document.depth == .f32 ? "linearRGB" : "profileRGB",
        "iccSHA256": store.document.workingICC.map {
          SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        } as Any? ?? NSNull(),
      ],
      "activeLayerID": store.document.activeLayerID?.uuidString as Any? ?? NSNull(),
      "selectedLayerIDs": store.clipboardLayerIDs.map(\.uuidString).sorted(),
      "mergeAvailability": [
        "down": store.canMerge(.down), "selected": store.canMerge(.selected),
        "visible": store.canMerge(.visible),
      ],
      "canUndo": !store.session.undoStack.isEmpty, "canRedo": !store.session.redoStack.isEmpty,
      "historyOperation": [
        "active": store.historyOperation != nil,
        "id": store.historyOperation?.id.uuidString as Any? ?? NSNull(),
        "direction": store.historyOperation.map { $0.redo ? "redo" : "undo" } as Any? ?? NSNull(),
        "cancellationRequested": store.historyOperation?.cancellationRequested ?? false,
      ],
      "historyStorage": store.historyStorageState,
      "isModified": document.isDocumentEdited,
      "persistenceFormat": document.persistenceFormat.rawValue,
      "saveFormats": saveFormats.map(\.rawValue),
      "saveEncodingOptions": Dictionary(uniqueKeysWithValues: DocumentIO.Format.allCases.map {
        ($0.rawValue, DocumentEncodingOptions.json(document.rememberedEncodingOptions[$0] ?? .init()))
      }),
      "effectiveSaveEncodingOptions": Dictionary(uniqueKeysWithValues: DocumentIO.Format.allCases.map {
        ($0.rawValue, DocumentEncodingOptions.json(document.effectiveEncodingOptions(
          document.rememberedEncodingOptions[$0] ?? .init(), format: $0, persistence: true)))
      }),
      "sourceSaveNeedsReview": document.sourceSaveNeedsReview,
      "canSave": documentSavesEnabled && document.fileURL != nil && !document.sourceSaveNeedsReview
        && saveFormats.contains(document.persistenceFormat) && document.canRunFileCommand
        && document.closeWorkflowID == nil,
      "canSaveAs": documentSavesEnabled && saveDirectoryURL != nil && document.canRunFileCommand
        && document.closeWorkflowID == nil,
      "hasRevertSource": document.revertSourceURL != nil,
      "fileOperationBusy": document.fileOperationBusy,
      "recovery": document.recoveryState,
      "recoverySource": document.recoverySourceState,
      "recoveryRegistration": document.recoveryRegistrationState,
      "closeOperationID": document.closeWorkflowID?.uuidString as Any? ?? NSNull(),
      "canRevert": documentTransfersEnabled && document.canRevertDocument && document.closeWorkflowID == nil,
      "selection": store.document.selection.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] } as Any? ?? NSNull(),
      "selectionHasSoftCoverage": store.document.selectionMask != nil,
      "shapes":store.shapeState,
      "paths":store.pathState,
      "frames": ["available": store.canEditFrames, "target": store.frameTarget.rawValue, "shape": store.frameShape.rawValue, "sides": store.frameSides],
      "artboards": ["available": store.canEditArtboards, "originX": store.document.artboardOrigin?.x ?? 0, "originY": store.document.artboardOrigin?.y ?? 0, "showNames": store.showArtboardNames, "showGuides": store.showArtboardGuides],
      "crop": ["available":store.canBeginCrop,"workspaceOpen":store.cropDraft != nil,"previewBusy":store.cropBusy,"previewError":store.cropError as Any? ?? NSNull()],
      "photomerge": ["operationID":photomergeOperationID?.uuidString as Any? ?? NSNull(),"source":photomergeSourceIDs.contains(share.id)],
      "imageProcessor": ["operationID":imageProcessorOperationID?.uuidString as Any? ?? NSNull(),"source":imageProcessorSourceIDs.contains(share.id)],
      "cropStraighten": ["operationID":scanCropOperationID?.uuidString as Any? ?? NSNull(),"source":scanCropSourceID == share.id],
      "contactSheet": ["operationID":contactSheetOperationID?.uuidString as Any? ?? NSNull(),"source":contactSheetSourceIDs.contains(share.id)],
      "imageStack": ["operationID":imageStackOperationID?.uuidString as Any? ?? NSNull(),"source":imageStackSourceIDs.contains(share.id)],
      "hdrMerge": ["operationID":hdrMergeOperationID?.uuidString as Any? ?? NSNull(),"source":hdrMergeSourceIDs.contains(share.id)],
      "vanishingPoint": ["available":store.canBeginVanishingPoint,"settings":store.document.vanishingPoint?.apiValue ?? NSNull(),"scene":(try? VanishingScene(store.document.vanishingPoint ?? .init(),width:store.document.width,height:store.document.height).apiValue) as Any? ?? NSNull(),"workspaceOpen":store.vanishingWorkspace != nil,"workspace":store.vanishingWorkspace?.apiState as Any? ?? NSNull()],
      "adaptiveWideAngle": ["available":store.canBeginFilterKind(.adaptiveWideAngle),"workspaceOpen":store.filterDraft?.filter.kind == .adaptiveWideAngle,"previewBusy":store.wideAngleWorkspace?.rendering ?? false,"workspace":store.wideAngleWorkspace?.apiState as Any? ?? NSNull()],
      "lensCorrection": ["available":store.canBeginFilterKind(.lensCorrection),"workspaceOpen":store.filterDraft?.filter.kind == .lensCorrection,"previewBusy":store.lensCorrectionWorkspace?.rendering ?? false,"workspace":store.lensCorrectionWorkspace?.apiState as Any? ?? NSNull()],
      "clipboard": store.clipboardAPIState,
      "documentMode": store.documentModeState,
      "inkMode": store.inkModeState,
      "classicTone":store.classicToneState,
      "proceduralRender":store.proceduralState,
      "classicDetail":["available":store.canBeginFilterKind(.radialBlur),"availableKinds":RasterFilter.Kind.allCases.filter{$0.isClassicDetail && store.canBeginFilterKind($0)}.map(\.rawValue),"workspaceOpen":store.filterDraft?.filter.kind.isClassicDetail == true,"previewBusy":store.classicDetailWorkspace?.rendering ?? false,"workspace":store.classicDetailWorkspace?.apiState as Any? ?? NSNull()],
      "otherVideo":["available":store.canBeginFilterKind(.customFilter),"workspaceOpen":store.filterDraft?.filter.kind.isOtherVideo == true,"previewBusy":store.otherVideoWorkspace?.rendering ?? false,"workspace":store.otherVideoWorkspace?.apiState as Any? ?? NSNull()],
      "render":["available":store.canBeginFilterKind(.fibers),"workspaceOpen":store.renderWorkspace != nil,"previewBusy":store.renderWorkspace?.rendering ?? false,"workspace":store.renderWorkspace?.apiState as Any? ?? NSNull()],
      "stylize":["available":store.canBeginFilterKind(.diffuse),"workspaceOpen":store.stylizeWorkspace != nil,"previewBusy":store.stylizeWorkspace?.rendering ?? false,"workspace":store.stylizeWorkspace?.apiState as Any? ?? NSNull()],
      "pixelate": ["available":store.canBeginFilterKind(.crystallize),"workspaceOpen":store.pixelateWorkspace != nil,"previewBusy":store.pixelateWorkspace?.rendering ?? false,"workspace":store.pixelateWorkspace?.apiState as Any? ?? NSNull()],
      "distortion": ["available":store.canBeginFilterKind(.wave),"workspaceOpen":store.distortionWorkspace != nil,"previewBusy":store.distortionWorkspace?.rendering ?? false,"workspace":store.distortionWorkspace?.apiState as Any? ?? NSNull()],
      "lensBlur": ["available":store.canBeginFilterKind(.lensBlur),"workspaceOpen":store.lensBlurWorkspace != nil,"previewBusy":store.lensBlurWorkspace?.rendering ?? false,"workspace":store.lensBlurWorkspace?.apiState as Any? ?? NSNull()],
      "photoDetail": ["available":store.canBeginFilterKind(.smartSharpen),"workspaceOpen":store.photoDetailWorkspace != nil,"previewBusy":store.photoDetailWorkspace?.rendering ?? false,"workspace":store.photoDetailWorkspace?.apiState as Any? ?? NSNull()],
      "filterGallery": ["available":store.canBeginFilterKind(.filterGallery),"workspaceOpen":store.filterDraft?.filter.kind == .filterGallery,"previewBusy":store.artisticGalleryWorkspace?.rendering ?? false,"workspace":store.artisticGalleryWorkspace?.apiState as Any? ?? NSNull()],
      "blurGallery": ["available":store.canBeginFilterKind(.blurGallery),"workspaceOpen":store.filterDraft?.filter.kind == .blurGallery,"previewBusy":store.blurGalleryWorkspace?.rendering ?? false],
      "perspectiveWarp": ["available":store.canBeginFilterKind(.perspectiveWarp),"workspaceOpen":store.filterDraft?.filter.kind == .perspectiveWarp,"previewBusy":store.perspectiveWorkspace?.rendering ?? false],
      "puppetWarp": ["available":store.canBeginFilterKind(.puppetWarp),"workspaceOpen":store.filterDraft?.filter.kind == .puppetWarp,"previewBusy":store.puppetWorkspace?.rendering ?? false],
      "warp": ["available":store.canBeginWarp,"previewOpen":store.warpDraft != nil,"previewBusy":store.warpDraft?.rendering ?? false],
      "photoAlign": ["available":store.canBeginPhotoAlign,"previewOpen":store.photoAlignDraft != nil,"previewBusy":store.photoAlignDraft?.rendering ?? false],
      "photoBlend": ["available":store.canBeginPhotoBlend,"previewOpen":store.photoBlendDraft != nil,"previewBusy":store.photoBlendDraft?.rendering ?? false],
      "selectionTools":store.selectionToolsState,
      "adjustmentBrush":store.adjustmentBrushState,
      "paintingTools":store.paintingState,
      "regionRetouch": ["available":store.canBeginRegionRetouch,"hasSelection":store.document.selection != nil,"previewOpen":store.regionRetouchDraft != nil,"previewBusy":store.regionRetouchBusy,"previewError":store.regionRetouchError as Any? ?? NSNull()],
      "contentAwareScale": ["available":store.canBeginContentAwareScale,"transformOpen":store.transformDraft?.contentAware == true,"previewBusy":store.contentAwareScaleBusy,"previewError":store.contentAwareScaleError as Any? ?? NSNull()],
      "contentAwareFill": ["available":store.canBeginContentAwareFill,"workspaceOpen":store.contentAwareDraft != nil],
      "selectionRefinement": ["available": store.canBeginSelectMask, "workspaceOpen": store.selectMaskDraft != nil && store.selectMaskDraft?.isFocus != true],
      "subjectDetection": ["canSelectSubject": store.canDetectSubject(),
        "canRemoveBackground": store.canDetectSubject(removeBackground: true),
        "sampleAllLayers": store.subjectSampleAllLayers],
      "channelTarget": store.document.inkMode != nil ? store.effectiveInkTargets.map { store.inkChannelName($0) }.joined(separator: ", ") : store.document.colorMode.isRestricted ? store.document.colorMode.componentNames[0] : store.usesModeChannels ? (store.modeComponentTargets.isEmpty ? store.document.colorMode.title : store.modeComponentTargets.sorted().map { store.document.colorMode.componentNames[$0] }.joined(separator: ", ")) : store.componentTarget.title,
      "alphaChannelTarget": store.alphaEditingID?.uuidString ?? (store.document.quickMask == nil ? "RGB":"quickMask"),
      "alphaChannelOverlay": store.alphaOverlay,
      "channels": (store.document.alphaChannels ?? []).map { ["id":$0.id.uuidString,"name":$0.name,"opacity":$0.options.opacity,"indicates":$0.options.indicates.rawValue,"color":[$0.options.color.r,$0.options.color.g,$0.options.color.b]] as [String:Any] },
      "quickMask": store.document.quickMask.map { ["id":$0.id.uuidString,"opacity":$0.options.opacity,"indicates":$0.options.indicates.rawValue,"color":[$0.options.color.r,$0.options.color.g,$0.options.color.b]] as [String:Any] } ?? NSNull(),
      "channelView": [
        "preview": store.document.inkMode != nil ? store.document.inkChannelTargets.filter { store.visibleInkTargets.contains($0) }.map { store.inkChannelName($0) }.joined(separator: ", ") : store.document.colorMode.isRestricted ? store.document.colorMode.componentNames[0] : store.usesModeChannels ? (store.modeVisibleComponents.count == 1 ? store.document.colorMode.componentNames[store.modeVisibleComponents.first!] : store.document.colorMode.title) : store.channelView.preview.title,
        "visible": store.document.inkMode != nil ? store.document.inkChannelTargets.filter { store.visibleInkTargets.contains($0) }.map { store.inkChannelName($0) } : store.document.colorMode.isRestricted ? store.document.colorMode.componentNames : store.usesModeChannels ? store.modeVisibleComponents.sorted().map { store.document.colorMode.componentNames[$0] } : RGBChannelPreview.allCases.filter {
          $0 != .composite && store.channelView.isVisible($0)
        }.map(\.title),
        "componentEditing": store.editingComponent,
      ],
      "layers": store.document.layers.map { layer in
        [
          "id": layer.id.uuidString, "name": layer.name, "opacity": layer.opacity,
          "visible": layer.visible, "x": layer.x, "y": layer.y,
          "transform": ["a": layer.coordinateTransform.a, "b": layer.coordinateTransform.b,
            "c": layer.coordinateTransform.c, "d": layer.coordinateTransform.d,
            "tx": layer.coordinateTransform.tx, "ty": layer.coordinateTransform.ty],
          "kind": layer.kindLabel, "smartObject": layer.smartObject?.apiState ?? NSNull(),
          "style": layer.style?.apiObject ?? NSNull(),
          "colorLookup": { () -> Any in if case .adjustment(.colorLookup(let a)) = layer.content { return a.apiObject }; return NSNull() }(),
          "classicAdjustment": { () -> Any in if case .adjustment(.classic(let a)) = layer.content { return a.apiObject }; return NSNull() }(),
          "smartFilters": layer.smartFilters?.apiState ?? NSNull(),
          "shape":layer.shapeAPIState,
          "shapeTransform":layer.shapeTransformAPIState,
          "frame": layer.frame?.apiState ?? NSNull(),
          "artboard": layer.artboard?.apiState ?? NSNull(),
          "warp": layer.warp?.apiState ?? NSNull(),
          "text": { () -> Any in if case .text(let t) = layer.content { return t.promoted(dpi: store.document.pixelsPerInch).apiType }; return NSNull() }(),
          "hasMask": layer.mask != nil,
          "maskEnabled": layer.mask != nil && layer.effectiveMaskProperties.enabled,
          "maskDensity": layer.effectiveMaskProperties.density,
          "maskFeather": layer.effectiveMaskProperties.feather,
          "protection": layer.protection.apiNames,
          "effectiveProtection": store.document.effectiveProtection(layer.id).apiNames,
          "imageLocked": store.document.isImageLocked(layer.id),
          "positionLocked": store.document.isPositionLocked(layer.id),
          "transparencyLocked": store.document.isTransparencyLocked(layer.id),
        ] as [String: Any]
      },
    ]
  }
  func preflight(_ document: CraftNSDocument) throws {
    let store = document.store
    // NSEvent reports buttons across the whole Mac. A click in another app or document
    // cannot be an in-progress pointer edit of this shared document. Gesture/draft guards
    // below continue to protect edits even after its window loses focus.
    let documentPointerActive =
      pressedMouseButtons() != 0 && NSApp?.isActive == true
      && document.windowForSheet?.isKeyWindow == true
    guard document.closeWorkflowID == nil, document.recoverySourceStatus != .checking,
      !document.fileOperationBusy, !document.recoveryWriteBusy, document.copyPanel == nil,
      !store.geometryBusy, !store.aiBusy, !store.hasToneDraft, store.transformDraft == nil,
      store.numericEditor == nil, store.layerNameDraft == nil, store.layerProtectionDraft == nil, !store.coalescingChanges,
      store.pathGesture == nil, store.geometrySheet == nil, !store.showFeatherSelection,
      store.patternNameDraft == nil, store.gradientNameDraft == nil, !store.showAI,
      !store.showImagePlayground, store.error == nil, document.windowForSheet?.attachedSheet == nil,
      NSApp?.modalWindow == nil, !documentPointerActive
    else {
      throw AutomationFailure(
        status: 409,
        message: "Finish or cancel the current desktop interaction before editing through the API.")
    }
    try Self.checkLimits(store.document)
  }
  func handle(_ request: AutomationRequest) async -> AutomationResponse {
    if request.method == "GET", let asset = AutomationBrowser.asset(request.path) { return asset }
    guard let token, isRunning, request.headers["authorization"] == "Bearer \(token)" else {
      if request.path.hasPrefix("/v2/") {
        return AdobeAPIError(
          status: 401, code: "401013", message: "A current local bearer token is required."
        ).response
      }
      return .failure(.init(status: 401, message: "A current bearer token is required."))
    }
    do {
      guard !Task.isCancelled else {
        throw AutomationFailure(status: 503, message: "Request cancelled.")
      }
      prune()
      if let response = try handleRecoveryPreferences(request) { return response }
      if let response = try handlePhotoshopFilePreferences(request) { return response }
      if let response = try handleColorSettings(request) { return response }
      if let response = try await handleRecoveryDiscovery(request) { return response }
      if let response = try await handleRecoveryBackups(request) { return response }
      if let response = try await handleRecoverySalvage(request) { return response }
      if let response = try handleDocumentOpening(request) { return response }
      if let response = try handleRecentDocuments(request) { return response }
      if let response = try handleDocumentClosing(request) { return response }
      if let response = try handleActionJobRequest(request) { return response }
      if let response = try await handleLUTTransfer(request) { return response }
      if let response = try cancelMovieFramesImport(request) {return response}
      if let response = try await handlePDFImport(request) {return response}
      if let response = try await handleDocumentTransfer(request) { return response }
      if request.method == "GET", request.path == "/v1/capabilities" {
        var result = Self.capabilities
        result["printingEnabled"] = printingEnabled
        result["printers"] = printingEnabled ? NSPrinter.printerNames : []
        result["photomergeState"] = ["open":controller.photomergeWorkspace != nil,"loading":controller.photomergeWorkspace?.loading ?? false,"rendering":controller.photomergeWorkspace?.rendering ?? false,"creatingFromAPI":photomergeOperationID != nil]
        result["movieFramesImportState"] = ["open":controller.movieFramesWorkspace != nil,"loading":controller.movieFramesWorkspace?.loading ?? false,"importing":controller.movieFramesWorkspace?.busy ?? false,"uploadOperationID":movieFramesImportOperationID?.uuidString as Any? ?? NSNull()]
        result["pdfImportState"] = pdfImportState
        result["imageProcessorState"] = ["exportingFromAPI":imageProcessorOperationID != nil]
        result["cropStraightenState"] = ["busy":controller.scanCropOperationID != nil,"creatingFromAPI":scanCropOperationID != nil]
        result["contactSheetState"] = ["open":controller.contactSheetWorkspace != nil,"loading":controller.contactSheetWorkspace?.loading ?? false,"rendering":controller.contactSheetWorkspace?.rendering ?? false,"creatingFromAPI":contactSheetOperationID != nil,"sourceCount":controller.contactSheetWorkspace?.sources.count ?? 0,"ready":controller.contactSheetWorkspace?.ready ?? false]
        result["imageStackState"] = ["open":controller.imageStackWorkspace != nil,"loading":controller.imageStackWorkspace?.loading ?? false,"rendering":controller.imageStackWorkspace?.rendering ?? false,"creatingFromAPI":imageStackOperationID != nil,"sourceCount":controller.imageStackWorkspace?.sources.count ?? 0,"ready":controller.imageStackWorkspace?.ready ?? false]
        result["hdrMergeState"] = ["open":controller.hdrMergeWorkspace != nil,"loading":controller.hdrMergeWorkspace?.loading ?? false,"rendering":controller.hdrMergeWorkspace?.rendering ?? false,"creatingFromAPI":hdrMergeOperationID != nil,"previewExposure":controller.hdrMergeWorkspace?.previewExposure ?? 0,"sourceCount":controller.hdrMergeWorkspace?.sources.count ?? 0,"ready":controller.hdrMergeWorkspace?.ready ?? false]
        result["resourceJobsEnabled"] = resourceJobsEnabled
        result["documentTransfersEnabled"] = documentTransfersEnabled
        result["documentSavesEnabled"] = documentSavesEnabled
        result["saveAsFolderSelected"] = saveDirectoryURL != nil
        result["preferenceChangesEnabled"] = preferenceChangesEnabled
        result["photoshopPreferenceChangesEnabled"] = photoshopPreferenceChangesEnabled
        result["colorSettingsChangesEnabled"] = colorSettingsChangesEnabled
        result["recentFilesEnabled"] = recentFilesEnabled
        result["recoveryBackupsEnabled"] = recoveryBackupsEnabled
        result["documentClosingEnabled"] = documentClosingEnabled
        return .json(result)
      }
      if request.method == "GET", request.path == "/v1/documents" {
        return .json([
          "documents": shares.compactMap { share in
            share.document.map { state(share, document: $0) }
          }
        ])
      }
      let parts = request.path.split(separator: "/", omittingEmptySubsequences: false)
      guard parts.count == 4 || parts.count == 5 || parts.count == 7, parts[0] == "", parts[1] == "v1",
        parts[2] == "documents",
        let id = UUID(uuidString: String(parts[3])),
        let share = shares.first(where: { $0.id == id }),
        let document = share.document
      else { throw AutomationFailure(status: 404, message: "Shared document or route not found.") }
      let store = document.store
      if request.method == "POST", parts.count == 5, parts[4] == "audio" { return try await importTimelineAudio(request,share:share,document:document) }
      if request.method == "GET", parts.count == 5, parts[4] == "audio.wav" { return try await timelineAudioPreview(share,document:document) }
      if request.method == "GET", parts.count == 4 {
        return .json(state(share, document: document))
      }
      if request.method == "GET", parts.count == 7, parts[4] == "smart-objects", parts[6] == "source" {
        guard let layerID = UUID(uuidString: String(parts[5])),
          let source = store.document.layers.first(where: { $0.id == layerID })?.smartObject else {
          throw AutomationFailure(status: 404, message: "Embedded Smart Object not found.")
        }
        return .init(status: 200, contentType: source.mediaType, body: source.data)
      }
      if request.method == "GET", parts.count == 5, parts[4] == "print.pdf" { return try await printPDF(share, document: document) }
      if request.method == "GET", parts.count == 5,
        parts[4] == "preview.png" || parts[4] == "channel-preview.png" || parts[4] == "proof-preview.png" || parts[4] == "onion-preview.png"
      {
        try Self.checkLimits(store.document)
        guard !previewBusy else {
          throw AutomationFailure(
            status: 429, message: "A preview is already rendering. Retry shortly.")
        }
        previewBusy = true
        defer { previewBusy = false }
        let snapshot = store.document
        let channelView = parts[4] == "channel-preview.png" ? store.channelView : RGBChannelView()
        let modeVisibility = parts[4] == "channel-preview.png" && store.usesModeChannels ? store.modeComponentVisibility : nil
        let inkVisibility = parts[4] == "channel-preview.png" && store.document.inkMode != nil ? store.effectiveInkVisibility : nil
        let auxiliary = parts[4] == "channel-preview.png" ? store.editingChannel:nil
        let overlay = auxiliary == .quickMask || store.alphaOverlay
        let onion = parts[4] == "onion-preview.png"
        let proof = parts[4] == "proof-preview.png" ? store.proofSettings : nil
        let expectedRevision = revision(store)
        let expectedGeneration = generation
        let worker = Task.detached(priority: .utility) {
          try Self.png(snapshot, onionSkin:onion, proof: proof, channelView: channelView,auxiliary:auxiliary,overlay:overlay,modeVisibility:modeVisibility,inkVisibility:inkVisibility)
        }
        let bytes = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        prune()
        guard !Task.isCancelled, generation == expectedGeneration,
          revision(store) == expectedRevision,
          shares.contains(where: { $0.id == id })
        else {
          throw AutomationFailure(
            status: 409, message: "Document changed or sharing ended during rendering.")
        }
        return .init(status: 200, contentType: "image/png", body: bytes)
      }
      guard request.method == "POST", parts.count == 5, parts[4] == "commands" else {
        throw AutomationFailure(status: 404, message: "Route not found.")
      }
      guard
        request.headers["content-type"]?.lowercased().split(separator: ";").first
          == "application/json"
      else {
        throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
      }
      let command = try AutomationCommand(data: request.body)
      guard command.revision == revision(store) else {
        throw AutomationFailure(
          status: 409, message: "Stale revision. Refresh the document before retrying.")
      }
      if command.name == "audio.import.cancel" {
        let operation=try command.actionUUID("operationID")
        guard store.timelineAudioImportID==operation else{throw AutomationFailure(status:409,message:"That audio import is no longer active.")}
        store.geometryTask?.cancel();return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "history.cancel" {
        guard case .string(let rawID) = command.parameters["operationID"],
          let operationID = UUID(uuidString: rawID)
        else { throw AutomationFailure(status: 400, message: "operationID must be a UUID.") }
        guard store.historyOperation?.id == operationID else {
          throw AutomationFailure(
            status: 409, message: "That history operation is no longer active.")
        }
        store.cancelHistory()
        return .json(state(share, document: document))
      }
      if command.name == "document.photomerge.cancel" {
        guard let operationID = UUID(uuidString:try command.string("operationID")),photomergeOperationID == operationID,photomergeSourceIDs.contains(id) else { throw AutomationFailure(status:409,message:"That panorama operation is no longer active for this source.") }
        photomergeTask?.cancel();return .json(["operationID":operationID.uuidString,"cancellationRequested":true])
      }
      if command.name == "document.imageProcessor.cancel" {
        let operation = try command.actionUUID("operationID")
        guard imageProcessorOperationID == operation,imageProcessorSourceIDs.contains(id) else {throw AutomationFailure(status:409,message:"That Image Processor operation is no longer active for this source.")}
        imageProcessorTask?.cancel();return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "document.cropStraighten.cancel" {
        let operation = try command.actionUUID("operationID")
        guard scanCropOperationID == operation,scanCropSourceID == id else {throw AutomationFailure(status:409,message:"That scan operation is no longer active for this source.")}
        scanCropTask?.cancel();return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "document.contactSheet.cancel" {
        guard let operationID = UUID(uuidString:try command.string("operationID")),contactSheetOperationID == operationID,contactSheetSourceIDs.contains(id) else {throw AutomationFailure(status:409,message:"That contact sheet operation is no longer active for this source.")}
        contactSheetTask?.cancel();return .json(["operationID":operationID.uuidString,"cancellationRequested":true])
      }
      if command.name == "document.imageStack.cancel" {
        guard let operationID = UUID(uuidString:try command.string("operationID")),imageStackOperationID == operationID,imageStackSourceIDs.contains(id) else { throw AutomationFailure(status:409,message:"That image stack operation is no longer active for this source.") }
        imageStackTask?.cancel();return .json(["operationID":operationID.uuidString,"cancellationRequested":true])
      }
      if command.name == "document.hdrMerge.cancel" {
        guard let operationID = UUID(uuidString:try command.string("operationID")),hdrMergeOperationID == operationID,hdrMergeSourceIDs.contains(id) else { throw AutomationFailure(status:409,message:"That HDR merge operation is no longer active for this source.") }
        hdrMergeTask?.cancel();return .json(["operationID":operationID.uuidString,"cancellationRequested":true])
      }
      if command.name == "actions.batch.cancel" {
        let operationID = try command.actionUUID("operationID")
        guard actionBatchOperationID == operationID, actionBatchSourceIDs.contains(id) else { throw AutomationFailure(status:409,message:"No matching batch operation for this source.") }
        actionBatchTask?.cancel(); return .json(["operationID":operationID.uuidString,"cancellationRequested":true])
      }
      if command.name == "video.sequence.cancel" {
        let operation = try command.actionUUID("operationID")
        guard videoSequenceOperationID == operation, videoSequenceSourceIDs.contains(id) else { throw AutomationFailure(status:409,message:"No matching video sequence creation is active.") }
        videoSequenceTask?.cancel();return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "video.place.cancel" {
        let operation=try command.actionUUID("operationID")
        guard store.moviePlacementID==operation else{throw AutomationFailure(status:409,message:"No matching video placement is active.")}
        store.geometryTask?.cancel();return .json(["cancelled":true,"operationID":operation.uuidString])
      }
      if command.name == "video.render.cancel" {
        let operation = try command.actionUUID("operationID")
        guard store.videoRenderID == operation else { throw AutomationFailure(status:409,message:"No matching video render is active.") }
        store.videoRenderWorker?.cancel();return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "variables.export.cancel" {
        let operation = try command.actionUUID("operationID")
        guard store.variableExportID == operation else { throw AutomationFailure(status: 409, message: "No matching data-set export is active.") }
        store.variableExportWorker?.cancel(); return .json(["operationID": operation.uuidString, "cancellationRequested": true])
      }
      if command.name == "sequence.export.cancel" {
        let operation = try command.actionUUID("operationID")
        guard store.sequenceExportID == operation else { throw AutomationFailure(status:409,message:"No matching sequence export is active.") }
        store.sequenceExportWorker?.cancel();return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "animation.export.cancel" {
        let operation = try command.actionUUID("operationID")
        guard store.animationExportID == operation else { throw AutomationFailure(status:409,message:"No matching animation export is active.") }
        store.animationExportWorker?.cancel()
        return .json(["operationID":operation.uuidString,"cancellationRequested":true])
      }
      if command.name == "print.cancel" { return try executePrint(command, share: share, document: document) }
      try preflight(document)
      if command.name == "video.view" { try command.applyVideoView(to:store);return .json(state(share,document:document)) }
      if command.name == "animation.view" { try command.applyAnimationView(to: store); return .json(state(share, document: document)) }
      guard store.timelineTask == nil else { throw AutomationFailure(status:409,message:"Stop animation playback before editing through the API.") }
      if command.name == "video.sequence" { return try await createVideoSequence(command,anchorID:id) }
      if command.name == "audio.edit" {
        guard store.timelineTask==nil else{throw AutomationFailure(status:409,message:"Stop playback before editing audio through the API.")}
        let native=try command.timelineAudioCommand()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){_ in native}
        return .json(state(share,document:document))
      }
      if command.name == "audio.view" { try command.applyAudioView(store);return .json(state(share,document:document)) }
      if TimelineWorkspaceAPI.commands.contains(command.name) {
        let native=try command.timelineWorkspaceCommand(in:store.document)
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){_ in native}
        return .json(state(share,document:document))
      }
      if command.name == "video.edit" {
        let native = try command.videoCommand()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { _ in native }
        if case .video(.create)=native {store.timelineVisible=true}
        return .json(state(share,document:document))
      }
      if command.name == VideoKeyframeAPI.name {
        guard store.canUseTimeline else{throw AutomationFailure(status:409,message:"Finish the current Timeline edit.")}
        let native=try command.videoKeyframeCommand(in:store.document)
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){_ in native}
        return .json(state(share,document:document))
      }
      if command.name == "video.place" {
        try await placeMovie(command,document:document,shareID:id)
        return .json(state(share,document:document))
      }
      if command.name == "video.render" { return try await exportVideo(command,document:document,shareID:id) }
      if command.name == "variables.preview" { return try await previewVariableData(command, document: document, shareID: id) }
      if command.name == "variables.export" { return try await exportVariableData(command, document: document, shareID: id) }
      if VariablesAPI.commands.contains(command.name) {
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { source in try command.variableCommand(in: source) }
        return .json(state(share, document: document))
      }
      if command.name == "sequence.export" { return try await exportImageSequence(command,document:document,shareID:id) }
      if command.name == "animation.export" { return try await exportAnimation(command, document: document, shareID: id) }
      if command.name == "animation.edit" {
        guard store.canUseTimeline else { throw AutomationFailure(status:409,message:"Finish the current Timeline interaction.") }
        let native = try command.animationCommand()
        store.stopTimelinePlayback(render:false)
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { _ in native }
        return .json(state(share, document: document))
      }
      if PrintAPI.commands.contains(command.name) { return try executePrint(command, share: share, document: document) }
      if ClipboardAPI.commands.contains(command.name) { return try await executeClipboard(command, document: document, share: share) }
      if command.name == "tone.statistics" {
        let snapshot=store.document,layer=try command.parameters["layerID"].map{_ in try command.actionUUID("layerID")},selected=try command.pathFlag("useSelection",false)
        if let layer,!snapshot.layers.contains(where:{$0.id==layer}) {throw AutomationFailure(status:404,message:"Statistics layer not found.")}
        guard !previewBusy else{throw AutomationFailure(status:429,message:"A preview or statistics operation is already running.")}
        previewBusy=true;defer{previewBusy=false};let expectedGeneration=generation
        let worker=Task.detached(priority:.userInitiated){try ClassicToneInput.statistics(in:snapshot,layerID:layer,useSelection:selected)}
        let stats=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
        prune()
        guard !Task.isCancelled,generation==expectedGeneration,shares.contains(where:{$0.id==id}),command.revision == revision(store) else{throw AutomationFailure(status:409,message:"The statistics source changed or sharing ended. Refresh and retry.")}
        return .json(["statistics":BrushAPI.json(stats),"revision":revision(store),"sourceDepth":snapshot.depth.rawValue])
      }
      if command.name == "ink.channel.read" {
        let (target, plane, offset) = try command.inkChannelPage(in: store.document)
        let count = try command.parameters["count"].map { _ in try command.integer("count", range: 1...4096) } ?? min(4096, plane.count - offset)
        guard count <= plane.count - offset else { throw AutomationFailure(status: 400, message: "Ink read exceeds its channel.") }
        return .json(["target": target.key, "offset": offset, "values": (offset..<(offset + count)).map { plane.value(at: $0) }, "width": plane.width, "height": plane.height, "depth": store.document.bitsPerChannel, "revision": revision(store)])
      }
      if InkChannelAPI.edits.contains(command.name) {
        guard store.canEditInkChannels else { throw AutomationFailure(status: 422, message: "Select an ink channel before editing ink data.") }
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { source in try command.inkChannelCommand(in: source) }
        return .json(state(share, document: document))
      }
      if ProofAPI.commands.contains(command.name) {
        if command.name == "proof.configure" { try store.setProof(command.proofSettings(base: store.proofSettings, document: store.document, colorSettings: controller.colorSettings.value)) }
        return .json(["proofing": store.proofState, "revision": revision(store)])
      }
      if command.name == "ink.settings.read" { return .json(try inkSettings(document)) }
      if InkModeAPI.edits.contains(command.name) {
        let request = try command.inkModeRequest(in: store.document)
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { original in try request.command(in: original) }
        return .json(state(share, document: document))
      }
      if command.name == "indexed.colorTable.read" {
        let (raster, _) = try command.indexedPage(in: store.document)
        return .json(["colors": BrushAPI.json(raster.palette), "transparentIndex": raster.transparentIndex ?? -1,
          "actBase64": try ColorTableFile(colors: raster.palette, transparentIndex: raster.transparentIndex).encoded().base64EncodedString(), "revision": revision(store)])
      }
      if command.name == "indexed.indices.read" {
        let (raster, offset) = try command.indexedPage(in: store.document)
        let count = try command.parameters["count"].map { _ in try command.integer("count", range: 1...4096) } ?? min(4096, raster.indices.count - offset)
        guard count <= raster.indices.count - offset else { throw AutomationFailure(status: 400, message: "Index read exceeds the pixel range.") }
        return .json(["values": Array(raster.indices[offset..<offset + count]), "offset": offset, "width": raster.width, "height": raster.height, "revision": revision(store)])
      }
      if ["document.convertIndexed", "document.convertBitmap", "indexed.colorTable.write"].contains(command.name) {
        try await executeRestrictedMode(command, document: document, shareID: id)
        return .json(state(share, document: document))
      }
      if command.name == "mode.channel.read" {
        let (layerID, native, component, offset) = try command.modeChannelPage(in: store.document)
        let count = try command.parameters["count"].map { _ in try command.integer("count", range: 1...4096) } ?? min(4096, native.width * native.height - offset)
        guard count <= native.width * native.height - offset else { throw AutomationFailure(status: 400, message: "Channel read exceeds the sample range.") }
        return .json(["layerID": layerID.uuidString, "component": component, "offset": offset, "values": (offset..<(offset + count)).map { native.value(component: component, index: $0) }, "width": native.width, "height": native.height, "revision": revision(store)])
      }
      if command.name == "document.profile.read" {
        return .json(["profileBase64": try ColorProfileInput.effectiveProfile(store.document).base64EncodedString(),
          "name": ColorProfileInput.name(store.document), "untagged": store.document.profileIsUntagged == true, "revision": revision(store)])
      }
      if ["document.assignProfile", "document.convertProfile"].contains(command.name) || command.name == "indexed.indices.write" || command.name == "document.convertMode" || command.name == "mode.channel.write" || command.name == "mode.channel.edit" {
        let settings = controller.colorSettings.value
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision, allowModeComponents: command.name == "mode.channel.edit") { original in
          guard let native = try command.nativeCommand(document: original, colorSettings: settings) else { throw AutomationFailure(status: 422, message: "Unsupported color mode operation.") }; return native
        }
        return .json(state(share, document: document))
      }
      if command.name == "tone.apply" {
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) {original in
          try ClassicToneInput.command(command.classicToneRequest(original),in:original)
        }
        return .json(state(share,document:document))
      }
      if ProceduralAPI.kind(command.name) != nil {
        let selected=store.selectedVectorPath
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision,allowPathTarget:true) {original in
          .proceduralRender(try command.proceduralRequest(original,selected:selected))
        }
        return .json(state(share,document:document))
      }
      if command.name == "layer.maskAllObjects" {
        let layerID = try command.actionUUID("layerID"), detector = store.allObjectsDetector
        guard store.document.layers.contains(where: { $0.id == layerID }) else { throw AutomationFailure(status:404,message:"Layer not found.") }
        let existing = Set(store.document.layers.map(\.id))
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in
          try await MaskAllObjectsInput.command(document:original,layerID:layerID,detector:detector)
        }
        var result = state(share,document:document)
        result["createdGroupIDs"] = store.document.layers.filter { !existing.contains($0.id) }.map { $0.id.uuidString }
        return .json(result)
      }
      if ["text.layout","text.create","text.set","text.glyph"].contains(command.name){
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision,allowPathTarget:command.name=="text.layout"){original in guard let native=try command.nativeCommand(document:original) else{throw AutomationFailure(status:422,message:"Unsupported type command.")};return native}
        return .json(state(share,document:document))
      }
      if command.name == "font.inspect"{return .json(try inspectFont(command,store:store))}
      if command.name == "path.configure" {try store.configurePath(command);return .json(state(share,document:document))}
      if PathAPI.commands.contains(command.name) {
        let selected=store.selectedVectorPath,brush=store.brush
        let vectorMaskTarget:Bool;if case .vectorMask=store.pathTarget{vectorMaskTarget=true}else{vectorMaskTarget=false}
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision,allowPathTarget:true){original in try command.pathCommand(original,selected:selected,brush:brush,selectedIsVectorMask:vectorMaskTarget)}
        if ["path.draw","path.trace"].contains(command.name),let path=store.document.paths?.first(where: \.isWorkPath){store.selectPath(.saved(path.id))}
        return .json(state(share,document:document))
      }
      if command.name == "shape.configure" {try store.configureShape(command);return .json(state(share,document:document))}
      if command.name == "shape.library" {return .json(try manageShapes(command,store:store))}
      if command.name == "shape.edit" {
        let patterns=store.patterns.items
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){original in try command.shapeCommand(original,patterns:patterns)}
        return .json(state(share,document:document))
      }
      if command.name == "frame.place" {
        try await executeSmartObject(command, document: document, shareID: id)
        return .json(state(share, document: document))
      }
      if command.name == "frame.edit" {
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { original in try command.frameCommand(original) }
        return .json(state(share, document: document))
      }
      if command.name == "artboard.export" { return try await exportArtboard(command, document: document, shareID: id) }
      if command.name == "artboard.edit" {
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { original in try command.artboardCommand(original) }
        return .json(state(share, document: document))
      }
      if command.name == "actions.batch" { return try await executeActionBatch(command, anchorID:id) }
      if command.name.hasPrefix("brush.") { return .json(try await manageBrushes(command,store:store,shareID:id)) }
      if command.name == "sky.library" {return .json(try await manageSkies(command,store:store,shareID:id))}
      if command.name == "selection.sky" {
        guard store.canSelectSky else{throw AutomationFailure(status:422,message:"Select an available RGB document target.")}
        let layerID=try command.parameters["layerID"].map{_ in try command.actionUUID("layerID")} ?? store.activeLayer?.id
        let all=try command.adjustmentBrushFlag("sampleAllLayers",true),mode=try command.selectionMode(.replace)
        let settings=try SkyAPI.decode(SkySelectionSettings.self,command.parameters["settings"],schema:SkyAPI.selection,default:.init())
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){original in try SkyReplacementInput.selection(original,layerID:layerID,allLayers:all,settings:settings,mode:mode)}
        return .json(state(share,document:document))
      }
      if command.name == "sky.replace" {
        guard store.canReplaceSky else{throw AutomationFailure(status:422,message:"Sky Replacement requires an RGB document up to8,388,608 pixels.")}
        guard (command.parameters["skyID"] != nil) != (command.parameters["sourceLayerID"] != nil) else{throw AutomationFailure(status:400,message:"Specify exactly one skyID or sourceLayerID.")}
        let preset=try command.parameters["skyID"].map{_ in try store.skies.preset(command.actionUUID("skyID"))}
        let sourceID=try command.parameters["sourceLayerID"].map{_ in try command.actionUUID("sourceLayerID")}
        let settings=try SkyAPI.decode(SkyReplacementSettings.self,command.parameters["settings"],schema:SkyAPI.settings,default:.init()),strokes=try command.skyStrokes(),useSelection=try command.adjustmentBrushFlag("useSelection",false)
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){original in
          let source=try preset?.document() ?? SkyWorkspace.sourceLayer(sourceID!,in:original),input=try SkyReplacementInput.prepare(original)
          let initial:SelectionMask?
          if useSelection{guard let mask=try original.coverageSelection() else{throw CraftError.invalid("Create a selection before using it as the sky mask.")};initial=mask}else{initial=nil}
          return .skyReplacement(try input.edit(sky:source,name:preset?.name ?? source.name,settings:settings,strokes:strokes,detected:initial).edit)
        }
        return .json(state(share,document:document))
      }
      if PeopleAPI.commands.contains(command.name) {return .json(try await peopleCommand(command,document:document,share:share))}
      if ObjectFinderAPI.commands.contains(command.name) {return .json(try await objectFinderCommand(command,document:document,share:share))}
      if command.name == "selection.configure" {try configureSelectionTools(command,store:store);return .json(state(share,document:document))}
      if ["selection.quick","selection.object","selection.brush"].contains(command.name) {
        guard store.canUseSelectionTools else{throw AutomationFailure(status:422,message:"Select an available RGB document target for selection tools.")}
        let request=try command.selectionToolRequest(store:store),detector=store.objectDetector
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) {original in try await SelectionToolPreparation.command(request,in:original,detector:detector)}
        return .json(state(share,document:document))
      }
      if command.name == "adjustmentBrush.configure" {
        try configureAdjustmentBrush(command,store:store);return .json(state(share,document:document))
      }
      if command.name == "adjustmentBrush.stroke" || command.name == "adjustmentBrush.object" {
        let object=command.name == "adjustmentBrush.object",request=try command.adjustmentBrushRequest(store:store,object:object),detector=store.objectDetector
        let point=object ? try PathPoint(command.number("x",range:0...1_000_000),command.number("y",range:0...1_000_000)):PathPoint(0,0)
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in
          if object{return try await AdjustmentBrushPreparation.object(request,at:point,in:original,detector:detector)}
          return .adjustmentBrush(request)
        }
        return .json(state(share,document:document))
      }
      if command.name == "adjustmentBrush.edit" {
        let operation=try command.string("operation")
        if operation=="new" {
          guard command.parameters.count==1 else{throw AutomationFailure(status:400,message:"New takes no other parameters.")}
          store.newAdjustmentBrush();return .json(state(share,document:document))
        }
        guard ["replace","invert","mask"].contains(operation),let target=try command.parameters["layerID"].map({_ in try command.actionUUID("layerID")}) ?? store.adjustmentBrushLayer?.id,
          let layer=store.document.layers.first(where:{$0.id==target}),case .adjustment(let old)=layer.content,layer.mask != nil else {throw AutomationFailure(status:400,message:"Choose an existing masked adjustment and valid operation.")}
        let edit:Command
        let extra=Set(command.parameters.keys).subtracting(["operation","layerID"])
        if operation=="mask" {
          guard !extra.isEmpty,extra.isSubset(of:["density","feather"]) else{throw AutomationFailure(status:400,message:"Mask takes density and/or feather.")}
          var mask=layer.effectiveMaskProperties
          if command.parameters["density"] != nil {mask.density=Float(try command.number("density",range:0...1))}
          if command.parameters["feather"] != nil {mask.feather=try command.number("feather",range:0...100)}
          edit = .maskProperties(target,mask)
        } else if operation=="invert" {
          guard extra.isEmpty else{throw AutomationFailure(status:400,message:"Invert takes only a target layer.")};edit = .invertMask(target)
        } else {
          guard extra.isSubset(of:["kind","settings"]) else{throw AutomationFailure(status:400,message:"Replace takes only adjustment values.")}
          let kind=try command.adjustmentBrushKind(AdjustmentBrushKind(adjustment:old) ?? .brightnessContrast)
          let base=AdjustmentBrushKind(adjustment:old)==kind ? old:kind.initial
          edit = .replaceContent(target,.adjustment(try AdjustmentBrushAPI.decode(command.parameters["settings"],kind:kind,base:base)))
        }
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision){_ in edit}
        return .json(state(share,document:document))
      }
      if command.name == "paint.configure" || command.name == "paint.mixer" {
        try await configurePainting(command,document:document,shareID:id);return .json(state(share,document:document))
      }
      if command.name == "paint.tool" {
        let request=try command.paintingRequest(store:store)
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision,allowAuxiliary:true) { original in .painting(try PaintingPreparation.prepare(request,in:original)) }
        return .json(state(share,document:document))
      }
      if command.name == "paint.stroke" {
        let current=store.brush,library=store.brushes.file
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision,allowAuxiliary:true) { original in try command.brushStroke(document:original,current:current,library:library) }
        return .json(state(share,document:document))
      }
      if command.name == "actions.manage" { return .json(try manageActions(command, store: store)) }
      if command.name == "actions.play" {
        guard store.session.actionRecording == nil else { throw AutomationFailure(status:409,message:"Stop action recording before playback.") }
        return try await executeRecordedAction(command, document: document, share: share)
      }
      if command.name == "document.photomerge" { return try await executePhotomerge(command,anchorID:id) }
      if command.name == "document.imageProcessor" {return try await executeImageProcessor(command,anchorID:id)}
      if command.name == "document.cropStraighten" || command.name == "document.cropStraighten.detect" {return try await executeScanCrop(command,document:document,shareID:id)}
      if command.name == "document.contactSheet" {return try await executeContactSheet(command,anchorID:id)}
      if command.name == "document.imageStack" { return try await executeImageStack(command,anchorID:id) }
      if command.name == "document.hdrMerge" { return try await executeHDRMerge(command,anchorID:id) }
      if command.name == "raw.inspect" { return .json(try await inspectRaw(command,document:document,shareID:id)) }
      if command.name == "liquify.faces" { return .json(try await detectLiquifyFaces(command, document: document, shareID: id)) }
      if command.name == "document.autosave" {
        try await document.writeRecoverySnapshot()
        prune()
        guard isRunning, shares.contains(where: { $0.id == id }) else {
          throw AutomationFailure(status: 409, message: "Document sharing ended during autosave.")
        }
        return .json(state(share, document: document))
      }
      if try await handleDocumentSave(command, document: document, shareID: id) {
        return .json(state(share, document: document))
      }
      if command.name == "document.revert" {
        guard documentTransfersEnabled else {
          throw AutomationFailure(
            status: 403, message: "Enable document transfers and Revert in the native API window.")
        }
        guard document.revertSourceURL != nil else {
          throw AutomationFailure(
            status: 409, message: "This document has no saved file to revert to.")
        }
        let expectedToken = token
        let expectedGeneration = documentTransferGeneration
        let decoder = documentDecoder
        try await document.revertDocument(
          reader: { url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= DocumentIO.maximumUploadBytes else {
              throw AutomationFailure(
                status: 413, message: "Saved file exceeds the API input limit.")
            }
            return try decoder(
              Data(contentsOf: url), DocumentIO.isNativeFile(url),
              url.deletingPathExtension().lastPathComponent)
          },
          validate: { model in
            self.prune()
            guard self.isRunning, self.token == expectedToken, self.documentTransfersEnabled,
              self.documentTransferGeneration == expectedGeneration,
              self.shares.contains(where: { $0.id == id }), command.revision == self.revision(store)
            else {
              throw AutomationFailure(
                status: 409, message: "Revert was cancelled or sharing changed.")
            }
            try Self.checkLimits(model)
          })
        return .json(state(share, document: document))
      }
      if try command.applyViewCommand(to: store) {
        return .json(state(share, document: document))
      }
      if command.name == "layer.new" {
        guard store.document.layers.count < 64,
          store.document.estimatedBytes + store.document.width * store.document.height * 16 <= 128
            * 1024 * 1024
        else {
          throw AutomationFailure(status: 413, message: "Adding a layer would exceed API limits.")
        }
      }
      if RegionRetouchAPI.commands.contains(command.name) {
        let options = try command.regionRetouchOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in
          .regionRetouch(try RegionRetouchPreparation.prepare(options.request,document:original,layerID:options.id))
        }
        return .json(state(share,document:document))
      }
      if GeometryAPI.commands.contains(command.name) {
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { original in try command.geometryCommand(in: original) }
        return .json(state(share, document: document))
      }
      if command.name == "document.crop" {
        let request = try command.cropOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in .cropDocument(try CropPreparation.prepare(request,document:original)) }
        return .json(state(share,document:document))
      }
      if command.name == "filter.vanishingPoint" {
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in
          let (layerID,program)=try command.vanishingOptions(in:original)
          return .vanishingPoint(try VanishingEdit.prepare(original,layerID:layerID,program:program,sample:Renderer.composite(original)))
        }
        return .json(state(share,document:document))
      }
      if command.name == "layer.warp" {
        let (layerID,settings) = try command.warpOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in .warp(try WarpEdit.prepare(original,layerID:layerID,warp:settings)) }
        return .json(state(share,document:document))
      }
      if command.name == "photo.autoAlign" {
        let (ids,settings) = try command.photoAlignOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in
          .photoAlign(try PhotoAlign.prepare(original,layerIDs:ids,settings:settings))
        }
        return .json(state(share,document:document))
      }
      if command.name == "photo.autoBlend" {
        let (ids,settings) = try command.photoBlendOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in
          .photoBlend(try PhotoBlend.prepare(original,layerIDs:ids,settings:settings))
        }
        return .json(state(share,document:document))
      }
      if command.name == "contentAware.scale" {
        let options = try command.contentAwareScaleOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in .contentAwareScale(try ContentAwareScaleEdit.prepare(original,layerID:options.id,request:options.request)) }
        return .json(state(share,document:document))
      }
      if command.name == "contentAware.fill" {
        let options = try command.contentAwareOptions()
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in .contentAwareFill(try options.edit(original)) }
        return .json(state(share,document:document))
      }
      if command.name == "channel.edit" {
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision,allowAuxiliary:true) { original in try command.channelEdit(document:original) }
        return .json(state(share,document:document))
      }
      if command.name == "selection.refine" || command.name == "selection.focus" { return try await refineSelection(command,document:document,share:share) }
      if command.name == "raw.develop" {
        try await executePreparedOperation(document:document,shareID:id,revision:command.revision) { original in try command.rawCommand(original) }
      } else if command.name.hasPrefix("smartObject.") || ["layer.rasterize", "layer.transform"].contains(command.name) {
        try await executeSmartObject(command, document: document, shareID: id)
      } else if command.name == "selection.subject" || command.name == "layer.removeBackground" {
        let options = try command.foregroundOptions(document: store.document)
        let detector = store.foregroundDetector
        try await executePreparedOperation(document: document, shareID: id, revision: command.revision) { original in
          try await ForegroundSelection.command(document: original, layerID: options.layerID,
            removeBackground: options.removeBackground, sampleAllLayers: options.all,
            mode: options.mode, detector: detector)
        }
      } else if let native = try command.nativeCommand(document: store.document, lookup: resolveColorLookup(command)) {
        if command.name == "layer.merge" || command.name == "filter.apply" || command.name.hasPrefix("adjustment.") || command.name.hasPrefix("smartFilter.") {
          try await executeMerge(
            native, document: document, shareID: id, revision: command.revision)
        } else {
          try store.executeEditorCommand(native)
        }
      } else {
        let expectedToken = token
        try await store.navigateHistory(
          redo: command.name == "history.redo", authorizationID: id, validate: Self.checkLimits,
          validateCommit: {
            self.prune()
            guard self.isRunning, self.token == expectedToken,
              self.shares.contains(where: { $0.id == id }), command.revision == self.revision(store)
            else {
              throw AutomationFailure(
                status: 409, message: "History sharing was revoked or changed.")
            }
          })
      }
      return .json(state(share, document: document))
    } catch is CancellationError {
      return .failure(.init(status: 409, message: "Operation cancelled; no changes were applied."))
    } catch let failure as HistoryNavigationConflict {
      return .failure(.init(status: 409, message: failure.localizedDescription))
    } catch let failure as RecoverySourceConflict {
      return .failure(.init(status: 409, message: failure.localizedDescription))
    } catch let failure as DocumentSaveConflict {
      return .failure(.init(status: 409, message: failure.localizedDescription))
    } catch let failure as DocumentPersistenceConflict {
      return .failure(.init(status: 409, message: failure.localizedDescription))
    } catch let failure as AdobeAPIError {
      return request.path.hasPrefix("/v2/")
        ? failure.response
        : .failure(.init(status: failure.status, message: failure.message))
    } catch let review as ColorPolicyReviewNeeded { return ColorPolicyAPI.reviewResponse(review.assessment) } catch let failure as AutomationFailure { return .failure(failure) } catch {
      return .failure(.init(status: 422, message: error.localizedDescription))
    }
  }
  nonisolated static func png(
    _ document: CraftDocument, onionSkin: Bool = false, proof: ProofSettings? = nil, channelView: RGBChannelView = RGBChannelView(),auxiliary: ChannelPlaneTarget? = nil,overlay: Bool = false,modeVisibility: Set<Int>? = nil, inkVisibility: Set<InkChannelTarget>? = nil
  ) throws -> Data {
    try Task.checkCancellation()
    let composite = try onionSkin ? OnionSkinRenderer.render(document):Renderer.composite(document)
    try Task.checkCancellation()
    let preview = try document.inkMode != nil ? InkChannelPresentation.surface(document, visible: inkVisibility) : modeVisibility.map { try ModeChannelPresentation.surface(document, visible: $0) } ?? channelView.applying(to: composite)
    let image =
      try proof?.active == true ? SoftProof.image(document, composite: composite, settings: proof!) : auxiliary != nil ? ChannelPresentation.image(composite,document:document,target:auxiliary,overlay:overlay) : (inkVisibility != nil || modeVisibility != nil || channelView.visible.count == 1)
      ? RasterIO.displayImage(preview) : ColorManagement.displayImage(preview, in: document)
    let bytes = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        bytes, UTType.png.identifier as CFString, 1, nil)
    else {
      throw AutomationFailure(status: 500, message: "Could not encode preview.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw AutomationFailure(status: 500, message: "Could not encode preview.")
    }
    return bytes as Data
  }
  static var capabilities: [String: Any] {
    func inventory(_ nodes: [EditorMenuNode], parents: [String] = []) -> [[String: Any]] {
      nodes.filter { $0.title != "-" }.flatMap { node -> [[String: Any]] in
        let path = parents + [node.title]
        return [
          ["path": path, "kind": node.children == nil ? "command" : "menu", "shortcut": node.key]
        ]
          + (node.children.map { inventory($0, parents: path) } ?? [])
      }
    }
    return [
      "apiVersion": 1, "transport": "loopback HTTP; bearer token; same origin",
      "recoveryPreferences": recoveryPreferencesCapabilities,
      "photoshopFilePreferences": photoshopFilePreferencesCapabilities,
      "recoveryDiscovery": recoveryDiscoveryCapabilities,
      "recoveryBackups": recoveryBackupsCapabilities,
      "recoverySalvage": recoverySalvageCapabilities,
      "documentClosing": documentClosingCapabilities,
      "documentOpening": documentOpeningCapabilities,
      "recentDocuments": recentDocumentsCapabilities,
      "commands": AutomationCommand.definitions.map {
        [
          "command": $0.name, "parameters": $0.parameters, "description": $0.description,
          "schema": $0.schema,
        ] as [String: Any]
      }, "menuInventory": inventory(PhotoshopMenuCatalog.menus),
      "menuInventoryNotice":
        "Reference inventory only. Only entries in commands are executable through this API.",
      "colorProfiles": ColorProfileAPI.capabilities,
      "timelineWorkspace": TimelineWorkspaceAPI.capabilities,
      "videoRender": VideoRenderAPI.capabilities,
      "variables": VariablesAPI.capabilities,
      "imageSequenceExport": ImageSequenceAPI.capabilities,
      "video": VideoAPI.capabilities,
      "audio": TimelineAudioAPI.capabilities,
      "animation": AnimationAPI.capabilities,
      "colorSettings": ColorSettingsAPI.capabilities,
      "colorPolicies": ColorPolicyAPI.capabilities,
      "proofing": ProofAPI.capabilities,
      "printing": PrintAPI.capabilities,
      "previews": [
        "onion-preview.png": "Committed video playhead with onion-skin presentation, separate from ordinary exports.",
        "proof-preview.png": "Committed composite with committed proof/gamut display settings. Excludes drafts and preserves original exports.",
        "preview.png": "Committed document composite, independent of channel visibility.",
        "channel-preview.png":
          "Committed native channel view, including selected alpha/Quick Mask gray or overlay. Excludes uncommitted drafts.",
      ],
      "channelView": [
        "preview": "Current color-mode composite or component name", "visible": "Nonempty array of component names in the current color mode",
        "componentEditing":
          "True when an individual editing target is selected; independent of preview",
        "persistence": "Per-document view state; no document history entry",
      ],
      "componentEditing": [
        "targets": Array(Set(RGBChannelPreview.allCases.map(\.title) + DocumentColorMode.componentModes.flatMap { [$0.title] + $0.componentNames })).sorted(),
        "depth": "RGB/Gray8/16/32 and CMYK/Lab8/16", "operations": ["Legacy RGB8 Normal neutral Fill", "Native component fill, brush/erase, invert and eight filters"],
        "nativeModeCapabilities": "documentModes",
        "unimplemented": [
          "Other legacy RGB8 component tools", "Full native component tool/Action coverage", "Spot channels",
        ],
      ],
      "actionJobs": [
        "blankDocumentCreation": AdobeDocumentCreation.capabilities,
        "colorModeActions": PhotoshopActionProgram.modeCapabilities,
        "photatoAdditionalInput": "Original PhotoCraft v1 .pcraft ZIP (editable subset described in documentOpening.pcraft). Not accepted by Adobe v2. Existing64MiB resource,4,194,304 canvas pixel,64layer and128MiB document limits apply.",
        "encodingOptions": DocumentEncodingOptions.capabilities,
        "outputs": ["image/png", "image/jpeg", "image/tiff", "image/vnd.adobe.photoshop"],
        "pngCompression": DocumentEncodingOptions.pngLevels,
        "outputICC": ["field": "outputs[].iccProfile", "standardNames": ["sRGB IEC61966-2.1", "Adobe RGB (1998)", "Gray Gamma 2.2"], "customModes": ["rgb", "grayscale", "cmyk"], "customMaximumBytes": ICCProfile.maximumBytes, "engine": "Apple ColorSync", "schema": AdobeOutputProfile.schema, "limitations": "URL resources only; non-RGB output ICC requires PSD/TIFF; other named profiles and proprietary ACE defaults/output equality remain open. Custom 32-bit profiles must be linear. Each output converts independently; PSD retains supported editable layers."],
        "encodingLimitations": "PNG action outputs retain RGB8/16 and flat Indexed8/Bitmap1. TIFF retains RGB/Gray8/16/32, CMYK/Lab8/16 and flat Indexed8/Bitmap1 with supported transparency and profiles. RGB32 PNG output requires PSD or TIFF instead. Photato encodingOptions includes TIFF byte order, channel layout and32-bit LZW/ZIP prediction, distinct from the Adobe output contract. Photato jobs can preserve supported TIFF layers with encodingOptions.tiffLayers=true and rle/zip tiffLayerCompression; Adobe TIFF output defaults remain flattened without new fields. JPEG output accepts the published quality enum and converts to opaque8-bit. Photato encodingOptions additionally selects baseline/optimized/progressive, matte and profile embedding; see documentTransfers.encodingOptions. Execute-actions rejects scan. Pyramids, Duotone/Multichannel and Photoshop JPEG quantization/scan parity remain unimplemented. See documentTransfers.restrictedFormats for exact restricted-mode storage limits. Supported layered TIFF inputs retain editable layers; see documentTransfers.layeredTIFF.",
        "photatoSubmit": "/v1/action-jobs", "photatoStatus": "/v1/action-jobs/{jobId}",
        "adobeProtectionSubmit": "/v2/create-composite",
        "adobeArtboardSubmit": "/v2/create-artboard",
        "adobeArtboardScope": "One to25 URL image sources, optional names and horizontal spacing0–32768 (default50); each source composite becomes an editable raster inside a native artboard. PNG/JPEG/TIFF/JSON outputs, hosted or HTTPS PUT. PSD/PSDC, cloud/embedded storage, scan/resizing and exact Adobe manifest/pixel equivalence remain unsupported.",
        "adobeColorEditSubmit": "/v2/edit",
        "adobeRemoveBackgroundSubmit": "/v2/remove-background",
        "adobeProtectionScope": "Existing input layers: operation.type edit with protection and supported dropShadow effects, exact unique name or PSD id. Group edits replace descendant flags. Blank images use the documented blankDocumentCreation subset. Other layer properties and unimplemented add/delete/move variants remain unsupported.",
        "adobeSubmit": "/v2/execute-actions", "adobeStatus": "/v2/status/{jobId}",
        "notice":
          "Optional isolated resource jobs. Requires native enablement each session. Inline actionJSON supports the documented colorModeActions creation-independent conversion/component subset. Legacy RGB8 neutral Fill remains qualified; RGB/Gray8/16/32 and CMYK/Lab8/16 PSD/PSB/TIFF input supports applicable root raster merges ($Mrg2/$MrgV), selectAllLayers, composite RGB selection and PSD preservation. The eight native raster filters are available through actionJSON on the active RGB pixel layer; Smart Filters and exact Photoshop output parity are unqualified. Five classic color adjustments and inline base64 Color Lookup LUT descriptors are supported through actionJSON (51,200-character program limit); /v2/edit supports light, color vibrance/saturation, effects, sharpening and noise reduction with PNG/JPEG output through the native Camera Raw engine. The installed applyImageStackPluginRenderer class descriptor supports eleven statistical modes on an embedded Smart Object; use flattened PNG/TIFF output because editable PSD stack transport is not implemented. Multichannel8/16 PSD/PSB file transport retains ink/alpha planes and spot metadata; ink editing descriptors remain unsupported. Other Adobe operations are unsupported.",
      ],
      "documentTransfers": documentTransferCapabilities,
      "classicAdjustments": ClassicAdjustment.apiCapabilities,
      "colorLookup": colorLookupCapabilities,
      "filters": RasterFilter.apiCapabilities,
      "vanishingPoint": VanishingSettings.apiCapabilities,
      "brushes":BrushAPI.capabilities,
      "rawDevelopment": RawDevelopment.apiCapabilities,
      "layerStyles": LayerStyle.apiCapabilities,
      "smartObjects": SmartObject.apiCapabilities,
      "text": TextContent.apiTypeCapabilities,
      "smartFilters": SmartFilterStack.apiCapabilities,
      "selectionRefinement": SelectionRefinement.apiCapabilities,
      "alphaChannels": ChannelAPI.capabilities,
      "contentAwareFill": ContentAwareSettings.apiCapabilities,
      "photomerge": PhotomergeSettings.apiCapabilities,
      "movieFramesImport":MovieFramesAPI.capabilities,
      "pdfImport":PDFImportAPI.capabilities,
      "imageProcessor": ImageProcessorAPI.capabilities,
      "cropStraighten": ScanCropAPI.capabilities,
      "contactSheet": ContactSheetSettings.apiCapabilities,
      "imageStack": ImageStackSettings.apiCapabilities,
      "hdrMerge": HDRMergeSettings.apiCapabilities,
      "shapes":ShapeAPI.capabilities,
      "inkModes": InkModeAPI.capabilities,
      "inkChannels": InkChannelAPI.capabilities,
      "restrictedModes": RestrictedModeAPI.capabilities,
      "documentModes": DocumentModeAPI.capabilities,
      "classicTone":ClassicToneAPI.capabilities,
      "proceduralRender":ProceduralAPI.capabilities,
      "paths":PathAPI.capabilities,
      "frames": FrameDefinition.apiCapabilities,
      "artboards": Artboard.apiCapabilities,
      "warp": WarpDefinition.apiCapabilities,
      "photoAlign": PhotoAlignSettings.apiCapabilities,
      "photoBlend": PhotoBlendSettings.apiCapabilities,
      "sky":SkyAPI.capabilities,
      "peopleSelection":PeopleAPI.capabilities,
      "objectFinder":ObjectFinderAPI.capabilities,
      "maskAllObjects":MaskAllObjectsAPI.capabilities,
      "focusArea":FocusAreaAPI.capabilities,
      "selectionTools":SelectionToolAPI.capabilities,
      "adjustmentBrush":AdjustmentBrushAPI.capabilities,
      "paintingTools":PaintingAPI.capabilities,
      "regionRetouch": RegionRetouchAPI.capabilities,
      "contentAwareScale": ContentAwareScaleRequest.apiCapabilities,
      "clipboard": ClipboardAPI.capabilities,
      "geometry": GeometryAPI.capabilities,
      "crop": CropRequest.apiCapabilities,
      "subjectDetection": ForegroundSelection.apiCapabilities,
      "atomicPersistence": atomicPersistenceCapabilities,
      "documentSaving": documentSavingCapabilities,
      "stateSchemas": [
        "shapes":ShapeAPI.stateSchema,
        "documentMode": DocumentModeAPI.stateSchema,
        "colorProfile": ColorProfileAPI.stateSchema,
        "videoRender": VideoRenderAPI.stateSchema,
        "variables": VariablesAPI.stateSchema,
        "sequenceExport": ImageSequenceAPI.stateSchema,
        "video": VideoAPI.stateSchema,
        "audio": TimelineAudioAPI.stateSchema,
        "videoSequenceCreation": BrushAPI.object(["operationID":["type":["string","null"],"format":"uuid"],"sourceIDs":["type":"array","items":["type":"string","format":"uuid"]]],required:["operationID","sourceIDs"]),
        "animation": AnimationAPI.stateSchema,
        "printing": PrintAPI.stateSchema, "proofing": ProofAPI.stateSchema, "inkMode": InkModeAPI.stateSchema,
        "classicTone":ClassicToneAPI.stateSchema,
        "proceduralRender":ProceduralAPI.stateSchema,
        "paths":PathAPI.stateSchema,
        "sky":SkyAPI.stateSchema,
        "peopleSelection":PeopleAPI.stateSchema,
        "objectFinder":ObjectFinderAPI.stateSchema,
        "maskAllObjects":MaskAllObjectsAPI.stateSchema,
        "focusArea":FocusAreaAPI.stateSchema,
        "selectionTools":SelectionToolAPI.stateSchema,
        "layerProtection": protectionStateSchema,
        "subjectDetection": ForegroundSelection.apiStateSchema,
        "foregroundLayerMask": ForegroundSelection.apiLayerStateSchema,
        "smartObject": SmartObject.apiLayerStateSchema,
        "recovery": recoveryStateSchema,
        "recoverySource": recoverySourceSchema,
        "recoveryRegistration": recoveryRegistrationSchema,
        "historyOperation": [
          "type": "object", "additionalProperties": false,
          "required": ["active", "id", "direction", "cancellationRequested"],
          "properties": [
            "active": ["type": "boolean"],
            "id": ["type": ["string", "null"], "format": "uuid"],
            "direction": ["type": ["string", "null"], "enum": ["undo", "redo", NSNull()]],
            "cancellationRequested": ["type": "boolean"],
          ],
        ],
        "historyStorage": [
          "type": "object", "additionalProperties": false,
          "required": [
            "undoStates", "redoStates", "spilledStates", "residentPayloadBytes",
            "sharedScratchBytes", "reusableCurrentRasterBytes",
            "residentPayloadLimitBytes", "scratchLimitBytes", "cleanupFailures",
          ],
          "properties": Dictionary(
            uniqueKeysWithValues: [
              "undoStates", "redoStates", "spilledStates", "residentPayloadBytes",
              "sharedScratchBytes", "reusableCurrentRasterBytes",
              "residentPayloadLimitBytes", "scratchLimitBytes", "cleanupFailures",
            ].map { ($0, ["type": "integer", "minimum": 0] as [String: Any]) }),
        ],
        "workingProfile": [
          "type": "object", "additionalProperties": false,
          "required": ["name", "embedded", "sampleEncoding", "iccSHA256"],
          "properties": [
            "name": ["type": "string"], "embedded": ["type": "boolean"],
            "sampleEncoding": ["type": "string", "enum": ["linearRGB", "profileRGB"]],
            "iccSHA256": ["type": ["string", "null"], "pattern": "^[0-9a-f]{64}$"],
          ],
        ],
        "selectedLayerIDs": [
          "type": "array", "uniqueItems": true, "items": ["type": "string", "format": "uuid"],
        ],
        "mergeAvailability": [
          "type": "object", "additionalProperties": false,
          "required": ["down", "selected", "visible"],
          "properties": [
            "down": ["type": "boolean"], "selected": ["type": "boolean"],
            "visible": ["type": "boolean"],
          ],
        ],
        "isModified": ["type": "boolean"],
        "persistenceFormat": [
          "type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue),
        ],
        "saveFormats": [
          "type": "array", "uniqueItems": true,
          "items": ["type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue)],
        ],
        "saveEncodingOptions": [
          "type": "object", "additionalProperties": false,
          "required": DocumentIO.Format.allCases.map(\.rawValue),
          "properties": Dictionary(uniqueKeysWithValues: DocumentIO.Format.allCases.map {
            ($0.rawValue, DocumentEncodingOptions.schema)
          }),
        ],
        "effectiveSaveEncodingOptions": [
          "type": "object", "additionalProperties": false,
          "required": DocumentIO.Format.allCases.map(\.rawValue),
          "properties": Dictionary(uniqueKeysWithValues: DocumentIO.Format.allCases.map {
            ($0.rawValue, DocumentEncodingOptions.schema)
          }),
        ],
        "canSave": ["type": "boolean"], "canSaveAs": ["type": "boolean"],
        "sourceSaveNeedsReview": ["type": "boolean"],
        "alphaChannelTarget": ["type":"string","description":"RGB, quickMask, or alpha UUID"],
      "alphaChannelOverlay": ["type":"boolean"],
      "channels": ["type":"array","items":["type":"object","required":["id","name","opacity","indicates","color"],"properties":["id":["type":"string","format":"uuid"],"name":["type":"string"],"opacity":["type":"number"],"indicates":["type":"string"],"color":["type":"array","items":["type":"number"]]]]],
      "quickMask": ["type":["object","null"]],
      "channelTarget": ["type": "string", "description": "Composite color mode or selected component names; numerical indices are in documentMode.editingComponents."],
        "channelView": [
          "type": "object", "additionalProperties": false,
          "required": ["preview", "visible", "componentEditing"],
          "properties": [
            "preview": ["type": "string"],
            "visible": [
              "type": "array", "minItems": 1, "maxItems": 4, "uniqueItems": true,
              "items": ["type": "string"],
            ],
            "componentEditing": ["type": "boolean"],
          ],
        ],
      ],
      "limits": [
        "maxCanvasPixels": 4_194_304, "maxLayers": 64, "maxDocumentBytes": 134_217_728,
        "maxSharedDocuments": 8, "maxRequestBytes": 65_536, "maxCommandRequestBytes": LiquifyMeshFile.maximumBytes,
      ],
      "commandEnvelope": [
        "command": "stable command name", "revision": "latest document revision",
        "parameters": "object; all listed fields required",
      ],
      "history":
        "Shared with desktop edits. A successful no-op may leave revision and history unchanged.",
      "recovery": recoveryCapabilities,
      "recoverySource": recoverySourceCapabilities,
      "historyNavigation": [
        "backgroundPreparation": true, "cancellable": true,
        "completion":
          "Undo/Redo HTTP requests wait for atomic publication and return document state.",
        "cancellation":
          "history.cancel requires the active operationID and current document revision. Acknowledgement requests cancellation; historyOperation remains active until the worker finishes.",
        "conflict":
          "Concurrent edits, cancelled/stale operations and revoked sharing return 409 without changing content, history, dirty state or revision.",
        "availability":
          "canUndo/canRedo describe stack availability. Mutations are unavailable while historyOperation.active is true; history.cancel remains available.",
        "storageState":
          "During preparation, historyStorage reports the last committed snapshot without waiting for scratch writes.",
      ],
      "historyStorage": [
        "scratchSnapshots": true, "integrity": "SHA256-checked immutable tile and metadata blobs",
        "defaultResidentPayloadLimitBytes": EditorSession.defaultHistoryByteLimit,
        "defaultScratchLimitBytes": EditorSession.defaultHistoryDiskByteLimit,
        "defaultStateLimit": 40,
        "currentRasterReuse": true,
        "reuseIntegrity": "Reused current-document tiles still require a verified scratch blob.",
        "reuseAccounting":
          "reusableCurrentRasterBytes is already included in current document pixels, not extra history memory. The reuse index is replaced on navigation and cleared on editing.",
        "accounting":
          "Unique native COW tile allocations beyond the current document, plus conservative other payload estimates; index and allocator overhead are separate.",
        "failure":
          "Edit/Undo/Redo failures leave document, history stacks and revision unchanged. No desktop alert for API failures.",
        "lifetime":
          "Private ephemeral files retained by snapshots/value-copy sessions; released with the last owner. Not crash recovery or a native archive.",
        "limits":
          "Active-document paging, total-memory qualification and complete Photoshop history/preferences parity remain open.",
      ],
    ]
  }
}
