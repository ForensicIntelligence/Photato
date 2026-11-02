import AppKit
import PhotoCraftCore

struct FlattenImageRequest {
  let original: CraftDocument
  var hiddenLayerIDs: [UUID] { FlattenImageEdit.hiddenLayerIDs(in:original) }
}
@MainActor enum FlattenImageAlert {
  static func make(_ request: FlattenImageRequest) -> NSAlert {
    let alert = NSAlert(); alert.alertStyle = .warning
    alert.messageText = "Discard hidden layers?"
    alert.informativeText = "Flatten Image combines visible artwork into a Background layer. Hidden layers will be discarded."
    alert.addButton(withTitle:"OK"); alert.addButton(withTitle:"Cancel").keyEquivalent = "\u{1b}"
    return alert
  }
}
extension EditorStore {
  var canFlattenImage: Bool {
    canBeginLayerCreation && isCompositeColorTarget && !editingMask && !smartFilterMaskEditing
      && FlattenImageEdit.unavailableReason(document) == nil
  }
  func requestFlattenImage() {
    finishLayerName(); guard canFlattenImage else { return }
    let request = FlattenImageRequest(original:document), generation = layerPanelGeneration, sessionID = sessionGeneration
    if !request.hiddenLayerIDs.isEmpty {
      let confirmationID = UUID()
      flattenImageConfirmationID = confirmationID
      geometryBusy = true
      let approved: Bool
      if let confirm = flattenImageConfirmation { approved = confirm(request) }
      else {
        let alert = FlattenImageAlert.make(request)
        flattenImageAlert = alert
        approved = alert.runModal() == .alertFirstButtonReturn
        flattenImageAlert = nil
      }
      let stillPending = flattenImageConfirmationID == confirmationID
      if stillPending { flattenImageConfirmationID = nil; geometryBusy = false }
      guard approved, stillPending else { return }
    }
    guard document == request.original, generation == layerPanelGeneration, sessionID == sessionGeneration else {
      error = "The document changed. Choose Flatten Image again."; return
    }
    let prepare = flattenImagePreparation
    performGeometry(label:"Flatten Image",prepare:prepare) { [weak self] in
      guard let self else { return }
      self.selectedLayerIDs = Set(self.document.activeLayerID.map{[$0]} ?? [])
      self.maskEditingLayerID = nil
    }
  }
}
extension AppDelegate {
  @objc func flattenImage() { store?.requestFlattenImage() }
}
