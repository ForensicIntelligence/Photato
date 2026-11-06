import AppKit

enum SelectionAntsAPI {
  static var capabilities: [String: Any] { [
    "presentationOnly": true, "driver": "Core Animation CAShapeLayer lineDashPhase",
    "dashPoints": [4, 4], "periodSeconds": SelectionAntsStroke.duration,
    "coverage": "Committed rectangular and half-coverage contours, Transform Selection preview, rectangular/elliptical/single-row/single-column and rectangular Object Selection previews. Existing sparse/bounded contour geometry is retained.",
    "lifecycle": "Animation requires an attached, visible, key, unoccluded window and active application. Hidden/minimized/detached views stop. Reduce Motion shows a static selection border. Selection Brush retains its mask overlay.",
    "data": "Presentation only: no pixel/mask/channel change, Undo, dirty state, document revision or archive field; no per-frame Swift canvas redraw, contour generation or source rendering. Local configuration is observed, not a remote cursor/animation injection endpoint.",
    "adobe": "No published Firefly Photoshop v2 selection-border presentation route; no Adobe endpoint added. Existing selection commands and document output are unchanged.",
    "qualification": "Current timing and dash values are implementation values, not verified Photoshop defaults. Physical refresh rate, compositor performance, complete Extras/Selection Edges controls and exact Photoshop visual/lifecycle parity remain open."
  ] }
  static var stateSchema: [String: Any] {
    BrushAPI.object(["hasSelection": BrushAPI.flag, "selectionBrushOverlay": BrushAPI.flag,
      "selectionTransformPreview": BrushAPI.flag, "reduceMotion": BrushAPI.flag,
      "animationRequested": BrushAPI.flag, "playbackControlledByNativeWindow": BrushAPI.flag],
      required: ["hasSelection", "selectionBrushOverlay", "selectionTransformPreview", "reduceMotion", "animationRequested", "playbackControlledByNativeWindow"])
  }
}
@MainActor extension EditorStore {
  var selectionAntsState: [String: Any] {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    return ["hasSelection": document.selection != nil, "selectionBrushOverlay": tool == .selectionBrush,
      "selectionTransformPreview": transformDraft?.selection == true, "reduceMotion": reduceMotion,
      "animationRequested": !reduceMotion && tool != .selectionBrush && document.selection != nil,
      "playbackControlledByNativeWindow": true]
  }
}
