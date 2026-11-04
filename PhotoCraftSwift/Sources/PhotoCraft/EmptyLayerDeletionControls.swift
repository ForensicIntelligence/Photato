import AppKit
import PhotoCraftCore

extension EditorStore {
  var canDeleteEmptyLayers: Bool {
    canBeginLayerCreation && historyOperation == nil && !editingComponent
      && !editingMask && !smartFilterMaskEditing && isCompositeColorTarget
      && EmptyLayerDeletion.unavailableReason(document) == nil
  }
  func deleteEmptyLayers() {
    finishLayerName()
    guard canDeleteEmptyLayers else { return }
    let selected = selectedLayerIDs
    performGeometry(label: EmptyLayerDeletion.title, prepare: { source in
      try EmptyLayerDeletion.prepare(source)
    }) { [weak self] in
      self?.restoreEmptyDeletionSelection(selected)
    }
  }
  func restoreEmptyDeletionSelection(_ selected: Set<UUID>) {
    selectedLayerIDs = selected.intersection(Set(document.layers.map(\.id)))
    if selectedLayerIDs.isEmpty, let active = document.activeLayerID {
      selectedLayerIDs = [active]
    }
  }
}

extension AppDelegate {
  @objc func deleteEmptyLayers() { store?.deleteEmptyLayers() }
}

enum EmptyLayerDeletionAPI {
  static let name = "layers.deleteEmpty"
  static var capabilities: [String: Any] {
    ["command": name,
      "scope": "Empty unmasked raster layers and plain groups, recursively. Hidden RGB is ignored; visibility, opacity, canvas placement and selection do not determine emptiness. Keeps an editable layer with its required parents.",
      "transaction": "Native asynchronous preparation, one Undo when changed, no history/dirty change for a no-op. Preserves surviving selection and active layer. Resolved deleted targets use the existing semantic delete Action.",
      "preserved": "Clipping bases, locked layers/ancestors, Background, masks/effects, source tags, native-mode storage, Smart Objects, temporal content, type, vector shapes, adjustments, fills, artboards and frames are retained.",
      "limits": "Full Photoshop lock/group/last-layer and extended-content behavior is unqualified. Timeline, ink, channel-only and restricted-mode documents are unavailable. No new pixel-area limit.",
      "adobe": "Published create-composite defines explicit layer deletion. The current general adapter retains a separate deletion gap; existing Background deletion is distinct. This automatic-empty selector is Photato-only. No Adobe route or general deletion support is invented or claimed."]
  }
}
