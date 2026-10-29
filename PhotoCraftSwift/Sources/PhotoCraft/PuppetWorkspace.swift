import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PuppetWorkspace {
  var settings=PuppetSettings()
  var image:CGImage?
  var originalImage:CGImage?
  var mesh:PuppetMesh?
  var deformed:[PathPoint]=[]
  var drawOrder:[Int]=[]
  var origin=PathPoint(0,0)
  var documentSize=CGSize(width:1,height:1)
  var selectedPin:Int?
  var showMesh=true
  var preview=true
  var rendering=false
  var loading=false
  var zoom=1.0
  var error:String?
  var undoStates=[PuppetSettings]()
  var redoStates=[PuppetSettings]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var input:Surface?
  private var generation=0
  private var closed=false
  private var gestureStart:PuppetSettings?
  var ready:Bool { input != nil && image != nil && !loading && !rendering && error == nil }
  func prepare(document:CraftDocument,draft:FilterDraft) async {
    self.document=document;self.draft=draft;settings=draft.filter.puppet ?? .init();documentSize=CGSize(width:document.width,height:document.height);closed=false;loading=true
    do {
      let worker=Task.detached(priority:.userInitiated) { () throws -> Layer in
        try PuppetEngine.validateTarget(document,layerID:draft.id)
        var layer=document.layers.first{$0.id == draft.id}!
        if layer.smartObject != nil {
          var stack=layer.smartFilters ?? SmartFilterStack()
          if let filterID=draft.filterID { guard let i=stack.filters.firstIndex(where:{$0.id == filterID}) else { throw CraftError.invalid("Missing Puppet filter.") };stack.filters=Array(stack.filters.prefix(i)) }
          stack.mask=nil;stack.enabled=true;layer.smartFilters=stack;return try SmartFilterEngine.renderedLayer(layer,in:document)
        }
        guard case .raster(let pixels)=layer.content else { throw CraftError.invalid("Missing Puppet pixels.") }
        let mapping=try WarpRaster.mapping(WarpDefinition(),width:pixels.width,height:pixels.height,transform:layer.coordinateTransform)
        return try WarpRaster.baked(layer,in:document,using:mapping,method:.bicubic)
      }
      let layer=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
      try Task.checkCancellation();guard !closed,case .raster(let pixels)=layer.content else { loading=false;return }
      input=pixels;origin=PathPoint(Double(layer.x),Double(layer.y));loading=false;refresh();await task?.value
    } catch { loading=false;if !Task.isCancelled { self.error=error.localizedDescription } }
  }
  private func remember(_ value:PuppetSettings) { undoStates.append(value);if undoStates.count>100 { undoStates.removeFirst() };redoStates.removeAll() }
  func change(_ value:PuppetSettings,remember:Bool=true) {
    do { try value.validate() } catch { self.error=error.localizedDescription;return }
    guard value != settings else { return }
    if remember && gestureStart == nil { self.remember(settings) };settings=value
    if let selectedPin,!settings.pins.indices.contains(selectedPin) { self.selectedPin=nil };refresh()
  }
  func beginGesture() { if gestureStart == nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { remember(before) };gestureStart=nil }
  func sourcePoint(for point:PathPoint)->PathPoint {
    guard let mesh,deformed.count == mesh.vertices.count else { return point }
    let p=PathPoint(point.x-origin.x,point.y-origin.y)
    // Pick the triangle painted on top, then carry its barycentric coordinates
    // back to the undeformed mesh so a new pin anchors the visible position.
    for index in drawOrder.reversed() {
      let t=mesh.triangles[index],a=deformed[t[0]],b=deformed[t[1]],c=deformed[t[2]],det=(b.x-a.x)*(c.y-a.y)-(c.x-a.x)*(b.y-a.y)
      guard abs(det)>1e-12 else { continue }
      let v=((p.x-a.x)*(c.y-a.y)-(c.x-a.x)*(p.y-a.y))/det,w=((b.x-a.x)*(p.y-a.y)-(p.x-a.x)*(b.y-a.y))/det,u=1-v-w
      if min(u,v,w)>=(-1e-9) { let q=zip(t,[u,v,w]);return PathPoint(q.reduce(origin.x){$0+mesh.vertices[$1.0].x*$1.1},q.reduce(origin.y){$0+mesh.vertices[$1.0].y*$1.1}) }
    }
    return point
  }
  func add(_ point:PathPoint) { var value=settings;value.pins.append(PuppetPin(source:sourcePoint(for:point),destination:point));change(value);if settings == value { selectedPin=value.pins.count-1 } }
  func move(_ index:Int,to point:PathPoint) { guard settings.pins.indices.contains(index) else { return };var value=settings;value.pins[index].destination=point;change(value,remember:false) }
  func remove() { guard let selectedPin,settings.pins.indices.contains(selectedPin) else { return };var value=settings;value.pins.remove(at:selectedPin);self.selectedPin=nil;change(value) }
  func undo() { endGesture();guard let value=undoStates.popLast() else { return };redoStates.append(settings);change(value,remember:false) }
  func redo() { endGesture();guard let value=redoStates.popLast() else { return };undoStates.append(settings);change(value,remember:false) }
  func refresh() {
    guard !closed,let document,let input,var draft else { return }
    task?.cancel();generation += 1;let token=generation,value=settings,origin=origin,needOriginal=originalImage == nil
    draft.filter.puppet=value;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?,PuppetEngine.Deformation) in
          let deformation=try PuppetEngine.deform(input,origin:origin,settings:value)
          var edited=document;try request.command(in:document).apply(to:&edited)
          let image=try ColorManagement.displayImage(Renderer.composite(edited),in:document)
          let original=needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil
          return (image,original,deformation)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.image=result.0;if let original=result.1 { self.originalImage=original };self.mesh=result.2.mesh;self.deformed=result.2.vertices;self.drawOrder=result.2.order;self.rendering=false
      } catch { guard let self,!self.closed,self.generation == token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation += 1;task?.cancel();task=nil;rendering=false }
}
struct PuppetSheet:View {
  @Bindable var store:EditorStore
  @State private var model:PuppetWorkspace
  init(store:EditorStore,model:PuppetWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? PuppetWorkspace()) }
  private func setting<T>(_ path:WritableKeyPath<PuppetSettings,T>)->Binding<T> {
    Binding(get:{model.settings[keyPath:path]},set:{ n in var value=model.settings;value[keyPath:path]=n;model.change(value) })
  }
  private func pin<T>(_ path:WritableKeyPath<PuppetPin,T>,fallback:T)->Binding<T> {
    Binding(get:{ guard let i=model.selectedPin,model.settings.pins.indices.contains(i) else { return fallback };return model.settings.pins[i][keyPath:path] },set:{ n in guard let i=model.selectedPin,model.settings.pins.indices.contains(i) else { return };var value=model.settings;value.pins[i][keyPath:path]=n;model.change(value) })
  }
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      HStack { Text("Puppet Warp").font(.headline);Spacer();if model.loading || model.rendering { ProgressView().controlSize(.small) } }
      HStack(alignment:.top,spacing:18) {
        PuppetPreview(model:model).frame(minWidth:500,minHeight:420).clipped()
        VStack(alignment:.leading,spacing:12) {
          Picker("Mode",selection:setting(\.mode)) { ForEach(PuppetSettings.Mode.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
          Picker("Density",selection:setting(\.density)) { ForEach(PuppetSettings.Density.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }
          HStack { Text("Expansion");TextField("Pixels",value:setting(\.expansion),format:.number).frame(width:70);Text("px") }
          Picker("Interpolation",selection:setting(\.interpolation)) { ForEach(Resampling.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
          Toggle("Show Mesh",isOn:$model.showMesh)
          Divider()
          Text(model.selectedPin.map{"Pin \($0+1)"} ?? "Select a pin").font(.headline)
          VStack(alignment:.leading,spacing:10) {
            HStack { Text("X");TextField("X",value:pin(\.destination.x,fallback:0),format:.number);Text("Y");TextField("Y",value:pin(\.destination.y,fallback:0),format:.number) }
            Toggle("Auto rotation",isOn:Binding(get:{model.selectedPin.flatMap{model.settings.pins.indices.contains($0) ? model.settings.pins[$0].rotation:nil} == nil},set:{auto in pin(\.rotation,fallback:nil).wrappedValue=auto ? nil:0}))
            if let i=model.selectedPin,model.settings.pins.indices.contains(i),model.settings.pins[i].rotation != nil {
              HStack { Text("Angle");TextField("Degrees",value:Binding(get:{model.settings.pins[i].rotation ?? 0},set:{pin(\.rotation,fallback:nil).wrappedValue=$0}),format:.number);Text("°") }
            }
            Stepper("Depth \(pin(\.depth,fallback:0).wrappedValue)",value:pin(\.depth,fallback:0),in:-1000...1000)
            Button("Remove Pin") { model.remove() }.keyboardShortcut(.delete,modifiers:[])
          }.disabled(model.selectedPin == nil)
          Button("Remove All Pins") { var value=model.settings;value.pins=[];model.change(value) }.disabled(model.settings.pins.isEmpty)
          Text("Click to place a pin. Drag to reshape. Place fixed pins around areas that should stay still.").font(.caption).foregroundStyle(.secondary)
          if let mesh=model.mesh { Text("\(model.settings.pins.count) pins · \(mesh.vertices.count) mesh points").font(.caption).foregroundStyle(.secondary) }
        }.frame(width:260).disabled(model.loading)
      }
      if let error=model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Toggle("Preview",isOn:$model.preview)
        Button("−") { model.zoom=max(0.25,model.zoom/1.25) };Button("+") { model.zoom=min(8,model.zoom*1.25) };Button("Fit") { model.zoom=1 }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button("OK") { model.endGesture();store.filterDraft?.filter.puppet=model.settings;model.close();store.commitFilter() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:850,height:630).background(Color(nsColor:.windowBackgroundColor))
      .task { store.puppetWorkspace=model;guard !model.loading,model.image == nil,let draft=store.filterDraft else { return };await model.prepare(document:store.document,draft:draft) }
      .onDisappear { model.close();if store.puppetWorkspace === model { store.puppetWorkspace=nil } }
  }
}
struct PuppetPreview:View {
  @Bindable var model:PuppetWorkspace
  @State private var dragging:Int?
  @State private var pressed=false
  var body:some View {
    GeometryReader { geometry in
      let scale=min((geometry.size.width-60)/model.documentSize.width,(geometry.size.height-60)/model.documentSize.height)*model.zoom
      let offset=CGPoint(x:(geometry.size.width-model.documentSize.width*scale)/2,y:(geometry.size.height-model.documentSize.height*scale)/2)
      Canvas { context,size in
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        if let image=model.preview ? model.image:model.originalImage { context.draw(Image(decorative:image,scale:1),in:CGRect(x:offset.x,y:offset.y,width:model.documentSize.width*scale,height:model.documentSize.height*scale)) }
        if model.showMesh,let mesh=model.mesh,model.deformed.count == mesh.vertices.count {
          var path=Path()
          for triangle in mesh.triangles { for (k,i) in triangle.enumerated() { let p=model.deformed[i],point=CGPoint(x:offset.x+(p.x+model.origin.x)*scale,y:offset.y+(p.y+model.origin.y)*scale);if k == 0 { path.move(to:point) } else { path.addLine(to:point) } };path.closeSubpath() }
          context.stroke(path,with:.color(.white.opacity(0.35)),lineWidth:0.6)
        }
        for (i,pin) in model.settings.pins.enumerated() {
          let p=pin.destination,rect=CGRect(x:offset.x+p.x*scale-5,y:offset.y+p.y*scale-5,width:10,height:10)
          context.fill(Path(ellipseIn:rect),with:.color(i == model.selectedPin ? .orange:.yellow));context.stroke(Path(ellipseIn:rect),with:.color(.black),lineWidth:1)
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        guard !model.loading,model.mesh != nil else { return }
        if !pressed {
          pressed=true
          dragging=model.settings.pins.indices.min{ a,b in let p=model.settings.pins[a].destination,q=model.settings.pins[b].destination;return hypot(offset.x+p.x*scale-value.startLocation.x,offset.y+p.y*scale-value.startLocation.y)<hypot(offset.x+q.x*scale-value.startLocation.x,offset.y+q.y*scale-value.startLocation.y) }
          if let i=dragging { let p=model.settings.pins[i].destination;if hypot(offset.x+p.x*scale-value.startLocation.x,offset.y+p.y*scale-value.startLocation.y)>14 { dragging=nil } }
          if dragging == nil { model.add(PathPoint((value.startLocation.x-offset.x)/scale,(value.startLocation.y-offset.y)/scale));dragging=model.selectedPin }
          model.selectedPin=dragging;model.beginGesture()
        }
        if let i=dragging { model.move(i,to:PathPoint((value.location.x-offset.x)/scale,(value.location.y-offset.y)/scale)) }
      }.onEnded { _ in model.endGesture();pressed=false;dragging=nil })
      .accessibilityLabel("Puppet Warp preview. Click to place a pin, then drag to reshape.")
    }
  }
}
