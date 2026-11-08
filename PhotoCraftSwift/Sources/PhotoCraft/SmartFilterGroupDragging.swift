import AppKit
import PhotoCraftCore

@MainActor enum SmartFilterGroupDrag {
  nonisolated static let identifier = "ca.forensicintelligence.photato.smart-filter-group"
  private static let prefix = "photato-smart-filter-group-v1:"
  @MainActor private final class Capture {
    weak var store: EditorStore?
    weak var controller: CraftDocumentController?
    let attached: Bool
    let token = UUID()
    let documentID: UUID, session: UUID, generation: UUID, sourceID: UUID
    let part: SmartFilterTransferRequest.Part
    init(_ store: EditorStore, sourceID: UUID, part: SmartFilterTransferRequest.Part) {
      self.store = store; controller = store.documentController; attached = controller != nil
      documentID = store.document.id; session = store.sessionGeneration
      generation = store.layerPanelGeneration; self.sourceID = sourceID; self.part = part
    }
  }
  private static var capture: Capture?
  private static func available(_ store: EditorStore) -> Bool {
    store.canBeginLayerCreation && store.isCompositeColorTarget && store.pathTarget == nil
      && store.document.colorMode == .rgb
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
  static func provider(store: EditorStore, layerID: UUID,
    part: SmartFilterTransferRequest.Part) -> NSItemProvider {
    capture = nil
    let provider = NSItemProvider()
    guard available(store), let layer = store.document.layers.first(where: { $0.id == layerID }),
      layer.smartObject != nil, let stack = layer.smartFilters,
      part == .mask ? stack.mask != nil : (!stack.filters.isEmpty && !stack.filters.contains(where: { $0.filter.kind == .lensBlur }))
    else { return provider }
    let value = Capture(store, sourceID: layerID, part: part); capture = value
    let data = Data((prefix + value.token.uuidString).utf8)
    provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .ownProcess) { completion in
      completion(data, nil); return nil
    }
    return provider
  }
  static func canReceive(store: EditorStore, layerID: UUID, copying: Bool) -> Bool {
    guard available(store), let value = current(store), value.sourceID != layerID,
      let source = store.document.layers.first(where: { $0.id == value.sourceID }),
      let target = store.document.layers.first(where: { $0.id == layerID }),
      source.smartObject != nil, target.smartObject != nil, let stack = source.smartFilters,
      !store.document.isImageLocked(layerID), copying || !store.document.isImageLocked(source.id)
    else { return false }
    switch value.part {
    case .stack:
      return !stack.filters.isEmpty && !stack.filters.contains(where: { $0.filter.kind == .lensBlur })
        && stack.filters.count + (target.smartFilters?.filters.count ?? 0) <= SmartFilterStack.maximumFilters
    case .mask: return stack.mask != nil && target.smartFilters?.filters.isEmpty == false
    }
  }
  static func receive(_ provider: NSItemProvider, store: EditorStore,
    layerID: UUID, copying: Bool) async -> Bool {
    guard canReceive(store: store, layerID: layerID, copying: copying), let value = current(store),
      provider.hasItemConformingToTypeIdentifier(identifier) else { return false }
    let original = store.document, token = value.token
    let data: Data? = await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
        continuation.resume(returning: error == nil ? data : nil)
      }
    }
    guard !Task.isCancelled, let data, data.count <= 96,
      String(data:data, encoding:.utf8) == prefix + token.uuidString,
      store.document == original, current(store)?.token == token,
      canReceive(store:store, layerID:layerID, copying:copying) else { return false }
    let request = SmartFilterTransferRequest(sourceLayerID:value.sourceID,
      targetLayerID:layerID, part:value.part, copy:copying)
    capture = nil
    store.performGeometry(label:request.title, allowAuxiliary:true, prepare: { try request.command(in:$0) })
    return true
  }
}
