import Foundation

public struct SmartFilterTransferRequest: Codable, Equatable, Sendable {
  public enum Part: String, Codable, CaseIterable, Sendable { case stack, mask }
  public var sourceLayerID: UUID
  public var targetLayerID: UUID
  public var part: Part
  public var copy: Bool
  public init(sourceLayerID: UUID, targetLayerID: UUID, part: Part, copy: Bool) {
    self.sourceLayerID = sourceLayerID; self.targetLayerID = targetLayerID
    self.part = part; self.copy = copy
  }
  public var title: String { "\(copy ? "Copy" : "Move") \(part == .stack ? "Smart Filters" : "Filter Mask")" }

  public func command(in document: CraftDocument) throws -> Command {
    try Task.checkCancellation(); try document.validate()
    guard document.colorMode == .rgb, sourceLayerID != targetLayerID,
      let source = document.layers.first(where: { $0.id == sourceLayerID }),
      let target = document.layers.first(where: { $0.id == targetLayerID }),
      source.smartObject != nil, target.smartObject != nil,
      let sourceStack = source.smartFilters,
      !document.isImageLocked(targetLayerID), copy || !document.isImageLocked(sourceLayerID)
    else { throw CraftError.invalid("Choose distinct Smart Objects and unlock every destination or moved source.") }
    var targetStack = target.smartFilters ?? SmartFilterStack()
    var remaining: SmartFilterStack? = sourceStack
    switch part {
    case .stack:
      guard !sourceStack.filters.isEmpty,
        !sourceStack.filters.contains(where: { $0.filter.kind == .lensBlur }),
        targetStack.filters.count + sourceStack.filters.count <= SmartFilterStack.maximumFilters
      else { throw CraftError.unsupported("The source stack is empty, contains unsupported Lens Blur, or would exceed the filter limit.") }
      if target.smartFilters == nil {
        targetStack.enabled = sourceStack.enabled
        targetStack.mask = sourceStack.mask
        targetStack.maskProperties = sourceStack.maskProperties
      }
      var used = Set(targetStack.filters.map(\.id))
      for original in sourceStack.filters {
        var item = original
        if copy || used.contains(item.id) {
          repeat { item.id = UUID() } while used.contains(item.id)
        }
        used.insert(item.id); targetStack.filters.append(item)
      }
      remaining = nil
    case .mask:
      guard let mask = sourceStack.mask, !targetStack.filters.isEmpty else {
        throw CraftError.invalid("Choose an existing filter mask and a destination Smart Filter stack.")
      }
      targetStack.mask = mask
      targetStack.maskProperties = sourceStack.maskProperties
      remaining?.mask = nil
    }
    var result = document
    // Primitive stack edits perform their normal applicability/render validation.
    // Only the fully prepared result is published, so a second failure cannot
    // leave a move half completed.
    try Command.smartFilters(targetLayerID, targetStack).apply(to: &result)
    if !copy { try Command.smartFilters(sourceLayerID, remaining).apply(to: &result) }
    try Task.checkCancellation(); try result.validate()
    let recorded = RecordedSmartFilterTransfer(self, in: document)
    return .preparedAction(.init(source: document, result: result, title: title,
      recording: .smartFilterTransfer(recorded)))
  }
}

/// Semantic source/destination references let the same operation replay on a
/// different document without embedding foreign layer UUIDs or mask snapshots.
public struct RecordedSmartFilterTransfer: Codable, Equatable, Sendable {
  public var source: ActionLayerTarget
  public var target: ActionLayerTarget
  public var part: SmartFilterTransferRequest.Part
  public var copy: Bool
  public init(_ request: SmartFilterTransferRequest, in document: CraftDocument) {
    source = .init(request.sourceLayerID, in: document, preferActive: false)
    target = .init(request.targetLayerID, in: document, preferActive: false)
    part = request.part; copy = request.copy
  }
  public func command(in document: CraftDocument) throws -> Command {
    try SmartFilterTransferRequest(sourceLayerID: source.resolve(in: document),
      targetLayerID: target.resolve(in: document), part: part, copy: copy).command(in: document)
  }
}
