import AppKit
import PhotoCraftCore
import PhotoCraftImaging

@MainActor extension AppDelegate {
  @objc func newVideoLayer(){store?.presentMovieLayerImport()}
}
extension EditorStore {
  var canImportMovieLayer:Bool {canUseTimeline && timelineTask==nil && document.animation==nil && !document.hasArtboards && !document.hasAuthoritativeModeStorage && document.layers.count<LayerLimits.maximumLayers && isCompositeColorTarget}
  func importMovieLayer(_ url:URL) async throws {
    guard canImportMovieLayer else{throw CraftError.invalid("Finish the current edit and select an RGB target before importing video.")}
    let source=document,generation=layerPanelGeneration,operation=UUID()
    geometryBusy=true;moviePlacementID=operation;renderTask?.cancel()
    let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
    defer{if layerPanelGeneration==generation{geometryBusy=false;geometryTask=nil;moviePlacementID=nil;render()}}
    let worker=Task.detached(priority:.userInitiated) {
      let imported=try PreparedLocalDocument.read(url,format:.movie).model
      return try PreparedEdit(command:.video(.insert(MovieIO.layer(from:imported,into:source))),document:source)
    }
    let observer=Task{await withTaskCancellationHandler{_=try? await worker.value} onCancel:{worker.cancel()}};geometryTask=observer
    let prepared=try await withTaskCancellationHandler{try await worker.value} onCancel:{worker.cancel()}
    try Task.checkCancellation();guard !observer.isCancelled,layerPanelGeneration==generation,document==source else{throw CancellationError()}
    try executeCompositePreparedEdit(prepared)
    selectedLayerIDs=Set(document.activeLayerID.map{[$0]} ?? []);timelineVisible=true;onChange?(.changeDone);status="Imported video layer"
  }
  func presentMovieLayerImport() {
    guard canImportMovieLayer else{return}
    let panel=NSOpenPanel();panel.title="New Video Layer from File";panel.allowedContentTypes=[.quickTimeMovie,.mpeg4Movie];panel.allowsMultipleSelection=false
    panel.message="Choose a movie to add at the Timeline playhead. Original audio is retained for Timeline playback, volume, mute and fades."
    let window=NSApp.keyWindow
    let finish:(NSApplication.ModalResponse)->Void = {[weak self] response in
      guard response == .OK,let self,let url=panel.url else{return}
      let progress=NSAlert();progress.messageText="Importing Video";progress.informativeText="Decoding movie frames…";progress.addButton(withTitle:"Cancel")
      let task=Task{@MainActor in
        defer{if let parent=progress.window.sheetParent{parent.endSheet(progress.window,returnCode:.OK)}}
        do{try await self.importMovieLayer(url)}catch is CancellationError{self.status="Video import cancelled"}catch{self.error=error.localizedDescription}
      }
      if let window{progress.beginSheetModal(for:window){if $0 != .OK{task.cancel()}}}
    }
    if let window{panel.beginSheetModal(for:window,completionHandler:finish)}else{panel.begin(completionHandler:finish)}
  }
}
