import AppKit
import SwiftUI

struct ImageProcessorView: View {
  @Bindable var model: ImageProcessorWorkspace
  func format(_ title: String,_ value: Binding<ImageProcessorSettings.Format>) -> some View {
    VStack(alignment:.leading,spacing:8) {
      Toggle(title,isOn:value.enabled)
      HStack {
        Toggle("Resize to Fit",isOn:value.resize)
        Text("W");TextField("Width",value:value.width,format:.number).frame(width:65)
        Text("H");TextField("Height",value:value.height,format:.number).frame(width:65);Text("px").foregroundStyle(.secondary)
      }.disabled(!value.wrappedValue.enabled)
    }
  }
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      ScrollView {
        VStack(alignment:.leading,spacing:16) {
          GroupBox("1. Select the images to process") {
            VStack(alignment:.leading,spacing:8) {
              HStack {Button("Use Open Images"){model.addOpen()};Button("Select Folder…"){model.browse(folder:true)};Button("Files…"){model.browse(folder:false)};Button("Clear"){model.clear()}}
              Toggle("Include All Subfolders",isOn:$model.includeSubfolders)
              Toggle("Use First Image’s Color Profile",isOn:$model.settings.useFirstImageProfile)
              Text("\(model.sources.count) images selected").font(.caption)
              if !model.sources.isEmpty {Text(model.sources.prefix(4).map(\.name).joined(separator:" · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)}
            }.frame(maxWidth:.infinity,alignment:.leading).padding(6)
          }
          GroupBox("2. Select location to save processed images") {
            HStack {Button("Select Folder…"){model.chooseDestination()};Text(model.destination?.path ?? "Choose an output folder").font(.caption).lineLimit(2);Spacer()}.padding(6)
          }
          GroupBox("3. File Type") {
            VStack(alignment:.leading,spacing:12) {
              format("Save as JPEG",$model.settings.jpeg)
              HStack {Text("Quality");TextField("Quality",value:$model.settings.jpegQuality,format:.number).frame(width:55);Text("0–12").foregroundStyle(.secondary);Toggle("Convert Profile to sRGB",isOn:$model.settings.convertJPEGToSRGB)}.disabled(!model.settings.jpeg.enabled)
              Divider();format("Save as PSD",$model.settings.psd)
              Toggle("Maximize Compatibility",isOn:$model.settings.maximizeCompatibility).disabled(true).help("PSD files currently always include a compatibility composite.")
              Divider();format("Save as TIFF",$model.settings.tiff)
              Toggle("LZW Compression",isOn:$model.settings.tiffLZW).disabled(!model.settings.tiff.enabled)
              Divider();Toggle("Don’t Enlarge",isOn:$model.settings.dontEnlarge)
            }.padding(6)
          }
          GroupBox("4. Preferences") {
            VStack(alignment:.leading,spacing:8) {
              Picker("Run Action",selection:$model.settings.actionID) {Text("None").tag(nil as UUID?);ForEach(model.library.file.actions) {Text("\($0.set) / \($0.name)").tag(Optional($0.id))}}
              TextField("Copyright Info",text:$model.settings.copyright)
              Toggle("Include ICC Profile",isOn:$model.settings.includeICC)
            }.padding(6)
          }
          Text("Creates JPEG, PSD and TIFF folders. Sources and existing files are preserved; duplicate output names receive a number.").font(.caption).foregroundStyle(.secondary)
        }.disabled(model.busy).padding(.trailing,8)
      }.scrollIndicators(.visible)
      if let error = model.error {Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled)}
      if model.busy {ProgressView(value:Double(model.completed),total:Double(max(1,model.sources.count)))}
      HStack {
        Button("Load…"){model.loadSettings()}.disabled(model.busy);Button("Save…"){model.saveSettings()}.disabled(model.busy)
        Text(model.busy ? "Processing \(model.completed) of \(model.sources.count)":"\(model.outputs.count) files saved").font(.caption).foregroundStyle(.secondary)
        Spacer()
        if model.busy {Button("Cancel"){model.cancel()}.keyboardShortcut(.cancelAction)}
        else {Button("Run"){model.run()}.keyboardShortcut(.defaultAction).disabled(model.destination == nil || model.sources.isEmpty)}
      }
    }.padding(18).frame(minWidth:650,minHeight:600)
  }
}
@MainActor final class ImageProcessorWindow: NSWindowController,NSWindowDelegate {
  let model: ImageProcessorWorkspace
  init(model: ImageProcessorWorkspace) {
    self.model = model
    let window = NSWindow(contentRect:NSRect(x:160,y:120,width:740,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.title = "Image Processor";window.isReleasedWhenClosed = false;window.contentView = NSHostingView(rootView:ImageProcessorView(model:model));window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) {fatalError("init(coder:) has not been implemented")}
  func windowShouldClose(_ sender: NSWindow) -> Bool {if model.busy {model.cancel();return false};return true}
  func windowWillClose(_ notification: Notification) {model.release();model.clear();model.destination = nil}
}
extension AppDelegate {
  @objc func imageProcessor() {
    if imageProcessorWindow == nil {imageProcessorWindow = ImageProcessorWindow(model:ImageProcessorWorkspace(controller:controller))}
    imageProcessorWindow?.showWindow(nil)
  }
}
