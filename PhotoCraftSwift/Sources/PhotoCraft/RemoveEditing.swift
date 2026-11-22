import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum RemoveProcessing: String, CaseIterable {
  case traditional, localFillWhenEligible, localFill, unavailable

  var title: String {
    switch self {
    case .traditional: "Traditional"
    case .localFillWhenEligible, .localFill: "Device"
    case .unavailable: "Model unavailable"
    }
  }
}

struct RemoveDraft: Sendable {
  let original: CraftDocument
  let session: UUID
  let generation: UUID
  let layerID: UUID
  let settings: RemoveToolSettings
  var strokes: [RemoveStroke] = []
  var initialCoverage: SelectionMask?
  var initialOverlay: CGImage?
  var detectedPeople = 0
  var distractionReview: RemoveDistractionReview?
  var requiresExplicitApply: Bool { initialCoverage != nil || distractionReview != nil }
  var hasMarks: Bool { initialCoverage?.bounds != nil || distractionReview?.enabled.isEmpty == false || !strokes.isEmpty }
  var request: RemoveRequest {
    .init(layerID: layerID, settings: settings, strokes: strokes, initialCoverage: initialCoverage,
      categoryCoverages: distractionReview?.selectedGroups.map(\.coverage) ?? [])
  }
}

extension EditorStore {
  var localRemoveModel: URL? { LocalGenerativeFill.supported ? GenerativeFillModelPreference.url() : nil }

  var localRemoveAvailable: Bool {
    localRemoveIsAvailable(in: document)
  }

  private func localRemoveIsAvailable(in source: CraftDocument) -> Bool {
    RemovePreparation.supportsLocalProcessing(source) && (removeLocalPreparation != nil || localRemoveModel != nil)
  }

  func removeProcessing(_ settings: RemoveToolSettings, in source: CraftDocument) -> RemoveProcessing {
    switch settings.mode {
    case .generativeOff: .traditional
    case .auto: localRemoveIsAvailable(in: source) ? .localFillWhenEligible : .traditional
    case .generativeOn: localRemoveIsAvailable(in: source) ? .localFill : .unavailable
    }
  }

  func removeWorker(for draft: RemoveDraft) throws -> @Sendable (RemoveRequest, CraftDocument) throws -> RegionRetouchEdit {
    let mode = draft.settings.mode
    if mode != .generativeOff, RemovePreparation.supportsLocalProcessing(draft.original) {
      if let removeLocalPreparation { return removeLocalPreparation }
      if let model = localRemoveModel {
        return { request, source in try RemovePreparation.prepareGenerative(request, document: source, model: model) }
      }
    }
    if mode == .generativeOn { throw CraftError.unavailable("Generative AI on requires an eligible RGB document and the on-device LaMa512 model.") }
    return removePreparation
  }

  var canUseRemove: Bool {
    guard canUseRemoveTarget else { return false }
    switch removeProcessing(removeSettings, in: document) {
    case .unavailable: return false
    case .traditional: return document.width <= RemovePreparation.maximumCanvasPixels / document.height
    case .localFill, .localFillWhenEligible: return true
    }
  }

  var canUseRemoveTarget: Bool {
    guard removeSettings.size.isFinite, (1...5000).contains(removeSettings.size),
      !geometryBusy, !aiBusy, !hasToneDraftExceptRemove, !coalescingChanges,
      transformDraft == nil, !editingComponent, !editingMask, !smartFilterMaskEditing,
      document.colorMode == .rgb, document.width > 0, document.height > 0,
      document.width <= Surface.maxDimension, document.height <= Surface.maxDimension,
      let layer = activeLayer, case .raster = layer.content, layer.smartObject == nil,
      layer.sourceProjection == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id],
      !document.ancestors(of:layer.id).contains(where: { $0.protection.fullyLocks }) else { return false }
    return removeSettings.createNewLayer || !document.isImageLocked(layer.id)
  }
  func removeSourceMatches(_ draft: RemoveDraft) -> Bool {
    draft.original == document && draft.session == sessionGeneration && draft.generation == layerPanelGeneration
  }
  func updateRemoveSettings(_ settings: RemoveToolSettings) throws {
    try settings.validate()
    guard !geometryBusy, removeStroke == nil else { throw CraftError.invalid("Finish the current Remove stroke first.") }
    if settings.mode == .generativeOn, settings.mode != removeSettings.mode, !localRemoveAvailable {
      throw CraftError.unavailable("Choose the on-device LaMa512 model for an eligible RGB document first.")
    }
    if let draft = removeDraft {
      guard settings.mode == draft.settings.mode,
        settings.sampleAllLayers == draft.settings.sampleAllLayers,
        settings.removeAfterEachStroke == draft.settings.removeAfterEachStroke,
        settings.createNewLayer == draft.settings.createNewLayer else {
        throw CraftError.invalid("Apply or clear pending Remove strokes before changing processing options.")
      }
    }
    guard settings != removeSettings else { return }
    removeSettings = settings; removeRevision = UUID()
  }
  @discardableResult func beginRemoveStroke(at point: CGPoint, alternate: Bool) -> Bool {
    guard canUseRemove, removeStroke == nil, point.x.isFinite, point.y.isFinite,
      abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000 else { return false }
    if let draft = removeDraft, !removeSourceMatches(draft) {
      cancelRemove(); status = "The source changed. Draw the removal area again."; return false
    }
    if removeDraft == nil, let id = activeLayer?.id {
      removeDraft = .init(original:document,session:sessionGeneration,generation:layerPanelGeneration,
        layerID:id,settings:removeSettings)
    }
    removeStroke = .init(size:removeSettings.size,subtract:removeSettings.subtract != alternate,
      points:[[point.x,point.y]])
    removeRevision = UUID(); return true
  }
  func extendRemoveStroke(to point: CGPoint) {
    guard var stroke = removeStroke, stroke.points.count < 4096,
      point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000,
      stroke.points.last != [point.x,point.y] else { return }
    stroke.points.append([point.x,point.y]); removeStroke = stroke
  }
  func finishRemoveStroke(at point: CGPoint) {
    extendRemoveStroke(to:point)
    guard let stroke = removeStroke else { return }; removeStroke = nil
    do {
      try appendRemoveStroke(stroke)
      if removeDraft?.settings.removeAfterEachStroke == true, removeDraft?.requiresExplicitApply != true { applyRemove() }
    } catch { status = error.localizedDescription }
  }
  func appendRemoveStroke(_ stroke: RemoveStroke) throws {
    try stroke.validate()
    guard canUseRemove else { throw CraftError.invalid("Remove is unavailable for the current editing target.") }
    if removeDraft == nil, let id = activeLayer?.id {
      removeDraft = .init(original:document,session:sessionGeneration,generation:layerPanelGeneration,
        layerID:id,settings:removeSettings)
    }
    guard var draft = removeDraft, removeSourceMatches(draft) else {
      throw CraftError.invalid("The Remove source changed. Clear the pending strokes first.")
    }
    draft.strokes.append(stroke); try draft.request.validate()
    removeDraft = draft; removeRevision = UUID()
  }
  func cancelRemove() {
    if removeWiresID != nil {
      geometryTask?.cancel(); removeWiresID = nil
    }
    if removeDetectionID != nil || removeDistractionID != nil {
      removeDetectionTask?.cancel(); removeDetectionTask = nil
      geometryTask?.cancel(); geometryTask = nil; geometryBusy = false; removeDetectionID = nil; removeDistractionID = nil
    }
    if removeApplying != nil { geometryTask?.cancel() }
    removeDraft = nil; removeStroke = nil; removeApplying = nil; removeRevision = UUID()
  }
  func cancelRemoveGesture() {
    guard removeStroke != nil else { return }
    removeStroke = nil
    if removeDraft?.hasMarks == false, removeDraft?.distractionReview == nil { removeDraft = nil }
    removeRevision = UUID()
  }
  func applyRemove() {
    guard removeStroke == nil, let draft = removeDraft, draft.hasMarks else { return }
    guard canUseRemove, removeSourceMatches(draft) else {
      status = "The Remove source changed or is unavailable. Clear the pending strokes first."; return
    }
    let prepare: @Sendable (RemoveRequest, CraftDocument) throws -> RegionRetouchEdit
    do { prepare = try removeWorker(for: draft) }
    catch { status = error.localizedDescription; return }
    removeDraft = nil; removeApplying = draft; removeRevision = UUID()
    let request = draft.request
    performGeometry(label:"Remove",prepare:{ original in
      guard original == draft.original else { throw CraftError.invalid("The Remove source changed.") }
      return .regionRetouch(try prepare(request,original))
    },onSuccess:{ [weak self] in
      guard let self else { return }
      self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
    })
    let pending = geometryTask
    removeCompletionTask = Task { [weak self] in
      await pending?.value
      guard let self, self.removeApplying?.session == draft.session else { return }
      self.removeApplying = nil
      if self.removeSourceMatches(draft), self.error != nil { self.removeDraft = draft }
      self.removeRevision = UUID()
    }
  }
}
