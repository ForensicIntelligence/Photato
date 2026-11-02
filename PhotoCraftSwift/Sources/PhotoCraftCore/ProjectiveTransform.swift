import Foundation

/// Row-major homogeneous coordinates. Affine placement is the last row [0,0,1].
/// Imported matrices remain double precision; file values never pass through Float.
public final class ProjectiveTransform:Codable,Equatable,Sendable {
  public let values:[Double]
  public init(_ values:[Double])throws{self.values=values;try validate()}
  public init(_ affine:Transform2D){values=[affine.a,affine.c,affine.tx,affine.b,affine.d,affine.ty,0,0,1]}
  public static func ==(a:ProjectiveTransform,b:ProjectiveTransform)->Bool{a === b || a.values==b.values}
  public static var identity:Self{Self(Transform2D.identity)}
  public func validate()throws {
    guard values.count==9,values.allSatisfy({$0.isFinite}) else{throw CraftError.invalid("A projective matrix requires nine finite coefficients.")}
    let scale=values.map{abs($0)}.max() ?? 0
    guard scale>0 else{throw CraftError.invalid("A projective matrix is singular.")}
    let a=values.map{$0/scale}
    let terms=[a[0]*a[4]*a[8],a[1]*a[5]*a[6],a[2]*a[3]*a[7],-a[2]*a[4]*a[6],-a[1]*a[3]*a[8],-a[0]*a[5]*a[7]]
    let determinant=terms.reduce(0,+),magnitude=terms.reduce(0){$0+abs($1)}
    guard determinant.isFinite,abs(determinant)>max(Double.leastNormalMagnitude,magnitude*1e-12) else{throw CraftError.invalid("A projective matrix is singular or ill-conditioned.")}
  }
  private var normalized:[Double]{let scale=values.map{abs($0)}.max() ?? 1;return values.map{$0/scale}}

  public func point(_ x:Double,_ y:Double)throws->PathPoint {
    try validate();guard x.isFinite,y.isFinite else{throw CraftError.invalid("Invalid projective input point.")}
    let a=normalized,w=a[6]*x+a[7]*y+a[8],scale=abs(a[6]*x)+abs(a[7]*y)+abs(a[8])
    guard w.isFinite,abs(w)>max(Double.leastNormalMagnitude,scale*1e-12) else{throw CraftError.invalid("A projective mapping crosses infinity.")}
    let p=PathPoint((a[0]*x+a[1]*y+a[2])/w,(a[3]*x+a[4]*y+a[5])/w)
    guard p.x.isFinite,p.y.isFinite,abs(p.x)<=1_000_000,abs(p.y)<=1_000_000 else{throw CraftError.invalid("Projective output exceeds supported coordinates.")}
    return p
  }
  public func affineValue()throws->Transform2D? {
    try validate();guard values[6]==0,values[7]==0,values[8] != 0 else{return nil}
    let w=values[8],result=Transform2D(a:values[0]/w,b:values[3]/w,c:values[1]/w,d:values[4]/w,tx:values[2]/w,ty:values[5]/w)
    try result.validated();return result
  }
  public func inverted()throws->Self {
    try validate();let a=normalized
    let b=[a[4]*a[8]-a[5]*a[7],a[2]*a[7]-a[1]*a[8],a[1]*a[5]-a[2]*a[4],
      a[5]*a[6]-a[3]*a[8],a[0]*a[8]-a[2]*a[6],a[2]*a[3]-a[0]*a[5],
      a[3]*a[7]-a[4]*a[6],a[1]*a[6]-a[0]*a[7],a[0]*a[4]-a[1]*a[3]]
    // Homogeneous matrices are equivalent up to a nonzero scalar. Normalize
    // the adjugate instead of dividing by a potentially tiny determinant.
    let divisor=b.map{abs($0)}.max() ?? 0
    guard divisor.isFinite,divisor != 0 else{throw CraftError.invalid("Invalid projective inverse.")}
    return try Self(b.map{$0/divisor})
  }
  /// Applies this map, then an ordinary layer transform.
  public func followed(by affine:Transform2D)throws->Self {
    try validate();try affine.validated();let a=normalized
    return try Self([affine.a*a[0]+affine.c*a[3]+affine.tx*a[6],affine.a*a[1]+affine.c*a[4]+affine.tx*a[7],affine.a*a[2]+affine.c*a[5]+affine.tx*a[8],
      affine.b*a[0]+affine.d*a[3]+affine.ty*a[6],affine.b*a[1]+affine.d*a[4]+affine.ty*a[7],affine.b*a[2]+affine.d*a[5]+affine.ty*a[8],a[6],a[7],a[8]])
  }
  /// Applies this map, then another homogeneous map. No Float conversion.
  public func followed(by next:ProjectiveTransform)throws->Self {
    try validate();try next.validate();let a=normalized,b=next.normalized
    var output=[Double](repeating:0,count:9)
    for row in 0..<3 {for col in 0..<3 {for k in 0..<3 {output[row*3+col]+=b[row*3+k]*a[k*3+col]}}}
    return try Self(output)
  }
  /// Changes source coordinates before applying this projective placement.
  public func preceded(by affine:Transform2D)throws->Self {
    try validate();try affine.validated();let a=normalized
    return try Self([a[0]*affine.a+a[1]*affine.b,a[0]*affine.c+a[1]*affine.d,a[0]*affine.tx+a[1]*affine.ty+a[2],
      a[3]*affine.a+a[4]*affine.b,a[3]*affine.c+a[4]*affine.d,a[3]*affine.tx+a[4]*affine.ty+a[5],
      a[6]*affine.a+a[7]*affine.b,a[6]*affine.c+a[7]*affine.d,a[6]*affine.tx+a[7]*affine.ty+a[8]])
  }
  public func bounds(width:Int,height:Int)throws->IntRect {
    try validate();guard width>0,height>0,width<=Surface.maxDimension,height<=Surface.maxDimension else{throw CraftError.invalid("Invalid projective source extent.")}
    let corners=[PathPoint(0,0),.init(Double(width),0),.init(Double(width),Double(height)),.init(0,Double(height))]
    let a=normalized,ws=corners.map{a[6]*$0.x+a[7]*$0.y+a[8]},threshold=max(Double.leastNormalMagnitude,(ws.map{abs($0)}.max() ?? 1)*1e-12)
    guard ws.allSatisfy({$0>threshold}) || ws.allSatisfy({$0 < -threshold}) else{throw CraftError.invalid("A projective mapping crosses infinity inside the source.")}
    let points=try corners.map{try point($0.x,$0.y)}
    let x=floor(points.map(\.x).min()!+1e-9),y=floor(points.map(\.y).min()!+1e-9)
    let right=ceil(points.map(\.x).max()!-1e-9),bottom=ceil(points.map(\.y).max()!-1e-9)
    guard right>x,bottom>y,right-x<=Double(Surface.maxDimension),bottom-y<=Double(Surface.maxDimension),(right-x)*(bottom-y)<=Double(Surface.maxPixels) else{throw CraftError.invalid("Projective output exceeds the supported extent.")}
    return .init(x:Int(x),y:Int(y),width:Int(right-x),height:Int(bottom-y))
  }
}
