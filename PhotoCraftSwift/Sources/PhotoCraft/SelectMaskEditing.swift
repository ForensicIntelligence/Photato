import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canBeginSelectMask: Bool {
    guard !geometryBusy, !hasToneDraft, transformDraft == nil, !editingComponent,
      let layer = activeLayer, case .raster = layer.content, layer.smartObject == nil,
      selectedLayerIDs.isEmpty || selectedLayerIDs == [layer.id] else { return false }
    return (try? SelectionMatting.checkSize(document.width,document.height)) != nil
  }
  func beginSelectMask(fromMask: Bool = false,focus:Bool=false) {
    guard canBeginSelectMask, let id = activeLayer?.id else { return }
    let draft = SelectMaskWorkspace(); selectMaskDraft = draft
    let original = document
    draft.task = Task { await draft.prepare(original,layerID:id,fromMask:fromMask,focus:focus) }
  }
  func cancelSelectMask() { selectMaskDraft?.close(); selectMaskDraft = nil; render() }
  func commitSelectMask() {
    guard let draft = selectMaskDraft, draft.ready, (!draft.isFocus || draft.canCommit), let input = draft.input else { return }
    draft.end(); let state = draft.state,focus = draft.focusInput
    if draft.effectiveOutput.createsDocument && documentController == nil { draft.error = "No document controller is available."; return }
    draft.committing = true; draft.error = nil
    draft.commitTask = Task { [weak self, weak draft] in
      let worker = Task.detached(priority:.userInitiated) { () throws -> (PreparedEdit?, CraftDocument?) in
        let edit = try SelectMaskWorkspace.preparedEdit(input:input,focus:focus,state:state)
        if edit.output.createsDocument { return (nil as PreparedEdit?,try edit.applied(to:input.original)) }
        return (try PreparedEdit(command:state.focus != nil ? .focusArea(edit):.selectionRefinement(edit),document:input.original),nil as CraftDocument?)
      }
      do {
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, let draft, self.selectMaskDraft === draft, self.document == input.original else { throw CraftError.invalid("The source document changed during refinement.") }
        if let prepared = result.0 {
          try self.executeCompositePreparedEdit(prepared)
          self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? []); self.maskEditingLayerID = nil
          if self.document != input.original { self.onChange?(.changeDone) }
        } else if let model = result.1 {
          guard let controller = self.documentController,
            controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === self }), !controller.documentClosing.isActive else { throw CraftError.invalid("The source document closed.") }
          let created = CraftNSDocument(model:model); controller.addDocument(created); created.updateChangeCount(.changeDone)
          self.selectMaskDraft = nil; created.makeWindowControllers(); created.showWindows()
        }
        self.selectMaskDraft = nil; draft.close(); self.status = state.focus != nil ? "Focus Area":"Select and Mask"; self.render()
      } catch { if !Task.isCancelled { draft?.error = error.localizedDescription } }
      draft?.committing = false
    }
  }
}
extension AppDelegate {
  @objc func focusArea(){store?.beginSelectMask(focus:true)}
  @objc func selectAndMask() { store?.beginSelectMask(fromMask:store?.editingMask == true) }
}
