import Foundation

public enum LayerStackOperation: String, Codable, CaseIterable, Sendable {
  case bringToFront, bringForward, sendBackward, sendToBack, reverse
  public var title: String {
    switch self {
    case .bringToFront: "Bring to Front"
    case .bringForward: "Bring Forward"
    case .sendBackward: "Send Backward"
    case .sendToBack: "Send to Back"
    case .reverse: "Reverse"
    }
  }
}

public struct LayerStackOrderRequest: Codable, Equatable, Sendable {
  public var layerIDs: [UUID]
  public var operation: LayerStackOperation
  public init(layerIDs: [UUID], operation: LayerStackOperation) {
    self.layerIDs = layerIDs; self.operation = operation
  }
  public func validate() throws {
    guard !layerIDs.isEmpty, layerIDs.count <= LayerLimits.maximumLayers,
      Set(layerIDs).count == layerIDs.count else {
      throw CraftError.invalid("Choose distinct existing layers to arrange.")
    }
  }
}

/// Reorder sibling roots without changing any layer, parent, surface or resource.
public enum LayerStackOrder {
  public static func order(_ request: LayerStackOrderRequest, in document: CraftDocument) throws -> [UUID] {
    try request.validate(); try document.validateHierarchy()
    let index = LayerHierarchyIndex(document), requested = Set(request.layerIDs)
    guard requested.isSubset(of: Set(index.byID.keys)) else { throw CraftError.invalid("An arranged layer is unavailable.") }
    let roots = document.layers.filter { requested.contains($0.id) && index.ancestors(of: $0.id).allSatisfy { !requested.contains($0.id) } }
    guard roots.allSatisfy({ !$0.isBackground && !index.effectiveProtection($0.id).fullyLocks }) else {
      throw CraftError.invalid("Convert Background or unlock the layer and its parent groups before arranging it.")
    }
    var children = Dictionary(grouping: document.layers, by: \.parentID).mapValues { $0.map(\.id) }
    for (parent, members) in Dictionary(grouping: roots, by: \.parentID) {
      try Task.checkCancellation()
      let selected = Set(members.map(\.id)), original = children[parent] ?? []
      var values = original
      let minimum = original.first.flatMap { index.byID[$0] }?.isBackground == true ? 1 : 0
      switch request.operation {
      case .bringToFront:
        values = original.filter { !selected.contains($0) } + original.filter { selected.contains($0) }
      case .sendToBack:
        values = Array(original.prefix(minimum)) + original.dropFirst(minimum).filter { selected.contains($0) }
          + original.dropFirst(minimum).filter { !selected.contains($0) }
      case .bringForward:
        if values.count >= 2 {
          for i in stride(from: values.count - 2, through: 0, by: -1)
            where selected.contains(values[i]) && !selected.contains(values[i + 1]) {
            values.swapAt(i, i + 1)
          }
        }
      case .sendBackward:
        if values.count > minimum + 1 {
          for i in (minimum + 1)..<values.count
            where selected.contains(values[i]) && !selected.contains(values[i - 1]) {
            values.swapAt(i, i - 1)
          }
        }
      case .reverse:
        let positions = original.indices.filter { selected.contains(original[$0]) }
        for (position, value) in zip(positions, positions.reversed().map { original[$0] }) { values[position] = value }
      }
      children[parent] = values
    }
    var result: [UUID] = []
    func append(_ parent: UUID?) throws {
      for id in children[parent] ?? [] {
        try Task.checkCancellation()
        if index.byID[id]?.isGroup == true { try append(id) }
        result.append(id)
      }
    }
    try append(nil)
    guard result.count == document.layers.count, Set(result) == Set(index.byID.keys) else {
      throw CraftError.invalid("An arranged hierarchy must retain every layer exactly once.")
    }
    return result
  }
  public static func apply(_ request: LayerStackOrderRequest, to document: inout CraftDocument) throws {
    let ordered = try order(request, in: document)
    let byID = Dictionary(uniqueKeysWithValues: document.layers.map { ($0.id, $0) })
    var candidate = document; candidate.layers = try ordered.map { id in
      guard let layer = byID[id] else { throw CraftError.invalid("An arranged layer is unavailable.") }
      return layer
    }
    try candidate.validateHierarchy(); document = candidate
  }
}
