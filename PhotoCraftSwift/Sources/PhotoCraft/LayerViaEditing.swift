import PhotoCraftCore

extension EditorStore {
  func canLayerVia(_ operation: LayerViaOperation) -> Bool {
    guard clipboardTargetAvailable, clipboardLayerIDs.count == 1,
      let layer = activeLayer, clipboardLayerIDs.contains(layer.id)
    else { return false }
    if document.selection == nil {
      return operation == .copy && canCopyWholeLayerViaMenu
    }
    return (operation != .cut || !document.isImageLocked(layer.id))
      && LayerVia.canApply(to: layer, in: document)
  }

  func layerVia(_ operation: LayerViaOperation) {
    guard canLayerVia(operation), let layer = activeLayer else { return }
    if document.selection == nil {
      copyWholeLayerViaMenu()
      return
    }
    performGeometry(.layerVia(layer.id, operation)) { [weak self] in
      guard let self else { return }
      self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
      self.maskEditingLayerID = nil
    }
  }
}
