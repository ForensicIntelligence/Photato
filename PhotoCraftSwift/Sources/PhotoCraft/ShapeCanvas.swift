import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension CraftCanvas {
  func beginShapeGesture(_ event:NSEvent,at point:CGPoint)->Bool{
    guard store.tool.shapeKind != nil,!spaceHeld else{return false};guard store.canDrawShapes else{return true}
    do{let definition=try store.currentShape();store.shapeGesture = .init(original:store.document,start:point,definition:definition,mode:store.shapeMode,target:store.activeLayer?.id,operation:store.shapeOperation,end:point)}catch{store.error=error.localizedDescription};needsDisplay=true;return true
  }
  func dragShapeGesture(_ event:NSEvent)->Bool{
    guard store.shapeGesture != nil else{return false};store.shapeGesture?.end=docPoint(event);store.shapeGesture?.square=event.modifierFlags.contains(.shift);store.shapeGesture?.center=event.modifierFlags.contains(.option);needsDisplay=true;return true
  }
  func endShapeGesture(_ event:NSEvent)->Bool{guard dragShapeGesture(event) else{return false};store.finishShapeGesture();needsDisplay=true;return true}
  func drawShapeGesture(in c:CGContext){
    guard let gesture=store.shapeGesture,let (definition,placement)=try? gesture.result(),let path=try? ShapeRenderer.outline(definition) else{return}
    let origin=viewPoint(.zero);let matrix=Transform2D.translation(origin.x,origin.y) * .scale(scale,scale) * placement
    var t=CGAffineTransform(a:matrix.a,b:matrix.b,c:matrix.c,d:matrix.d,tx:matrix.tx,ty:matrix.ty)
    guard let outline=path.copy(using:&t) else{return}
    c.saveGState();defer{c.restoreGState()};c.addPath(outline);c.setStrokeColor(NSColor.controlAccentColor.cgColor);c.setLineWidth(1.5)
    if definition.fill.kind == .solid{let p=definition.fill.color;c.setFillColor(NSColor(deviceRed:CGFloat(p.r),green:CGFloat(p.g),blue:CGFloat(p.b),alpha:CGFloat(p.a)*0.4).cgColor);c.drawPath(using:.fillStroke)}else{c.strokePath()}
  }
}
