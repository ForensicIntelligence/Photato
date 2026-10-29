import Foundation

extension Layer {
  public var isGroup: Bool { if case .group = content { true } else { false } }
  public var isClipped: Bool { clipped ?? false }
  public var clipsBlendAsGroup: Bool { blendClippedAsGroup ?? true }
  public var group: GroupContent? { if case .group(let value) = content { value } else { nil } }
}

extension CraftDocument {
  public func children(of parent: UUID?) -> [Layer] { layers.filter { $0.parentID == parent } }
  public func ancestors(of id: UUID) -> [Layer] {
    let byID = Dictionary(layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var result: [Layer] = []
    var next = byID[id]?.parentID
    var visited: Set<UUID> = [id]
    while let key = next, visited.insert(key).inserted, let layer = byID[key] {
      result.append(layer)
      next = layer.parentID
    }
    return result
  }
  public func subtreeIDs(_ id: UUID) -> Set<UUID> {
    Set(layers.filter { $0.id == id || ancestors(of: $0.id).contains { $0.id == id } }.map(\.id))
  }
  public func isLocked(_ id: UUID) -> Bool {
    effectiveProtection(id).fullyLocks
  }
  public func isVisible(_ id: UUID) -> Bool {
    guard let layer = layers.first(where: { $0.id == id }), layer.visible, layer.opacity > 0 else {
      return false
    }
    return !ancestors(of: id).contains { !$0.visible || $0.opacity <= 0 }
  }
  public func clippingBase(for id: UUID) -> Layer? {
    guard let layer = layers.first(where: { $0.id == id }) else { return nil }
    let siblings = children(of: layer.parentID)
    guard let index = siblings.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
    return siblings[..<index].last { !$0.isClipped }
  }
  public func isClippingBase(_ id: UUID) -> Bool {
    guard let layer = layers.first(where: { $0.id == id }) else { return false }
    let siblings = children(of: layer.parentID)
    guard let i = siblings.firstIndex(where: { $0.id == id }), i + 1 < siblings.count else {
      return false
    }
    return !layer.isClipped && siblings[i + 1].isClipped
  }
  func validateHierarchy() throws {
    let byID = Dictionary(layers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for layer in layers {
      if let parent = layer.parentID, byID[parent]?.isGroup != true {
        throw CraftError.invalid("A layer's parent must be an existing group.")
      }
    }
    var ordered: [UUID] = []
    var visited = Set<UUID>()
    func walk(_ parent: UUID?, depth: Int) throws {
      guard depth <= 32 else { throw CraftError.invalid("Groups may be nested at most 32 levels.") }
      for layer in children(of: parent) {
        guard visited.insert(layer.id).inserted else {
          throw CraftError.invalid("Cyclic layer group.")
        }
        if layer.isGroup { try walk(layer.id, depth: depth + 1) }
        ordered.append(layer.id)
      }
    }
    try walk(nil, depth: 0)
    guard ordered == layers.map(\.id) else {
      throw CraftError.invalid("Layer groups must be contiguous, ordered, and free of cycles.")
    }
  }

  /// Move a complete subtree to a sibling position (bottom to top) in another group.
  mutating func relocate(_ id: UUID, parent: UUID?, position: Int) throws {
    guard layers.contains(where: { $0.id == id }), !isLocked(id) else {
      throw CraftError.invalid("Unlock the layer and its parent groups before moving it.")
    }
    let ids = subtreeIDs(id)
    guard
      parent == nil
        || (layers.contains { $0.id == parent && $0.isGroup }
          && !ids.contains(parent!) && !isLocked(parent!))
    else {
      throw CraftError.invalid("A group cannot be moved inside itself or a locked group.")
    }
    var block = layers.filter { ids.contains($0.id) }
    block[block.count - 1].parentID = parent
    layers.removeAll { ids.contains($0.id) }
    let siblings = children(of: parent)
    let insertion: Int
    if position < siblings.count {
      let next = siblings[max(0, position)]
      let nextIDs = subtreeIDs(next.id)
      insertion = layers.firstIndex { nextIDs.contains($0.id) }!
    } else if let parent {
      insertion = layers.firstIndex { $0.id == parent }!
    } else {
      insertion = layers.count
    }
    layers.insert(contentsOf: block, at: insertion)
  }
}
