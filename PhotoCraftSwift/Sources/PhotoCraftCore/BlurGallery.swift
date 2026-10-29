import Foundation

/// Native Blur Gallery geometry is normalized to the filter's source image.
public struct BlurGallerySettings: Codable, Equatable, Sendable {
  public enum Mode: String, Codable, CaseIterable, Sendable { case field, iris, tiltShift, path, spin
    public var title: String { switch self { case .field: "Field Blur"; case .iris: "Iris Blur"; case .tiltShift: "Tilt-Shift"; case .path: "Path Blur"; case .spin: "Spin Blur" } }
  }
  public struct Pin: Codable, Equatable, Sendable {
    public var x = 0.5, y = 0.5, blur = 15.0
    public var radiusX = 0.35, radiusY = 0.25, angle = 0.0, feather = 0.5, roundness = 0.0
    public var focus = 0.1, transition = 0.15, blurAngle = 15.0
    public init() {}
  }
  public struct MotionPath: Codable, Equatable, Sendable {
    public var points: [PathPoint] = [.init(0.2,0.5), .init(0.8,0.5)]
    public var speed = 50.0, taper = 0.0
    public var curved = true
    public var centered = true
    public init() {}
  }
  public enum Noise: String, Codable, CaseIterable, Sendable { case uniform, gaussian, grain }
  public var enabled: [Mode] = [.field]
  public var field: [Pin] = [.init()], iris: [Pin] = [.init()], tiltShift: [Pin] = [.init()]
  public var spin: [Pin] = { var p=Pin();p.radiusX=0.3;p.radiusY=0.3;p.feather=0.85;return [p] }()
  public var paths: [MotionPath] = [.init()]
  public var lightBokeh = 0.0, bokehColor = 0.0, lightMin = 0.75, lightMax = 1.0
  public var noise: Noise = .uniform
  public var noiseAmount = 0.0, noiseSize = 1.0, noiseRoughness = 50.0, noiseColor = 0.0, noiseHighlights = 0.0
  public var seed: UInt32 = 1
  public var strobeStrength = 0.0, strobeFlashes = 4, strobeDuration = 10.0
  public init() {}
  public func pins(_ mode: Mode) -> [Pin] { switch mode { case .field: field; case .iris: iris; case .tiltShift: tiltShift; case .spin: spin; case .path: [] } }
  public mutating func setPins(_ value: [Pin], for mode: Mode) { switch mode { case .field: field = value; case .iris: iris = value; case .tiltShift: tiltShift = value; case .spin: spin = value; case .path: break } }
  public func validate() throws {
    func range(_ x: Double, _ bounds: ClosedRange<Double>) throws { guard x.isFinite, bounds.contains(x) else { throw CraftError.invalid("Blur Gallery parameter is out of range.") } }
    guard enabled.count <= 5, Set(enabled).count == enabled.count, paths.count <= 16, (1...30).contains(strobeFlashes) else { throw CraftError.invalid("Too many Blur Gallery effects or paths.") }
    for mode in Mode.allCases {
      let pins = pins(mode); guard pins.count <= 64 else { throw CraftError.invalid("Use at most64 pins per blur tool.") }
      for p in pins {
        try range(p.x,-4...5); try range(p.y,-4...5); try range(p.blur,0...500)
        try range(p.radiusX,0.001...8); try range(p.radiusY,0.001...8); try range(p.angle,-360...360)
        try range(p.feather,0...0.999); try range(p.roundness,0...100); try range(p.focus,0...2); try range(p.transition,0.001...2); try range(p.blurAngle,0...360)
      }
    }
    for p in paths {
      guard (2...32).contains(p.points.count) else { throw CraftError.invalid("Each blur path requires2–32 control points.") }
      for point in p.points { try range(point.x,-4...5); try range(point.y,-4...5) }
      try range(p.speed,0...500); try range(p.taper,0...100)
    }
    for x in [lightBokeh,bokehColor,noiseAmount,noiseRoughness,noiseColor,noiseHighlights,strobeStrength] { try range(x,0...100) }
    try range(strobeDuration,0...360)
    try range(noiseSize,0.1...10);try range(lightMin,0...1);try range(lightMax,0...1)
    guard lightMin <= lightMax else { throw CraftError.invalid("Light Range minimum exceeds maximum.") }
  }
  public var isIdentity: Bool {
    enabled.allSatisfy { mode in mode == .path ? paths.allSatisfy { $0.speed == 0 } : pins(mode).allSatisfy { mode == .spin ? $0.blurAngle == 0 : $0.blur == 0 } }
  }
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard let fields = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CraftError.invalid("Blur Gallery settings must be an object.") }
    let encoder = JSONEncoder()
    func object<T:Encodable>(_ value:T) throws -> [String:Any] { try JSONSerialization.jsonObject(with:encoder.encode(value)) as! [String:Any] }
    func merge(_ raw:[String:Any], _ defaults:[String:Any]) throws -> [String:Any] {
      guard Set(raw.keys).isSubset(of:Set(defaults.keys)) else { throw CraftError.invalid("Unknown Blur Gallery parameter.") }
      var result=defaults;for (k,v) in raw { result[k]=v };return result
    }
    var canonical = try merge(fields,object(Self()))
    for key in ["field","iris","tiltShift","spin"] where fields[key] != nil {
      guard let pins=fields[key] as? [[String:Any]], pins.count <= 64 else { throw CraftError.invalid("Invalid blur pins.") }
      canonical[key] = try pins.map { try merge($0,object(Pin())) }
    }
    if let raw=fields["paths"] {
      guard let paths=raw as? [[String:Any]], paths.count<=16 else { throw CraftError.invalid("Invalid blur paths.") }
      canonical["paths"] = try paths.map { path in
        if let points=path["points"] {
          guard let values=points as? [[String:Any]], values.allSatisfy({Set($0.keys)==["x","y"]}) else { throw CraftError.invalid("Path points require x and y.") }
        }
        return try merge(path,object(MotionPath()))
      }
    }
    let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:canonical));try result.validate();return result
  }
}
