import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class ClassicDetailWorkspace {
  var filter=RasterFilter(.radialBlur)
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
    do { guard f.kind.isClassicDetail else {throw CraftError.invalid("Missing Blur/Noise/Sharpen kind.")};try f.validate();guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change Blur/Noise/Sharpen workspace kind.") } } catch { self.error=error.localizedDescription;return }
    guard f != filter else{if error != nil {refresh()};return};if remember && gestureStart==nil { self.remember(filter) };filter=f;refresh()
  }
  func update(_ edit:(inout RasterFilter)->Void) { var f=filter;edit(&f);change(f) }
  func chooseShape(_ preset:ShapePreset)throws {
    guard !closed,filter.kind == .shapeBlur else {throw CraftError.invalid("Open Shape Blur before choosing a kernel.")}
    let snapshot=try ShapeBlurKernel(name:preset.name,path:preset.path)
    update{$0.classicDetail?.shape = .circle;$0.classicDetail?.kernel=snapshot}
  }
  func chooseBuiltInShape(_ shape:ClassicDetailSettings.Shape) {
    guard !closed,filter.kind == .shapeBlur else{return}
    update{$0.classicDetail?.kernel=nil;$0.classicDetail?.shape=shape}
  }
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
  var documentWidth:Int {document?.width ?? 1}
  var documentHeight:Int {document?.height ?? 1}
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}

struct ClassicDetailSheet:View {
  @Bindable var store:EditorStore
  @State private var model:ClassicDetailWorkspace
  init(store:EditorStore,model:ClassicDetailWorkspace?=nil) {self.store=store;_model=State(initialValue:model ?? ClassicDetailWorkspace())}
  var settings:ClassicDetailSettings {model.filter.classicDetail ?? ClassicDetailSettings(kind:model.filter.kind)}
  var body:some View {
    VStack(spacing:12) {
      HStack {Text(model.filter.kind.title).font(.headline);Spacer();if model.rendering {ProgressView().controlSize(.small)}}
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView {VStack(alignment:.leading,spacing:14) {controls;Divider();Button("Reset"){model.change(RasterFilter(model.filter.kind))}}.padding(.trailing,5)}.frame(width:275)
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
    .task {store.classicDetailWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft)}
    .onDisappear {model.close();if store.classicDetailWorkspace === model {store.classicDetailWorkspace=nil}}
  }
  var preview:some View {
    GeometryReader {g in ScrollView([.horizontal,.vertical]) {
      if let image=model.preview ? model.image:model.originalImage {
        let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
        ZStack(alignment:.topLeading) {
          Image(decorative:image,scale:1).resizable().interpolation(.none)
          if model.filter.kind == .radialBlur {
            Circle().stroke(.white,lineWidth:2).frame(width:16,height:16).shadow(color:.black,radius:1).position(x:settings.centerX*Double(image.width)*scale,y:settings.centerY*Double(image.height)*scale)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{value in
              model.beginGesture();model.update{$0.classicDetail?.centerX=min(1,max(0,value.location.x/(Double(image.width)*scale)));$0.classicDetail?.centerY=min(1,max(0,value.location.y/(Double(image.height)*scale)))}
            }.onEnded{_ in model.endGesture()})
          }
        }.frame(width:Double(image.width)*scale,height:Double(image.height)*scale).padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
      }
    }.background(Color(white:0.12)).clipped().accessibilityLabel("Filter preview")}
  }
  func choice<T>(_ key:WritableKeyPath<ClassicDetailSettings,T>)->Binding<T> {
    Binding(get:{settings[keyPath:key]},set:{value in model.update{$0.classicDetail?[keyPath:key]=value}})
  }
  func number(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,step:Double=1)->some View {
    VStack(spacing:4) {
      HStack {Text(title);Spacer();TextField(title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:70).textFieldStyle(.roundedBorder)}
      Slider(value:value,in:range,step:step,onEditingChanged:{editing in if editing {model.beginGesture()} else {model.endGesture()}}).accessibilityLabel(title)
    }
  }
  @ViewBuilder var controls:some View {
    switch model.filter.kind {
    case .radialBlur:
      number("Amount",choice(\.amount),1...100)
      Picker("Blur Method",selection:choice(\.method)){Text("Spin").tag(ClassicDetailSettings.Method.spin);Text("Zoom").tag(ClassicDetailSettings.Method.zoom)}.pickerStyle(.radioGroup)
      Picker("Quality",selection:choice(\.radialQuality)){ForEach(ClassicDetailSettings.RadialQuality.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}.pickerStyle(.segmented)
      number("Center X",choice(\.centerX),0...1,step:0.01)
      number("Center Y",choice(\.centerY),0...1,step:0.01)
      Button("Center"){model.update{$0.classicDetail?.centerX=0.5;$0.classicDetail?.centerY=0.5}}
      Text("Drag in the preview to set the blur center.").font(.caption).foregroundStyle(.secondary)
    case .shapeBlur:
      number("Radius (pixels)",choice(\.radius),5...1000)
      Menu {
        Section("Built-in shapes") {
          ForEach(ClassicDetailSettings.Shape.allCases,id:\.self){shape in
            Button(shape.rawValue.capitalized){model.chooseBuiltInShape(shape)}
          }
        }
        Section("Saved shapes") {
          ForEach(store.shapes.shapes){preset in
            Button {do{try model.chooseShape(preset)}catch{model.error=error.localizedDescription}} label:{
              Label {Text(preset.name)} icon:{ShapeSwatch(path:preset.path)}
            }
          }
          if store.shapes.shapes.isEmpty {Text("No saved custom shapes")}
        }
      } label:{
        HStack {
          if let kernel=settings.kernel {ShapeSwatch(path:(try? kernel.previewPath()) ?? kernel.path).frame(width:28,height:24)}
          Text(settings.kernel?.name ?? settings.shape.rawValue.capitalized)
        }
      }.accessibilityLabel("Shape Blur kernel").accessibilityValue(settings.kernel?.name ?? settings.shape.rawValue.capitalized)
      Text("Custom shapes come from the Shapes panel. The chosen shape is saved with this filter.").font(.caption).foregroundStyle(.secondary)
    case .smartBlur:
      number("Radius (pixels)",choice(\.radius),0.1...100,step:0.1)
      number("Threshold",choice(\.threshold),0.1...100,step:0.1)
      Picker("Quality",selection:choice(\.quality)){ForEach(ClassicDetailSettings.Quality.allCases,id:\.self){Text($0.rawValue.capitalized).tag($0)}}
      Picker("Mode",selection:choice(\.mode)){Text("Normal").tag(ClassicDetailSettings.Mode.normal);Text("Edge Only").tag(ClassicDetailSettings.Mode.edgeOnly);Text("Overlay Edge").tag(ClassicDetailSettings.Mode.overlayEdge)}
    case .surfaceBlur,.dustAndScratches,.median:
      number("Radius (pixels)",choice(\.radius),1...(model.filter.kind == .median ? 500:100))
      if model.filter.kind != .median {number("Threshold",choice(\.threshold),(model.filter.kind == .surfaceBlur ? 2:0)...255)}
    default:Text("This filter applies its fixed settings.").foregroundStyle(.secondary)
    }
  }
}
