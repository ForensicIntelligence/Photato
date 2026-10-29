import Foundation

public struct WideAngleSettings:Codable,Equatable,Sendable {
  public enum Model:String,Codable,CaseIterable,Sendable { case auto,fisheye,perspective,panorama,fullSpherical
    public var title:String { switch self { case .auto:"Auto";case .fisheye:"Fisheye";case .perspective:"Perspective";case .panorama:"Panorama";case .fullSpherical:"Full Spherical" } }
  }
  public enum Orientation:String,Codable,CaseIterable,Sendable { case free,horizontal,vertical,angle }
  public struct Constraint:Codable,Equatable,Sendable {
    public var points:[PathPoint]
    public var closed=false
    public var orientations:[Orientation]=[]
    public var angles:[Double]=[]
    public init(points:[PathPoint],closed:Bool=false) { self.points=points;self.closed=closed }
    public var segmentCount:Int { max(0,points.count-1)+(closed ? 1:0) }
    public func orientation(_ index:Int)->Orientation { orientations.isEmpty ? .free:orientations[index] }
    public func angle(_ index:Int)->Double { angles.isEmpty ? 0:angles[index] }
    public mutating func setOrientation(_ value:Orientation,angle:Double=0,at index:Int) {
      guard (0..<segmentCount).contains(index) else { return }
      if orientations.isEmpty { orientations=Array(repeating:.free,count:segmentCount) };if angles.isEmpty { angles=Array(repeating:0,count:segmentCount) }
      orientations[index]=value;angles[index]=angle
    }
  }
  public var model:Model = .auto
  public var focalLength=0.0
  public var cropFactor=1.0
  public var scale=100.0
  public var constraints:[Constraint]=[]
  public var interpolation:Resampling = .bicubic
  public init() {}
  public var isIdentity:Bool { constraints.isEmpty && scale == 100 }
  public func validate() throws {
    guard focalLength.isFinite,(0...200).contains(focalLength),cropFactor.isFinite,(0.1...10).contains(cropFactor),scale.isFinite,(5...400).contains(scale),constraints.count<=64,constraints.reduce(0,{$0+$1.segmentCount})<=128 else { throw CraftError.invalid("Invalid Adaptive Wide Angle parameters or constraint count.") }
    for c in constraints {
      guard (c.closed ? 3:2)...32 ~= c.points.count,c.points.allSatisfy({$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)}),c.orientations.isEmpty || c.orientations.count == c.segmentCount,c.angles.isEmpty || c.angles.count == c.segmentCount,c.angles.allSatisfy({$0.isFinite && (-360...360).contains($0)}) else { throw CraftError.invalid("Invalid wide-angle line or polygon.") }
      for i in 0..<c.segmentCount { let a=c.points[i],b=c.points[(i+1)%c.points.count];guard hypot(a.x-b.x,a.y-b.y)>1e-6 else { throw CraftError.invalid("Constraint endpoints must be distinct.") } }
    }
  }
  public static func decodeJSON(_ data:Data) throws -> Self {
    guard var values=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CraftError.invalid("Wide Angle requires an object.") }
    var defaults=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    guard Set(values.keys).isSubset(of:Set(defaults.keys)) else { throw CraftError.invalid("Unknown Wide Angle parameter.") }
    if let raw=values["constraints"] {
      guard let constraints=raw as? [[String:Any]] else { throw CraftError.invalid("Invalid constraints.") }
      values["constraints"]=try constraints.map { c -> [String:Any] in
        guard Set(c.keys).isSubset(of:["points","closed","orientations","angles"]),let points=c["points"] as? [[String:Any]],points.allSatisfy({Set($0.keys)==["x","y"]}) else { throw CraftError.invalid("Invalid constraint fields.") }
        var d:[String:Any]=["closed":false,"orientations":[],"angles":[]];d.merge(c){_,new in new};return d
      }
    }
    defaults.merge(values){_,new in new};let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:defaults));try result.validate();return result
  }
}

/// Projection models translated from algo/wideangle.rs, plus a cylindrical panorama.
public struct WideAngleCamera:Sendable {
  public let model:WideAngleSettings.Model
  public let focal:Double
  public let width:Double
  public let height:Double
  public init(_ p:WideAngleSettings,width:Int,height:Int) {
    self.width=Double(width);self.height=Double(height);let equivalent=p.focalLength*p.cropFactor
    model=p.model == .auto ? (abs(Double(width)/Double(height)-2)<0.01 ? .fullSpherical:equivalent>0 && equivalent<17 ? .fisheye:.perspective):p.model
    let mm=equivalent>0 ? equivalent:model == .fisheye ? 12:24
    focal=mm/36*Double(max(width,height))
  }
  private func unit(_ v:SIMD3<Double>)->SIMD3<Double> { v/max(1e-300,sqrt(v.x*v.x+v.y*v.y+v.z*v.z)) }
  public func ray(_ p:PathPoint)->SIMD3<Double> {
    let dx=p.x-width/2,dy=p.y-height/2
    switch model {
    case .fullSpherical:
      let lon=dx/width*2 * .pi,lat=dy/height * .pi;return .init(sin(lon)*cos(lat),sin(lat),cos(lon)*cos(lat))
    case .panorama:
      let lon=dx/focal;return unit(.init(sin(lon),dy/focal,cos(lon)))
    case .fisheye:
      let r=hypot(dx,dy),a=r/focal;return r<1e-12 ? .init(0,0,1):.init(sin(a)*dx/r,sin(a)*dy/r,cos(a))
    default:return unit(.init(dx,dy,focal))
    }
  }
  public func pixel(_ v:SIMD3<Double>)->PathPoint? {
    switch model {
    case .fullSpherical:return .init(width/2+atan2(v.x,v.z)/(.pi*2)*width,height/2+asin(min(1,max(-1,v.y)))/(.pi)*height)
    case .panorama:
      let r=hypot(v.x,v.z);guard r>1e-8 else { return nil };return .init(width/2+focal*atan2(v.x,v.z),height/2+focal*v.y/r)
    case .fisheye:
      let a=acos(min(1,max(-1,v.z))),r=hypot(v.x,v.y);return r<1e-12 ? .init(width/2,height/2):.init(width/2+focal*a*v.x/r,height/2+focal*a*v.y/r)
    default:guard v.z>1e-8 else { return nil };return .init(width/2+focal*v.x/v.z,height/2+focal*v.y/v.z)
    }
  }
  public func arc(_ a:PathPoint,_ b:PathPoint,samples:Int=24) throws -> [PathPoint] {
    let ra=ray(a),rb=ray(b),cosine=min(1,max(-1,ra.x*rb.x+ra.y*rb.y+ra.z*rb.z)),omega=acos(cosine)
    guard omega < .pi-1e-5 else { throw CraftError.invalid("Constraint crosses opposite camera rays; split it into shorter segments.") }
    var points=[PathPoint]()
    for i in 0...samples {
      let t=Double(i)/Double(samples),v=omega<1e-9 ? ra:unit(ra*(sin((1-t)*omega)/sin(omega))+rb*(sin(t*omega)/sin(omega)))
      guard var p=pixel(v),p.x.isFinite,p.y.isFinite else { throw CraftError.invalid("Constraint crosses the projection horizon; split it into shorter segments.") }
      if model == .fullSpherical || model == .panorama {
        let period=model == .fullSpherical ? width:2 * .pi*focal,expected=a.x+(b.x-a.x)*t;p.x += ((expected-p.x)/period).rounded()*period
      }
      points.append(p)
    };return points
  }
}
