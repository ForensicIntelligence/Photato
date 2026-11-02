import AppKit
import PhotoCraftCore
import SwiftUI

struct LightingPreview:NSViewRepresentable {
  @Bindable var model:LightingWorkspace
  func makeNSView(context:Context)->LightingPreviewView{LightingPreviewView(frame:.zero)}
  func updateNSView(_ view:LightingPreviewView,context:Context){view.model=model;view.needsDisplay=true;view.refreshToolCursor()}
}

@MainActor final class LightingPreviewView:ModifierCursorView {
  struct Handle:Equatable {var light:Int;var target:Bool=false;var direction:Bool=false}
  struct Drag {var handle:Handle;var original:LightingSettings.Light;var flags:NSEvent.ModifierFlags}
  var model:LightingWorkspace?
  var hovered:Handle?
  var dragging:Drag?
  override var isFlipped:Bool{true}
  override var acceptsFirstResponder:Bool{true}
  var imageRect:NSRect {
    guard let image=model?.originalImage ?? model?.image else{return bounds}
    let scale=min(bounds.width/CGFloat(image.width),bounds.height/CGFloat(image.height)),size=NSSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
    return NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
  }
  var handles:[Handle] {
    guard let model,model.originalImage != nil else{return []}
    let order=model.settings.lights.indices.sorted{a,b in if a==b{return false};if a==model.selected{return true};if b==model.selected{return false};return a<b}
    return order.flatMap{i->[Handle] in let l=model.settings.lights[i];return l.kind == .infinite ? [Handle(light:i,direction:true)]:[Handle(light:i)]+(l.kind == .spot ? [Handle(light:i,target:true)]:[])}
  }
  func point(_ handle:Handle)->NSPoint {
    guard let model,model.settings.lights.indices.contains(handle.light),let image=model.originalImage ?? model.image,let inverse=try? model.previewToDocument.inverted() else{return .zero}
    let l=model.settings.lights[handle.light],reference=model.reference,x:Double,y:Double
    if handle.direction{x=0.5+cos(l.angle*Double.pi/180)*0.35;y=0.5-sin(l.angle*Double.pi/180)*0.35}else{x=handle.target ? l.targetX:l.x;y=handle.target ? l.targetY:l.y}
    let q=inverse.point(Double(reference.x)+x*Double(reference.width),Double(reference.y)+y*Double(reference.height)),rect=imageRect
    return .init(x:rect.minX+CGFloat(q.x/Double(image.width))*rect.width,y:rect.minY+CGFloat(q.y/Double(image.height))*rect.height)
  }
  func hit(_ p:NSPoint)->Handle?{handles.map{($0,hypot(point($0).x-p.x,point($0).y-p.y))}.filter{$0.1<=12}.min{$0.1<$1.1}?.0}
  override var toolCursor:ToolCursor{ToolCursor.lighting(modifiers:dragging?.flags ?? cursorModifiers,hasHandle:dragging != nil || hovered != nil,canDuplicate:dragging != nil || model?.canAdd == true)}
  override func draw(_ dirtyRect:NSRect){
    guard let context=NSGraphicsContext.current?.cgContext else{return};context.saveGState();defer{context.restoreGState()};context.clip(to:bounds)
    NSColor(calibratedWhite:0.12,alpha:1).setFill();bounds.fill()
    guard let model else{return}
    if let image=model.preview ? model.image:model.originalImage{NSGraphicsContext.current?.imageInterpolation = .high;NSImage(cgImage:image,size:NSSize(width:CGFloat(image.width),height:CGFloat(image.height))).draw(in:imageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)}
    for handle in handles.reversed(){
      let l=model.settings.lights[handle.light],p=point(handle),color=handle.light==model.selected ? NSColor.systemCyan:NSColor.white.withAlphaComponent(l.enabled ? 0.8:0.35)
      if handle.target {
        let start=point(Handle(light:handle.light)),line=NSBezierPath();line.move(to:start);line.line(to:p);line.lineWidth=1;color.setStroke();line.stroke()
        let diamond=NSBezierPath();diamond.move(to:.init(x:p.x,y:p.y-6));diamond.line(to:.init(x:p.x+6,y:p.y));diamond.line(to:.init(x:p.x,y:p.y+6));diamond.line(to:.init(x:p.x-6,y:p.y));diamond.close();NSColor.black.setFill();diamond.fill();color.setStroke();diamond.lineWidth=2;diamond.stroke()
      }else{
        let circle=NSBezierPath(ovalIn:.init(x:p.x-7,y:p.y-7,width:14,height:14));NSColor.black.setFill();circle.fill();color.setStroke();circle.lineWidth=2;circle.stroke()
        ("\(handle.light+1)" as NSString).draw(at:.init(x:p.x+9,y:p.y-7),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.semibold),.foregroundColor:color])
      }
    }
  }
  override func mouseMoved(with event:NSEvent){hovered=hit(convert(event.locationInWindow,from:nil));super.mouseMoved(with:event)}
  override func mouseEntered(with event:NSEvent){hovered=hit(convert(event.locationInWindow,from:nil));super.mouseEntered(with:event)}
  override func mouseExited(with event:NSEvent){hovered=nil;super.mouseExited(with:event)}
  override func mouseDown(with event:NSEvent){
    guard let model,var handle=hit(convert(event.locationInWindow,from:nil)),!(event.modifierFlags.contains(.option) && !model.canAdd) else{updateCursorModifiers(event.modifierFlags);return}
    window?.makeFirstResponder(self);beginCursorGesture(event);model.beginGesture();model.select(handle.light)
    if event.modifierFlags.contains(.option),let index=model.duplicate(handle.light){handle.light=index}
    dragging=Drag(handle:handle,original:model.settings.lights[handle.light],flags:event.modifierFlags.intersection([.control,.command,.option,.shift]));refreshToolCursor();needsDisplay=true
  }
  override func mouseDragged(with event:NSEvent){
    guard let model,let drag=dragging,let image=model.originalImage ?? model.image else{return}
    let rect=imageRect,p=convert(event.locationInWindow,from:nil);guard rect.width>0,rect.height>0 else{return}
    let local=PathPoint(Double((p.x-rect.minX)/rect.width)*Double(image.width),Double((p.y-rect.minY)/rect.height)*Double(image.height)),q=model.previewToDocument.point(local.x,local.y),reference=model.reference
    var x=(q.x-Double(reference.x))/Double(reference.width),y=(q.y-Double(reference.y))/Double(reference.height),light=drag.original
    if drag.handle.direction{var angle=atan2(-(y-0.5),x-0.5)*180/Double.pi;if drag.flags.contains(.shift){angle=(angle/15).rounded()*15};light.angle=angle}
    else{
      let startX=drag.handle.target ? light.targetX:light.x,startY=drag.handle.target ? light.targetY:light.y
      if drag.flags.contains(.shift){if abs(x-startX)>=abs(y-startY){y=startY}else{x=startX}}
      if drag.handle.target{light.targetX=x;light.targetY=y}else{light.x=x;light.y=y}
    }
    model.selected=drag.handle.light;model.editLight(light);needsDisplay=true;refreshToolCursor()
  }
  override func mouseUp(with event:NSEvent){model?.endGesture();dragging=nil;hovered=hit(convert(event.locationInWindow,from:nil));endCursorGesture(event);needsDisplay=true}
  override func clearCursorInput(){if dragging != nil{model?.endGesture()};dragging=nil;hovered=nil;super.clearCursorInput()}
}
