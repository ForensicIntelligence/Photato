import AppKit
import PhotoCraftCore
import SwiftUI

/// Filter-input points pass through the correction, layer placement and view frame.
struct WideAngleCoordinates {
  var mesh:WideAngleMesh?
  var transform:Transform2D
  var sourceSize:CGSize
  var scale:Double
  var offset:CGPoint
  func screen(_ source:PathPoint,normalized:Bool=true)->CGPoint {
    let p=normalized ? PathPoint(source.x*sourceSize.width,source.y*sourceSize.height):source
    let q=(mesh?.point(p) ?? p).transformed(transform)
    return .init(x:offset.x+q.x*scale,y:offset.y+q.y*scale)
  }
  func source(_ screen:CGPoint)->PathPoint? {
    guard let inverse=try? transform.inverted(),scale>0 else { return nil }
    let p=PathPoint((screen.x-offset.x)/scale,(screen.y-offset.y)/scale).transformed(inverse)
    let q:PathPoint
    if let mesh { guard let input=mesh.input(at:p) else { return nil };q=input } else { q=p }
    guard (0...sourceSize.width).contains(q.x),(0...sourceSize.height).contains(q.y) else { return nil }
    return .init(q.x/sourceSize.width,q.y/sourceSize.height)
  }
  static func distance(_ p:CGPoint,_ a:CGPoint,_ b:CGPoint)->Double {
    let dx=b.x-a.x,dy=b.y-a.y,t=max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/max(1e-12,dx*dx+dy*dy)))
    return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
  }
}

struct WideAnglePreview:View {
  @Bindable var model:WideAngleWorkspace
  @State private var pressed=false
  @State private var initialPan=CGSize.zero
  @State private var frozen:WideAngleCoordinates?
  @State private var hitConstraint:Int?
  @State private var hitPoint:Int?
  @State private var start:PathPoint?
  @State private var end:PathPoint?
  var body:some View {
    GeometryReader { geometry in
      let scale=max(0.001,min((geometry.size.width-32)/model.documentSize.width,(geometry.size.height-32)/model.documentSize.height)*model.zoom)
      let offset=CGPoint(x:(geometry.size.width-model.documentSize.width*scale)/2+model.pan.width,y:(geometry.size.height-model.documentSize.height*scale)/2+model.pan.height)
      let coordinates=WideAngleCoordinates(mesh:model.preview ? model.mesh:nil,transform:model.sourceTransform,sourceSize:model.sourceSize,scale:scale,offset:offset)
      Canvas { context,size in
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        if let image=model.preview ? model.image:model.originalImage { context.draw(Image(decorative:image,scale:1),in:CGRect(x:offset.x,y:offset.y,width:model.documentSize.width*scale,height:model.documentSize.height*scale)) }
        if model.showMesh,let mesh=model.mesh {
          var path=Path()
          for j in 0...mesh.rows { for i in 0...mesh.columns { let p=coordinates.screen(mesh.inputs[j*(mesh.columns+1)+i],normalized:false);if i==0 { path.move(to:p) } else { path.addLine(to:p) } } }
          for i in 0...mesh.columns { for j in 0...mesh.rows { let p=coordinates.screen(mesh.inputs[j*(mesh.columns+1)+i],normalized:false);if j==0 { path.move(to:p) } else { path.addLine(to:p) } } }
          context.stroke(path,with:.color(.white.opacity(0.3)),lineWidth:0.5)
        }
        if model.showConstraints,let mesh=model.mesh {
          for (i,curve) in mesh.curves.enumerated() {
            let ref=mesh.references[i],selected=ref.constraint==model.selected && ref.segment==model.selectedSegment
            var path=Path();for (j,p) in curve.enumerated() { let q=coordinates.screen(p,normalized:false);if j==0 { path.move(to:q) } else { path.addLine(to:q) } }
            context.stroke(path,with:.color(selected ? .orange:.cyan),lineWidth:selected ? 2.5:1.5)
          }
          for (i,c) in model.settings.constraints.enumerated() { for p in c.points { let q=coordinates.screen(p),rect=CGRect(x:q.x-4,y:q.y-4,width:8,height:8);context.fill(Path(ellipseIn:rect),with:.color(i==model.selected ? .orange:.cyan)) } }
        }
        let pending=model.polygon.isEmpty ? [start,end].compactMap{$0}:model.polygon
        if !pending.isEmpty {
          var line=Path();for (i,p) in pending.enumerated() { let q=coordinates.screen(p);if i==0 { line.move(to:q) } else { line.addLine(to:q) };context.fill(Path(ellipseIn:CGRect(x:q.x-3,y:q.y-3,width:6,height:6)),with:.color(.yellow)) }
          context.stroke(line,with:.color(.yellow),lineWidth:2)
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        if !pressed {
          pressed=true;initialPan=model.pan;frozen=coordinates;hitConstraint=nil;hitPoint=nil;start=coordinates.source(value.startLocation);end=start;model.beginGesture()
          if model.tool == .constraint && model.showConstraints {
            var best=10.0
            for (i,c) in model.settings.constraints.enumerated() { for (j,p) in c.points.enumerated() { let q=coordinates.screen(p),d=hypot(q.x-value.startLocation.x,q.y-value.startLocation.y);if d<best { best=d;hitConstraint=i;hitPoint=j } } }
            if hitPoint==nil,let mesh=model.mesh { for (i,curve) in mesh.curves.enumerated() { for j in 1..<curve.count { let d=WideAngleCoordinates.distance(value.startLocation,coordinates.screen(curve[j-1],normalized:false),coordinates.screen(curve[j],normalized:false));if d<best { best=d;hitConstraint=mesh.references[i].constraint;model.selectedSegment=mesh.references[i].segment } } } }
            if let hitConstraint { model.selected=hitConstraint;if let hitPoint { model.selectedPoint=hitPoint } }
          }
        }
        if model.tool == .hand { model.pan=CGSize(width:initialPan.width+value.translation.width,height:initialPan.height+value.translation.height);return }
        guard let point=frozen?.source(value.location) else { return };end=point
        if model.tool == .constraint,let hitConstraint {
          if let hitPoint { model.movePoint(constraint:hitConstraint,point:hitPoint,to:point) }
          else if let start { model.moveConstraint(hitConstraint,dx:point.x-start.x,dy:point.y-start.y) }
        }
      }.onEnded { _ in
        if model.tool == .polygon,let end { model.addPolygonPoint(end) }
        else if model.tool == .constraint,hitConstraint==nil,let start,let end { model.addLine(start,end,axis:NSEvent.modifierFlags.contains(.shift)) }
        model.endGesture();pressed=false;frozen=nil;start=nil;end=nil;hitPoint=nil;hitConstraint=nil
      }).clipped().accessibilityLabel("Adaptive Wide Angle preview. Drag a constraint along an edge, or use Polygon Constraint to mark its corners.")
    }
  }
}
