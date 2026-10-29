import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class PixelateWorkspace {
  var filter=RasterFilter(.crystallize)
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var fit=true
  var zoom=1.0
  var error:String?
  var undoStates=[RasterFilter]()
  var redoStates=[RasterFilter]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var closed=false
  private var generation=0
  private var gestureStart:RasterFilter?
  var ready:Bool { image != nil && !rendering && error == nil }
  var apiState:[String:Any] {
    ["filter":filter.apiState,"preview":preview,"zoom":zoom,"fit":fit,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
  func prepare(document:CraftDocument,draft:FilterDraft) async { self.document=document;self.draft=draft;filter=draft.filter;closed=false;refresh();await task?.value }
  func remember(_ f:RasterFilter) { undoStates.append(f);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ f:RasterFilter,remember:Bool=true) {
    do { guard f.kind.isPixelate else {throw CraftError.invalid("Missing Pixelate kind.")};try f.validate();guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change Pixelate workspace kind.") } } catch { self.error=error.localizedDescription;return }
    guard f != filter else{if error != nil {refresh()};return};if remember && gestureStart==nil { self.remember(filter) };filter=f;refresh()
  }
  func update(_ edit:(inout RasterFilter)->Void) { var f=filter;edit(&f);change(f) }
  func beginGesture() { if gestureStart==nil { gestureStart=filter } }
  func endGesture() { if let old=gestureStart,old != filter { remember(old) };gestureStart=nil }
  func undo() { endGesture();guard let f=undoStates.popLast() else{return};redoStates.append(filter);change(f,remember:false) }
  func redo() { endGesture();guard let f=redoStates.popLast() else{return};undoStates.append(filter);change(f,remember:false) }
  func refresh() {
    guard !closed,let document,var draft else{return};task?.cancel();generation+=1;let token=generation,needOriginal=originalImage==nil
    draft.filter=filter;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do { try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { ()throws->(CGImage,CGImage?) in
          var edited=document;try request.command(in:document).apply(to:&edited)
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:document),needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==token else{return};self.image=result.0;if let image=result.1 { self.originalImage=image };self.rendering=false
      } catch { guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}

struct PixelateSheet: View {
  @Bindable var store: EditorStore
  @State private var model: PixelateWorkspace
  init(store:EditorStore,model:PixelateWorkspace?=nil) {self.store=store;_model=State(initialValue:model ?? PixelateWorkspace())}
  var settings:PixelateSettings {model.filter.pixelate ?? .init(kind:.crystallize)}
  var body: some View {
    VStack(spacing:12) {
      HStack {Text(model.filter.kind.title).font(.headline);Spacer();if model.rendering {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView { VStack(alignment:.leading,spacing:14) {
          controls
          if !model.filter.kind.isImmediatePixelate {
            Divider();Button("Reset") {var f=RasterFilter(model.filter.kind);f.pixelate?.background=settings.background;model.change(f)}
          }
        }.padding(.trailing,5)}.frame(width:275)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−"){model.fit=false;model.zoom=max(0.125,model.zoom/1.5)}
        Button("+"){model.fit=false;model.zoom=min(8,model.zoom*1.5)}
        Button("100%"){model.fit=false;model.zoom=1};Button("Fit"){model.fit=true}
        Button("Undo"){model.undo()}.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo"){model.redo()}.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel"){model.close();store.cancelFilter()}.keyboardShortcut(.cancelAction)
        Button("OK"){model.endGesture();store.filterDraft?.filter=model.filter;model.close();store.commitFilter()}.disabled(!model.ready).keyboardShortcut(.defaultAction)
      }.controlSize(.small)
      if let error=model.error {Text(error).foregroundStyle(.red).font(.caption)}
    }.padding(16).frame(width:840,height:620)
    .task {store.pixelateWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear {model.close();if store.pixelateWorkspace === model {store.pixelateWorkspace=nil}}
  }
  var preview: some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? model.image:model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).clipped().accessibilityLabel("Pixelate preview")}
  }
  func choice<T>(_ key:WritableKeyPath<PixelateSettings,T>)->Binding<T> {
    Binding(get:{settings[keyPath:key]},set:{value in model.update{$0.pixelate?[keyPath:key]=value}})
  }
  func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
    VStack(spacing:4) {
      HStack {Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0))).frame(width:65).textFieldStyle(.roundedBorder)}
      Slider(value:value,in:range,step:1,onEditingChanged:{editing in if editing {model.beginGesture()} else {model.endGesture()}}).accessibilityLabel(title)
    }
  }
  var background: Binding<Color> {
    Binding(get:{Color(red:Double(settings.background.r),green:Double(settings.background.g),blue:Double(settings.background.b))},set:{color in
      guard let c=NSColor(color).usingColorSpace(.sRGB) else {return}
      model.update{$0.pixelate?.background=Pixel(Float(c.redComponent),Float(c.greenComponent),Float(c.blueComponent))}
    })
  }
  @ViewBuilder var controls: some View {
    switch model.filter.kind {
    case .colorHalftone:
      number("Max. Radius (pixels)",choice(\.maxRadius),4...127)
      Text("Screen Angles (degrees)").font(.headline)
      ForEach(0..<4,id:\.self) {i in
        number("Channel \(i+1)",Binding(get:{settings.angles[i]},set:{v in model.update{$0.pixelate?.angles[i]=v}}),-360...360)
      }
      Button("Defaults"){model.update{$0.pixelate?.angles=[108,162,90,45]}}
    case .crystallize,.pointillize:
      number("Cell Size (pixels)",choice(\.cellSize),3...300)
      if model.filter.kind == .pointillize {ColorPicker("Background",selection:background,supportsOpacity:false)}
      Button("New Pattern"){model.update{$0.pixelate?.seed=UInt32.random(in:.min ... .max)}}
    case .mezzotint:
      Picker("Type",selection:choice(\.pattern)){ForEach(PixelateSettings.Pattern.allCases,id:\.self){Text($0.title).tag($0)}}
      Button("New Pattern"){model.update{$0.pixelate?.seed=UInt32.random(in:.min ... .max)}}
    case .facet,.fragment:Text("This filter has no adjustable settings.").foregroundStyle(.secondary)
    default:EmptyView()
    }
  }
}
