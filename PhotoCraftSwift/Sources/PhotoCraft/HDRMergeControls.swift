import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

struct HDRMergeView: View {
  @Bindable var model: HDRMergeWorkspace
  private func slider(_ title: String,_ value: Binding<Float>,_ bounds: ClosedRange<Float>) -> some View {
    VStack(alignment:.leading,spacing:2) { HStack { Text(title);Spacer();Text(value.wrappedValue,format:.number.precision(.fractionLength(2))).monospacedDigit() };Slider(value:value,in:bounds) }.font(.caption)
  }
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Merge to HDR Pro").font(.headline)
      HStack(alignment:.top,spacing:14) {
        VStack(alignment:.leading,spacing:9) {
          TextField("Document name",text:$model.name)
          Text("Source Images").font(.subheadline)
          List(selection:$model.selected) { ForEach(model.sources) { source in
            VStack(alignment:.leading,spacing:3) {
              Text(source.title).lineLimit(1)
              if model.settings.exposureSource == .manual {
                HStack { Text("EV");TextField("EV",value:Binding(get:{model.manualEV[source.id] ?? 0},set:{model.manualEV[source.id] = $0;model.invalidate()}),format:.number).frame(width:70) }
              } else { Text(HDRMerge.exposureFactor(source.model) == nil ? "No exposure metadata":"Exposure metadata available").font(.caption).foregroundStyle(.secondary) }
            }.tag(source.id)
          } }.frame(height:230)
          HStack { Button("Browse…") { model.browse() };Button("Folder…") { model.browse(folder:true) } }.disabled(model.loading)
          HStack { Button("Add Open Files") { model.addOpenDocuments() };Button("Remove") { model.removeSelected() }.disabled(model.selected.isEmpty) }.disabled(model.loading)
          Picker("Exposure",selection:$model.settings.exposureSource) {
            Text("Camera Metadata").tag(HDRMergeSettings.ExposureSource.metadata)
            Text("Manual EV").tag(HDRMergeSettings.ExposureSource.manual)
            Text("Estimate from Images").tag(HDRMergeSettings.ExposureSource.estimate)
          }
          Toggle("Attempt to Automatically Align Source Images",isOn:$model.settings.align)
          Toggle("Remove Ghosts",isOn:$model.settings.removeGhosts)
          Picker("Base Image",selection:$model.settings.ghostBase) {
            Text("Automatic").tag(Int?.none)
            ForEach(Array(model.sources.enumerated()),id:\.element.id) { i,source in Text(source.title).tag(Int?.some(i)) }
          }.disabled(!model.settings.removeGhosts)
          Text("Use photographs of the same scene at different exposures. Originals stay unchanged.").font(.caption).foregroundStyle(.secondary)
        }.frame(width:260)
        VStack(alignment:.leading,spacing:10) {
          ZStack {
            Color.black.opacity(0.2)
            if let image = model.image { Image(decorative:image,scale:1).resizable().scaledToFit() }
            else { Text("Preview the HDR merge.").foregroundStyle(.secondary) }
            if model.rendering || model.loading { ProgressView() }
          }.frame(height:470)
          if model.settings.depth == .f32 {
            HStack { Text("Preview Exposure");Slider(value:$model.previewExposure,in:-10...10);Text(model.previewExposure,format:.number.precision(.fractionLength(1))).monospacedDigit() }
            Text("Preview brightness only; all32-bit HDR values are retained.").font(.caption).foregroundStyle(.secondary)
          }
        }.frame(minWidth:410)
        ScrollView {
          VStack(alignment:.leading,spacing:10) {
            Picker("Mode",selection:$model.settings.depth) { ForEach(PixelDepth.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
            if model.settings.depth != .f32 {
              Picker("Method",selection:$model.settings.method) { ForEach(HDRMergeSettings.Method.allCases,id:\.self) { Text($0.title).tag($0) } }
              if model.settings.method == .localAdaptation {
                slider("Radius",$model.settings.radius,1...500);slider("Strength",$model.settings.strength,0.1...4)
              }
              if [.localAdaptation,.exposureGamma].contains(model.settings.method) {
                slider("Gamma",$model.settings.gamma,0.1...4);slider("Exposure",$model.settings.exposure,-5...5)
              }
              if model.settings.method == .localAdaptation {
                slider("Detail",$model.settings.detail,-100...300);slider("Shadow",$model.settings.shadows,-100...100)
                slider("Highlight",$model.settings.highlights,-100...100);slider("Vibrance",$model.settings.vibrance,-100...100);slider("Saturation",$model.settings.saturation,-100...100)
              }
            }
          }
        }.frame(width:230,height:540)
      }
      if let result = model.result {
        Text("\(result.document.width) × \(result.document.height) · \(result.stops,format:.number.precision(.fractionLength(1))) stops · \(result.ghostFraction*100,format:.number.precision(.fractionLength(1)))% ghost removal").font(.caption).foregroundStyle(.secondary)
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).lineLimit(3) }
      HStack {
        Button("Preview") { model.refresh() }.disabled(model.loading || model.sources.count < 2)
        Spacer();Button("Cancel") { model.controller?.cancelHDRMerge() }.keyboardShortcut(.cancelAction)
        Button("OK") { do { try model.commit() } catch { model.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:1000,height:740)
      .onChange(of:model.settings) { _,_ in model.invalidate() }
      .onChange(of:model.name) { _,_ in model.invalidate() }
      .onChange(of:model.previewExposure) { _,_ in model.updatePreview() }
  }
}
@MainActor final class HDRMergeWindow: NSWindowController,NSWindowDelegate {
  weak var documentController: CraftDocumentController?
  init(model: HDRMergeWorkspace,owner: CraftDocumentController) {
    documentController = owner
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:740),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title = "Merge to HDR Pro";window.contentView = NSHostingView(rootView:HDRMergeView(model:model));window.isReleasedWhenClosed = false;window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) { nil }
  func windowWillClose(_ notification: Notification) { documentController?.cancelHDRMerge() }
}
extension CraftDocumentController {
  var canPublishHDRMerge: Bool {
    scanCropOperationID == nil && contactSheetWorkspace == nil && imageStackWorkspace == nil && photomergeWorkspace == nil && !documentOpening.isActive && !documentOpening.hasPendingRequests && documentOpenPanel == nil && !documentClosing.isActive && !recoveryIndex.isBusy && initialRecoveryTask == nil && NSApp?.modalWindow == nil
  }
  func beginHDRMerge(display: Bool = true) {
    guard canPublishHDRMerge else { return }
    if hdrMergeWorkspace == nil { hdrMergeWorkspace = HDRMergeWorkspace(controller:self) }
    if display,let model = hdrMergeWorkspace {
      if hdrMergeWindow == nil { hdrMergeWindow = HDRMergeWindow(model:model,owner:self) };hdrMergeWindow?.showWindow(nil)
    }
  }
  func cancelHDRMerge() { let window = hdrMergeWindow;hdrMergeWindow = nil;hdrMergeWorkspace?.close();hdrMergeWorkspace = nil;window?.close() }
}
extension AppDelegate { @objc func hdrMerge() { controller.beginHDRMerge() } }
