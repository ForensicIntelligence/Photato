import Foundation

/// Structural selection, shared by UI, API, Actions and the compositor worker.
public struct LayerMergePlan: Sendable {
  public let rootIDs: Set<UUID>, sourceIDs: Set<UUID>, removedIDs: Set<UUID>
  public let base: Layer
  public let parentID: UUID?
  public let includesBackground: Bool
  public init(_ operation: LayerMergeOperation, layerIDs: Set<UUID>, in d: CraftDocument) throws {
    guard d.colorMode == .rgb, d.modeDescriptor == nil, d.restrictedMode == nil, d.inkMode == nil else {
      throw CraftError.unsupported("Merging numerical, palette and ink layers requires their component compositor.")
    }
    guard d.animation == nil, d.videoTimeline == nil else {
      throw CraftError.unsupported("Merging temporal layers requires frame and Timeline composition.")
    }
    if operation.preservesSources, d.layers.count >= LayerLimits.maximumLayers {
      throw CraftError.invalid("The document has reached its layer limit.")
    }
    let hierarchy = LayerHierarchyIndex(d)
    let siblingsByParent=Dictionary(grouping:d.layers,by: \.parentID)
    var clippingBases:[UUID:UUID]=[:]
    for siblings in siblingsByParent.values {
      var base:UUID?
      for layer in siblings {
        if layer.isClipped {if let base {clippingBases[layer.id]=base}}
        else {base=layer.id}
      }
    }
    guard layerIDs.isSubset(of: Set(hierarchy.byID.keys)) else {throw CraftError.invalid("Layer no longer exists.")}
    let roots: [Layer]
    switch operation {
    case .down:
      guard layerIDs.count == 1,let id=layerIDs.first,let top=hierarchy.byID[id] else{throw CraftError.invalid("Select one layer to merge down.")}
      let siblings=siblingsByParent[top.parentID] ?? []
      guard let index=siblings.firstIndex(where:{$0.id==id}),index>0,
        top.visible,siblings[index-1].visible,case .raster=siblings[index-1].content else {
        throw CraftError.invalid("Merge Down requires an adjacent visible pixel layer below the selection.")
      }
      roots=[siblings[index-1],top];base=roots[0]
    case .selected:
      roots=d.layers.filter{layerIDs.contains($0.id) && !hierarchy.ancestors(of:$0.id).contains{layerIDs.contains($0.id)}}
      guard let top=roots.last,top.visible,roots.count>1 || top.isGroup else{throw CraftError.invalid("Select multiple layers or a group to merge.")}
      guard roots.allSatisfy({$0.parentID==top.parentID}) else{throw CraftError.unsupported("Merging selections across different parent groups needs independent Photoshop qualification.")}
      base=top
    case .stampSelected:
      roots = d.layers.filter { layerIDs.contains($0.id) && !hierarchy.ancestors(of: $0.id).contains { layerIDs.contains($0.id) } }
      guard let top = roots.last, roots.count > 1 || top.isGroup,
        roots.contains(where: \.visible)
      else { throw CraftError.invalid("Select multiple layers with visible artwork, or a visible group to stamp.") }
      base = top
    case .visible, .stampVisible:
      roots=(siblingsByParent[nil] ?? []).filter(\.visible)
      guard let active=d.activeLayerID,let layer=hierarchy.byID[active],layer.visible,
        !hierarchy.ancestors(of:active).contains(where:{!$0.visible}),
        roots.count>1 || roots.first?.isGroup==true else{throw CraftError.invalid("Select a visible layer in an image with multiple visible layers or a visible group.")}
      base=layer
    }
    let rootsToRender = Set(roots.map(\.id))
    let included = hierarchy.subtreeIDs(rootsToRender)
    rootIDs = rootsToRender
    sourceIDs = included
    removedIDs = operation.preservesSources ? [] : included
    parentID = operation == .visible ? nil : base.parentID
    includesBackground = d.layers.contains { $0.isBackground && included.contains($0.id) }
    for layer in d.layers where sourceIDs.contains(layer.id) {
      guard operation.preservesSources || layer.isBackground || !hierarchy.effectiveProtection(layer.id).fullyLocks else{throw CraftError.invalid("Unlock the merged layers and their parent groups first.")}
      if operation == .visible, !layer.visible {
        throw CraftError.unsupported("Hidden descendants inside a visible merged group require qualified retention semantics; no layers were removed.")
      }
      if operation != .stampVisible,layer.isClipped,let clippingBase=clippingBases[layer.id],!sourceIDs.contains(clippingBase) {
        throw CraftError.unsupported("Include the clipping base when merging clipped artwork.")
      }
    }
  }
}

public struct PreparedLayerMerge: Sendable {
  public let source: CraftDocument, result: CraftDocument
  public let layerIDs: Set<UUID>
  public let operation: LayerMergeOperation
  public init(source:CraftDocument,result:CraftDocument,layerIDs:Set<UUID>,operation:LayerMergeOperation) {
    self.source=source;self.result=result;self.layerIDs=layerIDs;self.operation=operation
  }
  public func applied(to document:CraftDocument)throws->CraftDocument {
    try Task.checkCancellation()
    guard document==source,result.id==source.id else{throw CraftError.invalid("The document changed before the merged layer could commit.")}
    try result.validate();return result
  }
}
