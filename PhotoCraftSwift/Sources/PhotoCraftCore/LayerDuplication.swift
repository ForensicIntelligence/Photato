import Foundation

/// Copies editable layer subtrees without involving the system clipboard.
public enum LayerDuplication {
  public static func roots(in document: CraftDocument, selected: Set<UUID>) throws -> [Layer] {
    guard !selected.isEmpty, selected.isSubset(of: Set(document.layers.map(\.id))) else {
      throw CraftError.invalid("Select existing layers to duplicate.")
    }
    return document.layers.filter {
      selected.contains($0.id)
        && !document.ancestors(of: $0.id).contains { selected.contains($0.id) }
    }
  }

  public static func validateName(_ name: String?) throws {
    if let name,
      name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || name.utf16.count > 65_535
    {
      throw CraftError.invalid("Enter a name for the duplicate layer.")
    }
  }

  public static func canDuplicate(in document: CraftDocument, selected: Set<UUID>) -> Bool {
    guard let roots = try? roots(in: document, selected: selected) else { return false }
    let count = roots.reduce(0) { $0 + document.subtreeIDs($1.id).count }
    return document.layers.count + count <= 512
      && roots.allSatisfy { $0.parentID.map { !document.isLocked($0) } ?? true }
  }

  static func duplicate(in document: inout CraftDocument, selected: Set<UUID>, name: String?) throws
  {
    let roots = try roots(in: document, selected: selected)
    try validateName(name)
    guard name == nil || roots.count == 1 else {
      throw CraftError.invalid("Rename one duplicate at a time.")
    }
    guard canDuplicate(in: document, selected: selected) else {
      throw CraftError.invalid("Unlock the parent group or free space below the 512-layer limit.")
    }
    var candidate = document
    var active: UUID?
    for root in roots {
      try Task.checkCancellation()
      let ids = document.subtreeIDs(root.id)
      let mapping = Dictionary(uniqueKeysWithValues: ids.map { ($0, UUID()) })
      let copies = document.layers.filter { ids.contains($0.id) }.map { original in
        var copy = original
        copy.id = mapping[original.id]!
        if let parent = original.parentID, let replacement = mapping[parent] {
          copy.parentID = replacement
        }
        if original.id == root.id { copy.name = name ?? original.name + " copy" }
        return copy
      }
      let index = candidate.layers.firstIndex { $0.id == root.id }!
      candidate.layers.insert(contentsOf: copies, at: index + 1)
      if let oldActive = document.activeLayerID, let newActive = mapping[oldActive] {
        active = newActive
      }
      candidate.activeLayerID = active ?? mapping[root.id]
    }
    try candidate.validate()
    document = candidate
  }

  /// Document coordinates are retained. Different-profile conversion needs an explicit
  /// color-management policy; never reinterpret those samples silently.
  static func transfer(
    from source: CraftDocument, selected: Set<UUID>, name: String?, into target: inout CraftDocument
  ) throws {
    try source.validate()
    try validateName(name)
    let roots = try roots(in: source, selected: selected)
    guard name == nil || roots.count == 1 else {
      throw CraftError.invalid("Rename one duplicate at a time.")
    }
    guard source.colorSpace == target.colorSpace, source.sourceICC == target.sourceICC else {
      throw CraftError.unsupported(
        "Duplicate between documents with matching color profiles. Profile conversion is not yet supported."
      )
    }
    let ids = roots.reduce(into: Set<UUID>()) { $0.formUnion(source.subtreeIDs($1.id)) }
    guard target.layers.count + ids.count <= 512 else {
      throw CraftError.invalid("Layer limit reached.")
    }
    let parent: UUID?
    let insertion: Int
    if let index = target.activeIndex {
      let active = target.layers[index]
      parent = active.isGroup ? active.id : active.parentID
      insertion = active.isGroup ? index : index + 1
    } else {
      parent = nil
      insertion = target.layers.count
    }
    if let parent, target.isLocked(parent) {
      throw CraftError.invalid("Unlock the destination group before duplicating layers.")
    }
    var candidate = target
    let mapping = Dictionary(uniqueKeysWithValues: ids.map { ($0, UUID()) })
    let rootIDs = Set(roots.map(\.id))
    var patterns: [String: String] = [:]
    var copies: [Layer] = []
    for original in source.layers where ids.contains(original.id) {
      try Task.checkCancellation()
      var copy = original
      copy.id = mapping[original.id]!
      copy.parentID = original.parentID.flatMap { mapping[$0] } ?? parent
      if rootIDs.contains(original.id) {
        copy.name = name ?? original.name
        // An external clipping base is not part of this independent transfer.
        if original.isClipped, let base = source.clippingBase(for: original.id),
          !ids.contains(base.id)
        {
          copy.clipped = false
        }
      }
      switch copy.content {
      case .raster(let surface): copy.content = .raster(try surface.converted(to: target.depth))
      case .patternFill(var fill):
        if patterns[fill.patternID] == nil {
          guard let pattern = source.pattern(fill.patternID) else {
            throw CraftError.invalid("Missing source pattern.")
          }
          patterns[fill.patternID] = try candidate.installPattern(pattern)
        }
        fill.patternID = patterns[fill.patternID]!
        copy.content = .patternFill(fill)
      case .adjustment(.gradientMap) where target.depth == .f32:
        throw CraftError.unsupported("Gradient Map layers require an 8- or 16-bit destination.")
      default: break
      }
      if let mask = copy.mask { copy.mask = try mask.converted(to: target.depth) }
      copies.append(copy)
    }
    candidate.layers.insert(contentsOf: copies, at: insertion)
    candidate.activeLayerID =
      source.activeLayerID.flatMap { mapping[$0] } ?? roots.last.flatMap { mapping[$0.id] }
    try candidate.validate()
    target = candidate
  }

  public static func newDocument(
    from source: CraftDocument, selected: Set<UUID>, layerName: String? = nil, documentName: String
  ) throws -> CraftDocument {
    try validateName(documentName)
    var target = try CraftDocument(
      width: source.width, height: source.height, depth: source.depth, name: documentName)
    target.layers = []
    target.activeLayerID = nil
    target.colorSpace = source.colorSpace
    target.sourceICC = source.sourceICC
    target.resolution = source.resolution
    try transfer(from: source, selected: selected, name: layerName, into: &target)
    return target
  }
}
