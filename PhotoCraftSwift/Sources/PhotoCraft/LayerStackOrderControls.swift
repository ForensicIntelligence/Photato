import AppKit
import PhotoCraftCore

@MainActor extension EditorStore {
  var canArrangeLayerContext: Bool {
    canBeginLayerCreation && !editingComponent && !coalescingChanges && brushGesture == nil
      && pathGesture == nil && historyOperation == nil && !aiBusy
  }
  var stackSelectionIDs: [UUID] { document.layers.filter { groupSelectionIDs.contains($0.id) }.map(\.id) }
  func canArrangeLayerStack(_ operation: LayerStackOperation) -> Bool {
    guard canArrangeLayerContext else { return false }
    let request = LayerStackOrderRequest(layerIDs: stackSelectionIDs, operation: operation)
    guard let order = try? LayerStackOrder.order(request, in: document) else { return false }
    return order != document.layers.map(\.id)
  }
  func arrangeLayerStack(_ operation: LayerStackOperation) {
    guard canArrangeLayerStack(operation) else { return }
    let request = LayerStackOrderRequest(layerIDs: stackSelectionIDs, operation: operation)
    let selected = selectedLayerIDs, target = selectedMaskPaintTarget
    let prepare = layerStackOrderPreparation
    performPreparedGeometry(label: operation.title, allowAuxiliary: true,
      prepare: { source in try await PreparedEdit(command: prepare(source, request), document: source) },
      validateCommit: { [weak self] in
        guard let self, self.selectedLayerIDs == selected, self.selectedMaskPaintTarget == target,
          !self.editingComponent else { throw CraftError.invalid("The layer arrangement target changed.") }
      })
  }
}

@MainActor extension AppDelegate {
  @objc func arrangeLayerStack(_ sender: NSMenuItem) {
    guard let operation = LayerStackOperation.allCases.first(where: { $0.title == sender.title }) else { return }
    store?.arrangeLayerStack(operation)
  }
}
