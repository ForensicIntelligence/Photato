import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PhotoCraftCore
import PhotoCraftImaging

struct ContactSheetView: View {
  @Bindable var model: ContactSheetWorkspace
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      Text("Contact Sheet II").font(.headline)
      HStack(alignment:.top,spacing:18) {
        ScrollView {
          VStack(alignment:.leading,spacing:10) {
            GroupBox("Source Images") {
              VStack(alignment:.leading) {
                List(selection:$model.selected) { ForEach(model.sources) { Text($0.title).tag($0.id) } }.frame(height:115)
                HStack { Button("Files…") { model.browse() };Button("Folder…") { model.browse(folder:true) };Button("Open Documents") { model.addOpenDocuments() } }
                Toggle("Include Subfolders",isOn:$model.includeSubfolders)
                HStack { Text("\(model.sources.count) images").foregroundStyle(.secondary);Spacer();Button("↑") { model.moveSelected(-1) };Button("↓") { model.moveSelected(1) };Button("Remove") { model.removeSelected() } }.disabled(model.selected.isEmpty)
              }.disabled(model.loading)
            }
            GroupBox("Document") {
              VStack(alignment:.leading) {
                TextField("Name",text:$model.name)
                Picker("Units",selection:$model.settings.units) { ForEach(ContactSheetSettings.Units.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
                HStack { number("Width",$model.settings.width);number("Height",$model.settings.height) }
                number("Resolution (pixels/inch)",$model.settings.resolution)
                Picker("Mode",selection:$model.settings.mode) { ForEach(DocumentColorMode.componentModes,id:\.self) { Text($0.title).tag($0) } }
                Picker("Bit Depth",selection:$model.settings.depth) { ForEach(model.settings.mode.depths,id:\.self) { Text($0.rawValue).tag($0) } }
                HStack { Text(model.settings.profile == nil ? "Standard color profile":"Custom ICC profile").font(.caption);Spacer();Button("Choose…") { model.chooseProfile() };Button("Reset") { model.settings.profile = nil } }
                Toggle("Flatten All Layers",isOn:$model.settings.flatten)
              }
            }
            GroupBox("Thumbnails") {
              VStack(alignment:.leading) {
                Picker("Place",selection:$model.settings.placeAcrossFirst) { Text("Across First").tag(true);Text("Down First").tag(false) }
                HStack { Text("Columns").font(.caption);TextField("Columns",value:$model.settings.columns,format:.number);Text("Rows").font(.caption);TextField("Rows",value:$model.settings.rows,format:.number) }.textFieldStyle(.roundedBorder)
                Toggle("Use Auto-Spacing",isOn:$model.settings.autoSpacing)
                HStack { number("Horizontal",$model.settings.horizontal);number("Vertical",$model.settings.vertical) }.disabled(model.settings.autoSpacing)
                Toggle("Rotate For Best Fit",isOn:$model.settings.rotateForBestFit)
                Toggle("Use Filename As Caption",isOn:$model.settings.caption)
                HStack { Picker("Font",selection:$model.settings.font) { ForEach(NSFontManager.shared.availableFonts.sorted(),id:\.self) { Text($0).tag($0) } };number("Size (pt)",$model.settings.fontSize) }.disabled(!model.settings.caption)
              }
            }
          }.padding(2)
        }.scrollIndicators(.visible).frame(width:420,height:620)
        VStack {
          ZStack {
            Color.black.opacity(0.15)
            if let image = model.image { Image(decorative:image,scale:1).resizable().scaledToFit().padding(10) }
            else { Text("Preview the contact sheets.").foregroundStyle(.secondary) }
            if model.loading || model.rendering { ProgressView() }
          }.frame(width:390,height:570)
          HStack {
            Button("Previous") { model.showPage(model.page-1) }.disabled(model.page == 0 || model.rendering)
            Text("Page \(model.result == nil ? 0:model.page+1) of \(model.result?.documents.count ?? 0)").monospacedDigit()
            Button("Next") { model.showPage(model.page+1) }.disabled(model.page+1 >= (model.result?.documents.count ?? 0) || model.rendering)
          }
        }
      }
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).lineLimit(2).textSelection(.enabled) }
      HStack {
        Button("Preview") { model.refresh() }.disabled(model.loading || model.sources.isEmpty)
        Spacer();Button("Cancel") { model.controller?.cancelContactSheet() }.keyboardShortcut(.cancelAction)
        Button("OK") { do { try model.commit() } catch { model.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(18).frame(width:870,height:730)
      .onChange(of:model.settings) { _,_ in model.invalidate() }
      .onChange(of:model.settings.mode) { _,mode in model.settings.profile = nil;if !mode.depths.contains(model.settings.depth) {model.settings.depth = .u8} }
      .onChange(of:model.settings.depth) { _,_ in model.settings.profile = nil }
      .onChange(of:model.name) { _,_ in model.invalidate() }
  }
  private func number(_ title: String,_ value: Binding<Double>) -> some View { HStack { Text(title).font(.caption);TextField(title,value:value,format:.number).textFieldStyle(.roundedBorder).frame(minWidth:45) } }
}
@MainActor final class ContactSheetWindow: NSWindowController,NSWindowDelegate {
  weak var documentController: CraftDocumentController?
  init(model: ContactSheetWorkspace,owner: CraftDocumentController) {
    documentController = owner
    let window = PhotatoWindow(contentRect:NSRect(x:0,y:0,width:870,height:730),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title = "Contact Sheet II";window.contentView = NSHostingView(rootView:ContactSheetView(model:model));window.isReleasedWhenClosed = false;window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) { nil }
  func windowWillClose(_ notification: Notification) { documentController?.cancelContactSheet() }
}
extension ContactSheetWorkspace {
  func chooseProfile() {
    guard panel == nil else { return }
    let picker = NSOpenPanel();panel = picker;picker.canChooseDirectories = false;picker.allowsMultipleSelection = false
    picker.allowedContentTypes = [UTType(filenameExtension:"icc"),UTType(filenameExtension:"icm")].compactMap{$0}
    picker.begin { [weak self] response in MainActor.assumeIsolated {
      guard let self else {return};self.panel = nil
      guard response == .OK,let url = picker.url else{return}
      let scoped = url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
      do {
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= ICCProfile.maximumBytes else {throw CraftError.invalid("ICC profiles must be at most4MiB.")}
        let data = try Data(contentsOf:url);try NativeModeProfile.validate(data,mode:self.settings.mode,depth:self.settings.depth);self.settings.profile = data;self.invalidate()
      } catch {self.error = error.localizedDescription}
    } }
  }
}
extension CraftDocumentController {
  var canPublishContactSheet: Bool {
    scanCropOperationID == nil && imageStackWorkspace == nil && photomergeWorkspace == nil && hdrMergeWorkspace == nil && !documentOpening.isActive && !documentOpening.hasPendingRequests && documentOpenPanel == nil && !documentClosing.isActive && !recoveryIndex.isBusy && initialRecoveryTask == nil && NSApp?.modalWindow == nil
  }
  func beginContactSheet(display: Bool = true) {
    guard canPublishContactSheet else {return}
    if contactSheetWorkspace == nil {contactSheetWorkspace = ContactSheetWorkspace(controller:self)}
    if display,let model = contactSheetWorkspace {
      if contactSheetWindow == nil {contactSheetWindow = ContactSheetWindow(model:model,owner:self)};contactSheetWindow?.showWindow(nil)
    }
  }
  func cancelContactSheet() {let window = contactSheetWindow;contactSheetWindow = nil;contactSheetWorkspace?.close();contactSheetWorkspace = nil;window?.close()}
}
extension AppDelegate { @objc func contactSheet() {controller.beginContactSheet()} }
