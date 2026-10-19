import AppKit
import PhotoCraftCore
import SwiftUI

struct LayerVisibilityFingerprint: Equatable {
  let documentID: UUID
  let order: [UUID]
  let parents: [UUID: UUID]
  let clipped: Set<UUID>
  let groups: Set<UUID>
  let values: [UUID: Bool]
  init(_ document: CraftDocument) {
    documentID = document.id
    order = document.layers.map(\.id)
    parents = Dictionary(
      uniqueKeysWithValues: document.layers.compactMap { layer in
        layer.parentID.map { (layer.id, $0) }
      })
    clipped = Set(document.layers.filter(\.isClipped).map(\.id))
    groups = Set(document.layers.filter(\.isGroup).map(\.id))
    values = LayerOrganization.visibility(in: document)
  }
}

struct LayerVisibilityIsolation {
  let target: UUID
  let original: [UUID: Bool]
  let applied: LayerVisibilityFingerprint
}

extension EditorStore {
  func canOrganizeLayers(context: UUID? = nil) -> Bool {
    let ids = layerPanelSelection(context)
    return canBeginLayerCreation && !ids.isEmpty
      && ids.isSubset(of: Set(document.layers.map(\.id)))
  }

  func selectedLayerColor(context: UUID? = nil) -> LayerColorLabel? {
    let ids = layerPanelSelection(context)
    let layers = document.layers.filter { ids.contains($0.id) }
    guard !layers.isEmpty, layers.count == ids.count,
      let first = layers.first?.colorLabel, layers.allSatisfy({ $0.colorLabel == first })
    else { return nil }
    return first
  }

  func setLayerColor(_ color: LayerColorLabel, context: UUID? = nil) {
    finishLayerName()
    guard canOrganizeLayers(context: context) else { return }
    if let context, !groupSelectionIDs.contains(context) { select(context) }
    perform(.layerColor(groupSelectionIDs, color))
  }

  func layerVisibilityMenuTitle(context: UUID? = nil) -> String {
    let ids = layerPanelSelection(context)
    return document.layers.contains { ids.contains($0.id) && $0.visible }
      ? "Hide Layers" : "Show Layers"
  }

  func toggleSelectedLayerVisibility(context: UUID? = nil) {
    finishLayerName()
    guard canOrganizeLayers(context: context) else { return }
    if let context, !groupSelectionIDs.contains(context) { select(context) }
    let ids = groupSelectionIDs
    let visible = !document.layers.contains { ids.contains($0.id) && $0.visible }
    perform(.layerVisibility(Dictionary(uniqueKeysWithValues: ids.map { ($0, visible) })))
  }

  func validateVisibilityIsolation() {
    if let isolation = layerVisibilityIsolation,
      isolation.applied != LayerVisibilityFingerprint(document)
    {
      layerVisibilityIsolation = nil
    }
  }

  func toggleLayerVisibility(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
    finishLayerName()
    guard canBeginLayerCreation, let layer = document.layers.first(where: { $0.id == id })
    else { return }
    validateVisibilityIsolation()
    guard modifiers.contains(.option) else {
      perform(.visibility(id, !layer.visible))
      return
    }
    if let isolation = layerVisibilityIsolation, isolation.target == id {
      layerVisibilityIsolation = nil
      perform(.layerVisibility(isolation.original))
      return
    }
    let original = layerVisibilityIsolation?.original ?? LayerOrganization.visibility(in: document)
    do {
      let values = try LayerOrganization.isolatedVisibility(id, in: document)
      if LayerOrganization.visibility(in: document) == values {
        // A document can already contain a solo layout when opened or after manual
        // changes. PhotoCraft reveals all rows when its original snapshot is absent.
        let restored =
          layerVisibilityIsolation == nil
          ? Dictionary(uniqueKeysWithValues: document.layers.map { ($0.id, true) }) : original
        layerVisibilityIsolation = nil
        perform(.layerVisibility(restored))
        return
      }
      perform(.layerVisibility(values))
      guard LayerOrganization.visibility(in: document) == values else { return }
      layerVisibilityIsolation = LayerVisibilityIsolation(
        target: id, original: original, applied: LayerVisibilityFingerprint(document))
    } catch { self.error = error.localizedDescription }
  }
}

/// Separate the color choices from the containing menu's large View expression.
struct LayerColorChoices: View {
  @Bindable var store: EditorStore
  let context: UUID
  var body: some View {
    ForEach(LayerColorLabel.allCases, id: \.self) { color in
      Toggle(
        isOn: Binding(
          get: { store.selectedLayerColor(context: context) == color },
          set: { _ in store.setLayerColor(color, context: context) }
        )
      ) {
        Label {
          Text(color.title)
        } icon: {
          Image(systemName: color == .none ? "circle.slash" : "circle.fill")
            .foregroundStyle(color == .none ? Color.secondary : color.swatch)
        }
      }.disabled(!store.canOrganizeLayers(context: context))
    }
  }
}

extension AppDelegate {
  @objc func toggleLayerVisibility() { store?.toggleSelectedLayerVisibility() }
}
