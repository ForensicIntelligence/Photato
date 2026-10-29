import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum SkyAPI {
  static let commands=["selection.sky","sky.replace","sky.library"]
  static var selection:[String:Any]{BrushAPI.object(["threshold":BrushAPI.number(0,100),"softness":BrushAPI.number(0,100)])}
  static var settings:[String:Any]{
    var fields:[String:Any]=["selection":selection,"scale":BrushAPI.number(10,500),"flip":BrushAPI.flag,"offsetX":BrushAPI.number(-1_000_000,1_000_000),"offsetY":BrushAPI.number(-1_000_000,1_000_000),"lightingMode":BrushAPI.enumeration(["multiply","screen"]),"output":BrushAPI.enumeration(["layers","duplicate"])]
    for k in ["shiftEdge","brightness","temperature"]{fields[k]=BrushAPI.number(-100,100)}
    for k in ["fadeEdge","foregroundLighting","edgeLighting","colorAdjustment"]{fields[k]=BrushAPI.number(0,100)}
    return BrushAPI.object(fields)
  }
  static var strokes:[String:Any]{["type":"array","maxItems":128,"items":BrushAPI.object(["points":BrushAPI.schema("points"),"size":BrushAPI.number(1,2048),"hardness":BrushAPI.number(0,1),"opacity":BrushAPI.number(0,1),"add":BrushAPI.flag],required:["points"])]}
  static func schema(_ key:String,command:String)->[String:Any]{switch key{
    case "settings":return command == "selection.sky" ? selection:settings
    case "strokes":return strokes
    case "skyID","sourceLayerID","layerID":return ["type":"string","format":"uuid"]
    case "sampleAllLayers","useSelection":return BrushAPI.flag
    case "mode":return SelectionToolAPI.schema("mode")
    case "operation":return BrushAPI.enumeration(["list","import","rename","delete","export"])
    case "data":return ["type":"string","contentEncoding":"base64","maxLength":3_000_000]
    default:return ["type":"string","minLength":1,"maxLength":255]
  }}
  static var stateSchema:[String:Any]{
    let nullableSettings:[String:Any]=["anyOf":[["type":"null"],settings]],nullableID:[String:Any]=["anyOf":[["type":"null"],["type":"string","format":"uuid"]]]
    let preset=BrushAPI.object(["id":["type":"string","format":"uuid"],"name":["type":"string"],"bytes":BrushAPI.number(1,16*1024*1024,integer:true)],required:["id","name","bytes"])
    let fields:[String:Any]=["canSelect":BrushAPI.flag,"canReplace":BrushAPI.flag,"workspaceOpen":BrushAPI.flag,"previewBusy":BrushAPI.flag,"settings":nullableSettings,"skyID":nullableID,"sourceLayerID":nullableID,"useSelection":BrushAPI.flag,"strokeCount":BrushAPI.number(0,128,integer:true),"libraryRevision":BrushAPI.number(0,Double(Int32.max),integer:true),"library":["type":"array","maxItems":64,"items":preset],"libraryError":["anyOf":[["type":"null"],["type":"string"]]]]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var resultSchema:[String:Any]{["type":"object","required":["revision","sky"],"properties":["revision":["type":"string"],"sky":stateSchema]]}
  static var libraryResultSchema:[String:Any]{["type":"object","required":["revision","state"],"properties":["revision":["type":"string"],"state":stateSchema,"skyID":["type":"string","format":"uuid"],"data":["type":"string","contentEncoding":"base64"]]]}
  static var capabilities:[String:Any]{["commands":commands,"settingsSchema":settings,"selectionSettingsSchema":selection,"strokeSchema":strokes,"stateSchema":stateSchema,"resultSchema":resultSchema,"libraryResultSchema":libraryResultSchema,"defaults":BrushAPI.json(SkyReplacementSettings()),"algorithm":"Native Swift translation of PhotoCraft's classical sky segmentation; no downloaded model or cloud processing. Replacement is native mask/transform/adjustment composition.","outputs":"Editable group retaining imported sky pixels, canvas-space mask, Sky Brightness/Temperature and Foreground Lighting/Color/Edge adjustments; or duplicate merged layer. One native Undo transaction. Current selection is preserved by replacement.","sources":"skyID from the optional persistent user library or sourceLayerID for existing raw raster content. Exactly one is required. useSelection:true uses the current selection as the initial mask instead of detection.","limits":"Select Sky native16MP; replacement and sky images8,388,608 pixels. API sharing4,194,304 pixels/64 layers/128MiB; request4MiB; imported base64<=3000000 characters. Native library64 entries/48MiB image data/64MiB file; each image<=16MiB.128 strokes,4096 points each,134217728 cumulative mask-pixel visits.","actions":"Select Sky records explicit coverage in Action library4. Sky Replacement recording is explicitly unsupported; direct desktop/API/history/native archive32 work.","qualification":"No dedicated Adobe v2 sky route is claimed. Complete preset/.sky transport, model/pixel/default/layer-structure equivalence and physical/live platform qualification remain open."]}
  static func decode<T:Codable>(_ type:T.Type,_ value:AutomationValue?,schema:[String:Any],default base:T)throws->T {
    guard let value else{return base};let raw=try BrushAPI.merge(value,schema:schema,base:BrushAPI.json(base),path:"sky settings")
    do{return try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:raw))}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
}
extension AutomationCommand {
  func skyStrokes()throws->[SkyMaskStroke]{
    guard let v=parameters["strokes"] else{return []};let raw=try BrushAPI.merge(v,schema:SkyAPI.strokes,path:"sky strokes") as! [[String:Any]]
    return try raw.map{fields in
      let points=try (fields["points"] as! [[String:Any]]).map{item in var item=item;if item["pressure"]==nil{item["pressure"]=1};return try JSONDecoder().decode(StrokePoint.self,from:JSONSerialization.data(withJSONObject:item))}
      let stroke=SkyMaskStroke(points:points,size:(fields["size"] as? NSNumber)?.doubleValue ?? 40,hardness:(fields["hardness"] as? NSNumber)?.floatValue ?? 0.5,opacity:(fields["opacity"] as? NSNumber)?.floatValue ?? 1,add:fields["add"] as? Bool ?? true);try stroke.validate();return stroke
    }
  }
}
@MainActor extension EditorStore {
  var skyState:[String:Any]{["canSelect":canSelectSky,"canReplace":canReplaceSky,"workspaceOpen":skyWorkspace != nil,"previewBusy":skyWorkspace?.rendering ?? false,"settings":skyWorkspace.map{BrushAPI.json($0.state.settings)} ?? NSNull(),"skyID":skyWorkspace?.state.skyID?.uuidString as Any? ?? NSNull(),"sourceLayerID":skyWorkspace?.state.sourceLayerID?.uuidString as Any? ?? NSNull(),"useSelection":skyWorkspace?.state.useSelection ?? false,"strokeCount":skyWorkspace?.state.strokes.count ?? 0,"libraryRevision":skies.revision,"library":skies.skies.map{["id":$0.id.uuidString,"name":$0.name,"bytes":$0.data.count] as [String:Any]},"libraryError":skies.loadError as Any? ?? NSNull()]}
}
extension AutomationService {
  func manageSkies(_ command:AutomationCommand,store:EditorStore,shareID:UUID)async throws->[String:Any]{
    let op=try command.string("operation"),allowed:[String:Set<String>]=["list":[],"import":["name","data"],"rename":["skyID","name"],"delete":["skyID"],"export":["skyID"]]
    guard let fields=allowed[op],Set(command.parameters.keys).subtracting(["operation"]).isSubset(of:fields) else{throw AutomationFailure(status:400,message:"Unknown or irrelevant sky library parameter.")}
    var newID:UUID?
    switch op {
    case "import":
      guard case .string(let text)=command.parameters["data"],text.utf8.count<=3_000_000,let data=Data(base64Encoded:text) else{throw AutomationFailure(status:400,message:"Supply bounded base64 sky image data.")}
      let preset=SkyPreset(name:try command.string("name"),data:data),expectedToken=token,expectedRevision=revision(store),generation=store.layerPanelGeneration
      store.geometryBusy=true;defer{if store.layerPanelGeneration==generation{store.geometryBusy=false;store.geometryTask=nil}}
      let worker=Task.detached(priority:.userInitiated){_=try preset.document();try Task.checkCancellation()}
      store.geometryTask=Task{await withTaskCancellationHandler{_=try? await worker.value}onCancel:{worker.cancel()}}
      try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();prune()
      guard store.geometryTask?.isCancelled != true,isRunning,token==expectedToken,revision(store)==expectedRevision,shares.contains(where:{$0.id==shareID}) else{throw AutomationFailure(status:409,message:"Sky import was cancelled or document sharing changed.")}
      try store.skies.add(preset);newID=preset.id
    case "delete":try store.skies.remove(command.actionUUID("skyID"))
    case "rename":try store.skies.rename(command.actionUUID("skyID"),command.string("name"))
    case "export":let preset=try store.skies.preset(command.actionUUID("skyID"));return ["state":store.skyState,"revision":revision(store),"skyID":preset.id.uuidString,"data":preset.data.base64EncodedString()]
    default:break
    }
    var result:[String:Any]=["state":store.skyState,"revision":revision(store)];if let newID{result["skyID"]=newID.uuidString};return result
  }
}
