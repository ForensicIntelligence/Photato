import Foundation
import CryptoKit
import PhotoCraftCore
import PhotoCraftImaging

enum PatternLibraryAPI {
  static let command="pattern.library"
  static let maximumBase64=3_000_000
  static let fields:[String:Set<String>]=[
    "list":[],"select":["nodeIDs","activeID"],"group.create":["name","parentID"],
    "rename":["nodeID","name"],"move":["nodeIDs","parentID","beforeID"],
    "duplicate":["nodeIDs","parentID","beforeID"],"delete":["nodeIDs"],
    "collapse":["nodeID","collapsed"],"import":["data","parentID"],
    "export":["nodeIDs"],"define":["name"],"reset.builtins":[]]
  static let required:[String:Set<String>]=[
    "list":[],"select":["nodeIDs"],"group.create":["name"],"rename":["nodeID","name"],
    "move":["nodeIDs"],"duplicate":["nodeIDs"],"delete":["nodeIDs"],"collapse":["nodeID","collapsed"],
    "import":["data"],"export":[],"define":["name"],"reset.builtins":[]]
  static var definition:AutomationCommand.Definition {
    var parameters=["operation":"Pattern library operation","libraryRevision":"Current shared pattern-library UUID"]
    for key in fields.values.reduce(into:Set<String>(),{$0.formUnion($1)}){parameters[key]="See operation-specific schema"}
    return .init(name:command,parameters:parameters,description:"Manage the shared native pattern library, preserving groups, resources and PAT hierarchy. No document pixel/history mutation.",optionalParameters:Set(parameters.keys).subtracting(["operation"]))
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "operation":BrushAPI.enumeration(fields.keys.sorted())
    case "libraryRevision","nodeID":VariablesAPI.uuid
    case "parentID","beforeID","activeID":["anyOf":[VariablesAPI.uuid,["type":"null"]]]
    case "nodeIDs":["type":"array","maxItems":PatternLibraryState.maximumNodes,"uniqueItems":true,"items":VariablesAPI.uuid]
    case "name":["type":"string","minLength":1,"maxLength":65_535]
    case "collapsed":BrushAPI.flag
    case "data":["type":"string","contentEncoding":"base64","maxLength":maximumBase64]
    default:["type":"null"]
    }
  }
  static var parameterSchema:[String:Any] {
    var result=BrushAPI.object(Dictionary(uniqueKeysWithValues:definition.parameters.keys.map{($0,schema($0))}),required:["operation"])
    result["oneOf"]=fields.keys.sorted().map{operation->[String:Any]in
      let keys=fields[operation]!.union(operation=="list" ? []:["libraryRevision"]).union(["operation"])
      var properties=Dictionary(uniqueKeysWithValues:keys.map{($0,schema($0))});properties["operation"]=["const":operation]
      let needed=required[operation]!.union(operation=="list" ? []:["libraryRevision"]).union(["operation"])
      return BrushAPI.object(properties,required:needed.sorted())
    }
    return result
  }
  static var nodeSchema:[String:Any] {
    BrushAPI.object(["id":VariablesAPI.uuid,"parentID":schema("parentID"),"patternID":["type":["string","null"]],
      "kind":BrushAPI.enumeration(["group","pattern"]),"name":["type":"string"]],required:["id","parentID","patternID","kind","name"])
  }
  static var stateSchema:[String:Any] {
    BrushAPI.object(["libraryRevision":VariablesAPI.uuid,"version":["type":"integer","const":2],
      "nodes":["type":"array","maxItems":PatternLibraryState.maximumNodes,"items":nodeSchema],
      "patterns":["type":"array","maxItems":PatternArchive.maxCount,"items":PixelPaintAPI.patternSchema],
      "selectedNodes":schema("nodeIDs"),"activeNodeID":schema("activeID"),"selectedPatternID":["type":["string","null"]],
      "collapsed":schema("nodeIDs"),"busy":BrushAPI.flag,"available":BrushAPI.flag,"error":["type":["string","null"]]],
      required:["libraryRevision","version","nodes","patterns","selectedNodes","activeNodeID","selectedPatternID","collapsed","busy","available","error"])
  }
  static var resultSchema:[String:Any] {
    BrushAPI.object(["revision":["type":"string"],"patternLibrary":stateSchema,"createdNodeID":VariablesAPI.uuid,
      "patternID":["type":"string"],"data":schema("data"),"contentType":["type":"string"],"filename":["type":"string"],"sha256":["type":"string"]],required:["revision","patternLibrary"])
  }
  @MainActor static func state(_ library:PatternLibrary)->[String:Any] {
    let state=library.state
    return ["libraryRevision":library.revision.uuidString,"version":2,
      "nodes":state.nodes.map{node->[String:Any]in ["id":node.id.uuidString,"parentID":node.parentID?.uuidString as Any? ?? NSNull(),
        "patternID":node.patternID as Any? ?? NSNull(),"kind":node.isGroup ? "group":"pattern","name":state.name(node.id) ?? ""]},
      "patterns":library.items.map{["id":$0.id,"name":$0.displayName,"width":$0.surface.width,"height":$0.surface.height,"depth":$0.surface.depth.rawValue,"source":"library"]as[String:Any]},
      "selectedNodes":state.selectedNodes.map(\.uuidString).sorted(),"activeNodeID":state.activeNodeID?.uuidString as Any? ?? NSNull(),
      "selectedPatternID":state.selectedID as Any? ?? NSNull(),"collapsed":state.collapsed.map(\.uuidString).sorted(),
      "busy":library.busy,"available":!library.busy && library.error==nil,"error":library.error as Any? ?? NSNull()]
  }
  static var capabilities:[String:Any] {
    ["command":command,"parameters":parameterSchema,"stateSchema":stateSchema,"resultSchema":resultSchema,
     "scope":"Shared application user library. Every operation except list requires libraryRevision and the normal shared-document revision. Library changes invalidate brush-dependent revisions for all attached documents. At completion, document/session/library/lifecycle and sharing fences remain; display-only redraws do not cancel an already accepted operation.",
     "history":"No image pixels, document archive, dirty state, Undo or recorded Action changes. New/renamed/duplicated/deleted presets do not change patterns already captured in a document. Native-library format2 migrates1 without rewriting on read. Selection and disclosure changes are session state, saved with the next persisted mutation.",
     "native":"Groups, Shift range/Command toggle selection, group/preset drag-move, duplicate/rename/delete, selected/all PAT import/export and Define Pattern share native implementation. Drop proposal and dispatched move agree for all modifiers; Option does not introduce copying. Private own-process source tokens fence stale/superseded/closed/revoked work. No editing-tool cursor or factory shortcut is added.",
     "transport":"Observed 8BPT1 pixel records and 8BIM/phry folder order retained; repeated nodes may reference one validated asset. Export nodeIDs explicitly selects subtrees; omission exports all. Import parentID defaults root. No paths accepted. Base64 input/output <=3000000characters inside existing4MiB HTTP budget.",
     "persistence":"Worker preparation validates before atomic replacement. Failure/cancellation/revocation before commit preserves old memory/file. Once atomic replacement is accepted, matching memory publishes even if cancellation arrives afterward.",
     "limits":"Existing1024unique assets/1024preset occurrences/64MP total/16MP each/512MiB file/1GiB tile budget;4096nodes/64group depth. These are working bounds, not full Photoshop capacity claims. Complete apply/drop-to-document semantics, legacy Adobe artwork, History/scripted Fill, arbitrary PAT metadata, exact defaults/output and physical60fps remain open.",
     "adobe":"Photato extension; no corresponding qualified desktop preset-library route or actionJSON operation added to pinned Adobe v2 contract."]
  }
}
extension AutomationCommand {
  func patternNodeIDs(_ key:String="nodeIDs")throws->Set<UUID> {
    guard case .array(let values)=parameters[key],values.count<=PatternLibraryState.maximumNodes else{throw AutomationFailure(status:400,message:"Supply a bounded nodeID array.")}
    let ids=try values.map{value->UUID in guard case .string(let text)=value,let id=UUID(uuidString:text)else{throw AutomationFailure(status:400,message:"Invalid pattern node UUID.")};return id}
    guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Pattern nodeIDs must be unique.")}
    return Set(ids)
  }
  func optionalPatternUUID(_ key:String)throws->UUID? {
    guard let value=parameters[key]else{return nil};if case .null=value{return nil};return try actionUUID(key)
  }
}
/// A short-lived accepted request owns its inputs; ownership never extends permission.
@MainActor private final class PatternLibraryRequest {
  let service:AutomationService
  let store:EditorStore
  let shareID:UUID
  let source:PatternDialogSource
  let token:String?
  private(set) var failure=""
  init(_ service:AutomationService,_ store:EditorStore,_ shareID:UUID) {
    self.service=service;self.store=store;self.shareID=shareID
    source=PatternDialogSource(store);token=service.token
  }
  func valid()->Bool {
    service.prune()
    guard service.isRunning else{failure="API stopped";return false}
    guard service.token==token else{failure="API authorization changed";return false}
    guard service.shares.contains(where:{$0.id==shareID && $0.document?.store===store})else{failure="document sharing ended";return false}
    guard source.documentID==store.document.id else{failure="document replaced";return false}
    guard source.session==store.sessionGeneration else{failure="document edited";return false}
    guard source.generation==store.layerPanelGeneration else{failure="document lifecycle changed";return false}
    guard source.libraryID==store.patterns.identity else{failure="library replaced";return false}
    guard source.libraryRevision==store.patterns.revision else{failure="library edited";return false}
    failure="";return true
  }
}
extension AutomationService {
  func managePatterns(_ command:AutomationCommand,store:EditorStore,shareID:UUID)async throws->[String:Any] {
    let operation=try command.string("operation"),library=store.patterns
    guard let allowed=PatternLibraryAPI.fields[operation],let required=PatternLibraryAPI.required[operation],
      Set(command.parameters.keys).subtracting(["operation","libraryRevision"]).isSubset(of:allowed),
      required.isSubset(of:Set(command.parameters.keys))else{throw AutomationFailure(status:400,message:"Unknown, missing or irrelevant pattern-library fields.")}
    if operation != "list" {
      guard try command.actionUUID("libraryRevision")==library.revision else{throw AutomationFailure(status:409,message:"Stale pattern library. Refresh and retry.")}
      guard !library.busy else{throw AutomationFailure(status:409,message:"Pattern library is busy.")}
    }else if command.parameters["libraryRevision"] != nil {throw AutomationFailure(status:400,message:"List does not take a library revision.")}
    let lease=PatternLibraryRequest(self,store,shareID)
    let authorize: @MainActor ()->Bool = {lease.valid()}
    var extra=[String:Any]()
    do { switch operation {
    case "list":break
    case "select":
      let ids=try command.patternNodeIDs(),active=try command.optionalPatternUUID("activeID")
      try library.select(ids,active:active)
    case "collapse":try library.collapse(command.actionUUID("nodeID"),command.pathFlag("collapsed",false))
    case "import":
      guard case .string(let encoded)=command.parameters["data"],encoded.utf8.count<=PatternLibraryAPI.maximumBase64,let data=Data(base64Encoded:encoded)else{throw AutomationFailure(status:400,message:"Supply bounded base64 PAT data.")}
      let parent=try command.optionalPatternUUID("parentID")
      _=try await library.importData(data,into:parent,authorize:authorize)
    case "export":
      let captured=library.state,ids=try command.parameters["nodeIDs"].map{_ in try command.patternNodeIDs()}
      let worker=Task.detached(priority:.userInitiated){
        let data=try PATCodec.writeLibrary(captured,selected:ids)
        guard data.count <= PatternLibraryAPI.maximumBase64/4*3 else{throw CraftError.invalid("PAT export exceeds the API transfer budget. Use native Export Patterns.")}
        return data
      }
      let data=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
      try Task.checkCancellation();guard authorize()else{throw AutomationFailure(status:409,message:"Pattern export source or sharing changed.")}
      extra=["data":data.base64EncodedString(),"contentType":"application/octet-stream","filename":"Photato Patterns.pat","sha256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()]
    case "define":
      extra["patternID"]=try await library.define(in:store.document,name:command.string("name"),authorize:authorize)
      store.bucketUsesPattern=true;store.colorTab = .patterns
    case "reset.builtins":
      let assets=try PatternPresets.make()
      // Same merge/reset policy as the native restore command, with source authorization.
      try await library.install(assets,authorize:authorize)
    default:
      let mutation:PatternLibraryMutation
      switch operation {
      case "group.create":mutation = .createGroup(try command.string("name"),parent:try command.optionalPatternUUID("parentID"))
      case "rename":mutation = .rename(try command.actionUUID("nodeID"),try command.string("name"))
      case "move":mutation = .move(try command.patternNodeIDs(),parent:try command.optionalPatternUUID("parentID"),before:try command.optionalPatternUUID("beforeID"))
      case "duplicate":mutation = .duplicate(try command.patternNodeIDs(),parent:try command.optionalPatternUUID("parentID"),before:try command.optionalPatternUUID("beforeID"))
      case "delete":mutation = .delete(try command.patternNodeIDs())
      default:throw AutomationFailure(status:400,message:"Unknown pattern-library operation.")
      }
      if let id=try await library.mutate(mutation,authorize:authorize){extra["createdNodeID"]=id.uuidString}
    }}catch{if !authorize(){throw AutomationFailure(status:409,message:"Pattern operation cancelled before commit: \(lease.failure).")};throw error}
    extra["patternLibrary"]=PatternLibraryAPI.state(library);extra["revision"]=revision(store);return extra
  }
}
