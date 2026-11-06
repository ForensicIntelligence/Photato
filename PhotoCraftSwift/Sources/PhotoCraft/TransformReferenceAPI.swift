import Foundation
import PhotoCraftCore

enum TransformReferenceAPI {
  static let name = "transform.reference"
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "workspaceRevision": return ["type": "string", "format": "uuid"]
    case "visible": return BrushAPI.flag
    case "anchor": return BrushAPI.enumeration(CanvasAnchor.allCases.map(\.rawValue))
    case "point": return BrushAPI.object(["x": BrushAPI.number(-1_000_000, 1_000_000), "y": BrushAPI.number(-1_000_000, 1_000_000)], required: ["x", "y"])
    default: return [:]
    }
  }
  static var stateSchema: [String: Any] {
    let fields: [String: Any] = ["available": BrushAPI.flag, "active": BrushAPI.flag, "visible": BrushAPI.flag,
      "dragging": BrushAPI.flag, "custom": BrushAPI.flag, "workspaceRevision": schema("workspaceRevision"),
      "anchor": schema("anchor"), "point": ["anyOf": [["type": "null"], schema("point")]]]
    return BrushAPI.object(fields, required: Array(fields.keys).sorted())
  }
  static var capabilities: [String: Any] { [
    "command": name, "stateSchema": stateSchema, "presentationOnly": true, "defaultVisible": false,
    "coordinates": "point is the current document-coordinate reference point, including locations outside transform bounds; x/y within ±1000000. Stored draft-local coordinates follow existing affine/projective placement. anchor chooses a nine-position preset and clears the custom point. point and anchor are mutually exclusive; visible is independent.",
    "revision": "workspaceRevision is required in addition to the document revision. Native geometry/reference/preset/visibility/begin/end changes invalidate it. No-op edits retain it. Active pointer/commit/file/history/busy/stale/revoked work commits nothing.",
    "native": "Show Reference Point in Options, nine presets and direct pivot drag. Rotation/numeric scaling and Option-scaling use the pivot. Move follows existing object geometry. Applies to existing Free Transform/Transform Selection/pixel/mask/channel/layer and Content-Aware Scale drafts. Warp/filter workspaces retain separate controls.",
    "data": "Reference-only changes do not render a new image/contour, edit document bytes, add Undo/Actions or change the document revision. The final existing transform matrix is committed through shared native/API engines; samplers/archive formats are unchanged.",
    "cursor": "A visible pivot uses the scope cursor for all16Control/Command/Option/Shift combinations; no invented modifier action. Space before press retains Hand. Captured pivot drag, cancellation and focus/owner/session/tool/detach cleanup retain source state.",
    "limits": "Visibility is open-document/session presentation, copied when opening another workspace; complete Photoshop factory/persistence/global preference and modifier/visual/pixel/live/platform equivalence remain unqualified. Transform Again/repeat state remains open.",
    "adobe": "The pinned Firefly Photoshop v2 contract has no native transform-workspace reference-point endpoint. No Adobe route is invented; existing explicit matrix editing operations retain their contracts."
  ] }
}
extension AutomationCommand {
  @MainActor func applyTransformReference(_ store: EditorStore) throws {
    let expected = try actionUUID("workspaceRevision")
    guard expected == store.transformReferenceRevision else { throw AutomationFailure(status: 409, message: "Stale transform workspace. Refresh reference-point state.") }
    guard store.canEditTransformReference, store.transformReferenceGestureID == nil else { throw AutomationFailure(status: 409, message: "The transform workspace is unavailable or interacting.") }
    var anchor: CanvasAnchor?, point: PathPoint?, visible: Bool?
    if parameters["anchor"] != nil {
      guard let parsed = CanvasAnchor(rawValue: try string("anchor")) else { throw AutomationFailure(status: 400, message: "Invalid reference preset.") }; anchor = parsed
    }
    if let raw = parameters["point"] {
      let object = try BrushAPI.merge(raw, schema: TransformReferenceAPI.schema("point"), path: "point") as! [String: Any]
      point = .init(object["x"] as! Double, object["y"] as! Double)
    }
    if let raw = parameters["visible"] { guard case .bool(let value) = raw else { throw AutomationFailure(status: 400, message: "visible must be boolean.") }; visible = value }
    guard anchor != nil || point != nil || visible != nil, anchor == nil || point == nil else { throw AutomationFailure(status: 400, message: "Choose one point or preset with optional visibility.") }
    do { try store.setTransformReference(anchor: anchor, point: point, visible: visible, expected: expected) }
    catch { throw AutomationFailure(status: 422, message: error.localizedDescription) }
  }
}
@MainActor extension EditorStore {
  var transformReferenceState: [String: Any] {
    let point = transformDraft?.transformReferencePoint
    return ["available": canEditTransformReference && transformReferenceGestureID == nil, "active": transformDraft != nil,
      "visible": showTransformReferencePoint, "dragging": transformReferenceGestureID != nil,
      "custom": transformDraft?.customReferencePoint != nil,
      "workspaceRevision": transformReferenceRevision.uuidString,
      "anchor": transformDraft?.referenceAnchor.rawValue ?? CanvasAnchor.center.rawValue,
      "point": point.map { ["x": $0.x, "y": $0.y] } as Any? ?? NSNull()]
  }
}
