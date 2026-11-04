import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum TextFindAPI {
  static let commands=["text.find","text.replace"]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "find":return ["type":"string","minLength":1,"maxLength":100_000]
    case "replacement":return ["type":"string","maxLength":100_000]
    case "caseSensitive","wholeWord","replaceAll":return BrushAPI.flag
    case "layerID":return ["type":"string","format":"uuid"]
    case "offset":return BrushAPI.number(0,2_000_000_000,integer:true)
    case "limit":return BrushAPI.number(1,10_000,integer:true)
    default:return BrushAPI.number(0,100_000,integer:true)
    }
  }
  static var matchSchema:[String:Any] {BrushAPI.object(["layerID":["type":"string","format":"uuid"],"layerName":["type":"string"],"location":schema("start"),"length":schema("start")],required:["layerID","layerName","location","length"])}
  static var resultSchema:[String:Any] {BrushAPI.object(["matches":["type":"array","maxItems":10_000,"items":matchSchema],"total":schema("offset"),"offset":schema("offset"),"hasMore":BrushAPI.flag],required:["matches","total","offset","hasMore"])}
  static var replacementResultSchema:[String:Any] {BrushAPI.object(["occurrences":schema("offset"),"layers":BrushAPI.number(0,Double(LayerLimits.maximumLayers),integer:true)],required:["occurrences","layers"])}
  static var pendingSchema:[String:Any] {BrushAPI.object(["find":["type":"string","maxLength":100_000],"replacement":schema("replacement"),"caseSensitive":BrushAPI.flag,"wholeWord":BrushAPI.flag,"forward":BrushAPI.flag,"allLayers":BrushAPI.flag],required:["find","replacement","caseSensitive","wholeWord","forward","allLayers"])}
  static var stateSchema:[String:Any] {BrushAPI.object(["available":BrushAPI.flag,"workspaceOpen":BrushAPI.flag,"busy":BrushAPI.flag,"replacing":BrushAPI.flag,"sourceChanged":BrushAPI.flag,"pendingOptions":["anyOf":[pendingSchema,["type":"null"]]],"currentMatch":["anyOf":[matchSchema,["type":"null"]]]],required:["available","workspaceOpen","busy","replacing","sourceChanged","pendingOptions","currentMatch"])}
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let workspace=store.textFindWorkspace
    let current:Any=workspace?.current.map{value -> Any in BrushAPI.json(value)} ?? NSNull()
    let pending:Any=workspace.map{value -> Any in ["find":value.find,"replacement":value.replacement,"caseSensitive":value.caseSensitive,"wholeWord":value.wholeWord,"forward":value.forward,"allLayers":value.allLayers]} ?? NSNull()
    return ["available":store.canBeginTextFind,"workspaceOpen":workspace != nil,"busy":workspace?.busy ?? false,"replacing":workspace?.replacing ?? false,"sourceChanged":workspace.map{$0.source != store.document} ?? false,"pendingOptions":pending,"currentMatch":current]
  }
  static var capabilities:[String:Any] {["commands":commands,"resultSchema":resultSchema,"replacementResultSchema":replacementResultSchema,"ActionsVersion":46,"offsetUnit":"UTF-16 code units","defaults":["caseSensitive":false,"wholeWord":false,"start":0,"offset":0,"limit":100,"replaceAll":true],"scope":"Omitted layerID searches all visible, image-unlocked type layers, top to bottom, including groups. Ancestor eyes and protection apply; opacity alone does not hide a type layer. Explicit layerID selects one layer. start requires an explicit layer. Query pages do not truncate Change All.","behavior":"Literal search; Unicode ICU word boundaries and case matching. Replacements retain unaffected type runs, inherit the first replaced character style, discard changed glyph overrides and preserve native type anchor/masks through shared shaping. Single or all replacements are one Undo; no matches/same text preserve the document/history but may record reusable Actions.","qualification":"Public Adobe workflow controls and native implementation. Exact Photoshop Unicode/case/word boundaries, ordering, factory/remembered settings, on-canvas match selection, typography/output, live UI and physical supported Macs remain unqualified. Existing type/layout/document/API budgets remain. No dedicated published Adobe Find/Replace endpoint or unqualified actionJSON descriptor is invented."]}
}
extension AutomationCommand {
  func textFindString(_ key:String)throws->String {guard case .string(let value)=parameters[key] else{throw AutomationFailure(status:400,message:"Invalid \(key).")};return value}
  func textSearchOptions(in document:CraftDocument)throws->(TextSearchSettings,UUID?,Int) {
    for (key,value)in parameters{_ = try BrushAPI.merge(value,schema:TextFindAPI.schema(key),path:key)}
    let settings=TextSearchSettings(find:try textFindString("find"),caseSensitive:try pathFlag("caseSensitive",false),wholeWord:try pathFlag("wholeWord",false))
    try settings.validate();let id=try parameters["layerID"].map{_ in try actionUUID("layerID")}
    if let id,!document.layers.contains(where:{$0.id==id}){throw AutomationFailure(status:404,message:"Text search layer not found.")}
    let start=try parameters["start"].map{_ in try integer("start",range:0...100_000)} ?? 0
    guard start==0 || id != nil else{throw AutomationFailure(status:400,message:"start requires an explicit layerID.")}
    return(settings,id,start)
  }
}
extension AutomationService {
  func executeTextFind(_ command:AutomationCommand,document:CraftNSDocument,share:Share)async throws->AutomationResponse {
    let store=document.store,original=store.document
    let (settings,layerID,start)=try command.textSearchOptions(in:original)
    if command.name=="text.replace" {
      guard store.isCompositeColorTarget,!store.editingMask,!store.smartFilterMaskEditing else{throw AutomationFailure(status:422,message:"Select the composite image target for type replacement.")}
      let request=RecordedTextReplacement(settings:settings,replacement:try command.textFindString("replacement"),target:layerID.map{.init($0,in:original,preferActive:false)},start:start,replaceAll:try command.pathFlag("replaceAll",true))
      let counts=try await executePreparedResult(document:document,shareID:share.id,revision:command.revision){source in
        let result=try TextReplacementPreparation.prepare(source,request:request)
        return(result.command,["occurrences":result.occurrences,"layers":result.layers])
      }
      var response=state(share,document:document);response["textReplacement"]=counts;return .json(response)
    }
    let offset=try command.parameters["offset"].map{_ in try command.integer("offset",range:0...2_000_000_000)} ?? 0
    let limit=try command.parameters["limit"].map{_ in try command.integer("limit",range:1...10_000)} ?? 100
    let expectedToken=token,generation=store.layerPanelGeneration,prepare=store.textSearchPreparation
    let worker=Task.detached(priority:.userInitiated){try prepare(original,settings,layerID,start,offset,limit)}
    let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation();prune()
    guard isRunning,token==expectedToken,shares.contains(where:{$0.id==share.id}),store.layerPanelGeneration==generation,store.document==original,revision(store)==command.revision else{throw AutomationFailure(status:409,message:"The text search source or sharing changed.")}
    var response=state(share,document:document);response["textSearchResult"]=BrushAPI.json(result);return .json(response)
  }
}
