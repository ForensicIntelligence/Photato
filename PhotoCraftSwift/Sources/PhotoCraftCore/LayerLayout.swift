import Foundation

public enum LayerAlignment: String, CaseIterable, Sendable {
  case top = "Top Edges"
  case verticalCenter = "Vertical Centers"
  case bottom = "Bottom Edges"
  case left = "Left Edges"
  case horizontalCenter = "Horizontal Centers"
  case right = "Right Edges"
  public var horizontal: Bool { self == .left || self == .horizontalCenter || self == .right }
  func coordinate2(_ r: IntRect) -> Int {
    switch self {
    case .top: 2 * r.y
    case .verticalCenter: 2 * r.y + r.height
    case .bottom: 2 * (r.y + r.height)
    case .left: 2 * r.x
    case .horizontalCenter: 2 * r.x + r.width
    case .right: 2 * (r.x + r.width)
    }
  }
}

public enum LayerDistribution: String, CaseIterable, Sendable {
  case top = "Top Edges"
  case verticalCenter = "Vertical Centers"
  case bottom = "Bottom Edges"
  case left = "Left Edges"
  case horizontalCenter = "Horizontal Centers"
  case right = "Right Edges"
  case horizontally = "Horizontally"
  case vertically = "Vertically"
  public var edge: LayerAlignment {
    LayerAlignment(rawValue: rawValue) ?? (self == .horizontally ? .left : .top)
  }
  public var spacing: Bool { self == .horizontally || self == .vertically }
}

public enum LayerLayoutTarget: String, CaseIterable, Sendable {
  /// A pixel selection takes precedence; otherwise align the selected layers to one another.
  case selection = "Selection"
  case canvas = "Canvas"
}

public enum LayerLayoutOperation: Equatable, Sendable {
  case align(LayerAlignment)
  case distribute(LayerDistribution)
  public var label: String {
    switch self {
    case .align(let edge): "Align \(edge.rawValue)"
    case .distribute(let kind): "Distribute \(kind.rawValue)"
    }
  }
}

public struct LayerLayoutItem: Equatable, Sendable {
  public let id: UUID
  public let bounds: IntRect
  public init(id: UUID, bounds: IntRect) {
    self.id = id
    self.bounds = bounds
  }
}

public struct LayerTranslation: Equatable, Sendable {
  public let id: UUID
  public let dx: Int
  public let dy: Int
  public init(id: UUID, dx: Int, dy: Int) {
    self.id = id
    self.dx = dx
    self.dy = dy
  }
}

public enum LayerLayout {
  /// Inputs are in document stack order; equal edge coordinates retain that order.
  /// Exact rational arithmetic rounds halves toward the greater document coordinate.
  public static func plan(
    _ items: [LayerLayoutItem], operation: LayerLayoutOperation, target: IntRect? = nil
  ) throws -> [LayerTranslation] {
    guard !items.isEmpty, items.count <= 512, Set(items.map(\.id)).count == items.count else {
      throw CraftError.invalid("Select distinct layers with content to align or distribute.")
    }
    for item in items { try validate(item.bounds) }
    if let target { try validate(target) }
    func rounded(_ numerator: Int, _ denominator: Int) -> Int {
      let n = 2 * numerator + denominator
      let d = 2 * denominator
      return n / d - (n < 0 && n % d != 0 ? 1 : 0)
    }
    var offsets = [Int](repeating: 0, count: items.count)
    let edge: LayerAlignment
    switch operation {
    case .align(let alignment):
      edge = alignment
      guard target != nil || items.count >= 2 else {
        throw CraftError.invalid(
          "Select two layers, make a pixel selection, or choose Align To Canvas.")
      }
      let destination = try target ?? union(items.map(\.bounds))!
      for i in items.indices {
        offsets[i] = rounded(edge.coordinate2(destination) - edge.coordinate2(items[i].bounds), 2)
      }
    case .distribute(let distribution):
      guard items.count >= 3 else {
        throw CraftError.invalid("Select at least three layers to distribute.")
      }
      edge = distribution.edge
      let order = items.indices.sorted {
        let a = edge.coordinate2(items[$0].bounds)
        let b = edge.coordinate2(items[$1].bounds)
        return a == b ? $0 < $1 : a < b
      }
      let first = items[order[0]].bounds
      let last = items[order.last!].bounds
      let intervals = items.count - 1
      if distribution.spacing {
        func start(_ r: IntRect) -> Int { edge.horizontal ? r.x : r.y }
        func size(_ r: IntRect) -> Int { edge.horizontal ? r.width : r.height }
        let gap = start(last) + size(last) - start(first) - items.reduce(0) { $0 + size($1.bounds) }
        var cursor = start(first) * intervals
        for i in order {
          offsets[i] = rounded(cursor - start(items[i].bounds) * intervals, intervals)
          cursor += size(items[i].bounds) * intervals + gap
        }
      } else {
        let a = edge.coordinate2(first)
        let span = edge.coordinate2(last) - a
        for (position, i) in order.enumerated() {
          offsets[i] = rounded(
            (a - edge.coordinate2(items[i].bounds)) * intervals + span * position,
            2 * intervals)
        }
      }
    }
    try Task.checkCancellation()
    return items.indices.map {
      LayerTranslation(
        id: items[$0].id, dx: edge.horizontal ? offsets[$0] : 0,
        dy: edge.horizontal ? 0 : offsets[$0])
    }
  }

  static func validate(_ r: IntRect) throws {
    guard abs(Double(r.x)) <= 1_000_000, abs(Double(r.y)) <= 1_000_000,
      r.width > 0, r.height > 0, r.width <= 2_000_000, r.height <= 2_000_000,
      abs(Double(r.x) + Double(r.width)) <= 1_000_000,
      abs(Double(r.y) + Double(r.height)) <= 1_000_000
    else { throw CraftError.invalid("Layer layout bounds are outside the supported range.") }
  }

  public static func union(_ bounds: [IntRect]) throws -> IntRect? {
    for bound in bounds { try validate(bound) }
    guard let first = bounds.first else { return nil }
    let x = bounds.reduce(first.x) { min($0, $1.x) }
    let y = bounds.reduce(first.y) { min($0, $1.y) }
    let right = bounds.reduce(first.x + first.width) { max($0, $1.x + $1.width) }
    let bottom = bounds.reduce(first.y + first.height) { max($0, $1.y + $1.height) }
    return IntRect(x: x, y: y, width: right - x, height: bottom - y)
  }

  public static func roots(_ selected: Set<UUID>, in document: CraftDocument) throws -> [Layer] {
    guard !selected.isEmpty, selected.isSubset(of: Set(document.layers.map(\.id))) else {
      throw CraftError.invalid("Select existing layers to align or distribute.")
    }
    let byID = Dictionary(
      document.layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return document.layers.filter {
      selected.contains($0.id) && owner($0.parentID, in: selected, byID: byID) == nil
    }
  }

  private static func owner(_ start: UUID?, in selected: Set<UUID>, byID: [UUID: Layer]) -> UUID? {
    var next = start
    for _ in 0...32 {
      guard let id = next else { return nil }
      if selected.contains(id) { return id }
      next = byID[id]?.parentID
    }
    return nil
  }

  /// Resolve the union once, rather than rescanning the hierarchy for every selected root.
  public static func members(of roots: Set<UUID>, in document: CraftDocument) -> [Layer] {
    let byID = Dictionary(
      document.layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return document.layers.filter { owner($0.id, in: roots, byID: byID) != nil }
  }

  public static func containsLockedLayerOrAncestor(_ members: [Layer], in document: CraftDocument)
    -> Bool
  {
    let byID = Dictionary(
      document.layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let locked = Set(document.layers.filter(\.locked).map(\.id))
    return members.contains { owner($0.id, in: locked, byID: byID) != nil }
  }

  static func apply(_ moves: [LayerTranslation], to document: inout CraftDocument) throws {
    try document.validate()
    let ids = Set(moves.map(\.id))
    guard moves.count <= 512, ids.count == moves.count,
      try roots(ids, in: document).count == moves.count
    else {
      throw CraftError.invalid("Layer layout contains duplicate or nested translations.")
    }
    let byID = Dictionary(uniqueKeysWithValues: document.layers.map { ($0.id, $0) })
    let byMove = Dictionary(uniqueKeysWithValues: moves.map { ($0.id, $0) })
    let affected: [(Int, LayerTranslation)] = document.layers.indices.compactMap { i in
      guard let id = owner(document.layers[i].id, in: ids, byID: byID), let move = byMove[id] else {
        return nil
      }
      return (i, move)
    }
    guard !containsLockedLayerOrAncestor(affected.map { document.layers[$0.0] }, in: document)
    else {
      throw CraftError.invalid("Unlock the selected layers and their groups before arranging them.")
    }
    for move in moves {
      guard abs(Double(move.dx)) <= 2_000_000, abs(Double(move.dy)) <= 2_000_000 else {
        throw CraftError.invalid("Layer translation is out of range.")
      }
    }
    // Validate every descendant, including stationary anchors, before changing any layer.
    for (i, move) in affected {
      let layer = document.layers[i]
      guard abs(Double(layer.x) + Double(move.dx)) <= 1_000_000,
        abs(Double(layer.y) + Double(move.dy)) <= 1_000_000
      else {
        throw CraftError.invalid("Layer translation is out of range.")
      }
    }
    var candidate = document
    for (i, move) in affected where move.dx != 0 || move.dy != 0 {
      try Task.checkCancellation()
      let old = candidate.layers[i]
      candidate.layers[i].x += move.dx
      candidate.layers[i].y += move.dy
      try candidate.layers[i].movePattern(x: move.dx, y: move.dy)
      try candidate.layers[i].preserveUnlinkedMask(from: old)
      if old.vectorMask?.linked == true {
        candidate.layers[i].vectorMask?.path = old.vectorMask!.path.transformed(
          .translation(Double(move.dx), Double(move.dy)))
      }
      try trimMovedRaster(&candidate.layers[i])
    }
    try Task.checkCancellation()
    try candidate.validate()
    document = candidate
  }

  /// Photoshop recomputes moved raster storage bounds. This matters for subsequent
  /// selection/canvas alignment, which uses the current storage extent.
  static func trimMovedRaster(_ layer: inout Layer) throws {
    guard case .raster(let pixels) = layer.content, let bounds = try pixels.contentBounds(),
      bounds != IntRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
    else { return }
    let old = layer
    layer.content = .raster(try pixels.cropped(to: bounds))
    if let affine = layer.affine {
      layer.affine = affine * .translation(Double(bounds.x), Double(bounds.y))
    } else {
      layer.x += bounds.x
      layer.y += bounds.y
    }
    if layer.mask != nil {
      var properties = old.effectiveMaskProperties
      properties.transform = try layer.coordinateTransform.inverted() * old.maskCoordinateTransform
      layer.maskProperties = properties
    }
    // Vector masks already use document coordinates and need no storage-frame correction.
  }
}
