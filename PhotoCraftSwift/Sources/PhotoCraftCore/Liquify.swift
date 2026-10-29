import Foundation

/// Native port of PhotoCraft algo/liquify.rs (MIT OR Apache-2.0).
public enum LiquifyTool: String, Codable, CaseIterable, Sendable {
  case forwardWarp, reconstruct, smooth, twirlCw, twirlCcw, pucker, bloat, pushLeft, freeze, thaw, lassoMask
  case reconstructAll, freezeAll, thawAll, invertFreeze
  public var title: String {
    switch self {
    case .forwardWarp: "Forward Warp"; case .reconstruct: "Reconstruct"; case .smooth: "Smooth"
    case .twirlCw: "Twirl Clockwise"; case .twirlCcw: "Twirl Counterclockwise"
    case .pucker: "Pucker"; case .bloat: "Bloat"; case .pushLeft: "Push Left"
    case .freeze: "Freeze Mask"; case .thaw: "Thaw Mask"; case .lassoMask: "Freeze Lasso"
    case .reconstructAll: "Reconstruct All"; case .freezeAll: "Mask All"; case .thawAll: "Mask None"; case .invertFreeze: "Invert Mask"
    }
  }
  public var global: Bool { [.reconstructAll,.freezeAll,.thawAll,.invertFreeze].contains(self) }
  public var stationary: Bool { ![.forwardWarp,.pushLeft,.lassoMask].contains(self) }
}
public struct LiquifyStroke: Codable, Equatable, Sendable {
  public var tool: LiquifyTool = .forwardWarp
  public var size: Double = 100
  public var density: Double = 50
  public var pressure: Double = 100
  public var rate: Double = 80
  public var points: [[Double]] = []
  public var amount: Double?
  public init(tool: LiquifyTool = .forwardWarp, size: Double = 100, points: [[Double]] = []) { self.tool = tool; self.size = size; self.points = points }
  public func validate() throws {
    guard size.isFinite, (1...15000).contains(size), [density,pressure,rate].allSatisfy({ $0.isFinite && (0...100).contains($0) }),
      amount == nil || (amount!.isFinite && (0...100).contains(amount!)), points.count <= 32768,
      points.allSatisfy({ p in (2...3).contains(p.count) && p.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) && (p.count == 2 || (0...1).contains(p[2])) }) else { throw CraftError.invalid("Invalid Liquify brush options or points.") }
    if tool.global && !points.isEmpty { throw CraftError.invalid("Global Liquify operations do not take points.") }
    if tool == .lassoMask, let amount, amount != 0 && amount != 1 { throw CraftError.invalid("Freeze Lasso amount must be0 or1.") }
  }
}
public struct LiquifySettings: Codable, Equatable, Sendable {
  /// Zero uses the current target dimensions; saved programs retain their original dimensions.
  public var width = 0
  public var height = 0
  /// Zero selects the source default:2px up to4.2MP,4px above.
  public var meshSize: Double = 0
  public var strokes: [LiquifyStroke] = []
  public var faces: [LiquifyFaceAdjustment] = []
  public init(width: Int = 0, height: Int = 0, strokes: [LiquifyStroke] = []) { self.width = width; self.height = height; self.strokes = strokes }
  public var estimatedBytes: Int { strokes.reduce(64+faces.count*2048) { $0+96+$1.points.reduce(0) { $0+$1.count*8 } } }
  public func validate() throws {
    guard width >= 0, height >= 0, width <= 65536, height <= 65536, (width == 0) == (height == 0),
      width == 0 || width <= RasterFilterEngine.maximumPixels / height,
      meshSize.isFinite, meshSize == 0 || (1...64).contains(meshSize), strokes.count <= 2048, faces.count <= 16,
      strokes.reduce(0,{ $0+$1.points.count }) <= 32768 else { throw CraftError.invalid("Liquify program exceeds its dimension, mesh or stroke limits.") }
    for stroke in strokes { try stroke.validate() }; for face in faces { try face.validate() }
  }
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard data.count <= 4*1024*1024, let raw = try JSONSerialization.jsonObject(with:data) as? [String:Any], Set(raw.keys).isSubset(of:["width","height","meshSize","strokes","faces"]) else { throw CraftError.invalid("Invalid Liquify program.") }
    var fields = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    for (key,value) in raw { fields[key] = value }
    if let values = raw["strokes"] {
      guard let list = values as? [[String:Any]], list.count <= 2048 else { throw CraftError.invalid("Invalid Liquify strokes.") }
      fields["strokes"] = try list.map { stroke in
        guard Set(stroke.keys).isSubset(of:["tool","size","density","pressure","rate","points","amount"]) else { throw CraftError.invalid("Unknown Liquify stroke parameter.") }
        var result = try JSONSerialization.jsonObject(with:JSONEncoder().encode(LiquifyStroke())) as! [String:Any]
        for (key,value) in stroke { result[key] = value }; return result
      }
    }
    if let faces = raw["faces"] {
      guard let faces = faces as? [[String:Any]], faces.count <= 16 else { throw CraftError.invalid("Invalid Liquify faces.") }
      fields["faces"] = try faces.map { face in
        guard Set(face.keys).isSubset(of:["geometry","parameters"]), let geometry = face["geometry"] as? [String:Any], Set(geometry.keys) == ["bounds","leftEye","rightEye","nose","mouth"] else { throw CraftError.invalid("Invalid face geometry parameters.") }
        var face = face; if face["parameters"] == nil { face["parameters"] = [String:Double]() }; return face
      }
    }
    let value = try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:fields)); try value.validate(); return value
  }
  public func field(targetWidth: Int, targetHeight: Int) throws -> LiquifyField {
    try validate()
    var field = try LiquifyField(width:width == 0 ? targetWidth : width,height:height == 0 ? targetHeight : height,cell:meshSize)
    for stroke in strokes { try field.apply(stroke) }; for face in faces { try field.applyFace(face) }
    return field
  }
}
public enum LiquifyMeshFile {
  public static let fileExtension = "photatoliquify"
  public static let maximumBytes = 4*1024*1024
  private struct Archive: Codable { var format = "PhotatoLiquify"; var version = 1; let settings: LiquifySettings }
  public static func encode(_ settings: LiquifySettings) throws -> Data {
    try settings.validate(); let data = try JSONEncoder().encode(Archive(settings:settings))
    guard data.count <= maximumBytes else { throw CraftError.invalid("Liquify mesh file exceeds4MiB.") }; return data
  }
  public static func decode(_ data: Data) throws -> LiquifySettings {
    guard data.count <= maximumBytes else { throw CraftError.invalid("Liquify mesh file exceeds4MiB.") }
    let value = try JSONDecoder().decode(Archive.self,from:data)
    guard value.format == "PhotatoLiquify", value.version == 1 else { throw CraftError.unsupported("Choose a Photato Liquify mesh file. Photoshop .msh is not supported yet.") }
    try value.settings.validate(); return value.settings
  }
}
