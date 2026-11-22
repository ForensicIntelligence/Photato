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
    return hasInterior(points)
  }
  public func enclosedPoints(width: Int, height: Int) -> [[Double]]? {
    if closesLoop { return points }
    guard points.count >= 2, points.allSatisfy({ $0.count == 2 }),
      let first = points.first, let last = points.last else { return nil }
    let right = Double(width), bottom = Double(height)
    func edge(_ p: [Double]) -> Int? {
      let distances = [abs(p[0]), abs(p[0] - right), abs(p[1]), abs(p[1] - bottom)]
      guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[nearest] <= size / 2 else { return nil }
      return nearest
    }
    guard let a = edge(first), let b = edge(last), (a < 2) != (b < 2) else { return nil }
    let vertical = a < 2 ? a : b, horizontal = a >= 2 ? a : b
    let path = points + [[vertical == 0 ? 0 : right, horizontal == 2 ? 0 : bottom]]
    return hasInterior(path) ? path : nil
  }
  private func hasInterior(_ path: [[Double]]) -> Bool {
    var area = 0.0
    for i in path.indices {
      let a = path[i], b = path[(i+1)%path.count]
      area += a[0]*b[1]-a[1]*b[0]
    }
    return abs(area) > size*size
  }
  public func applying(to mask: SelectionMask) throws -> SelectionMask {
    try validate()
    var brush = ContentAwareStroke(); brush.target = .selection
    brush.add = !subtract; brush.size = size; brush.points = points
    var result = mask
    if let enclosing = enclosedPoints(width: mask.width, height: mask.height) {
      var loop = brush; loop.kind = .lasso; loop.points = enclosing
      result = try loop.applying(to:result)
    }
    return try brush.applying(to:result)
  }
}

public struct RemoveRequest: Equatable, Sendable {
  public let layerID: UUID
  public let settings: RemoveToolSettings
  public let strokes: [RemoveStroke]
  public let initialCoverage: SelectionMask?
  public let categoryCoverages: [SelectionMask]
  public init(layerID: UUID, settings: RemoveToolSettings, strokes: [RemoveStroke],
    initialCoverage: SelectionMask? = nil, categoryCoverages: [SelectionMask] = []) {
    self.layerID = layerID; self.settings = settings; self.strokes = strokes; self.initialCoverage = initialCoverage
    self.categoryCoverages = categoryCoverages
  }
  public func validate() throws {
    try settings.validate()
    guard categoryCoverages.count <= 6 else { throw CraftError.invalid("Too many distraction selection categories.") }
    guard (!strokes.isEmpty || initialCoverage?.bounds != nil || categoryCoverages.contains { $0.bounds != nil }), strokes.count <= 256,
      strokes.reduce(0, { $0+$1.points.count }) <= 16384 else {
      throw CraftError.invalid("Remove accepts up to 256 strokes and 16384 points per operation.")
    }
    for stroke in strokes { try stroke.validate() }
  }
}
