import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LayerMergeIntent {
  nonisolated static func singleGroup(_ ids:Set<UUID>,in document:CraftDocument)->Bool {
    ids.count==1 && document.layers.contains{ids.contains($0.id) && $0.isGroup}
  }
  nonisolated static func operation(_ ids:Set<UUID>,in document:CraftDocument)->LayerMergeOperation {
    if LayerMerge.isClippingBase(ids, in: document) { return .clippingMask }
    if ids.count == 1 && !singleGroup(ids, in: document) && LayerMerge.canApply(.down, layerIDs: ids, in: document) {
      return .down
    }
    return .selected
  }
  nonisolated static func stampOperation(_ ids: Set<UUID>, in document: CraftDocument) -> LayerMergeOperation {
    guard ids.count == 1, !singleGroup(ids, in: document) else { return .stampSelected }
    return LayerMerge.isClippingBase(ids, in: document) ? .stampGroup : .stampDown
  }

  nonisolated static func adobeCommand(_ document:CraftDocument,_ ids:Set<UUID>,_ operation:LayerMergeOperation)throws->Command {
    let contextual: LayerMergeOperation
    switch operation {
    case .down: contextual = self.operation(ids, in: document)
    case .stampSelected: contextual = stampOperation(ids, in: document)
    default: contextual = operation
    }
    return try LayerMergePreparation.command(document, layerIDs: ids, operation: contextual)
  }
}
extension EditorStore {
  var menuMergeOperation: LayerMergeOperation {
    LayerMergeIntent.operation(clipboardLayerIDs,in:document)
  }
  var menuMergeTitle:String {LayerMergeIntent.singleGroup(clipboardLayerIDs,in:document) ? "Merge Group":menuMergeOperation.rawValue}
  func contextualStamp(_ operation: LayerMergeOperation) -> LayerMergeOperation {
    operation == .stampSelected ? LayerMergeIntent.stampOperation(clipboardLayerIDs, in: document) : operation
  }

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
