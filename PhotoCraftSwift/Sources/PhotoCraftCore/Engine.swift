import Foundation

public enum Command: Sendable {
  indirect case variables(VariableCommand)
  case video(VideoCommand)
  case animation(AnimationCommand)
  case documentMode(DocumentModeConversion)
  case preparedColorProfile(ColorProfileEdit)
  case preparedDocumentMode(DocumentModeEdit)
  case channelArithmetic(ChannelArithmeticEdit)
  case modeChannel(ModeChannelEdit)
  case modeComponents(ModeComponentEdit)
  indirect case toneAdjustment(ClassicToneRequest)
  case hdrToning(HDRToningEdit)
  indirect case proceduralRender(ProceduralRenderRequest)
  case maskAllObjects(MaskAllObjectsEdit)
  case skyReplacement(SkyReplacementEdit)
  indirect case adjustmentBrush(AdjustmentBrushRequest)
  indirect case painting(PaintingEdit)
  case artboard(ArtboardCommand)
  case frame(FrameCommand)
  indirect case shape(ShapeCommand)
  case action(RecordedAction, limits: ActionPlaybackLimits? = nil)
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
  case reorder(UUID, Int)
  case relocate(UUID, UUID?, Int)
  case groupLayers([UUID], String)
  case ungroup(UUID)
  case groupProperties(UUID, GroupContent)
  case clipping(UUID, Bool)
  case blendClippedAsGroup(UUID, Bool)
  case replaceContent(UUID, LayerContent)
  case editType(UUID, TextContent, originDelta: PathPoint)
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
  case resolution(Double)
  case rotateCanvas(CanvasTurn)
  public var label: String {
    switch self {
    case .variables(let command): command.label
    case .video(let command): command.label
    case .animation(let command): command.label
    case .toneAdjustment(let request):request.settings.kind.title
    case .hdrToning:"HDR Toning"
    case .documentMode(let request):request.mode.title
    case .preparedColorProfile(let edit):edit.title
    case .preparedDocumentMode(let edit):edit.title
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
    case .artboard(let command): command.label
    case .action(let action, _): "Play \(action.name)"
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
    case .editType: "Edit Type"
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
    case .desaturate: "Desaturate"
    case .autoCorrection(_, let kind): kind.rawValue
    case .applyAdjustment: "Adjustment"
    case .crop: "Crop"
    case .cropDocument: "Crop"
    case .flip: "Flip Layer"
    case .transform: "Free Transform"
    case .canvasSize: "Canvas Size"
    case .imageSize: "Image Size"
    case .resolution: "Image Resolution"
    case .rotateCanvas: "Image Rotation"
    }
  }
  public func apply(to d: inout CraftDocument) throws {
    if d.restrictedMode != nil || d.inkMode != nil || d.animation != nil || d.videoTimeline != nil || d.variables != nil {
      // A layer/geometry operation may be rejected by restricted-mode invariants.
      // Keep direct Command callers just as atomic as EditorSession/PreparedEdit.
      var candidate = d; try applyValidated(to: &candidate); d = candidate
    } else { try applyValidated(to: &d) }
  }
  private func applyValidated(to d: inout CraftDocument) throws {
    let variableSource = d.variables == nil ? nil : d
    let hadAnimation = d.animation != nil
    let hadVideo = d.videoTimeline != nil
    try validateVideoContext(in: d)
    try validateAnimationContext(in: d)
    try validateProtection(in:d)
    if d.inkMode != nil, try InkModeGeometry.apply(self, to: &d) { try d.validate(); return }
    if d.restrictedMode != nil, try RestrictedModeGeometry.apply(self, to: &d) { try d.validate(); return }
    let modeBefore = d.hasAuthoritativeModeStorage ? d : nil
    // Keep nested modular commands off the large primitive-switch stack frame.
    // Frame wrapping and live-shape creation can invoke another native command.
    switch self {
    case .variables(let command): try command.apply(to: &d)
    case .video(let command): try command.apply(to: &d)
    case .animation(let command):try command.apply(to: &d)
    case .documentMode(let request):d=try d.convertingMode(request)
    case .preparedColorProfile(let edit):d=try edit.applied(to:d)
    case .preparedDocumentMode(let edit):d=try edit.applied(to:d)
    case .channelArithmetic(let edit):d=try edit.applied(to:d)
    case .modeChannel(let edit):try d.editModeChannel(edit)
    case .modeComponents(let edit):try edit.apply(to:&d)
    case .frame(let command):try command.apply(to:&d)
    case .shape(let command):try command.apply(to:&d)
    case .artboard(let command):try command.apply(to:&d)
    case .action(let action,let limits):try action.apply(to:&d,validate:{try limits?.validate($0)})
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
    try d.fitArtboardCanvas()
    if let modeBefore { try d.reconcileModeStorage(from:modeBefore) }
    try d.validate()
  }
  private func applyPrimitive(to d:inout CraftDocument)throws {
    func index(_ id: UUID, editable: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }) else {
        throw CraftError.invalid("Layer no longer exists.")
      }
      if editable && d.isLocked(id) {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
      return i
    }
    func raster(_ i: Int, allowLarge: Bool = false) throws -> Surface {
      guard case .raster(let s) = d.layers[i].content else {
        throw CraftError.unsupported(
          "Rasterize this layer before painting or applying pixel filters.")
      }
      guard allowLarge || s.width <= Surface.maximumDensePixels / s.height else {
        throw CraftError.unsupported("This whole-raster operation is not yet tiled for large documents. No pixels were changed.")
      }
      return s
    }
    switch self {
    case .channelArithmetic,.mergeLayers,.applyAdjustment,.applyFilter,.smartFilters: throw CraftError.invalid("Unexpected nested command routing.")
    case .toneAdjustment(let request):try ClassicToneEngine.apply(request,to:&d)
    case .hdrToning(let edit):d=try edit.applied(to:d)
    case .proceduralRender(let request):try ProceduralRenderEngine.apply(request,to:&d)
    case .variables,.addGradientFill,.addPatternFill,.independentSmartObjectCopy,.autoCorrection,.desaturate,.video, .animation,.frame,.shape,.artboard,.action,.preparedAction,.channel,.inkChannel,.smartFilterMask,.documentMode,.preparedDocumentMode,.preparedColorProfile,.modeChannel,.modeComponents:throw CraftError.invalid("Unexpected modular command routing.")
    case .paste(let content, let placement, let center):
      try content.paste(into: &d, placement: placement, center: center)
    case .layerVia(let id, let operation):
      try LayerVia.apply(operation, layerID: id, to: &d)
    case .cut(let requested, let background):
      let ids = Set(requested)
      guard !ids.isEmpty, ids.allSatisfy({ id in d.layers.contains { $0.id == id } }) else {
        throw CraftError.invalid("Select a layer to cut.")
      }
      guard background?.isFinite != false, background == nil || background!.a == 1 else { throw CraftError.invalid("Cut background must be an opaque finite color.") }
      if d.selection != nil || d.restrictedMode != nil {
        guard ids.count == 1, let id = ids.first else {
          throw CraftError.unsupported("Cut a pixel selection from one layer at a time.")
        }
        let i = try index(id)
        var pixels = try raster(i)
        let transform = d.layers[i].coordinateTransform
        let flatBackground: Pixel?
        switch d.restrictedMode {
        case .bitmap: flatBackground = background ?? .white
        case .indexed(let raster): flatBackground = raster.transparentIndex == nil ? background ?? .white : nil
        case nil: flatBackground = nil
        }
        for y in 0..<pixels.height {
          try Task.checkCancellation()
          for x in 0..<pixels.width {
            let point = transform.point(Double(x) + 0.5, Double(y) + 0.5)
            let coverage = d.selectionCoverage(x: Int(floor(point.x)), y: Int(floor(point.y)))
            if coverage > 0 {
              var value = pixels.pixel(x: x, y: y)
              if let fill = flatBackground { value = Pixel(value.r * (1 - coverage) + fill.r * coverage, value.g * (1 - coverage) + fill.g * coverage, value.b * (1 - coverage) + fill.b * coverage, 1) }
              else { value.a *= 1 - coverage }
              pixels.setPixel(x: x, y: y, value)
            }
          }
        }
        d.layers[i].content = .raster(pixels)
      } else {
        let removed = ids.reduce(into: Set<UUID>()) { $0.formUnion(d.subtreeIDs($1)) }
        guard removed.allSatisfy({ !d.isLocked($0) }) else {
          throw CraftError.invalid("Unlock the selected layers and groups before cutting.")
        }
        d.layers.removeAll { removed.contains($0.id) }
        d.activeLayerID = d.layers.last?.id
      }
    case .setGradientFill(let id, let fill):
      let i = try index(id)
      guard case .gradientFill = d.layers[i].content else {
        throw CraftError.invalid("Select a gradient fill layer.")
      }
      try fill.validate()
      d.layers[i].content = .gradientFill(fill)
    case .setPatternFill(let id, var fill, let pattern):
      let i = try index(id)
      guard case .patternFill = d.layers[i].content else {
        throw CraftError.invalid("Select a pattern fill layer.")
      }
      if let pattern { fill.patternID = try d.installPattern(pattern) }
      d.layers[i].content = .patternFill(fill)
    case .addLayer(let layer):
      try d.insertNewLayer(layer)
    case .newPixelLayer(let options, let below):
      try d.insertNewLayer(options.layer(in: d), below: below)
    case .deleteLayers(let ids):
      try LayerDeletion.apply(to: &d, selected: ids)
    case .deleteLayer(let id):
      let i = try index(id)
      let ids = d.subtreeIDs(id)
      d.layers.removeAll { ids.contains($0.id) }
      d.activeLayerID = d.layers.isEmpty ? nil : d.layers[min(i, d.layers.count - 1)].id
    case .duplicateLayer(let id):
      try LayerDuplication.duplicate(in: &d, selected: [id], name: nil)
    case .duplicateLayers(let ids, let name):
      try LayerDuplication.duplicate(in: &d, selected: ids, name: name)
    case .duplicateLayersFrom(let source, let ids, let name):
      try LayerDuplication.transfer(from: source, selected: ids, name: name, into: &d)
    case .renameLayer(let id, let name):
      guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        name.utf16.count <= 65_535
      else {
        throw CraftError.invalid("A layer needs a name.")
      }
      let i = try index(id, editable: false)
      d.layers[i].name = name
    case .layerColor(let ids, let color):
      try LayerOrganization.setColor(color, selected: ids, in: &d)
    case .layerVisibility(let values):
      try LayerOrganization.setVisibility(values, in: &d)
    case .visibility(let id, let v):
      let i = try index(id, editable: false)
      d.layers[i].visible = v
    case .lock(let id, let v):
      let i = try index(id, editable: false)
      d.layers[i].protection = v ? .fullyLocked : []
    case .protection(let values):
      let ids = Set(values.keys)
      for value in values.values { try value.validate() }
      guard !ids.isEmpty, ids.isSubset(of: Set(d.layers.map(\.id))) else {
        throw CraftError.invalid("Select existing layers to protect.")
      }
      for i in d.layers.indices where ids.contains(d.layers[i].id) {
        d.layers[i].protection = values[d.layers[i].id]!
      }
    case .opacity(let id, let v):
      guard v.isFinite, (0...1).contains(v) else {
        throw CraftError.invalid("Opacity must be between 0 and 1.")
      }
      let i = try index(id)
      d.layers[i].opacity = v
    case .blend(let id, let v):
      let i = try index(id)
      d.layers[i].blendMode = v
      if case .group(var group) = d.layers[i].content {
        group.passThrough = false
        d.layers[i].content = .group(group)
      }
    case .layoutLayers(let moves, _):
      try LayerLayout.apply(moves, to: &d)
    case .move(let id, let x, let y):
      guard abs(Double(x)) <= 1_000_000, abs(Double(y)) <= 1_000_000 else {
        throw CraftError.invalid("Position is out of range.")
      }
      let i = try index(id)
      let dx = x - d.layers[i].x
      let dy = y - d.layers[i].y
      let ids = d.subtreeIDs(id)
      for j in d.layers.indices where ids.contains(d.layers[j].id) {
        let old = d.layers[j]
        d.layers[j].smartFilters?.transformPuppetPins(.translation(Double(dx), Double(dy)))
        d.layers[j].smartFilters?.transformPerspectivePlanes(.translation(Double(dx), Double(dy)))
        d.layers[j].x += dx
        d.layers[j].y += dy
        try d.layers[j].movePattern(x: dx, y: dy)
        try d.layers[j].preserveUnlinkedMask(from: old)
        if old.smartFilters?.maskProperties.linked == true {
          d.layers[j].smartFilters?.maskProperties.transform = .translation(Double(dx), Double(dy)) * old.smartFilters!.maskProperties.transform
        }
        if old.vectorMask?.linked == true {
          d.layers[j].vectorMask?.path = old.vectorMask!.path.transformed(
            .translation(Double(dx), Double(dy)))
        }
      }
    case .reorder(let id, let target):
      let i = try index(id)
      guard d.layers.indices.contains(target) else {
        throw CraftError.invalid("Invalid layer position.")
      }
      let destination = d.layers[target]
      guard destination.parentID == d.layers[i].parentID else {
        throw CraftError.invalid("Use Move Into Group to change a layer's parent.")
      }
      let siblings = d.children(of: destination.parentID)
      let position = siblings.firstIndex { $0.id == destination.id }!
      try d.relocate(id, parent: destination.parentID, position: position)
    case .relocate(let id, let parent, let position):
      _ = try index(id)
      try d.relocate(id, parent: parent, position: position)
    case .groupLayers(let requested, let name):
      try d.createLayerGroup(.init(name: name), children: requested, below: false)
    case .newGroup(let options, let children, let below):
      try d.createLayerGroup(options, children: children, below: below)
    case .ungroup(let id):
      let i = try index(id)
      guard d.layers[i].isGroup else { throw CraftError.invalid("Select a group to ungroup.") }
      let parent = d.layers[i].parentID
      let children = d.children(of: id)
      for j in d.layers.indices where d.layers[j].parentID == id { d.layers[j].parentID = parent }
      d.layers.remove(at: i)
      d.activeLayerID = children.last?.id ?? parent ?? d.layers.last?.id
    case .groupProperties(let id, let properties):
      let i = try index(id, editable: false)
      if d.layers[i].group?.passThrough != properties.passThrough && d.isLocked(id) {
        throw CraftError.invalid("Unlock the group before changing its blending.")
      }
      guard d.layers[i].isGroup else { throw CraftError.invalid("Select a group.") }
      guard properties.frame == d.layers[i].frame else { throw CraftError.invalid("Use Frame Properties to edit frame metadata.") }
      guard properties.artboard == d.layers[i].artboard else { throw CraftError.invalid("Use Artboard Properties to change artboard metadata.") }
      d.layers[i].content = .group(properties)
    case .clipping(let id, let value):
      let i = try index(id)
      if value && d.clippingBase(for: id) == nil {
        throw CraftError.invalid("A clipping mask needs a base layer below it in the same group.")
      }
      d.layers[i].clipped = value
    case .blendClippedAsGroup(let id, let value):
      let i = try index(id)
      d.layers[i].blendClippedAsGroup = value
    case .editType(let id,let content,let delta):
      let i=try index(id);guard case .text=d.layers[i].content,!d.isImageLocked(id),delta.x.isFinite,delta.y.isFinite,abs(delta.x)<=1_000_000,abs(delta.y)<=1_000_000 else{throw CraftError.invalid("Editable type and a finite origin are required.")}
      try content.validate();let old=d.layers[i];d.layers[i].content = .text(content)
      if delta.x != 0 || delta.y != 0 {
        d.layers[i].x=0;d.layers[i].y=0;d.layers[i].affine=old.coordinateTransform * .translation(delta.x,delta.y)
        if old.mask != nil{var properties=old.effectiveMaskProperties;properties.transform=try d.layers[i].coordinateTransform.inverted() * old.maskCoordinateTransform;d.layers[i].maskProperties=properties}
      }
    case .replaceContent(let id, let c):
      let i = try index(id)
      guard !d.layers[i].isGroup, !Layer(name: "", content: c).isGroup else {
        throw CraftError.invalid("Use group commands to change the layer hierarchy.")
      }
      d.layers[i].content = c
    case .rasterize(let id, let surface):
      let i = try index(id)
      var layer = d.layers[i]
      if let object = layer.smartObject, object.pdfSource != nil,
        surface.width != object.width || surface.height != object.height {
        // The shared PDF renderer can supply a denser source-space surface.
        // Preserve its document geometry and mask mapping when dropping source.
        let sx = Double(surface.width)/Double(object.width)
        let sy = Double(surface.height)/Double(object.height)
        layer.affine = (layer.affine ?? .identity) * .scale(1/sx,1/sy)
        if layer.mask != nil {
          var properties = layer.effectiveMaskProperties
          properties.transform = .scale(sx,sy) * properties.transform
          layer.maskProperties = properties
        }
        layer.content = .raster(surface)
      }
      if layer.smartFilters != nil || layer.warp != nil {
        layer = try SmartFilterEngine.renderedLayer(layer, in: d)
        for key in ["SoLd", "SoLE", "PlLd"] { layer.sourceTags?.removeValue(forKey: key) }
        d.layers[i] = layer
        break
      }
      layer.video = nil
      layer.smartObject = nil
      for key in ["SoLd", "SoLE", "PlLd"] { layer.sourceTags?.removeValue(forKey: key) }
      guard !layer.isGroup else {
        throw CraftError.unsupported("Group rasterization is not available yet; ungroup first.")
      }
      if layer.isCanvasFill {
        let old = layer
        layer.x = 0
        layer.y = 0
        layer.affine = nil
        if old.mask != nil {
          layer.maskProperties = old.effectiveMaskProperties
          layer.maskProperties?.transform = old.maskCoordinateTransform
        }
      }
      layer.content = .raster(try surface.converted(to: d.depth))
      d.layers[i] = try DocumentGeometry.transformLayer(
        layer, by: .identity, in: d, method: .bicubic)
    case .embedSmartObject(let ids, let layer):
      try d.embedSmartObject(replacing: ids, with: layer)
    case .smartObjectStack(let id, let mode, let pixels):
      let i = try index(id)
      guard d.layers[i].smartObject != nil, !d.isImageLocked(id) else { throw CraftError.invalid("Select an unlocked Smart Object.") }
      d.layers[i].smartObject?.stackMode = mode; try d.layers[i].smartObject?.validate()
      d.layers[i].content = .raster(pixels)
      for key in ["SoLd", "SoLE", "PlLd"] { d.layers[i].sourceTags?.removeValue(forKey: key) }
    case .replaceSmartObject(let id, let source, let pixels, let preserveSize, let allInstances, let instancePixels):
      try d.replaceSmartObject(id, source: source, pixels: pixels, preserveSize: preserveSize, allInstances: allInstances, instancePixels: instancePixels)
    case .resetSmartObjectTransform(let id):
      let i = try index(id)
      guard d.layers[i].smartObject != nil, !d.isPositionLocked(id) else {
        throw CraftError.invalid("Select a position-unlocked Smart Object.")
      }
      let delta = Transform2D.translation(Double(d.layers[i].x), Double(d.layers[i].y)) * (try d.layers[i].coordinateTransform.inverted())
      d.layers[i] = try DocumentGeometry.transformLayer(d.layers[i], by: delta, in: d)
      d.layers[i].warp = nil
    case .mask(let id, let s):
      let i = try index(id)
      if s == nil { try LensBlurEngine.validateMaskRemoval(d.layers[i]) }
      d.layers[i].mask = s
      d.layers[i].maskProperties = nil
      if s != nil && d.layers[i].isGroup {
        var properties = MaskProperties()
        properties.outside = d.selection == nil ? 1 : 0
        properties.transform = try d.layers[i].coordinateTransform.inverted()
        d.layers[i].maskProperties = properties
      }
    case .createMask(let id, let kind):
      let i = try index(id)
      d.layers[i] = try d.layers[i].creatingPixelMask(kind, in: d)
      if kind == .revealSelection || kind == .hideSelection { d.setCoverageSelection(nil) }
    case .applyMask(let id):
      let i = try index(id)
      try LensBlurEngine.validateMaskRemoval(d.layers[i])
      d.layers[i] = try d.layers[i].applyingPixelMask(in: d)
    case .deleteMask(let id):
      let i = try index(id)
      try LensBlurEngine.validateMaskRemoval(d.layers[i])
      guard d.layers[i].mask != nil else { throw CraftError.invalid("This layer has no mask.") }
      d.layers[i].mask = nil
      d.layers[i].maskProperties = nil
    case .maskProperties(let id, let properties):
      let i = try index(id)
      guard d.layers[i].mask != nil else { throw CraftError.invalid("This layer has no mask.") }
      try properties.validate()
      d.layers[i].maskProperties = properties
    case .vectorMask(let id, let mask):
      let i = try index(id)
      try mask?.validate()
      d.layers[i].vectorMask = mask
    case .savePath(let path):
      try path.path.validate()
      var paths = d.paths ?? []
      if let i = paths.firstIndex(where: { $0.id == path.id }) {
        paths[i] = path
      } else {
        paths.append(path)
      }
      d.paths = paths
    case .deletePath(let id):
      guard d.paths?.contains(where: { $0.id == id }) == true else {
        throw CraftError.invalid("Path no longer exists.")
      }
      d.paths?.removeAll { $0.id == id }
    case .selection(let s):
      d.selection = s
      d.selectionMask = nil
    case .selectShape(let shape, let mode, let antiAlias, let feather):
      let mask = try SelectionMask.make(
        shape, width: d.width, height: d.height, antiAlias: antiAlias
      )
      .feathered(radius: feather)
      d.setCoverageSelection(try mask.combined(with: d.coverageSelection(), mode: mode))
    case .selectionCoverage(let mask, let mode):
      guard mask == nil || (mask?.width == d.width && mask?.height == d.height) else {
        throw CraftError.invalid("Selection canvas sizes differ.")
      }
      d.setCoverageSelection(try mask?.combined(with: d.coverageSelection(), mode: mode))
    case .vanishingPoint(let edit): d = try edit.applied(to:d)
    case .maskAllObjects(let edit): d = try edit.applied(to:d)
    case .skyReplacement(let edit): d = try edit.applied(to:d)
    case .warp(let edit):
      d = try edit.applied(to:d)
    case .contentAwareScale(let edit):
      d = try edit.applied(to:d)
    case .photoAlign(let edit):
      d = try edit.applied(to:d)
    case .photoBlend(let edit):
      d = try edit.applied(to:d)
    case .adjustmentBrush(let request): try request.apply(to:&d)
    case .painting(let edit):
      d = try edit.applied(to:d)
    case .regionRetouch(let edit):
      d = try edit.applied(to:d)
    case .contentAwareFill(let edit):
      d = try edit.applied(to:d)
    case .selectionRefinement(let edit),.focusArea(let edit):
      guard !edit.output.createsDocument else { throw CraftError.invalid("Create the refined document through the document controller.") }
      d = try edit.applied(to:d)
    case .selectSubject(let mask, let mode):
      guard mask.width == d.width, mask.height == d.height, mask.bounds != nil else {
        throw CraftError.invalid("No foreground subject was found, or the mask dimensions differ.")
      }
      d.setCoverageSelection(try mask.combined(with: d.coverageSelection(), mode: mode))
    case .removeBackground(let id, let mask):
      let i = try index(id)
      _ = try raster(i)
      guard mask.width == d.width, mask.height == d.height, mask.bounds != nil else {
        throw CraftError.invalid("No foreground subject was found, or the mask dimensions differ.")
      }
      // Reuse canvas-to-layer mask coordinates without consuming the user's selection.
      var selected = d
      selected.setCoverageSelection(mask)
      d.layers[i] = try d.layers[i].creatingPixelMask(.revealSelection, in: selected)
    case .magicWand(let source, let seed, let options, let mode, let mask):
      let region = try ColorRegion.selection(
        source: source, width: d.width, height: d.height,
        seed: seed, options: options, mask: mask)
      let combined = try region.combined(with: d.coverageSelection(), mode: mode)
      try Task.checkCancellation()
      d.setCoverageSelection(combined)
    case .paintBucket(let id, let fill):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try BucketPainter.paint(
        fill, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .paintGradient(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try GradientPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .invertSelection:
      guard let mask = try d.coverageSelection() else {
        throw CraftError.invalid("Make a selection first.")
      }
      d.setCoverageSelection(try mask.inverted())
    case .featherSelection(let radius):
      guard let mask = try d.coverageSelection() else {
        throw CraftError.invalid("Make a selection first.")
      }
      d.setCoverageSelection(try mask.feathered(radius: radius))
    case .maskStroke(let id, let points, var brush):
      let i = try index(id)
      try d.layers[i].expandMask(for: points, brush: brush, clipping: d.selection)
      guard var mask = d.layers[i].mask else { throw CraftError.invalid("This layer has no mask.") }
      let value =
        brush.erase
        ? Float(1) : unit(0.2126 * brush.color.r + 0.7152 * brush.color.g + 0.0722 * brush.color.b)
      guard brush.color.isFinite else { throw CraftError.invalid("Invalid mask brush color.") }
      brush.color = Pixel(value, value, value, brush.color.a)
      brush.erase = false
      try Painter.stroke(
        surface: &mask, points: points, brush: brush, selection: d.selection,
        selectionMask: d.selectionMask, transform: d.layers[i].maskCoordinateTransform,
        grayscaleMask: true)
      d.layers[i].mask = mask
    case .maskFill(let id, let value):
      guard value.isFinite, (0...1).contains(value) else {
        throw CraftError.invalid("Invalid mask fill.")
      }
      let i = try index(id)
      if let selection = d.selection { try d.layers[i].expandMask(toDocumentBounds: selection) }
      guard var mask = d.layers[i].mask else { throw CraftError.invalid("This layer has no mask.") }
      let before = d
      let matrix = d.layers[i].maskCoordinateTransform
      mask.mapPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        let cov = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
        let v = unit(p.r) * (1 - cov) + value * cov
        return Pixel(v, v, v)
      }
      d.layers[i].mask = mask
      if d.selection == nil {
        var p = d.layers[i].effectiveMaskProperties
        p.outside = value
        d.layers[i].maskProperties = p
      }
    case .invertMask(let id):
      let i = try index(id)
      guard var mask = d.layers[i].mask else { throw CraftError.invalid("This layer has no mask.") }
      mask.mapPixels { _, _, p in
        let v = 1 - unit(p.r)
        return Pixel(v, v, v)
      }
      d.layers[i].mask = mask
      var properties = d.layers[i].effectiveMaskProperties
      properties.outside = 1 - properties.outside
      d.layers[i].maskProperties = properties
    case .focus(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try FocusPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .toning(let id, let stroke):
      let i = try index(id)
      try ToningPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask)
    case .spotHealing(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try SpotHealingPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .healingBrush(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try HealingPainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .cloneStamp(let id, let stroke):
      let i = try index(id)
      let preserve = d.isTransparencyLocked(id)
      try ClonePainter.paint(
        stroke, on: &d.layers[i], canvasWidth: d.width, canvasHeight: d.height,
        selection: d.selection, selectionMask: d.selectionMask, preserveTransparency: preserve)
    case .stroke(let id, let points, let brush):
      let i = try index(id)
      var s = try raster(i, allowLarge: true)
      try Painter.stroke(
        surface: &s, points: points, brush: brush, selection: d.selection,
        selectionMask: d.selectionMask, offsetX: d.layers[i].x,
        offsetY: d.layers[i].y, transform: d.layers[i].coordinateTransform,
        preserveTransparency: d.isTransparencyLocked(id))
      d.layers[i].content = .raster(s)
    case .clear(let id):
      let i = try index(id)
      var s = try raster(i)
      let matrix = d.layers[i].coordinateTransform
      let before = d
      s.mapPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        return p.mixing(
          .clear, coverage: before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
      }
      d.layers[i].content = .raster(s)
    case .fill(let id, let color):
      guard color.isFinite else { throw CraftError.invalid("Invalid color.") }
      let i = try index(id)
      var s = try raster(i)
      let matrix = d.layers[i].coordinateTransform
      let before = d
      let preserveTransparency = d.isTransparencyLocked(id)
      let targetDepth = s.depth
      let edit: (Int, Int, Pixel) -> Pixel = { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        let coverage = before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
        if preserveTransparency {
          guard p.a > 0, coverage > 0 else { return p }
          var edited = ProtectedPixels.fill(p, color: color, coverage: coverage).quantized(targetDepth)
          edited.a = p.a
          return edited
        }
        return p.mixing(color, coverage: coverage)
      }
      if preserveTransparency { try s.mapStoredPixels(edit) } else { s.mapPixels(edit) }
      d.layers[i].content = .raster(s)
    case .fillComponents(let id, let fill):
      try fill.validate()
      let i = try index(id)
      var s = try raster(i)
      guard d.depth == .u8, s.depth == .u8 else {
        throw CraftError.unsupported("Component Fill currently requires RGB/8 pixels.")
      }
      let matrix = d.layers[i].coordinateTransform
      try matrix.validated()
      let before = d
      try s.mapStoredPixels { x, y, p in
        let q = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
        return fill.applying(
          to: p, coverage: before.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
      }
      d.layers[i].content = .raster(s)
    case .layerStyle(let ids, let style):
      guard !ids.isEmpty else { throw CraftError.invalid("Select a layer for Layer Style.") }
      try style?.validate(in: d)
      if style != nil, d.width > 8_388_608 / d.height { throw CraftError.unsupported("Layer styles support canvases up to8,388,608 pixels.") }
      let indices = try ids.map { try index($0) }
      for i in indices {
        if case .adjustment = d.layers[i].content { throw CraftError.unsupported("Layer styles on adjustment layers are not available yet.") }
      }
      for i in indices {
        d.layers[i].style = style
        for tag in ["lfx2", "lmfx", "lrFX", "iOpa"] { d.layers[i].sourceTags?.removeValue(forKey: tag) }
      }
    case .cropDocument(let edit):
      d = try edit.applied(to:d)
    case .crop(let r):
      let original = d
      guard r.x >= 0, r.y >= 0, r.width > 0, r.height > 0, r.x <= d.width - r.width,
        r.y <= d.height - r.height
      else { throw CraftError.invalid("Crop must lie within the canvas.") }
      guard !d.layers.contains(where: { $0.locked }) else {
        throw CraftError.invalid("Unlock all layers before cropping.")
      }
      for i in d.layers.indices {
        d.layers[i].x -= r.x
        d.layers[i].y -= r.y
        if let stack = d.layers[i].smartFilters {
          d.layers[i].smartFilters?.transformPuppetPins(.translation(-Double(r.x), -Double(r.y)))
          d.layers[i].smartFilters?.transformPerspectivePlanes(.translation(-Double(r.x), -Double(r.y)))
          d.layers[i].smartFilters?.maskProperties.transform = .translation(-Double(r.x), -Double(r.y)) * stack.maskProperties.transform
        }
        if case .patternFill(var fill) = d.layers[i].content {
          try fill.transform(by: .translation(-Double(r.x), -Double(r.y)))
          d.layers[i].content = .patternFill(fill)
        }
        if let mask = d.layers[i].vectorMask {
          d.layers[i].vectorMask?.path = mask.path.transformed(
            .translation(-Double(r.x), -Double(r.y)))
        }
      }
      d.transformSavedPaths(by: .translation(-Double(r.x), -Double(r.y)))
      if let origin = d.artboardOrigin { d.artboardOrigin = .init(x: origin.x + r.x, y: origin.y + r.y) }
      d.width = r.width
      d.height = r.height
      d.selection = nil
      d.selectionMask = nil
      try d.transformChannels(from:original,by:.translation(-Double(r.x),-Double(r.y)))
    case .flip(let id, let horizontal):
      let i = try index(id)
      let s = try raster(i,allowLarge:true)
      let layer = d.layers[i]
      let delta =
        Transform2D.translation(Double(layer.x), Double(layer.y))
        * (horizontal
          ? Transform2D(a: -1, tx: Double(s.width)) : Transform2D(d: -1, ty: Double(s.height)))
        * .translation(-Double(layer.x), -Double(layer.y))
      d.layers[i] = try DocumentGeometry.transformLayer(layer, by: delta, in: d, method: .nearest)
    case .transform(let id, let delta, let method):
      let i = try index(id)
      guard d.layers[i].canTransform else {
        throw CraftError.unsupported("Select a pixel, type or shape layer to transform.")
      }
      let before = d
      let ids = d.subtreeIDs(id)
      for j in d.layers.indices where ids.contains(d.layers[j].id) {
        d.layers[j] = try DocumentGeometry.transformLayer(
          d.layers[j], by: delta, in: before, method: method)
      }
    case .resolution(let value):
      guard value.isFinite, (1...100_000).contains(value) else {
        throw CraftError.invalid("Invalid image resolution.")
      }
      d.resolution = value
    case .canvasSize(let width, let height, let anchor, let extensionColor):
      _ = try Surface(width: width, height: height, depth: d.depth)
      guard extensionColor?.isFinite != false else {
        throw CraftError.invalid("Invalid canvas extension color.")
      }
      let old = d
      let fractions = anchor.fractions
      let dx = Int((Double(width - d.width) * fractions.0).rounded(.down))
      let dy = Int((Double(height - d.height) * fractions.1).rounded(.down))
      for i in d.layers.indices {
        DocumentGeometry.freezeTextLayout(&d.layers[i], document: old)
        d.layers[i].x += dx
        d.layers[i].y += dy
        if let stack = d.layers[i].smartFilters {
          d.layers[i].smartFilters?.transformPuppetPins(.translation(Double(dx), Double(dy)))
          d.layers[i].smartFilters?.transformPerspectivePlanes(.translation(Double(dx), Double(dy)))
          d.layers[i].smartFilters?.maskProperties.transform = .translation(Double(dx), Double(dy)) * stack.maskProperties.transform
        }
        if case .patternFill(var fill) = d.layers[i].content {
          try fill.transform(by: .translation(Double(dx), Double(dy)))
          d.layers[i].content = .patternFill(fill)
        }
        if let mask = d.layers[i].vectorMask {
          d.layers[i].vectorMask?.path = mask.path.transformed(.translation(Double(dx), Double(dy)))
        }
      }
      if let color = extensionColor, color.a > 0, width > old.width || height > old.height {
        guard color.isFinite, d.layers.count < 512 else {
          throw CraftError.invalid("Invalid canvas extension or layer limit.")
        }
        let pixels=try Surface.canvasExtension(width:width,height:height,depth:d.depth,color:color,
          original:IntRect(x:dx,y:dy,width:old.width,height:old.height))
        d.layers.insert(Layer(name: "Canvas Extension", content: .raster(pixels)), at: 0)
      }
      if let origin = d.artboardOrigin { d.artboardOrigin = .init(x: origin.x - dx, y: origin.y - dy) }
      d.width = width
      d.height = height
      d.transformSavedPaths(by: .translation(Double(dx), Double(dy)))
      try d.mapSelection(from: old, by: .translation(Double(dx), Double(dy)))
      try d.transformChannels(from:old,by:.translation(Double(dx),Double(dy)))
    case .imageSize(let width, let height, let resolution, let method):
      _ = try Surface(width: width, height: height, depth: d.depth)
      guard resolution.isFinite, (1...100_000).contains(resolution) else {
        throw CraftError.invalid("Invalid image resolution.")
      }
      let old = d
      let delta = Transform2D.scale(
        Double(width) / Double(d.width), Double(height) / Double(d.height))
      if width != old.width || height != old.height {
        for i in d.layers.indices {
          d.layers[i] = try DocumentGeometry.transformLayer(
            d.layers[i], by: delta, in: old, method: method, includingUnlinkedMasks: true)
        }
      }
      d.width = width
      d.height = height
      d.resolution = resolution
      if let origin = old.artboardOrigin { d.artboardOrigin = .init(x: Int((Double(origin.x) * Double(width) / Double(old.width)).rounded()), y: Int((Double(origin.y) * Double(height) / Double(old.height)).rounded())) }
      d.transformSavedPaths(by: delta)
      try d.mapSelection(from: old, by: delta)
      try d.transformChannels(from:old,by:delta,method:method)
    case .rotateCanvas(let turn):
      let old = d
      let delta = turn.transform(width: d.width, height: d.height)
      for i in d.layers.indices {
        d.layers[i] = try DocumentGeometry.transformLayer(
          d.layers[i], by: delta, in: old, method: .nearest, includingUnlinkedMasks: true)
      }
      if turn == .clockwise || turn == .counterclockwise {
        d.width = old.height
        d.height = old.width
      }
      d.transformSavedPaths(by: delta)
      try d.mapSelection(from: old, by: delta)
      try d.transformChannels(from:old,by:delta)
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
      if let command = prepared.recordingCommand, case .paste = command {
        recordActionOperation(ActionOperation(recording: command, in: document), name: prepared.label)
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
