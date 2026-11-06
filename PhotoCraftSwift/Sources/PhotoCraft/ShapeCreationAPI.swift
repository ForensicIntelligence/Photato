import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ShapeCreationAPI {
  static var pointSchema:[String:Any]{BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000)],required:["x","y"])}
  static var draftSchema:[String:Any]{["anyOf":[["type":"null"],BrushAPI.object(["kind":BrushAPI.enumeration(["rectangle","ellipse"]),"point":pointSchema,"fromCenter":BrushAPI.flag,"linkedCorners":BrushAPI.flag,"definition":ShapeAPI.definition,"mode":ShapeAPI.schema("mode"),"combine":ShapeAPI.schema("combine")],required:["kind","point","fromCenter","linkedCorners","definition","mode","combine"])]]}
  static var capabilities:[String:Any]{[
    "nativeKinds":["rectangle","ellipse"],"command":"shape.edit","operation":"create","pointSchema":pointSchema,
    "parameters":"point plus optional fromCenter/combine, or the existing transform; mutually exclusive. fromCenter/combine require point. Precise placement needs one parametric component with identity local transform and no path override. Old transform clients retain their contract.",
    "coordinates":"point is the top-left logical origin, or the width/height center when fromCenter is true. Existing local dimensions/radii/styles remain; combine appends geometry in the target shape's local coordinates with its existing paint.",
    "native":"A click without movement opens Create Rectangle/Ellipse. Dragging retains the existing drawing path. The dialog captures point/mode/target/operation/resources; Cancel changes no document/history. Option at click initializes From Center; Shift/Control/Command have no extra precise-dialog effect. Physical Photoshop combined-modifier behavior remains unqualified.",
    "limits":"Existing geometry32768/8MP shape rasterization and renderer/target/color-mode limits remain. Other primitive click dialogs, live corner widgets/controls, exact defaults/persistence/rounding and full G03 remain functional stillneeded where missing.",
    "qualification":"Public Adobe rectangle/ellipse guidance; no current live Photoshop byte/default/gesture proof. Native/API share command preparation and history; no new command/archive/action version or dedicated Adobe endpoint."]}
}
extension AutomationCommand {
  func preciseShapeCreation(_ definition:ShapeDefinition,mode:ShapeOutputMode,target:UUID?,name:String)throws->ShapeCreationRequest? {
    guard let raw=parameters["point"] else {
      guard parameters["fromCenter"]==nil,parameters["combine"]==nil else{throw AutomationFailure(status:400,message:"fromCenter and combine require point.")};return nil
    }
    guard parameters["transform"]==nil,case .object(let fields)=raw,Set(fields.keys)==["x","y"],
      case .number(let x)=fields["x"],case .number(let y)=fields["y"],x.isFinite,y.isFinite,abs(x)<=1_000_000,abs(y)<=1_000_000 else{throw AutomationFailure(status:400,message:"Supply a finite point, or transform, not both.")}
    var center=false,combine:PathOperation?
    if let raw=parameters["fromCenter"]{guard case .bool(let value)=raw else{throw AutomationFailure(status:400,message:"fromCenter must be boolean.")};center=value}
    if let raw=parameters["combine"],case .null=raw {}else if let raw=parameters["combine"] {
      guard case .string(let value)=raw,let operation=PathOperation(rawValue:value)else{throw AutomationFailure(status:400,message:"Invalid shape combination.")};combine=operation
    }
    let request=ShapeCreationRequest(definition:definition,point:.init(x:x,y:y),fromCenter:center,mode:mode,target:target,combine:combine,name:name)
    do{_ = try request.placement();guard combine==nil || mode == .shape else{throw CraftError.invalid("Combine requires shape mode.")}}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    return request
  }
}
