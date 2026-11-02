import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct FreeformPathGesture {
  var original:CraftDocument
  var path:VectorPath
  var samples:[PathPoint]
  var tolerance:Double
  var hitTolerance:Double
  var component:Int?
  var prepend:Bool
  var preview:VectorPath {
    var result=path
    let stride=max(1,Int(ceil(Double(samples.count)/2048)))
    var previewSamples=samples.enumerated().compactMap{$0.offset % stride == 0 ? $0.element:nil};if let last=samples.last,previewSamples.last != last{previewSamples.append(last)}
    let part=PathComponent(knots:previewSamples.map{PathKnot($0)})
    result.components.append(part);return result
  }
}
extension EditorStore {
  func commitConstructedPath(_ path:VectorPath)throws {
    try path.validate()
    if selectedVectorPath != nil {
      guard pathIsEditable else{throw CraftError.invalid("Unlock the vector mask before editing its path.")}
      switch pathTarget {
      case .saved(let id):var saved=document.paths!.first{$0.id==id}!;saved.path=path;try executeEditorCommand(.savePath(saved))
      case .shape(let id):
        guard let layer=document.layers.first(where:{$0.id==id})else{throw CraftError.invalid("Shape not found.")}
        try executeEditorCommand(.shape(.configure(id,try layer.replacingShapePath(path,canvas:.init(x:0,y:0,width:document.width,height:document.height)))))
      case .vectorMask(let id):var mask=document.layers.first{$0.id==id}!.vectorMask!;mask.path=path;try executeEditorCommand(.vectorMask(id,mask))
      case nil:break
      }
    }else{
      var saved=NamedPath(path:path);if let old=document.paths?.first(where:\.isWorkPath){saved.id=old.id}
      try executeEditorCommand(.savePath(saved));selectPath(.saved(saved.id))
    }
  }
  func beginFreeform(at p:PathPoint,tolerance:Double) {
    guard !geometryBusy,!hasToneDraft,transformDraft==nil,pathIsEditable else{return}
    let path=selectedVectorPath ?? VectorPath();var component:Int?,prepend=false
    for i in path.components.indices where !path.components[i].closed {
      let knots=path.components[i].knots
      if let last=knots.last,hypot(last.anchor.x-p.x,last.anchor.y-p.y)<=tolerance{component=i;break}
      if let first=knots.first,hypot(first.anchor.x-p.x,first.anchor.y-p.y)<=tolerance{component=i;prepend=true;break}
    }
    let start=component.map{prepend ? path.components[$0].knots.first!.anchor:path.components[$0].knots.last!.anchor} ?? p
    freeformGesture = .init(original:document,path:path,samples:[start],tolerance:pathCurveFit,hitTolerance:tolerance,component:component,prepend:prepend);revision += 1
  }
  func extendFreeform(to p:PathPoint) {
    guard var gesture=freeformGesture else{return}
    guard gesture.original==document else{finishFreeform(cancel:true);return}
    guard gesture.samples.count<PathConstruction.maxSamples else{finishFreeform(cancel:true);error="Freeform path exceeds 100,000 samples.";return}
    if let last=gesture.samples.last,hypot(last.x-p.x,last.y-p.y)<0.25{return}
    gesture.samples.append(p);freeformGesture=gesture;revision += 1
  }
  func finishFreeform(cancel:Bool=false) {
    guard let gesture=freeformGesture else{return};freeformGesture=nil
    guard !cancel,gesture.original==document,gesture.samples.count>=2 else{render();return}
    do{
      var path=gesture.path
      let closes:Bool
      if let c=gesture.component{let end=gesture.prepend ? path.components[c].knots.last!.anchor:path.components[c].knots.first!.anchor;closes=hypot(end.x-gesture.samples.last!.x,end.y-gesture.samples.last!.y)<=gesture.hitTolerance}
      else{closes=gesture.samples.count>=3 && hypot(gesture.samples[0].x-gesture.samples.last!.x,gesture.samples[0].y-gesture.samples.last!.y)<=gesture.hitTolerance}
      var samples=gesture.samples
      if closes,let c=gesture.component{samples[samples.count-1]=gesture.prepend ? path.components[c].knots.last!.anchor:path.components[c].knots.first!.anchor}
      else if closes{samples.removeLast()}
      var part=try PathConstruction.fitted(samples,tolerance:gesture.tolerance,closed:closes && gesture.component==nil)
      if let c=gesture.component {
        var old=path.components[c]
        if gesture.prepend{part.knots=part.knots.reversed().map{.init($0.anchor,incoming:$0.outgoing,outgoing:$0.incoming,smooth:$0.smooth)};old.knots[0].incoming=part.knots.last!.incoming;old.knots=Array(part.knots.dropLast())+old.knots}
        else{old.knots[old.knots.count-1].outgoing=part.knots[0].outgoing;old.knots += part.knots.dropFirst()}
        if closes{old.knots[0].incoming=old.knots.last!.incoming;old.knots.removeLast();old.closed=true}
        path.components[c]=old
      }else{part.operation=pathOperation;path.components.append(part)}
      try commitConstructedPath(path)
    }catch{self.error=error.localizedDescription;render()}
  }
  func beginCurvature(at p:PathPoint,tolerance:Double,clickCount:Int) {
    guard !geometryBusy,!hasToneDraft,transformDraft==nil,pathIsEditable else{return}
    var path=selectedVectorPath ?? VectorPath()
    func near(_ q:PathPoint)->Bool{hypot(p.x-q.x,p.y-q.y)<=tolerance}
    do{
      if let c=penComponent,path.components.indices.contains(c),!path.components[c].closed,path.components[c].knots.count>=3,near(path.components[c].knots[0].anchor),clickCount<2 {
        path.components[c].closed=true;path.components[c]=try PathConstruction.curvature(path.components[c]);try commitConstructedPath(path);penComponent=nil;return
      }
      for c in path.components.indices{for k in path.components[c].knots.indices where near(path.components[c].knots[k].anchor) {
        pathAnchor = .init(component:c,knot:k)
        if clickCount>=2{path.components[c].knots[k].smooth.toggle();path.components[c]=try PathConstruction.curvature(path.components[c]);try commitConstructedPath(path)}
        else{pathGesture = .init(original:path,preview:path,start:p,selection:pathAnchor!,part:.anchor);if !path.components[c].closed,k==path.components[c].knots.count-1{penComponent=c}}
        return
      }}
      let c:Int
      if let current=penComponent,path.components.indices.contains(current),!path.components[current].closed{c=current}else{c=path.components.count;path.components.append(.init(operation:pathOperation))}
      path.components[c].knots.append(.init(p,smooth:clickCount<2));path.components[c]=try PathConstruction.curvature(path.components[c]);try commitConstructedPath(path);penComponent=c;pathAnchor = .init(component:c,knot:path.components[c].knots.count-1)
    }catch{self.error=error.localizedDescription}
  }
  func makeWorkPath() {
    let tolerance=pathCurveFit
    performGeometry(label:"Make Work Path",prepare:{try PathTracing.command($0,tolerance:tolerance)},onSuccess:{[weak self] in if let self,let path=self.document.paths?.first(where: \.isWorkPath){self.selectPath(.saved(path.id))}})
  }
  func paintSelectedPath(stroke:Bool,simulatePressure:Bool=false) {
    guard let path=selectedVectorPath,let id=activeLayer?.id else{return}
    guard !editingMask,!smartFilterMaskEditing,!editingComponent else{error="Select the RGB pixels before painting a path.";return}
    let brush=brush
    performGeometry(label:stroke ? "Stroke Path":"Fill Path",prepare:{try PathPainting.command(path,document:$0,layerID:id,brush:brush,stroke:stroke,simulatePressure:simulatePressure)})
  }
  func showMakeWorkPath() {
    let alert=NSAlert();alert.messageText="Make Work Path";alert.informativeText="Tolerance (0.5–10 pixels)";let field=NSTextField(string:String(pathCurveFit));field.frame=NSRect(x:0,y:0,width:200,height:24);alert.accessoryView=field;alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel")
    if alert.runModal() == .alertFirstButtonReturn{guard let value=Double(field.stringValue),value.isFinite,(0.5...10).contains(value) else{error="Tolerance must be 0.5–10 pixels.";return};pathCurveFit=value;makeWorkPath()}
  }
  func showStrokePath() {
    let alert=NSAlert();alert.messageText="Stroke Path";alert.informativeText="Uses the current Brush tip, size, foreground color and dynamics.";let check=NSButton(checkboxWithTitle:"Simulate Pressure",target:nil,action:nil);check.frame=NSRect(x:0,y:0,width:240,height:24);alert.accessoryView=check;alert.addButton(withTitle:"Stroke");alert.addButton(withTitle:"Cancel");if alert.runModal() == .alertFirstButtonReturn{paintSelectedPath(stroke:true,simulatePressure:check.state == .on)}
  }
}
