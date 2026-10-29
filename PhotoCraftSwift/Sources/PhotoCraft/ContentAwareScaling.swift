import AppKit
import PhotoCraftCore

extension TransformDraft {
  var referencePoint: CGPoint {
    let f = referenceAnchor.fractions
    return CGPoint(x:centerX+(f.0-0.5)*Double(bounds.width)*scaleX/100,y:centerY+(f.1-0.5)*Double(bounds.height)*scaleY/100)
  }
  func scaleRequest() throws -> ContentAwareScaleRequest {
    let w = Double(bounds.width)*scaleX/100,h = Double(bounds.height)*scaleY/100
    guard w.isFinite,h.isFinite,(1...60000).contains(w),(1...60000).contains(h),centerX.isFinite,centerY.isFinite,abs(centerX) <= 1_000_000,abs(centerY) <= 1_000_000,angle == 0 else { throw CraftError.invalid("Content-Aware Scale requires positive dimensions up to60000 pixels and no rotation.") }
    let width = Int(w.rounded()),height = Int(h.rounded())
    var r = ContentAwareScaleRequest(width:width,height:height,x:Int(floor(centerX-Double(width)/2)),y:Int(floor(centerY-Double(height)/2)))
    r.amount = Float(amount);r.protectChannelID = protectChannelID;r.protectSkinTones = protectSkinTones;try r.validate();return r
  }
}
extension EditorStore {
  var canBeginContentAwareScale: Bool {
    guard !geometryBusy,!aiBusy,!hasToneDraft,!coalescingChanges,transformDraft == nil,!editingComponent,!editingMask,
      document.width <= SeamCarving.maximumPixels/document.height,let layer = activeLayer,case .raster = layer.content,layer.smartObject == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id],!document.isImageLocked(layer.id),!document.isPositionLocked(layer.id),!document.isTransparencyLocked(layer.id) else { return false }
    return (try? ContentAwareScaleEdit.bounds(document,layerID:layer.id)) != nil
  }
  func beginContentAwareScale() {
    guard canBeginContentAwareScale,let id = activeLayer?.id else { return }
    do { var draft = TransformDraft(layerID:id,bounds:try ContentAwareScaleEdit.bounds(document,layerID:id));draft.contentAware = true;draft.proportional = false;transformDraft = draft;tool = .move;status = "Content-Aware Scale · Return to apply · Escape to cancel";refreshContentAwareScale() }
    catch { self.error = error.localizedDescription }
  }
  func clearContentAwareScale() {
    contentAwareScaleTask?.cancel();contentAwareScaleTask = nil;contentAwareScalePreview = nil;contentAwareScalePrepared = nil;contentAwareScaleReadyDraft = nil;contentAwareScaleBusy = false;contentAwareScaleError = nil
  }
  func refreshContentAwareScale() {
    contentAwareScaleTask?.cancel();contentAwareScaleReadyDraft = nil;contentAwareScalePrepared = nil;contentAwareScaleError = nil
    guard let draft = transformDraft,draft.contentAware else { return }
    let original = document;contentAwareScaleBusy = true
    contentAwareScaleTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds:80_000_000)
        let request = try draft.scaleRequest()
        let worker = Task.detached(priority:.userInitiated) { let edit = try ContentAwareScaleEdit.prepare(original,layerID:draft.layerID,request:request);return (edit,try edit.applied(to:original)) }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,self.transformDraft == draft,self.document == original else { return }
        self.contentAwareScalePrepared = result.0;self.contentAwareScalePreview = result.1;self.contentAwareScaleReadyDraft = draft;self.contentAwareScaleBusy = false;self.render()
      } catch { guard !Task.isCancelled,let self,self.transformDraft == draft else { return };self.contentAwareScaleBusy = false;self.contentAwareScaleError = error.localizedDescription }
    }
  }
}
extension AppDelegate { @objc func contentAwareScale() { store?.beginContentAwareScale() } }
