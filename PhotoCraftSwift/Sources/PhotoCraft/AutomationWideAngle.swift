import Foundation
import PhotoCraftCore

extension WideAngleSettings {
  static var apiSchema:[String:Any] {
    func number(_ low:Double,_ high:Double,_ value:Double)->[String:Any] { ["type":"number","minimum":low,"maximum":high,"default":value] }
    let point:[String:Any]=["type":"object","additionalProperties":false,"required":["x","y"],"properties":["x":number(0,1,0),"y":number(0,1,0)]]
    let constraint:[String:Any]=["type":"object","additionalProperties":false,"required":["points"],"properties":[
      "points":["type":"array","minItems":2,"maxItems":32,"items":point],"closed":["type":"boolean","default":false],
      "orientations":["type":"array","maxItems":32,"items":["type":"string","enum":Orientation.allCases.map(\.rawValue)],"default":[]],
      "angles":["type":"array","maxItems":32,"items":number(-360,360,0),"default":[]]],
      "description":"Open polyline or closed polygon (at least3 points). Distinct consecutive endpoints, normalized to actual filter-input pixels after Smart Object placement/prior filters. orientations/angles are empty or exactly one entry per segment; empty means free/zero. Angles are clockwise degrees from horizontal."]
    return ["type":"object","additionalProperties":false,"properties":[
      "model":["type":"string","enum":Model.allCases.map(\.rawValue),"default":"auto"],"focalLength":number(0,200,0),"cropFactor":number(0.1,10,1),"scale":number(5,400,100),
      "interpolation":["type":"string","enum":Resampling.allCases.map(\.rawValue),"default":Resampling.bicubic.rawValue],
      "constraints":["type":"array","maxItems":64,"items":constraint,"default":[],"description":"At most128 total segments."]]]
  }
  static var apiCapabilities:[String:Any] {
    ["schema":apiSchema,"default":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())),
     "engine":"Native camera-ray constraints and sparse similarity mesh. Perspective, equidistant Fisheye, cylindrical Panorama and Full Spherical projections. Free/horizontal/vertical/arbitrary-angle lines and polygon edges. Fixed extent with transparent uncovered pixels.",
     "auto":"Aspect ratio within0.01 of2:1 selects Full Spherical; explicit focalLength*cropFactor below17mm selects Fisheye; otherwise Perspective. Zero focal length defaults to12mm for Fisheye,24mm otherwise. This is a heuristic; no As Shot, EXIF/manufacturer or Photomerge calibration is implied.",
     "workspace":"Line/polygon constraint creation, point/line dragging, per-edge orientation, hand/zoom, mesh/constraint overlays, preview, local Undo/Redo, settings JSON files and document Cancel/OK.",
     "persistence":"Editable Smart Filters require native31. Shared typed filter.apply/smartFilter.set and recorded Actions/Batch. Editable PSD/PSB descriptors unsupported; rasterized output supported.",
     "limits":"8,388,608 input pixels;64 constraints/128 total segments/32 points each. Antipodal or horizon-crossing constraints reject. No-constraint scale100 preserves source bytes. RGB8/16 encoded and RGB32 linear processing, selection and locks. No Adobe pixel-equivalence or live/platform claim.",
     "adobe":"No dedicated pinned Photoshop v2 operation; unsupported adaptiveWideAngle actionJSON rejects. No invented Adobe route."]
  }
}
@MainActor extension WideAngleWorkspace {
  var apiState:[String:Any] {
    ["settings":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)),"tool":tool.rawValue,"preview":preview,"rendering":rendering,"zoom":zoom,"showConstraints":showConstraints,"showMesh":showMesh,"selectedConstraint":selected,"selectedSegment":selectedSegment,"pendingPolygonPoints":polygon.count,"resolvedModel":resolvedModel.rawValue,"canUndo":!undoStates.isEmpty || !polygon.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()]
  }
}
