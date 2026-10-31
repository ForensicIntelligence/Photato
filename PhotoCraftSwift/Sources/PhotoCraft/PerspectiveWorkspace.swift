import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PerspectiveWorkspace {
  enum Mode:String,CaseIterable { case layout,warp }
  var settings=PerspectiveSettings()
  var mode:Mode = .layout
  var image:CGImage?
  var originalImage:CGImage?
  var layoutImage:CGImage?
  var documentSize=CGSize(width:1,height:1)
  var selectedPlane:Int?
  var selectedCorner=0
  var selectedEdge=0
  var showGrid=true
  var preview=true
  var rendering=false
  var zoom=1.0
  var error:String?
  var undoStates=[PerspectiveSettings]()
  var redoStates=[PerspectiveSettings]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var generation=0
  private var closed=false
  private var gestureStart:PerspectiveSettings?
  var ready:Bool { image != nil && !rendering && error == nil }
  var map:PerspectiveMap? { try? PerspectiveMap(settings) }
  func prepare(document:CraftDocument,draft:FilterDraft) async {
    self.document=document;self.draft=draft;settings=draft.filter.perspective ?? .init();documentSize=CGSize(width:document.width,height:document.height);closed=false
    mode=settings.planes.isEmpty ? .layout:.warp;selectedPlane=settings.planes.isEmpty ? nil:0;refresh();await task?.value
  }
  private func remember(_ value:PerspectiveSettings) { undoStates.append(value);if undoStates.count>100 { undoStates.removeFirst() };redoStates.removeAll() }
  func change(_ value:PerspectiveSettings,remember:Bool=true) {
    do { try value.validate() } catch { self.error=error.localizedDescription;return }
    let value=value.normalized()
    guard value != settings else { error=nil;return }
    if remember && gestureStart == nil { self.remember(settings) };settings=value
    if let selectedPlane,!value.planes.indices.contains(selectedPlane) { self.selectedPlane=value.planes.isEmpty ? nil:0 };refresh()
  }
  func beginGesture() { if gestureStart == nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { remember(before) };gestureStart=nil }
  func undo() { endGesture();guard let value=undoStates.popLast() else { return };redoStates.append(settings);change(value,remember:false) }
  func redo() { endGesture();guard let value=redoStates.popLast() else { return };undoStates.append(settings);change(value,remember:false) }
  func addRectangle(_ a:PathPoint,_ b:PathPoint,snap:Double=0) {
    let x=min(a.x,b.x),y=min(a.y,b.y),w=abs(a.x-b.x),h=abs(a.y-b.y)
    guard w>=1,h>=1 else { return }
    var source=[PathPoint(x,y),PathPoint(x+w,y),PathPoint(x+w,y+h),PathPoint(x,y+h)],destination=[PathPoint]()
    let existing=settings.planes.flatMap(\.source),map=self.map
    for i in source.indices {
      if let near=existing.min(by:{hypot($0.x-source[i].x,$0.y-source[i].y)<hypot($1.x-source[i].x,$1.y-source[i].y)}),hypot(near.x-source[i].x,near.y-source[i].y)<=snap { source[i]=near }
      destination.append(map?.point(source[i]) ?? source[i])
    }
    var value=settings;value.planes.append(.init(source:source,destination:destination));change(value)
    if settings.planes.count == value.planes.count { selectedPlane=value.planes.count-1;selectedCorner=0 }
  }
  func move(plane:Int,corner:Int,to point:PathPoint,snap:Double=0) { change(settings.movingCorner(plane:plane,corner:corner,to:point,layout:mode == .layout,snap:snap),remember:gestureStart == nil) }
  func remove() {
    guard let selectedPlane else { return };var value=settings;value.planes.remove(at:selectedPlane)
    value.locks=value.locks.filter{$0.plane != selectedPlane}.map{var lock=$0;if lock.plane>selectedPlane { lock.plane -= 1 };return lock};change(value)
  }
  func resetWarp() { var value=settings;value.locks=[];for i in value.planes.indices { value.planes[i].destination=value.planes[i].source };change(value) }
  func straighten(_ mode:PerspectiveSettings.Straighten) { change(settings.straightened(mode)) }
  func toggleLock(plane:Int,edge:Int) {
    guard settings.planes.indices.contains(plane) else { return };var value=settings
    if let i=value.locks.firstIndex(where:{$0.plane == plane && $0.edge == edge}) { value.locks.remove(at:i) }
    else { let a=value.planes[plane].destination[edge],b=value.planes[plane].destination[(edge+1)%4];value.locks.append(.init(plane:plane,edge:edge,axis:abs(b.y-a.y)<=abs(b.x-a.x) ? .horizontal:.vertical)) }
    change(value);selectedPlane=plane;selectedEdge=edge
  }
  func refresh() {
    guard !closed,let document,var draft else { return };task?.cancel();generation += 1;let token=generation,needOriginal=originalImage == nil
    draft.filter.perspective=settings;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?,CGImage?) in
          try PerspectiveEngine.validateTarget(document,layerID:request.id)
          var edited=document;try request.command(in:document).apply(to:&edited)
          let image=try ColorManagement.displayImage(Renderer.composite(edited),in:document)
          let original=needOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil
          var layout:CGImage?
          if needOriginal {
            var input=document
            if let filterID=request.filterID,let i=input.layers.firstIndex(where:{$0.id == request.id}),let j=input.layers[i].smartFilters?.filters.firstIndex(where:{$0.id == filterID}) {
              let preceding=Array(input.layers[i].smartFilters!.filters.prefix(j))
              input.layers[i].smartFilters?.filters=preceding
              input.layers[i].smartFilters?.mask=nil
            }
            layout=try ColorManagement.displayImage(Renderer.composite(input),in:input)
          }
          return (image,original,layout)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.image=result.0;if let original=result.1 { self.originalImage=original };if let layout=result.2 { self.layoutImage=layout };self.rendering=false
      } catch { guard let self,!self.closed,self.generation == token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation += 1;task?.cancel();task=nil;rendering=false }
}
struct PerspectiveSheet:View {
  @Bindable var store:EditorStore
  @State private var model:PerspectiveWorkspace
  init(store:EditorStore,model:PerspectiveWorkspace?=nil) { self.store=store;_model=State(initialValue:model ?? PerspectiveWorkspace()) }
  private func coordinate(_ x:Bool)->Binding<Double> {
    Binding(get:{ guard let i=model.selectedPlane,model.settings.planes.indices.contains(i) else { return 0 };let plane=model.settings.planes[i],p=model.mode == .layout ? plane.source[model.selectedCorner]:plane.destination[model.selectedCorner];return x ? p.x:p.y },set:{ n in guard let i=model.selectedPlane,model.settings.planes.indices.contains(i) else { return };let plane=model.settings.planes[i];var p=model.mode == .layout ? plane.source[model.selectedCorner]:plane.destination[model.selectedCorner];if x { p.x=n } else { p.y=n };model.move(plane:i,corner:model.selectedCorner,to:p) })
  }
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      HStack { Text("Perspective Warp").font(.headline);Spacer();Button("Layout") { model.mode = .layout }.keyboardShortcut("l",modifiers:[]).tint(model.mode == .layout ? .accentColor:nil);Button("Warp") { model.mode = .warp }.keyboardShortcut("w",modifiers:[]).disabled(model.settings.planes.isEmpty);if model.rendering { ProgressView().controlSize(.small) } }
      HStack(alignment:.top,spacing:18) {
        PerspectivePreview(model:model).frame(minWidth:500,minHeight:420).clipped()
        ScrollView { VStack(alignment:.leading,spacing:12) {
          Text(model.mode == .layout ? "Drag to draw a plane. Match its corners to the image, then switch to Warp.":"Drag corners to adjust perspective. Shared corners move together.").font(.callout)
          Toggle("Show Grid",isOn:$model.showGrid).keyboardShortcut("h",modifiers:[])
          if !model.settings.planes.isEmpty {
            Picker("Plane",selection:Binding(get:{model.selectedPlane ?? 0},set:{model.selectedPlane=$0})) { ForEach(model.settings.planes.indices,id:\.self) { Text("Plane \($0+1)").tag($0) } }
            Picker("Corner",selection:$model.selectedCorner) { ForEach(0..<4) { Text("\($0+1)").tag($0) } }
            HStack { Text("X");TextField("X",value:coordinate(true),format:.number);Text("Y");TextField("Y",value:coordinate(false),format:.number) }.textFieldStyle(.roundedBorder)
            Button("Remove Plane") { model.remove() }
            Divider()
            Text("Straighten").font(.subheadline.bold())
            HStack { Button("Horizontal") { model.straighten(.horizontal) };Button("Vertical") { model.straighten(.vertical) } }.disabled(model.mode != .warp)
            Button("Auto Straighten") { model.straighten(.auto) }.disabled(model.mode != .warp)
            Picker("Edge",selection:$model.selectedEdge) { ForEach(0..<4) { Text("\($0+1)").tag($0) } }
            let locked=model.settings.locks.contains{$0.plane == model.selectedPlane && $0.edge == model.selectedEdge}
            Button(locked ? "Unlock Edge":"Straighten and Lock Edge") { if let i=model.selectedPlane { model.toggleLock(plane:i,edge:model.selectedEdge) } }.disabled(model.mode != .warp)
            Text("Shift-click an edge to straighten and lock it.").font(.caption).foregroundStyle(.secondary)
            Button("Reset Warp") { model.resetWarp() }
          }
          Divider()
          Picker("Interpolation",selection:Binding(get:{model.settings.interpolation},set:{ n in var value=model.settings;value.interpolation=n;model.change(value) })) { ForEach(Resampling.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
          Text("\(model.settings.planes.count) planes · \(model.settings.linkedCorners.filter{$0.count>1}.count) shared corners").font(.caption).foregroundStyle(.secondary)
          if let error=model.error { Text(error).font(.caption).foregroundStyle(.red) }
          Spacer()
        }.frame(width:250) }.frame(width:260)
      }
      HStack {
        Toggle("Preview",isOn:$model.preview).disabled(model.mode == .layout)
        Button("−") { model.zoom=max(0.25,model.zoom/1.5) };Button("+") { model.zoom=min(4,model.zoom*1.5) };Button("Fit") { model.zoom=1 }
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Spacer();Button("Cancel") { model.close();store.cancelFilter() }.keyboardShortcut(.cancelAction)
        Button(model.mode == .layout ? "Next":"OK") { if model.mode == .layout { model.mode = .warp } else { model.endGesture();store.filterDraft?.filter.perspective=model.settings;model.close();store.commitFilter() } }.keyboardShortcut(.defaultAction).disabled(!model.ready || model.settings.planes.isEmpty)
      }
    }.padding(20).frame(width:850,height:650).background(Color(nsColor:.windowBackgroundColor))
      .task { store.perspectiveWorkspace=model;guard model.image == nil,!model.rendering,let draft=store.filterDraft else { return };await model.prepare(document:store.document,draft:draft) }
      .onDisappear { model.close();if store.perspectiveWorkspace === model { store.perspectiveWorkspace=nil } }
  }
}
struct PerspectivePreview:View {
  @Bindable var model:PerspectiveWorkspace
  @State private var dragging:Int?
  @State private var pressed=false
  @State private var drawingStart:CGPoint?
  @State private var drawingEnd:CGPoint?
  var body:some View {
    GeometryReader { geometry in
      let scale=min((geometry.size.width-60)/model.documentSize.width,(geometry.size.height-60)/model.documentSize.height)*model.zoom
      let offset=CGPoint(x:(geometry.size.width-model.documentSize.width*scale)/2,y:(geometry.size.height-model.documentSize.height*scale)/2)
      let planes=model.settings.planes,map=model.map,warped=model.mode == .warp
      Canvas { context,size in
        func position(_ p:PathPoint)->CGPoint { CGPoint(x:offset.x+p.x*scale,y:offset.y+p.y*scale) }
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        if let image=warped ? (model.preview ? model.image:model.originalImage):model.layoutImage { context.draw(Image(decorative:image,scale:1),in:CGRect(x:offset.x,y:offset.y,width:model.documentSize.width*scale,height:model.documentSize.height*scale)) }
        if model.showGrid,let map {
          for i in planes.indices {
            var grid=Path()
            for j in 0...5 { let t=Double(j)/5;for axis in 0..<2 { for k in 0...20 { let q=Double(k)/20,p=map.planePoint(i,u:axis == 0 ? t:q,v:axis == 0 ? q:t,warped:warped);if k == 0 { grid.move(to:position(p)) } else { grid.addLine(to:position(p)) } } } }
            context.stroke(grid,with:.color(i == model.selectedPlane ? .cyan:.white.opacity(0.65)),lineWidth:0.7)
            let points=warped ? planes[i].destination:planes[i].source
            for (k,p) in points.enumerated() { let q=position(p),rect=CGRect(x:q.x-4,y:q.y-4,width:8,height:8);context.fill(Path(ellipseIn:rect),with:.color(i == model.selectedPlane && k == model.selectedCorner ? .orange:.white)) }
          }
          for lock in model.settings.locks where warped {
            let points=planes[lock.plane].destination;var edge=Path();edge.move(to:position(points[lock.edge]));edge.addLine(to:position(points[(lock.edge+1)%4]));context.stroke(edge,with:.color(.yellow),lineWidth:3)
          }
        }
        if let a=drawingStart,let b=drawingEnd { let rect=CGRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y));context.stroke(Path(rect),with:.color(.cyan),lineWidth:1) }
      }.toolCursor { flags in
        warped && flags.contains(.shift) ? .symbol("lock"):.symbol(warped ? "arrow.up.and.down.and.arrow.left.and.right":"plus")
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        func documentPoint(_ p:CGPoint)->PathPoint { PathPoint((p.x-offset.x)/scale,(p.y-offset.y)/scale) }
        let point=documentPoint(value.startLocation)
        if !pressed {
          pressed=true
          if warped && NSEvent.modifierFlags.contains(.shift) {
            var nearest:(Int,Int,Double)?
            for i in planes.indices { for k in 0..<4 { let a=planes[i].destination[k],b=planes[i].destination[(k+1)%4],dx=b.x-a.x,dy=b.y-a.y,l=dx*dx+dy*dy,t=l>0 ? max(0,min(1,((point.x-a.x)*dx+(point.y-a.y)*dy)/l)):0,distance=hypot(a.x+t*dx-point.x,a.y+t*dy-point.y);if distance*scale<=10 && distance<(nearest?.2 ?? .infinity) { nearest=(i,k,distance) } } }
            if let nearest { model.toggleLock(plane:nearest.0,edge:nearest.1);return }
          }
          var distance=14.0
          for i in planes.indices { for k in 0..<4 { let p=warped ? planes[i].destination[k]:planes[i].source[k],d=hypot(p.x-point.x,p.y-point.y)*scale;if d<distance { distance=d;dragging=i*4+k } } }
          if let dragging { model.selectedPlane=dragging/4;model.selectedCorner=dragging%4;model.beginGesture() }
          else if !warped { drawingStart=value.startLocation;drawingEnd=value.location }
        }
        if let dragging { model.move(plane:dragging/4,corner:dragging%4,to:documentPoint(value.location),snap:12/scale) }
        else if drawingStart != nil { drawingEnd=value.location }
      }.onEnded { _ in
        if let a=drawingStart,let b=drawingEnd { model.addRectangle(PathPoint((a.x-offset.x)/scale,(a.y-offset.y)/scale),PathPoint((b.x-offset.x)/scale,(b.y-offset.y)/scale),snap:12/scale) }
        model.endGesture();dragging=nil;pressed=false;drawingStart=nil;drawingEnd=nil
      }).accessibilityLabel("Perspective Warp preview. Draw planes in Layout mode, then drag linked corners in Warp mode.")
    }
  }
}
