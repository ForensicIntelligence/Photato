import AppKit
import PhotoCraftCore

extension EditorStore {
  func canBeginProcedural(_ kind:ProceduralRenderSettings.Kind)->Bool {
    guard !geometryBusy,!aiBusy,!hasToneDraft,!coalescingChanges,transformDraft==nil,!editingComponent,!editingMask,!smartFilterMaskEditing,
      document.width<=ProceduralRenderEngine.maximumPixels/document.height,
      let layer=activeLayer,case .raster=layer.content,layer.smartObject==nil,
      !document.isImageLocked(layer.id),!document.isLocked(layer.id),
      selectedLayerIDs.isEmpty || selectedLayerIDs==[layer.id] else{return false}
    return kind != .flame || selectedVectorPath != nil || !(document.paths?.isEmpty ?? true)
  }
  func beginProcedural(_ kind:ProceduralRenderSettings.Kind) {
    guard canBeginProcedural(kind) else{return}
    let request=ProceduralRenderRequest(.init(kind),layerID:document.activeLayerID,path:kind == .flame ? selectedVectorPath:nil)
    let model=ProceduralWorkspace(document:document,request:request);proceduralWorkspace=model;model.refresh()
  }
  func cancelProcedural() {proceduralWorkspace?.close();proceduralWorkspace=nil;render()}
  func commitProcedural() {
    guard let draft=proceduralWorkspace,draft.ready else{return}
    draft.endGesture();draft.committing=true;let request=draft.request,original=draft.source
    draft.commitTask=Task { [weak self,weak draft] in
      do {
        let worker=Task.detached(priority:.userInitiated) {try PreparedEdit(command:.proceduralRender(request),document:original)}
        let prepared=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,let draft,self.proceduralWorkspace === draft,self.document==original else{throw CraftError.invalid("Source document changed during Render.")}
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs=Set(self.document.activeLayerID.map{[$0]} ?? [])
        if self.document != original {self.onChange?(.changeDone)}
        self.proceduralWorkspace=nil;self.status=request.settings.kind.title;draft.close();self.render()
      } catch {if !Task.isCancelled {draft?.error=error.localizedDescription}}
      draft?.committing=false
    }
  }
}
extension AppDelegate {
  static let proceduralMenus:[String:ProceduralRenderSettings.Kind]=Dictionary(uniqueKeysWithValues:ProceduralRenderSettings.Kind.allCases.map{("Filter > Render > \($0.title)…",$0)})
  @objc func proceduralRenderDialog(_ sender:NSMenuItem) {
    guard let kind=Self.proceduralMenus[sender.identifier?.rawValue ?? ""] else{return};store?.beginProcedural(kind)
  }
}
