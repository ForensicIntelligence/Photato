import Foundation

public struct FrameDefinition: Codable, Equatable, Sendable {
  public enum Shape: String, Codable, CaseIterable, Sendable { case rectangle, ellipse, triangle, polygon, custom }
  public enum Alignment: String, Codable, CaseIterable, Sendable { case inside, center, outside }
  public var width: Int
  public var height: Int
  public var shape: Shape
  public var sides: Int
  /// Custom geometry is normalized to the frame's own width/height.
  public var customPath: VectorPath?
  public var strokeWidth: Double
  public var strokeColor: Pixel
  public var strokeAlignment: Alignment
  public init(width: Int, height: Int, shape: Shape = .rectangle, sides: Int = 5,
    customPath: VectorPath? = nil, strokeWidth: Double = 0, strokeColor: Pixel = .black,
    strokeAlignment: Alignment = .inside) {
    self.width = width; self.height = height; self.shape = shape; self.sides = sides
    self.customPath = customPath; self.strokeWidth = strokeWidth; self.strokeColor = strokeColor; self.strokeAlignment = strokeAlignment
  }
  public func validate() throws {
    _ = try Surface(width: width, height: height)
    guard (3...64).contains(sides), strokeWidth.isFinite, (0...1000).contains(strokeWidth), strokeColor.isFinite, (0...1).contains(strokeColor.a) else { throw CraftError.invalid("Invalid frame size, sides or stroke.") }
    if shape == .custom {
      guard let customPath, !customPath.isEmpty, !customPath.inverted, customPath.components.allSatisfy({ $0.closed }), customPath.components.flatMap(\.knots).allSatisfy({ [$0.anchor, $0.incoming, $0.outgoing].allSatisfy { abs($0.x) <= 10 && abs($0.y) <= 10 } }) else { throw CraftError.invalid("Choose a bounded, closed custom frame path.") }
      try customPath.validate()
    } else if customPath != nil { throw CraftError.invalid("Custom geometry requires the Custom frame shape.") }
  }
  public func path() throws -> VectorPath {
    try validate()
    let unit: VectorPath
    switch shape {
    case .custom: unit = customPath!
    case .rectangle: unit = .init(components: [.init(knots: [PathPoint(0,0), .init(1,0), .init(1,1), .init(0,1)].map { PathKnot($0) }, closed: true)])
    case .ellipse:
      let k = 0.2761423749153967
      unit = .init(components: [.init(knots: [
        .init(.init(0.5,0), incoming: .init(0.5-k,0), outgoing: .init(0.5+k,0), smooth: true),
        .init(.init(1,0.5), incoming: .init(1,0.5-k), outgoing: .init(1,0.5+k), smooth: true),
        .init(.init(0.5,1), incoming: .init(0.5+k,1), outgoing: .init(0.5-k,1), smooth: true),
        .init(.init(0,0.5), incoming: .init(0,0.5+k), outgoing: .init(0,0.5-k), smooth: true)], closed: true)])
    case .triangle, .polygon:
      let count = shape == .triangle ? 3 : sides
      let points = (0..<count).map { index -> PathKnot in
        let angle = Double(index) * 2 * Double.pi / Double(count) - Double.pi / 2
        return PathKnot(.init(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle)))
      }
      unit = .init(components: [.init(knots: points, closed: true)])
    }
    return unit.transformed(.scale(Double(width), Double(height)))
  }
}
public enum FrameFit: String, Codable, CaseIterable, Sendable { case fill, fit, original }
public enum FrameCommand: Sendable {
  case create(name: String, bounds: IntRect, definition: FrameDefinition, children: [UUID])
  case wrap(name: String, bounds: IntRect, definition: FrameDefinition, sourceIDs: Set<UUID>, embedded: Layer)
  case convert(UUID, FrameDefinition, offset: PathPoint = .init(0,0))
  case configure(UUID, FrameDefinition)
  case transform(UUID, Transform2D, contents: Bool)
  case transformContents(UUID, Transform2D)
  case replace(UUID, Layer, fit: FrameFit)
  case fit(UUID, FrameFit)
  case clear(UUID)
  public var label: String {
    switch self {
    case .create, .wrap: "New Frame"
    case .convert: "Convert to Frame"
    case .configure: "Frame Properties"
    case .transform: "Transform Frame"
    case .transformContents: "Transform Frame Contents"
    case .replace: "Place in Frame"
    case .fit: "Fit Frame Contents"
    case .clear: "Clear Frame Contents"
    }
  }
  func apply(to d: inout CraftDocument) throws {
    func index(_ id: UUID) throws -> Int {
      guard let i = d.layers.firstIndex(where: { $0.id == id }), d.layers[i].frame != nil, !d.isLocked(id) else { throw CraftError.invalid("Choose an unlocked frame.") }; return i
    }
    func contentIDs(_ id: UUID) -> Set<UUID> { d.subtreeIDs(id).subtracting([id]) }
    func fit(_ child: inout Layer, inside frame: Layer, method: FrameFit) throws {
      guard let definition = frame.frame, case .raster(let pixels) = child.content else { throw CraftError.invalid("Frame fitting requires an image or Smart Object.") }
      let sx = Double(definition.width) / Double(pixels.width), sy = Double(definition.height) / Double(pixels.height)
      let scale = method == .original ? 1 : method == .fill ? max(sx,sy) : min(sx,sy)
      let full = frame.coordinateTransform * .translation((Double(definition.width) - Double(pixels.width) * scale) / 2, (Double(definition.height) - Double(pixels.height) * scale) / 2) * .scale(scale,scale)
      child.x = Int(floor(full.tx)); child.y = Int(floor(full.ty)); child.affine = .translation(-Double(child.x),-Double(child.y)) * full
    }
    switch self {
    case .create(let name, let bounds, let definition, let children):
      try definition.validate(); try LayerLayout.validate(bounds)
      guard bounds.width == definition.width, bounds.height == definition.height, Set(children).count == children.count else { throw CraftError.invalid("Invalid frame bounds or child selection.") }
      try d.createLayerGroup(.init(name: name), children: children, below: false)
      let i = d.activeIndex!; var group = d.layers[i].group!; group.frame = definition; group.passThrough = false
      d.layers[i].content = .group(group); d.layers[i].x = bounds.x; d.layers[i].y = bounds.y
    case .wrap(let name, let bounds, let definition, let sourceIDs, let embedded):
      try Command.embedSmartObject(sourceIDs, embedded).apply(to: &d)
      try FrameCommand.create(name: name, bounds: bounds, definition: definition, children: [embedded.id]).apply(to: &d)
    case .convert(let id, let definition, let offset):
      try definition.validate()
      guard let i = d.layers.firstIndex(where: { $0.id == id }), !d.layers[i].isGroup, !d.isImageLocked(id), !d.isPositionLocked(id) else { throw CraftError.invalid("Choose an unlocked shape or type layer.") }
      switch d.layers[i].content { case .shape, .text: break; default: throw CraftError.invalid("Convert to Frame requires a shape or type layer.") }
      let full = d.layers[i].coordinateTransform * .translation(offset.x,offset.y)
      try full.validated()
      var group = GroupContent(passThrough: false); group.frame = definition
      d.layers[i].content = .group(group); d.layers[i].x = Int(floor(full.tx)); d.layers[i].y = Int(floor(full.ty)); d.layers[i].affine = .translation(-Double(d.layers[i].x),-Double(d.layers[i].y)) * full
      d.activeLayerID = id
    case .configure(let id, let definition):
      let i = try index(id); try definition.validate()
      guard !d.isImageLocked(id), (definition.width == d.layers[i].frame!.width && definition.height == d.layers[i].frame!.height) || !d.isPositionLocked(id) else { throw CraftError.invalid("Unlock the frame before changing its shape or dimensions.") }
      var group = d.layers[i].group!; group.frame = definition; d.layers[i].content = .group(group)
    case .transform(let id, let delta, let contents):
      _ = try index(id); try delta.validated()
      let ids = contents ? d.subtreeIDs(id) : Set([id]), original = d
      guard ids.allSatisfy({ !d.isPositionLocked($0) }) else { throw CraftError.invalid("Unlock frame/content position before transforming.") }
      for i in d.layers.indices where ids.contains(d.layers[i].id) { d.layers[i] = try DocumentGeometry.transformLayer(d.layers[i], by: delta, in: original) }
    case .transformContents(let id, let delta):
      _ = try index(id); try delta.validated(); let ids = contentIDs(id), original = d
      guard !ids.isEmpty, ids.allSatisfy({ !d.isPositionLocked($0) }) else { throw CraftError.invalid("Choose unlocked frame contents.") }
      for i in d.layers.indices where ids.contains(d.layers[i].id) { d.layers[i] = try DocumentGeometry.transformLayer(d.layers[i], by: delta, in: original) }
    case .replace(let id, var child, let method):
      let i = try index(id), frame = d.layers[i], old = contentIDs(id)
      guard !d.isImageLocked(id), old.allSatisfy({ !d.isLocked($0) && !d.isImageLocked($0) }), child.smartObject != nil, !d.layers.contains(where: { $0.id == child.id }), !child.isGroup else { throw CraftError.invalid("Place an embedded Smart Object into an unlocked frame.") }
      try fit(&child, inside: frame, method: method); child.parentID = id; child.clipped = false
      d.layers.removeAll { old.contains($0.id) }; let target = d.layers.firstIndex { $0.id == id }!
      d.layers.insert(child, at: target); d.activeLayerID = id
    case .fit(let id, let method):
      let i = try index(id), frame = d.layers[i], children = d.children(of: id)
      guard children.count == 1, !d.isPositionLocked(children[0].id) else { throw CraftError.invalid("Fit requires one unlocked image child.") }
      let childIndex = d.layers.firstIndex { $0.id == children[0].id }!; try fit(&d.layers[childIndex], inside: frame, method: method)
    case .clear(let id):
      _ = try index(id); let ids = contentIDs(id)
      guard !d.isImageLocked(id), ids.allSatisfy({ !d.isLocked($0) && !d.isImageLocked($0) }) else { throw CraftError.invalid("Unlock the contents before removing them.") }
      d.layers.removeAll { ids.contains($0.id) }; d.activeLayerID = id
    }
  }
}
extension Layer {
  public var frame: FrameDefinition? { group?.frame }
  public var frameBounds: IntRect? { frame.flatMap { try? coordinateTransform.bounds(width: $0.width, height: $0.height) } }
  public func framePath() throws -> VectorPath? { try frame?.path().transformed(coordinateTransform) }
}
extension CraftDocument {
  public var hasFrames: Bool { layers.contains { $0.frame != nil } }
  public func frame(containing id: UUID) -> Layer? {
    guard let layer = layers.first(where: { $0.id == id }) else { return nil }
    return layer.frame != nil ? layer : ancestors(of: id).first { $0.frame != nil }
  }
  func validateFrames() throws {
    for layer in layers where layer.frame != nil {
      guard layer.artboard == nil else { throw CraftError.invalid("An artboard cannot also be a frame.") }
      try layer.frame!.validate(); try layer.framePath()?.validate()
      guard let bounds = layer.frameBounds else { throw CraftError.invalid("Invalid frame transform.") }; try LayerLayout.validate(bounds)
    }
  }
}
