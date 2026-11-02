import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct ImageStackView: View {
  @Bindable var model: ImageStackWorkspace
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      Text(model.statistics ? "Image Statistics":"Load Layers").font(.headline)
      HStack(alignment:.top,spacing:20) {
        VStack(alignment:.leading,spacing:12) {
          TextField("Document name",text:$model.name)
          Text("Source Images").font(.subheadline)
          List(selection:$model.selected) { ForEach(model.sources) { Text($0.title).tag($0.id) } }.frame(height:240)
          HStack { Button("Browse…") { model.browse() };Button("Folder…") { model.browse(folder:true) } }.disabled(model.loading)
          HStack { Button("Add Open Files") { model.addOpenDocuments() };Button("Remove") { model.removeSelected() }.disabled(model.selected.isEmpty) }.disabled(model.loading)
          Toggle("Attempt to Automatically Align Source Images",isOn:$model.settings.align)
          Toggle("Create Smart Object after Loading Layers",isOn:$model.settings.createSmartObject).disabled(model.statistics)
          if model.settings.createSmartObject {
            Picker("Stack Mode",selection:$model.settings.mode) {
              Text("None").tag(ImageStackMode?.none)
              ForEach(ImageStackMode.allCases,id:\.self) { Text($0.title).tag(ImageStackMode?.some($0)) }
            }
          }
          Text("Median removes moving objects. Mean averages noise. Edit the Smart Object contents to change its source photos.").font(.caption).foregroundStyle(.secondary)
        }.frame(width:310)
        ZStack {
          Color.black.opacity(0.2)
          if let image = model.image { Image(decorative:image,scale:1).resizable().scaledToFit() }
          else { Text("Preview the image stack.").foregroundStyle(.secondary) }
          if model.loading || model.rendering { ProgressView() }
        }.frame(width:460,height:490)
      }
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).lineLimit(3).textSelection(.enabled) }
      HStack {
        Button("Preview") { model.refresh() }.disabled(model.loading || model.sources.count < 2)
        Spacer();Button("Cancel") { model.controller?.cancelImageStack() }.keyboardShortcut(.cancelAction)
        Button("OK") { do { try model.commit() } catch { model.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:830,height:630)
      .onChange(of:model.settings) { _,_ in if !model.settings.createSmartObject { model.settings.mode = nil };model.invalidate() }
      .onChange(of:model.name) { _,_ in model.invalidate() }
  }
}
@MainActor final class ImageStackWindow: NSWindowController,NSWindowDelegate {
  weak var documentController: CraftDocumentController?
  init(model: ImageStackWorkspace,owner: CraftDocumentController) {
    documentController = owner
    let window = PhotatoWindow(contentRect:NSRect(x:0,y:0,width:830,height:630),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title = model.statistics ? "Image Statistics":"Load Layers";window.contentView = NSHostingView(rootView:ImageStackView(model:model));window.isReleasedWhenClosed = false;window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) { nil }
  func windowWillClose(_ notification: Notification) { documentController?.cancelImageStack() }
}
extension CraftDocumentController {
  var canPublishImageStack: Bool {
    scanCropOperationID == nil && contactSheetWorkspace == nil && photomergeWorkspace == nil && hdrMergeWorkspace == nil && !documentOpening.isActive && !documentOpening.hasPendingRequests && documentOpenPanel == nil && !documentClosing.isActive && !recoveryIndex.isBusy && initialRecoveryTask == nil && NSApp?.modalWindow == nil
  }
  func beginImageStack(statistics: Bool = false,display: Bool = true) {
    guard canPublishImageStack else { return }
    if imageStackWorkspace == nil { imageStackWorkspace = ImageStackWorkspace(controller:self,statistics:statistics) }
    if display,let model = imageStackWorkspace {
      if imageStackWindow == nil { imageStackWindow = ImageStackWindow(model:model,owner:self) };imageStackWindow?.showWindow(nil)
    }
  }
  func cancelImageStack() { let window = imageStackWindow;imageStackWindow = nil;imageStackWorkspace?.close();imageStackWorkspace = nil;window?.close() }
}
extension EditorStore {
  func setImageStackMode(_ mode: ImageStackMode?) {
    guard canEditSmartObject,let layer = activeLayer,layer.smartObject?.rawDevelopment == nil,layer.smartObject?.pdfSource == nil else { return }
    performGeometry(label:"Stack Mode: " + (mode?.title ?? "None"),prepare:{ original in try ImageStack.command(in:original,layerID:layer.id,mode:mode) })
  }
}
extension AppDelegate {
  @objc func loadImageStack() { controller.beginImageStack() }
  @objc func imageStatistics() { controller.beginImageStack(statistics:true) }
  @objc func imageStackMode(_ sender: NSMenuItem) { store?.setImageStackMode(ImageStackMode.allCases.first{$0.title == sender.title}) }
}
