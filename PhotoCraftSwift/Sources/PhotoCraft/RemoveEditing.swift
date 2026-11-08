import AppKit
import PhotoCraftCore
import PhotoCraftImaging

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
  var hasMarks: Bool { initialCoverage?.bounds != nil || !strokes.isEmpty }
  var request: RemoveRequest { .init(layerID:layerID,settings:settings,strokes:strokes,initialCoverage:initialCoverage) }
}

extension EditorStore {
  var canUseRemove: Bool {
    guard removeSettings.size.isFinite, (1...5000).contains(removeSettings.size),
      !geometryBusy, !aiBusy, !hasToneDraftExceptRemove, !coalescingChanges,
      transformDraft == nil, !editingComponent, !editingMask, !smartFilterMaskEditing,
      document.colorMode == .rgb, document.width > 0, document.height > 0,
      document.width <= Surface.maxDimension, document.height <= Surface.maxDimension,
      document.width <= RemovePreparation.maximumCanvasPixels/document.height,
      let layer = activeLayer, case .raster = layer.content, layer.smartObject == nil,
      layer.sourceProjection == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id],
      !document.ancestors(of:layer.id).contains(where: { $0.protection.fullyLocks }) else { return false }
    return removeSettings.mode != .generativeOn && (removeSettings.createNewLayer || !document.isImageLocked(layer.id))
  }
  func removeSourceMatches(_ draft: RemoveDraft) -> Bool {
    draft.original == document && draft.session == sessionGeneration && draft.generation == layerPanelGeneration
  }
  func updateRemoveSettings(_ settings: RemoveToolSettings) throws {
    try settings.validate()
    guard !geometryBusy, removeStroke == nil else { throw CraftError.invalid("Finish the current Remove stroke first.") }
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
      if removeDraft?.settings.removeAfterEachStroke == true, removeDraft?.initialCoverage == nil { applyRemove() }
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
    if removeDetectionID != nil {
      removeDetectionTask?.cancel(); removeDetectionTask = nil
      geometryTask?.cancel(); geometryTask = nil; geometryBusy = false; removeDetectionID = nil
    }
    if removeApplying != nil { geometryTask?.cancel() }
    removeDraft = nil; removeStroke = nil; removeApplying = nil; removeRevision = UUID()
  }
  func cancelRemoveGesture() {
    guard removeStroke != nil else { return }
    removeStroke = nil
    if removeDraft?.hasMarks == false { removeDraft = nil }
    removeRevision = UUID()
  }
  func applyRemove() {
    guard removeStroke == nil, let draft = removeDraft, draft.hasMarks else { return }
    guard canUseRemove, removeSourceMatches(draft) else {
      status = "The Remove source changed or is unavailable. Clear the pending strokes first."; return
    }
    removeDraft = nil; removeApplying = draft; removeRevision = UUID()
    let request = draft.request, prepare = removePreparation
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
