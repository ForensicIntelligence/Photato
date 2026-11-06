import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

extension EditorStore {
  var lightPreviewEditingLayers: Set<UUID> {
    guard document.animation == nil, document.videoTimeline == nil, editingChannel == nil,
      !editingComponent, document.colorMode == .rgb else { return [] }
    if let gesture = brushGesture, gesture.sessionGeneration == sessionGeneration,
      gesture.generation == layerPanelGeneration, gesture.original == document,
      gesture.selection == nil, gesture.adjustment == nil { return [gesture.layerID] }
    if let draft = cloneDraft, draft.sessionGeneration == sessionGeneration, !draft.commitRequested {
      return [draft.layerID]
    }
    return []
  }
  var lightEditingPreview: LightEditingPreview {
    .init(document: document, editingLayers: lightPreviewEditingLayers)
  }
}
struct LightPreviewNotice: View {
  let count: Int
  var body: some View {
    Label(count == 1 ? "Light paused while editing below" : "\(count) Light layers paused while editing below", systemImage: "pause.circle")
      .font(.system(size: 10)).foregroundStyle(.secondary).allowsHitTesting(false)
      .accessibilityLabel(count == 1 ? "Light adjustment paused while editing below" : "\(count) Light adjustments paused while editing below")
      .help("Highlights and Shadows resume when the stroke finishes or is cancelled. Final pixels and saved settings use the full adjustment.")
  }
}
enum LightPreviewAPI {
  static var stateSchema: [String: Any] {
    let ids: [String: Any] = ["type": "array", "uniqueItems": true, "items": ["type": "string", "format": "uuid"]]
    return BrushAPI.object(["paused": BrushAPI.flag, "pausedLayerIDs": ids, "editingLayerIDs": ids,
      "phase": BrushAPI.enumeration(["idle", "painting", "retouching"])], required: ["paused", "pausedLayerIDs", "editingLayerIDs", "phase"])
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let ids = store.lightEditingPreview.pausedLayerIDs
    let targets = store.lightPreviewEditingLayers
    return ["paused": !ids.isEmpty, "pausedLayerIDs": ids.map(\.uuidString),
      "editingLayerIDs": store.document.layers.filter { targets.contains($0.id) }.map { $0.id.uuidString },
      "phase": targets.isEmpty ? "idle" : store.brushGesture != nil ? "painting" : "retouching"]
  }
  static var capabilities: [String: Any] {
    ["state": "lightPreview", "schema": stateSchema,
     "behavior": "Native paint and retouch gestures below visible Light layers pause those layers when Highlights or Shadows are active. Release/Cancel restores full composition. Incremental preview retains original stroke sampling and commit data.",
     "persistence": "Presentation only: no command, archive, Actions, preference, saved settings, API export or final pixel change.",
     "limits": "Static RGB paint/retouch layer and mask contexts; selection/auxiliary/adjustment-brush/Timeline edits do not use this path. Transform/type/other live edits, exact Photoshop pause visuals/timing, occlusion, all performance/platform combinations remain unqualified. Clarity/Dehaze is not paused by this policy."]
  }
}
