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
  var newLayerDraft: NewLayerDraft?
  var newGroupDraft: NewGroupDraft?
  var duplicateLayerDraft: DuplicateLayerDraft?
  var layerNameDraft: LayerNameDraft?
  var layerPanelOptionsDraft: LayerPanelOptionsDraft?
  var channelPanelOptionsDraft: ChannelPanelOptionsDraft?
  var layerVisibilityDraft: LayerVisibilityDraft?
  @ObservationIgnored var layerVisibilityIsolation: LayerVisibilityIsolation?
  var confirmingLayerDeletion = false
  @ObservationIgnored var layerDeletionConfirmation:
    ((LayerDeletionRequest) -> LayerDeletionChoice)?
  var duplicateTask: Task<Void, Never>?
  @ObservationIgnored weak var documentController: CraftDocumentController?
  var gradientLibraryTask: Task<Void, Never>?
  var gradientSelectionAnchor: UUID?
  var cloneDraft: CloneDraft?
  var clonePrepareTask: Task<Void, Never>?
  var cloneOverlayTask: Task<Void, Never>?
  var cloneOverlayKey: CloneOverlayKey?
  var cloneOverlay: CloneOverlayImage?
  let clipboard: any ClipboardAccess
  var session: EditorSession
  var image: CGImage?
  var surface: Surface? { didSet { channelCompositeRevision = UUID() } }
  private(set) var channelCompositeRevision = UUID()
  @ObservationIgnored var renderSnapshot: RenderSnapshot?
  var selectionPath: CGPath?
  var tool: EditorTool = .move { didSet { unavailableToolID = nil } }
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
  var showLayerBounds = false
  var selectedLayerIDs: Set<UUID> = []
  var layoutTarget = LayerLayoutTarget.selection
  var pathTarget: PathTarget?
  var pathAnchor: PathAnchorSelection?
  var pathGesture: PathGesture?
  var penComponent: Int?
  var pathOperation = PathOperation.combine
  var layerMaskView: LayerMaskView?
  var renderedMaskView: LayerMaskView?
  var maskViewImage: CGImage?
  var maskEditingLayerID: UUID?
  var editingMask: Bool { activeLayer?.id == maskEditingLayerID && activeLayer?.mask != nil }
  var selectionMode = SelectionMode.replace
  var selectionFeather: Double = 0
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
  var transformDraft: TransformDraft?
  var geometrySheet: GeometrySheetKind?
  var levelsDraft: LevelsDraft?
  var curvesDraft: CurvesDraft?
  var hueSaturationDraft: HueSaturationDraft?
  var colorBalanceDraft: ColorBalanceDraft?
  var gradientMapDraft: GradientMapDraft?
  var tonalStepsDraft: TonalStepsDraft?
  var geometryBusy = false
  var geometryTask: Task<Void, Never>?
  var backgroundColor: Pixel = .white
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
  var brush = Brush()
  var zoom: Double = 0  // Zero requests the initial fit, resolved by the first canvas layout.
  var pan = CGSize.zero
  var revision = 0
  var error: String?
  var status = "Ready"
  var rendering = false
  var textDraft = "Your words here"
  var fontSize: Double = 72
  var prompt = ""
  var aiBusy = false
  var aiError: String?
  var showAI = false
  var showImagePlayground = false
  var coalescingChanges = false
  var coalescedDirty = false
  var onChange: ((NSDocument.ChangeType) -> Void)?
  var renderTask: Task<Void, Never>?
  var aiTask: Task<Void, Never>?
  var document: CraftDocument { session.document }
  var activeLayer: Layer? { document.activeIndex.map { document.layers[$0] } }
  init(
    document: CraftDocument, clipboard: (any ClipboardAccess)? = nil,
    cloneState: CloneSources? = nil, patterns: PatternLibrary? = nil,
    gradients: GradientLibrary? = nil
  ) {
    self.cloneState = cloneState ?? .shared
    self.patterns = patterns ?? .shared
    self.gradients = gradients ?? .shared
    self.clipboard = clipboard ?? SystemClipboard.shared
    session = EditorSession(document: document)
    brush.color = .black
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
  func executeEditorCommand(_ command: Command) throws {
    try validateComponentContext(command)
    let before = session.document
    try session.execute(command)
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
    guard transformDraft == nil, !hasToneDraft else { return }
    if modifiers.contains(.shift), let active = document.activeIndex,
      let destination = document.layers.firstIndex(where: { $0.id == id })
    {
      selectedLayerIDs = Set(
        document.layers[min(active, destination)...max(active, destination)].map(\.id))
    } else if modifiers.contains(.command) {
      if selectedLayerIDs.isEmpty, let active = document.activeLayerID {
        selectedLayerIDs.insert(active)
      }
      if selectedLayerIDs.contains(id) {
        selectedLayerIDs.remove(id)
      } else {
        selectedLayerIDs.insert(id)
      }
    } else {
      selectedLayerIDs = [id]
    }
    session.selectLayer(id)
    if case .vectorMask = pathTarget { selectPath(nil) }
    maskEditingLayerID = nil
    clearMaskView()
  }
  func undo() {
    finishNumericField()
    finishLayerName()
    guard !geometryBusy, !hasToneDraft else { return }
    if transformDraft != nil {
      cancelTransform()
      return
    }
    guard !session.undoStack.isEmpty else { return }
    resetPathGesture()
    session.undo()
    selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? [])
    onChange?(.changeUndone)
    render()
    status = "Undo"
  }
  func redo() {
    finishNumericField()
    finishLayerName()
    guard !geometryBusy, !hasToneDraft else { return }
    guard transformDraft == nil else { return }
    guard !session.redoStack.isEmpty else { return }
    resetPathGesture()
    session.redo()
    selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? [])
    onChange?(.changeRedone)
    render()
    status = "Redo"
  }
  func render() {
    if let draft = layerVisibilityDraft, draft.baseline != document { layerVisibilityDraft = nil }
    validateVisibilityIsolation()
    if let id = maskEditingLayerID,
      !document.layers.contains(where: { $0.id == id && $0.mask != nil })
    {
      maskEditingLayerID = nil
    }
    if currentMaskView == nil { clearMaskView() }
    let maskView = currentMaskView
    renderTask?.cancel()
    revision += 1
    let request = revision
    let doc = previewDocument
    let levels = levelsDraft
    let curves = curvesDraft
    let hueSaturation = hueSaturationDraft
    let colorBalance = colorBalanceDraft
    let tonalSteps = tonalStepsDraft
    let gradientMap = gradientMapDraft
    let clone = cloneDraft?.previewCommand
    let gradientFill = gradientFillDraft.flatMap { $0.preview ? $0.command : nil }
    let gradientGesture = gradientGesture?.command
    let gradientStopColor = gradientStopColorDraft?.command
    let patternFill = patternFillDraft.flatMap { $0.preview ? $0.command : nil }
    let channelView = channelView
    let previous = renderSnapshot
    rendering = true
    selectionPath = nil
    renderTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        var doc = doc
        if let levels, levels.preview {
          try Command.applyAdjustment(levels.id, .levels(levels.levels)).apply(to: &doc)
        }
        if let curves, curves.preview {
          try Command.applyAdjustment(curves.id, .curves(curves.curves)).apply(to: &doc)
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
        if let clone { try clone.apply(to: &doc) }
        if let gradientFill { try gradientFill.apply(to: &doc) }
        if let gradientGesture { try gradientGesture.apply(to: &doc) }
        if let gradientStopColor { try gradientStopColor.apply(to: &doc) }
        if let patternFill { try patternFill.apply(to: &doc) }
        let snapshot = try Renderer.render(doc, reusing: previous)
        let preview = try channelView.applying(to: snapshot.surface)
        let image = try RasterIO.displayImage(preview)
        let path = try doc.selectionMask.map { try SelectionOutline.path($0) }
        let maskImage: CGImage?
        if let maskView, let layer = doc.layers.first(where: { $0.id == maskView.layerID }) {
          maskImage = try RasterIO.displayImage(
            Renderer.maskPresentation(
              layer, mode: maskView.mode, width: doc.width, height: doc.height))
        } else {
          maskImage = nil
        }
        return (snapshot, image, path, maskImage)
      }
      do {
        let pair = try await withTaskCancellationHandler(
          operation: { try await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, let self, self.revision == request else { return }
        self.renderSnapshot = pair.0
        self.surface = pair.0.surface
        self.image = pair.1
        self.selectionPath = pair.2?.path
        if self.currentMaskView == maskView {
          self.maskViewImage = pair.3
          self.renderedMaskView = maskView
        }
        self.rendering = false
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
    guard let layer = activeLayer else { return }
    do {
      perform(.rasterize(layer.id, try Renderer.layerSurface(layer, in: document)))
    } catch { self.error = error.localizedDescription }
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
      maskEditingLayerID = id
      render()
    }
    if view?.layerID == id {
      layerMaskView = view
      render()
    }
  }
  func stroke(_ points: [StrokePoint], brush: Brush) {
    guard let layer = activeLayer else { return }
    perform(editingMask ? .maskStroke(layer.id, points, brush) : .stroke(layer.id, points, brush))
  }
  func clear() {
    if let layer = activeLayer { perform(editingMask ? .maskFill(layer.id, 0) : .clear(layer.id)) }
  }
  func fill(color: Pixel? = nil, opacity: Float = 1) {
    guard let layer = activeLayer else { return }
    let color = color ?? brush.color
    if editingComponent {
      do {
        guard color.r == color.g, color.g == color.b, color.a == 1 else {
          throw CraftError.unsupported(
            "Component Fill currently supports opaque neutral colors. Choose Black, 50% Gray or White."
          )
        }
        perform(try componentFillCommand(value: color.r, opacity: opacity))
      } catch { self.error = error.localizedDescription }
      return
    }
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
    guard let layer = document.layers.first(where: { $0.id == id }), layer.mask != nil else {
      return
    }
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
      if case .raster = layer.content { return true }
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
    layer.canApplyPixelMask && !document.isLocked(layer.id) && !geometryBusy
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
    if let r = document.selection {
      perform(.crop(r))
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
        guard var l = imported.layers.first else { return }
        l.x = (self.document.width - imported.width) / 2
        l.y = (self.document.height - imported.height) / 2
        self.perform(.addLayer(l))
      } catch { self.error = error.localizedDescription }
    }
  }
  func exportImage() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png, .jpeg, .tiff]
    panel.nameFieldStringValue = document.name + ".png"
    panel.title = "Export Flattened Image"
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      do {
        let type: UTType =
          url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
          ? .jpeg : ["tif", "tiff"].contains(url.pathExtension.lowercased()) ? .tiff : .png
        try RasterIO.write(self.document, to: url, type: type)
        self.status = "Exported \(url.lastPathComponent)"
      } catch { self.error = error.localizedDescription }
    }
  }
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
    guard let l = activeLayer, case .raster(let original) = l.content else {
      error = "Select a pixel layer or rasterize the current layer first."
      return
    }
    do {
      var result = try Renderer.gaussianBlur(original, radius: radius)
      if document.selection != nil {
        let doc = document
        result.mapPixels { x, y, p in
          let q = l.coordinateTransform.point(Double(x) + 0.5, Double(y) + 0.5)
          return original.pixel(x: x, y: y).mixing(
            p, coverage: doc.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y))))
        }
      }
      perform(.replaceContent(l.id, .raster(result)))
    } catch { self.error = error.localizedDescription }
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
    if item.id != selectedTool.id { cancelClone() }
    if item.id != selectedTool.id { cancelGradientGesture() }
    if transformDraft != nil { commitTransform() }
    if let native = item.native { tool = native } else { unavailableToolID = item.id }
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
    if cycle, let index = group.firstIndex(of: selectedTool) {
      chooseTool(group[(index + 1) % group.count])
    } else {
      chooseTool(group.first { $0.id == rememberedTools[group[0].id] } ?? group[0])
    }
    return true
  }
  func swapColors() { swap(&brush.color, &backgroundColor) }
  func resetColors() {
    brush.color = .black
    backgroundColor = .white
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
        guard let raster = try? Renderer.layerSurface(l, in: document),
          let inverse = try? l.coordinateTransform.inverted()
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
