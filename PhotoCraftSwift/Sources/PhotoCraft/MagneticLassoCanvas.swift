import AppKit
import PhotoCraftCore

extension CraftCanvas {
  var magneticNearStart:Bool {
    guard let draft=store.magneticDraft,draft.trace.points.count>=3,let first=draft.trace.points.first,let point=cursorDocumentPoint else{return false}
    return hypot(point.x-first.x,point.y-first.y)*scale<6
  }
  func magneticDown(_ event:NSEvent)->Bool {
    guard store.tool == .magneticLasso,!spaceHeld else{return false}
    let p=docPoint(event),point=SelectionPoint(p.x,p.y)
    guard p.x>=0,p.y>=0,p.x<Double(store.document.width),p.y<Double(store.document.height) else{return store.magneticDraft != nil}
    if let draft=store.magneticDraft {
      guard !draft.finishing else{return true}
      if event.clickCount>=2 || event.modifierFlags.contains(.command) || magneticNearStart {store.finishMagneticLasso(straight:event.modifierFlags.contains(.option))}
      else {draft.append(.init(draft.alternateReady && event.modifierFlags.contains(.option) ? .straight:.anchor,point:point,pressure:event.subtype == .tabletPoint ? Double(unit(event.pressure)):0))}
    }else {store.beginMagneticLasso(at:point,modifiers:event.modifierFlags){[weak self] in self?.needsDisplay=true;self?.refreshToolCursor()}}
    needsDisplay=true;return true
  }
  func magneticMotion(_ event:NSEvent,dragging:Bool)->Bool {
    guard store.tool == .magneticLasso,let draft=store.magneticDraft,!spaceHeld,!panningGesture else{return false}
    if !event.modifierFlags.contains(.option) {draft.alternateReady=true}
    guard !draft.finishing else{return true}
    let p=docPoint(event);guard p.x>=0,p.y>=0,p.x<Double(store.document.width),p.y<Double(store.document.height) else{return true}
    let alternate=draft.alternateReady && event.modifierFlags.contains(.option)
    // Option-hover previews a straight segment; Option-drag records freehand samples.
    if alternate && !dragging {draft.latest = .init(p.x,p.y);needsDisplay=true;refreshToolCursor();return true}
    draft.append(.init(alternate ? .freehand:.move,point:.init(p.x,p.y),pressure:event.subtype == .tabletPoint ? Double(unit(event.pressure)):0))
    needsDisplay=true;refreshToolCursor();return true
  }
  func magneticKey(_ event:NSEvent)->Bool {
    guard store.tool == .magneticLasso else{return false}
    if event.charactersIgnoringModifiers == "[" || event.charactersIgnoringModifiers == "]" {
      let value=min(256,max(1,store.magneticSettings.width+(event.charactersIgnoringModifiers == "]" ? 1:-1)))
      store.magneticSettings.width=value;store.magneticDraft?.append(.init(.width,width:value));needsDisplay=true;return true
    }
    guard let draft=store.magneticDraft else{return false}
    if event.keyCode==53 || (event.charactersIgnoringModifiers == "." && event.modifierFlags.contains(.command)) {store.cancelMagneticLasso();needsDisplay=true;return true}
    if [36,76].contains(event.keyCode) {store.finishMagneticLasso(straight:event.modifierFlags.contains(.option));return true}
    if [51,117].contains(event.keyCode) {draft.append(.init(.remove));needsDisplay=true;return true}
    return false
  }
  func drawMagneticLasso(in c:CGContext) {
    guard store.tool == .magneticLasso else{return}
    c.saveGState();c.clip(to:imageRect);defer{c.restoreGState()}
    if let draft=store.magneticDraft {
      let points=draft.trace.points
      c.setStrokeColor(NSColor.white.cgColor);c.setLineWidth(1)
      for (i,p) in points.enumerated() {let q=viewPoint(CGPoint(x:p.x,y:p.y));if i==0{c.move(to:q)}else{c.addLine(to:q)}}
      if let p=draft.latest {c.addLine(to:viewPoint(CGPoint(x:p.x,y:p.y)))}
      c.strokePath();c.setFillColor(NSColor.systemBlue.cgColor)
      for index in draft.trace.anchors {let p=points[index],q=viewPoint(CGPoint(x:p.x,y:p.y));c.fill(CGRect(x:q.x-2,y:q.y-2,width:4,height:4))}
    }else if magneticPrecision,let point=cursorLocationInView {
      let r=store.magneticSettings.width*scale
      c.setStrokeColor(NSColor.white.cgColor);c.setLineWidth(1);c.strokeEllipse(in:CGRect(x:point.x-r,y:point.y-r,width:r*2,height:r*2))
    }
  }
}