import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct PhotomergeView: View {
  @Bindable var model: PhotomergeWorkspace
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Photomerge").font(.headline)
      HStack(alignment:.top,spacing:18) {
        VStack(alignment:.leading,spacing:12) {
          GroupBox("Layout") {
            Picker("Projection",selection:$model.settings.projection) {
              ForEach(PhotoAlignSettings.Projection.allCases,id:\.self) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup).labelsHidden().padding(7)
          }
          TextField("Panorama name",text:$model.name)
          Toggle("Blend Images Together",isOn:$model.settings.blendImages)
          Toggle("Content Aware Fill Transparent Areas",isOn:$model.settings.fillTransparentAreas)
          Text("Combine overlapping photos into a new document. Each source remains available as a layer.").font(.caption).foregroundStyle(.secondary)
        }.frame(width:230)
        VStack(alignment:.leading,spacing:10) {
          Text("Source Files").font(.subheadline)
          List(selection:$model.selected) { ForEach(model.sources) { source in
            VStack(alignment:.leading,spacing:3) {
              Text(source.title).lineLimit(1)
              Text("\(source.model.width) × \(source.model.height)\(source.document == nil ? "":" · Open document")").font(.caption).foregroundStyle(.secondary)
            }.tag(source.id)
          } }.frame(height:140)
          HStack {
            Button("Browse…") { model.browse() }
            Button("Folder…") { model.browse(folder:true) }
            Button("Add Open Files") { model.addOpenDocuments() }
            Button("Remove") { model.removeSelected() }.disabled(model.selected.isEmpty)
          }.disabled(model.loading)
          ZStack {
            Color.black.opacity(0.16)
            if let image = model.image { Image(decorative:image,scale:1).resizable().scaledToFit() }
            else { Text("Preview the panorama before creating it.").font(.caption).foregroundStyle(.secondary) }
            if model.rendering || model.loading { ProgressView() }
          }.frame(height:230)
        }.frame(minWidth:470)
      }
      if let result = model.result { Text("\(result.document.width) × \(result.document.height) · \(result.projection.title) · \(result.matchedPoints) matching points").font(.caption).foregroundStyle(.secondary) }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Preview") { model.refresh() }.disabled(model.loading || model.sources.count < 2)
        Spacer()
        Button("Cancel") { model.controller?.cancelPhotomerge() }.keyboardShortcut(.cancelAction)
        Button("OK") { do { try model.commit() } catch { model.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:780,height:590)
      .onChange(of:model.settings) { _,_ in model.invalidate() }
      .onChange(of:model.name) { _,_ in model.invalidate() }
  }
}
@MainActor final class PhotomergeWindow: NSWindowController,NSWindowDelegate {
  weak var documentController: CraftDocumentController?
  init(model: PhotomergeWorkspace,owner: CraftDocumentController) {
    self.documentController = owner
    let window = PhotatoWindow(contentRect:NSRect(x:0,y:0,width:780,height:590),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title = "Photomerge";window.contentView = NSHostingView(rootView:PhotomergeView(model:model));window.isReleasedWhenClosed = false;window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) { nil }
  func windowWillClose(_ notification: Notification) { documentController?.cancelPhotomerge() }
}
extension CraftDocumentController {
  var canPublishPhotomerge: Bool {
    scanCropOperationID == nil && contactSheetWorkspace == nil && imageStackWorkspace == nil && hdrMergeWorkspace == nil && !documentOpening.isActive && !documentOpening.hasPendingRequests && documentOpenPanel == nil && !documentClosing.isActive && !recoveryIndex.isBusy && initialRecoveryTask == nil && NSApp?.modalWindow == nil
  }
  func beginPhotomerge(display: Bool = true) {
    guard canPublishPhotomerge else { return }
    if photomergeWorkspace == nil { photomergeWorkspace = PhotomergeWorkspace(controller:self) }
    if display,let model = photomergeWorkspace {
      if photomergeWindow == nil { photomergeWindow = PhotomergeWindow(model:model,owner:self) };photomergeWindow?.showWindow(nil)
    }
  }
  func cancelPhotomerge() {
    let window = photomergeWindow;photomergeWindow = nil;photomergeWorkspace?.close();photomergeWorkspace = nil;window?.close()
  }
}
extension AppDelegate { @objc func photomerge() { controller.beginPhotomerge() } }
