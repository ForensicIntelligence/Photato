import Foundation
import PhotoCraftCore

enum GradientToolAPI {
  static let commands = ["gradient.tool.configure", "gradient.fill.create", "gradient.paint"]
  static var definitionSchema: [String:Any] { (ShapeAPI.gradient["properties"] as! [String:Any])["gradient"] as! [String:Any] }
  static var definitionPatchSchema:[String:Any] {
    var schema=definitionSchema;schema["required"]=[String]();schema["minProperties"]=1;return schema
  }
  static var optionsSchema: [String:Any] {
    BrushAPI.object(["mode":BrushAPI.enumeration(GradientToolMode.allCases.map(\.rawValue)),
      "gradient":definitionPatchSchema,"style":BrushAPI.enumeration(GradientStyle.allCases.map(\.rawValue)),
      "reverse":BrushAPI.flag,"dither":BrushAPI.flag,"transparency":BrushAPI.flag,
      "opacity":BrushAPI.number(0,1),"blend":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue))])
  }
  static var strokeSchema: [String:Any] {
    let point=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000)],required:["x","y"])
    return BrushAPI.object(["gradient":definitionSchema,"start":point,"end":point,
      "style":BrushAPI.enumeration(GradientStyle.allCases.map(\.rawValue)),"reverse":BrushAPI.flag,
      "dither":BrushAPI.flag,"transparency":BrushAPI.flag,"opacity":BrushAPI.number(0,1),
      "mode":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue)),"mask":BrushAPI.flag],required:["gradient","start","end"])
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "options":optionsSchema
    case "fill":ShapeAPI.gradient
    case "stroke":strokeSchema
    case "reset","maskFromSelection":BrushAPI.flag
    case "opacity":BrushAPI.number(0,1)
    case "blend":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue))
    case "name":["type":"string","minLength":1,"maxLength":65_535]
    case "parentID":["type":["string","null"],"format":"uuid"]
    default:PathAPI.schema("layerID")
    }
  }
  static func object(_ options:GradientToolOptions, foreground:Pixel, background:Pixel)throws->[String:Any] {
    ["mode":options.mode.rawValue,"gradient":BrushAPI.json(try options.gradient.resolved(foreground:foreground,background:background)),
     "style":options.style.rawValue,"reverse":options.reverse,"dither":options.dither,"transparency":options.transparency,
     "opacity":options.opacity,"blend":options.blend.rawValue]
  }
  static var stateSchema:[String:Any] {
    var options=optionsSchema
    var fields=options["properties"] as! [String:Any];fields["gradient"]=definitionSchema;options["properties"]=fields
    options["required"]=["mode","gradient","style","reverse","dither","transparency","opacity","blend"]
    return BrushAPI.object(["options":options,"canConfigure":BrushAPI.flag,"canCreate":BrushAPI.flag,
      "canPaintActivePixels":BrushAPI.flag,"canPaintActiveMask":BrushAPI.flag],required:["options","canConfigure","canCreate","canPaintActivePixels","canPaintActiveMask"])
  }
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let layer=store.activeLayer
    let pixels:Bool;if case .raster=layer?.content {pixels=layer?.smartObject==nil}else{pixels=false}
    let unlocked=layer.map{!store.document.isLocked($0.id)} ?? false
    return ["options":(try? object(store.gradientOptions,foreground:store.brush.color,background:store.backgroundColor)) ?? [:],
      "canConfigure":store.canConfigureGradientCreation,"canCreate":store.canBeginGradientFill,
      "canPaintActivePixels":store.canConfigureGradientCreation && pixels && unlocked,
      "canPaintActiveMask":store.canConfigureGradientCreation && layer?.mask != nil && unlocked]
  }
  static var capabilities:[String:Any] {
    ["commands":commands,"optionsSchema":optionsSchema,"strokeSchema":strokeSchema,"fillSchema":ShapeAPI.gradient,
     "stateSchema":stateSchema,"state":"gradientTool","actionsVersion":51,
     "resultSchema":["type":"object","required":["revision","gradientTool"],"properties":["revision":["type":"string"],"gradientTool":stateSchema]],
     "behavior":"Native Options defaults and toolbar preset selection configure future gradients only. Existing fills use Properties/canvas/gradient.fill.patch. Tool configuration is atomic, advances the shared view revision, preserves pixels/history and does not select a different tool. Creation and Classic painting use the shared native factories and prepared one-Undo commands.",
     "colors":"API inputs contain captured gradient colours. State resolves native foreground/background references at read time. Partial tool configuration preserves native dynamic references unless gradient is supplied; reset restores factory references.",
     "creation":"fill required; name/parentID/opacity/blend optional. Parent defaults to active group/parent; explicit null selects root. maskFromSelection defaults to current selection presence and applies exact captured coverage. An explicit true without selection creates Reveal All, matching the existing command.",
     "painting":"Explicit layerID/stroke; pixel or pixel-mask target only. Core selection/transparency locks/geometry/admission apply. Style defaults Linear, reverse false, dither/transparency true, opacity1 and blend Normal. API does not sample UI creation defaults implicitly.",
     "limits":"Existing gradient validation,1000colour/1000opacity stops, Core painting/admission and API body/sharing budgets. Smart Filter/auxiliary/mode-channel painting, preset-library automation, canvas opacity controls, all GRD/noise/dither/default/output/platform/performance cases remain open.",
     "adobe":"Photato extension; no corresponding qualified desktop-gradient route/actionJSON operation added to the pinned Adobe v2 contract."]
  }
}
private struct GradientStrokePayload:Decodable {
  let gradient:GradientDefinition
  let start,end:PathPoint
  let style:GradientStyle
  let reverse,dither,transparency,mask:Bool
  let opacity:Float
  let mode:BlendMode
  func stroke()throws->GradientStroke {
    try GradientToolCommands.stroke(gradient:gradient,start:start,end:end,style:style,reverse:reverse,
      dither:dither,transparency:transparency,opacity:opacity,blend:mode,mask:mask)
  }
}
extension AutomationCommand {
  @MainActor func gradientToolOptions(_ store:EditorStore)throws->GradientToolOptions {
    let reset=try pathFlag("reset",false)
    let original=reset ? GradientToolOptions():store.gradientOptions
    guard reset || parameters["options"] != nil else{throw AutomationFailure(status:400,message:"Supply options or reset:true.")}
    var result=original
    if let raw=parameters["options"] {
      guard case .object(let fields)=raw,!fields.isEmpty else{throw AutomationFailure(status:400,message:"Supply a nonempty Gradient options patch.")}
      let base=try GradientToolAPI.object(original,foreground:store.brush.color,background:store.backgroundColor)
      let merged=try BrushAPI.merge(raw,schema:GradientToolAPI.optionsSchema,base:base,path:"options")
      result=try JSONDecoder().decode(GradientToolOptions.self,from:JSONSerialization.data(withJSONObject:merged))
      if case .object(let gradientFields)?=fields["gradient"] {
        if gradientFields["colors"]==nil{result.gradient.colors=original.gradient.colors}
        if gradientFields["opacity"]==nil{result.gradient.opacity=original.gradient.opacity}
      }else{result.gradient=original.gradient}
    }
    do {try result.gradient.validate();guard result.opacity.isFinite,(0...1).contains(result.opacity)else{throw CraftError.invalid("Invalid gradient opacity.")}}
    catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    return result
  }
  func gradientCreateCommand(in document:CraftDocument)throws->Command {
    guard let raw=parameters["fill"]else{throw AutomationFailure(status:400,message:"Supply a Gradient Fill.")}
    let value=try BrushAPI.merge(raw,schema:ShapeAPI.gradient,path:"fill")
    let fill=try JSONDecoder().decode(GradientFill.self,from:JSONSerialization.data(withJSONObject:value))
    let parentID:UUID?
    if let raw=parameters["parentID"] {if case .null=raw{parentID=nil}else{parentID=try actionUUID("parentID")}}
    else {parentID=document.layers.first(where:{$0.id==document.activeLayerID}).flatMap{$0.isGroup ? $0.id:$0.parentID}}
    let name=try parameters["name"].map{_ in try string("name")} ?? "Gradient Fill"
    let opacity=try parameters["opacity"].map{_ in Float(try number("opacity",range:0...1))} ?? 1
    let blend:BlendMode
    if parameters["blend"] != nil {guard let mode=BlendMode(rawValue:try string("blend"))else{throw AutomationFailure(status:400,message:"Invalid gradient blend mode.")};blend=mode}else{blend = .normal}
    do {
      let layer=try GradientToolCommands.layer(fill:fill,in:document,name:name,parentID:parentID,opacity:opacity,blend:blend)
      return .addGradientFill(layer,try pathFlag("maskFromSelection",document.selection != nil))
    }catch let e as AutomationFailure{throw e}catch{throw AutomationFailure(status:422,message:error.localizedDescription)}
  }
  func gradientPaintCommand(in document:CraftDocument)throws->Command {
    let id=try actionUUID("layerID")
    guard let layer=document.layers.first(where:{$0.id==id})else{throw AutomationFailure(status:404,message:"Gradient paint layer not found.")}
    guard !document.isLocked(id)else{throw AutomationFailure(status:422,message:"Unlock the gradient paint target and its parent groups.")}
    guard let raw=parameters["stroke"]else{throw AutomationFailure(status:400,message:"Supply a Classic Gradient stroke.")}
    let base:[String:Any]=["style":GradientStyle.linear.rawValue,"reverse":false,"dither":true,"transparency":true,"opacity":1,"mode":BlendMode.normal.rawValue,"mask":false]
    let merged=try BrushAPI.merge(raw,schema:GradientToolAPI.strokeSchema,base:base,path:"stroke")
    let stroke=try JSONDecoder().decode(GradientStrokePayload.self,from:JSONSerialization.data(withJSONObject:merged)).stroke()
    if stroke.mask {guard layer.mask != nil else{throw AutomationFailure(status:422,message:"This layer has no pixel mask.")}}
    else {guard case .raster=layer.content,layer.smartObject==nil else{throw AutomationFailure(status:422,message:"Classic Gradient requires an ordinary pixel layer.")}}
    return .paintGradient(id,stroke)
  }
}
