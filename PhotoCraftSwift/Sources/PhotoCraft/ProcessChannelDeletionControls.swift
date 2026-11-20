import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var selectedProcessChannelsForDeletion: [Int] {
    guard editingChannel == nil, !editingMask, !smartFilterMaskEditing else { return [] }
    return effectiveComponentTargets.sorted()
  }

  func canDeleteProcessChannels(_ components: [Int]) -> Bool {
    let request = ProcessChannelDeletion(mode: document.colorMode, components: components, mergeVisible: false)
    return canEditChannels && (try? request.retainedComponents(in: document)) != nil
  }

  var canDeleteSelectedChannel: Bool {
    guard canEditChannels else { return false }
    if alphaEditingID != nil { return true }
    if document.inkChannelTargets.count > 1, effectiveInkTargets.count == 1,
      case .plate = effectiveInkTargets.first { return true }
    return canDeleteProcessChannels(selectedProcessChannelsForDeletion)
  }

  func deleteSelectedChannel(fromTrash: Bool = false, modifiers: NSEvent.ModifierFlags = []) {
    if let id = alphaEditingID {
      perform(.channel(.delete(id)))
    } else if document.inkChannelTargets.count > 1, effectiveInkTargets.count == 1,
      case .plate(let id) = effectiveInkTargets.first {
      performInkChannel(.delete(id))
    } else {
      requestProcessChannelDeletion(selectedProcessChannelsForDeletion,
        confirmEvenIfFlat: fromTrash, immediate: fromTrash && modifiers.contains(.option))
    }
  }

  func requestProcessChannelDeletion(_ components: [Int], confirmEvenIfFlat: Bool = false, immediate: Bool = false) {
    finishNumericField()
    finishLayerName()
    guard canDeleteProcessChannels(components) else { return }
    let source = document, panel = layerPanelGeneration, generation = sessionGeneration
    let flattens = InkModeInput.needsMerge(source)
    if !immediate && (flattens || confirmEvenIfFlat) {
      let detail = flattens
        ? "The visible layers will be flattened and hidden layers will be discarded. The remaining channels become a Multichannel document."
        : "The remaining channels become a Multichannel document."
      guard confirmHiddenLayerDiscard(FlattenImageRequest(original: source), operation: "Delete Channels",
        question: "Delete the selected process channels?", detail: detail) else { return }
    }
    guard document == source, layerPanelGeneration == panel, sessionGeneration == generation else {
      error = "The document changed. Choose Delete Channels again."
      return
    }
    let request = ProcessChannelDeletion(mode: source.colorMode, components: components, mergeVisible: flattens)
    performGeometry(label: "Delete Channels", allowAuxiliary: true, prepare: { original in
      try InkModeInput.deleteProcess(request, in: original)
    }, onSuccess: { [weak self] in self?.showProcessChannelDeletionResult() })
  }

  func showProcessChannelDeletionResult() {
    selectedLayerIDs = []
    let remainingVisible = visibleAlphaIDs
    try? selectInkChannels([])
    savedChannelVisibility = .init(documentID: document.id, imageVisible: true, alphaIDs: remainingVisible)
    render()
  }
}
