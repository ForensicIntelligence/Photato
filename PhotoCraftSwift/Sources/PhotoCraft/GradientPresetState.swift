import Foundation
import PhotoCraftCore
import PhotoCraftImaging

indirect enum GradientLibraryNode: Codable, Equatable, Identifiable, Sendable {
  case preset(UUID)
  case folder(UUID, String, [GradientLibraryNode])
  var id: UUID {
    switch self {
    case .preset(let id), .folder(let id, _, _): id
    }
  }
  var children: [Self]? {
    if case .folder(_, _, let children) = self { return children }
    return nil
  }
  func contains(_ id: UUID) -> Bool {
    self.id == id || children?.contains { $0.contains(id) } == true
  }
}

/// Identity and full-precision Swift controls live alongside the interchange descriptors.
/// This keeps a native save from quantizing stops to GRD's 1/4096 and 1/100 grids.
struct GradientPresetState: Equatable, Sendable {
  static let maxBytes = 64 * 1024 * 1024
  var library = GRDLibrary([])
  var presetIDs: [UUID] = []
  var nodes: [GradientLibraryNode] = []
  var selected: Set<UUID> = []
  var activePreset: UUID?
  var importedSources: [UUID: Data] = [:]
  var presets: [UUID: GRDPreset] {
    Dictionary(uniqueKeysWithValues: zip(presetIDs, library.presets))
  }
  func node(_ id: UUID) -> GradientLibraryNode? {
    func find(_ nodes: [GradientLibraryNode]) -> GradientLibraryNode? {
      for node in nodes {
        if node.id == id { return node }
        if let found = find(node.children ?? []) { return found }
      }
      return nil
    }
    return find(nodes)
  }
  func name(_ id: UUID) -> String? {
    if case .folder(_, let name, _) = node(id) { return name }
    return presets[id]?.name
  }
  static func builtins() -> Self {
    var state = Self()
    state.library = GRDLibrary([.foregroundToBackground, .foregroundToTransparent, .blackToWhite])
    state.presetIDs = state.library.presets.map { _ in UUID() }
    state.nodes = [.folder(UUID(), "Basics", state.presetIDs.map(GradientLibraryNode.preset))]
    state.activePreset = state.presetIDs.first
    state.selected = Set(state.presetIDs.prefix(1))
    try! state.rebuild()
    return state
  }
  mutating func rebuild(pruning: Bool = false) throws {
    guard presetIDs.count == library.presets.count, Set(presetIDs).count == presetIDs.count,
      presetIDs.count <= GRDCodec.maxPresets
    else { throw CraftError.invalid("Invalid gradient library records.") }
    let records = presets
    var ids: [UUID] = []
    var all = Set<UUID>()
    var entries: [GRDPreset] = []
    func visit(_ nodes: [GradientLibraryNode], depth: Int) throws -> [GRDPresetNode] {
      guard depth <= 64 else { throw CraftError.invalid("Gradient groups are too deeply nested.") }
      return try nodes.map { node in
        guard all.insert(node.id).inserted, all.count <= 20_000 else {
          throw CraftError.invalid("Duplicate or excessive gradient library entries.")
        }
        switch node {
        case .preset(let id):
          guard let entry = records[id] else {
            throw CraftError.invalid("Missing gradient preset.")
          }
          try entry.gradient?.validate()
          let index = entries.count
          ids.append(id)
          entries.append(entry)
          return .preset(index)
        case .folder(_, let name, let children):
          try Self.validateName(name)
          return .group(name, try visit(children, depth: depth + 1))
        }
      }
    }
    let hierarchy = try visit(nodes, depth: 0)
    guard pruning || ids.count == presetIDs.count else {
      throw CraftError.invalid("Orphaned gradient preset.")
    }
    library.presets = entries
    library.hierarchy = hierarchy
    presetIDs = ids
    selected.formIntersection(all)
    if let activePreset, !ids.contains(activePreset) { self.activePreset = nil }
    importedSources = importedSources.filter { all.contains($0.key) }
  }
  static func validateName(_ name: String) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf16.count <= 65_535
    else { throw CraftError.invalid("Enter a gradient or group name.") }
  }
  private mutating func insert(
    _ new: [GradientLibraryNode], into parent: UUID?, before: UUID? = nil
  ) throws {
    var found = parent == nil
    func adding(_ children: inout [GradientLibraryNode]) throws {
      let at: Int
      if let before {
        guard let i = children.firstIndex(where: { $0.id == before }) else {
          throw CraftError.invalid("The destination gradient entry no longer exists.")
        }
        at = i
      } else {
        at = children.count
      }
      children.insert(contentsOf: new, at: at)
    }
    func visit(_ nodes: inout [GradientLibraryNode]) throws {
      for i in nodes.indices {
        if case .folder(let id, let name, var children) = nodes[i] {
          if id == parent {
            try adding(&children)
            found = true
          } else {
            try visit(&children)
          }
          nodes[i] = .folder(id, name, children)
        }
      }
    }
    if parent == nil { try adding(&nodes) } else { try visit(&nodes) }
    guard found else {
      throw CraftError.invalid("The destination gradient group no longer exists.")
    }
  }
  @discardableResult mutating func add(_ gradient: GradientDefinition, into parent: UUID?) throws
    -> UUID
  {
    try gradient.validate()
    try Self.validateName(gradient.name)
    let id = UUID()
    library.presets.append(GRDPreset(gradient))
    presetIDs.append(id)
    try insert([.preset(id)], into: parent)
    selected = [id]
    activePreset = id
    try rebuild()
    return id
  }
  @discardableResult mutating func group(_ name: String, into parent: UUID?) throws -> UUID {
    try Self.validateName(name)
    let id = UUID()
    try insert([.folder(id, name, [])], into: parent)
    selected = [id]
    try rebuild()
    return id
  }
  mutating func rename(_ id: UUID, to name: String) throws {
    try Self.validateName(name)
    guard node(id) != nil else { throw CraftError.invalid("Gradient entry no longer exists.") }
    if let i = presetIDs.firstIndex(of: id) {
      library.presets[i] = try library.presets[i].renamed(name)
    }
    func visit(_ nodes: inout [GradientLibraryNode]) {
      for i in nodes.indices {
        if case .folder(let key, let oldName, var children) = nodes[i] {
          visit(&children)
          nodes[i] = .folder(key, key == id ? name : oldName, children)
        }
      }
    }
    visit(&nodes)
    try rebuild()
  }
  mutating func remove(_ ids: Set<UUID>) throws {
    func removing(_ nodes: [GradientLibraryNode]) -> [GradientLibraryNode] {
      nodes.compactMap { node in
        guard !ids.contains(node.id) else { return nil }
        if case .folder(let id, let name, let children) = node {
          return .folder(id, name, removing(children))
        }
        return node
      }
    }
    nodes = removing(nodes)
    try rebuild(pruning: true)
  }
  /// Preserve display order, and move a selected ancestor only once.
  func roots(for ids: Set<UUID>) -> [GradientLibraryNode] {
    func visit(_ nodes: [GradientLibraryNode]) -> [GradientLibraryNode] {
      nodes.flatMap { ids.contains($0.id) ? [$0] : visit($0.children ?? []) }
    }
    return visit(nodes)
  }
  mutating func move(_ ids: Set<UUID>, into parent: UUID?, before: UUID? = nil) throws {
    let moving = roots(for: ids)
    guard !moving.isEmpty else { return }
    guard
      !moving.contains(where: { parent.map($0.contains) == true || before.map($0.contains) == true }
      )
    else {
      throw CraftError.invalid("A gradient group cannot be moved inside itself.")
    }
    // Detach without pruning records; rebuild once both sides of the move are complete.
    let oldRecords = library.presets
    let oldIDs = presetIDs
    let sources = importedSources
    let oldActive = activePreset
    try remove(Set(moving.map(\.id)))
    library.presets = oldRecords
    presetIDs = oldIDs
    importedSources = sources
    activePreset = oldActive
    try insert(moving, into: parent, before: before)
    selected = Set(moving.map(\.id))
    try rebuild()
  }
  mutating func duplicate(_ ids: Set<UUID>, into parent: UUID?) throws {
    let originals = presets
    func copy(_ node: GradientLibraryNode) -> GradientLibraryNode {
      let id = UUID()
      switch node {
      case .preset(let old):
        library.presets.append(originals[old]!)
        presetIDs.append(id)
        return .preset(id)
      case .folder(_, let name, let children): return .folder(id, name, children.map(copy))
      }
    }
    let copies = roots(for: ids).map(copy)
    try insert(copies, into: parent)
    selected = Set(copies.map(\.id))
    try rebuild()
  }
  @discardableResult mutating func install(_ data: Data, name: String, into parent: UUID?) throws
    -> UUID
  {
    let imported = try GRDCodec.read(data)
    let ids = imported.presets.map { _ in UUID() }
    func nodes(_ input: [GRDPresetNode]) -> [GradientLibraryNode] {
      input.map { node in
        switch node {
        case .preset(let index): .preset(ids[index])
        case .group(let name, let children): .folder(UUID(), name, nodes(children))
        }
      }
    }
    let id = UUID()
    try Self.validateName(name)
    library.presets.append(contentsOf: imported.presets)
    presetIDs.append(contentsOf: ids)
    try insert([.folder(id, name, nodes(imported.hierarchy))], into: parent)
    importedSources[id] = data
    selected = [id]
    try rebuild()
    return id
  }
  func exported(_ selected: Set<UUID>? = nil) throws -> Data {
    var next = self
    if let selected {
      next.nodes = roots(for: selected)
      if next.nodes.count == 1, let source = importedSources[next.nodes[0].id],
        let children = next.nodes[0].children
      {
        var imported = try GRDCodec.read(source)
        next.nodes = children
        try next.rebuild(pruning: true)
        imported.presets = next.library.presets
        imported.hierarchy = next.library.hierarchy
        return try GRDCodec.write(imported)
      }
      try next.rebuild(pruning: true)
    }
    return try GRDCodec.write(next.library)
  }
  private struct FlatNode: Codable {
    var id: UUID
    var depth: Int
    var folderName: String?
  }
  private struct Archive: Codable {
    var version = 1
    var grd: Data?
    var presetIDs: [UUID]
    var nodes: [FlatNode]
    var selected: Set<UUID>
    var activePreset: UUID?
    var precise: [UUID: GradientDefinition]
    var importedSources: [UUID: Data]
  }
  func encoded() throws -> Data {
    var validated = self
    try validated.rebuild()
    var flat: [FlatNode] = []
    func flatten(_ nodes: [GradientLibraryNode], depth: Int) {
      for node in nodes {
        switch node {
        case .preset(let id): flat.append(.init(id: id, depth: depth))
        case .folder(let id, let name, let children):
          flat.append(.init(id: id, depth: depth, folderName: name))
          flatten(children, depth: depth + 1)
        }
      }
    }
    flatten(validated.nodes, depth: 0)
    let archive = Archive(
      grd: validated.library.presets.isEmpty ? nil : try GRDCodec.write(validated.library),
      presetIDs: validated.presetIDs, nodes: flat, selected: validated.selected,
      activePreset: validated.activePreset,
      precise: Dictionary(
        uniqueKeysWithValues: zip(presetIDs, library.presets).compactMap { id, preset in
          preset.gradient.map { (id, $0) }
        }), importedSources: importedSources)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(archive)
    guard data.count <= Self.maxBytes else {
      throw CraftError.invalid("Gradient library exceeds 64 MiB.")
    }
    return data
  }
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= maxBytes else {
      throw CraftError.invalid("Gradient library exceeds 64 MiB.")
    }
    let archive = try PropertyListDecoder().decode(Archive.self, from: data)
    guard archive.version == 1 else {
      throw CraftError.unsupported("Unsupported gradient library version.")
    }
    var state = Self()
    state.library = try archive.grd.map(GRDCodec.read) ?? GRDLibrary([])
    guard archive.nodes.count <= 20_000, archive.nodes.allSatisfy({ (0...64).contains($0.depth) })
    else {
      throw CraftError.invalid("Invalid gradient library hierarchy.")
    }
    var at = 0
    func tree(depth: Int) throws -> [GradientLibraryNode] {
      var nodes: [GradientLibraryNode] = []
      while at < archive.nodes.count, archive.nodes[at].depth >= depth {
        let flat = archive.nodes[at]
        guard flat.depth == depth else {
          throw CraftError.invalid("Invalid gradient group nesting.")
        }
        at += 1
        if let name = flat.folderName {
          nodes.append(.folder(flat.id, name, try tree(depth: depth + 1)))
        } else {
          nodes.append(.preset(flat.id))
        }
      }
      return nodes
    }
    state.presetIDs = archive.presetIDs
    state.nodes = try tree(depth: 0)
    state.selected = archive.selected
    state.activePreset = archive.activePreset
    state.importedSources = archive.importedSources
    guard state.presetIDs.count == state.library.presets.count,
      Set(state.presetIDs).count == state.presetIDs.count,
      Set(archive.precise.keys).isSubset(of: Set(state.presetIDs))
    else {
      throw CraftError.invalid("Invalid gradient library identities.")
    }
    for i in state.presetIDs.indices {
      if let gradient = archive.precise[state.presetIDs[i]] {
        guard state.library.presets[i].gradient != nil else {
          throw CraftError.invalid("An unavailable preset cannot acquire substitute pixels.")
        }
        try gradient.validate()
        state.library.presets[i].gradient = gradient
      }
    }
    try state.rebuild()
    guard state.selected == archive.selected, state.activePreset == archive.activePreset,
      state.importedSources.count == archive.importedSources.count
    else {
      throw CraftError.invalid("Invalid gradient library references.")
    }
    for (id, source) in state.importedSources {
      guard state.node(id)?.children != nil else {
        throw CraftError.invalid("Invalid imported gradient group.")
      }
      _ = try GRDCodec.read(source)
    }
    return state
  }
}
