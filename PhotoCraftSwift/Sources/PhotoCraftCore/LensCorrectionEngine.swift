import Foundation

public enum LensCorrectionEngine {
  public struct Sample: Sendable { public var green:PathPoint;public var red:PathPoint;public var blue:PathPoint;public var gain:Double }
  public struct Map: Sendable {
    let settings:LensCorrectionSettings
    let width:Int
    let height:Int
    let scale:Double
    let rotation:Double
    public init(_ settings:LensCorrectionSettings,width:Int,height:Int,scale:Double?=nil) {
      self.settings=settings;self.width=width;self.height=height;self.scale=(scale ?? settings.scale)/100
      rotation=(settings.angle+(settings.straighten.map { LensCorrectionEngine.straightenAngle($0[0],$0[1],width:width,height:height) } ?? 0)) * .pi/180
    }
    public func sample(x:Double,y:Double)->Sample? {
      let s=settings,p=s.resolvedProfile,cx=Double(width)/2,cy=Double(height)/2,r=max(2,hypot(Double(width),Double(height)))/2
      let dx=(x-cx)/scale,dy=(y-cy)/scale,c=cos(rotation),sn=sin(rotation)
      let nx=(c*dx+sn*dy)/r,ny=(-sn*dx+c*dy)/r,w=1+s.horizontal/200*nx+s.vertical/200*ny
      guard w>0.05 else { return nil };let ux=nx/w,uy=ny/w,r2=ux*ux+uy*uy
      let k1=(s.correctDistortion ? p.k1:0)-s.distortion/400,k2=s.correctDistortion ? p.k2:0,p1=s.correctDistortion ? p.p1:0,p2=s.correctDistortion ? p.p2:0
      let radial=1+k1*r2+k2*r2*r2,sx=ux*radial+2*p1*ux*uy+p2*(r2+2*ux*ux),sy=uy*radial+p1*(r2+2*uy*uy)+2*p2*ux*uy
      func point(_ k:Double)->PathPoint { .init(cx+sx*k*r,cy+sy*k*r) }
      let caR=(s.correctCA ? p.caRed:0)-s.redCyan*4e-5,caB=(s.correctCA ? p.caBlue:0)-s.blueYellow*4e-5
      let rs2=sx*sx+sy*sy,v=s.correctVignette ? p.vignette:[0,0,0],falloff=max(0.05,1+v[0]*rs2+v[1]*rs2*rs2+v[2]*rs2*rs2*rs2)
      // Adobe's documented midpoint direction: lower values affect more area.
      let start=s.vignetteMidpoint/100*0.9,t=min(1,max(0,(sqrt(rs2)-start)/(1-start))),ramp=t*t*(3-2*t)
      return Sample(green:point(1),red:point(1+caR),blue:point(1+caB),gain:pow(2,s.vignetteAmount/100*1.5*ramp)/falloff)
    }
  }
  public static func straightenAngle(_ a:PathPoint,_ b:PathPoint,width:Int,height:Int)->Double {
    let angle=atan2((b.y-a.y)*Double(height),(b.x-a.x)*Double(width))*180 / .pi
    return (angle/90).rounded()*90-angle
  }
  public static func resolvedScale(_ s:LensCorrectionSettings,width:Int,height:Int) throws -> Double {
    try s.validate();guard width>0,height>0 else { throw CraftError.invalid("Invalid lens image size.") }
    guard s.autoScale else { return s.scale }
    func covers(_ scale:Double) throws -> Bool {
      let map=Map(s,width:width,height:height,scale:scale)
      for i in 0...40 { try Task.checkCancellation();let t=Double(i)/40,x=0.5+t*Double(width-1),y=0.5+t*Double(height-1)
        for p in [PathPoint(x,0.5),PathPoint(x,Double(height)-0.5),PathPoint(0.5,y),PathPoint(Double(width)-0.5,y)] {
          guard let sample=map.sample(x:p.x,y:p.y) else { return false }
          for q in [sample.green,sample.red,sample.blue] { if q.x<0.5-1e-9 || q.y<0.5-1e-9 || q.x>Double(width)-0.5+1e-9 || q.y>Double(height)-0.5+1e-9 { return false } }
        }
      };return true
    }
    if try covers(s.scale) { return s.scale }
    var lo=s.scale,hi=s.scale
    while hi<800 { hi=min(800,hi*1.25);if try covers(hi) { break } }
    guard try covers(hi) else { throw CraftError.invalid("Auto Scale cannot cover this image within800%. Reduce the correction or choose an edge fill.") }
    for _ in 0..<30 { let mid=(lo+hi)/2;if try covers(mid) { hi=mid } else { lo=mid } };return hi
  }
  static func process(_ input:[SIMD4<Double>],width:Int,height:Int,settings s:LensCorrectionSettings) throws -> [SIMD4<Double>] {
    let scale=try resolvedScale(s,width:width,height:height);if s.isIdentity { return input }
    let map=Map(s,width:width,height:height,scale:scale)
    let color=s.edge == .white ? [1.0,1,1,1]:s.edge == .black ? [0.0,0,0,1]:s.edge == .color ? s.edgeColor:[0.0,0,0,0]
    let fill=SIMD4(color[0]*color[3],color[1]*color[3],color[2]*color[3],color[3])
    func cubic(_ t:Double)->[Double] { let t2=t*t,t3=t2*t;return [-0.5*t+t2-0.5*t3,1-2.5*t2+1.5*t3,0.5*t+2*t2-1.5*t3,-0.5*t2+0.5*t3] }
    func sample(_ p:PathPoint)->SIMD4<Double> {
      let x=min(Double(width-1),max(0,p.x-0.5)),y=min(Double(height-1),max(0,p.y-0.5)),ix=Int(floor(x)),iy=Int(floor(y)),wx=cubic(x-Double(ix)),wy=cubic(y-Double(iy))
      var value=SIMD4<Double>.zero
      for j in 0..<4 { for i in 0..<4 { value += input[min(height-1,max(0,iy+j-1))*width+min(width-1,max(0,ix+i-1))]*(wx[i]*wy[j]) } };value.w=min(1,max(0,value.w));return value
    }
    var result=[SIMD4<Double>](repeating:fill,count:input.count)
    for y in 0..<height { try Task.checkCancellation();for x in 0..<width {
      guard let s=map.sample(x:Double(x)+0.5,y:Double(y)+0.5) else { continue }
      let green=sample(s.green),red=sample(s.red),blue=sample(s.blue)
      let inside=settingsInside(s.green,width:width,height:height,extend:settingsEdgeExtends(map.settings))
      let edited=SIMD4(red.x*s.gain,green.y*s.gain,blue.z*s.gain,green.w)
      result[y*width+x]=edited*inside+fill*(1-inside)
    } };return result
  }
  private static func settingsEdgeExtends(_ s:LensCorrectionSettings)->Bool { s.edge == .edgeExtension }
  private static func settingsInside(_ p:PathPoint,width:Int,height:Int,extend:Bool)->Double {
    if extend { return 1 };return min(1,max(0,min(p.x,Double(width)-p.x)+0.5))*min(1,max(0,min(p.y,Double(height)-p.y)+0.5))
  }
}
