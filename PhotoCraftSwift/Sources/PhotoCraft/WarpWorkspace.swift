import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class WarpWorkspace: Identifiable {
  let id=UUID(),source:CraftDocument,layer:Layer,width:Int,height:Int
  let sourceSession:UUID?,sourceLifecycle:UUID?
  var settings:WarpDefinition
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var showGuides=true
  var rendering=false
  var error:String?
  var edit:WarpEdit?
  var selectedPoint:Int?
  var splitPosition=0.5
  var undoStates=[WarpDefinition]()
  var redoStates=[WarpDefinition]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var generation=0
  private var closed=false
  private var gestureStart:WarpDefinition?
  init(source:CraftDocument,layer:Layer,session:UUID?=nil,lifecycle:UUID?=nil) {
    self.source=source;self.layer=layer;sourceSession=session;sourceLifecycle=lifecycle;settings=layer.warp ?? WarpDefinition()
    if case .raster(let p)=layer.content { width=p.width;height=p.height } else { width=1;height=1 }
  }
  var ready:Bool { edit != nil && !rendering && !closed && error == nil }
  var controls:WarpMesh? { settings.mesh ?? (try? settings.custom(width:width,height:height).mesh) }
  func change(_ value:WarpDefinition,remember:Bool=true) {
    guard !closed else{return}
    do { try value.validate() } catch { self.error=error.localizedDescription;return }
    guard value != settings else { return }
    if remember { rememberUndo(settings) };settings=value;refresh()
  }
  private func rememberUndo(_ value:WarpDefinition) { undoStates.append(value);if undoStates.count>100 { undoStates.removeFirst() };redoStates.removeAll() }
  func undo() { endGesture();guard let previous=undoStates.popLast() else { return };redoStates.append(settings);change(previous,remember:false) }
  func redo() { endGesture();guard let next=redoStates.popLast() else { return };undoStates.append(settings);change(next,remember:false) }
  func beginGesture() { if gestureStart == nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { rememberUndo(before) };gestureStart=nil }
  func choose(_ style:WarpStyle) {
    do { var value=settings;value.style=style;value.mesh=nil
      if style == .custom { value=try settings.custom(width:width,height:height) }
      else if style != .none && value.bend == 0 { value.bend=50 }
      selectedPoint=nil;change(value)
    } catch { self.error=error.localizedDescription }
  }
  func grid(_ count:Int) { do { selectedPoint=nil;change(try settings.custom(width:width,height:height,columns:count,rows:count)) } catch { self.error=error.localizedDescription } }
  func drag(_ index:Int,to point:PathPoint) {
    do { beginGesture();var value=settings
      if value.mesh == nil { value=try value.custom(width:width,height:height) }
      guard value.mesh!.points.indices.contains(index) else { return }
      value.mesh!.points[index]=point;selectedPoint=index;change(value,remember:false)
    } catch { self.error=error.localizedDescription }
  }
  func split(vertical:Bool,cross:Bool=false) {
    do { var value=settings.mesh == nil ? try settings.custom(width:width,height:height):settings
      try value.mesh!.split(at:splitPosition,vertical:vertical)
      if cross { try value.mesh!.split(at:splitPosition,vertical:!vertical) };selectedPoint=nil;change(value)
    } catch { self.error=error.localizedDescription }
  }
  func remove(vertical:Bool) {
    do { guard var mesh=settings.mesh else { return }
      let knots=vertical ? mesh.us:mesh.vs
      guard knots.count>2 else { throw CraftError.invalid("There are no interior splits in this direction.") }
      let index=(1..<(knots.count-1)).min(by:{abs(knots[$0]-splitPosition)<abs(knots[$1]-splitPosition)})!
      try mesh.removeSplit(index:index,vertical:vertical);var value=settings;value.mesh=mesh;selectedPoint=nil;change(value)
    } catch { self.error=error.localizedDescription }
  }
  func refresh() {
    guard !closed else{return}
    task?.cancel();edit=nil;error=nil;rendering=true;generation += 1
    let token=generation,source=source,layerID=layer.id,value=settings,needOriginal=originalImage == nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (WarpEdit,CGImage,CGImage?) in
          let edit=try WarpEdit.prepare(source,layerID:layerID,warp:value)
          let bounds=try RasterPreviewRequest.overview(width:source.width,height:source.height)
          return (edit,try ColorManagement.displayImage(bounds.reducing(Renderer.composite(edit.result)),in:source),needOriginal ? try ColorManagement.displayImage(bounds.reducing(Renderer.composite(source)),in:source):nil)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.edit=result.0;self.image=result.1;if let before=result.2 { self.originalImage=before };self.rendering=false
      } catch { guard let self,!self.closed,self.generation == token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation += 1;task?.cancel();task=nil;rendering=false }
}

struct WarpSheet:View {
  @Bindable var store:EditorStore
  @Bindable var model:WarpWorkspace
  func amount(_ key:WritableKeyPath<WarpDefinition,Double>)->Binding<Double> {
    Binding(get:{model.settings[keyPath:key]},set:{ n in var value=model.settings;value[keyPath:key]=n;model.change(value,remember:false) })
  }
  var body:some View {
    VStack(alignment:.leading,spacing:12) {
      HStack { Text("Warp").font(.headline);Spacer();Text(model.layer.name).foregroundStyle(.secondary) }
      HStack(alignment:.top,spacing:18) {
        WarpPreview(model:model).frame(minWidth:460,minHeight:400)
        VStack(alignment:.leading,spacing:10) {
          Picker("Warp",selection:Binding(get:{model.settings.style},set:{model.choose($0)})) { ForEach(WarpStyle.allCases,id:\.self) { Text($0.title).tag($0) } }
          ForEach([("Bend",\WarpDefinition.bend),("Horizontal",\WarpDefinition.horizontalDistortion),("Vertical",\WarpDefinition.verticalDistortion)],id:\.0) { label,key in
            HStack { Text(label);Spacer();Text(model.settings[keyPath:key].formatted(.number.precision(.fractionLength(0)))+"%") }
            Slider(value:amount(key),in:-100...100,onEditingChanged:{ if $0 { model.beginGesture() } else { model.endGesture() } }).disabled(model.settings.style == .custom || model.settings.style == .none)
          }
          Toggle("Vertical orientation",isOn:Binding(get:{model.settings.vertical},set:{n in var value=model.settings;value.vertical=n;model.change(value)})).disabled(model.settings.style == .custom)
          Picker("Interpolation",selection:Binding(get:{model.settings.interpolation},set:{n in var value=model.settings;value.interpolation=n;model.change(value)})) { ForEach(Resampling.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
          Menu("Grid") { ForEach([1,3,4,5],id:\.self) { n in Button(n == 1 ? "Default":"\(n) × \(n)") { model.grid(n) } } }
          HStack { Text("Split at");TextField("Position",value:$model.splitPosition,format:.percent).frame(width:65) }
          HStack { Button("Horizontal") { model.split(vertical:false) };Button("Vertical") { model.split(vertical:true) } }.font(.caption)
          HStack { Button("Remove H") { model.remove(vertical:false) }.disabled((model.settings.mesh?.vs.count ?? 0)<=2);Button("Remove V") { model.remove(vertical:true) }.disabled((model.settings.mesh?.us.count ?? 0)<=2) }.font(.caption)
          Toggle("Show Guides",isOn:$model.showGuides);Toggle("Preview",isOn:$model.preview)
          Text("Drag the control points to reshape. Smart Objects retain their original pixels.").font(.caption).foregroundStyle(.secondary)
        }.frame(width:260)
      }
      if let error=model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Undo") { model.undo() }.disabled(model.undoStates.isEmpty).keyboardShortcut("z",modifiers:.command)
        Button("Redo") { model.redo() }.disabled(model.redoStates.isEmpty).keyboardShortcut("z",modifiers:[.command,.shift])
        Button("Reset") { model.change(WarpDefinition()) };Spacer()
        if model.rendering { ProgressView().controlSize(.small) }
        Button("Cancel") { store.cancelWarp() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitWarp() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:820,height:610).task { if model.edit == nil && !model.rendering { model.refresh() } }.onDisappear { model.close() }
  }
}
struct WarpPreview:View {
  @Bindable var model:WarpWorkspace
  @State private var dragged:Int?
  var body:some View {
    GeometryReader { geometry in
      let padding=40.0,scale=min((geometry.size.width-padding*2)/Double(model.source.width),(geometry.size.height-padding*2)/Double(model.source.height))
      let origin=CGPoint(x:(geometry.size.width-Double(model.source.width)*scale)/2,y:(geometry.size.height-Double(model.source.height)*scale)/2)
      let mapping=Transform2D.translation(origin.x,origin.y) * .scale(scale,scale) * model.layer.coordinateTransform
      let mesh=model.controls
      Canvas { context,size in
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.12)))
        if let image=model.preview ? model.image:model.originalImage { context.draw(Image(decorative:image,scale:1),in:CGRect(x:origin.x,y:origin.y,width:Double(model.source.width)*scale,height:Double(model.source.height)*scale)) }
        if model.showGuides,let mesh {
          var path=Path()
          for vertical in [true,false] { for k in 0...6 { for n in 0...64 {
            let s=Double(vertical ? k:n)/Double(vertical ? 6:64),t=Double(vertical ? n:k)/Double(vertical ? 64:6)
            let p=model.settings.point(s*Double(model.width),t*Double(model.height),width:Double(model.width),height:Double(model.height)).transformed(mapping)
            if n == 0 { path.move(to:CGPoint(x:p.x,y:p.y)) } else { path.addLine(to:CGPoint(x:p.x,y:p.y)) }
          } } };context.stroke(path,with:.color(.cyan.opacity(0.75)),lineWidth:1)
          for (index,control) in mesh.points.enumerated() { let p=control.transformed(mapping),rect=CGRect(x:p.x-3.5,y:p.y-3.5,width:7,height:7);context.fill(Path(ellipseIn:rect),with:.color(index == model.selectedPoint ? .orange:.white)) }
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        guard model.showGuides,let mesh,let inverse=try? mapping.inverted() else { return }
        if dragged == nil { dragged=mesh.points.indices.min { a,b in let p=mesh.points[a].transformed(mapping),q=mesh.points[b].transformed(mapping);return hypot(p.x-value.startLocation.x,p.y-value.startLocation.y)<hypot(q.x-value.startLocation.x,q.y-value.startLocation.y) }
          if let index=dragged { let p=mesh.points[index].transformed(mapping);if hypot(p.x-value.startLocation.x,p.y-value.startLocation.y)>16 { dragged=nil } }
        }
        if let index=dragged { let p=inverse.point(value.location.x,value.location.y);model.drag(index,to:PathPoint(p.x,p.y)) }
      }.onEnded { _ in model.endGesture();dragged=nil })
      .accessibilityLabel("Warp preview. Drag a control point to reshape the image.")
    }
  }
}
extension EditorStore {
  var canBeginWarp:Bool { !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingMask && !editingComponent && document.activeLayerID.map{(try? WarpEdit.target(document,layerID:$0)) != nil} == true }
  func beginWarp() { guard canBeginWarp,let id=document.activeLayerID,let layer=try? WarpEdit.target(document,layerID:id) else { return };warpDraft=WarpWorkspace(source:document,layer:layer,session:sessionGeneration,lifecycle:layerPanelGeneration) }
  func cancelWarp() { warpDraft?.close();warpDraft=nil }
  func commitWarp() { guard let draft=warpDraft,draft.ready,let edit=draft.edit else { return }
    guard draft.sourceSession==sessionGeneration,draft.sourceLifecycle==layerPanelGeneration,draft.source==document else{draft.error="The Warp source changed. Cancel and preview again.";return}
    cancelWarp();performGeometry(.warp(edit))
  }
}
extension AppDelegate { @objc func warpLayer() { store?.beginWarp() } }
