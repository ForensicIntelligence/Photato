import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func canMergeSpotChannel(_ id: UUID?) -> Bool {
    canEditChannels && SpotChannelMerge.unavailableReason(document, channelID: id) == nil
  }

  func requestSpotChannelMerge(_ id: UUID?) {
    finishLayerName()
    guard let id, canMergeSpotChannel(id) else { return }
    let original = document
    let panel = layerPanelGeneration
    let session = sessionGeneration
    let hidden = !FlattenImageEdit.hiddenLayerIDs(in: original).isEmpty
    if hidden && !confirmHiddenLayerDiscard(FlattenImageRequest(original: original), operation: "Merge Spot Channel") {
      return
    }
    guard document == original, layerPanelGeneration == panel, sessionGeneration == session else {
      error = "The document changed. Choose Merge Spot Channel again."
      return
    }
    performGeometry(label: "Merge Spot Channel", allowAuxiliary: true, prepare: { source in
      try SpotChannelMerge.command(source, channelID: id, discardHiddenLayers: hidden)
    }, onSuccess: { [weak self] in self?.showMergedSpotChannelResult() })
  }

  func showMergedSpotChannelResult() {
    selectedLayerIDs = Set(document.activeLayerID.map { [$0] } ?? [])
    let remainingVisible = visibleAlphaIDs
    // API commits immediately before this call, after releasing geometryBusy.
    try? selectAlphaChannel(nil)
    savedChannelVisibility = .init(documentID: document.id, imageVisible: true, alphaIDs: remainingVisible)
    render()
  }
}
