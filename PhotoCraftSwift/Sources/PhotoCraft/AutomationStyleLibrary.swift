import Foundation
import PhotoCraftCore

enum StyleLibraryAPI {
  static let command="style.library"
  static let fields:[String:Set<String>]=[
    "list":[],"create":["name","layerID","style","includesEffects","includesBlending","parentID"],"group.create":["name","parentID"],
    "rename":["nodeID","name"],"delete":["nodeIDs"],"move":["nodeIDs","parentID","beforeID"],"duplicate":["nodeIDs","parentID","beforeID"],"apply":["nodeID","layerIDs"],"inspect":["nodeID"]]
  static let required:[String:Set<String>]=["list":[],"create":["name"],"group.create":["name"],"rename":["nodeID","name"],"delete":["nodeIDs"],"move":["nodeIDs"],"duplicate":["nodeIDs"],"apply":["nodeID","layerIDs"],"inspect":["nodeID"]]
  static var definition:AutomationCommand.Definition {
    let keys=fields.values.reduce(into:Set<String>()){$0.formUnion($1)}.union(["operation","libraryRevision"])
    return .init(name:command,parameters:Dictionary(uniqueKeysWithValues:keys.map{($0,"See operation-specific style library schema")}),description:"Save, organize and apply native layer style presets with embedded pattern resources and shared Undo.",optionalParameters:keys.subtracting(["operation"]))
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "operation":return BrushAPI.enumeration(fields.keys.sorted())
    case "libraryRevision","nodeID","layerID":return VariablesAPI.uuid
    case "parentID","beforeID":return ["anyOf":[VariablesAPI.uuid,["type":"null"]]]
    case "nodeIDs","layerIDs":return ["type":"array","minItems":1,"maxItems":key=="layerIDs" ? LayerLimits.maximumLayers:StyleLibraryState.maximumNodes,"uniqueItems":true,"items":VariablesAPI.uuid]
    case "name":return ["type":"string","minLength":1,"maxLength":65535]
    case "style":var schema=LayerStyle.apiSchema;schema["type"]="object";return schema
    case "includesEffects","includesBlending":return BrushAPI.flag
    default:return [:]
    }
  }
  static var parameterSchema:[String:Any] {
    var value=BrushAPI.object(Dictionary(uniqueKeysWithValues:definition.parameters.keys.map{($0,schema($0))}),required:["operation"])
    value["oneOf"]=fields.keys.sorted().map{operation->[String:Any] in
      let keys=fields[operation]!.union(["operation"]).union(operation=="list" ? []:["libraryRevision"])
      var properties=Dictionary(uniqueKeysWithValues:keys.map{($0,schema($0))});properties["operation"]=["const":operation]
      return BrushAPI.object(properties,required:required[operation]!.union(["operation"]).union(operation=="list" ? []:["libraryRevision"]).sorted())
    };return value
  }
  static var blendingSchema:[String:Any] { ["anyOf":[BrushAPI.object(["mode":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue)),"opacity":BrushAPI.number(0,1),"passThrough":["type":["boolean","null"]],"blendClippedAsGroup":["type":["boolean","null"]]],required:["mode","opacity","passThrough","blendClippedAsGroup"]),["type":"null"]]] }
  static var presetSchema:[String:Any] { BrushAPI.object(["includesEffects":BrushAPI.flag,"includesBlending":BrushAPI.flag,"blending":blendingSchema,"style":LayerStyle.apiSchema,"patterns":ShapeAPI.array(PixelPaintAPI.patternSchema,PatternArchive.maxCount)],required:["includesEffects","includesBlending","blending","style","patterns"]) }
  static var stateSchema:[String:Any] {
    let summary=BrushAPI.object(["includesEffects":BrushAPI.flag,"includesBlending":BrushAPI.flag,"blending":blendingSchema,"effectKinds":ShapeAPI.array(BrushAPI.enumeration(LayerEffect.Kind.allCases.map(\.rawValue)),32),"patternCount":BrushAPI.number(0,Double(PatternArchive.maxCount),integer:true)],required:["includesEffects","includesBlending","blending","effectKinds","patternCount"])
    let node=BrushAPI.object(["id":VariablesAPI.uuid,"parentID":["anyOf":[VariablesAPI.uuid,["type":"null"]]],"name":["type":"string"],"kind":BrushAPI.enumeration(["group","style"]),"preset":["anyOf":[summary,["type":"null"]]]],required:["id","parentID","name","kind","preset"])
    return BrushAPI.object(["libraryRevision":VariablesAPI.uuid,"version":["const":1],"nodes":ShapeAPI.array(node,StyleLibraryState.maximumNodes),"selected":ShapeAPI.array(VariablesAPI.uuid,StyleLibraryState.maximumNodes),"busy":BrushAPI.flag,"available":BrushAPI.flag,"error":["type":["string","null"]]],required:["libraryRevision","version","nodes","selected","busy","available","error"])
  }
  static func blendingObject(_ value:StylePresetBlending?)->Any {
    value.map{["mode":$0.mode.rawValue,"opacity":$0.opacity,"passThrough":$0.passThrough as Any? ?? NSNull(),"blendClippedAsGroup":$0.blendClippedAsGroup as Any? ?? NSNull()]as[String:Any]} as Any? ?? NSNull()
  }
  static func presetObject(_ value:StylePreset)->[String:Any] {
    ["includesEffects":value.includesEffects,"includesBlending":value.blending != nil,"blending":blendingObject(value.blending),"style":value.style.apiObject,"patterns":value.patterns.map{["id":$0.id,"name":$0.displayName,"width":$0.surface.width,"height":$0.surface.height,"depth":$0.surface.depth.rawValue,"source":"library"]as[String:Any]}]
  }
  @MainActor static func state(_ library:StyleLibrary)->[String:Any] {
    ["libraryRevision":library.revision.uuidString,"version":1,"nodes":library.state.nodes.map{node->[String:Any] in
      let summary:Any=node.preset.map{p->Any in ["includesEffects":p.includesEffects,"includesBlending":p.blending != nil,"blending":blendingObject(p.blending),"effectKinds":p.style.effects.map{$0.kind.rawValue},"patternCount":p.patterns.count]} ?? NSNull()
      return ["id":node.id.uuidString,"parentID":node.parentID?.uuidString as Any? ?? NSNull(),"name":node.name,"kind":node.isGroup ? "group":"style","preset":summary]
    },"selected":library.selected.map(\.uuidString).sorted(),"busy":library.busy,"available":!library.busy && !library.loadFailed,"error":library.error as Any? ?? NSNull()]
  }
  static var capabilities:[String:Any] {
    ["command":command,"parameters":parameterSchema,"stateSchema":stateSchema,"resultSchema":BrushAPI.object(["revision":["type":"string"],"styleLibrary":stateSchema,"createdNodeID":VariablesAPI.uuid,"preset":presetSchema],required:["revision","styleLibrary"]),
     "native":"Window > Styles reveals a real dock/floating panel. New Style saves committed or private Layer Style settings, with Include Layer Effects/Include Layer Blending Options. Native/API group, rename, duplicate, move, delete and application share the same models. Text-only presentation; imported Adobe default artwork and ASL transport remain open.",
     "history":"Library edits do not edit image content/history. Applying captures a preset by value, remaps conflicting embedded pattern IDs, preserves target blending when omitted, and commits one shared style transaction. Undo/Redo and portable Actions57 retain resources/blending; preset library contents need not exist during replay. Native document archive89 remains current.",
     "fences":"inspect returns full effect/blending descriptors on request (2MiB API response budget); routine state carries metadata without raw style/PSD descriptors. Every mutation and apply requires libraryRevision plus the normal document revision. Preparation checks source/session/sharing/token/library revision before persistence. Atomic file replacement is the library commit point; accepted immutable apply inputs need no later library lookup. Stale/invalid/locked/busy/cancelled/revoked operations cannot publish prepared edits.",
     "capacity":"Working bounds:4096nodes/64group depth/512MiB native library/64MP aggregate pattern resources. Existing effect8MP and API document limits remain. These are not Photoshop maximum claims.",
     "adobe":"No defined preset-library operation in the pinned Firefly v2 contract. No route, descriptor execution or plug-in runtime invented. ASL/complete defaults/previews/drag/precise Photoshop behavior and full L04 remain unfinished."]
  }
}
extension AutomationCommand {
  func styleIDs(_ key:String,maximum:Int=StyleLibraryState.maximumNodes)throws->Set<UUID> {
    guard case .array(let values)=parameters[key],!values.isEmpty,values.count<=maximum else {throw AutomationFailure(status:400,message:"Choose a bounded nonempty UUID array.")}
    let ids=try values.map{value->UUID in guard case .string(let text)=value,let id=UUID(uuidString:text) else {throw AutomationFailure(status:400,message:"Invalid style UUID.")};return id}
    guard Set(ids).count==ids.count else {throw AutomationFailure(status:400,message:"Style IDs must be unique.")};return Set(ids)
  }
}
extension AutomationService {
  func manageStyles(_ command:AutomationCommand,store:EditorStore,document:CraftNSDocument,shareID:UUID)async throws->[String:Any] {
    let operation=try command.string("operation"),library=store.styles
    guard let allowed=StyleLibraryAPI.fields[operation],let required=StyleLibraryAPI.required[operation],Set(command.parameters.keys).subtracting(["operation","libraryRevision"]).isSubset(of:allowed),required.isSubset(of:Set(command.parameters.keys)) else {throw AutomationFailure(status:400,message:"Unknown, irrelevant or missing style-library fields.")}
    if operation != "list" {
      guard try command.actionUUID("libraryRevision")==library.revision else {throw AutomationFailure(status:409,message:"Stale style library. Refresh and retry.")}
      guard !library.busy,!library.loadFailed else {throw AutomationFailure(status:409,message:"Resolve the busy or unreadable style library first.")}
    } else if command.parameters["libraryRevision"] != nil {throw AutomationFailure(status:400,message:"List does not take a library revision.")}
    let capturedToken=self.token,session=store.sessionGeneration,owner=store.document.id,revision=library.revision,generation=store.layerPanelGeneration
    // The in-flight request owns its service/document/store until completion.
    // Explicit sharing/lifecycle checks still reject a closed document; weak
    // captures may otherwise disappear early under normal ARC optimization.
    let mismatch:@MainActor ()->String? = {[self,store,document] in
      self.prune()
      guard self.isRunning,self.token==capturedToken else{return "The API service or authorization changed."}
      guard self.shares.contains(where:{$0.id==shareID && $0.document===document && document.store===store}) else{return "Document sharing ended."}
      guard store.sessionGeneration==session,store.document.id==owner else{return "The source document changed."}
      guard store.layerPanelGeneration==generation else{return "The document lifecycle changed."}
      guard library.revision==revision else{return "The saved style library changed."}
      return nil
    }
    let authorize:@MainActor ()->Bool = {mismatch()==nil}
    var extra=[String:Any]()
    if operation=="inspect" {
      guard let preset=library.state.node(try command.actionUUID("nodeID"))?.preset else {throw AutomationFailure(status:404,message:"Style preset not found.")}
      let object=StyleLibraryAPI.presetObject(preset)
      guard try JSONSerialization.data(withJSONObject:object).count<=2*1024*1024 else {throw AutomationFailure(status:422,message:"Style details exceed the API response budget.")}
      extra["preset"]=object
    } else if operation=="apply" {
      let id=try command.actionUUID("nodeID"),ids=try command.styleIDs("layerIDs",maximum:LayerLimits.maximumLayers)
      guard let preset=library.state.node(id)?.preset else {throw AutomationFailure(status:404,message:"Style preset not found.")}
      try await executePreparedOperation(document:document,shareID:shareID,revision:command.revision){source in .layerStyles(try preset.edit(layerIDs:ids,in:source))}
    } else if operation != "list" {
      let mutation:StyleLibraryMutation
      switch operation {
      case "create":
        let layer=try command.parameters["layerID"].map{_ in try command.actionUUID("layerID")} ?? store.document.activeLayerID
        guard let layer else {throw AutomationFailure(status:422,message:"Choose a source layer.")}
        let style=try command.parameters["style"].map{try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject:$0.jsonValue))}
        let preset=try StylePreset.capture(layerID:layer,in:store.document,includesEffects:command.pathFlag("includesEffects",true),includesBlending:command.pathFlag("includesBlending",false),styleOverride:style)
        mutation = .save(try command.string("name"),preset,parent:try command.optionalPatternUUID("parentID"))
      case "group.create":mutation = .group(try command.string("name"),parent:try command.optionalPatternUUID("parentID"))
      case "rename":mutation = .rename(try command.actionUUID("nodeID"),try command.string("name"))
      case "delete":mutation = .delete(try command.styleIDs("nodeIDs"))
      case "move":mutation = .move(try command.styleIDs("nodeIDs"),parent:try command.optionalPatternUUID("parentID"),before:try command.optionalPatternUUID("beforeID"))
      case "duplicate":mutation = .duplicate(try command.styleIDs("nodeIDs"),parent:try command.optionalPatternUUID("parentID"),before:try command.optionalPatternUUID("beforeID"))
      default:throw AutomationFailure(status:400,message:"Unknown style library operation.")
      }
      do {if let id=try await library.edit(mutation,authorize:authorize){extra["createdNodeID"]=id.uuidString}}
      catch {if let reason=mismatch(){throw AutomationFailure(status:409,message:"Style library source or authorization changed. " + reason)};throw error}
    }
    extra["revision"]=self.revision(store);extra["styleLibrary"]=StyleLibraryAPI.state(library);return extra
  }
}
