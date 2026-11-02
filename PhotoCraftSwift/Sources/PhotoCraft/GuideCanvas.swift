import AppKit
import PhotoCraftCore

extension ToolCursor {
  static func guide(_ axis:DocumentGuide.Axis,modifiers:NSEvent.ModifierFlags,selection:Bool?=nil)->Self {
    if let selected=selection,modifiers.contains([.shift,.option]) {return .symbol(axis == .vertical ? "arrow.left.and.right":"arrow.up.and.down",selected ? .subtract:.add)}
    let flipped=modifiers.contains(.option)
    let vertical=(axis == .vertical) != flipped
    return .symbol(vertical ? "arrow.left.and.right":"arrow.up.and.down",modifiers.contains(.shift) ? .constrain:nil)
  }
}

extension CraftCanvas {
  func guideAxis(at point:CGPoint)->DocumentGuide.Axis? {
    if let gesture=store.guideGesture{return gesture.lines.first?.axis}
    guard store.guideDraft==nil,store.canEditGuides else{return nil}
    if store.showRulers {
      if point.y<18,point.x>=18{return .horizontal}
      if point.x<18,point.y>=18{return .vertical}
    }
    return store.tool == .move ? hitGuide(at:viewport.documentPoint(at:point))?.axis:nil
  }
  func guideCursorSelection(at point:CGPoint)->Bool? {
    guard store.guideGesture==nil,store.tool == .move,!(store.showRulers && (point.x<18 || point.y<18)),let guide=hitGuide(at:viewport.documentPoint(at:point))else{return nil}
    return store.selectedGuideIDs.contains(guide.id)
  }
  func hitGuide(at point:CGPoint)->DocumentGuide? {
    guard store.showCanvasGuides else{return nil}
    let tolerance=5/max(scale,0.000001)
    return (store.document.guides ?? []).enumerated().compactMap {i,line->(DocumentGuide,Double,Int)? in
      let delta=abs((line.axis == .vertical ? point.x:point.y)-line.position)
      return delta<=tolerance ? (line,delta,i):nil
    }.min {a,b in a.1==b.1 ? a.2<b.2:a.1<b.1}?.0
  }
  func beginGuideGesture(_ event:NSEvent)->Bool {
    guard !spaceHeld,store.canEditGuides,store.unavailableToolID==nil else{return false}
    let view=convert(event.locationInWindow,from:nil),point=docPoint(event)
    if store.showRulers,view.x>=18,view.y<18 || store.showRulers && view.y>=18 && view.x<18 {
      let axis:DocumentGuide.Axis=view.y<18 ? .horizontal:.vertical
      let line=DocumentGuide(axis:axis,position:axis == .vertical ? point.x:point.y)
      store.guideGesture=GuideGesture(original:store.document,lines:[line],start:.init(point.x,point.y),newGuide:true,current:[line]);store.showCanvasGuides=true;needsDisplay=true;return true
    }
    guard store.tool == .move,let line=hitGuide(at:point)else{return false}
    if event.modifierFlags.contains([.shift,.option]) {
      if store.selectedGuideIDs.contains(line.id){store.selectedGuideIDs.remove(line.id)}else{store.selectedGuideIDs.insert(line.id)}
      needsDisplay=true;return true
    }
    if !store.selectedGuideIDs.contains(line.id){store.selectedGuideIDs=[line.id]}
    let selected=store.selectedGuides
    store.guideGesture=GuideGesture(original:store.document,lines:selected,start:.init(point.x,point.y),newGuide:false,current:selected)
    needsDisplay=true;return true
  }
  @discardableResult func dragGuideGesture(_ event:NSEvent)->Bool {
    guard store.guideGesture != nil else{return false}
    let point=docPoint(event),tick=pow(10,floor(log10(max(1,80/scale))))
    store.guideGesture?.update(.init(point.x,point.y),option:event.modifierFlags.contains(.option),shift:event.modifierFlags.contains(.shift),tick:tick)
    needsDisplay=true;refreshToolCursor();return true
  }
  func endGuideGesture(_ event:NSEvent)->Bool {
    guard dragGuideGesture(event),let gesture=store.guideGesture else{return false}
    store.guideGesture=nil
    guard store.document==gesture.original,!store.guidesLocked,!store.geometryBusy else{store.status="The document changed; the guide move was cancelled.";return true}
    let point=convert(event.locationInWindow,from:nil)
    let remove = !bounds.contains(point) || (store.showRulers && (point.x<18 || point.y<18))
    let command:GuideCommand
    if remove {
      if gesture.newGuide{return true}
      command = .delete(Set(gesture.lines.map(\.id)))
    }else {
      command = gesture.newGuide ? .add(gesture.current):.update(gesture.current)
      store.selectedGuideIDs=Set(gesture.current.map(\.id))
    }
    store.perform(.guides(command));return true
  }
  func drawDocumentGuides(in context:CGContext) {
    guard store.showCanvasGuides || store.guideDraft?.preview==true else{return}
    context.saveGState();defer{context.restoreGState()}
    let edge=store.showRulers ? 18.0:0.0
    context.clip(to:CGRect(x:edge,y:edge,width:max(0,bounds.width-edge),height:max(0,bounds.height-edge)))
    context.setLineWidth(1/max(window?.backingScaleFactor ?? 1,1));context.setLineDash(phase:0,lengths:[])
    for line in store.displayedGuides {
      let p=viewPoint(.init(x:line.axis == .vertical ? line.position:0,y:line.axis == .horizontal ? line.position:0))
      let vertical=line.axis == .vertical,coordinate=vertical ? p.x:p.y
      guard coordinate>=edge,coordinate<=(vertical ? bounds.width:bounds.height)else{continue}
      let color=line.color;context.setStrokeColor(NSColor(srgbRed:Double(color.r),green:Double(color.g),blue:Double(color.b),alpha:Double(color.a)*0.9).cgColor)
      context.move(to:vertical ? .init(x:p.x,y:edge):.init(x:edge,y:p.y))
      context.addLine(to:vertical ? .init(x:p.x,y:bounds.height):.init(x:bounds.width,y:p.y));context.strokePath()
      if store.selectedGuideIDs.contains(line.id) {context.setLineDash(phase:0,lengths:[3,3]);context.setStrokeColor(NSColor.white.cgColor);context.move(to:vertical ? .init(x:p.x,y:edge):.init(x:edge,y:p.y));context.addLine(to:vertical ? .init(x:p.x,y:bounds.height):.init(x:bounds.width,y:p.y));context.strokePath();context.setLineDash(phase:0,lengths:[])}
    }
  }
}
