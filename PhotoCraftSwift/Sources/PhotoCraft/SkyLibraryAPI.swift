import Foundation
import PhotoCraftCore

enum SkyLibraryAPI {
  static let fields:[String:Set<String>]=[
    "list":[],"import":["name","data","groupID"],"importBatch":["images","groupID"],
    "rename":["skyID","name"],"delete":["skyID"],"export":["skyID"],
    "group.create":["name"],"group.rename":["groupID","name"],
    "group.delete":["groupID","removeSkies"],"move":["skyIDs","groupID"]]
  static let required:[String:Set<String>]=[
    "list":[],"import":["name","data"],"importBatch":["images"],"rename":["skyID","name"],
    "delete":["skyID"],"export":["skyID"],"group.create":["name"],
    "group.rename":["groupID","name"],"group.delete":["groupID","removeSkies"],"move":["skyIDs","groupID"]]
  static var definition:AutomationCommand.Definition {
    let keys=fields.values.reduce(into:Set<String>(),{$0.formUnion($1)})
    var parameters=Dictionary(uniqueKeysWithValues:keys.map{($0,"See sky library operation schema")});parameters["operation"]="Sky library operation"
    return .init(name:"sky.library",parameters:parameters,description:"Manage sky groups, membership and atomic image imports without editing document pixels or history.",optionalParameters:keys)
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "operation":return BrushAPI.enumeration(fields.keys.sorted())
    case "groupID":return ["anyOf":[VariablesAPI.uuid,["type":"null"]]]
    case "skyID":return VariablesAPI.uuid
    case "skyIDs":return ["type":"array","minItems":1,"maxItems":64,"uniqueItems":true,"items":VariablesAPI.uuid]
    case "removeSkies":return BrushAPI.flag
    case "data":return ["type":"string","contentEncoding":"base64","maxLength":3_000_000]
    case "images":return ["type":"array","minItems":1,"maxItems":64,"items":BrushAPI.object(["name":schema("name"),"data":schema("data")],required:["name","data"])]
    default:return ["type":"string","minLength":1,"maxLength":255]
    }
  }
  static var parameterSchema:[String:Any] {
    var result=BrushAPI.object(Dictionary(uniqueKeysWithValues:definition.parameters.keys.map{($0,schema($0))}),required:["operation"])
    result["oneOf"]=fields.keys.sorted().map{op->[String:Any]in
      var fields=Dictionary(uniqueKeysWithValues:Self.fields[op]!.map{($0,schema($0))});fields["operation"]=["const":op]
      if op=="group.rename" || op=="group.delete"{fields["groupID"]=VariablesAPI.uuid}
      return BrushAPI.object(fields,required:required[op]!.union(["operation"]).sorted())
    }
    return result
  }
  static var capabilities:[String:Any]{[
    "operations":fields.keys.sorted(),"parameterSchema":parameterSchema,"libraryVersion":2,
    "groups":"Up to64 named, flat groups with stable UUIDs. Images have optional groupID; null means Ungrouped. Removing a group requires explicit removeSkies. False keeps every member image and UUID; true removes members from the library. Existing document layers are independent.",
    "imports":"Native Import accepts multiple images. API importBatch requires images:[{name,data}] and optional groupID. All images decode and the final library validates before one atomic persistence/publication. No partial import on invalid image, capacity/storage failure, cancellation or changed source/library/sharing.",
    "state":"groups, per-image groupID, groupFilter, groupDialogOpen and canManageGroups extend existing sky state. Native group filters/moves are presentation/library operations; document pixels/selection/dirty/history stay unchanged.",
    "compatibility":"Version1 libraries load without groups and upgrade on the next successful edit. Unknown/corrupt libraries remain preserved and editing disabled. The internal plist is not Adobe .sky interchange.",
    "limits":"64images/64groups/48MiB aggregate image data/64MiB library;16MiB per native image. API retains4MiB request and3000000base64 characters per image; these are separate budgets. No bundled default skies or recents, nested groups, drag reorder or .sky compatibility claimed."
  ]}
}
extension AutomationCommand {
  func skyGroupID()throws->UUID? {
    guard let value=parameters["groupID"] else{return nil}
    if case .null=value{return nil};return try actionUUID("groupID")
  }
  func importedSkies(batch:Bool)throws->[SkyPreset] {
    let values:[[String:AutomationValue]]
    if batch{
      guard case .array(let items)=parameters["images"],!items.isEmpty,items.count<=64 else{throw AutomationFailure(status:400,message:"Supply1–64 sky images.")}
      values=try items.map{guard case .object(let v)=$0,Set(v.keys)==["name","data"] else{throw AutomationFailure(status:400,message:"Each sky image requires only name and data.")};return v}
    }else{values=[["name":parameters["name"] ?? .null,"data":parameters["data"] ?? .null]]}
    return try values.map{v in
      guard case .string(let name)=v["name"],!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=255,
        case .string(let text)=v["data"],text.utf8.count<=3_000_000,let data=Data(base64Encoded:text) else{throw AutomationFailure(status:400,message:"Supply a name and bounded base64 sky image data.")}
      return SkyPreset(name:name,data:data)
    }
  }
}
extension AutomationService {
  func manageSkies(_ command:AutomationCommand,store:EditorStore,shareID:UUID)async throws->[String:Any]{
    let op=try command.string("operation"),keys=Set(command.parameters.keys).subtracting(["operation"])
    guard let allowed=SkyLibraryAPI.fields[op],keys.isSubset(of:allowed),SkyLibraryAPI.required[op]!.isSubset(of:keys) else{throw AutomationFailure(status:400,message:"Missing, unknown or irrelevant sky library parameter.")}
    var result:[String:Any]=[:]
    switch op {
    case "import","importBatch":
      let presets=try command.importedSkies(batch:op=="importBatch"),groupID=try command.skyGroupID()
      let expectedLibrary=store.skies.revision,expectedToken=token,expectedRevision=revision(store),generation=store.layerPanelGeneration
      try SkyLibrary.validate(store.skies.skies+presets.map{var p=$0;p.groupID=groupID;return p},groups:store.skies.groups)
      store.geometryBusy=true;defer{if store.layerPanelGeneration==generation{store.geometryBusy=false;store.geometryTask=nil}}
      let worker=Task.detached(priority:.userInitiated){try SkyImportPreparation.validate(presets);try Task.checkCancellation()}
      store.geometryTask=Task{await withTaskCancellationHandler{_=try? await worker.value}onCancel:{worker.cancel()}}
      try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();prune()
      guard store.geometryTask?.isCancelled != true,isRunning,token==expectedToken,revision(store)==expectedRevision,shares.contains(where:{$0.id==shareID}) else{throw AutomationFailure(status:409,message:"Sky import was cancelled or document sharing changed.")}
      try store.skies.append(presets,to:groupID,expectedRevision:expectedLibrary)
      result["skyIDs"]=presets.map{$0.id.uuidString};if presets.count==1{result["skyID"]=presets[0].id.uuidString}
    case "group.create":result["groupID"]=try store.skies.createGroup(command.string("name")).uuidString
    case "group.rename":try store.skies.renameGroup(command.actionUUID("groupID"),command.string("name"))
    case "group.delete":try store.skies.deleteGroup(command.actionUUID("groupID"),removeSkies:command.adjustmentBrushFlag("removeSkies",false))
    case "move":
      guard case .array(let values)=command.parameters["skyIDs"],!values.isEmpty,values.count<=64 else{throw AutomationFailure(status:400,message:"Supply1–64 sky IDs.")}
      let ids=try values.map{value->UUID in guard case .string(let s)=value,let id=UUID(uuidString:s) else{throw AutomationFailure(status:400,message:"Invalid sky UUID.")};return id}
      guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Sky IDs must be unique.")}
      try store.skies.move(ids,to:command.skyGroupID())
    case "delete":try store.skies.remove(command.actionUUID("skyID"))
    case "rename":try store.skies.rename(command.actionUUID("skyID"),command.string("name"))
    case "export":let preset=try store.skies.preset(command.actionUUID("skyID"));result["skyID"]=preset.id.uuidString;result["data"]=preset.data.base64EncodedString()
    default:break
    }
    result["state"]=store.skyState;result["revision"]=revision(store);return result
  }
}
