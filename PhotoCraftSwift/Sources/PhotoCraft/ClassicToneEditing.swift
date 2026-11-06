import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func canBeginClassicTone(_ kind:ClassicToneSettings.Kind)->Bool {
    guard !geometryBusy,!aiBusy,!hasToneDraft,!coalescingChanges,transformDraft==nil,!editingComponent,!editingMask,!smartFilterMaskEditing,
      document.width<=ClassicToneEngine.maximumPixels(for:kind)/document.height else{return false}
    if kind == .hdrToning{return !document.layers.isEmpty}
    guard let layer=activeLayer,selectedLayerIDs.isEmpty || selectedLayerIDs==[layer.id] else{return false}
    return (try? ClassicToneEngine.validateTarget(.init(.init(kind),layerID:layer.id),in:document)) != nil
  }
  var activeClassicToneWorkspace:ClassicToneWorkspace? {classicToneWorkspace ?? shadowWorkspace}
  func beginClassicTone(_ kind:ClassicToneSettings.Kind) {
    guard canBeginClassicTone(kind) else{return}
    if kind == .shadowsHighlights {beginFilter(.shadowsHighlights);return}
    var settings=ClassicToneSettings(kind)
    if kind == .replaceColor {var color=brush.color;color.a=1;settings.samples=[ToneColorSample(color:color)]}
    let request=ClassicToneRequest(settings,layerID:kind == .hdrToning ? nil:document.activeLayerID)
    if kind == .equalize,document.selection==nil {performGeometry(label:kind.title){_ in .toneAdjustment(request)};return}
    let documents=NSDocumentController.shared.documents.compactMap{($0 as? CraftNSDocument)?.store.document}
    let model=ClassicToneWorkspace(document:document,request:request,sources:documents);classicToneWorkspace=model;model.refresh()
  }
  func cancelClassicTone() {classicToneWorkspace?.close();classicToneWorkspace=nil;render()}
  func commitClassicTone() {
    guard let draft=classicToneWorkspace,draft.ready else{return}
    draft.endGesture();draft.committing=true;let request=draft.request,original=draft.source
    draft.commitTask=Task { [weak self,weak draft] in
      do {
        let worker=Task.detached(priority:.userInitiated) {try PreparedEdit(command:ClassicToneInput.command(request,in:original),document:original)}
        let prepared=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,let draft,self.classicToneWorkspace === draft,self.document==original else{throw CraftError.invalid("Source document changed during the adjustment.")}
        try self.executeCompositePreparedEdit(prepared)
        self.selectedLayerIDs=Set(self.document.activeLayerID.map{[$0]} ?? [])
        if self.document != original {self.onChange?(.changeDone)}
        self.classicToneWorkspace=nil;self.status=request.settings.kind.title;draft.close();self.render()
      } catch {if !Task.isCancelled {draft?.error=error.localizedDescription}}
      draft?.committing=false
    }
  }
}
extension AppDelegate {
  static let classicToneMenus:[String:ClassicToneSettings.Kind]=Dictionary(uniqueKeysWithValues:ClassicToneSettings.Kind.allCases.map{("Image > Adjustments > \($0.title)"+($0 == .equalize ? "":"…"),$0)})
  @objc func classicToneDialog(_ sender:NSMenuItem) {
    guard let kind=Self.classicToneMenus[sender.identifier?.rawValue ?? ""] else{return};store?.beginClassicTone(kind)
  }
}
