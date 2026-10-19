import PhotoCraftCore

extension EditorStore {
  var menuMergeOperation: LayerMergeOperation {
    clipboardLayerIDs.count == 1 && canMerge(.down) ? .down : .selected
  }
  func canMerge(_ operation: LayerMergeOperation) -> Bool {
    clipboardTargetAvailable
      && LayerMerge.canApply(operation, layerIDs: clipboardLayerIDs, in: document)
  }
  func merge(_ operation: LayerMergeOperation) {
    guard canMerge(operation) else { return }
    performGeometry(.mergeLayers(clipboardLayerIDs, operation)) { [weak self] in
      guard let self else { return }
      self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
      self.maskEditingLayerID = nil
    }
  }
}
