import Foundation

/// Window-local Remove options. These do not imply availability of a generative model.
public struct RemoveToolSettings: Codable, Equatable, Sendable {
  public enum Mode: String, Codable, CaseIterable, Sendable {
    case auto, generativeOff, generativeOn
    public var title: String {
      switch self {
      case .auto: "Auto (May use generative AI)"
      case .generativeOff: "Generative AI off"
      case .generativeOn: "Generative AI on"
      }
    }
  }
  public var size = 19.0
  public var subtract = false
  public var mode: Mode = .auto
  public var sampleAllLayers = false
  public var removeAfterEachStroke = true
  public var createNewLayer = false
  public init() {}
  public func validate() throws {
    guard size.isFinite, (1...5000).contains(size) else {
      throw CraftError.invalid("Remove brush size must be 1–5000 pixels.")
    }
    guard mode != .generativeOn else {
      throw CraftError.unsupported("Generative Remove is not available. Choose Auto or Generative AI off for native traditional processing.")
    }
  }
}

public struct RemoveStroke: Codable, Equatable, Sendable {
  public var size: Double
  public var subtract: Bool
  public var points: [[Double]]
  public init(size: Double, subtract: Bool = false, points: [[Double]]) {
    self.size = size; self.subtract = subtract; self.points = points
  }
  public func validate() throws {
    var brush = ContentAwareStroke(); brush.size = size; brush.points = points
    try brush.validate()
  }
  /// A geometric policy, not a claim about Photoshop's unpublished closing threshold.
  public var closesLoop: Bool {
    guard points.count >= 4, points.allSatisfy({ $0.count == 2 }),
      let first = points.first, let last = points.last,
      hypot(last[0]-first[0],last[1]-first[1]) <= size else { return false }
    var area = 0.0
    for i in points.indices {
      let a = points[i], b = points[(i+1)%points.count]
      area += a[0]*b[1]-a[1]*b[0]
    }
    return abs(area) > size*size
  }
  public func applying(to mask: SelectionMask) throws -> SelectionMask {
    try validate()
    var brush = ContentAwareStroke(); brush.target = .selection
    brush.add = !subtract; brush.size = size; brush.points = points
    var result = mask
    if closesLoop { var loop = brush; loop.kind = .lasso; result = try loop.applying(to:result) }
    return try brush.applying(to:result)
  }
}

public struct RemoveRequest: Equatable, Sendable {
  public let layerID: UUID
  public let settings: RemoveToolSettings
  public let strokes: [RemoveStroke]
  public init(layerID: UUID, settings: RemoveToolSettings, strokes: [RemoveStroke]) {
    self.layerID = layerID; self.settings = settings; self.strokes = strokes
  }
  public func validate() throws {
    try settings.validate()
    guard !strokes.isEmpty, strokes.count <= 256,
      strokes.reduce(0, { $0+$1.points.count }) <= 16384 else {
      throw CraftError.invalid("Remove accepts up to 256 strokes and 16384 points per operation.")
    }
    for stroke in strokes { try stroke.validate() }
  }
}
