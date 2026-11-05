import AppKit
import Observation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class EditorStore {
  let identity = UUID()
  var layerPanelGeneration = UUID()
  @ObservationIgnored weak var numericEditor: (any NumericFieldEditing)?
  let cloneState: CloneSources
  let patterns: PatternLibrary
  let gradients: GradientLibrary
  var gradientNameDraft: GradientNameDraft?
  var backgroundLayerDraft:BackgroundLayerDraft?
  var newLayerDraft: NewLayerDraft?
  var newGroupDraft: NewGroupDraft?
  let shapes: ShapeLibrary
  var shapeRevision=0
  var selectedShapeID: UUID? {didSet{if oldValue != selectedShapeID{shapeRevision+=1}}}
  var shapeDraft: ShapeDraft?
  var shapePreview: CraftDocument?
  var shapeGesture: ShapeGesture?
  var shapeTemplate=ShapeDefinition(geometry:.init()) {didSet{if oldValue != shapeTemplate{shapeRevision+=1}}}
  var shapeMode=ShapeOutputMode.shape {didSet{if oldValue != shapeMode{shapeRevision+=1}}}
  var shapeOperation: PathOperation? {didSet{if oldValue != shapeOperation{shapeRevision+=1}}}
  var frameDraft: FrameDraft?
  var frameGesture: FrameGesture?
  var frameShape: FrameDefinition.Shape = .rectangle
  var frameSides = 5
  var frameTarget: FrameTarget = .both
  var layerFileDraft: LayerFileDraft?
  var layerFilesID: UUID?
  var layerFilesProgress = LayerFileProgress()
  @ObservationIgnored var layerFilesWorker: Task<LayerFileExportResult, Error>?
  @ObservationIgnored var layerFilePreparation: @Sendable (CraftDocument,LayerFileExportSettings,URL,@Sendable (LayerFileProgress)->Void) throws -> PreparedLayerFiles = { try LayerFileExport.prepare($0,options:$1,directory:$2,progress:$3) }
  var imageExportDraft: ImageExportDraft?
  var colorLookupExportDraft: ColorLookupExportDraft?
  var colorLookupExportID: UUID?
  @ObservationIgnored var colorLookupExportWorker: Task<Data, Error>?
  @ObservationIgnored var colorLookupExportPreparation: @Sendable (CraftDocument, Int, String) throws -> Data = { try ColorLookupExport.cube($0, size: $1, title: $2) }
  var imageExportID: UUID?
  @ObservationIgnored var imageExportWorker: Task<ImageExportOutput, Error>?
  @ObservationIgnored var imageExportPreparation: @Sendable (CraftDocument, ImageExportSettings) throws -> ImageExportOutput = ImageExportPreparation.render
  var selectionModifyDraft:SelectionModifyDraft?
  var selectionRecall:SelectionRecall?
  var selectionModificationPreparation:@Sendable(CraftDocument,SelectionModification)throws->Command = {try $1.command(in:$0)}
  var magneticDraft:MagneticLassoDraft?
  var magneticSettings=MagneticLassoSettings()
  var magneticPreparation:@Sendable(CraftDocument)throws->MagneticLassoInput = {try MagneticLassoInput.prepare($0)}
  var colorRangeDraft: ColorRangeWorkspace?
  var colorRangeSettings = ColorRangeSettings()
  var colorRangePreparation: @Sendable (CraftDocument) throws -> ColorRangeInput = {try ColorRangeInput.prepare($0)}
  var fileInfoDraft: FileInfoDraft?
  var layerCompExportID: UUID?
  @ObservationIgnored var layerCompExportWorker: Task<LayerCompExportOutput, Error>?
  var guideDraft:GuideDraft?
  var guideGesture:GuideGesture?
  var selectedGuideIDs:Set<UUID>=[]
  var showCanvasGuides=true
  var guidesLocked=false
  var snapToGuides=true
  var snappingEnabled=true
  var artboardDraft: ArtboardDraft?
  var artboardGesture: ArtboardGesture?
  var showArtboardNames = true
  var showArtboardGuides = true
  var trimDraft: TrimDraft?
  @ObservationIgnored var canvasEdgePreparation: @Sendable (CraftDocument,CanvasEdgeOperation,Pixel) throws -> Command = {try CanvasEdgePreparation.command($0,operation:$1,background:$2)}
  var documentDuplicateDraft: DocumentDuplicateDraft?
  @ObservationIgnored var documentDuplicatePreparation: @Sendable (CraftDocument,String,Bool) throws -> CraftDocument = { try DocumentDuplicatePreparation.copy($0,name:$1,merged:$2) }
  var duplicateLayerDraft: DuplicateLayerDraft?
  var layerNameDraft: LayerNameDraft?
  var layerProtectionDraft: LayerProtectionDraft?
  var layerPanelOptionsDraft: LayerPanelOptionsDraft?
  var channelPanelOptionsDraft: ChannelPanelOptionsDraft?
  var layerVisibilityDraft: LayerVisibilityDraft?
  @ObservationIgnored var layerVisibilityIsolation: LayerVisibilityIsolation?
  @ObservationIgnored var layerMergePreparation: @Sendable (CraftDocument,Set<UUID>,LayerMergeOperation) throws -> Command = {try LayerMergePreparation.command($0,layerIDs:$1,operation:$2)}
  var flattenImageConfirmationID: UUID?
  @ObservationIgnored var flattenImageAlert: NSAlert?
  @ObservationIgnored var flattenImageConfirmation: (@MainActor (FlattenImageRequest) -> Bool)?
  @ObservationIgnored var flattenImagePreparation: @Sendable (CraftDocument) throws -> Command = FlattenPreparation.command
  var confirmingLayerDeletion = false
  @ObservationIgnored var layerDeletionConfirmation:
    ((LayerDeletionRequest) -> LayerDeletionChoice)?
  @ObservationIgnored var maskRemovalConfirmation: ((MaskRemovalPrompt) -> MaskRemovalChoice)?
  var duplicateTask: Task<Void, Never>?
  @ObservationIgnored var linkedArtworkOperationID:UUID?
  var linkedSourceController: LinkedSourceController?
  @ObservationIgnored var linkedSourceRegistry = LinkedSourceRegistry.shared
  @ObservationIgnored weak var documentController: CraftDocumentController?
  @ObservationIgnored var colorPolicyReviewer: ColorPolicyReviewer = ColorPolicyDialog.present
  var gradientLibraryTask: Task<Void, Never>?
  var gradientSelectionAnchor: UUID?
  var cloneDraft: CloneDraft?
  var clonePrepareTask: Task<Void, Never>?
  @ObservationIgnored var retouchPreviewFrameCount = 0
  @ObservationIgnored var retouchPreviewTask: Task<Void, Never>?
  @ObservationIgnored var interactiveRetouchPreview: InteractiveRetouchPreview?
  @ObservationIgnored var retouchPreviewGeneration = UUID()
  @ObservationIgnored var retouchPreviewDeadline = 0.0
  @ObservationIgnored var retouchPreviewFrameInterval = 1.0 / 60
  @ObservationIgnored var retouchPreviewSampleCount = 0
  @ObservationIgnored var retouchPreviewRenderMS = 0.0
  var cloneOverlayTask: Task<Void, Never>?
  var cloneOverlayKey: CloneOverlayKey?
  var cloneOverlay: CloneOverlayImage?
  let clipboard: any ClipboardAccess
  let prepareHistory: HistoryPreparation
  let brushes: BrushLibrary
  var selectedBrushID: UUID?
  var paintToolOptions: [PaintTool:PaintToolOptions] = [:] { didSet { if oldValue != paintToolOptions { brushRevision += 1 } } }
  var mixerPaint = MixerPaint() { didSet { if oldValue != mixerPaint { brushRevision += 1 } } }
  var patternStampOrigin: PathPoint?
  var patternStampID: String?
  var adjustmentBrushKind = AdjustmentBrushKind.brightnessContrast {didSet {if oldValue != adjustmentBrushKind {brushRevision += 1}}}
  var adjustmentBrushSubtract = false {didSet {if oldValue != adjustmentBrushSubtract {brushRevision += 1}}}
  var adjustmentBrushNewLayer = false {didSet {if oldValue != adjustmentBrushNewLayer {brushRevision += 1}}}
  var adjustmentBrushObject = false {didSet {if oldValue != adjustmentBrushObject {brushRevision += 1}}}
  var adjustmentBrushOverlay = false
  @ObservationIgnored var peopleFeaturesDetector:(any PeopleFeaturesDetecting)? = CoreMLPeopleFeaturesDetector.bundled
  @ObservationIgnored var peopleDetector:any PeopleDetecting = VisionPeopleDetector()
  let peopleWorkspace = PeopleWorkspace()
  @ObservationIgnored var allObjectsDetector:any AllObjectsDetecting = VisionForegroundDetector()
  @ObservationIgnored var objectDetector:any ObjectDetecting = VisionForegroundDetector()
  var brushGesture: BrushGesture?
  @ObservationIgnored var brushPreviewTask: Task<Void,Never>?
  @ObservationIgnored var brushPreviewGeneration = UUID()
  @ObservationIgnored var brushPreviewFrameInterval = 1.0 / 60
  @ObservationIgnored var brushPreviewLastStart = 0.0
  @ObservationIgnored var canvasFrameTrace = CanvasFrameTrace.fromEnvironment()
  @ObservationIgnored var brushPreviewFrameCount = 0
  @ObservationIgnored var brushPreviewSampleCount = 0
  @ObservationIgnored var brushPreviewRenderMS = 0.0
  let actions: ActionLibrary
  var actionRevision = 0
  var session: EditorSession { didSet { rememberDeselectedSelection(from:oldValue.document,to:session.document); if oldValue.document.id != session.document.id { layerPanelFilter = LayerPanelFilter(); layerFilterRevision = UUID(); layerFilterFocusRequest = 0; proofSettings = ProofSettings(); proofWorkspace = nil; printSettings = PrintSettings(); printRevision = UUID(); printWorkspace?.close(); printWorkspace = nil; printAfterDismiss = nil }; if oldValue.document.colorMode != session.document.colorMode || oldValue.document.depth != session.document.depth { proofSettings.preserveNumbers = false }; if oldValue.document.id != session.document.id || oldValue.document.colorMode != session.document.colorMode || oldValue.document.depth != session.document.depth { savedChannelVisibility=nil; temporaryMaskChannelVisibility=nil; channelVisibilitySweep=nil; inkTargets = []; inkVisibility = nil; modeComponentTargets = []; modeComponentVisibility = nil; componentTarget = .composite }; sessionGeneration = UUID(); invalidateObjectFinderIfNeeded(); invalidatePeopleIfNeeded(); layerContentFilter.sourceChanged(in: self) } }
  @ObservationIgnored private(set) var sessionGeneration = UUID()
  var historyOperation: HistoryOperation?
  @ObservationIgnored var interactiveBrushPreview: InteractiveBrushPreview?
  var canvasRasterPreview: CanvasRasterPreview?
  @ObservationIgnored var ordinaryCanvasImage = false
  var image: CGImage? { didSet { canvasRasterPreview = nil; ordinaryCanvasImage = false } }
  var surface: Surface? { didSet { channelCompositeRevision = UUID() } }
  private(set) var channelCompositeRevision = UUID()
  @ObservationIgnored var renderSnapshot: RenderSnapshot?
  var selectionPath: CGPath?
  var tool: EditorTool = .move {
    didSet {
      unavailableToolID = nil
      if oldValue != tool {
        cancelMagneticLasso()
        objectFinder.cancel(); peopleWorkspace.close()
        artboardGesture = nil; frameGesture = nil; shapeGesture = nil; _ = finishType()
        if oldValue == .crop { cancelCrop() }
        if oldValue.regionRetouchKind != nil { cancelRegionRetouch() }
        if oldValue.usesSelectionStroke {cancelBrush()}
        if oldValue == .selectionBrush || tool == .selectionBrush {render()}
      }
    }
  }
  var unavailableToolID: String?
  var rememberedTools: [String: String] = [:]
  var selectedTool: WorkspaceTool {
    if let id = unavailableToolID { return WorkspaceCatalog.tool(id) }
    return WorkspaceCatalog.tools.first { $0.native == tool } ?? WorkspaceCatalog.tools[0]
  }
  var showGaps = false
  var workspaceLibrary = WorkspaceLibrary()
  var workspace: WorkspaceVisibility {
    get { workspaceLibrary.layout.visibility }
    set { workspaceLibrary.layout.visibility = newValue }
  }
  var showRulers = false
  var autoSelect = true
  var lastPixelStroke=PixelPaintSettings()
  var lastPixelFill=PixelPaintSettings()
  var lastPixelFillContents="Foreground Color"
  var lastPixelFillPatternID:String?
  @ObservationIgnored var pixelPaintPreparation:@Sendable (CraftDocument,PixelPaintRequest)throws->Command = {_,request in .pixelPaint(request)}
  var showLayerBounds = false
  var selectedLayerIDs: Set<UUID> = []
  let layerContentFilter = LayerContentFilterWorkspace()
  var layerPanelFilter = LayerPanelFilter()
  var layerFilterRevision = UUID()
  var layerFilterFocusRequest = 0
  var layoutTarget = LayerLayoutTarget.selection
  var pathTarget: PathTarget?
  var pathAnchor: PathAnchorSelection?
  var pathGesture: PathGesture?
  var freeformGesture: FreeformPathGesture?
  var pathSettingsRevision = 0
  var pathCurveFit: Double = 2 { didSet {if !pathCurveFit.isFinite || !(0.5...10).contains(pathCurveFit){pathCurveFit=oldValue};if pathCurveFit != oldValue{pathSettingsRevision += 1}} }
  var penComponent: Int?
  var pathOperation = PathOperation.combine { didSet {if oldValue != pathOperation{pathSettingsRevision += 1}} }
  var layerMaskView: LayerMaskView?
  var renderedMaskView: LayerMaskView?
  var maskViewImage: CGImage?
  var maskViewRegion: IntRect?
  var smartFilterMaskEditing = false
  var maskEditingLayerID: UUID? {
    didSet {
      // Clearing the owner always leaves Smart Filter mask editing. Keep the
      // viewing state: prepared mask edits may restore their captured target.
      if maskEditingLayerID == nil { smartFilterMaskEditing = false }
    }
  }
  var editingMask: Bool { activeLayer?.id == maskEditingLayerID && activeLayer?.mask != nil }
  var selectionMode = SelectionMode.replace
  var selectionFeather: Double = 0
  var selectionPaintMode:SelectionMode = .add
  let objectFinder = ObjectFinderWorkspace()
  var objectFinderEnabled = true { didSet { if oldValue != objectFinderEnabled { objectFinder.cancel(); refreshObjectFinderIfNeeded() } } }
  var objectFinderHardEdge = false
  var objectFinderColor = Pixel(0.15,0.45,1,0.45) { didSet { if oldValue != objectFinderColor { setObjectHover(objectFinder.hoveredID,force:true) } } }
  var objectSelectionMode:ObjectSelectionMode = .rectangle
  var selectionSampleAllLayers=false { didSet { if oldValue != selectionSampleAllLayers { objectFinder.cancel(); peopleWorkspace.cancel(); refreshObjectFinderIfNeeded() } } }
  var selectionEnhanceEdge=false
  var selectionOverlayColor=Pixel(1,0,0,0.5)
  var selectionOverlayImage:CGImage?
  var selectionOverlayRegion: IntRect?
  var selectionAntiAlias = true
  var wandOptions = ColorMatchOptions()
  var wandSampleAllLayers = false
  var bucketOptions = BucketOptions()
  var bucketUsesPattern = false
  var bucketPatternPlacement = PatternPlacement()
  var patternNameDraft: PatternNameDraft?
  var gradientFillDraft: GradientFillDraft?
  var gradientOptions = GradientToolOptions()
  var gradientGesture: GradientGesture?
  var gradientSelectedStop: (id: UUID, index: Int)?
  var gradientStopColorDraft: GradientStopColorDraft?
  @ObservationIgnored var gradientFrameCache:
    (layer: Layer, width: Int, height: Int, frame: IntRect)?
  var patternFillDraft: PatternFillDraft?
  var showFeatherSelection = false
  @ObservationIgnored var cropPreparation:@Sendable(CropRequest,CraftDocument)throws->CropEdit = {try CropPreparation.prepare($0,document:$1)}
  var cropDraft: CropDraft?
  var cropReadyDraft: CropDraft?
  var cropPrepared: CropEdit?
  var cropPreviewImage: CGImage?
  var cropBusy = false
  var cropError: String?
  var cropStraighten = false
  var cropRevision = 0
  var puppetWorkspace: PuppetWorkspace?
  var skyWorkspace: SkyWorkspace?
  let skies:SkyLibrary
  var vanishingWorkspace: VanishingWorkspace?
  var wideAngleWorkspace: WideAngleWorkspace?
  var lensCorrectionWorkspace: LensCorrectionWorkspace?
  var proofDisplayError: String?
  var printSettings = PrintSettings()
  var printWorkspace: PrintWorkspace?
  var printBusy = false
  var printOperationID: UUID?
  var printJobStatus = "idle"
  var printJobError: String?
  var printRevision = UUID()
  @ObservationIgnored var printCancellation: (() -> Void)?
  @ObservationIgnored var printAfterDismiss: (() -> Void)?
  var proofSettings = ProofSettings()
  var proofWorkspace: ProofWorkspace?
  var colorProfileWorkspace: ColorProfileWorkspace?
  var inkModeWorkspace: InkModeWorkspace?
  var restrictedModeWorkspace: RestrictedModeWorkspace?
  var previousIndexedPalette: [PaletteColor]?
  var documentModeWorkspace: DocumentModeWorkspace?
  var classicToneWorkspace:ClassicToneWorkspace?
  var channelArithmeticWorkspace:ChannelArithmeticWorkspace?
  var shadowWorkspace:ClassicToneWorkspace?
  var proceduralWorkspace:ProceduralWorkspace?
  var classicDetailWorkspace: ClassicDetailWorkspace?
  var otherVideoWorkspace: OtherVideoWorkspace?
  var renderWorkspace: RenderWorkspace?
  var stylizeWorkspace: StylizeWorkspace?
  var pixelateWorkspace: PixelateWorkspace?
  var distortionWorkspace: DistortionWorkspace?
  var lensBlurWorkspace: LensBlurWorkspace?
  var lightingWorkspace:LightingWorkspace?
  var relightWorkspace:RelightWorkspace?
  var photoDetailWorkspace: PhotoDetailWorkspace?
  var artisticGalleryWorkspace: ArtisticGalleryWorkspace?
  var blurGalleryWorkspace: BlurGalleryWorkspace?
  var perspectiveWorkspace: PerspectiveWorkspace?
  var warpDraft: WarpWorkspace?
  var photoAlignDraft: PhotoAlignWorkspace?
  var photoBlendDraft: PhotoBlendWorkspace?
  var regionRetouchSettings = RegionRetouchRequest(kind:.patch)
  var regionRetouchTransformOnDrop = true
  var regionRetouchDraft: RegionRetouchDraft?
  var regionRetouchReady: RegionRetouchDraft?
  var regionRetouchPreview: CraftDocument?
  var regionRetouchBusy = false
  var regionRetouchError: String?
  var regionRetouchCommitWhenReady = false
  var regionRetouchRevision = 0
  @ObservationIgnored var regionRetouchPrepared: RegionRetouchEdit?
  @ObservationIgnored var regionRetouchTask: Task<Void,Never>?
  var cropShowPreview = true { didSet { cropRevision += 1 } }
  @ObservationIgnored var cropTask: Task<Void,Never>?
  var wholeLayerMovePreparation:@Sendable(CraftDocument,LayerMoveRequest)throws->Command = {_,request in .moveLayers(request)}
  var layerCollectionTransformPreparation:@Sendable(CraftDocument,LayerCollectionTransformRequest)throws->Command = {_,request in .transformLayers(request)}
  var channelTransformPreparation:@Sendable(CraftDocument,ChannelTransformRequest)throws->Command = {_,request in .transformChannel(request)}
  var pixelMaskTransformPreparation:@Sendable(CraftDocument,PixelMaskTransformRequest)throws->Command = {_,request in .transformPixelMask(request)}
  var selectedPixelMovePreparation:@Sendable(CraftDocument,SelectedPixelMoveRequest)throws->Command = {_,request in .movePixels(request)}
  var selectedPixelTransformPreparation:@Sendable(CraftDocument,SelectedPixelTransformRequest)throws->Command = {_,request in .transformPixels(request)}
  var selectionTransform:SelectionTransformSession?
  var selectionTransformPreparation:@Sendable(CraftDocument,ProjectiveTransform,Resampling)throws->Command = {try SelectionTransform.command(in:$0,projection:$1,interpolation:$2)}
  var transformDraft: TransformDraft?
  var embeddedPlacement: EmbeddedPlacementDraft?
  var embeddedPlacementSourceName: String?
  var embeddedPlacementIsPDF = false
  var rawPlacementWorkspace: RawPlacementWorkspace?
  @ObservationIgnored var rawPlacementWindow: RawPlacementWindow?
  @ObservationIgnored var rawPlacementPresenter: (@MainActor (RawPlacementWorkspace) -> Void)?
  var pdfPlacementWorkspace: PDFImportWorkspace?
  @ObservationIgnored var pdfPlacementWindow: PDFImportWindow?
  var pdfSourceEditors: [UUID:PDFSourceEditWorkspace] = [:]
  @ObservationIgnored var pdfSourceEditOperationID: UUID?
  @ObservationIgnored var pdfSourceEditRoot: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Photato/SourceEdits",isDirectory:true)
  @ObservationIgnored var pdfSourceOpener: @MainActor (URL) async throws -> Void = PDFSourceEditWorkspace.openInAssociatedEditor
  @ObservationIgnored var embeddedPlacementOperationID: UUID?
  @ObservationIgnored var pdfPlacementPresenter: (@MainActor (PDFImportWorkspace) -> Void)?
  var contentAwareScalePreview: CraftDocument?
  var contentAwareScaleReadyDraft: TransformDraft?
  var contentAwareScaleBusy = false
  var contentAwareScaleError: String?
  @ObservationIgnored var contentAwareScalePrepared: ContentAwareScaleEdit?
  @ObservationIgnored var contentAwareScaleTask: Task<Void,Never>?
  var fitImageDraft: FitImageDraft?
  var geometrySheet: GeometrySheetKind? {
    didSet { if geometrySheet != .fitImage { fitImageDraft = nil } }
  }
  @ObservationIgnored var foregroundDetector: any ForegroundDetecting = VisionForegroundDetector()
  var subjectSampleAllLayers = false
  var levelsDraft: LevelsDraft?
  var curvesDraft: CurvesDraft?
  var hueSaturationDraft: HueSaturationDraft?
  var colorLookupDraft: ColorLookupDraft?
  var classicAdjustmentDraft: ClassicAdjustmentDraft?
  var colorBalanceDraft: ColorBalanceDraft?
  var gradientMapDraft: GradientMapDraft?
  var filterDraft: FilterDraft?
  var filterRecall = FilterRecall()
  @ObservationIgnored var repeatFilterPreparation: @Sendable (CraftDocument, FilterRepeatRequest) throws -> Command = { try $1.command(in: $0) }
  var contentAwareDraft: ContentAwareWorkspace?
  var selectMaskDraft: SelectMaskWorkspace?
  var layerStyleDraft: LayerStyleDraft?
  static var copiedLayerStyle: LayerStyle?
  var tonalStepsDraft: TonalStepsDraft?
  var videoRenderID: UUID?
  var videoRenderWorker: Task<RenderedVideo, Error>?
  var variableExportID: UUID?
  var variableExportWorker: Task<ImageSequenceOutput, Error>?
  var sequenceExportID: UUID?
  var sequenceExportWorker: Task<ImageSequenceOutput, Error>?
  var animationExportID: UUID?
  var animationExportWorker: Task<Data, Error>?
  var geometryBusy = false
  var geometryTask: Task<Void, Never>?
  var paintPalette: PaintPalette
  var backgroundColor: Pixel {
    get { activePaintColorPair.background }
    set { var pair = activePaintColorPair; pair.background = newValue; activePaintColorPair = pair }
  }
  var colorTab: ColorPanelTab {
    get { workspaceLibrary.layout.colorTab }
    set { workspaceLibrary.selectPanel(WorkspacePanel(rawValue: newValue.rawValue)!) }
  }
  var propertiesTab: PropertiesTab {
    get { workspaceLibrary.layout.propertiesTab }
    set { workspaceLibrary.selectPanel(WorkspacePanel(rawValue: newValue.rawValue)!) }
  }
  var layersTab: LayersTab {
    get { workspaceLibrary.layout.layersTab }
    set { workspaceLibrary.selectPanel(WorkspacePanel(rawValue: newValue.rawValue)!) }
  }
  var inkTargets: Set<InkChannelTarget> = []
  var inkVisibility: Set<InkChannelTarget>?
  var inkChannelOptions: InkChannelOptionsDraft?
  var alphaEditingID: UUID?
  var alphaOverlay = false
  var savedChannelVisibility:SavedChannelVisibility?
  var temporaryMaskChannelVisibility:TemporaryMaskChannelVisibility?
  var channelVisibilitySweep:ChannelVisibilitySweep?
  // A retained Quick Mask can be visible while a different channel receives edits.
  var nonQuickMaskDocumentID: UUID?
  var nonQuickMaskID: UUID?
  // Visibility belongs to this temporary mask, independently of its edit target.
  var hiddenQuickMaskDocumentID: UUID?
  var hiddenQuickMaskID: UUID?
  @ObservationIgnored let quickMaskPreferences:QuickMaskPreferences
  var quickMaskOptions:ChannelDisplayOptions {
    get {quickMaskPreferences.value}
    set {try? quickMaskPreferences.set(newValue)}
  }
  var channelDialog: ChannelDialog?
  var modeComponentTargets: Set<Int> = []
  var modeComponentVisibility: Set<Int>?
  var componentTarget = RGBChannelPreview.composite
  var channelView = RGBChannelView() { didSet { if channelView != oldValue { render() } } }
  /// Legacy isolated-preview entry points. Combined visibility lives in channelView.
  var displayChannel: Int? {
    get { channelView.preview == .composite ? nil : channelView.preview.rawValue - 1 }
    set {
      channelView = RGBChannelView(
        preview: newValue.flatMap {
          (0...2).contains($0) ? RGBChannelPreview(rawValue: $0 + 1) : nil
        } ?? .composite)
    }
  }
  var fontName = "Helvetica Neue"
  var measuredZoom: Double = 1
  var viewportSize = CGSize(width: 900, height: 700)
  var viewportBackingScale: Double = 1
  private var localBrushRevision = 0
  var brushRevision: Int {
    get { localBrushRevision + paintPalette.revision }
    set { localBrushRevision = newValue - paintPalette.revision }
  }
  private var brushSettingsValue = Brush()
  var brush: Brush {
    get {
      var value = brushSettingsValue
      let pair = activePaintColorPair
      value.color = pair.foreground; value.backgroundColor = pair.background
      return value
    }
    set {
      var value = newValue
      value.backgroundColor = value.backgroundColor ?? backgroundColor
      guard value != brush else { return }
      brushSettingsValue = value; localBrushRevision += 1
      activePaintColorPair = PaintColorPair(foreground: value.color, background: value.backgroundColor ?? backgroundColor)
    }
  }
  var zoom: Double = 0  // Zero requests the initial fit, resolved by the first canvas layout.
  var pan = CGSize.zero {
    didSet { if pan != oldValue, document.width * document.height > Surface.maximumDensePixels { render() } }
  }
  var revision = 0
  // Rendering requests and API staleness advance before pixels are ready. The
  // canvas observes only accepted presentation changes, avoiding an old-frame draw.
  var canvasPresentationRevision = 0
  var error: String?
  var status = "Ready"
  var rendering = false
  var textSearchPreparation:@Sendable (CraftDocument,TextSearchSettings,UUID?,Int,Int,Int)throws->TextSearchResult = {try NativeTextSearch.scan($0,settings:$1,layerID:$2,start:$3,offset:$4,limit:$5)}
  var textFindWorkspace: TextFindWorkspace?
  var typeEditingDraft: TypeEditingDraft?
  var shapedTypeDraft:ShapedTypeWorkspace?
  var typeSelectionRevision = 0
  @ObservationIgnored weak var typeEditor: CanvasTypeEditor?
  var textDraft = "Your words here"
  var fontSize: Double = 72
  var prompt = ""
  var aiBusy = false
  var aiError: String?
  var showAI = false
  var showImagePlayground = false
  var coalescingChanges = false
  var layerOpacityDraft: LayerOpacityDraft?
  var coalescedDirty = false
  var onChange: ((NSDocument.ChangeType) -> Void)?
  var timelinePreviewVideoFrame: Int?
  var timelineVisible = false { didSet { if oldValue != timelineVisible { timelinePanelGeneration = UUID() } } }
  @ObservationIgnored private(set) var timelinePanelGeneration = UUID()
  var timelineTask: Task<Void, Never>?
  var timelineAudioPlayer: (any TimelineAudioPlaying)?
  var timelineAudioFactory: (Data) throws -> any TimelineAudioPlaying = { try NativeTimelineAudioPlayer(data:$0) }
  var timelineAudioPreparation: Task<Data?, Error>?
  var timelineAudioPreparing = false
  var timelineAudioImportID: UUID?
  var timelineAudioViewRevision = 0
  var selectedAudioTrackID: UUID? { didSet { if oldValue != selectedAudioTrackID { timelineAudioViewRevision &+= 1 } } }
  var selectedAudioClipID: UUID? { didSet { if oldValue != selectedAudioClipID { timelineAudioViewRevision &+= 1 } } }
  var showAudioControls = false { didSet { if oldValue != showAudioControls { timelineAudioViewRevision &+= 1 } } }

  var timelinePreviewFrameID: UUID?
  var timelinePlaybackSource: CraftDocument?
  var timelineThumbnailSource: CraftDocument?
  var timelineContentGeneration = 0
  var timelinePlaybackRenderCount = 0
  var timelinePlaybackRevision = UUID()
  var renderTask: Task<Void, Never>?
  var aiTask: Task<Void, Never>?
  var document: CraftDocument { session.document }
  var activeLayer: Layer? {
    if let layer = embeddedPlacement?.layer {return layer}
    guard let i = document.activeIndex else { return nil }
    let layer = document.layers[i]
    return smartFilterMaskEditing && maskEditingLayerID == layer.id ? (try? layer.filterMaskProjection()) ?? layer : layer
  }
  init(
    document: CraftDocument, clipboard: (any ClipboardAccess)? = nil,
    cloneState: CloneSources? = nil, patterns: PatternLibrary? = nil,
    gradients: GradientLibrary? = nil, actions: ActionLibrary? = nil, brushes: BrushLibrary? = nil, skies:SkyLibrary? = nil, shapes:ShapeLibrary? = nil,
    quickMaskPreferences:QuickMaskPreferences? = nil, paintPalette: PaintPalette? = nil,
    prepareHistory: @escaping HistoryPreparation = NativeHistoryNavigation.prepare
  ) {
    self.paintPalette = paintPalette ?? PaintPalette()
    self.quickMaskPreferences=quickMaskPreferences ?? .shared
    self.shapes = shapes ?? .shared
    self.actions = actions ?? .shared
    self.brushes = brushes ?? .shared
    self.skies = skies ?? .shared
    self.prepareHistory = prepareHistory
    self.cloneState = cloneState ?? .shared
    self.patterns = patterns ?? .shared
    self.gradients = gradients ?? .shared
    self.clipboard = clipboard ?? SystemClipboard.shared
    session = EditorSession(document: document)
    if document.isChannelOnly,document.quickMask == nil {alphaEditingID=document.alphaChannels?.first?.id}
    timelineVisible = document.animation != nil || document.videoTimeline != nil
    brush.settings = .init()
    brush.settings!.symmetry.center = .init(Double(document.width)/2,Double(document.height)/2)
    let library = self.gradients
    gradientOptions.gradient = library.selectedPreset?.gradient ?? .foregroundToBackground
    if let loading = library.loadTask {
      let initial = gradientOptions.gradient
      Task { [weak self] in
        await loading.value
        guard let self, self.gradientOptions.gradient == initial else { return }
        self.gradientOptions.gradient = library.selectedPreset?.gradient ?? initial
      }
    }
    render()
  }
  var videoTimelinePixelsPerSecond:Double = 60
  var videoSelectedTransitionID:UUID?
  var videoTransitionEditorVisible = false
  var videoTimelineGestureID:UUID?
  var moviePlacementID: UUID?
  func perform(_ command: Command) {
    finishNumericField()
    finishLayerName()
    guard !geometryBusy, !hasToneDraft else { return }
    guard transformDraft == nil else {
      error = "Apply or cancel Free Transform before another edit."
      return
    }
    do { try executeEditorCommand(command) } catch { self.error = error.localizedDescription }
  }
  /// Shared native/API transaction: history, dirty state, selection and rendering stay together.
  @ObservationIgnored var layerStackOrderPreparation: @Sendable (CraftDocument, LayerStackOrderRequest) async throws -> Command = { _, request in .stackLayers(request) }

  func executeEditorCommand(_ command: Command) throws {
    stopTimelinePlayback(render: false)
    guard historyOperation == nil else { throw HistoryNavigationConflict.busy }
    let command = try routeInkChannels(routeModeComponents(Self.routeChannel(command,target:editingChannel)))
    try validateQuickMaskVisibility(command)
    try validateComponentContext(command)
    let before = session.document
    try session.execute(routedMaskCommand(command))
    if let filter = command.filterRecallValue(in: before) { filterRecall.remember(filter) }
    if before != session.document {
      if before.activeLayerID != document.activeLayerID {
        selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? [])
      } else {
        selectedLayerIDs.formIntersection(Set(document.layers.map(\.id)))
      }
      if !coalescingChanges || !coalescedDirty { onChange?(.changeDone) }
      if coalescingChanges { coalescedDirty = true }
      render()
      status = command.label
    }
  }
  func coalesce(_ editing: Bool) {
    coalescingChanges = editing
    coalescedDirty = false
    if editing { session.beginCoalescing() } else { session.endCoalescing() }
  }
  func select(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
    finishNumericField()
    finishLayerName()
    guard canChangeLayerSelection, document.layers.contains(where: { $0.id == id }) else { return }
    var target = id
    if modifiers.contains(.shift), let active = document.activeIndex,
      let destination = document.layers.firstIndex(where: { $0.id == id })
    {
      selectedLayerIDs = Set(
        document.layers[min(active, destination)...max(active, destination)].map(\.id))
      if layerPanelFilter.isFiltering { selectedLayerIDs.formIntersection(Set(layersInPanel().map(\.id))) }
    } else if modifiers.contains(.command) {
      if selectedLayerIDs.isEmpty, let active = document.activeLayerID {
        selectedLayerIDs.insert(active)
      }
      if selectedLayerIDs.contains(id) {
        selectedLayerIDs.remove(id)
        if selectedLayerIDs.isEmpty { _ = deselectLayers(); return }
        target = document.activeLayerID.flatMap { selectedLayerIDs.contains($0) ? $0 : nil }
          ?? document.layers.reversed().first { selectedLayerIDs.contains($0.id) }!.id
      } else {
        selectedLayerIDs.insert(id)
      }
    } else {
      selectedLayerIDs = [id]
    }
    let wasAlpha = alphaEditingID != nil
    let changedMaskOwner = document.activeLayerID != target && !visibleTemporaryMaskChannels.isEmpty
    if document.activeLayerID != target {temporaryMaskChannelVisibility=nil}
    showColorChannelsKeepingAlphas()
    alphaEditingID = nil
    session.selectLayer(target)
    if case .vectorMask = pathTarget { selectPath(nil) }
    if case .shape = pathTarget { selectPath(nil) }
    maskEditingLayerID = nil
    smartFilterMaskEditing = false
    clearMaskView()
    if wasAlpha || changedMaskOwner { render() }
    invalidatePeopleIfNeeded()
    refreshObjectFinderIfNeeded()
  }
  @discardableResult func undo() async -> Bool {
    finishNumericField()
    finishLayerName()
    guard !geometryBusy, !hasToneDraft else { return false }
    if transformDraft != nil {
      cancelTransform()
      return true
    }
    let lifecycle = layerPanelGeneration
    do { return try await navigateHistory(redo: false) } catch is CancellationError {
      if layerPanelGeneration == lifecycle { status = "Undo cancelled" }
      return false
    } catch {
      if layerPanelGeneration == lifecycle { self.error = error.localizedDescription }
      return false
    }
  }
  @discardableResult func redo() async -> Bool {
    finishNumericField()
    finishLayerName()
    guard !geometryBusy, !hasToneDraft, transformDraft == nil else { return false }
    let lifecycle = layerPanelGeneration
    do { return try await navigateHistory(redo: true) } catch is CancellationError {
      if layerPanelGeneration == lifecycle { status = "Redo cancelled" }
      return false
    } catch {
      if layerPanelGeneration == lifecycle { self.error = error.localizedDescription }
      return false
    }
  }
  func render(isAnimationPlayback: Bool = false) {
    layerContentFilter.refreshIfNeeded(in: self)
    if let draft = layerOpacityDraft, !draft.matches(self) { layerOpacityDraft = nil }

    if let id = selectedAudioTrackID, document.videoTimeline?.audioTracks?.contains(where: { $0.id == id }) != true { selectedAudioTrackID = nil }
    if let id = selectedAudioClipID, document.videoTimeline?.audioTracks?.flatMap(\.clips).contains(where: { $0.id == id }) != true { selectedAudioClipID = nil }
    if let id = selectedAudioClipID, let owner = document.videoTimeline?.audioTracks?.first(where: { $0.clips.contains(where: { $0.id == id }) }), selectedAudioTrackID != owner.id { selectedAudioTrackID = owner.id }
    if document.videoTimeline == nil || (selectedAudioClipID == nil && (activeLayer?.video?.movie?.audioTracks ?? 0) == 0) { showAudioControls = false }
    if let id = videoSelectedTransitionID,
      document.videoTimeline?.transitions?.contains(where: { $0.id == id }) != true
    { videoSelectedTransitionID = nil }
    if document.videoTimeline == nil { videoTransitionEditorVisible = false }
    if isAnimationPlayback { timelinePlaybackRenderCount += 1 }
    if let source = timelinePlaybackSource, source != document { stopTimelinePlayback(render: false) }
    if timelineThumbnailSource != document { timelineThumbnailSource = document; timelineContentGeneration += 1 }
    invalidatePeopleIfNeeded()
    refreshObjectFinderIfNeeded()
    if let id = alphaEditingID, document.alphaChannels?.contains(where: { $0.id == id }) != true { alphaEditingID = nil }
    if document.isChannelOnly,document.quickMask == nil,alphaEditingID == nil {alphaEditingID=document.alphaChannels?.first?.id}
    if let draft = layerVisibilityDraft, draft.baseline != document { layerVisibilityDraft = nil }
    validateVisibilityIsolation()
    if let id = maskEditingLayerID,
      !document.layers.contains(where: { $0.id == id && (smartFilterMaskEditing ? $0.smartFilters?.mask != nil : $0.mask != nil) })
    {
      maskEditingLayerID = nil
    smartFilterMaskEditing = false
    }
    if currentMaskView == nil { clearMaskView() }
    let maskView = adjustmentBrushMaskView ?? currentMaskView
    renderTask?.cancel()
    revision += 1
    let request = revision
    let doc = previewDocument
    // The editing composition can strip video metadata. Ghosts need the retained
    // Timeline at the displayed playhead, while the current frame keeps its drafts.
    let onionSource: CraftDocument?
    if document.videoTimeline?.onionSkin?.enabled == true {
      if let frame = timelinePreviewVideoFrame { onionSource = try? document.videoDocument(at: frame) }
      else { onionSource = document }
    } else { onionSource = nil }
    let levels = levelsDraft
    let curves = curvesDraft
    let hueSaturation = hueSaturationDraft
    let lookup = colorLookupDraft
    let classic = classicAdjustmentDraft
    let colorBalance = colorBalanceDraft
    let filter = filterDraft
    let layerStyle = layerStyleDraft
    let tonalSteps = tonalStepsDraft
    let gradientMap = gradientMapDraft
    let clone = cloneDraft?.previewCommand
    let retouchPointCount = clone == nil ? 0 : cloneDraft?.points.count ?? 0
    let retouchPoints = cloneDraft?.points ?? []
    let interactiveRetouch = interactiveRetouchPreview
    let selectionTool = brushGesture.flatMap { $0.sessionGeneration==sessionGeneration && $0.generation==layerPanelGeneration ? $0.selectionRequest:nil }
    let selectionOverlay = tool == .selectionBrush ? selectionOverlayColor:nil
    let painting = brushPreviewCommand
    let paintTools = brushGesture.flatMap { $0.sessionGeneration==sessionGeneration && $0.generation==layerPanelGeneration ? $0.paintingPreviewRequest:nil }
    let gradientFill = gradientFillDraft.flatMap { $0.preview ? $0.command : nil }
    let gradientGesture = gradientGesture?.command
    let gradientStopColor = gradientStopColorDraft?.command
    let patternFill = patternFillDraft.flatMap { $0.preview ? $0.command : nil }
    let auxiliaryView = auxiliaryChannelView
    let auxiliaryPresentation = auxiliaryView.needsPresentation
    let channelView = channelView
    let modeVisibility = usesModeChannels ? modeComponentVisibility : nil
    let inkVisibility = document.inkMode != nil ? effectiveInkVisibility : nil
    let proof = effectiveProof
    let proofComposite = !auxiliaryPresentation && maskView == nil && channelView.visible.count == 3
      && (modeVisibility == nil || modeVisibility?.count == doc.colorMode.componentCount)
      && (inkVisibility == nil || inkVisibility?.count == doc.inkChannelTargets.count)
    let previous = renderSnapshot
    let interactiveBrush: InteractiveBrushPreview?
    if case .stroke? = painting { interactiveBrush = interactiveBrushPreview } else { interactiveBrush = nil }
    let brushPoints = brushGesture?.points ?? []
    let ordinaryDisplay = !auxiliaryPresentation && maskView == nil && modeVisibility == nil && inkVisibility == nil
      && channelView.visible.count == 3 && !proof.active && onionSource == nil
    // The previous image must have the same presentation semantics as its snapshot.
    let previousDisplay = ordinaryDisplay && ordinaryCanvasImage && previous != nil
      ? canvasRasterPreview ?? image.map { CanvasRasterPreview(base: $0) } : nil
    let displayScale = min(1, max(0.0001, viewport.resolvedZoom))
    let largeCanvas = doc.width * doc.height > Surface.maximumDensePixels ? viewport.largeCanvasRequest : nil
    rendering = true
    selectionPath = nil
    let renderStarted = ProcessInfo.processInfo.systemUptime
    let frameTraceToken = canvasFrameTrace?.beginFrame(samples: max(brushPoints.count, retouchPointCount), revision: request)
    renderTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        var doc = doc
        let presentation = try largeCanvas.map {
          try RasterPreviewRequest(region: $0.region, width: $0.width, height: $0.height)
        }
        if let layerStyle, layerStyle.preview, (try? layerStyle.style.validate(in: doc)) != nil {
          if !layerStyle.globalLightOnly {try Command.layerStyle([layerStyle.id], layerStyle.style).apply(to: &doc)}
          if let light=layerStyle.globalLight {try Command.globalLight(light).apply(to:&doc)}
        }
        if let filter, filter.preview, (try? filter.filter.validate()) != nil {
          try filter.command(in: doc).apply(to: &doc)
        }
        if let levels, levels.preview {
          try Command.applyAdjustment(levels.id, .levels(levels.levels)).apply(to: &doc)
        }
        if let curves, curves.preview {
          try Command.applyAdjustment(curves.id, .curves(curves.curves)).apply(to: &doc)
        }
        if let lookup, lookup.preview {
          try Command.applyAdjustment(lookup.id, .colorLookup(lookup.adjustment)).apply(to: &doc)
        }
        if let classic, classic.preview {
          try Command.applyAdjustment(classic.id, .classic(classic.adjustment)).apply(to: &doc)
        }
        if let colorBalance, colorBalance.preview {
          try Command.applyAdjustment(colorBalance.id, .colorBalance(colorBalance.adjustment))
            .apply(to: &doc)
        }
        if let hueSaturation, hueSaturation.preview {
          try Command.applyAdjustment(hueSaturation.id, .hueSaturation(hueSaturation.adjustment))
            .apply(to: &doc)
        }
        if let tonalSteps, tonalSteps.preview {
          try Command.applyAdjustment(tonalSteps.id, .tonalSteps(tonalSteps.adjustment)).apply(
            to: &doc)
        }
        if let gradientMap, gradientMap.preview {
          try Command.applyAdjustment(gradientMap.id, .gradientMap(gradientMap.adjustment)).apply(
            to: &doc)
        }
        let retouchSnapshot: RenderSnapshot?
        if clone != nil && selectionTool == nil && painting == nil && paintTools == nil
          && gradientFill == nil && gradientGesture == nil && gradientStopColor == nil && patternFill == nil {
          retouchSnapshot = try await interactiveRetouch?.snapshot(base: doc, points: retouchPoints, previous: previous)
        } else { retouchSnapshot = nil }
        if let retouchSnapshot { doc = retouchSnapshot.document }
        else if let clone { try clone.apply(to: &doc) }
        if let selectionTool {try await SelectionToolPreparation.command(selectionTool,in:doc).apply(to:&doc)}
        let brushSnapshot: RenderSnapshot?
        if paintTools == nil && gradientFill == nil && gradientGesture == nil && gradientStopColor == nil && patternFill == nil {
          brushSnapshot = try await interactiveBrush?.snapshot(base: doc, points: brushPoints, previous: previous)
        } else { brushSnapshot = nil }
        if let brushSnapshot { doc = brushSnapshot.document }
        else if let painting { try painting.apply(to: &doc) }
        if let paintTools { doc = try PaintingPreparation.prepare(paintTools,in:doc).result }
        if let gradientFill { try gradientFill.apply(to: &doc) }
        if let gradientGesture { try gradientGesture.apply(to: &doc) }
        if let gradientStopColor { try gradientStopColor.apply(to: &doc) }
        if let patternFill { try patternFill.apply(to: &doc) }
        let snapshot = try brushSnapshot ?? retouchSnapshot ?? Renderer.render(doc, reusing: previous)
        let displayComposite: Surface
        if proofComposite, let onionSource { displayComposite = try OnionSkinRenderer.render(onionSource, base: snapshot.surface) }
        else { displayComposite = snapshot.surface }
        let preview = try doc.inkMode != nil ? InkChannelPresentation.surface(doc, visible: inkVisibility) : modeVisibility.map { try ModeChannelPresentation.surface(doc, visible: $0) } ?? channelView.applying(to: displayComposite)
        let boundedPreview = try !auxiliaryPresentation ? presentation.map { try $0.reducing(preview) } : nil
        var canvasPreview = try largeCanvas == nil ? previousDisplay?.updating(snapshot, scale: displayScale) : nil
        var image = try canvasPreview?.base ?? (auxiliaryPresentation ? AuxiliaryChannelPresentation.image(preview,document:doc,view:auxiliaryView,colorManaged:!(inkVisibility != nil || modeVisibility != nil || channelView.visible.count == 1),request:presentation) : (inkVisibility != nil || modeVisibility != nil || channelView.visible.count == 1)
          ? RasterIO.displayImage(boundedPreview ?? preview) : ColorManagement.displayImage(boundedPreview ?? preview, in: doc))
        if let largeCanvas { canvasPreview = CanvasRasterPreview(base: image, documentRegion: largeCanvas.region) }
        else if ordinaryDisplay, canvasPreview == nil {
          canvasPreview = try CanvasRasterPreview(base: image).scaled(to: displayScale)
        }
        var proofFailure: String?
        if proof.active && proofComposite {
          do { image = try SoftProof.image(doc, composite: displayComposite, settings: proof) }
          catch is CancellationError { throw CancellationError() }
          catch { proofFailure = error.localizedDescription }
        }
        let path = try doc.selectionMask.map { try SelectionOutline.path($0,region:largeCanvas?.region,sampleStep:largeCanvas.map {max(1,($0.region.width+max(1,$0.width)-1)/max(1,$0.width),($0.region.height+max(1,$0.height)-1)/max(1,$0.height))} ?? 1) }
        let maskImage: CGImage?
        if let maskView, let layer = doc.layers.first(where: { $0.id == maskView.layerID }) {
          let maskLayer = maskView.smartFilter ? try layer.filterMaskProjection() : layer
          maskImage = try RasterIO.displayImage(presentation.map {
            try Renderer.maskPresentation(maskLayer, mode: maskView.mode, request: $0)
          } ?? Renderer.maskPresentation(maskLayer, mode: maskView.mode, width: doc.width, height: doc.height))
        } else {
          maskImage = nil
        }
        let overlay=try selectionOverlay.map{try SelectionToolPreparation.overlay(doc.coverageSelection(),color:$0,request:presentation)} ?? nil
        return (snapshot, image, path, maskImage,overlay,proofFailure,canvasPreview)
      }
      do {
        let pair = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, let self, self.revision == request else { return }
        self.renderSnapshot = pair.0
        self.surface = pair.0.surface
        self.image = pair.1
        self.canvasRasterPreview = pair.6
        self.ordinaryCanvasImage = ordinaryDisplay
        self.canvasFrameTrace?.prepared(frameTraceToken)
        if !brushPoints.isEmpty {
          self.brushPreviewFrameCount += 1
          self.brushPreviewSampleCount = brushPoints.count
          self.brushPreviewRenderMS = (ProcessInfo.processInfo.systemUptime - renderStarted) * 1000
        }
        if retouchPointCount > 0 {
          self.retouchPreviewFrameCount += 1
          self.retouchPreviewSampleCount = retouchPointCount
          self.retouchPreviewRenderMS = (ProcessInfo.processInfo.systemUptime - renderStarted) * 1000
        }
        self.proofDisplayError = pair.5
        self.selectionPath = pair.2?.path
        self.selectionOverlayImage = pair.4
        self.selectionOverlayRegion = largeCanvas?.region
        if (self.adjustmentBrushMaskView ?? self.currentMaskView) == maskView {
          self.maskViewImage = pair.3
          self.maskViewRegion = largeCanvas?.region
          self.renderedMaskView = maskView
        }
        self.rendering = false
        self.canvasPresentationRevision += 1
      } catch is CancellationError {} catch {
        guard let self, self.revision == request else { return }
        self.error = error.localizedDescription
        self.rendering = false
      }
    }
  }
  func groupSelection() {
    guard canCreateGroup(fromSelection: true) else { return }
    perform(.newGroup(.init(name: document.suggestedGroupName), children: Array(groupSelectionIDs)))
    finishGroupCreation()
  }
  func newGroup(below: Bool = false) {
    guard canCreateGroup(below: below) else { return }
    perform(.newGroup(.init(name: document.suggestedGroupName), below: below))
    finishGroupCreation()
  }
  func ungroup() { if let layer = activeLayer { perform(.ungroup(layer.id)) } }
  func toggleClipping() {
    if let layer = activeLayer { perform(.clipping(layer.id, !layer.isClipped)) }
  }
  func moveOutOfGroup(_ layer: Layer) {
    guard let parent = document.layers.first(where: { $0.id == layer.parentID }) else { return }
    let position = document.children(of: parent.parentID).firstIndex { $0.id == parent.id } ?? 0
    perform(.relocate(layer.id, parent.parentID, position + 1))
  }
  func addPixelLayer(below: Bool = false) {
    guard canCreatePixelLayer(below: below) else { return }
    perform(.newPixelLayer(.init(name: document.suggestedPixelLayerName), below: below))
    maskEditingLayerID = nil
    smartFilterMaskEditing = false
    selectPath(nil)
  }
  func addSolidColorLayer() {
    do {
      var layer = Layer(
        name: "Color Fill \(document.layers.count + 1)",
        content: .fill(Pixel(brush.color.r, brush.color.g, brush.color.b)))
      var mask = try Surface(
        width: document.width, height: document.height,
        depth: document.depth, fill: .white)
      if document.selection != nil {
        mask.mapPixels { x, y, _ in
          let value = document.selectionCoverage(x: x, y: y)
          return Pixel(value, value, value)
        }
      }
      layer.mask = mask
      perform(.addLayer(layer))
      propertiesTab = .properties
    } catch { self.error = error.localizedDescription }
  }
  func setSolidColor(_ id: UUID, color: Pixel) {
    guard let layer = document.layers.first(where: { $0.id == id }), case .fill = layer.content
    else { return }
    perform(.replaceContent(id, .fill(Pixel(color.r, color.g, color.b))))
  }
  func rasterize() {
    guard let id = activeLayer?.id else { return }
    performGeometry(label: "Rasterize Layer", prepare: { original in
      guard let layer = original.layers.first(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer unavailable.")
      }
      return try SmartObjectIO.rasterizationCommand(layer, in: original)
    })
  }
  func deleteLayer() {
    finishNumericField()
    finishLayerName()
    guard canBeginLayerCreation, LayerDeletion.canDelete(in: document, selected: groupSelectionIDs)
    else { return }
    perform(.deleteLayers(groupSelectionIDs))
  }
  func duplicateLayer() { if let l = activeLayer { perform(.duplicateLayer(l.id)) } }
  func adjustment(_ a: Adjustment, name: String) {
    perform(.addLayer(Layer(name: name, content: .adjustment(a))))
  }
  func selectMask(_ id: UUID) {
    guard canUseMaskThumbnail(id, kind: .pixel) else { return }
    let view = currentMaskView
    select(id)
    if activeLayer?.id == id, activeLayer?.mask != nil {
      componentTarget = .composite
      modeComponentTargets = []; modeComponentVisibility = nil
      maskEditingLayerID = id
      deselectQuickMaskTarget()
      render()
    }
    if view?.layerID == id {
      layerMaskView = view
      render()
    }
  }
  func stroke(_ points: [StrokePoint], brush: Brush) {
    if let channel=editingChannel {perform(.channel(.stroke(channel,points,brush)));return}
    if document.inkMode != nil, editingChannel == nil, !editingMask { perform(.inkChannel(.edit(effectiveInkTargets, .stroke(points, brush)))); return }
    guard let layer = activeLayer else { return }
    perform(editingMask ? .maskStroke(layer.id, points, brush) : .stroke(layer.id, points, brush))
  }
  func clear() {
    if let channel=editingChannel {perform(.channel(.fill(channel,1,1)));return}
    if document.inkMode != nil, editingChannel == nil, !editingMask { fill(color: .white); return }
    if let layer = activeLayer { perform(editingMask ? .maskFill(layer.id, 0) : layer.isBackground && !editingComponent ? .backgroundLayer(.clear(layer.id,backgroundColor)):.clear(layer.id)) }
  }
  func fill(color: Pixel? = nil, opacity: Float = 1) {
    let color = color ?? brush.color
    if let target=editingChannel {
      perform(.channel(.fill(target,unit(0.2126*color.r+0.7152*color.g+0.0722*color.b),unit(color.a*opacity))));return
    }
    if document.inkMode != nil, editingChannel == nil, !editingMask {
      guard canEditInkChannels else { return }
      perform(.inkChannel(.edit(effectiveInkTargets, .fill(unit(color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722), opacity * color.a))))
      return
    }
    if let target = editingChannel { perform(.channel(.fill(target,unit(0.2126*color.r+0.7152*color.g+0.0722*color.b),opacity))); return }
    if editingComponent {
      do {
        guard color.r == color.g, color.g == color.b, color.a.isFinite, (0...1).contains(color.a) else {
          throw CraftError.unsupported(
            "Component Fill currently supports neutral colors. Choose Black, 50% Gray or White."
          )
        }
        perform(try componentFillCommand(value: color.r, opacity: opacity*color.a))
      } catch { self.error = error.localizedDescription }
      return
    }
    guard let layer = activeLayer else { return }
    guard opacity == 1 else {
      error = "Composite and mask Fill currently require 100% opacity."
      return
    }
    if editingMask {
      let value = unit(0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b)
      perform(.maskFill(layer.id, value))
    } else {
      perform(.fill(layer.id, color))
    }
  }
  func updateMask(_ id: UUID, _ edit: (inout MaskProperties) -> Void) {
    guard let source = document.layers.first(where: { $0.id == id }) else { return }
    let layer = smartFilterMaskEditing && maskEditingLayerID == id ? (try? source.filterMaskProjection()) ?? source : source
    guard layer.mask != nil else { return }
    var properties = layer.effectiveMaskProperties
    edit(&properties)
    perform(.maskProperties(id, properties))
  }
  var canEditActiveMask: Bool {
    guard let layer = activeLayer else { return false }
    return !geometryBusy && transformDraft == nil && !document.isLocked(layer.id)
  }
  func canCreateMask(_ kind: LayerMaskCreation) -> Bool {
    guard !editingComponent, canEditActiveMask, let layer = activeLayer, layer.mask == nil else {
      return false
    }
    if kind == .fromTransparency {
      if case .raster = layer.content { return !document.isImageLocked(layer.id) }
      return false
    }
    return (kind != .revealSelection && kind != .hideSelection) || document.selection != nil
  }
  func createMask(_ kind: LayerMaskCreation) {
    guard canCreateMask(kind), let layer = activeLayer else { return }
    if kind == .fromTransparency {
      performGeometry(.createMask(layer.id, kind)) { [weak self] in
        self?.maskEditingLayerID = layer.id
      }
    } else {
      perform(.createMask(layer.id, kind))
      if activeLayer?.mask != nil { maskEditingLayerID = layer.id }
    }
  }
  func addMask(hiding: Bool = false) {
    let kind: LayerMaskCreation =
      document.selection == nil
      ? (hiding ? .hideAll : .revealAll) : (hiding ? .hideSelection : .revealSelection)
    createMask(kind)
  }
  func canApplyMask(_ layer: Layer) -> Bool {
    layer.smartObject == nil && layer.canApplyPixelMask && !document.isImageLocked(layer.id) && !geometryBusy
      && transformDraft == nil
  }
  func applyMask(_ requested: UUID? = nil) {
    guard let id = requested ?? activeLayer?.id,
      let layer = document.layers.first(where: { $0.id == id }), canApplyMask(layer)
    else { return }
    if !layer.effectiveMaskProperties.enabled {
      let alert = NSAlert()
      alert.messageText = "The layer mask is disabled."
      alert.informativeText = "Applying it will use the mask to change this layer’s transparency."
      alert.addButton(withTitle: "Apply Mask")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
    }
    performGeometry(.applyMask(id))
  }
  func deleteMask(_ requested: UUID? = nil) {
    guard let id = requested ?? activeLayer?.id else { return }
    perform(.deleteMask(id))
  }
  func cropToSelection() {
    if cropDraft != nil { commitCrop(); return }
    if let r = document.selection {
      let request = CropRequest(x:r.x,y:r.y,width:r.width,height:r.height)
      performGeometry(label:"Crop",prepare:{ document in .cropDocument(try CropPreparation.prepare(request,document:document)) })
    } else {
      error = "Draw a rectangular selection first, then choose Image → Crop to Selection."
    }
  }
  func placeImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .bmp, .gif]
    panel.canChooseDirectories = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      do {
        let imported = try RasterIO.read(url)
        guard var l = imported.layers.first, case .raster(let pixels) = l.content else { return }
        l.content = .raster(
          try ColorManagement.converted(pixels, from: imported, to: self.document))
        l.x = (self.document.width - imported.width) / 2
        l.y = (self.document.height - imported.height) / 2
        self.perform(.addLayer(l))
      } catch { self.error = error.localizedDescription }
    }
  }
  func exportImage() { beginImageExport() }
  func exportPSD() {
    do {
      let data = try PSDCodec.writeRasterLayers(document)
      let panel = NSSavePanel()
      panel.allowedContentTypes = [UTType(filenameExtension: "psd") ?? .data]
      panel.nameFieldStringValue = document.name + ".psd"
      panel.title = "Export Layers to PSD"
      panel.begin { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        do {
          try data.write(to: url, options: .atomic)
          self?.status = "Exported layered PSD"
        } catch { self?.error = error.localizedDescription }
      }
    } catch { self.error = error.localizedDescription }
  }
  func blur(radius: Double = 5) {
    guard canBeginFilterKind(.gaussianBlur), let id = activeLayer?.id else { return }
    var filter = RasterFilter(.gaussianBlur)
    filter.radius = radius
    performGeometry(.applyFilter(id, filter))
  }
  func refinePrompt() {
    guard !aiBusy else { return }
    aiBusy = true
    aiError = nil
    let input = prompt
    aiTask = Task { [weak self] in
      defer { self?.aiBusy = false }
      do {
        let p = try await LocalAI.refinePrompt(input)
        guard !Task.isCancelled else { return }
        self?.prompt = p
      } catch is CancellationError { self?.status = "Prompt refinement cancelled" } catch {
        self?.aiError = error.localizedDescription
      }
    }
  }
  func beginImageCreation(capability: AICapability = LocalAI.imageCapability) {
    do {
      prompt = try LocalAI.validatePrompt(prompt)
      guard capability.available else {
        throw LocalAIError.unavailable(capability.message)
      }
      aiError = nil
      showImagePlayground = true
    } catch { aiError = error.localizedDescription }
  }
  func acceptGeneratedImage(_ url: URL) {
    showImagePlayground = false
    do {
      let imported = try RasterIO.read(url)
      guard case .raster(var raster) = imported.layers.first?.content else {
        throw CraftError.invalid("The image model returned an unreadable image.")
      }
      raster = try ColorManagement.converted(raster, from: imported, to: document)
      if raster.width > document.width || raster.height > document.height {
        let factor = min(
          Double(document.width) / Double(raster.width),
          Double(document.height) / Double(raster.height))
        raster = try Renderer.resize(
          raster, width: max(1, Int(Double(raster.width) * factor)),
          height: max(1, Int(Double(raster.height) * factor)))
      }
      var layer = Layer(name: "Generated · \(prompt.prefix(32))", content: .raster(raster))
      layer.x = (document.width - raster.width) / 2
      layer.y = (document.height - raster.height) / 2
      perform(.addLayer(layer))
      status = "Created with Image Playground"
    } catch { aiError = error.localizedDescription }
  }
  func fit() { setZoom(viewport.fitZoom, center: true) }
  func chooseTool(_ item: WorkspaceTool) {
    if regionRetouchDraft != nil,item.native != tool,!commitRegionRetouch() { status = "Wait for the retouch preview, or cancel the edit."; return }
    if cropDraft != nil,item.native != .crop,!commitCrop() { status = "Wait for the crop preview, or cancel the crop."; return }
    if item.id != selectedTool.id { cancelClone() }
    if item.id != selectedTool.id { cancelGradientGesture() }
    if transformDraft != nil { commitTransform() }
    if let native = item.native { tool = native; if native == .crop { beginCrop() } } else { unavailableToolID = item.id }
    if let group = WorkspaceCatalog.groups.first(where: { $0.contains(item) }) {
      rememberedTools[group[0].id] = item.id
    }
    status = item.native == nil ? "\(item.title) is not available yet" : item.title
  }
  func chooseShortcut(_ key: String, cycle: Bool) -> Bool {
    guard
      let group = WorkspaceCatalog.groups.first(where: {
        $0.contains { !$0.shortcut.isEmpty && $0.shortcut.lowercased() == key }
      })
    else { return false }
    let shortcutTools = group.filter { $0.shortcut.lowercased() == key }
    if cycle, let index = shortcutTools.firstIndex(of: selectedTool) {
      chooseTool(shortcutTools[(index + 1) % shortcutTools.count])
    } else {
      chooseTool(group.first { $0.id == rememberedTools[group[0].id] } ?? group[0])
    }
    return true
  }
  func swapColors() {
    let pair = activePaintColorPair
    activePaintColorPair = PaintColorPair(foreground: pair.background, background: pair.foreground)
  }
  func resetColors() {
    activePaintColorPair=paintColorContext.defaults
  }
  var activeLayerSize: CGSize {
    if let b = activeLayerBounds { return CGSize(width: b.width, height: b.height) }
    guard let l = activeLayer else { return .zero }
    switch l.content {
    case .raster(let s): return CGSize(width: s.width, height: s.height)
    case .shape(let s): return CGSize(width: s.width, height: s.height)
    case .text: return CGSize(width: document.width, height: document.height)
    default: return CGSize(width: document.width, height: document.height)
    }
  }
  func autoSelectLayer(at point: CGPoint) {
    guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000
    else { return }
    for l in document.layers.reversed() where !l.isGroup && document.isVisible(l.id) {
      let color: Pixel
      if case .gradientFill = l.content {
        guard
          let sample = try? Renderer.gradientPixel(
            l, in: document,
            x: Int(floor(point.x)), y: Int(floor(point.y)))
        else { continue }
        color = sample
      } else if case .patternFill(let fill) = l.content {
        guard
          let sample = try? Renderer.patternPixel(
            fill, in: document,
            x: Int(floor(point.x)), y: Int(floor(point.y)))
        else { continue }
        color = sample
      } else {
        // Imported Smart appearance is already in document coordinates. Hit the
        // same derived layer shown on canvas, including projective placement.
        let displayed:Layer
        if l.importedSmartAppearance != nil || l.sourceProjection != nil {
          guard let prepared=try? SmartFilterEngine.renderedLayer(l,in:document) else{continue};displayed=prepared
        }else{displayed=l}
        guard let raster = try? Renderer.layerSurface(displayed, in: document),
          let inverse = try? displayed.coordinateTransform.inverted()
        else { continue }
        let local = inverse.point(point.x, point.y)
        color =
          l.isCanvasFill
          ? raster.pixel(x: Int(floor(point.x)), y: Int(floor(point.y)))
          : raster.pixel(x: Int(floor(local.x)), y: Int(floor(local.y)))
      }
      let mask = try? LayerMaskSampler.make(layer: l, document: document)
      var alpha =
        color.a * l.opacity * (mask?.coverage(x: Double(point.x), y: Double(point.y)) ?? 1)
      for node in [l] + document.ancestors(of: l.id) {
        if node.id != l.id {
          let sampler = try? LayerMaskSampler.make(layer: node, document: document)
          alpha *= node.opacity * (sampler?.coverage(x: point.x, y: point.y) ?? 1)
        }
        if node.isClipped {
          guard let base = document.clippingBase(for: node.id), document.isVisible(base.id),
            let pixels = try? Renderer.clippingCoverage(base, in: document)
          else {
            alpha = 0
            break
          }
          alpha *= pixels.pixel(x: Int(floor(point.x)), y: Int(floor(point.y))).a * base.opacity
        }
      }
      if alpha > 0.01 {
        select(l.id)
        return
      }
    }
  }
}
