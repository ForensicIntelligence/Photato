import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LayerMergeIntent {
  nonisolated static func singleGroup(_ ids:Set<UUID>,in document:CraftDocument)->Bool {
    ids.count==1 && document.layers.contains{ids.contains($0.id) && $0.isGroup}
  }
  nonisolated static func operation(_ ids:Set<UUID>,in document:CraftDocument)->LayerMergeOperation {
    ids.count==1 && !singleGroup(ids,in:document) && LayerMerge.canApply(.down,layerIDs:ids,in:document) ? .down:.selected
  }
  nonisolated static func adobeCommand(_ document:CraftDocument,_ ids:Set<UUID>,_ operation:LayerMergeOperation)throws->Command {
    try LayerMergePreparation.command(document,layerIDs:ids,operation:operation == .down && singleGroup(ids,in:document) ? .selected:operation)
  }
}
extension EditorStore {
  var menuMergeOperation: LayerMergeOperation {
    LayerMergeIntent.operation(clipboardLayerIDs,in:document)
  }
  var menuMergeTitle:String {LayerMergeIntent.singleGroup(clipboardLayerIDs,in:document) ? "Merge Group":menuMergeOperation.rawValue}
  func canMerge(_ operation: LayerMergeOperation) -> Bool {
    clipboardTargetAvailable && !smartFilterMaskEditing
      && LayerMerge.canApply(operation, layerIDs: clipboardLayerIDs, in: document)
  }
  func merge(_ operation: LayerMergeOperation) {
    guard canMerge(operation) else { return }
    let ids=clipboardLayerIDs,prepare=layerMergePreparation
    performGeometry(label:operation.rawValue,prepare:{try prepare($0,ids,operation)}) { [weak self] in
      guard let self else { return }
      self.selectedLayerIDs = Set(self.document.activeLayerID.map { [$0] } ?? [])
      self.maskEditingLayerID = nil
    }
  }
}
