import AppKit
import PhotoCraftCore
import SwiftUI

@MainActor extension BlurGalleryWorkspace {
  enum HandleKind { case center,radiusX,radiusY,angle,feather,focus,transition,pathPoint }
  struct Handle { let index:Int,pointIndex:Int,kind:HandleKind,point:PathPoint }
  var handles:[Handle] {
    if mode == .path { return settings.paths.enumerated().flatMap { i,p in p.points.enumerated().map { j,point in Handle(index:i,pointIndex:j,kind:.pathPoint,point:point) } } }
    let w=sourceSize.width,h=sourceSize.height,ss=min(w,h)
    return pins.enumerated().flatMap { i,p -> [Handle] in
      var result=[Handle(index:i,pointIndex:0,kind:.center,point:.init(p.x,p.y))]
      func add(_ kind:HandleKind,_ dx:Double,_ dy:Double) { result.append(.init(index:i,pointIndex:0,kind:kind,point:.init(p.x+dx/w,p.y+dy/h))) }
      let a=p.angle * .pi/180,c=cos(a),s=sin(a)
      if mode == .iris || mode == .spin {
        add(.radiusX,p.radiusX*ss*c,p.radiusX*ss*s);add(.radiusY,-p.radiusY*ss*s,p.radiusY*ss*c)
        add(.angle,(p.radiusX+0.08)*ss*c,(p.radiusX+0.08)*ss*s)
        add(.feather,p.radiusX*p.feather*ss*c,p.radiusX*p.feather*ss*s)
      } else if mode == .tiltShift {
        add(.focus,p.focus*ss*s,p.focus*ss*c);add(.transition,(p.focus+p.transition)*ss*s,(p.focus+p.transition)*ss*c)
        add(.angle,0.35*ss*c,-0.35*ss*s)
      }
      return result
    }
  }
  func move(_ handle:Handle,to q:PathPoint) {
    selected=handle.index;selectedPoint=handle.pointIndex
    if handle.kind == .pathPoint { updatePath { p in if p.points.indices.contains(handle.pointIndex) { p.points[handle.pointIndex]=q } };return }
    guard let p=pin else { return }
    let dx=(q.x-p.x)*sourceSize.width,dy=(q.y-p.y)*sourceSize.height,ss=min(sourceSize.width,sourceSize.height),a=p.angle * .pi/180,u=dx*cos(a)+dy*sin(a),v = -dx*sin(a)+dy*cos(a)
    updatePin { value in
      switch handle.kind {
      case .center:value.x=max(-4,min(5,q.x));value.y=max(-4,min(5,q.y))
      case .radiusX:value.radiusX=max(0.001,min(8,abs(u)/ss))
      case .radiusY:value.radiusY=max(0.001,min(8,abs(v)/ss))
      case .angle:value.angle=atan2(mode == .tiltShift ? -dy:dy,dx)*180 / .pi
      case .feather:value.feather=max(0,min(0.999,abs(u)/(value.radiusX*ss)))
      case .focus:value.focus=min(2,abs(dx*sin(a)+dy*cos(a))/ss)
      case .transition:value.transition=max(0.001,min(2,abs(dx*sin(a)+dy*cos(a))/ss-value.focus))
      case .pathPoint:break
      }
    }
  }
}
struct BlurGalleryPreview:View {
  @Bindable var model:BlurGalleryWorkspace
  @State private var drag:BlurGalleryWorkspace.Handle?
  @State private var pressed=false
  var body:some View {
    GeometryReader { geometry in
      let scale=min((geometry.size.width-40)/model.documentSize.width,(geometry.size.height-40)/model.documentSize.height)*model.zoom
      let offset=CGPoint(x:(geometry.size.width-model.documentSize.width*scale)/2,y:(geometry.size.height-model.documentSize.height*scale)/2)
      let transform=model.sourceTransform,sourceSize=model.sourceSize,inverse=(try? model.sourceTransform.inverted()) ?? .identity
      Canvas { context,size in
        func position(_ p:PathPoint)->CGPoint { let q=p.transformed(.scale(sourceSize.width,sourceSize.height)).transformed(transform);return CGPoint(x:offset.x+q.x*scale,y:offset.y+q.y*scale) }
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(white:0.13)))
        if let image=model.showMask ? model.maskImage:(model.preview ? model.image:model.originalImage) { context.draw(Image(decorative:image,scale:1),in:CGRect(x:offset.x,y:offset.y,width:model.documentSize.width*scale,height:model.documentSize.height*scale)) }
        if model.showControls {
          let ss=min(model.sourceSize.width,model.sourceSize.height),w=model.sourceSize.width,h=model.sourceSize.height
          for (i,p) in model.pins.enumerated() {
            var outline=Path();let a=p.angle * .pi/180,c=cos(a),s=sin(a)
            func local(_ x:Double,_ y:Double)->CGPoint { position(.init(p.x+(x*c-y*s)/w,p.y+(x*s+y*c)/h)) }
            if model.mode == .iris || model.mode == .spin {
              for factor in [1.0,p.feather] {
                for j in 0...64 { let t=Double(j)*2 * .pi/64,exponent=2/(2+p.roundness*0.06),co=cos(t),si=sin(t),point=local((co<0 ? -1:1)*pow(abs(co),exponent)*p.radiusX*ss*factor,(si<0 ? -1:1)*pow(abs(si),exponent)*p.radiusY*ss*factor);if j==0 { outline.move(to:point) } else { outline.addLine(to:point) } }
              }
            } else if model.mode == .tiltShift {
              for dist in [-p.focus-p.transition,-p.focus,p.focus,p.focus+p.transition] {
                let dx=dist*ss*s,dy=dist*ss*c
                outline.move(to:position(.init(p.x+(dx-w*c)/w,p.y+(dy+w*s)/h)))
                outline.addLine(to:position(.init(p.x+(dx+w*c)/w,p.y+(dy-w*s)/h)))
              }
            }
            context.stroke(outline,with:.color(i==model.selected ? .cyan:.white.opacity(0.7)),lineWidth:1)
          }
          if model.mode == .path {
            for (i,path) in model.settings.paths.enumerated() { var line=Path();for (j,p) in BlurGalleryEngine.pathPoints(path).enumerated() { if j==0 { line.move(to:position(p)) } else { line.addLine(to:position(p)) } };context.stroke(line,with:.color(i==model.selected ? .cyan:.white),lineWidth:2) }
          }
          for handle in model.handles {
            let p=position(handle.point),r=handle.kind == .center ? 5.0:4.0,rect=CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)
            context.fill(handle.kind == .center || handle.kind == .pathPoint ? Path(ellipseIn:rect):Path(rect),with:.color(handle.index==model.selected ? .orange:.white))
          }
        }
      }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
        func normalized(_ p:CGPoint)->PathPoint { let q=PathPoint((p.x-offset.x)/scale,(p.y-offset.y)/scale).transformed(inverse);return .init(q.x/sourceSize.width,q.y/sourceSize.height) }
        if !pressed {
          pressed=true
          let q=normalized(value.startLocation);var nearest=12.0
          for handle in model.handles { let a=model.point(handle.point),b=model.point(q),distance=hypot(a.x-b.x,a.y-b.y)*scale;if distance<nearest { nearest=distance;drag=handle } }
          model.beginGesture()
          if let drag { model.selected=drag.index;model.selectedPoint=drag.pointIndex }
          else { model.add(at:q);drag=model.handles.first { $0.index==model.selected && ($0.kind == .center || $0.kind == .pathPoint && $0.pointIndex==model.selectedPoint) } }
        }
        if let drag { model.move(drag,to:normalized(value.location)) }
      }.onEnded { _ in model.endGesture();drag=nil;pressed=false })
      .accessibilityLabel("Blur Gallery image. Drag pins and handles. Use the adjacent controls for exact values.")
    }
  }
}
