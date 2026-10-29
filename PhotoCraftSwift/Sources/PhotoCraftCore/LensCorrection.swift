import Foundation

/// Lens parameters follow the original PhotoCraft lens.rs model. Generic profiles
/// are estimates, not Adobe/manufacturer calibration data.
public struct LensCorrectionSettings: Codable, Equatable, Sendable {
  public enum Edge: String, Codable, CaseIterable, Sendable { case transparency, edgeExtension, black, white, color }
  public struct Profile: Codable, Equatable, Sendable {
    public var name = "Custom"
    public var k1 = 0.0
    public var k2 = 0.0
    public var p1 = 0.0
    public var p2 = 0.0
    public var vignette = [0.0,0.0,0.0]
    public var caRed = 0.0
    public var caBlue = 0.0
    public init() {}
    public static func generic(focalLength: Double) -> Self {
      let table:[[Double]] = [[12,-0.16,0.04,-0.60,0.15],[16,-0.11,0.025,-0.50,0.12],[24,-0.06,0.012,-0.38,0.08],[35,-0.025,0.004,-0.28,0.05],[50,0,0,-0.22,0.04],[85,0.012,0,-0.16,0.02],[200,0.02,0,-0.10,0.01]]
      let f = min(200,max(12,focalLength.isFinite ? focalLength:50))
      let i = (0..<6).first { f <= table[$0+1][0] } ?? 5,a=table[i],b=table[i+1]
      let t=(log(f)-log(a[0]))/(log(b[0])-log(a[0]))
      func mix(_ c:Int)->Double { a[c]+(b[c]-a[c])*t }
      var p=Self();p.name="Generic estimate (\(Int(f.rounded())) mm equivalent)";p.k1=mix(1);p.k2=mix(2);p.vignette=[mix(3),mix(4),0];return p
    }
  }
  public var profile: Profile?
  public var genericFocalLength: Double?
  public var resolvedProfile: Profile { profile ?? genericFocalLength.map { Profile.generic(focalLength:$0) } ?? Profile() }
  public var correctDistortion = true
  public var correctVignette = true
  public var correctCA = true
  public var distortion = 0.0
  public var redCyan = 0.0
  public var blueYellow = 0.0
  public var vignetteAmount = 0.0
  public var vignetteMidpoint = 50.0
  public var vertical = 0.0
  public var horizontal = 0.0
  public var angle = 0.0
  public var scale = 100.0
  public var autoScale = false
  public var edge: Edge = .transparency
  public var edgeColor = [0.0,0.0,0.0,1.0]
  /// Optional source-normalized line; its correction is added to angle.
  public var straighten: [PathPoint]?
  public init() {}
  public var isIdentity: Bool {
    let p=resolvedProfile
    return distortion == 0 && redCyan == 0 && blueYellow == 0 && vignetteAmount == 0 && vertical == 0 && horizontal == 0 && angle == 0 && scale == 100 && straighten == nil &&
      (!correctDistortion || (p.k1 == 0 && p.k2 == 0 && p.p1 == 0 && p.p2 == 0)) &&
      (!correctCA || (p.caRed == 0 && p.caBlue == 0)) && (!correctVignette || p.vignette.allSatisfy{$0 == 0})
  }
  public func validate() throws {
    func range(_ v:Double,_ r:ClosedRange<Double>) throws { guard v.isFinite,r.contains(v) else { throw CraftError.invalid("Lens Correction value is outside its supported range.") } }
    for v in [distortion,redCyan,blueYellow,vignetteAmount,vertical,horizontal] { try range(v,-100...100) }
    try range(vignetteMidpoint,0...100);try range(angle,-360...360);try range(scale,5...800)
    guard edgeColor.count == 4 else { throw CraftError.invalid("Edge color requires four RGBA values.") };for v in edgeColor { try range(v,0...1) }
    guard profile == nil || genericFocalLength == nil else { throw CraftError.invalid("Choose a custom profile or a generic focal estimate, not both.") }
    if let focal=genericFocalLength { try range(focal,12...200) }
    if let p=profile {
      guard !p.name.isEmpty,p.name.utf8.count<=256,p.vignette.count == 3 else { throw CraftError.invalid("Invalid lens profile.") }
      for v in [p.k1,p.k2,p.p1,p.p2]+p.vignette { try range(v,-4...4) };try range(p.caRed,-0.2...0.2);try range(p.caBlue,-0.2...0.2)
    }
    if let line=straighten {
      guard line.count == 2 else { throw CraftError.invalid("Straighten needs two source-normalized points.") }
      for p in line { try range(p.x,-4...5);try range(p.y,-4...5) }
      guard hypot(line[1].x-line[0].x,line[1].y-line[0].y)>1e-6 else { throw CraftError.invalid("Straighten points must be distinct.") }
    }
  }
  public static func decodeJSON(_ data:Data) throws -> Self {
    guard var values=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CraftError.invalid("Lens Correction requires an object.") }
    let encoder=JSONEncoder()
    var defaults=try JSONSerialization.jsonObject(with:encoder.encode(Self())) as! [String:Any]
    guard Set(values.keys).isSubset(of:Set(defaults.keys).union(["profile","straighten","genericFocalLength"])) else { throw CraftError.invalid("Unknown Lens Correction parameter.") }
    if let profile=values["profile"],!(profile is NSNull) {
      guard let p=profile as? [String:Any] else { throw CraftError.invalid("Invalid lens profile.") }
      var d=try JSONSerialization.jsonObject(with:encoder.encode(Profile())) as! [String:Any]
      guard Set(p.keys).isSubset(of:Set(d.keys)) else { throw CraftError.invalid("Unknown lens profile field.") };d.merge(p){_,new in new};values["profile"]=d
    }
    if let line=values["straighten"],!(line is NSNull) {
      guard let points=line as? [[String:Any]],points.allSatisfy({Set($0.keys)==["x","y"]}) else { throw CraftError.invalid("Invalid straighten points.") }
    }
    defaults.merge(values){_,new in new}
    let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:defaults));try result.validate();return result
  }
}
