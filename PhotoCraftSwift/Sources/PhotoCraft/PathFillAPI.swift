import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PathFillAPI {
  static var schema:[String:Any]{BrushAPI.object([
    "contents":BrushAPI.enumeration(PathFillOptions.Contents.allCases.map(\.rawValue)),"color":PixelPaintAPI.schema("color"),
    "patternID":PixelPaintAPI.schema("patternID"),"placement":PixelPaintAPI.schema("placement"),
    "mode":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue)+["Clear"]),"opacity":BrushAPI.number(0.01,1),
    "preserveTransparency":BrushAPI.flag,"feather":BrushAPI.number(0,100),"antiAlias":BrushAPI.flag])}
  static var stateSchema:[String:Any]{BrushAPI.object(["available":BrushAPI.flag,"draftOpen":BrushAPI.flag,"settings":schema,"historyAvailable":BrushAPI.flag],required:["available","draftOpen","settings","historyAvailable"])}
  static func settings(_ value:PathFillOptions)->[String:Any]{
    var raw:[String:Any]=["contents":value.contents.rawValue,"mode":value.clear ? "Clear":value.mode.rawValue,"opacity":value.opacity,"preserveTransparency":value.preserveTransparency,"feather":value.feather,"antiAlias":value.antiAlias]
    if value.contents == .color{raw["color"]=[value.color.r,value.color.g,value.color.b,value.color.a]}
    if let id=value.patternID{raw["patternID"]=id;raw["placement"]=["scale":value.placement.scale,"angle":value.placement.angle,"phaseX":value.placement.phaseX,"phaseY":value.placement.phaseY]}
    return raw
  }
  static var capabilities:[String:Any]{["command":"path.paint","parameter":"fill","schema":schema,"stateSchema":stateSchema,"behavior":"Explicit fill shares native captured path coverage, original selection clipping, RGB raster expansion/protection and paint engine. Mode/opacity/contents/pattern/feather/AA and Clear/background safeguards produce one prepared Undo and portable Actions50. Document selection and path data remain unchanged.","legacy":"Omitting fill retains old brush-based Fill/Stroke Path contract. fill cannot combine with brush, stroke or simulatePressure parameters. Native menu and Option footer open options; ordinary footer retains legacy behavior pending live default/persistence qualification.","contents":"Foreground/background/custom/black/gray/white/pattern implemented. History is unavailable (422), with no invented history source. Pattern phase/scale API override reuses native sampler; exact Photoshop phase/kernel/defaults remain unqualified.","limits":"Static RGB raster; canvas16MP; existing target/API/Actions16MiB and source-pattern16MP limits. Feather0–100pixels and opacity1–100% use current working bounds, not asserted Photoshop maxima. Missing history/magnetic/multi-anchor/fitting/clipping/capacity/targets and completeG04remain major stillneeded.","Actions":"50only for captured path coverage/settings/assets/Clear; older41/42/49minimum formats retained. Replay captures coverage and resolves portable layer target, clipping the replay document's current selection. Dynamic Photoshop current-path/history descriptors are unqualified.","adobe":"No dedicated path fill route or unverified Photoshop action descriptor is invented in the pinned Adobe v2 contract."]}
  static func parse(_ value:AutomationValue,context:PathFillContext)throws->PathFillOptions {
    guard case .object(let f)=value,Set(f.keys).isSubset(of:["contents","color","patternID","placement","mode","opacity","preserveTransparency","feather","antiAlias"])else{throw AutomationFailure(status:400,message:"Fill must contain supported option fields.")}
    var result=PathFillOptions()
    if let raw=f["contents"]{guard case .string(let name)=raw,let kind=PathFillOptions.Contents(rawValue:name)else{throw AutomationFailure(status:400,message:"Unknown fill contents.")};result.contents=kind}
    if result.contents == .history{throw AutomationFailure(status:422,message:"History Fill is not implemented.")}
    if result.contents == .color {
      guard case .array(let values)=f["color"],values.count==4 else{throw AutomationFailure(status:400,message:"Color contents require RGBA.")}
      let rgba=try values.map{raw->Float in guard case .number(let n)=raw,n.isFinite,(0...1).contains(n)else{throw AutomationFailure(status:400,message:"Color channels must be0–1.")};return Float(n)}
      result.color=Pixel(rgba[0],rgba[1],rgba[2],rgba[3])
    }else if f["color"] != nil{throw AutomationFailure(status:400,message:"color is only used by Color contents.")}
    if result.contents == .pattern {
      guard !context.patternBusy else{throw AutomationFailure(status:409,message:"The pattern library is busy.")}
      guard case .string(let id)=f["patternID"],!id.isEmpty,id.utf8.count<=255,context.patterns.contains(where:{$0.id==id})else{throw AutomationFailure(status:404,message:"Choose an available saved pattern.")};result.patternID=id
      if let raw=f["placement"]{result.placement=try ShapeAPI.decode(PatternPlacement.self,raw,schema:PixelPaintAPI.schema("placement"),base:.init())}
    }else if f["patternID"] != nil || f["placement"] != nil{throw AutomationFailure(status:400,message:"Pattern settings require Pattern contents.")}
    if let raw=f["mode"]{guard case .string(let name)=raw else{throw AutomationFailure(status:400,message:"Invalid fill mode.")};if name=="Clear"{result.clear=true}else{guard let mode=BlendMode(rawValue:name)else{throw AutomationFailure(status:400,message:"Unknown fill mode.")};result.mode=mode}}
    for (key,path,range)in [("opacity",\PathFillOptions.opacity,0.01...1.0)] {if let raw=f[key]{guard case .number(let n)=raw,n.isFinite,range.contains(n)else{throw AutomationFailure(status:400,message:"Opacity must be0.01–1.")};result[keyPath:path]=Float(n)}}
    if let raw=f["feather"]{guard case .number(let n)=raw,n.isFinite,(0...100).contains(n)else{throw AutomationFailure(status:400,message:"Feather must be0–100px.")};result.feather=n}
    for (key,path)in [("preserveTransparency",\PathFillOptions.preserveTransparency),("antiAlias",\PathFillOptions.antiAlias)]{if let raw=f[key]{guard case .bool(let b)=raw else{throw AutomationFailure(status:400,message:"Fill flags must be boolean.")};result[keyPath:path]=b}}
    do{try result.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)};return result
  }
}
extension EditorStore {
  var pathFillState:[String:Any]{["available":canBeginPathFill,"draftOpen":pathFillDraft != nil,"settings":PathFillAPI.settings(pathFillDraft?.options ?? lastPathFill),"historyAvailable":false]}
}
