import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func canMaskAllObjects(context: UUID? = nil) -> Bool {
    guard canBeginLayerCreation, clipboardTargetAvailable, let layer = layerPanelSingle(context),
      (try? ForegroundSelection.checkSize(document.width, document.height)) != nil,
      (try? MaskAllObjectsEdit.checkTarget(document, layerID: layer.id)) != nil else { return false }
    return true
  }
  func maskAllObjects() {
    guard canMaskAllObjects(), let id = activeLayer?.id else { return }
    let detector = allObjectsDetector
    performGeometry(label: "Mask All Objects", prepare: { original in
      try await MaskAllObjectsInput.command(document: original, layerID: id, detector: detector)
    }, onSuccess: { [weak self] in
      guard let self, let group = self.document.activeLayerID else { return }
      self.select(group)
      self.status = "Object masks ready — add an adjustment inside a group to edit that object."
    })
  }
}

extension AppDelegate {
  @objc func maskAllObjects() { store?.maskAllObjects() }
}
