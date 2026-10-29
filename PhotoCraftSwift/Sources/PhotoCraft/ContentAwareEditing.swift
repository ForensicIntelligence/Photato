import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canBeginContentAwareFill: Bool {
    guard !geometryBusy,!aiBusy,!hasToneDraft,!coalescingChanges,transformDraft == nil,!editingComponent,!editingMask,
      document.selection != nil,document.width <= ContentAwareInput.maximumCanvasPixels/document.height,
      let layer = activeLayer,case .raster = layer.content,layer.smartObject == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id] else { return false }
    return !document.ancestors(of:layer.id).contains { $0.protection.fullyLocks }
  }
  func beginContentAwareFill() {
    guard canBeginContentAwareFill,let id = activeLayer?.id else { return }
    let draft = ContentAwareWorkspace(),original = document; contentAwareDraft = draft
    draft.task = Task { await draft.prepare(original,layerID:id) }
  }
  func cancelContentAwareFill() { contentAwareDraft?.close(); contentAwareDraft = nil; render() }
  func commitContentAwareFill() {
    guard let draft = contentAwareDraft,draft.canCommit,let edit = draft.edit,let input = draft.input else { return }
    draft.committing = true
    draft.commitTask = Task { [weak self,weak draft] in
      do {
        let worker = Task.detached(priority:.userInitiated) { try PreparedEdit(command:.contentAwareFill(edit),document:input.original) }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self,let draft,self.contentAwareDraft === draft,self.document == input.original else { throw CraftError.invalid("Source document changed during Content-Aware Fill.") }
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
        if self.document != input.original { self.onChange?(.changeDone) }
        self.contentAwareDraft = nil; self.status = "Content-Aware Fill"; draft.close(); self.render()
      } catch { if !Task.isCancelled { draft?.error = error.localizedDescription } }
      draft?.committing = false
    }
  }
}
extension AppDelegate {
  @objc func contentAwareFill() { store?.beginContentAwareFill() }
}
