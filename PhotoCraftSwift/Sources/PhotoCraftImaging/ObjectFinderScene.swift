import Foundation
import PhotoCraftCore

public struct ObjectFinderSource: Equatable, Sendable {
  public let document: CraftDocument
  public let layerID: UUID?
  public let sampleAllLayers: Bool
  public init(_ document: CraftDocument, layerID: UUID?, sampleAllLayers: Bool) {
    var key = document
    key.selection = nil; key.selectionMask = nil; key.activeLayerID = nil
    self.document = key; self.layerID = layerID; self.sampleAllLayers = sampleAllLayers
  }
}

public struct FoundObject: Sendable {
  public let instanceID: Int
  public let mask: SelectionMask
  public let bounds: IntRect
}

public struct ObjectFinderScene: Sendable {
  public let source: ObjectFinderSource
  public let objects: [FoundObject]
  public init(source: ObjectFinderSource, masks: [DetectedObjectMask]) throws {
    try ForegroundSelection.checkSize(source.document.width, source.document.height)
    try MaskAllObjectsEdit.checkBudget(width: source.document.width, height: source.document.height, count: masks.count)
    guard Set(masks.map(\.instanceID)).count == masks.count else { throw CraftError.invalid("Duplicate object instances.") }
    self.source = source
    objects = try masks.sorted { $0.instanceID < $1.instanceID }.map {
      guard (1...255).contains($0.instanceID), $0.mask.width == source.document.width,
        $0.mask.height == source.document.height, let bounds = $0.mask.bounds else {
        throw CraftError.invalid("Invalid object instance mask.")
      }
      return FoundObject(instanceID: $0.instanceID, mask: $0.mask, bounds: bounds)
    }
  }
  public static func detect(_ document: CraftDocument, layerID: UUID?, sampleAllLayers: Bool,
    detector: any AllObjectsDetecting = VisionForegroundDetector()) async throws -> ObjectFinderScene {
    try ForegroundSelection.checkSize(document.width, document.height)
    let input = try SelectionToolPreparation.input(document, layerID: layerID, allLayers: sampleAllLayers)
    let masks = try await detector.masks(for: input)
    try Task.checkCancellation()
    return try .init(source: .init(document, layerID: layerID, sampleAllLayers: sampleAllLayers), masks: masks)
  }
  public func object(at point: PathPoint) -> FoundObject? {
    guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
      point.x < Double(source.document.width), point.y < Double(source.document.height) else { return nil }
    let x = Int(point.x), y = Int(point.y)
    // Soft-edge overlap chooses the strongest coverage. Ties retain ascending instance order.
    var best: FoundObject?, coverage: UInt8 = 127
    for object in objects where object.bounds.contains(x,y) {
      let value = object.mask.bytes[y * object.mask.width + x]
      if value > coverage { best = object; coverage = value }
    }
    return best
  }
  public func command(instanceID: Int, mode: SelectionMode, hardEdge: Bool) throws -> Command {
    guard let object = objects.first(where: { $0.instanceID == instanceID }) else { throw CraftError.invalid("Object instance no longer exists.") }
    return .selectionCoverage(try Self.coverage(object.mask, hardEdge: hardEdge), mode)
  }
  public static func coverage(_ mask: SelectionMask, hardEdge: Bool) throws -> SelectionMask {
    guard hardEdge else { return mask }
    var bytes = mask.bytes
    for y in 0..<mask.height {
      try Task.checkCancellation()
      for x in 0..<mask.width { let i = y * mask.width + x; bytes[i] = bytes[i] >= 128 ? 255 : 0 }
    }
    return try SelectionMask(width: mask.width, height: mask.height, bytes: bytes)
  }
}
