import Foundation
import PhotoCraftCore

extension LensCorrectionSettings {
  static var apiSchema:[String:Any] {
    func number(_ low:Double,_ high:Double,_ value:Double)->[String:Any] { ["type":"number","minimum":low,"maximum":high,"default":value] }
    let defaults=try! JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    var fields=[String:Any]()
    for key in ["distortion","redCyan","blueYellow","vignetteAmount","vertical","horizontal"] { fields[key]=number(-100,100,0) }
    fields["vignetteMidpoint"]=number(0,100,50);fields["angle"]=number(-360,360,0);fields["scale"]=number(5,800,100)
    for key in ["correctDistortion","correctVignette","correctCA","autoScale"] { fields[key]=["type":"boolean","default":defaults[key]!] }
    fields["edge"]=["type":"string","enum":Edge.allCases.map(\.rawValue),"default":"transparency"]
    fields["edgeColor"]=["type":"array","minItems":4,"maxItems":4,"items":number(0,1,0),"default":[0,0,0,1]]
    let point:[String:Any]=["type":"object","additionalProperties":false,"required":["x","y"],"properties":["x":number(-4,5,0),"y":number(-4,5,0)]]
    fields["straighten"]=["type":["array","null"],"minItems":2,"maxItems":2,"items":point,"description":"Distinct source-normalized line points. Adds the nearest horizontal/vertical correction to angle using actual filter-input dimensions. Smart Object input includes affine placement and preceding filters."]
    var profile:[String:Any]=["name":["type":"string","minLength":1,"maxLength":256,"default":"Custom"],"vignette":["type":"array","minItems":3,"maxItems":3,"items":number(-4,4,0),"default":[0,0,0]]]
    for k in ["k1","k2","p1","p2"] { profile[k]=number(-4,4,0) };for k in ["caRed","caBlue"] { profile[k]=number(-0.2,0.2,0) }
    fields["genericFocalLength"]=["type":["number","null"],"minimum":12,"maximum":200,"description":"Explicit opt-in generic35mm-equivalent estimate. Mutually exclusive with profile; no manufacturer matching."]
    fields["profile"]=["type":["object","null"],"additionalProperties":false,"properties":profile,"description":"Explicit calibration coefficients retained with the Smart Filter. No automatic manufacturer profile lookup is implied."]
    return ["type":"object","additionalProperties":false,"properties":fields]
  }
  static var apiCapabilities:[String:Any] {
    ["schema":apiSchema,"default":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())),
     "engine":"Native Brown–Conrady inverse map, radial red/blue fringe compensation, profile/custom vignette, perspective/rotation/scale, premultiplied Catmull–Rom resampling and transparent/extended/black/white/custom edges. Identity preserves source bytes.",
     "workspace":"Custom/profile controls, distortion drag, straighten line, pan/zoom/grid, preview, settings import/export, local Undo/Redo and document Cancel/OK. Settings files use this same JSON value.",
     "autoScale":"Samples all four image borders and three chromatic coordinates, searches up to800%, rejects if coverage cannot be achieved. Grid/preview settings are presentation-only.",
     "profiles":"Explicit coefficients and labelled generic estimates; no Adobe/manufacturer database or EXIF profile matching. Clients may provide their own coefficients. Vignette midpoint follows Adobe documented direction.",
     "persistence":"Editable Smart Filters require native30. Existing actions.manage/actions.play/actions.batch can store/play the same typed filter. Rasterized exports work; editable PSD/PSB descriptors are unsupported.",
     "limits":"8,388,608 source pixels, RGB composite, current filter selection/lock rules. RGB32 is a Photato extension. Exact Adobe pixels and live/physical platform checks remain open.",
     "adobe":"No dedicated pinned Photoshop v2 operation; unqualified lensCorrection actionJSON rejects explicitly. No Adobe route is invented."]
  }
}

@MainActor extension LensCorrectionWorkspace {
  var apiState:[String:Any] {
    ["settings":try! JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)),"preview":preview,"rendering":rendering,"tool":tool.rawValue,"zoom":zoom,"showGrid":showGrid,"gridSize":gridSize,"effectiveScale":effectiveScale,"error":error as Any? ?? NSNull(),"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty]
  }
}
