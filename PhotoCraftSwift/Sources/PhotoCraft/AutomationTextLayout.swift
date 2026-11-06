import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum TextLayoutAPI {
  static let command="text.layout"
  static var warp:[String:Any]{BrushAPI.object(["style":BrushAPI.enumeration(WarpStyle.allCases.filter{$0 != .custom}.map(\.rawValue)),"bend":BrushAPI.number(-100,100),"horizontalDistortion":BrushAPI.number(-100,100),"verticalDistortion":BrushAPI.number(-100,100),"vertical":BrushAPI.flag])}
  static var settings:[String:Any]{BrushAPI.object(["mode":BrushAPI.enumeration(TextGeometry.Mode.allCases.map(\.rawValue)),"width":BrushAPI.number(1,16384),"height":BrushAPI.number(1,16384),"path":PathAPI.path,"warp":warp,"fit":BrushAPI.flag,"reverse":BrushAPI.flag,"start":BrushAPI.number(0,1),"end":BrushAPI.number(0,1),"offset":BrushAPI.number(-4096,4096),"wordSpacing":BrushAPI.number(-4096,4096),"lineSpacing":BrushAPI.number(-4096,4096)])}
  static func decode(_ value:AutomationValue)throws->TextGeometry {
    do {
      let merged=try BrushAPI.merge(value,schema:settings,base:BrushAPI.json(TextGeometry()))
      let result=try JSONDecoder().decode(TextGeometry.self,from:JSONSerialization.data(withJSONObject:merged));try result.validate();return result
    }catch let error as AutomationFailure{throw error}
    catch{throw AutomationFailure(status:400,message:"Invalid text layout: \(error.localizedDescription)")}
  }
  static var capabilities:[String:Any]{["command":command,"settingsSchema":settings,"nativeArchiveVersion":35,"actionsVersion":7,"nativePathEditing":PathTypeAPI.capabilities,"coordinates":"Geometry uses logical type pixels, before the layer affine transform. start/end are fractions of baseline length; offset follows its normal. text.layout preserves the logical anchor and mask placement. pathID copies a saved document path into type coordinates; subsequent path edits are independent. Full text.create/set descriptions may include geometry.","behavior":"Editable Warp, text on/inside paths, Block/Circle/Arch/Bow and Dynamic Fit share native glyph shaping, bounded outlines, desktop preview, Cancel and one Undo transaction. enabled=false removes geometry. settings are a complete replacement with defaults for omitted fields.","limits":["utf16":16384,"outlinePoints":2000000,"pixels":16777216],"adobe":"No dedicated path/warp/Dynamic Text field or endpoint in the pinned v2 contract. Native extensions only; no invented Adobe routes. Editable shaped PSD export rejects until its mappings are qualified.","qualification":"Native layout and source-derived warp approximations. Vertical shaped type, bitmap/color glyphs, exact Adobe fitting/composers/warps, live path delimiter gestures, PSD and platform qualification remain open."]}
}
extension AutomationCommand {
  func textLayoutCommand(_ document:CraftDocument)throws->Command {
    let id=try actionUUID("layerID")
    guard let layer=document.layers.first(where:{$0.id==id}),case .text(let original)=layer.content else{throw AutomationFailure(status:404,message:"Type layer not found.")}
    var text=original.promoted(dpi:document.pixelsPerInch)
    let enabled=try pathFlag("enabled",true)
    if enabled {
      guard let raw=parameters["settings"] else{throw AutomationFailure(status:400,message:"Layout settings are required.")}
      var settings=raw
      if parameters["pathID"] != nil {
        let pathID=try actionUUID("pathID")
        guard let named=document.paths?.first(where:{$0.id==pathID}),case .object(var fields)=settings else{throw AutomationFailure(status:400,message:"Saved path or layout settings not found.")}
        let origin=try NativeTextLayout.metrics(original,dpi:document.pixelsPerInch).origin,toLocal=try Transform2D.translation(origin.x,origin.y) * layer.coordinateTransform.inverted()
        fields["path"]=try JSONDecoder().decode(AutomationValue.self,from:JSONEncoder().encode(named.path.transformed(toLocal)));settings = .object(fields)
      }
      text.typography?.geometry=try TextLayoutAPI.decode(settings)
    }else{
      guard parameters["settings"]==nil,parameters["pathID"]==nil else{throw AutomationFailure(status:400,message:"Removing a text layout takes no settings or path.")}
      text.typography?.geometry=nil
    }
    return try ShapedTextLayout.replacement(layer,content:text,document:document)
  }
}
