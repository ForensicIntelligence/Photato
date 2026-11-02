import AppKit
import PhotoCraftCore
import SwiftUI

enum LayerPanelAction: String, CaseIterable {
  case newLayer, newGroup, groupFromLayers, duplicate, delete, rename, ungroup
  case maskAllObjects, rasterize, clipping, addMask, toggleMask, applyMask, deleteMask, merge, mergeVisible
}

extension EditorStore {
  func layerPanelSelection(_ context: UUID?) -> Set<UUID> {
    if let context, !groupSelectionIDs.contains(context) { return [context] }
    return groupSelectionIDs
  }
  func layerPanelSingle(_ context: UUID?) -> Layer? {
    let ids = layerPanelSelection(context)
    return ids.count == 1 ? document.layers.first { ids.contains($0.id) } : nil
  }
  func layerPanelTitle(_ action: LayerPanelAction, context: UUID? = nil) -> String {
    let ids = layerPanelSelection(context)
    let layer = layerPanelSingle(context)
    switch action {
    case .newLayer: return "New Layer…"
    case .newGroup: return "New Group…"
    case .groupFromLayers: return "New Group from Layers…"
    case .duplicate:
      let groups =
        !ids.isEmpty && document.layers.filter { ids.contains($0.id) }.allSatisfy(\.isGroup)
      return "Duplicate "
        + (groups ? (ids.count > 1 ? "Groups…" : "Group…") : (ids.count > 1 ? "Layers…" : "Layer…"))
    case .delete:
      return ids.count > 1
        ? "Delete Layers" : (layer?.isGroup == true ? "Delete Group" : "Delete Layer")
    case .rename: return layer?.isBackground == true ? "Layer from Background…":layer?.isGroup == true ? "Rename Group…" : "Rename Layer…"
    case .ungroup: return "Ungroup Layers"
    case .maskAllObjects: return "Mask All Objects"
    case .rasterize: return "Rasterize Layer"
    case .clipping:
      return layer?.isClipped == true ? "Release Clipping Mask" : "Create Clipping Mask"
    case .addMask: return "Add Layer Mask"
    case .toggleMask:
      return layer?.effectiveMaskProperties.enabled == false
        ? "Enable Layer Mask" : "Disable Layer Mask"
    case .applyMask: return "Apply Layer Mask"
    case .deleteMask: return "Delete Layer Mask"
    case .merge:
      return ids.count == 1 && LayerMerge.canApply(.down, layerIDs: ids, in: document)
        ? "Merge Down" : "Merge Layers"
    case .mergeVisible: return "Merge Visible"
    }
  }
  func canPerformLayerPanel(_ action: LayerPanelAction, context: UUID? = nil) -> Bool {
    guard canBeginLayerCreation else { return false }
    let ids = layerPanelSelection(context)
    guard ids.isSubset(of: Set(document.layers.map(\.id))) else { return false }
    let layer = layerPanelSingle(context)
    let editable = layer.map { !document.isLocked($0.id) } == true
    switch action {
    case .newLayer: return canCreatePixelLayer()
    case .newGroup: return canCreateGroup()
    case .groupFromLayers:
      guard !ids.isEmpty else { return false }
      var candidate = document
      return
        (try? Command.newGroup(.init(name: "Group"), children: Array(ids)).apply(to: &candidate))
        != nil
    case .duplicate: return !ids.isEmpty
    case .delete: return canRequestLayerDeletion(context: context)
    case .rename: return layer != nil
    case .ungroup: return editable && layer?.isGroup == true
    case .maskAllObjects: return canMaskAllObjects(context: context)
    case .rasterize:
      guard editable, let layer else { return false }
      if layer.smartObject != nil || layer.video != nil { return true }
      switch layer.content {
      case .raster, .adjustment, .group: return false
      default: return true
      }
    case .clipping:
      return editable
        && (layer?.isClipped == true
          || layer.map { document.clippingBase(for: $0.id) != nil } == true)
    case .addMask: return editable && layer?.isBackground != true && layer?.mask == nil
    case .toggleMask, .deleteMask: return editable && layer?.mask != nil
    case .applyMask: return editable && layer.map(canApplyMask) == true
    case .merge:
      return LayerMerge.canApply(ids.count == 1 ? .down : .selected, layerIDs: ids, in: document)
    case .mergeVisible: return LayerMerge.canApply(.visible, layerIDs: ids, in: document)
    }
  }
  func performLayerPanel(_ action: LayerPanelAction, context: UUID? = nil) {
    finishLayerName()
    guard canPerformLayerPanel(action, context: context) else { return }
    if let context, !groupSelectionIDs.contains(context) { select(context) }
    // A context action targets the single selected row even if active selection is stale.
    if let only = layerPanelSingle(nil), document.activeLayerID != only.id { select(only.id) }
    switch action {
    case .newLayer: beginNewLayer()
    case .newGroup: beginNewGroup()
    case .groupFromLayers: beginNewGroup(fromSelection: true)
    case .duplicate: beginDuplicate()
    case .delete: requestLayerDeletion()
    case .rename: if let id = activeLayer?.id { beginLayerName(id) }
    case .ungroup: ungroup()
    case .maskAllObjects: maskAllObjects()
    case .rasterize: rasterize()
    case .clipping: if let layer = activeLayer { perform(.clipping(layer.id, !layer.isClipped)) }
    case .addMask: addMask()
    case .toggleMask: if let layer = activeLayer { updateMask(layer.id) { $0.enabled.toggle() } }
    case .applyMask: applyMask()
    case .deleteMask: deleteMask()
    case .merge: merge(menuMergeOperation)
    case .mergeVisible: merge(.visible)
    }
  }
}

struct LayerEditingMenu: View {
  @Bindable var store: EditorStore
  var contextLayer: UUID? = nil
  @ViewBuilder func layerPanelButton(_ action: LayerPanelAction, context: UUID?) -> some View {
    Button(store.layerPanelTitle(action, context: context)) {
      store.performLayerPanel(action, context: context)
    }.disabled(!store.canPerformLayerPanel(action, context: context))
  }
  var body: some View {
    if contextLayer == nil {
      layerPanelButton(.newLayer, context: nil)
      layerPanelButton(.newGroup, context: nil)
      layerPanelButton(.groupFromLayers, context: nil)
      Divider()
    } else {
      Button("Blending Options…") {}.disabled(true)
      Divider()
    }
    layerPanelButton(.duplicate, context: contextLayer)
    layerPanelButton(.delete, context: contextLayer)
    if contextLayer != nil { layerPanelButton(.groupFromLayers, context: contextLayer) }
    layerPanelButton(.rename, context: contextLayer)
    Button(store.layerVisibilityMenuTitle(context: contextLayer)) {
      store.toggleSelectedLayerVisibility(context: contextLayer)
    }.disabled(!store.canOrganizeLayers(context: contextLayer))
    if store.layerPanelSingle(contextLayer)?.isGroup == true {
      layerPanelButton(.ungroup, context: contextLayer)
    }
    Divider()
    Button("Quick Export as PNG") {}.disabled(true)
    Button("Export As…") {}.disabled(true)
    Divider()
    Button("Convert to Smart Object") {}.disabled(true)
    layerPanelButton(.rasterize, context: contextLayer)
    Divider()
    if store.layerPanelSingle(contextLayer)?.mask != nil {
      layerPanelButton(.toggleMask, context: contextLayer)
      layerPanelButton(.applyMask, context: contextLayer)
      layerPanelButton(.deleteMask, context: contextLayer)
    } else {
      layerPanelButton(.addMask, context: contextLayer)
    }
    layerPanelButton(.maskAllObjects, context: contextLayer)
    layerPanelButton(.clipping, context: contextLayer)
    Divider()
    Button(store.linkMenuUnlinks(store.linkTargets(contextLayer)) ? "Unlink Layers":"Link Layers"){store.toggleLayerLinks(context:contextLayer,temporary:NSEvent.modifierFlags.contains(.shift))}.disabled(!store.canToggleLayerLinks(context:contextLayer))
    Button("Select Linked Layers"){store.selectLinkedLayers(context:contextLayer)}.disabled(!store.canSelectLinkedLayers(context:contextLayer))
    Divider()
    Button("Copy Layer Style") { store.copyLayerStyle() }.disabled(!store.canCopyLayerStyle)
    Button("Paste Layer Style") { store.pasteLayerStyle() }.disabled(!store.canPasteLayerStyle)
    Button("Clear Layer Style") { store.clearLayerStyle() }.disabled(!store.canClearLayerStyle)
    Divider()
    layerPanelButton(.merge, context: contextLayer)
    layerPanelButton(.mergeVisible, context: contextLayer)
    Button("Flatten Image") {store.requestFlattenImage()}.disabled(!store.canFlattenImage)
    if let contextLayer, let layer = store.document.layers.first(where: { $0.id == contextLayer }) {
      Divider()
      LayerColorChoices(store: store, context: contextLayer)
      Divider()
      Menu("Layer Utilities") {
        if layer.mask != nil {
          Button("Edit Layer Mask") { store.selectMask(layer.id) }
          Button("Invert Layer Mask") { store.perform(.invertMask(layer.id)) }
            .disabled(!store.canBeginLayerCreation || store.document.isLocked(layer.id))
        }
        if store.document.isClippingBase(layer.id) {
          Toggle(
            "Blend Clipped Layers As Group",
            isOn: Binding(
              get: { layer.clipsBlendAsGroup },
              set: { store.perform(.blendClippedAsGroup(layer.id, $0)) })
          )
          .disabled(!store.canBeginLayerCreation || store.document.isLocked(layer.id))
        }
        if layer.parentID != nil { Button("Move Out of Group") { store.moveOutOfGroup(layer) } }
        Button("Move Up") { moveLayer(layer, by: 1) }
        Button("Move Down") { moveLayer(layer, by: -1) }
        Button(layer.locked ? "Unlock Layer" : "Lock Layer") {
          store.perform(.lock(layer.id, !layer.locked))
        }
      }.disabled(!store.canBeginLayerCreation || store.layerPanelSelection(contextLayer).count != 1)
    } else {
      Divider()
      Button("Collapse All Groups") { store.collapseAllLayerGroups() }
        .disabled(!store.canChangeGroupDisclosure())
      Button("Panel Options…") { store.beginLayerPanelOptions() }
        .disabled(!store.canBeginLayerCreation)
    }
  }
  private func moveLayer(_ layer: Layer, by delta: Int) {
    let siblings = store.document.children(of: layer.parentID)
    guard let index = siblings.firstIndex(where: { $0.id == layer.id }),
      siblings.indices.contains(index + delta)
    else { return }
    store.perform(.relocate(layer.id, layer.parentID, index + delta))
  }

}
