import Foundation

public enum Command: Sendable {
  case layerStyles(LayerStyleEdit)
  case globalLight(GlobalLight)
  indirect case variables(VariableCommand)
  case video(VideoCommand)
  case animation(AnimationCommand)
  case documentMode(DocumentModeConversion)
  case preparedColorProfile(ColorProfileEdit)
  case preparedDocumentMode(DocumentModeEdit)
  case channelArithmetic(ChannelArithmeticEdit)
  case linkedSmartObject(LinkedSmartObjectEdit)
  case modeChannel(ModeChannelEdit)
  case modeComponents(ModeComponentEdit)
  indirect case toneAdjustment(ClassicToneRequest)
  case hdrToning(HDRToningEdit)
  indirect case proceduralRender(ProceduralRenderRequest)
  case maskAllObjects(MaskAllObjectsEdit)
  case skyReplacement(SkyReplacementEdit)
  indirect case adjustmentBrush(AdjustmentBrushRequest)
  indirect case painting(PaintingEdit)
  case documentMetadata([String: Data]?)
  case layerComp(LayerCompCommand)
  case guides(GuideCommand)
  case artboard(ArtboardCommand)
  case frame(FrameCommand)
  indirect case shape(ShapeCommand)
  case action(RecordedAction, limits: ActionPlaybackLimits? = nil)
  case canvasEdges(CanvasEdgesEdit)
  case flattenImage(FlattenImageEdit)
  case preparedAction(PreparedActionEdit)
  case channel(ChannelCommand)
  case inkChannel(InkChannelCommand)
  case addLayer(Layer)
  case newPixelLayer(NewPixelLayerOptions, below: Bool = false)
  case newGroup(NewLayerGroupOptions, children: [UUID] = [], below: Bool = false)
  case addGradientFill(Layer, Bool = false)
  case setGradientFill(UUID, GradientFill)
  case addPatternFill(Layer, RasterPattern, Bool = false)
  case setPatternFill(UUID, PatternFill, RasterPattern?)
  case paste(ClipboardContent, PastePlacement, PathPoint?)
  case cut([UUID], background: Pixel? = nil)
  case layerVia(UUID, LayerViaOperation)
  case mergeLayers(Set<UUID>, LayerMergeOperation)
  case preparedLayerMerge(PreparedLayerMerge)
  case deleteLayer(UUID)
  case deleteLayers(Set<UUID>)
  case duplicateLayer(UUID)
  case duplicateLayers(Set<UUID>, name: String? = nil)
  case duplicateLayersFrom(CraftDocument, Set<UUID>, name: String? = nil)
  case renameLayer(UUID, String)
  case layerColor(Set<UUID>, LayerColorLabel)
  case layerVisibility([UUID: Bool])
  case visibility(UUID, Bool)
  case lock(UUID, Bool)
  case protection([UUID: LayerProtection])
  case opacity(UUID, Float)
  case blend(UUID, BlendMode)
  case move(UUID, Int, Int)
  case layoutLayers([LayerTranslation], LayerLayoutOperation)
  case stackLayers(LayerStackOrderRequest)
  case reorder(UUID, Int)
  case relocate(UUID, UUID?, Int)
  case groupLayers([UUID], String)
  case ungroup(UUID)
  case groupProperties(UUID, GroupContent)
  case clipping(UUID, Bool)
  case blendClippedAsGroup(UUID, Bool)
  case replaceContent(UUID, LayerContent)
  case editType(UUID, TextContent, originDelta: PathPoint)
  case importedType(ImportedTypeTransition)
  case rasterize(UUID, Surface)
  case embedSmartObject(Set<UUID>, Layer)
  case replaceSmartObject(UUID, SmartObject, Surface, preserveSize: Bool, allInstances: Bool, instancePixels: [UUID: Surface] = [:])
  case smartObjectStack(UUID, ImageStackMode?, Surface)
  case independentSmartObjectCopy(UUID)
  case resetSmartObjectTransform(UUID)
  case mask(UUID, Surface?)
  case createMask(UUID, LayerMaskCreation)
  case applyMask(UUID)
  case deleteMask(UUID)
  case maskProperties(UUID, MaskProperties)
  case vectorMask(UUID, VectorMask?)
  case savePath(NamedPath)
  case deletePath(UUID)
  case selection(IntRect?)
  case selectShape(SelectionShape, SelectionMode, Bool, Double)
  case selectionCoverage(SelectionMask?, SelectionMode)
  case colorRange(SelectionMask)
  case magneticSelection(SelectionMask,SelectionMode)
  case modifiedSelection(SelectionMask,SelectionModification.Kind)
  case reselectedSelection(SelectionMask)
  case transformedSelection(SelectionMask)
  case pixelPaint(PixelPaintRequest)
  case layerLinks(LayerLinkCommand)
  case moveLayers(LayerMoveRequest)
  case transformLayers(LayerCollectionTransformRequest)
  case transformChannel(ChannelTransformRequest)
  case transformPixelMask(PixelMaskTransformRequest)
  case transformPixels(SelectedPixelTransformRequest)
  case movePixels(SelectedPixelMoveRequest)
  case backgroundLayer(BackgroundLayerEdit)
  case photoAlign(PhotoAlignEdit)
  case photoBlend(PhotoBlendEdit)
  case regionRetouch(RegionRetouchEdit)
  case contentAwareFill(ContentAwareEdit)
  case vanishingPoint(VanishingEdit)
  case warp(WarpEdit)
  case contentAwareScale(ContentAwareScaleEdit)
  case focusArea(SelectionRefinementEdit)
  case selectionRefinement(SelectionRefinementEdit)
  case selectSubject(SelectionMask, SelectionMode)
  case removeBackground(UUID, SelectionMask)
  case magicWand(CloneSample, PathPoint, ColorMatchOptions, SelectionMode, Bool)
  case paintBucket(UUID, BucketFill)
  case paintGradient(UUID, GradientStroke)
  case invertSelection
  case featherSelection(Double)
  case healingBrush(UUID, HealingStroke)
  case focus(UUID, FocusStroke)
  case toning(UUID, ToningStroke)
  case spotHealing(UUID, SpotHealingStroke)
  case cloneStamp(UUID, CloneStroke)
  case stroke(UUID, [StrokePoint], Brush)
  case maskStroke(UUID, [StrokePoint], Brush)
  case maskFill(UUID, Float)
  case invertMask(UUID)
  case clear(UUID)
  case fill(UUID, Pixel)
  case fillComponents(UUID, RGBComponentFill)
  case layerStyle(Set<UUID>, LayerStyle?)
  case smartFilters(UUID, SmartFilterStack?)
  indirect case smartFilterMask(UUID, Command)
  case applyFilter(UUID, RasterFilter)
  case applyAdjustment(UUID, Adjustment)
  case desaturate(UUID)
  case autoCorrection(UUID, AutoCorrection)
  case crop(IntRect)
  case cropDocument(CropEdit)
  case flip(UUID, Bool)
  case transform(UUID, Transform2D, Resampling)
  case canvasSize(Int, Int, CanvasAnchor, Pixel?)
  case imageSize(Int, Int, Double, Resampling)
  case fitImage(FitImageOptions)
  case resolution(Double)
  case rotateCanvas(CanvasTurn)
  public var label: String {
    switch self {
    case .layerStyles:"Layer Style"
    case .globalLight:"Global Light"
    case .documentMetadata: "File Info"
    case .layerComp(let command): command.label
    case .variables(let command): command.label
    case .video(let command): command.label
    case .animation(let command): command.label
    case .toneAdjustment(let request):request.settings.kind.title
    case .hdrToning:"HDR Toning"
    case .documentMode(let request):request.mode.title
    case .preparedColorProfile(let edit):edit.title
    case .preparedDocumentMode(let edit):edit.title
    case .linkedSmartObject(let edit):edit.title
    case .channelArithmetic(let edit):edit.title
    case .modeChannel:"Edit Color Channel"
    case .modeComponents(let edit):edit.label
    case .proceduralRender(let request):request.settings.kind.title
    case .maskAllObjects: "Mask All Objects"
    case .skyReplacement: "Sky Replacement"
    case .adjustmentBrush: "Adjustment Brush"
    case .painting(let edit): edit.label
    case .frame(let command): command.label
    case .shape(let command): command.label
    case .guides(let command): command.label
    case .artboard(let command): command.label
    case .action(let action, _): "Play \(action.name)"
    case .canvasEdges(let edit): edit.operation.label
    case .flattenImage: "Flatten Image"
    case .preparedAction(let edit): edit.title
    case .channel(let value): value.label
    case .inkChannel(let value): value.label
    case .addLayer, .newPixelLayer: "New Layer"
    case .newGroup(_, let children, _): children.isEmpty ? "New Group" : "Group Layers"
    case .addGradientFill: "New Gradient Fill Layer"
    case .setGradientFill: "Gradient Fill"
    case .addPatternFill: "New Pattern Fill Layer"
    case .setPatternFill: "Pattern Fill"
    case .paste(_, let placement, _):
      placement == .into
        ? "Paste Into"
        : placement == .outside
          ? "Paste Outside" : placement == .inPlace ? "Paste in Place" : "Paste"
    case .cut: "Cut"
    case .layerVia(_, let operation): operation.rawValue
    case .mergeLayers(_, let operation): operation.rawValue
    case .preparedLayerMerge(let edit): edit.operation.rawValue
    case .deleteLayer: "Delete Layer"
    case .deleteLayers(let ids): ids.count == 1 ? "Delete Layer" : "Delete Layers"
    case .duplicateLayer: "Duplicate Layer"
    case .duplicateLayers(let ids, _), .duplicateLayersFrom(_, let ids, _):
      ids.count == 1 ? "Duplicate Layer" : "Duplicate Layers"
    case .renameLayer: "Rename Layer"
    case .layerColor: "Layer Color"
    case .visibility, .layerVisibility: "Layer Visibility"
    case .lock: "Lock Layer"
    case .protection: "Lock Layers"
    case .opacity: "Layer Opacity"
    case .blend: "Blend Mode"
    case .move: "Move Layer"
    case .layoutLayers(_, let operation): operation.label
    case .stackLayers(let request): request.operation.title
    case .reorder, .relocate: "Arrange Layer"
    case .groupLayers: "Group Layers"
    case .ungroup: "Ungroup Layers"
    case .groupProperties: "Group Properties"
    case .clipping(_, let value): value ? "Create Clipping Mask" : "Release Clipping Mask"
    case .blendClippedAsGroup: "Blend Clipped Layers As Group"
    case .replaceContent(_, .adjustment(.levels)): "Levels"
    case .replaceContent(_, .adjustment(.curves)): "Curves"
    case .replaceContent(_, .adjustment(.hueSaturation)): "Hue/Saturation"
    case .replaceContent(_, .adjustment(.colorLookup)): "Color Lookup"
    case .replaceContent(_, .adjustment(.classic(let value))): value.kind.title
    case .replaceContent(_, .adjustment(.colorBalance)): "Color Balance"
    case .replaceContent: "Edit Layer"
    case .editType,.importedType: "Edit Type"
    case .rasterize: "Rasterize Layer"
    case .embedSmartObject: "Convert to Smart Object"
    case .smartObjectStack(_, let mode, _): "Stack Mode: " + (mode?.title ?? "None")
    case .replaceSmartObject(_,let source,_,_,_,_): source.rawDevelopment == nil ? "Replace Smart Object Contents" : "Develop RAW Source"
    case .independentSmartObjectCopy: "New Smart Object via Copy"
    case .resetSmartObjectTransform: "Reset Smart Object Transform"
    case .mask: "Layer Mask"
    case .createMask(_, let kind):
      kind == .fromTransparency ? "From Transparency" : "Add Layer Mask"
    case .applyMask: "Apply Layer Mask"
    case .deleteMask: "Delete Layer Mask"
    case .maskProperties: "Mask Properties"
    case .vectorMask: "Vector Mask"
    case .savePath: "Edit Path"
    case .deletePath: "Delete Path"
    case .selection, .selectShape, .selectionCoverage: "Selection"
    case .colorRange: "Color Range"
    case .magneticSelection: "Magnetic Lasso"
    case .modifiedSelection(_,let kind): "\(kind.title) Selection"
    case .reselectedSelection: "Reselect"
    case .transformedSelection: "Transform Selection"
    case .pixelPaint(let request):request.kind.title
    case .layerLinks(let command):command.label
    case .moveLayers:"Move"
    case .transformLayers: "Free Transform"
    case .transformChannel: "Free Transform"
    case .transformPixelMask: "Free Transform"
    case .transformPixels: "Free Transform"
    case .movePixels: "Move"
    case .backgroundLayer(let edit):edit.label
    case .photoAlign: "Auto-Align Layers"
    case .photoBlend: "Auto-Blend Layers"
    case .regionRetouch(let edit): edit.label
    case .contentAwareFill: "Content-Aware Fill"
    case .vanishingPoint: "Vanishing Point"
    case .warp: "Warp"
    case .contentAwareScale: "Content-Aware Scale"
    case .focusArea: "Focus Area"
    case .selectionRefinement: "Select and Mask"
    case .selectSubject: "Select Subject"
    case .removeBackground: "Remove Background"
    case .magicWand: "Magic Wand"
    case .paintBucket: "Paint Bucket"
    case .paintGradient: "Gradient"
    case .invertSelection: "Inverse Selection"
    case .featherSelection: "Feather Selection"
    case .healingBrush: "Healing Brush"
    case .focus(_, let stroke): stroke.tool.rawValue + " Tool"
    case .toning(_, let stroke): stroke.tool.rawValue + " Tool"
    case .spotHealing: "Spot Healing Brush"
    case .cloneStamp: "Clone Stamp"
    case .stroke(_, _, let b): b.erase ? "Eraser" : "Brush"
    case .maskStroke: "Brush on Layer Mask"
    case .maskFill: "Fill Layer Mask"
    case .invertMask: "Invert Layer Mask"
    case .clear: "Clear"
    case .fill, .fillComponents: "Fill"
    case .layerStyle(_, let style): style == nil ? "Clear Layer Style" : "Layer Style"
    case .smartFilters: "Smart Filters"
    case .smartFilterMask(_, let command): "Smart Filter Mask: " + command.label
    case .applyFilter(_, let filter): filter.kind.title
    case .applyAdjustment(_, .levels): "Levels"
    case .applyAdjustment(_, .curves): "Curves"
    case .applyAdjustment(_, .hueSaturation): "Hue/Saturation"
    case .applyAdjustment(_, .colorLookup): "Color Lookup"
    case .applyAdjustment(_, .classic(let value)): value.kind.title
    case .applyAdjustment(_, .modern(let value)): value.kind.title
    case .applyAdjustment(_, .colorBalance): "Color Balance"
    case .applyAdjustment(_, .gradientMap): "Gradient Map"
    case .applyAdjustment(_, .tonalSteps(let settings)): settings.kind.rawValue
    case .applyAdjustment(_, .invert): "Invert"
    case .desaturate: "Desaturate"
    case .autoCorrection(_, let kind): kind.rawValue
    case .applyAdjustment: "Adjustment"
    case .crop: "Crop"
    case .cropDocument: "Crop"
    case .flip: "Flip Layer"
    case .transform: "Free Transform"
    case .canvasSize: "Canvas Size"
    case .imageSize: "Image Size"
    case .fitImage: "Fit Image"
    case .resolution: "Image Resolution"
    case .rotateCanvas: "Image Rotation"
    }
  }
  public func apply(to d: inout CraftDocument) throws {
    if case .fitImage(let options) = self { try options.apply(to: &d); return }
    let linkEdit:Bool;switch self{case .pixelPaint,.layerLinks,.moveLayers:linkEdit=true;default:linkEdit=false}
    if linkEdit || d.requiresLayerLinkArchive || d.restrictedMode != nil || d.inkMode != nil || d.animation != nil || d.videoTimeline != nil || d.variables != nil || d.layerComps != nil || d.requiresSmartObjectLayerCompArchive {
      // A layer/geometry operation may be rejected by restricted-mode invariants.
      // Keep direct Command callers just as atomic as EditorSession/PreparedEdit.
      var candidate = d; try applyValidated(to: &candidate); d = candidate
    } else { try applyValidated(to: &d) }
  }
  private func applyValidated(to d: inout CraftDocument) throws {
    let originalLayerIDs=Set(d.layers.map(\.id))
    let variableSource = d.variables == nil ? nil : d
    let hadAnimation = d.animation != nil
    let hadVideo = d.videoTimeline != nil
    let hadComps = d.layerComps != nil
    try validateVideoContext(in: d)
    try validateAnimationContext(in: d)
    try validateProtection(in:d)
    if d.inkMode != nil, try InkModeGeometry.apply(self, to: &d) { try d.validate(); return }
    if d.restrictedMode != nil, try RestrictedModeGeometry.apply(self, to: &d) { try d.validate(); return }
    let modeBefore = d.hasAuthoritativeModeStorage ? d : nil
    // Keep nested modular commands off the large primitive-switch stack frame.
    // Frame wrapping and live-shape creation can invoke another native command.
    switch self {
    case .layerComp(let command): try command.apply(to: &d)
    case .variables(let command): try command.apply(to: &d)
    case .video(let command): try command.apply(to: &d)
    case .animation(let command):try command.apply(to: &d)
    case .documentMode(let request):d=try d.convertingMode(request)
    case .preparedColorProfile(let edit):d=try edit.applied(to:d)
    case .preparedDocumentMode(let edit):d=try edit.applied(to:d)
    case .linkedSmartObject(let edit):d=try edit.applied(to:d)
    case .channelArithmetic(let edit):d=try edit.applied(to:d)
    case .modeChannel(let edit):try d.editModeChannel(edit)
    case .modeComponents(let edit):try edit.apply(to:&d)
    case .frame(let command):try command.apply(to:&d)
    case .shape(let command):try command.apply(to:&d)
    case .guides(let command):try command.apply(to:&d)
    case .artboard(let command):try command.apply(to:&d)
    case .action(let action,let limits):try action.apply(to:&d,validate:{try limits?.validate($0)})
    case .canvasEdges(let edit): d = try edit.applied(to:d)
    case .flattenImage(let edit): d = try edit.applied(to: d)
    case .preparedLayerMerge(let edit): d = try edit.applied(to:d)
    case .preparedAction(let edit): d = try edit.applied(to: d)
    case .channel(let command):try command.apply(to:&d)
    case .inkChannel(let command):try command.apply(to:&d)
    case .smartFilterMask(let id,let command):try SmartFilterEngine.editMask(command,on:id,in:&d)
    case .applyAdjustment(let id,let adjustment):try PixelCommandEngine.adjust(id,adjustment,in:&d)
    case .applyFilter(let id,let filter):try PixelCommandEngine.filter(id,filter,in:&d)
    case .smartFilters(let id,let stack):try PixelCommandEngine.stack(id,stack,in:&d)
    case .mergeLayers,.addGradientFill,.addPatternFill,.independentSmartObjectCopy,.autoCorrection,.desaturate:try applyNestedPrimitive(to:&d)
    default:try applyPrimitive(to:&d)
    }
    if hadComps, d.layerComps == nil {
      if case .layerComp(.clear) = self {} else { throw CraftError.unsupported("This operation would discard Layer Comps. Export a still copy or clear the comps explicitly first.") }
    }
    if hadAnimation, d.animation == nil {
      if case .animation(.remove) = self {} else if case .animation(.convertToVideo) = self {} else if case .animation(.restoreVideoSource)=self {} else {
        throw CraftError.unsupported("This operation would discard the animation. Keep the animated original and prepare a still copy first.")
      }
    }
    if hadVideo, d.videoTimeline == nil {if case .video(.remove)=self {} else if case .animation(.convertFromVideo)=self {} else {throw CraftError.unsupported("This operation would discard the video Timeline.")}}
    if case .video = self {} else { try d.captureVideoChanges() }
    if case .animation = self {} else { try d.captureAnimationChanges() }
    if d.videoTimeline != nil { try d.reflowVideoGroups(); try d.refreshVideoDuration(); d.reconcileVideoTransitions() }
    if let variableSource {
      if case .variables = self {} else { try d.reconcileVariables(after: self, before: variableSource) }
    }
    let added=Set(d.layers.map(\.id)).subtracting(originalLayerIDs);if !added.isEmpty{if case .paste=self{LayerLinks.independentCopies(in:&d,layerIDs:added)}}
    LayerLinks.prune(in:&d)
    try d.fitArtboardCanvas()
    if let modeBefore { try d.reconcileModeStorage(from:modeBefore) }
    try d.validate()
  }
  // Bound command frames: nested validated edits run on cooperative worker stacks.
  @inline(never)
  private func applyPrimitive(to d:inout CraftDocument)throws {
    switch self {
    case .backgroundLayer(let edit):try BackgroundLayer.apply(edit,to:&d)
    case .pixelPaint(let request):try PixelFillStroke.apply(request,to:&d)
    case .layerLinks(let command):guard d.animation==nil,d.videoTimeline==nil else{throw CraftError.unsupported("Layer-link editing in Timeline documents requires further qualification.")};try LayerLinks.apply(command,to:&d)
    case .moveLayers(let request):_ = try LayerCollectionTransform.members(d,layerIDs:request.layerIDs);try LayerLinks.move(request,in:&d)
    case .transformLayers(let request):try LayerCollectionTransform.apply(request,to:&d)
    case .transformChannel(let request):try ChannelTransform.apply(request,to:&d)
    case .transformPixelMask(let request):try PixelMaskTransform.apply(request,to:&d)
    case .transformPixels(let request):try SelectedPixelTransform.apply(request,to:&d)
    case .movePixels(let request):try SelectedPixelTransform.apply(request.transform(),to:&d)
    case .layerStyles(let edit):try edit.apply(to:&d)
    case .globalLight(let value):try value.validate();d.globalLight=value
    case .documentMetadata(let value):
      guard (value?.count ?? 0) <= 4096,
        value?.keys.allSatisfy({ $0.utf8.count <= 4096 }) ?? true,
        (value?.values.reduce(0, { $0 + $1.count }) ?? 0) <= NativeArchive.maximumBytes else {
        throw CraftError.invalid("Document metadata exceeds the native limit.")
      }
      d.sourceMetadata = value
    case .linkedSmartObject,.channelArithmetic,.mergeLayers,.applyAdjustment,.applyFilter,.smartFilters: throw CraftError.invalid("Unexpected nested command routing.")
    case .toneAdjustment(let request):try ClassicToneEngine.apply(request,to:&d)
    case .hdrToning(let edit):d=try edit.applied(to:d)
    case .proceduralRender(let request):try ProceduralRenderEngine.apply(request,to:&d)
    case .fitImage,.preparedLayerMerge,.canvasEdges,.flattenImage,.layerComp,.guides,.variables,.addGradientFill,.addPatternFill,.independentSmartObjectCopy,.autoCorrection,.desaturate,.video, .animation,.frame,.shape,.artboard,.action,.preparedAction,.channel,.inkChannel,.smartFilterMask,.documentMode,.preparedDocumentMode,.preparedColorProfile,.modeChannel,.modeComponents:throw CraftError.invalid("Unexpected modular command routing.")
    case .paste,.layerVia,.cut,.setGradientFill,.setPatternFill: try applyClipboardPrimitive(to:&d)
    case .addLayer,.newPixelLayer,.deleteLayers,.deleteLayer,.duplicateLayer,.duplicateLayers,.duplicateLayersFrom,.renameLayer,.layerColor,.layerVisibility,.visibility,.lock,.protection: try applyLayerStructurePrimitive(to:&d)
    case .opacity,.blend,.layoutLayers,.move,.stackLayers,.reorder,.relocate,.groupLayers,.newGroup,.ungroup,.groupProperties,.clipping,.blendClippedAsGroup: try applyLayerPropertiesPrimitive(to:&d)
    case .importedType,.editType,.replaceContent,.rasterize,.embedSmartObject,.smartObjectStack,.replaceSmartObject,.resetSmartObjectTransform: try applyLayerContentPrimitive(to:&d)
    case .mask,.createMask,.applyMask,.deleteMask,.maskProperties,.vectorMask,.savePath,.deletePath,.selection,.selectShape,.selectionCoverage,.colorRange,.magneticSelection,.modifiedSelection,.reselectedSelection,.transformedSelection: try applyMaskPathPrimitive(to:&d)
    case .vanishingPoint,.maskAllObjects,.skyReplacement,.warp,.contentAwareScale,.photoAlign,.photoBlend,.adjustmentBrush,.painting,.regionRetouch,.contentAwareFill,.selectionRefinement,.focusArea,.selectSubject,.removeBackground: try applyPreparedRasterPrimitive(to:&d)
    case .magicWand,.paintBucket,.paintGradient,.invertSelection,.featherSelection,.maskStroke,.maskFill,.invertMask,.focus,.toning,.spotHealing,.healingBrush,.cloneStamp,.stroke,.clear,.fill,.fillComponents: try applyPaintingPrimitive(to:&d)
    case .layerStyle,.cropDocument,.crop,.flip,.transform,.resolution,.canvasSize,.imageSize,.rotateCanvas: try applyGeometryPrimitive(to:&d)
    }
  }
}
public struct HistoryEntry: Sendable {
  public let id: UUID
  public var label: String
  private enum Storage: Sendable {
    case resident(CraftDocument)
    case scratch(HistorySnapshot)
  }
  private var storage: Storage
  public init(label: String, document: CraftDocument, id: UUID = UUID()) {
    self.id = id
    self.label = label
    storage = .resident(document)
  }
  public var isOnDisk: Bool {
    if case .scratch = storage { return true }
    return false
  }
  var residentDocument: CraftDocument? {
    if case .resident(let document) = storage { return document }
    return nil
  }
  public func restoredDocument() throws -> CraftDocument {
    switch storage {
    case .resident(let document): return document
    case .scratch(let snapshot): return try snapshot.restore()
    }
  }
  func restoredDocument(reusing tiles: HistoryDecodedTiles?) throws
    -> (document: CraftDocument, tiles: HistoryDecodedTiles?)
  {
    switch storage {
    case .resident(let document): return (document, nil)
    case .scratch(let snapshot):
      let restored = try snapshot.restore(reusing: tiles)
      return (restored.document, restored.tiles)
    }
  }
  mutating func spill(to store: HistoryScratchStore) throws {
    if case .resident(let document) = storage {
      storage = .scratch(try HistorySnapshot(document, store: store))
    }
  }
}
public struct PreparedEdit: Sendable {
  public var isFitImageEdit: Bool { if case .fitImage = recordingCommand { return true }; return false }
  public var channelCommand: ChannelCommand? { if case .channel(let command) = recordingCommand { return command }; return nil }
  public var pixelPaintRequest: PixelPaintRequest? { if case .pixelPaint(let request) = recordingCommand { return request }; return nil }
  public var paintingRequest: PaintToolRequest? { if case .painting(let edit) = recordingCommand { return edit.request }; return nil }
  public var isChannelOnlyEdit:Bool {if case .channel=recordingCommand{return true};return false}
  public var isSelectionOnly:Bool {switch recordingCommand {case .modifiedSelection,.reselectedSelection,.transformedSelection,.channel(.load(_,_,_)),.channel(.loadCoverage(_,_)):return true;default:return false}}
  public var linkedSmartObjectEdit:LinkedSmartObjectEdit? {if case .linkedSmartObject(let edit)=recordingCommand{return edit};return nil}
  public var channelArithmeticEdit: ChannelArithmeticEdit? { if case .channelArithmetic(let edit) = recordingCommand { return edit }; return nil }
  public var modeComponentEdit: ModeComponentEdit? { if case .modeComponents(let edit) = recordingCommand { return edit }; return nil }
  public var adjustmentBrushTarget:UUID? {if case .adjustmentBrush(let request)=recordingCommand {return request.layerID ?? request.newLayerID};return nil}
  public var paintingSession: PaintingSessionResult? {
    if case .painting(let edit) = recordingCommand { return edit.session };return nil
  }
  let original: CraftDocument
  let result: CraftDocument
  public let label: String
  let recordingCommand: Command?
  // Only the core's validated retained-stroke owner can produce this result.
  init(retainedStrokeOriginal original: CraftDocument, result: CraftDocument, command: Command) {
    self.original = original; self.result = result; label = command.label; recordingCommand = command
  }
  /// Restore saved content as one undoable edit while retaining this open document's identity.
  public init(restoring saved: CraftDocument, over current: CraftDocument) throws {
    var restored = saved
    restored.id = current.id
    try restored.validate()
    original = current
    result = restored
    label = "Revert"
    recordingCommand = nil
  }
  public init(command: Command, document: CraftDocument) throws {
    original = document
    var candidate = document
    try command.apply(to: &candidate)
    result = candidate
    label = command.label
    recordingCommand = command
  }
}
public struct EditorSession: Sendable {
  /// Refill an authorized runtime cache without adding history or changing source revision.
  public mutating func hydrateLinkedSmartObject(_ sourceID:UUID,bytes:Data)throws {
    var candidate=document;var found=false
    for i in candidate.layers.indices where candidate.layers[i].smartObject?.sourceID==sourceID {
      guard let object=candidate.layers[i].smartObject,object.linkedSource != nil else{throw CraftError.invalid("Choose a linked source.")}
      candidate.layers[i].smartObject=try object.hydrating(bytes);found=true
    }
    guard found else{throw CraftError.invalid("Linked source not found.")}
    try candidate.validate();document=candidate
  }
  public private(set) var actionRecording: ActionRecording?
  public mutating func startActionRecording(name: String, set: String = "My Actions") throws {
    guard actionRecording == nil else { throw CraftError.invalid("An action is already recording.") }
    let action = RecordedAction(name: name, set: set); try action.validate()
    endCoalescing(); actionRecording = ActionRecording(action: action)
  }
  public mutating func stopActionRecording() { actionRecording = nil; endCoalescing() }
  /// Clipboard reads have a semantic action step without a document/history mutation.
  public mutating func recordActionOperation(_ operation: ActionOperation, name: String) {
    guard let recording = actionRecording else { return }
    if recording.snapshot.steps.count < 511 { actionRecording?.pending.append(.init(name: name, operation: operation)) }
    else if recording.snapshot.steps.count == 511 { actionRecording?.pending.append(.init(name: "Recording limit", operation: .unsupported("Recording exceeded 511 steps. Split this action."))) }
  }
  public private(set) var document: CraftDocument
  public private(set) var undoStack: [HistoryEntry] = []
  public private(set) var redoStack: [HistoryEntry] = []
  private var coalescing = false
  private var coalescingHasChanges = false
  public static let defaultHistoryByteLimit = 256 * 1024 * 1024
  public static let defaultHistoryDiskByteLimit = 4 * 1024 * 1024 * 1024
  public let historyByteLimit: Int
  public let historyDiskByteLimit: Int
  public let limit: Int
  private let scratchParent: URL?
  private var scratchStore: HistoryScratchStore?
  private var restoredTiles: HistoryDecodedTiles?
  /// These buffers are shared with current document pixels, not additional history payload.
  public var historyReusableCurrentRasterBytes: Int { restoredTiles?.bytes ?? 0 }
  public var historyDiskBytes: Int { scratchStore?.allocatedBytes ?? 0 }
  public var historyCleanupFailures: Int { scratchStore?.cleanupFailureCount ?? 0 }
  public var historySpilledStates: Int { (undoStack + redoStack).filter(\.isOnDisk).count }
  /// History payloads beyond the current document. Index/allocator overhead is separate.
  public var residentHistoryBytes: Int {
    var seen: Set<UInt> = []
    _ = document.accountHistoryMemory(&seen, includeMetadata: false)
    return (undoStack + redoStack).reduce(0) { bytes, entry in
      bytes + (entry.residentDocument?.accountHistoryMemory(&seen, includeMetadata: true) ?? 0)
    }
  }
  public init(
    document: CraftDocument, historyLimit: Int = 40,
    historyByteLimit: Int = Self.defaultHistoryByteLimit,
    historyDiskByteLimit: Int = Self.defaultHistoryDiskByteLimit, scratchParent: URL? = nil
  ) {
    self.document = document
    limit = max(1, min(200, historyLimit))
    self.historyByteLimit = max(0, historyByteLimit)
    self.historyDiskByteLimit = max(0, historyDiskByteLimit)
    self.scratchParent = scratchParent
  }
  mutating func setAnimationSelection(_ candidate: CraftDocument) { document = candidate }
  public mutating func selectLayer(_ id: UUID) {
    if document.layers.contains(where: { $0.id == id }), document.activeLayerID != id {
      if let recording = actionRecording {
        if recording.snapshot.steps.count < 511 {
          actionRecording?.pending.append(.init(name: "Select Layer", operation: .select(.init(id, in: document, preferActive: false))))
        } else if recording.snapshot.steps.count == 511 {
          actionRecording?.pending.append(.init(name: "Recording limit", operation: .unsupported("Recording exceeded 511 steps. Split this action.")))
        }
      }
      document.activeLayerID = id
    }
  }
  /// User-driven deselection is a portable view Action, independent of edit history.
  public mutating func deselectLayers() {
    recordActionOperation(.deselectLayers, name: "Deselect Layers")
    document.activeLayerID = nil
  }
  /// Filtering changes view selection without an edit, dirty event or Action step.
  public mutating func setFilteredLayerSelection(_ id: UUID?) {
    guard id == nil || document.layers.contains(where: { $0.id == id }) else { return }
    document.activeLayerID = id
  }
  /// Persisted panel metadata, deliberately outside edit history and coalescing.
  /// Validate the complete request before changing any group; locks protect content,
  /// not whether its rows are expanded in the Layers panel.
  @discardableResult
  public mutating func setGroupExpansion(_ ids: Set<UUID>, expanded: Bool) throws -> Bool {
    let groups = Set(document.layers.filter(\.isGroup).map(\.id))
    guard !ids.isEmpty, ids.isSubset(of: groups) else {
      throw CraftError.invalid("Choose existing layer groups.")
    }
    var changed = false
    for index in document.layers.indices where ids.contains(document.layers[index].id) {
      guard var group = document.layers[index].group, group.expanded != expanded else { continue }
      group.expanded = expanded
      document.layers[index].content = .group(group)
      changed = true
    }
    return changed
  }
  public mutating func beginCoalescing() {
    coalescing = true
    coalescingHasChanges = false
  }
  public mutating func endCoalescing() {
    coalescing = false
    coalescingHasChanges = false
  }
  public mutating func execute(_ command: Command) throws {
    try executePrepared(PreparedEdit(command: command, document: document))
  }
  public mutating func executePrepared(_ prepared: PreparedEdit) throws {
    // API/jobs may execute many transactions without an AppKit event-pool drain.
    // Release temporary Foundation coding objects at each transaction boundary.
    try autoreleasepool { try commitPrepared(prepared) }
  }
  private mutating func commitPrepared(_ prepared: PreparedEdit) throws {
    guard prepared.original == document else {
      throw CraftError.invalid("The document changed while processing. The result was not applied.")
    }
    let candidate = prepared.result
    guard candidate != document else {
      if let command = prepared.recordingCommand {
        switch command {
        case .preparedAction(let edit): if let recording=edit.recording {recordActionOperation(recording,name:prepared.label)}
        case .paste, .fitImage: recordActionOperation(ActionOperation(recording: command, in: document), name: prepared.label)
        default: break
        }
      }
      return
    }
    var next = self
    if !coalescing || !coalescingHasChanges {
      next.undoStack.append(HistoryEntry(label: prepared.label, document: document))
    }
    if next.actionRecording != nil, let entry = next.undoStack.last {
      let operation = prepared.recordingCommand.map { ActionOperation(recording: $0, in: document) } ?? .unsupported("\(prepared.label) is not recordable.")
      next.actionRecording?.append(.init(name: prepared.label, operation: operation), historyID: entry.id)
    }
    next.coalescingHasChanges = true
    next.redoStack = []
    if next.undoStack.count > limit { next.undoStack.removeFirst() }
    next.document = candidate
    next.restoredTiles = nil
    try next.spillHistoryIfNeeded()
    try Task.checkCancellation()
    self = next
  }
  private mutating func spillHistoryIfNeeded() throws {
    guard residentHistoryBytes > historyByteLimit else { return }
    if scratchStore == nil {
      scratchStore = try HistoryScratchStore(parent: scratchParent, limit: historyDiskByteLimit)
    }
    guard let scratchStore else { return }
    for index in undoStack.indices {
      guard residentHistoryBytes > historyByteLimit else { break }
      try undoStack[index].spill(to: scratchStore)
    }
    for index in redoStack.indices {
      guard residentHistoryBytes > historyByteLimit else { break }
      try redoStack[index].spill(to: scratchStore)
    }
  }
  public mutating func undo(validate: (CraftDocument) throws -> Void = { _ in }) throws {
    try autoreleasepool { try navigateHistory(redo: false, validate: validate) }
  }
  public mutating func redo(validate: (CraftDocument) throws -> Void = { _ in }) throws {
    try autoreleasepool { try navigateHistory(redo: true, validate: validate) }
  }
  private mutating func navigateHistory(
    redo: Bool, validate: (CraftDocument) throws -> Void
  ) throws {
    try Task.checkCancellation()
    guard let entry = redo ? redoStack.last : undoStack.last else { return }
    let restored = try entry.restoredDocument(reusing: restoredTiles)
    try validate(restored.document)
    var next = self
    next.endCoalescing()
    if redo {
      next.redoStack.removeLast()
      next.undoStack.append(HistoryEntry(label: entry.label, document: document, id: entry.id))
    } else {
      next.undoStack.removeLast()
      next.redoStack.append(HistoryEntry(label: entry.label, document: document, id: entry.id))
    }
    next.actionRecording?.navigate(historyID: entry.id, redo: redo)
    next.document = restored.document
    next.restoredTiles = restored.tiles
    try next.spillHistoryIfNeeded()
    try Task.checkCancellation()
    self = next
  }
}
