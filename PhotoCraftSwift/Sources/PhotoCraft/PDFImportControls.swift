import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

extension PDFImportSettings.Crop {
  var title: String {
    switch self {
    case .bounding: "Bounding Box"
    case .media: "Media Box"
    case .crop: "Crop Box"
    case .bleed: "Bleed Box"
    case .trim: "Trim Box"
    case .art: "Art Box"
    }
  }
}
struct PDFImportView: View {
  @Bindable var model: PDFImportWorkspace
  private var columns: [GridItem] {[GridItem(.adaptive(minimum:CGFloat(model.thumbnailSize+24)),spacing:12)]}
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      HStack {
        Text("Name:");TextField("Document name",text:$model.name).accessibilityLabel("PDF document name")
      }.disabled(model.busy)
      HStack(alignment:.top,spacing:20) {
        VStack(alignment:.leading,spacing:10) {
          HStack {
            Picker("Import",selection:Binding(get:{model.content},set:{model.changeContent($0)})) {Text("Pages").tag(PDFImportContent.pages);Text("Images").tag(PDFImportContent.images)}.pickerStyle(.segmented).labelsHidden().accessibilityLabel("PDF import content").frame(width:150).disabled(model.busy || model.loading)
            Spacer()
            Picker("Thumbnail Size",selection:$model.thumbnailSize) {Text("Small").tag(80);Text("Medium").tag(120);Text("Large").tag(180)}.frame(width:210)
          }
          ScrollView {
            LazyVGrid(columns:columns,spacing:12) {
              ForEach(model.items,id:\.self) {page in
                Button {
                  let flags = NSApp.currentEvent?.modifierFlags ?? []
                  model.select(page,extend:flags.contains(.shift),toggle:flags.contains(.command))
                } label: {
                  VStack(spacing:6) {
                    ZStack {
                      Color(nsColor:.textBackgroundColor)
                      if let data = model.thumbnails[page],let image = NSImage(data:data) {
                        Image(nsImage:image).resizable().scaledToFit().padding(6)
                      } else {Image(systemName:"doc").font(.largeTitle).foregroundStyle(.secondary)}
                    }.frame(width:CGFloat(model.thumbnailSize),height:CGFloat(model.thumbnailSize))
                      .overlay(RoundedRectangle(cornerRadius:4).stroke(model.selected.contains(page) ? Color.accentColor:Color.secondary.opacity(0.3),lineWidth:model.selected.contains(page) ? 3:1))
                    Text("\(page)").monospacedDigit()
                  }.padding(4)
                }.buttonStyle(.plain).disabled(model.busy)
                  .accessibilityLabel("PDF \(model.content == .pages ? "page":"image") \(page)")
                  .accessibilityValue(model.selected.contains(page) ? "Selected":"Not selected")
                  .onAppear {model.showThumbnail(page)}.onDisappear {model.hideThumbnail(page)}
              }
            }.padding(8)
          }.id(model.content).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:5))
          HStack {
            Text("\(model.selected.count) selected").foregroundStyle(.secondary)
            Spacer();Button("Select All") {model.selected = Set(model.items)}.disabled(model.info == nil || model.busy)
          }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
        VStack(alignment:.leading,spacing:14) {
          if model.content == .pages {
          Picker("Crop To:",selection:$model.settings.crop) {ForEach(PDFImportSettings.Crop.allCases,id:\.self) {Text($0.title).tag($0)}}
          Toggle("Anti-aliased",isOn:$model.settings.antialias)
          Divider()
          HStack {Text("Width:").frame(width:70,alignment:.leading);TextField("Automatic",text:$model.widthText).accessibilityLabel("PDF width");Text("px")}
          HStack {Text("Height:").frame(width:70,alignment:.leading);TextField("Automatic",text:$model.heightText).accessibilityLabel("PDF height");Text("px")}
          Toggle("Constrain Proportions",isOn:$model.settings.constrainProportions)
          HStack {Text("Resolution:");TextField("Resolution",value:$model.settings.resolution,format:.number);Text("ppi")}
          Picker("Mode:",selection:$model.settings.mode) {ForEach(DocumentColorMode.componentModes,id:\.self) {Text($0.title).tag($0)}}
          Picker("Bit Depth:",selection:$model.settings.depth) {
            ForEach(model.settings.mode.depths,id:\.self) {depth in Text(depth == .u8 ? "8 Bits/Channel":depth == .u16 ? "16 Bits/Channel":"32 Bits/Channel").tag(depth)}
          }
          Text("Leave dimensions blank to use each page’s size at the chosen resolution.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
          } else {
            Text("Image Size").font(.headline)
            Text("Embedded images keep their original pixel dimensions. Resolution changes print size.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if model.selected.count == 1,let id = model.selected.first,let info = model.imageInfo?.first(where:{$0.number == id}) {Text("\(info.width) × \(info.height) px").monospacedDigit()}
            HStack {Text("Resolution:");TextField("Resolution",value:$model.imageSettings.resolution,format:.number);Text("ppi")}
            Picker("Mode:",selection:$model.imageSettings.mode) {ForEach(DocumentColorMode.componentModes,id:\.self) {Text($0.title).tag($0)}}
            Picker("Bit Depth:",selection:$model.imageSettings.depth) {ForEach(model.imageSettings.mode.depths,id:\.self) {Text($0 == .u8 ? "8 Bits/Channel":$0 == .u16 ? "16 Bits/Channel":"32 Bits/Channel").tag($0)}}
            if model.imageInfo?.isEmpty == true {Text("No embedded images were found.").foregroundStyle(.secondary)}
          }
          Spacer()
        }.frame(width:265).disabled(model.busy || model.info == nil)
      }
      if model.info == nil {
        HStack {SecureField("PDF password",text:$model.password);Button("Unlock") {model.inspect()}.disabled(model.loading || model.password.isEmpty)}
      }
      if let error = model.error {Text(error).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
      HStack {
        if model.loading || model.busy {ProgressView().controlSize(.small);Text(model.loading ? "Reading PDF…":"Importing PDF…").foregroundStyle(.secondary)}
        Spacer();Button("Cancel") {model.cancel()}.keyboardShortcut(.cancelAction)
        Button("OK") {model.run()}.keyboardShortcut(.defaultAction).disabled(model.loading || model.busy || model.info == nil || model.selected.isEmpty)
      }
    }.padding(20).frame(minWidth:740,minHeight:540)
      .onChange(of:model.imageSettings.mode) {if !model.imageSettings.mode.depths.contains(model.imageSettings.depth) {model.imageSettings.depth = .u8}}
      .onChange(of:model.settings.mode) {if !model.settings.mode.depths.contains(model.settings.depth) {model.settings.depth = .u8}}
  }
}
@MainActor final class PDFImportWindow: NSWindowController,NSWindowDelegate {
  let model: PDFImportWorkspace
  init(model: PDFImportWorkspace) {
    self.model = model
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
    window.title = "Import PDF";window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width:740,height:540)
    window.contentView = NSHostingView(rootView:PDFImportView(model:model));window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) {nil}
  func windowWillClose(_ notification: Notification) {model.cancel()}
}
