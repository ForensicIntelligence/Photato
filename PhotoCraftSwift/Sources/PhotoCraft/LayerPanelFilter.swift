import AppKit
import CryptoKit
import PhotoCraftCore

enum LayerFilterMode: String, Codable, CaseIterable, Sendable {
  case kind, name, effect, mode, attribute, color, smartObject, selected, artboard
  var title: String { self == .smartObject ? "Smart Object" : rawValue.capitalized }
}
enum LayerFilterKind: String, Codable, CaseIterable, Sendable {
  case pixel, adjustment, type, shape, smartObject
  var title: String {
    switch self { case .pixel: "Pixel layers"; case .adjustment: "Adjustment layers"
    case .type: "Type layers"; case .shape: "Shape layers"; case .smartObject: "Smart Objects" }
  }
  var symbol: String {
    switch self { case .pixel: "photo"; case .adjustment: "circle.lefthalf.filled"
    case .type: "textformat"; case .shape: "square"; case .smartObject: "square.on.square" }
  }
}
enum LayerFilterSmartKind: String, Codable, CaseIterable, Sendable {
  case library, local, modified, missing, embedded
  var title: String {
    switch self { case .library: "Linked in library"; case .local: "Linked locally"
    case .modified: "Out of date"; case .missing: "Missing"; case .embedded: "Embedded" }
  }
  var symbol: String {
    switch self { case .library: "books.vertical"; case .local: "link"
    case .modified: "exclamationmark.triangle"; case .missing: "questionmark.square.dashed"
    case .embedded: "square.on.square" }
  }
}
enum LayerFilterAttribute: String, Codable, CaseIterable, Sendable {
  case visible, notVisible, linked, notLinked, clipped, notClipped, locked, notLocked
  case layerEffects, noLayerEffects, layerMask, noLayerMask, vectorMask, noVectorMask
  case empty, notEmpty
  var title: String {
    switch self {
    case .empty: "Empty"; case .notEmpty: "Not Empty"
    case .visible: "Visible"; case .notVisible: "Not Visible"; case .linked: "Linked"; case .notLinked: "Not Linked"
    case .clipped: "Clipped"; case .notClipped: "Not Clipped"; case .locked: "Locked"; case .notLocked: "Not Locked"
    case .layerEffects: "Layer Effects"; case .noLayerEffects: "No Layer Effects"
    case .layerMask: "Layer Mask"; case .noLayerMask: "No Layer Mask"
    case .vectorMask: "Vector Mask"; case .noVectorMask: "No Vector Mask"
    }
  }
}

/// Document-local filter settings. Matching can clear view selection, never samples/history.
struct LayerPanelFilter: Codable, Equatable, Sendable {
  var enabled = true
  var mode = LayerFilterMode.kind
  var kinds: Set<LayerFilterKind> = []
  var name = ""
  var effect = LayerEffect.Kind.dropShadow
  var blend = BlendMode.normal.rawValue
  var attribute = LayerFilterAttribute.visible
  var color = LayerColorLabel.none
  var smartKinds: Set<LayerFilterSmartKind> = []
  var artboardID = ""

  var isFiltering: Bool {
    enabled && (mode == .kind ? !kinds.isEmpty : (mode == .name ? !name.isEmpty : true))
  }
  var requiresContentEvaluation: Bool { enabled && mode == .attribute && (attribute == .empty || attribute == .notEmpty) }
  func validate() throws {
    guard name.utf16.count <= 65_535, !name.contains("\0"),
      blend == "Pass Through" || BlendMode(rawValue: blend) != nil,
      artboardID.isEmpty || UUID(uuidString: artboardID) != nil else {
      throw CraftError.invalid("Invalid layer filter settings.")
    }
    guard !smartKinds.contains(.library) else {
      throw CraftError.unsupported("Library-linked artwork filtering requires the missing library integration.")
    }
  }
  func matches(_ layer: Layer, hierarchy: LayerHierarchyIndex, selected: Set<UUID>,
    linkedStatus: [UUID: LinkedArtworkStatus], emptyLayerIDs: Set<UUID>? = nil) -> Bool {
    guard isFiltering else { return true }
    switch mode {
    case .kind:
      if layer.smartObject != nil { return kinds.contains(.smartObject) }
      switch layer.content {
      case .raster: return kinds.contains(.pixel)
      case .fill, .gradientFill, .patternFill, .adjustment: return kinds.contains(.adjustment)
      case .text: return kinds.contains(.type)
      case .shape: return kinds.contains(.shape)
      case .group: return false
      }
    case .name: return layer.name.localizedCaseInsensitiveContains(name)
    case .effect: return layer.style?.effects.contains(where: { $0.kind == effect }) == true
    case .mode:
      if layer.group?.passThrough == true { return blend == "Pass Through" }
      return layer.blendMode.rawValue == blend
    case .attribute:
      let hasEffects = layer.style?.effects.isEmpty == false
      switch attribute {
      case .empty: return emptyLayerIDs?.contains(layer.id) == true
      case .notEmpty: return emptyLayerIDs.map { !$0.contains(layer.id) } ?? false
      case .visible: return layer.visible
      case .notVisible: return !layer.visible
      case .linked: return layer.linkID != nil
      case .notLinked: return layer.linkID == nil
      case .clipped: return layer.isClipped
      case .notClipped: return !layer.isClipped
      case .locked: return layer.isBackground || !layer.protection.isEmpty
      case .notLocked: return !layer.isBackground && layer.protection.isEmpty
      case .layerEffects: return hasEffects
      case .noLayerEffects: return !hasEffects
      case .layerMask: return layer.mask != nil
      case .noLayerMask: return layer.mask == nil
      case .vectorMask: return layer.vectorMask != nil
      case .noVectorMask: return layer.vectorMask == nil
      }
    case .color: return layer.colorLabel == color
    case .smartObject:
      guard let object = layer.smartObject else { return false }
      if smartKinds.isEmpty { return true }
      if object.linkedSource == nil { return smartKinds.contains(.embedded) }
      if smartKinds.contains(.local), object.linkedSource?.kind == .file { return true }
      if smartKinds.contains(.modified), linkedStatus[object.sourceID] == .modified { return true }
      return smartKinds.contains(.missing) && linkedStatus[object.sourceID] == .missing
    case .selected: return selected.contains(layer.id)
    case .artboard:
      let boards = ([layer] + hierarchy.ancestors(of: layer.id)).filter { $0.group?.artboard != nil }
      return artboardID.isEmpty ? !boards.isEmpty : boards.contains { $0.id == UUID(uuidString: artboardID) }
    }
  }
}

@MainActor extension EditorStore {
  var canChangeLayerFilter: Bool { canBeginLayerCreation && canSelectComponentTarget && historyOperation == nil }
  var layerFilterIsolated: Bool { layerPanelFilter.enabled && layerPanelFilter.mode == .selected }
  func setLayerFilter(_ value: LayerPanelFilter) throws {
    var filter = value
    if let identifier = UUID(uuidString: filter.artboardID) { filter.artboardID = identifier.uuidString }
    guard canChangeLayerFilter else { throw CraftError.invalid("Finish the current interaction before changing layer filtering.") }
    try filter.validate()
    if !filter.artboardID.isEmpty,
      !document.layers.contains(where: { $0.id.uuidString == filter.artboardID && $0.group?.artboard != nil }) {
      // A deleted existing target remains visible as a missing filter target; a new one must exist.
      guard filter.artboardID == layerPanelFilter.artboardID else { throw CraftError.invalid("The filter artboard is unavailable.") }
    }
    if filter.requiresContentEvaluation && !layerContentFilter.isResolved(in: self) {
      throw CraftError.invalid("Evaluate pixel content asynchronously before enabling this filter.")
    }
    if !filter.requiresContentEvaluation { layerContentFilter.reset() }
    if filter != layerPanelFilter { layerPanelFilter = filter; layerFilterRevision = UUID() }
    reconcileFilteredLayerSelection()

  }
  func editLayerFilter(_ update: (inout LayerPanelFilter) -> Void) {
    var candidate = displayedLayerFilter; update(&candidate)
    if candidate.requiresContentEvaluation {
      _ = layerContentFilter.start(candidate, in: self)
    } else {
      do { try setLayerFilter(candidate) } catch { self.error = error.localizedDescription }
    }
  }
  func findLayers() {
    guard canChangeLayerFilter else { return }
    editLayerFilter { $0.mode = .name; $0.enabled = true }
    reveal(LayersTab.layers); layerFilterFocusRequest += 1
  }
  func toggleLayerIsolation() {
    guard canChangeLayerFilter, layerFilterIsolated || !groupSelectionIDs.isEmpty else { return }
    editLayerFilter {
      if $0.mode == .selected && $0.enabled { $0.mode = .kind; $0.kinds = [] }
      else { $0.mode = .selected; $0.enabled = true }
    }
  }
  var displayedLayerFilter: LayerPanelFilter { layerContentFilter.candidate ?? layerPanelFilter }
  func reconcileFilteredLayerSelection() {
    guard layerPanelFilter.isFiltering,
      !layerPanelFilter.requiresContentEvaluation || layerContentFilter.isResolved(in: self) else { return }
    let visible = Set(layersInPanel().map(\.id))
    selectedLayerIDs.formIntersection(visible)
    if let active = document.activeLayerID, !visible.contains(active) {
      let replacement = document.layers.reversed().first { selectedLayerIDs.contains($0.id) }?.id
      layerContentFilter.publishingSelection = true
      session.setFilteredLayerSelection(replacement)
      layerContentFilter.publishingSelection = false
      maskEditingLayerID = nil; smartFilterMaskEditing = false; clearMaskView()
      if case .shape = pathTarget { selectPath(nil) }
      if case .vectorMask = pathTarget { selectPath(nil) }
    }
  }
  var layerFilterStatuses: [UUID: LinkedArtworkStatus] {
    linkedSourceController?.states.mapValues(\.status) ?? [:]
  }
  var layerFilterRevisionToken: String {
    let selection = groupSelectionIDs.map(\.uuidString).sorted().joined(separator: ",")
    let links = layerFilterStatuses.map { $0.key.uuidString + ":" + $0.value.rawValue }.sorted().joined(separator: ",")
    let groups = document.layers.filter(\.isGroup).map { $0.id.uuidString + ":" + String($0.group?.expanded == true) }.joined(separator: ",")
    let input = "\(layerFilterRevision):\(layerFilterFocusRequest):\(selection):\(links):\(groups):\(layerNameDraft?.layerID.uuidString ?? "")"
    return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

@MainActor extension AppDelegate {
  @objc func findLayers() { store?.findLayers() }
  @objc func isolateLayers() { store?.toggleLayerIsolation() }
}
