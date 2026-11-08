import AppKit
import SwiftUI
import PhotoCraftCore

@MainActor enum SmartFilterDrag {
  nonisolated static let identifier = "ca.forensicintelligence.photato.smart-filter"
  private static let prefix = "photato-smart-filter-v1:"
  @MainActor private final class Capture {
    weak var store: EditorStore?
    weak var controller: CraftDocumentController?
    let attached: Bool
    let token = UUID()
    let documentID: UUID
    let session: UUID
    let generation: UUID
    let layerID: UUID
    let filterID: UUID
    init(_ store: EditorStore, layerID: UUID, filterID: UUID) {
      self.store = store; controller = store.documentController; attached = controller != nil
      documentID = store.document.id; session = store.sessionGeneration
      generation = store.layerPanelGeneration; self.layerID = layerID; self.filterID = filterID
    }
  }
  private static var capture: Capture?
  static func operation(_ modifiers: NSEvent.ModifierFlags) -> DropOperation {
    modifiers.contains(.option) ? .copy : .move
  }
  private static func current(_ store: EditorStore) -> Capture? {
    guard let value = capture, value.store === store,
      value.documentID == store.document.id, value.session == store.sessionGeneration,
      value.generation == store.layerPanelGeneration else { return nil }
    if value.attached {
      guard let controller = value.controller,
        controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === store }) else { return nil }
    }
    return value
  }
  static func provider(store: EditorStore, layerID: UUID, filterID: UUID) -> NSItemProvider {
    capture = nil
    let provider = NSItemProvider()
    guard store.clipboardTargetAvailable,
      let layer = store.document.layers.first(where: { $0.id == layerID }), layer.smartObject != nil,
      let filter = layer.smartFilters?.filters.first(where: { $0.id == filterID }),
      filter.filter.kind != .lensBlur else { return provider }
    let value = Capture(store, layerID: layerID, filterID: filterID); capture = value
    let data = Data((prefix + value.token.uuidString).utf8)
    provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .ownProcess) { completion in
      completion(data, nil); return nil
    }
    return provider
  }
  static func canReceive(store: EditorStore, layerID: UUID, filterID: UUID?, copying: Bool) -> Bool {
    guard store.clipboardTargetAvailable, let value = current(store),
      let source = store.document.layers.first(where: { $0.id == value.layerID }),
      source.smartObject != nil,
      source.smartFilters?.filters.contains(where: { $0.id == value.filterID && $0.filter.kind != .lensBlur }) == true,
      let target = store.document.layers.first(where: { $0.id == layerID }), target.smartObject != nil,
      !store.document.isImageLocked(layerID) else { return false }
    let filters = target.smartFilters?.filters ?? []
    guard filterID == nil || filters.contains(where: { $0.id == filterID }) else { return false }
    if copying { return filters.count < SmartFilterStack.maximumFilters }
    guard value.layerID == layerID, let sourceIndex = filters.firstIndex(where: { $0.id == value.filterID }) else { return false }
    let destination = filterID.flatMap { id in filters.firstIndex(where: { $0.id == id }) } ?? (filters.count - 1)
    return sourceIndex != destination
  }
  static func receive(_ provider: NSItemProvider, store: EditorStore, layerID: UUID,
                      filterID: UUID?, copying: Bool) async -> Bool {
    guard canReceive(store: store, layerID: layerID, filterID: filterID, copying: copying),
      let expected = current(store)?.token, provider.hasItemConformingToTypeIdentifier(identifier) else { return false }
    let data: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
        continuation.resume(returning: error == nil ? data : nil)
      }
    }
    guard !Task.isCancelled, let data, data.count <= 96,
      String(data: data, encoding: .utf8) == prefix + expected.uuidString,
      current(store)?.token == expected,
      canReceive(store: store, layerID: layerID, filterID: filterID, copying: copying),
      let value = current(store),
      let source = store.document.layers.first(where: { $0.id == value.layerID })?.smartFilters?.filters.first(where: { $0.id == value.filterID }),
      let layer = store.document.layers.first(where: { $0.id == layerID }) else { return false }
    do {
      var stack = layer.smartFilters ?? SmartFilterStack()
      if copying {
        var copy = source; copy.id = UUID()
        let position = filterID.flatMap { id in stack.filters.firstIndex(where: { $0.id == id }) } ?? stack.filters.count
        if layer.smartFilters == nil { try stack.createMask(in: store.document, selection: store.document.selection != nil) }
        stack.filters.insert(copy, at: position)
      } else {
        guard let index = stack.filters.firstIndex(where: { $0.id == source.id }) else { return false }
        let position = filterID.flatMap { id in stack.filters.firstIndex(where: { $0.id == id }) } ?? (stack.filters.count - 1)
        stack.filters.remove(at: index); stack.filters.insert(source, at: position)
      }
      try stack.validate()
      capture = nil
      store.performGeometry(.smartFilters(layerID, stack))
      return true
    } catch { store.error = error.localizedDescription; return false }
  }
  nonisolated static var apiCapabilities: [String: Any] {
    ["command": "smartFilter.set", "array": "stack.filters is application order, bottom first. Supply the complete resulting target stack; copying uses a fresh unique filter id and retains every filter value.",
     "native": "Drag a Smart Filter onto a row to reorder within its stack. Hold Option at drop to copy to a row or another Smart Object in the same document. A layer/header target appends at the visual top. Target mask/properties and stack enable state are retained; a new stack uses the existing selection-mask policy. One native Undo and resolved portable filter-stack Action.",
     "modifiers": "The drop proposal and dispatched operation share live Option copy versus plain move resolution. Capture that operation at drop before loading private data; other modifiers add no action.",
     "guards": "Private process-local token with weak store, document/session/layer generation and attachment checks; superseded, stale, foreign, closed, malformed, multi-provider, busy, locked, over-budget and no-op transfers reject. Renderer validates the existing prepared transaction before commit.",
     "groupTransfer": SmartFilterTransferAPI.capabilities,
     "limits": "This single-filter path supports same-document copy and within-stack reorder. Whole-stack/mask move/copy uses smartFilter.transfer and the group/mask drag source. Cross-document, cross-layer single-filter destructive move and Lens Blur drag remain unavailable. Existing file/source/renderer budgets apply.",
     "qualification": "Physical hit testing/system feedback/modifier timing and full Photoshop output/default/platform behavior remain unqualified. No new API operation, Adobe descriptor, document or Actions version."]
  }
}

@MainActor struct SmartFilterDropDelegate: @preconcurrency DropDelegate {
  let store: EditorStore
  let layerID: UUID
  let filterID: UUID?
  @Binding var highlighted: Bool
  private var copying: Bool { SmartFilterDrag.operation(NSEvent.modifierFlags) == .copy }
  static var identifiers: [String] { [SmartFilterDrag.identifier, SmartFilterGroupDrag.identifier] }
  func validateDrop(info: DropInfo) -> Bool {
    guard info.hasItemsConforming(to: Self.identifiers),
      info.itemProviders(for: Self.identifiers).count == 1 else { return false }
    if info.hasItemsConforming(to: [SmartFilterGroupDrag.identifier]) {
      return filterID == nil && SmartFilterGroupDrag.canReceive(store:store, layerID:layerID, copying:copying)
    }
    return SmartFilterDrag.canReceive(store:store, layerID:layerID, filterID:filterID, copying:copying)
  }
  func dropEntered(info: DropInfo) { highlighted = validateDrop(info: info) }
  func dropExited(info: DropInfo) { highlighted = false }
  func dropUpdated(info: DropInfo) -> DropProposal? {
    highlighted = validateDrop(info: info)
    return DropProposal(operation: highlighted ? (copying ? .copy : .move) : .cancel)
  }
  func performDrop(info: DropInfo) -> Bool {
    guard validateDrop(info: info), let provider = info.itemProviders(for: Self.identifiers).first else { return false }
    let copying = self.copying; highlighted = false
    let group = provider.hasItemConformingToTypeIdentifier(SmartFilterGroupDrag.identifier)
    Task { @MainActor in
      if group { _ = await SmartFilterGroupDrag.receive(provider, store:store, layerID:layerID, copying:copying) }
      else { _ = await SmartFilterDrag.receive(provider, store: store, layerID: layerID, filterID: filterID, copying: copying) }
    }
    return true
  }
}

@MainActor struct SmartFilterDropTarget: ViewModifier {
  let store: EditorStore
  let layerID: UUID
  var filterID: UUID? = nil
  @State private var highlighted = false
  func body(content: Content) -> some View {
    content.onDrop(of: SmartFilterDropDelegate.identifiers, delegate: SmartFilterDropDelegate(
      store: store, layerID: layerID, filterID: filterID, highlighted: $highlighted))
      .overlay { Rectangle().stroke(highlighted ? Color.accentColor : .clear, lineWidth: 1).allowsHitTesting(false) }
      .onChange(of: store.sessionGeneration) { _, _ in highlighted = false }
  }
}
