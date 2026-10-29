import Foundation

public struct ArtboardGuide: Codable, Equatable, Identifiable, Sendable {
  public enum Axis: String, Codable, CaseIterable, Sendable { case horizontal, vertical }
  public var id: UUID
  public var axis: Axis
  /// Offset from the artboard's own top or left edge, in pixels.
  public var position: Double
  public init(axis: Axis, position: Double) { id = UUID(); self.axis = axis; self.position = position }
}
public struct Artboard: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var background: Pixel
  public var preset: String
  public var guides: [ArtboardGuide]
  public init(width: Int, height: Int, background: Pixel = .white, preset: String = "", guides: [ArtboardGuide] = []) {
    self.width = width; self.height = height; self.background = background; self.preset = preset; self.guides = guides
  }
  public func validate() throws {
    _ = try Surface(width: width, height: height)
    guard background.isFinite, (0...1).contains(background.a), preset.utf8.count <= 256,
      guides.count <= 512, Set(guides.map(\.id)).count == guides.count,
      guides.allSatisfy({ $0.position.isFinite && abs($0.position) <= 1_000_000 }) else { throw CraftError.invalid("Invalid artboard appearance or guides.") }
  }
}
public struct ArtboardOrigin: Codable, Equatable, Sendable {
  public var x: Int
  public var y: Int
  public init(x: Int = 0, y: Int = 0) { self.x = x; self.y = y }
}
public enum ArtboardCommand: Sendable {
  case create(name: String, bounds: IntRect, background: Pixel, children: [UUID])
  case convert(UUID, bounds: IntRect, background: Pixel)
  case configure(UUID, name: String, bounds: IntRect, appearance: Artboard, moveContents: Bool)
  case resize(UUID, bounds: IntRect, moveContents: Bool)
  case settings(UUID, Artboard)
  case duplicate(UUID, x: Int, y: Int, name: String?)
  case clearGuides(UUID)
  case removeMetadata(UUID)
  public var label: String {
    switch self {
    case .create: "New Artboard"
    case .convert: "Artboard from Group"
    case .resize: "Resize Artboard"
    case .settings, .configure: "Artboard Properties"
    case .duplicate: "Duplicate Artboard"
    case .clearGuides: "Clear Artboard Guides"
    case .removeMetadata: "Ungroup Artboard"
    }
  }
  func apply(to d: inout CraftDocument) throws {
    func index(_ id: UUID, requireBoard: Bool = true) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }), d.layers[i].isGroup,
        d.layers[i].parentID == nil, !d.isLocked(id), !requireBoard || d.layers[i].artboard != nil else { throw CraftError.invalid("Choose an unlocked top-level artboard group.") }; return i
    }
    func physical(_ bounds: IntRect) throws -> IntRect {
      try LayerLayout.validate(bounds)
      return IntRect(x: bounds.x - (d.artboardOrigin?.x ?? 0), y: bounds.y - (d.artboardOrigin?.y ?? 0), width: bounds.width, height: bounds.height)
    }
    func install(_ i: Int, bounds: IntRect, background: Pixel) throws {
      let board = Artboard(width: bounds.width, height: bounds.height, background: background); try board.validate()
      var group = d.layers[i].group!; group.artboard = board; group.passThrough = false
      d.layers[i].content = .group(group); d.layers[i].x = bounds.x; d.layers[i].y = bounds.y; d.layers[i].affine = nil
      d.activeLayerID = d.layers[i].id
    }
    switch self {
    case .create(let name, let bounds, let background, let children):
      let rect = try physical(bounds)
      guard children.count == Set(children).count, children.allSatisfy({ id in d.layers.contains { $0.id == id && $0.parentID == nil && $0.artboard == nil } }) else { throw CraftError.invalid("Select top-level layers outside existing artboards.") }
      if children.isEmpty {
        guard d.layers.count < 512 else { throw CraftError.invalid("Layer limit reached.") }
        let layer = try NewLayerGroupOptions(name: name).layer(); d.layers.append(layer); d.activeLayerID = layer.id
      } else { try d.createLayerGroup(.init(name: name), children: children, below: false) }
      try install(d.activeIndex!, bounds: rect, background: background)
    case .convert(let id, let bounds, let background):
      let i = try index(id, requireBoard: false)
      guard d.layers[i].artboard == nil else { throw CraftError.invalid("This group is already an artboard.") }
      try install(i, bounds: physical(bounds), background: background)
    case .configure(let id, let name, let bounds, let appearance, let moveContents):
      _ = try NewLayerGroupOptions(name: name).layer(); try appearance.validate()
      guard appearance.width == bounds.width, appearance.height == bounds.height else { throw CraftError.invalid("Artboard dimensions disagree.") }
      try ArtboardCommand.resize(id, bounds: bounds, moveContents: moveContents).apply(to: &d)
      try ArtboardCommand.settings(id, appearance).apply(to: &d)
      let i = try index(id); d.layers[i].name = name
    case .resize(let id, let bounds, let moveContents):
      var i = try index(id); let rect = try physical(bounds)
      guard !d.isPositionLocked(id) else { throw CraftError.invalid("Unlock the artboard position before resizing.") }
      var board = d.layers[i].artboard!; board.width = rect.width; board.height = rect.height; board.preset = ""; try board.validate()
      if moveContents {
        try Command.move(id, rect.x, rect.y).apply(to: &d); i = try index(id)
      } else { d.layers[i].x = rect.x; d.layers[i].y = rect.y }
      var group = d.layers[i].group!; group.artboard = board; d.layers[i].content = .group(group)
    case .settings(let id, let board):
      let i = try index(id); try board.validate()
      guard board.width == d.layers[i].artboard!.width, board.height == d.layers[i].artboard!.height else { throw CraftError.invalid("Use Resize Artboard to change dimensions.") }
      var group = d.layers[i].group!; group.artboard = board; d.layers[i].content = .group(group)
    case .duplicate(let id, let x, let y, let name):
      let i = try index(id), original = d.layers[i]
      let rect = try physical(IntRect(x: x, y: y, width: original.artboard!.width, height: original.artboard!.height))
      try LayerDuplication.duplicate(in: &d, selected: [id], name: name)
      try Command.move(d.activeLayerID!, rect.x, rect.y).apply(to: &d)
    case .clearGuides(let id):
      let i = try index(id); var group = d.layers[i].group!; group.artboard?.guides = []; d.layers[i].content = .group(group)
    case .removeMetadata(let id):
      let i = try index(id); var group = d.layers[i].group!; group.artboard = nil; d.layers[i].content = .group(group)
    }
  }
}
extension Layer {
  public var artboard: Artboard? { group?.artboard }
  public var artboardBounds: IntRect? { artboard.map { IntRect(x: x, y: y, width: $0.width, height: $0.height) } }
}
extension CraftDocument {
  public var artboards: [Layer] { layers.filter { $0.artboard != nil } }
  public var hasArtboards: Bool { layers.contains { $0.artboard != nil } }
  public func artboard(containing id: UUID) -> Layer? {
    guard let layer = layers.first(where: { $0.id == id }) else { return nil }
    return layer.artboard != nil ? layer : ancestors(of: id).first { $0.artboard != nil }
  }
  public func logicalArtboardBounds(_ layer: Layer) -> IntRect? {
    layer.artboardBounds.map { IntRect(x: $0.x + (artboardOrigin?.x ?? 0), y: $0.y + (artboardOrigin?.y ?? 0), width: $0.width, height: $0.height) }
  }
  func validateArtboards() throws {
    if let origin = artboardOrigin {
      guard abs(Double(origin.x)) <= 1_000_000, abs(Double(origin.y)) <= 1_000_000 else { throw CraftError.invalid("Invalid artboard canvas origin.") }
    }
    for layer in artboards {
      guard layer.parentID == nil, !layer.isClipped, layer.affine == nil else { throw CraftError.invalid("Artboards must be untransformed top-level groups, not clipping layers.") }
      try layer.artboard!.validate()
      try LayerLayout.validate(layer.artboardBounds!)
      guard layer.x >= 0, layer.y >= 0, layer.x + layer.artboard!.width <= width, layer.y + layer.artboard!.height <= height else { throw CraftError.invalid("Artboard extends outside its allocated canvas.") }
    }
  }
  /// Rebase all physical pixel coordinates when artboards grow left/up. The origin
  /// preserves their logical coordinates; source pixels are never resampled here.
  mutating func fitArtboardCanvas() throws {
    guard hasArtboards, let bounds = try LayerLayout.union(artboards.compactMap(\.artboardBounds)) else { return }
    let dx = -min(0, bounds.x), dy = -min(0, bounds.y)
    let w = max(width, bounds.x + bounds.width) + dx, h = max(height, bounds.y + bounds.height) + dy
    guard w != width || h != height || artboardOrigin == nil else { return }
    _ = try Surface(width: w, height: h, depth: depth)
    let old = self, delta = Transform2D.translation(Double(dx), Double(dy))
    if dx != 0 || dy != 0 {
      for i in layers.indices {
        DocumentGeometry.freezeTextLayout(&layers[i], document: old)
        layers[i].x += dx; layers[i].y += dy
        layers[i].smartFilters?.transformPuppetPins(delta); layers[i].smartFilters?.transformPerspectivePlanes(delta)
        if let stack = old.layers[i].smartFilters { layers[i].smartFilters?.maskProperties.transform = delta * stack.maskProperties.transform }
        if case .patternFill(var fill) = layers[i].content { try fill.transform(by: delta); layers[i].content = .patternFill(fill) }
        if let mask = old.layers[i].vectorMask { layers[i].vectorMask?.path = mask.path.transformed(delta) }
      }
      transformSavedPaths(by: delta)
    }
    width = w; height = h
    try mapSelection(from: old, by: delta); try transformChannels(from: old, by: delta)
    artboardOrigin = .init(x: (old.artboardOrigin?.x ?? 0) - dx, y: (old.artboardOrigin?.y ?? 0) - dy)
  }
}

extension CraftDocument {
  /// Isolate one artboard for export without resampling or modifying source layers.
  public func extractedArtboard(_ id: UUID) throws -> CraftDocument {
    try validate()
    guard let board = artboards.first(where: { $0.id == id }), let bounds = board.artboardBounds else { throw CraftError.invalid("Choose an existing artboard.") }
    let ids = subtreeIDs(id), delta = Transform2D.translation(-Double(bounds.x), -Double(bounds.y))
    var result = self; result.id = UUID(); result.name = board.name
    result.layers = layers.filter { ids.contains($0.id) }
    for i in result.layers.indices {
      let old = result.layers[i]
      DocumentGeometry.freezeTextLayout(&result.layers[i], document: self)
      result.layers[i].x -= bounds.x; result.layers[i].y -= bounds.y
      result.layers[i].smartFilters?.transformPuppetPins(delta); result.layers[i].smartFilters?.transformPerspectivePlanes(delta)
      if let filters = old.smartFilters { result.layers[i].smartFilters?.maskProperties.transform = delta * filters.maskProperties.transform }
      if case .patternFill(var fill) = old.content { try fill.transform(by: delta); result.layers[i].content = .patternFill(fill) }
      if let mask = old.vectorMask { result.layers[i].vectorMask?.path = mask.path.transformed(delta) }
    }
    result.width = bounds.width; result.height = bounds.height; result.artboardOrigin = .init()
    result.activeLayerID = ids.contains(activeLayerID ?? UUID()) ? activeLayerID : id
    result.transformSavedPaths(by: delta)
    result.selection = nil; result.selectionMask = nil
    try result.transformChannels(from: self, by: delta, method: .nearest)
    try result.validate(); return result
  }
}
