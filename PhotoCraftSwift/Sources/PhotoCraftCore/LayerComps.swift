import Foundation

/// A comp records layer properties, never a second copy of the layer pixels.
public struct LayerCompOptions: Codable, Equatable, Sendable {
  public var visibility: Bool
  public var position: Bool
  public var appearance: Bool
  public var smartObjects: Bool?
  public var recordsSmartObjects: Bool { smartObjects == true }
  public init(visibility: Bool = true, position: Bool = true, appearance: Bool = true, smartObjects: Bool = false) {
    self.visibility = visibility; self.position = position; self.appearance = appearance
    self.smartObjects = smartObjects ? true : nil
  }
}
public struct LayerCompSmartObjectSelection: Codable, Equatable, Sendable {
  public var sourceID: UUID
  public var compID: UUID?
  public init(_ object: SmartObject) { sourceID = object.sourceID; compID = object.layerComps?.selectedID }
  public func matches(_ object: SmartObject?) -> Bool {
    object?.sourceID == sourceID && object?.layerComps?.selectedID == compID
  }
}
public struct LayerCompAppearance: Codable, Equatable, Sendable {
  public var opacity: Float
  public var blendMode: BlendMode
  public var style: LayerStyle?
  public var blendClippedAsGroup: Bool?
  public var passThrough: Bool?
  init(_ layer: Layer) {
    opacity = layer.opacity; blendMode = layer.blendMode; style = layer.style
    blendClippedAsGroup = layer.blendClippedAsGroup; passThrough = layer.group?.passThrough
  }
}
public struct LayerCompLayerState: Codable, Equatable, Sendable {
  public var layerID: UUID
  public var visible: Bool?
  public var x: Int?
  public var y: Int?
  public var translation: PathPoint?
  public var appearance: LayerCompAppearance?
  public var smartObjectSelection: LayerCompSmartObjectSelection?
  public init(_ layer: Layer, options: LayerCompOptions) {
    layerID = layer.id; visible = options.visibility ? layer.visible : nil
    x = options.position ? layer.x : nil; y = options.position ? layer.y : nil
    translation = options.position ? PathPoint(layer.affine?.tx ?? 0, layer.affine?.ty ?? 0) : nil
    appearance = options.appearance ? LayerCompAppearance(layer) : nil
    smartObjectSelection = options.recordsSmartObjects ? layer.smartObject.map(LayerCompSmartObjectSelection.init) : nil
  }
  func apply(to layer: inout Layer) {
    if let visible { layer.visible = visible }
    if let x, let y { layer.x = x; layer.y = y }
    if let translation, var affine = layer.affine {
      affine.tx = translation.x; affine.ty = translation.y; layer.affine = affine
    } else if let translation, translation.x != 0 || translation.y != 0 {
      layer.affine = .init(a: 1, b: 0, c: 0, d: 1, tx: translation.x, ty: translation.y)
    }
    if let appearance {
      layer.opacity = appearance.opacity; layer.blendMode = appearance.blendMode
      layer.style = appearance.style; layer.blendClippedAsGroup = appearance.blendClippedAsGroup
      if var group = layer.group, let passThrough = appearance.passThrough { group.passThrough = passThrough; layer.content = .group(group) }
    }
  }
}
public struct LayerComp: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var comment: String
  public var options: LayerCompOptions
  public var layers: [LayerCompLayerState]
  public init(id: UUID = UUID(), name: String, comment: String = "", options: LayerCompOptions = .init(), document: CraftDocument) {
    self.id = id; self.name = name; self.comment = comment; self.options = options
    layers = document.layers.map { LayerCompLayerState($0, options: options) }
  }
  public func missingLayers(in document: CraftDocument) -> [UUID] {
    let present = Set(document.layers.map(\.id)); return layers.map(\.layerID).filter { !present.contains($0) }
  }
  public func matches(_ document: CraftDocument) -> Bool {
    let states = Dictionary(uniqueKeysWithValues: layers.map { ($0.layerID, $0) })
    return missingLayers(in: document).isEmpty && document.layers.allSatisfy {
      guard let state = states[$0.id] else { return false }
      return state == LayerCompLayerState($0, options: options)
    }
  }
  public func unavailableSmartObjectLayers(in document: CraftDocument) -> [UUID] {
    layers.compactMap { state in
      guard let selection = state.smartObjectSelection, let layer = document.layers.first(where: { $0.id == state.layerID }) else { return nil }
      guard let object = layer.smartObject, object.sourceID == selection.sourceID else { return state.layerID }
      if let id = selection.compID, let choices = object.layerComps, !choices.entries.contains(where: { $0.id == id }) { return state.layerID }
      return nil
    }
  }
}
public struct LayerComps: Codable, Equatable, Sendable {
  public static let maximumComps = 2048
  public static let maximumStates = 262_144
  public var comps: [LayerComp] = []
  public var appliedID: UUID?
  public var lastDocumentState: [LayerCompLayerState]?
  public init() {}
  public var estimatedBytes: Int {
    comps.reduce(0) { $0 + $1.name.utf8.count + $1.comment.utf8.count + Self.bytes($1.layers) } + Self.bytes(lastDocumentState ?? [])
  }
  public var requiresEmptyOptionsArchive: Bool { comps.contains { !$0.options.visibility && !$0.options.position && !$0.options.appearance && !$0.options.recordsSmartObjects } }
  public var requiresSmartObjectSelectionArchive: Bool {
    comps.contains { $0.options.recordsSmartObjects || $0.layers.contains { $0.smartObjectSelection != nil } } || lastDocumentState?.contains { $0.smartObjectSelection != nil } == true
  }
  static func bytes(_ states: [LayerCompLayerState]) -> Int { states.reduce(0) { $0 + 256 + ($1.smartObjectSelection == nil ? 0 : 64) + ($1.appearance?.style?.estimatedBytes ?? 0) } }
  public func validate() throws {
    guard comps.count <= Self.maximumComps, Set(comps.map(\.id)).count == comps.count,
      appliedID == nil || comps.contains(where: { $0.id == appliedID }),
      comps.reduce(0, { $0 + $1.layers.count }) + (lastDocumentState?.count ?? 0) <= Self.maximumStates,
      estimatedBytes <= 64 * 1024 * 1024 else { throw CraftError.invalid("Invalid or oversized Layer Comps.") }
    for comp in comps {
      guard !comp.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, comp.name.utf8.count <= 1024,
        comp.comment.utf8.count <= 65_536, !comp.name.contains("\0"), !comp.comment.contains("\0") else { throw CraftError.invalid("Choose a valid comp name and comment.") }
      try Self.validate(comp.layers)
      for state in comp.layers {
        guard (state.visible != nil) == comp.options.visibility,
          (comp.options.position ? (state.x != nil && state.y != nil && state.translation != nil) : (state.x == nil && state.y == nil && state.translation == nil)),
          (state.appearance != nil) == comp.options.appearance,
          state.smartObjectSelection == nil || comp.options.recordsSmartObjects else { throw CraftError.invalid("Layer Comp properties do not match its options.") }
      }
    }
    if let lastDocumentState { try Self.validate(lastDocumentState) }
  }
  static func validate(_ states: [LayerCompLayerState]) throws {
    guard states.count <= LayerLimits.maximumLayers, Set(states.map(\.layerID)).count == states.count else { throw CraftError.invalid("Invalid Layer Comp layer identifiers.") }
    for state in states {
      if let x = state.x { guard (-1_000_000...1_000_000).contains(x) else { throw CraftError.invalid("Invalid comp position.") } }
      if let y = state.y { guard (-1_000_000...1_000_000).contains(y) else { throw CraftError.invalid("Invalid comp position.") } }
      if let p = state.translation { guard p.x.isFinite, p.y.isFinite, abs(p.x) <= 1_000_000, abs(p.y) <= 1_000_000 else { throw CraftError.invalid("Invalid comp translation.") } }
      if let appearance = state.appearance {
        guard appearance.opacity.isFinite, (0...1).contains(appearance.opacity) else { throw CraftError.invalid("Invalid comp opacity.") }
        try appearance.style?.validate()
      }
    }
  }
}
public enum LayerCompCommand: Sendable {
  case capture(id: UUID, name: String, comment: String, options: LayerCompOptions)
  case update(UUID, name: String, comment: String, options: LayerCompOptions, recapture: Bool)
  case apply(UUID), restoreLast, duplicate(UUID, newID: UUID), delete([UUID]), reorder([UUID]), clear
  public var label: String {
    switch self {
    case .capture: "New Layer Comp"
    case .update: "Update Layer Comp"
    case .apply: "Apply Layer Comp"
    case .restoreLast: "Last Document State"
    case .duplicate: "Duplicate Layer Comp"
    case .delete: "Delete Layer Comps"
    case .reorder: "Reorder Layer Comps"
    case .clear: "Clear Layer Comps"
    }
  }
  public func apply(to document: inout CraftDocument, recordingBefore: CraftDocument? = nil) throws {
    try document.validate()
    if let recordingBefore { try recordingBefore.validate(); guard recordingBefore.id == document.id else { throw CraftError.invalid("Prepared comp changed document identity.") } }
    var result = document, library = document.layerComps ?? LayerComps()
    func index(_ id: UUID) throws -> Int {
      guard let i = library.comps.firstIndex(where: { $0.id == id }) else { throw CraftError.invalid("Layer Comp no longer exists.") }; return i
    }
    switch self {
    case .capture(let id, let name, let comment, let options):
      library.comps.append(.init(id: id, name: name, comment: comment, options: options, document: document))
    case .update(let id, let name, let comment, let options, let recapture):
      let i = try index(id)
      if recapture { library.comps[i] = .init(id: id, name: name, comment: comment, options: options, document: document) }
      else {
        guard library.comps[i].options == options else { throw CraftError.invalid("Recapture to change recorded properties.") }
        library.comps[i].name = name; library.comps[i].comment = comment
      }
    case .apply(let id):
      let comp = library.comps[try index(id)]
      let before = recordingBefore ?? document
      if library.appliedID == id, comp.matches(before) { return }
      try result.validatePreparedSmartChoices(comp.layers)
      library.lastDocumentState = before.layers.map { .init($0, options: .init(smartObjects: true)) }
      result.applyCompStates(comp.layers); library.appliedID = id
    case .restoreLast:
      guard let states = library.lastDocumentState else { throw CraftError.invalid("No saved document state.") }
      try result.validatePreparedSmartChoices(states)
      result.applyCompStates(states); library.appliedID = nil; library.lastDocumentState = nil
    case .duplicate(let id, let newID):
      let i = try index(id); var comp = library.comps[i]; comp.id = newID; comp.name += " copy"; library.comps.insert(comp, at: i + 1)
    case .delete(let ids):
      guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ id in library.comps.contains { $0.id == id } }) else { throw CraftError.invalid("Choose distinct existing Layer Comps.") }
      library.comps.removeAll { ids.contains($0.id) }; if let id = library.appliedID, ids.contains(id) { library.appliedID = nil }
    case .reorder(let ids):
      guard ids.count == library.comps.count, Set(ids) == Set(library.comps.map(\.id)) else { throw CraftError.invalid("Supply every Layer Comp exactly once.") }
      let all = Dictionary(uniqueKeysWithValues: library.comps.map { ($0.id, $0) }); library.comps = ids.map { all[$0]! }
    case .clear:
      if result.layerComps != nil, result.sourceMetadata?["psdResources"] != nil { result.sourceMetadata?["psdLayerCompsCleared"] = Data([1]) }
      result.layerComps = nil; try result.validate(); document = result; return
    }
    result.sourceMetadata?.removeValue(forKey: "psdLayerCompsCleared")
    try library.validate(); result.layerComps = library; try result.validate(); document = result
  }
}
extension CraftDocument {
  public var clearedSourceLayerComps: Bool { sourceMetadata?["psdLayerCompsCleared"] == Data([1]) }
  public var requiresLayerComp82Archive: Bool { layerComps?.requiresEmptyOptionsArchive == true || clearedSourceLayerComps }
  func validatePreparedSmartChoices(_ states: [LayerCompLayerState]) throws {
    for state in states {
      guard let choice = state.smartObjectSelection, let layer = layers.first(where: { $0.id == state.layerID }) else { continue }
      guard choice.matches(layer.smartObject) else { throw CraftError.invalid("Prepare the current Smart Object source choice before applying this Layer Comp. A changed source requires review or recapture.") }
    }
  }
  mutating func applyCompStates(_ states: [LayerCompLayerState]) {
    let byID = Dictionary(uniqueKeysWithValues: states.map { ($0.layerID, $0) })
    for i in layers.indices { byID[layers[i].id]?.apply(to: &layers[i]) }
  }
  public func layerCompDocument(_ id: UUID) throws -> CraftDocument {
    var result = self; try LayerCompCommand.apply(id).apply(to: &result); return result
  }
}
