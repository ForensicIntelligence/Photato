import AppKit
import PhotoCraftCore

enum SelectionTransformMode:String,CaseIterable,Sendable {case free="Free Transform",scale="Scale",rotate="Rotate",skew="Skew",distort="Distort",perspective="Perspective"}
extension TransformDraft {
  var selectionCorners:[PathPoint] {selectionQuad ?? [PathPoint(Double(bounds.x),Double(bounds.y)),.init(Double(bounds.x+bounds.width),Double(bounds.y)),.init(Double(bounds.x+bounds.width),Double(bounds.y+bounds.height)),.init(Double(bounds.x),Double(bounds.y+bounds.height))]}
  var selectionProjection:ProjectiveTransform {get throws {
    let original:[PathPoint]=[.init(Double(bounds.x),Double(bounds.y)),.init(Double(bounds.x+bounds.width),Double(bounds.y)),.init(Double(bounds.x+bounds.width),Double(bounds.y+bounds.height)),.init(Double(bounds.x),Double(bounds.y+bounds.height))]
    if selectionCorners==original{return .identity}
    return try SelectionTransform.projection(bounds:bounds,corners:selectionCorners)
  }}
  var selectionReferencePoint:PathPoint {
    if let point = customReferencePoint, let mapped = try? selectionProjection.point(point.x, point.y) { return mapped }
    let q=selectionCorners
    switch referenceAnchor {case .topLeft:return q[0];case .topRight:return q[1];case .bottomRight:return q[2];case .bottomLeft:return q[3];default:break}
    let f=referenceAnchor.fractions;return (try? selectionProjection.point(Double(bounds.x)+Double(bounds.width)*f.0,Double(bounds.y)+Double(bounds.height)*f.1)) ?? .init(centerX,centerY)
  }
  func selectionApplying(_ matrix:Transform2D)->Self {
    var result=self;result.selectionQuad=selectionCorners.map{let p=matrix.point($0.x,$0.y);return .init(p.x,p.y)};return result
  }
  func selectionNumeric(_ key:WritableKeyPath<TransformDraft,Double>,_ value:Double)->Self {
    var next=self;let pivot=selectionReferencePoint,old=self[keyPath:key]
    if key == \.centerX {return selectionApplying(.translation(value-pivot.x,0))}
    if key == \.centerY {return selectionApplying(.translation(0,value-pivot.y))}
    var delta=Transform2D.identity
    if key == \.angle {delta = .rotation(value-old);next.angle=value}
    else if key == \.scaleX || key == \.scaleY {
      guard old != 0,value != 0 else{return self};let ratio=value/old,xy=key == \.scaleX
      let sx=xy || proportional ? ratio:1,sy = !xy || proportional ? ratio:1
      let q=selectionCorners,angle=atan2(q[1].y-q[0].y,q[1].x-q[0].x)*180 / .pi
      delta = .rotation(angle) * .scale(sx,sy) * .rotation(-angle)
      if xy {next.scaleX=value;if proportional{next.scaleY*=ratio}}else{next.scaleY=value;if proportional{next.scaleX*=ratio}}
    }else {next[keyPath:key]=value;return next}
    let matrix=Transform2D.translation(pivot.x,pivot.y)*delta * .translation(-pivot.x,-pivot.y)
    next.selectionQuad=selectionApplying(matrix).selectionQuad;return next
  }
  func selectionMode(handle:Int,modifiers:NSEvent.ModifierFlags)->SelectionTransformMode {
    if handle == 8{return .rotate};if handle == -1{return .free}
    let corner=handle%2==0
    if modifiers.contains([.command,.option,.shift]),corner{return .perspective}
    if modifiers.contains([.command,.shift]),!corner{return .skew}
    if modifiers.contains(.command){return .distort}
    if selectionMode == .perspective && !corner{return .scale}
    return selectionMode
  }
  func selectionDragging(handle:Int,from start:CGPoint,to end:CGPoint,mode:SelectionTransformMode,shift:Bool,option:Bool)->Self {
    let q=selectionCorners;var next=self,dx=Double(end.x-start.x),dy=Double(end.y-start.y)
    if handle == -1 {
      if shift {let length=hypot(dx,dy),angle=(atan2(dy,dx)/(.pi/4)).rounded()*(.pi/4);dx=cos(angle)*length;dy=sin(angle)*length}
      return selectionApplying(.translation(dx,dy))
    }
    let pivot=selectionReferencePoint
    if handle==8 || mode == .rotate {
      var degrees=(atan2(end.y-pivot.y,end.x-pivot.x)-atan2(start.y-pivot.y,start.x-pivot.x))*180 / .pi
      if shift {degrees=((angle+degrees)/15).rounded()*15-angle}
      next=selectionApplying(.translation(pivot.x,pivot.y) * .rotation(degrees) * .translation(-pivot.x,-pivot.y));next.angle=angle+degrees;return next
    }
    guard (0..<8).contains(handle) else{return self}
    let edge=handle/2,corner=handle%2==0,u=SIMD2(q[1].x-q[0].x,q[1].y-q[0].y),length=max(1e-9,hypot(u.x,u.y)),unit=u/length,v=SIMD2(-unit.y,unit.x),movement=SIMD2<Double>(dx,dy)
    func dot(_ a:SIMD2<Double>,_ b:SIMD2<Double>)->Double{a.x*b.x+a.y*b.y}
    func moving(_ indices:[Int],_ delta:SIMD2<Double>,_ points:inout [PathPoint]) {for i in indices{points[i].x+=delta.x;points[i].y+=delta.y}}
    var out=q
    if mode == .distort {
      if shift {if abs(dx)>=abs(dy){dy=0}else{dx=0}}
      let delta=SIMD2(dx,dy);moving(corner ? [edge]:[edge,(edge+1)%4],delta,&out)
      if option {moving(corner ? [(edge+2)%4]:[(edge+2)%4,(edge+3)%4],-delta,&out)}
    }else if mode == .skew {
      let horizontal=edge==0 || edge==2,basis=horizontal ? unit:v,delta=basis*dot(movement,basis)
      moving([edge,(edge+1)%4],delta,&out)
    }else if mode == .perspective {
      let horizontal=abs(dot(movement,unit))>=abs(dot(movement,v)),basis=horizontal ? unit:v
      let partner=horizontal ? [1,0,3,2][edge]:[3,2,1,0][edge],delta=basis*dot(movement,basis)
      moving([edge],delta,&out);moving([partner],-delta,&out)
    }else {
      let handles=self.handles,p=option ? CGPoint(x:pivot.x,y:pivot.y):handles[(handle+4)%8]
      let a=SIMD2<Double>(Double(start.x-p.x),Double(start.y-p.y)),b=SIMD2<Double>(Double(end.x-p.x),Double(end.y-p.y)),ax=dot(a,unit),ay=dot(a,v)
      var sx=abs(ax)>1e-9 ? dot(b,unit)/ax:1,sy=abs(ay)>1e-9 ? dot(b,v)/ay:1
      if !corner {if edge==0 || edge==2{sx=1}else{sy=1}}
      if proportional != shift {let factor = !corner ? (edge==0 || edge==2 ? sy:sx):abs(sx)>abs(sy) ? sx:sy;sx=factor;sy=factor}
      guard abs(sx)>1e-6,abs(sy)>1e-6 else{return self}
      let angle=atan2(unit.y,unit.x)*180 / .pi,matrix=Transform2D.translation(p.x,p.y) * .rotation(angle) * .scale(sx,sy) * .rotation(-angle) * .translation(-p.x,-p.y)
      next=selectionApplying(matrix);next.scaleX=scaleX*sx;next.scaleY=scaleY*sy;return next
    }
    next.selectionQuad=out;return next
  }
}
