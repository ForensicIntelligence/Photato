import Foundation

/// Native translation of photocraft geom/warp.rs (MIT OR Apache-2.0).
public enum WarpStyle: String, Codable, CaseIterable, Sendable {
  case none, custom, arc, arcLower, arcUpper, arch, bulge, shellLower, shellUpper, flag, wave, fish, rise, fisheye, inflate, squeeze, twist
  public var title: String {
    switch self { case .arcLower: "Arc Lower"; case .arcUpper: "Arc Upper"; case .shellLower: "Shell Lower"; case .shellUpper: "Shell Upper"; default: rawValue.prefix(1).uppercased()+rawValue.dropFirst() }
  }
}
public struct WarpMesh: Codable, Equatable, Sendable {
  public var us: [Double], vs: [Double], points: [PathPoint]
  public var columns: Int { 3*(us.count-1)+1 }
  public var rows: Int { 3*(vs.count-1)+1 }
  public init(us: [Double], vs: [Double], points: [PathPoint]) { self.us=us;self.vs=vs;self.points=points }
  public func validate() throws {
    func valid(_ k:[Double]) -> Bool { (2...17).contains(k.count) && k.first == 0 && k.last == 1 && zip(k,k.dropFirst()).allSatisfy { $0.isFinite && $1.isFinite && $1-$0 >= 0.000001 } }
    guard valid(us),valid(vs),points.count == columns*rows,points.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}) else { throw CraftError.invalid("Warp needs ascending 0–1 knots, at most16 patches per axis, and a complete finite control grid.") }
  }
  private static func locate(_ knots:[Double],_ value:Double) -> (Int,Double) {
    let v=max(0,min(1,value));var i=0
    while i+2<knots.count && v>knots[i+1] { i += 1 }
    return (i,(v-knots[i])/(knots[i+1]-knots[i]))
  }
  public func point(_ s:Double,_ t:Double) -> PathPoint {
    let (i,a)=Self.locate(us,s),(j,b)=Self.locate(vs,t)
    func weights(_ t:Double)->[Double] { let u=1-t;return [u*u*u,3*t*u*u,3*t*t*u,t*t*t] }
    let wa=weights(a),wb=weights(b);var p=PathPoint(0,0)
    for y in 0..<4 { for x in 0..<4 { let q=points[(3*j+y)*columns+3*i+x],w=wa[x]*wb[y];p.x += q.x*w;p.y += q.y*w } };return p
  }
  public static func fit(columns:Int,rows:Int,map:(Double,Double)->PathPoint) throws -> Self {
    guard (1...16).contains(columns),(1...16).contains(rows) else { throw CraftError.invalid("Warp grid supports1–16 patches per axis.") }
    let us=(0...columns).map{Double($0)/Double(columns)},vs=(0...rows).map{Double($0)/Double(rows)},nx=3*columns+1
    let inv:[[Double]]=[[1,0,0,0],[-5.0/6,3,-1.5,1.0/3],[1.0/3,-1.5,3,-5.0/6],[0,0,0,1]]
    var points=[PathPoint](repeating:PathPoint(0,0),count:nx*(3*rows+1))
    for j in 0..<rows { for i in 0..<columns {
      var samples=[PathPoint]();for y in 0..<4 { for x in 0..<4 { samples.append(map(us[i]+(us[i+1]-us[i])*Double(x)/3,vs[j]+(vs[j+1]-vs[j])*Double(y)/3)) } }
      for y in 0..<4 { for x in 0..<4 { var p=PathPoint(0,0);for a in 0..<4 { for b in 0..<4 { let w=inv[y][a]*inv[x][b],q=samples[a*4+b];p.x += w*q.x;p.y += w*q.y } };points[(3*j+y)*nx+3*i+x]=p } }
    } };return Self(us:us,vs:vs,points:points)
  }
  private mutating func transpose() { let nx=columns,ny=rows,old=points;for j in 0..<ny { for i in 0..<nx { points[i*ny+j]=old[j*nx+i] } };let u=us;us=vs;vs=u }
  public mutating func split(at s:Double,vertical:Bool) throws {
    try validate();guard s.isFinite else { throw CraftError.invalid("Invalid split position.") }
    if !vertical { transpose() };defer { if !vertical { transpose() } }
    let (i,t)=Self.locate(us,s)
    guard us.count<17,(0.01...0.99).contains(t) else { throw CraftError.invalid("Split is too close to a boundary or the grid limit is reached.") }
    var next=[PathPoint]();let nx=columns,ny=rows
    for j in 0..<ny {
      let row=Array(points[j*nx..<(j+1)*nx]),k=i*3,p=Array(row[k...k+3])
      let a=p[0].interpolated(to:p[1],at:t),b=p[1].interpolated(to:p[2],at:t),c=p[2].interpolated(to:p[3],at:t)
      let d=a.interpolated(to:b,at:t),e=b.interpolated(to:c,at:t),f=d.interpolated(to:e,at:t)
      next += row[..<k];next += [p[0],a,d,f,e,c,p[3]];next += row[(k+4)...]
    };points=next;us.insert(s,at:i+1)
  }
  public mutating func removeSplit(index:Int,vertical:Bool) throws {
    try validate();if !vertical { transpose() };defer { if !vertical { transpose() } }
    guard index>0,index+1<us.count else { throw CraftError.invalid("Select an interior warp split.") }
    let t=(us[index]-us[index-1])/(us[index+1]-us[index-1]),nx=columns,ny=rows,k=3*(index-1);var next=[PathPoint]()
    for j in 0..<ny { let row=Array(points[j*nx..<(j+1)*nx]),p=row[k],q=row[k+6]
      let a=PathPoint((row[k+1].x-(1-t)*p.x)/t,(row[k+1].y-(1-t)*p.y)/t)
      let b=PathPoint((row[k+5].x-t*q.x)/(1-t),(row[k+5].y-t*q.y)/(1-t))
      next += row[..<k];next += [p,a,b,q];next += row[(k+7)...]
    };points=next;us.remove(at:index)
  }
}

/// Warp coordinates are in the unwarped layer's pixel space. Affine placement follows warp.
public struct WarpDefinition: Codable, Equatable, Sendable {
  public var style: WarpStyle = .none
  public var bend: Double = 0, horizontalDistortion: Double = 0, verticalDistortion: Double = 0
  public var vertical = false
  public var mesh: WarpMesh?
  public var interpolation: Resampling = .bicubic
  public init() {}
  public func validate() throws {
    guard [bend,horizontalDistortion,verticalDistortion].allSatisfy({$0.isFinite && (-100...100).contains($0)}) else { throw CraftError.invalid("Warp amounts must be between−100 and100.") }
    try mesh?.validate()
    guard (style == .custom) == (mesh != nil) else { throw CraftError.invalid("Custom Warp requires a mesh; presets cannot contain a mesh.") }
  }
  public var isIdentity: Bool { style == .none || (style != .custom && bend == 0 && horizontalDistortion == 0 && verticalDistortion == 0) }
  public func point(_ x:Double,_ y:Double,width:Double,height:Double) -> PathPoint {
    if style == .custom,let mesh { return mesh.point(x/width,y/height) }
    if style == .none { return PathPoint(x,y) }
    let hu=(vertical ? height:width)/2,hv=(vertical ? width:height)/2,aspect=hu/hv
    let u=(vertical ? y:x)/hu-1,v=(vertical ? x:y)/hv-1,b=bend/100,bell=max(0,1-u*u)
    var q=u,r=v
    func arc()->(Double,Double) { if abs(b)<1e-6 { return (u,v) };let theta=b*Double.pi/2,rad=aspect/theta;return ((rad-v)*sin(u*theta)/aspect,rad-(rad-v)*cos(u*theta)) }
    switch style {
    case .none,.custom: break
    case .arc: (q,r)=arc()
    case .arcLower,.arcUpper: let (a,c)=arc(),k=max(0,min(1,style == .arcLower ? (v+1)/2:(1-v)/2));q=u+(a-u)*k;r=v+(c-v)*k
    case .arch: r=v-b*bell
    case .bulge: r=v*(1+b*bell)
    case .shellLower: r=v+b*bell*(v+1)/2
    case .shellUpper: r=v-b*bell*(1-v)/2
    case .flag: r=v-b*0.5*sin(.pi*u)
    case .wave: r=v-b*0.5*sin(.pi*u+v * .pi/2)
    case .fish: r=v*(1+b*0.6*(1-u)*sqrt(bell))-b*0.35*bell
    case .rise: r=v-b*0.5*sin(.pi/2*u)
    case .fisheye: let k=1+b*(1-min(1,u*u+v*v));q=u*k;r=v*k
    case .inflate: q=u*(1+b*0.5*max(0,1-v*v));r=v*(1+b*0.5*bell)
    case .squeeze: q=u*(1+b*0.5*max(0,1-v*v));r=v*(1-b*0.5*bell)
    case .twist: let rad=hypot(u,v);if rad<1 { let a=b * .pi/2*pow(1-rad,2),xx=u*aspect;q=(xx*cos(a)-v*sin(a))/aspect;r=xx*sin(a)+v*cos(a) }
    }
    r *= max(0.05,1+horizontalDistortion/100*q);q *= max(0.05,1+verticalDistortion/100*r)
    return vertical ? PathPoint((r+1)*hv,(q+1)*hu):PathPoint((q+1)*hu,(r+1)*hv)
  }
  public func custom(width:Int,height:Int,columns:Int=1,rows:Int=1) throws -> Self {
    try validate();var value=self;value.mesh=try WarpMesh.fit(columns:columns,rows:rows) { s,t in point(s*Double(width),t*Double(height),width:Double(width),height:Double(height)) };value.style = .custom;return value
  }
}
