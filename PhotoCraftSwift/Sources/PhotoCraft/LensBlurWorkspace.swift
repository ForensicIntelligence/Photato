import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class LensBlurWorkspace {
  var filter=RasterFilter(.lensBlur)
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
  struct DepthChoice:Identifiable { let id:String,title:String }
  var depthChoices:[DepthChoice] {
    var result=[DepthChoice(id:"none",title:"None"),DepthChoice(id:"transparency",title:"Transparency")]
    if let document,let draft,document.layers.first(where:{$0.id==draft.id})?.mask != nil { result.append(.init(id:"layerMask",title:"Layer Mask")) }
    for channel in document?.alphaChannels ?? [] { result.append(.init(id:channel.id.uuidString,title:channel.name)) };return result
  }
  var depthChoice:String { filter.lensBlur?.depthChannelID?.uuidString ?? filter.lensBlur?.depthSource.rawValue ?? "none" }
  func setDepth(_ choice:String) {
    guard depthChoices.contains(where:{$0.id==choice}) else { error="Depth source is unavailable.";return }
    update { f in
      if let id=UUID(uuidString:choice) { f.lensBlur?.depthSource = .alphaChannel;f.lensBlur?.depthChannelID=id }
      else { f.lensBlur?.depthSource=LensBlurSettings.DepthSource(rawValue:choice) ?? .none;f.lensBlur?.depthChannelID=nil }
    }
  }
  /// Preview coordinates are document coordinates, including Smart Filter geometry.
  func pickFocus(x:Double,y:Double) {
    guard let document,let draft,let s=filter.lensBlur,s.depthSource != .none,x.isFinite,y.isFinite else{return}
    do {
      let layer=try draft.inputLayer(in:document);guard case .raster(let source)=layer.content else{return}
      let value:Float
      switch s.depthSource {
      case .none:return
      case .transparency:
        let p=try layer.coordinateTransform.inverted().point(x,y),ix=Int(floor(p.x)),iy=Int(floor(p.y))
        value=(0..<source.width).contains(ix) && (0..<source.height).contains(iy) ? source.pixel(x:ix,y:iy).a:0
      case .layerMask:
        var raw=layer;var properties=layer.effectiveMaskProperties;properties.enabled=true;properties.inverted=false;properties.density=1;properties.feather=0;raw.maskProperties=properties
        value=try MaskSampler(layer:raw,feather:false).coverage(x:x,y:y)
      case .alphaChannel:
        guard let channel=document.alphaChannels?.first(where:{$0.id==s.depthChannelID}) else { throw CraftError.invalid("Depth channel is missing.") }
        value=MaskSampler.sample(channel.pixels,x:x,y:y,outside:0)
      }
      update{$0.lensBlur?.focalDistance=Double(s.invert ? 1-value:value)*255}
    } catch { self.error=error.localizedDescription }
  }
  var apiState:[String:Any] {
    let encoded=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(filter))) as? [String:Any] ?? [:]
    let parameters=encoded.filter { filter.kind.parameters.contains($0.key) || $0.key == "kind" }
    return ["filter":parameters,"depthSources":depthChoices.map{["id":$0.id,"title":$0.title]},"focusPicker":"Click preview to set focalDistance from the selected depth source; API clients set focalDistance directly.","preview":preview,"zoom":zoom,"fit":fit,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()] }
  func prepare(document:CraftDocument,draft:FilterDraft) async { self.document=document;self.draft=draft;filter=draft.filter;closed=false;refresh();await task?.value }
  func remember(_ f:RasterFilter) { undoStates.append(f);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ f:RasterFilter,remember:Bool=true) {
    do { try f.validate();guard f.kind==filter.kind else { throw CraftError.invalid("Cannot change Lens Blur workspace kind.") } } catch { self.error=error.localizedDescription;return }
    guard f != filter else{return};if remember && gestureStart==nil { self.remember(filter) };filter=f;refresh()
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

struct LensBlurSheet:View {
  @Bindable var store:EditorStore
  @State private var model:LensBlurWorkspace
  init(store:EditorStore,model:LensBlurWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? LensBlurWorkspace()) }
  var body:some View {
    VStack(spacing:12) {
      HStack { Text("Lens Blur").font(.headline);Spacer();if model.rendering { ProgressView().controlSize(.small);Text("Rendering…").foregroundStyle(.secondary) } }
      HStack(alignment:.top,spacing:16) {
        preview.frame(minWidth:400,maxWidth:.infinity,maxHeight:.infinity)
        ScrollView { VStack(alignment:.leading,spacing:12) {
          Text("Depth Map").font(.headline)
          Picker("Source",selection:Binding(get:{model.depthChoice},set:{model.setDepth($0)})) { ForEach(model.depthChoices) { Text($0.title).tag($0.id) } }
          control(3,\.focalDistance).disabled(model.filter.lensBlur?.depthSource == LensBlurSettings.DepthSource.none)
          Toggle("Invert",isOn:boolean(\.invert)).disabled(model.filter.lensBlur?.depthSource == LensBlurSettings.DepthSource.none)
          Text("Click the preview to bring a depth into focus.").font(.caption).foregroundStyle(.secondary)
          Divider();Text("Iris").font(.headline)
          Picker("Shape",selection:Binding(get:{model.filter.lensBlur?.blades ?? 6},set:{v in model.update{$0.lensBlur?.blades=v}})) {
            Text("Triangle (3)").tag(3);Text("Square (4)").tag(4);Text("Pentagon (5)").tag(5);Text("Hexagon (6)").tag(6);Text("Heptagon (7)").tag(7);Text("Octagon (8)").tag(8)
          }
          control(0,\.radius);control(1,\.bladeCurvature);control(2,\.rotation)
          Divider();Text("Specular Highlights").font(.headline);control(4,\.brightness);control(5,\.threshold)
          Divider();Text("Noise").font(.headline);control(6,\.noiseAmount)
          Picker("Distribution",selection:Binding(get:{model.filter.lensBlur?.distribution ?? .uniform},set:{v in model.update{$0.lensBlur?.distribution=v}})) { Text("Uniform").tag(RasterFilter.Distribution.uniform);Text("Gaussian").tag(RasterFilter.Distribution.gaussian) }
          Toggle("Monochromatic",isOn:boolean(\.monochromatic))
          Button("Reset") { model.change(RasterFilter(.lensBlur)) }
        }.padding(.trailing,5) }.frame(width:275)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.fit=false;model.zoom=max(0.125,model.zoom/1.5) };Button("+") { model.fit=false;model.zoom=min(8,model.zoom*1.5) }
        Button("100%") { model.fit=false;model.zoom=1 };Button("Fit") { model.fit=true }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter=model.filter;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }.controlSize(.small)
      if let error=model.error { Text(error).foregroundStyle(.red).font(.caption) }
    }.padding(16).frame(width:840,height:620)
    .task { store.lensBlurWorkspace=model;guard model.image==nil,!model.rendering,let draft=store.filterDraft else{return};await model.prepare(document:store.document,draft:draft) }
    .onDisappear { model.close();if store.lensBlurWorkspace === model { store.lensBlurWorkspace=nil } }
  }
  var preview:some View {
    GeometryReader { g in
      ScrollView([.horizontal,.vertical]) {
        if let image=model.preview ? model.image:model.originalImage {
          let scale=model.fit ? min((g.size.width-24)/Double(image.width),(g.size.height-24)/Double(image.height)):model.zoom
          Image(decorative:image,scale:1).resizable().interpolation(.none).frame(width:Double(image.width)*scale,height:Double(image.height)*scale)
            .contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { e in model.pickFocus(x:e.location.x/scale,y:e.location.y/scale) })
            .padding(12).frame(minWidth:g.size.width,minHeight:g.size.height)
        }
      }.background(Color(white:0.12)).accessibilityLabel("Lens Blur preview; click to set focal distance")
    }
  }
  func boolean(_ key:WritableKeyPath<LensBlurSettings,Bool>)->Binding<Bool> { .init(get:{model.filter.lensBlur?[keyPath:key] ?? false},set:{v in model.update{$0.lensBlur?[keyPath:key]=v}}) }
  func control(_ index:Int,_ key:WritableKeyPath<LensBlurSettings,Double>)->some View {
    let p=LensBlurSettings.controls[index],value=Binding(get:{model.filter.lensBlur?[keyPath:key] ?? 0},set:{v in model.update{$0.lensBlur?[keyPath:key]=v}})
    return VStack(spacing:3) {
      HStack { Text(p.title);Spacer();TextField(p.title,value:value,format:.number.precision(.fractionLength(0...2))).frame(width:60).textFieldStyle(.roundedBorder) }
      Slider(value:value,in:p.bounds,onEditingChanged:{editing in if editing { model.beginGesture() } else { model.endGesture() } }).accessibilityLabel(p.title)
    }
  }
}
