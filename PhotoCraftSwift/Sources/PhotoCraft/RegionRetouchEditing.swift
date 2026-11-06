import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct RegionRetouchDraft: Equatable {
  var frame: TransformDraft
  var request: RegionRetouchRequest
  var pattern: RasterPattern?
  func resolved() -> RegionRetouchRequest {
    var r = request
    r.dx = frame.centerX - Double(frame.bounds.x) - Double(frame.bounds.width)/2
    r.dy = frame.centerY - Double(frame.bounds.y) - Double(frame.bounds.height)/2
    r.scaleX = frame.scaleX; r.scaleY = frame.scaleY; r.angle = frame.angle
    if r.kind == .patch { r.dx = r.dx.rounded(); r.dy = r.dy.rounded(); if r.patchType == .normal { r.sampleAllLayers = false } }
    if r.kind == .redEye { r.sampleAllLayers = false }
    return r
  }
}
extension EditorTool {
  var regionRetouchKind: RegionRetouchRequest.Kind? {
    switch self { case .patch: .patch; case .contentAwareMove: .move; case .redEye: .redEye; default: nil }
  }
  var isRetouchSelectionTool: Bool { self == .patch || self == .contentAwareMove }
}
extension EditorStore {
  var patchPatterns: [RasterPattern] { pixelFillPatterns }
  var selectedPatchPattern: RasterPattern? {
    if let id = patchPatternID { return patchPatterns.first(where: { $0.id == id }) }
    return patchPatterns.first(where: { $0.id == patterns.selected?.id }) ?? patchPatterns.first
  }
  var canUsePatternPatch: Bool {
    guard tool == .patch, regionRetouchSettings.patchType == .normal, !patterns.busy,
      selectedPatchPattern != nil, !geometryBusy, !aiBusy, !hasToneDraft, !coalescingChanges,
      transformDraft == nil, !editingMask, !editingComponent, document.colorMode == .rgb, let layer = activeLayer,
      case .raster = layer.content, layer.smartObject == nil, layer.sourceProjection == nil,
      !document.isImageLocked(layer.id), document.selection != nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id] else { return false }
    return true
  }
  func usePatternPatch() {
    guard canUsePatternPatch, let layer = activeLayer, let bounds = document.selection,
      let pattern = selectedPatchPattern else { return }
    var request = RegionRetouchRequest(kind: .patch)
    request.diffusion = regionRetouchSettings.diffusion; request.transparent = regionRetouchSettings.transparent
    var frame = TransformDraft(layerID: layer.id, bounds: bounds)
    frame.proportional = false; frame.allowsFlips = false
    regionRetouchDraft = .init(frame: frame, request: request, pattern: pattern)
    refreshRegionRetouch(); regionRetouchCommitWhenReady = true; regionRetouchRevision += 1
  }
  var canBeginRegionRetouch: Bool {
    guard !geometryBusy,!aiBusy,!hasToneDraft,!coalescingChanges,transformDraft == nil,!editingMask,!editingComponent,
      document.width <= RegionRetouchPreparation.maximumCanvasPixels/document.height,
      let layer = activeLayer,case .raster = layer.content,layer.smartObject == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id] else { return false }
    return !document.isImageLocked(layer.id)
  }
  func beginRegionRetouch(kind: RegionRetouchRequest.Kind,region: IntRect? = nil) {
    guard canBeginRegionRetouch,let id = activeLayer?.id,let box = region ?? document.selection else { return }
    var request = regionRetouchSettings;request.kind = kind;request.region = region
    var frame = TransformDraft(layerID:id,bounds:box);frame.proportional = false;frame.allowsFlips = false
    regionRetouchDraft = RegionRetouchDraft(frame:frame,request:request)
    regionRetouchError = nil;regionRetouchRevision += 1
    if kind == .redEye { refreshRegionRetouch() }
  }
  func updateRegionRetouch(_ draft: RegionRetouchDraft) {
    guard regionRetouchDraft != nil else { return }
    regionRetouchDraft = draft;regionRetouchCommitWhenReady = false
    refreshRegionRetouch();regionRetouchRevision += 1
  }
  func updateRegionRetouchSettings(_ settings: RegionRetouchRequest) {
    regionRetouchSettings = settings
    if var d = regionRetouchDraft {
      let kind = d.request.kind,region = d.request.region
      d.request = settings;d.request.kind = kind;d.request.region = region;updateRegionRetouch(d)
    }
  }
  func refreshRegionRetouch() {
    regionRetouchTask?.cancel();regionRetouchPrepared = nil;regionRetouchReady = nil;regionRetouchError = nil
    guard let draft = regionRetouchDraft else { return }
    regionRetouchBusy = true
    let original = document, selfPatternPreparation = patternPatchPreparation
    let sourceSession = sessionGeneration, sourcePanel = layerPanelGeneration
    regionRetouchTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds:80_000_000)
        let worker = Task.detached(priority:.userInitiated) {
          if let pattern = draft.pattern {
            return try selfPatternPreparation(draft.resolved(),pattern,original,draft.frame.layerID)
          }
          return try RegionRetouchPreparation.prepare(draft.resolved(),document:original,layerID:draft.frame.layerID)
        }
        let edit = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self,self.regionRetouchDraft == draft else { return }
        guard self.document == original, self.sessionGeneration == sourceSession, self.layerPanelGeneration == sourcePanel else {
          self.cancelRegionRetouch(); return
        }
        self.regionRetouchPrepared = edit;self.regionRetouchReady = draft;self.regionRetouchPreview = edit.result
        self.regionRetouchBusy = false;self.render()
        if self.regionRetouchCommitWhenReady { self.commitRegionRetouch() }
      } catch {
        guard !Task.isCancelled,let self,self.regionRetouchDraft == draft else { return }
        self.regionRetouchBusy = false;self.regionRetouchError = error.localizedDescription;self.regionRetouchCommitWhenReady = false
      }
    }
  }
  func cancelRegionRetouch() {
    regionRetouchTask?.cancel();regionRetouchTask = nil;regionRetouchDraft = nil
    regionRetouchPrepared = nil;regionRetouchReady = nil;regionRetouchPreview = nil
    regionRetouchBusy = false;regionRetouchError = nil;regionRetouchCommitWhenReady = false
    regionRetouchRevision += 1;render()
  }
  @discardableResult func commitRegionRetouch() -> Bool {
    guard let draft = regionRetouchDraft else { return false }
    guard regionRetouchReady == draft,let edit = regionRetouchPrepared else {
      regionRetouchCommitWhenReady = regionRetouchBusy;return false
    }
    cancelRegionRetouch();performGeometry(.regionRetouch(edit));return true
  }
}
