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

  func validateSharedHorizon(left: Int, top: Int, right: Int, bottom: Int) throws {
    let a = normalized
    let weights = [(left, top), (right, top), (right, bottom), (left, bottom)].map {
      a[6] * Double($0.0) + a[7] * Double($0.1) + a[8]
    }
    let threshold = max(Double.leastNormalMagnitude, (weights.map(abs).max() ?? 1) * 1e-12)
    guard weights.allSatisfy({ $0 > threshold }) || weights.allSatisfy({ $0 < -threshold }) else {
      throw CraftError.invalid("The projective horizon crosses the shared transform bounds.")
    }
  }

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
  /// Bounds local document pixels per source pixel for vector rerasterization.
  /// Within each cell the Jacobian numerator is affine and its spectral norm
  /// is convex. Its largest corner norm over the smallest squared homogeneous
  /// weight bounds the whole cell, including the strongly enlarged edge.
  public func maximumMagnification(width: Int, height: Int) throws -> Double {
    _ = try bounds(width: width, height: height)
    let m = normalized
    func corner(_ x: Double, _ y: Double) -> (weight: Double, norm: Double) {
      let w = m[6] * x + m[7] * y + m[8]
      let u = m[0] * x + m[1] * y + m[2], v = m[3] * x + m[4] * y + m[5]
      let ux = m[0] * w - m[6] * u, vx = m[3] * w - m[6] * v
      let uy = m[1] * w - m[7] * u, vy = m[4] * w - m[7] * v
      let aa = ux * ux + vx * vx, bb = uy * uy + vy * vy, ab = ux * uy + vx * vy
      return (abs(w), sqrt((aa + bb + hypot(aa - bb, 2 * ab)) / 2))
    }
    if m[6] == 0, m[7] == 0 {
      let sample = corner(0, 0)
      return sample.norm / (sample.weight * sample.weight)
    }
    let divisions = 16
    let grid = (0...divisions).map { y in
      (0...divisions).map { x in
        corner(Double(x * width) / Double(divisions), Double(y * height) / Double(divisions))
      }
    }
    var maximum = 0.0
    for y in 0..<divisions {
      try Task.checkCancellation()
      for x in 0..<divisions {
        let a = grid[y][x], b = grid[y][x + 1], c = grid[y + 1][x], d = grid[y + 1][x + 1]
        let weight = min(a.weight, b.weight, c.weight, d.weight)
        maximum = max(maximum, max(a.norm, b.norm, c.norm, d.norm) / (weight * weight))
      }
    }
    return maximum
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
