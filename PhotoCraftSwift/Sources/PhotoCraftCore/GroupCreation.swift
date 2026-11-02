import Foundation

public struct NewLayerGroupOptions: Equatable, Sendable, Codable {
  public var name: String
  public var color: LayerColorLabel = .none
  /// Nil represents Pass Through, the default group mode.
  public var mode: BlendMode?
  public var opacity: Float = 1
  public init(name: String) { self.name = name }
  public func layer() throws -> Layer {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf16.count <= 65_535, opacity.isFinite, (0...1).contains(opacity)
    else { throw CraftError.invalid("Enter a group name and an opacity from 0% to 100%.") }
    var group = Layer(name: name, content: .group(GroupContent(passThrough: mode == nil)))
    group.blendMode = mode ?? .normal
    group.opacity = opacity
    if color != .none { group.colorLabel = color }
    return group
  }
}

extension CraftDocument {
  /// Build and validate the hierarchy before publishing any mutation, including
  /// the case where adding a group exceeds the nesting limit.
  mutating func createLayerGroup(
    _ options: NewLayerGroupOptions, children requested: [UUID], below: Bool
  ) throws {
    guard layers.count < LayerLimits.maximumLayers else { throw CraftError.invalid("Layer limit reached.") }
    var group = try options.layer()
    let requestedIDs = Set(requested)
    guard requestedIDs.allSatisfy({ key in layers.contains { $0.id == key } }) else {
      throw CraftError.invalid("Selected layer no longer exists.")
    }
    var candidate = self
    let hierarchy = LayerHierarchyIndex(self)
    let roots = layers.filter {
      requestedIDs.contains($0.id)
        && !hierarchy.ancestors(of: $0.id).contains { requestedIDs.contains($0.id) }
    }
    if roots.isEmpty {
      try candidate.insertNewLayer(group, below: below)
    } else {
      guard !below else {
        throw CraftError.invalid("Below placement applies to an empty group.")
      }
      let parent = roots[0].parentID
      guard roots.allSatisfy({ $0.parentID == parent }), parent.map({ !isLocked($0) }) ?? true else {
        throw CraftError.invalid("Select layers with the same unlocked parent to group them.")
      }
      group.parentID = parent
      let rootIDs = Set(roots.map(\.id))
      guard
        roots.allSatisfy({ layer in
          !layer.isClipped || clippingBase(for: layer.id).map { rootIDs.contains($0.id) } == true
        })
      else {
        throw CraftError.invalid(
          "Include the clipping base in the group selection, or release the clipping mask first.")
      }
      let ids = hierarchy.subtreeIDs(Set(roots.map(\.id)))
      let last = layers.lastIndex { ids.contains($0.id) }!
      let insertion = layers[..<last].filter { !ids.contains($0.id) }.count
      var contents = layers.filter { ids.contains($0.id) }
      for i in contents.indices where rootIDs.contains(contents[i].id) {
        contents[i].parentID = group.id
      }
      candidate.layers.removeAll { ids.contains($0.id) }
      candidate.layers.insert(contentsOf: contents + [group], at: insertion)
      candidate.activeLayerID = group.id
    }
    try candidate.validateHierarchy()
    self = candidate
  }
}
