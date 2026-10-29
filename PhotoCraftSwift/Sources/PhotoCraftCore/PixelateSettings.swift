import Foundation

public struct PixelateSettings: Codable, Equatable, Sendable {
  public enum Pattern: String, Codable, CaseIterable, Sendable {
    case fineDots, mediumDots, grainyDots, coarseDots, shortLines, mediumLines, longLines, shortStrokes, mediumStrokes, longStrokes
    public var title: String {
      switch self {
      case .fineDots: "Fine Dots"
      case .mediumDots: "Medium Dots"
      case .grainyDots: "Grainy Dots"
      case .coarseDots: "Coarse Dots"
      case .shortLines: "Short Lines"
      case .mediumLines: "Medium Lines"
      case .longLines: "Long Lines"
      case .shortStrokes: "Short Strokes"
      case .mediumStrokes: "Medium Strokes"
      case .longStrokes: "Long Strokes"
      }
    }
  }
  private struct Values: Codable, Equatable, Sendable {
    var maxRadius = 8.0
    var angles = [108.0, 162.0, 90.0, 45.0]
    var cellSize = 10.0
    var pattern = Pattern.fineDots
    var seed: UInt32 = 0
    var background = Pixel.white
  }
  private indirect enum Storage: Equatable, Sendable { case value(Values) }
  private var storage: Storage = .value(Values())
  private var values: Values {
    get { switch storage { case .value(let value): return value } }
    set { storage = .value(newValue) }
  }
  public init(kind: RasterFilter.Kind) { if kind == .pointillize { cellSize = 5 } }
  public init(from decoder: Decoder) throws { storage = .value(try Values(from: decoder)) }
  public func encode(to encoder: Encoder) throws { try values.encode(to: encoder) }
  public var maxRadius: Double { get { values.maxRadius } set { var v=values;v.maxRadius=newValue;values=v } }
  public var angles: [Double] { get { values.angles } set { var v=values;v.angles=newValue;values=v } }
  public var cellSize: Double { get { values.cellSize } set { var v=values;v.cellSize=newValue;values=v } }
  public var pattern: Pattern { get { values.pattern } set { var v=values;v.pattern=newValue;values=v } }
  public var seed: UInt32 { get { values.seed } set { var v=values;v.seed=newValue;values=v } }
  public var background: Pixel { get { values.background } set { var v=values;v.background=newValue;values=v } }
  public static func keys(_ kind: RasterFilter.Kind) -> Set<String> {
    switch kind {
    case .colorHalftone: ["maxRadius", "angles"]
    case .crystallize: ["cellSize", "seed"]
    case .pointillize: ["cellSize", "seed", "background"]
    case .mezzotint: ["pattern", "seed"]
    default: []
    }
  }
  public func validate(kind: RasterFilter.Kind) throws {
    guard kind.isPixelate else { throw CraftError.invalid("Pixelate settings require a Pixelate filter.") }
    func integer(_ value: Double, _ range: ClosedRange<Double>) throws {
      guard value.isFinite, range.contains(value), value.rounded() == value else {
        throw CraftError.invalid("Pixelate numeric settings must be whole numbers in their supported ranges.")
      }
    }
    // Bound the complete persisted value, including settings inactive for this kind.
    try integer(maxRadius,4...127)
    guard angles.count == 4 else {throw CraftError.invalid("Color Halftone requires four channel angles.")}
    for angle in angles {try integer(angle,-360...360)}
    try integer(cellSize,3...300)
    guard background.isFinite,[background.r,background.g,background.b,background.a].allSatisfy({(0...1).contains($0)}) else {
      throw CraftError.invalid("Pointillize background components must be between zero and one.")
    }
  }

  public static func decodeJSON(_ data: Data, kind: RasterFilter.Kind) throws -> Self {
    guard let fields = try JSONSerialization.jsonObject(with: data) as? [String:Any], Set(fields.keys).isSubset(of: keys(kind)) else {
      throw CraftError.invalid("Unknown Pixelate setting.")
    }
    if let bg = fields["background"] as? [String:Any], Set(bg.keys) != ["r","g","b","a"] { throw CraftError.invalid("Invalid background color fields.") }
    if let angles = fields["angles"] as? [Any], angles.count != 4 { throw CraftError.invalid("Color Halftone requires four channel angles.") }
    var complete = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self(kind:kind))) as! [String:Any]
    for (key,value) in fields { complete[key] = value }
    let result = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: complete))
    try result.validate(kind:kind); return result
  }
  public func apiParameters(kind: RasterFilter.Kind) -> [String:Any] {
    ((try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter { Self.keys(kind).contains($0.key) }
  }
  public static func apiSchema(kind: RasterFilter.Kind) -> [String:Any] {
    let defaults = Self(kind:kind).apiParameters(kind:kind)
    var properties: [String:Any] = [:]
    for key in keys(kind) {
      switch key {
      case "angles": properties[key] = ["type":"array","minItems":4,"maxItems":4,"items":["type":"integer","minimum":-360,"maximum":360],"default":defaults[key]!]
      case "pattern": properties[key] = ["type":"string","enum":Pattern.allCases.map(\.rawValue),"default":defaults[key]!]
      case "background": properties[key] = ["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,["type":"number","minimum":0,"maximum":1] as [String:Any])}),"default":defaults[key]!]
      default: properties[key] = ["type":"integer","minimum":key == "seed" ? 0:key == "maxRadius" ? 4:3,"maximum":key == "seed" ? Double(UInt32.max):key == "maxRadius" ? 127:300,"default":defaults[key]!]
      }
    }
    return ["type":"object","additionalProperties":false,"properties":properties]
  }
  public static var apiCapabilities: [String:Any] {
    ["kinds":RasterFilter.Kind.allCases.filter(\.isPixelate).map(\.rawValue),"nativeVersion":40,"actionsVersion":12,"patterns":Pattern.allCases.map(\.rawValue),"algorithm":"Licensed PhotoCraft pixelate.rs translated to native Swift; deterministic seeds and layer-local cell origins. RGB uses the first three Halftone angles; the fourth is retained. Exact Photoshop pixels/defaults/depth availability and actionJSON/PSD mappings remain unqualified.","pointillizeBackground":"Desktop snapshots the current background color; API defaults to opaque white and can supply background RGBA."]
  }
}

extension RasterFilter.Kind {
  public var isPixelate: Bool { [.colorHalftone,.crystallize,.facet,.fragment,.mezzotint,.pointillize].contains(self) }
  public var isImmediatePixelate: Bool { self == .facet || self == .fragment }
}
