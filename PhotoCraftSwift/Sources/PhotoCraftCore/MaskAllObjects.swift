import Foundation

/// One independently detected instance in canvas coordinates, not a component of a union mask.
public struct DetectedObjectMask: Sendable {
  public let instanceID: Int
  public let mask: SelectionMask
  public init(instanceID: Int, mask: SelectionMask) { self.instanceID = instanceID; self.mask = mask }
}

public struct MaskAllObjectsEdit: Sendable {
  public static let maximumObjects = 64
  public static let maximumMaskPixels = 16_777_216
  public let layerID: UUID
  public let objects: [DetectedObjectMask]
  public let groupIDs: [UUID]
  public init(layerID: UUID, objects: [DetectedObjectMask]) {
    self.layerID = layerID; self.objects = objects.sorted { $0.instanceID < $1.instanceID }
    groupIDs = objects.map { _ in UUID() }
  }
  public static func checkBudget(width: Int, height: Int, count: Int) throws {
    guard width > 0, height > 0, count > 0, count <= maximumObjects,
      width <= maximumMaskPixels / height / count else {
      throw CraftError.unsupported("Mask All Objects requires 1–64 objects and at most 16,777,216 aggregate mask pixels. Reduce image size or mask objects individually.")
    }
    let side = Surface.tileSide, columns = (width - 1) / side + 1, rows = (height - 1) / side + 1
    guard columns <= maximumMaskPixels / side / side / rows / count else {
      throw CraftError.unsupported("Object mask tile storage would exceed 256 MiB. Reduce image size or mask objects individually.")
    }
  }
  public static func checkTarget(_ original: CraftDocument, layerID: UUID) throws {
    guard let layer = original.layers.first(where: { $0.id == layerID }), case .raster = layer.content else {
      throw CraftError.invalid("Select a pixel layer for Mask All Objects.")
    }
    guard layer.parentID.map({ !original.isLocked($0) }) ?? true else {
      throw CraftError.invalid("Unlock the containing group before creating object masks.")
    }
    guard original.layers.count < LayerLimits.maximumLayers else { throw CraftError.invalid("Layer limit reached.") }
  }
  public func applied(to original: CraftDocument) throws -> CraftDocument {
    try Self.checkTarget(original, layerID: layerID)
    try Self.checkBudget(width: original.width, height: original.height, count: objects.count)
    guard original.layers.count + objects.count <= LayerLimits.maximumLayers,
      Set(objects.map(\.instanceID)).count == objects.count,
      objects.allSatisfy({ $0.instanceID > 0 && $0.mask.width == original.width && $0.mask.height == original.height && $0.mask.bounds != nil }),
      groupIDs.allSatisfy({ id in !original.layers.contains { $0.id == id } }) else {
      throw CraftError.invalid("Invalid object masks or insufficient layer capacity.")
    }
    let source = original.layers.first { $0.id == layerID }!
    // Insert after the entire clipping family; inserting between its base and clips
    // would silently change the original image even though the new groups are empty.
    let siblings = original.children(of: source.parentID)
    var last = siblings.firstIndex { $0.id == layerID }!
    while last + 1 < siblings.count && siblings[last + 1].isClipped { last += 1 }
    let insertion = original.layers.firstIndex { $0.id == siblings[last].id }! + 1
    var groups: [Layer] = []
    for (index, object) in objects.enumerated() {
      try Task.checkCancellation()
      var group = Layer(name: "Object \(index + 1)", content: .group(.init(passThrough: true)))
      group.id = groupIDs[index]; group.parentID = source.parentID
      var mask = try Surface(width: original.width, height: original.height, depth: original.depth, fill: .black)
      for y in 0..<original.height {
        try Task.checkCancellation()
        for x in 0..<original.width {
          let value = Float(object.mask.byte(at:y * original.width + x)) / 255
          if value > 0 { mask.setPixel(x: x, y: y, Pixel(value, value, value)) }
        }
      }
      group.mask = mask
      var properties = MaskProperties(); properties.outside = 0
      group.maskProperties = properties
      groups.append(group)
    }
    var result = original
    result.layers.insert(contentsOf: groups, at: insertion)
    result.activeLayerID = groups.last!.id
    try result.validate()
    return result
  }
}
