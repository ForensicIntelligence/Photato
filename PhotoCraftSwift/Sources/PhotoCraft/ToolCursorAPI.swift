import Foundation

/// Local pointer presentation is discoverable, but is not persistent document state or a remote input API.
enum ToolCursorAPI {
  static var capabilities: [String: Any] { [
    "version": 1,
    "presentationOnly": true,
    "tools": EditorTool.allCases.map(\.id),
    "modifiers": ["control", "command", "option", "shift"],
    "workspaces": ["document", "selectMask", "focusArea", "colorRange", "magneticLasso", "selectionTransform", "transformReference", "selectedPixelTransform", "selectedPixelMove", "artboardNeighbors", "liquify", "contentAwareFill", "sky", "vanishingPoint", "blurGallery", "perspectiveWarp", "adaptiveWideAngle", "lensCorrection", "lightingEffects"],
    "behavior": "Cursor follows the effective existing operation; stationary modifier changes and gesture-end/tool/focus changes refresh immediately. Captured stroke modes remain stable until release. Modifier observations received while the canvas window is inactive clear stale hover modifiers; other active-window events remain ignored. Selected-pixel Move captures Option-copy, shows live Shift constraints and guide-snap suppression, and refreshes stationary modifier changes. Artboard + controls show add or Option-copy, captured at press until release; Escape, tool/focus/source changes cancel the press. Transform reference drags keep a scope cursor with no modifier alternate; Space before press keeps Hand. Space shows temporary Hand; dragging shows closed Hand.",
    "eyedropper":["option":"Background color", "shift":"Unavailable persistent Color Sampler", "capture":"Foreground/background target and sample settings captured at press until release; Control/Command add no action. Escape restores the initial pair if no other palette change occurred; focus/tool changes cancel pending samples."],
    "eraserModes":["brush":"Existing eraser cursor","pencil":"Pencil tip","block":"16point square","option":"Unavailable until Erase to History has a real source","capture":"Mode and brush snapshot retained through a stroke; Space/hand/focus policy unchanged"],
    "contentAwareFillSelection":["modes":["New","Add","Subtract","Intersect"],"modifiers":"Shift Add, Option Subtract, Shift-Option Intersect; Control/Command add no action. Mode captured at selection stroke start; sampling Option reversal and temporary Hand unchanged."],
    "scope": "Native macOS pointer presentation only. Modifiers without an alternate implementation retain the current tool cursor. Control/Command are observed, not assigned invented editing operations. Editing requests continue to use explicit existing command parameters; no remote keyboard or cursor injection.",
    "adobe": "No published Adobe Photoshop v2 pointer-presentation endpoint; no Adobe route added. Existing shared editing operations and document/history contracts are unchanged.",
    "qualification": "Native regression matrix; complete Photoshop modifier/default/hover cursor parity and physical held-key comparison remain separate gates."
  ] }
}
