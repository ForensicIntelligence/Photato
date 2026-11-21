import Foundation
import PhotoCraftCore

enum PathGroupsAPI {
  static let select = "paths.select"
  static let transform = "paths.transform"
  static let warp = "paths.warp"
  static let isolate = "paths.isolate"
  static let commands = [select, transform, warp, isolate]

  static var targetFields: [String: Any] {
    ["target": PathTransformAPI.schema("target"), "id": PathTransformAPI.schema("id")]
  }

  static func schema(_ key: String, command: String) -> [String: Any] {
    switch key {
    case "targets":
      var fields = targetFields
      fields["components"] = PathTransformAPI.schema("components")
      fields["anchors"] = PathTransformAPI.schema("anchors")
      return ["type": "array", "minItems": command == select ? 0 : 1,
              "maxItems": PathTransformGroupRequest.maximumTargets,
              "items": BrushAPI.object(fields, required: ["target", "id"])]
    case "focus":
      return BrushAPI.object(targetFields, required: ["target", "id"])
    case "marquee", "extend": return PathAPI.schema(key)
    case "enabled": return BrushAPI.flag
    case "settings": return WarpDefinition.apiSchema
    case "matrixAfter": return SelectionTransformAPI.schema("matrix")
    default: return SelectionTransformAPI.schema(key)
    }
  }

  static var choicesStateSchema: [String: Any] {
    var fields = targetFields
    fields["selection"] = PathTransformAPI.selectionSchema
    return ["type": "array", "maxItems": PathTransformGroupRequest.maximumTargets,
            "items": BrushAPI.object(fields, required: ["target", "id", "selection"])]
  }

  static var capabilities: [String: Any] {
    [
      "commands": commands, "stateSchema": choicesStateSchema,
      "resultSchema": ["type": "object", "required": ["revision", "pathTransformSelections"],
                       "properties": ["revision": ["type": "string"], "pathTransformSelections": choicesStateSchema]],
      "selection": "Select saved paths, shape contours and vector masks together. A focused target remains available for Pen editing. A document-coordinate marquee applies to each selected path. Selection does not add Undo.",
      "transform": "Use one document-coordinate affine or projective matrix for all targets. Different targets may select different components or anchors. All targets commit in one Undo after validation, and resulting anchor indices are returned.",
      "warp": "Use Warp settings in document coordinates. Optional matrix runs before Warp and matrixAfter runs after it. Without sourceBounds, the selected contours after the first matrix define the mesh frame. Paths remain editable.",
      "warpStateSchema": warpStateSchema,
      "isolation": "Isolate the focused shape or vector mask owner in the Layers and Paths panels. This changes the editor view.",
      "isolationStateSchema": isolationStateSchema,
      "actions": "Native Actions version 77 retains the shared path matrix, version 78 adds Warp, and version 79 retains a transform after Warp.",
      "adobe": "The published Photoshop v2 endpoints do not define cross-layer path selection, transform, Warp or isolation."
    ]
  }

  static var isolationStateSchema: [String: Any] {
    BrushAPI.object(["available": BrushAPI.flag, "active": BrushAPI.flag,
                     "layerID": ["anyOf": [["type": "null"], PathTransformAPI.schema("id")]]],
                    required: ["available", "active", "layerID"])
  }

  static var warpStateSchema: [String: Any] {
    BrushAPI.object(["available": BrushAPI.flag, "active": BrushAPI.flag, "previewBusy": BrushAPI.flag,
                     "style": BrushAPI.enumeration(WarpStyle.allCases.map(\.rawValue)),
                     "mode": BrushAPI.enumeration(["idle", "warp", "freeTransform"]),
                     "matrixAfter": ["anyOf": [["type": "null"], SelectionTransformAPI.schema("matrix")]]],
                    required: ["available", "active", "previewBusy", "style", "mode", "matrixAfter"])
  }

  static func state(_ choices: [PathTransformChoice]) -> [[String: Any]] {
    choices.map { choice in
      let kind: String
      switch choice.target {
      case .saved: kind = "saved"
      case .vectorMask: kind = "vectorMask"
      case .shape: kind = "shape"
      }
      return ["target": kind, "id": choice.target.id.uuidString,
              "selection": PathTransformAPI.selection(choice.selection)]
    }
  }

  static func target(_ fields: [String: Any]) throws -> PathTransformTarget {
    guard let raw = fields["id"] as? String, let id = UUID(uuidString: raw) else {
      throw AutomationFailure(status: 400, message: "Supply a valid path target ID.")
    }
    switch fields["target"] as? String {
    case "saved": return .saved(id)
    case "vectorMask": return .vectorMask(id)
    case "shape": return .shape(id)
    default: throw AutomationFailure(status: 400, message: "Supply a path target kind.")
    }
  }

  private static func selection(_ fields: [String: Any]) throws -> PathTransformSelection {
    guard fields["components"] == nil || fields["anchors"] == nil else {
      throw AutomationFailure(status: 400, message: "Choose either components or anchors for each path.")
    }
    if let components = fields["components"] as? [Double] {
      guard Set(components).count == components.count else {
        throw AutomationFailure(status: 400, message: "Supply distinct component indices.")
      }
      return .components(components.map(Int.init))
    }
    if let points = fields["anchors"] as? [[String: Double]] {
      let anchors: [PathTransformAnchor] = try points.map {
        guard let component = $0["component"], let knot = $0["knot"] else {
          throw AutomationFailure(status: 400, message: "Supply an anchor's component and knot.")
        }
        return .init(component: Int(component), knot: Int(knot))
      }
      guard Set(anchors).count == anchors.count else {
        throw AutomationFailure(status: 400, message: "Supply distinct anchor indices.")
      }
      return .anchors(anchors)
    }
    return .all
  }

  static func choices(_ fields: [[String: Any]]) throws -> [PathTransformChoice] {
    let choices: [PathTransformChoice] = try fields.map { try .init(target($0), selection: selection($0)) }
    guard Set(choices.map(\.target)).count == choices.count else {
      throw AutomationFailure(status: 400, message: "Supply distinct path targets.")
    }
    return choices
  }
}

extension AutomationCommand {
  func pathWarpRequest() throws -> PathWarpRequest {
    let matrix = parameters["matrix"] == nil ? .identity : try selectionTransformOptions().0
    let after: ProjectiveTransform
    if let value = parameters["matrixAfter"] {
      do {
        let raw = try BrushAPI.merge(value, schema: SelectionTransformAPI.schema("matrix"), path: "matrixAfter") as! [Double]
        after = try ProjectiveTransform(raw)
      } catch let failure as AutomationFailure { throw failure }
      catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    } else { after = .identity }
    return try .init(choices: pathGroupChoices(), matrix: matrix, settings: warpSettings(), matrixAfter: after)
  }

  func pathGroupChoices() throws -> [PathTransformChoice] {
    guard let raw = parameters["targets"], let fields = try BrushAPI.merge(
      raw, schema: PathGroupsAPI.schema("targets", command: name), path: "targets"
    ) as? [[String: Any]] else {
      throw AutomationFailure(status: 400, message: "Supply path targets.")
    }
    return try PathGroupsAPI.choices(fields)
  }
}

@MainActor extension EditorStore {
  var pathIsolationState: [String: Any] {
    ["available": canIsolateFocusedPath, "active": pathIsolationLayerID != nil,
     "layerID": pathIsolationLayerID?.uuidString as Any? ?? NSNull()]
  }

  var pathWarpState: [String: Any] {
    let transform = selectionTransform
    let active = pathWarp
    let model = active ?? transform?.warpModel
    let result = active?.pathEdit ?? transform?.warpPreview
    return [
      "available": canBeginPathWarp,
      "active": active != nil,
      "previewBusy": active?.rendering ?? (model != nil && (transform?.loading == true || transform?.previewBusy == true)),
      "style": model?.settings.style.rawValue ?? WarpStyle.none.rawValue,
      "mode": active != nil ? "warp" : model != nil ? "freeTransform" : "idle",
      "matrixAfter": result?.request.matrixAfter.values as Any? ?? NSNull()
    ]
  }

  func configurePathGroup(_ command: AutomationCommand) throws {
    var choices = try command.pathGroupChoices()
    let focus = try command.parameters["focus"].map { raw -> PathTransformTarget in
      guard let fields = try BrushAPI.merge(raw, schema: PathGroupsAPI.schema("focus", command: command.name),
                                            path: "focus") as? [String: Any] else {
        throw AutomationFailure(status: 400, message: "Supply a focused path target.")
      }
      let target = try PathGroupsAPI.target(fields)
      guard choices.contains(where: { $0.target == target }) else {
        throw AutomationFailure(status: 400, message: "The focused path must be selected.")
      }
      return target
    }
    guard command.parameters["marquee"] != nil || command.parameters["extend"] == nil else {
      throw AutomationFailure(status: 400, message: "Supply a path marquee when setting extend.")
    }
    for choice in choices { _ = try PathTransform.path(choice.target, in: document) }
    if let raw = command.parameters["marquee"] {
      let rectangle = try command.pathMarquee(raw), extend = try command.pathFlag("extend", false)
      choices = try choices.map { choice in
        let path = try PathTransform.editablePath(choice.target, in: document)
        return .init(choice.target, selection: rectangle.selection(in: path, extending: extend ? choice.selection : nil))
      }
    } else {
      for choice in choices {
        if case .all = choice.selection { continue }
        _ = try PathTransform.bounds(PathTransform.path(choice.target, in: document), selection: choice.selection)
      }
    }
    setPathChoices(choices, focus: focus)
    if !usesPathTool, !choices.isEmpty { tool = .directSelection }
  }
}
