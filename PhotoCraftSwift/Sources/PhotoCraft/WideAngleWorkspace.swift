import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class WideAngleWorkspace {
  enum Tool:String,CaseIterable { case constraint="Constraint",polygon="Polygon Constraint",hand="Hand" }
  var settings=WideAngleSettings()
  var tool:Tool = .constraint
  var selected=0
  var selectedSegment=0
  var selectedPoint=0
  var polygon=[PathPoint]()
  var closePolygon=true
  var image:CGImage?
  var originalImage:CGImage?
  var mesh:WideAngleMesh?
  var documentSize=CGSize(width:1,height:1)
  var sourceSize=CGSize(width:1,height:1)
  var sourceTransform=Transform2D.identity
  var preview=true
  var showConstraints=true
  var showMesh=false
  var pan=CGSize.zero
  var zoom=1.0
  var rendering=false
  var error:String?
  var undoStates=[WideAngleSettings]()
  var redoStates=[WideAngleSettings]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var gestureStart:WideAngleSettings?
  private var generation=0
  private var closed=false
  var ready:Bool { image != nil && !rendering && error == nil && polygon.isEmpty }
  var constraint:WideAngleSettings.Constraint? { settings.constraints.indices.contains(selected) ? settings.constraints[selected]:nil }
  var resolvedModel:WideAngleSettings.Model { WideAngleCamera(settings,width:Int(sourceSize.width),height:Int(sourceSize.height)).model }
  func prepare(document:CraftDocument,draft:FilterDraft) async {
    self.document=document;self.draft=draft;settings=draft.filter.wideAngle ?? .init();closed=false;documentSize=CGSize(width:document.width,height:document.height)
    refresh();await task?.value
  }
  func remember(_ s:WideAngleSettings) { undoStates.append(s);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ s:WideAngleSettings,remember:Bool=true) {
    do { try s.validate() } catch { self.error=error.localizedDescription;return }
    guard s != settings else { error=nil;return };if remember && gestureStart==nil { self.remember(settings) };settings=s;selected=max(0,min(selected,s.constraints.count-1));if let c=constraint { selectedSegment=max(0,min(selectedSegment,c.segmentCount-1));selectedPoint=max(0,min(selectedPoint,c.points.count-1)) };refresh()
  }
  func beginGesture() { if gestureStart==nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { remember(before) };gestureStart=nil }
  func slider(_ on:Bool) { if on { beginGesture() } else { endGesture() } }
  func undo() { if !polygon.isEmpty { polygon.removeLast();return };endGesture();guard let s=undoStates.popLast() else { return };redoStates.append(settings);change(s,remember:false) }
  func redo() { endGesture();guard let s=redoStates.popLast() else { return };undoStates.append(settings);change(s,remember:false) }
  func bounded(_ p:PathPoint)->PathPoint { .init(min(1,max(0,p.x)),min(1,max(0,p.y))) }
  func addLine(_ a:PathPoint,_ b:PathPoint,axis:Bool=false) {
    let a=bounded(a),b=bounded(b);guard hypot(a.x-b.x,a.y-b.y)>1e-6 else { return };var s=settings,c=WideAngleSettings.Constraint(points:[a,b])
    if axis { c.setOrientation(abs((a.x-b.x)*sourceSize.width)>=abs((a.y-b.y)*sourceSize.height) ? .horizontal:.vertical,at:0) }
    s.constraints.append(c);selected=s.constraints.count-1;selectedSegment=0;selectedPoint=0;change(s)
  }
  func addPolygonPoint(_ point:PathPoint) {
    let point=bounded(point)
    if polygon.count>=3,let first=polygon.first,hypot((point.x-first.x)*sourceSize.width,(point.y-first.y)*sourceSize.height)<8 { closePolygon=true;finishPolygon();return }
    if let last=polygon.last,hypot(last.x-point.x,last.y-point.y)<1e-6 { return }
    guard polygon.count<32 else { error="A polygon supports up to 32 points.";return };polygon.append(point)
  }
  func finishPolygon() {
    guard polygon.count >= (closePolygon ? 3:2) else { error="Add more polygon points.";return };var s=settings;s.constraints.append(.init(points:polygon,closed:closePolygon))
    do { try s.validate();polygon=[];selected=s.constraints.count-1;selectedPoint=0;selectedSegment=0;change(s) } catch { self.error=error.localizedDescription }
  }
  func movePoint(constraint index:Int,point:Int,to p:PathPoint) {
    guard settings.constraints.indices.contains(index),settings.constraints[index].points.indices.contains(point) else { return };var s=settings;s.constraints[index].points[point]=bounded(p);selected=index;selectedPoint=point;selectedSegment=min(point,s.constraints[index].segmentCount-1);change(s)
  }
  func moveConstraint(_ index:Int,dx:Double,dy:Double) {
    var s=gestureStart ?? settings;guard s.constraints.indices.contains(index) else { return };s.constraints[index].points=s.constraints[index].points.map{bounded(.init($0.x+dx,$0.y+dy))};change(s)
  }
  func orient(_ value:WideAngleSettings.Orientation,angle:Double?=nil) {
    guard settings.constraints.indices.contains(selected) else { return };var s=settings;guard (0..<s.constraints[selected].segmentCount).contains(selectedSegment) else { return };let old=s.constraints[selected].angle(selectedSegment);s.constraints[selected].setOrientation(value,angle:angle ?? old,at:selectedSegment);change(s)
  }
  func remove() { guard settings.constraints.indices.contains(selected) else { return };var s=settings;s.constraints.remove(at:selected);selected=max(0,min(selected,s.constraints.count-1));selectedSegment=0;selectedPoint=0;change(s) }
  func refresh() {
    guard !closed,let document,var draft else { return };task?.cancel();generation+=1;let token=generation,needsOriginal=originalImage==nil,s=settings
    draft.filter.wideAngle=s;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(100))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?,WideAngleMesh,Transform2D) in
          let layer=try request.inputLayer(in:document);guard case .raster(let input)=layer.content else { throw CraftError.invalid("Wide Angle requires pixels.") }
          let mesh=try WideAngleSolver.solve(s,width:input.width,height:input.height)
          var edited=document;try request.command(in:document).apply(to:&edited)
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:document),needsOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil,mesh,layer.coordinateTransform)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation==token else { return };self.image=result.0;if let original=result.1 { self.originalImage=original };self.mesh=result.2;self.sourceSize=CGSize(width:result.2.width,height:result.2.height);self.sourceTransform=result.3;self.rendering=false
      } catch { guard let self,!self.closed,self.generation==token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}
