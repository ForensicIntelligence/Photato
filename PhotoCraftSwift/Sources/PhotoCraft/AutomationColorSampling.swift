import Foundation
import PhotoCraftCore

enum ColorSamplingAPI {
  static let name="color.sample"
  static var definition:AutomationCommand.Definition {
    .init(name:name,parameters:["operation":"configure or sample","size":"1,3,5,11,31,51,101","source":"Layer sampling source","showRing":"Native sampling ring","x":"Document x","y":"Document y","layerID":"Optional explicit source layer","target":"none, foreground or background"],description:"Configure shared Eyedropper settings, or sample through the native averaging/layer engine. Sampling overrides do not change defaults; target none is read-only. No document/history change.",optionalParameters:["size","source","showRing","x","y","layerID","target"])
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "operation":return BrushAPI.enumeration(["configure","sample"])
    case "size":return ["type":"integer","enum":ColorSampleSettings.sizes]
    case "source":return BrushAPI.enumeration(ColorSampleSource.allCases.map(\.rawValue))
    case "showRing":return BrushAPI.flag
    case "x","y":return ["type":"number","minimum":0,"exclusiveMaximum":300000]
    case "layerID":return ["type":"string","format":"uuid"]
    case "target":return BrushAPI.enumeration(ColorSampleTarget.allCases.map(\.rawValue))
    default:return [:]
    }
  }
  static var settingsSchema:[String:Any]{BrushAPI.object(["size":schema("size"),"source":schema("source"),"showRing":schema("showRing")],required:["size","source","showRing"])}
  static var parameterSchema:[String:Any]{
    var p:[String:Any]=[:];for key in definition.parameters.keys{p[key]=schema(key)}
    var result=BrushAPI.object(p,required:["operation"])
    var config=BrushAPI.object(["operation":["const":"configure"],"size":schema("size"),"source":schema("source"),"showRing":schema("showRing")],required:["operation"]);config["minProperties"]=2
    result["oneOf"]=[config,BrushAPI.object(p.merging(["operation":["const":"sample"]]){_,new in new}.filter{$0.key != "showRing"},required:["operation","x","y"])]
    return result
  }
  static var sampleResultSchema:[String:Any]{BrushAPI.object(["revision":["type":"string"],"color":BrushAPI.object(["r":BrushAPI.number(-Double(Float.greatestFiniteMagnitude),Double(Float.greatestFiniteMagnitude)),"g":BrushAPI.number(-Double(Float.greatestFiniteMagnitude),Double(Float.greatestFiniteMagnitude)),"b":BrushAPI.number(-Double(Float.greatestFiniteMagnitude),Double(Float.greatestFiniteMagnitude)),"a":["const":1]],required:["r","g","b","a"]),"coverage":["type":"number","minimum":0,"maximum":1],"region":BrushAPI.object(["x":BrushAPI.number(0,299999,integer:true),"y":BrushAPI.number(0,299999,integer:true),"width":BrushAPI.number(1,101,integer:true),"height":BrushAPI.number(1,101,integer:true)],required:["x","y","width","height"]),"visitedPixels":["type":"integer","minimum":1,"maximum":10201],"contributingPixels":["type":"integer","minimum":1,"maximum":10201],"eyedropper":stateSchema],required:["revision","color","coverage","region","visitedPixels","contributingPixels","eyedropper"])}
  static var stateSchema:[String:Any] {
    let fields:[String:Any]=["settings":settingsSchema,"available":BrushAPI.flag,"displayedChannel":BrushAPI.flag,"gestureActive":BrushAPI.flag,"persistentSamplersSupported":["const":false]]
    return BrushAPI.object(fields,required:fields.keys.sorted())
  }
  static var resultSchema:[String:Any] {
    ["oneOf":[BrushAPI.object(["revision":["type":"string"],"eyedropper":stateSchema],required:["revision","eyedropper"]),sampleResultSchema]]
  }
  static var capabilities:[String:Any]{["command":name,"parameterSchema":parameterSchema,"resultSchema":resultSchema,"settingsSchema":settingsSchema,"stateSchema":stateSchema,"state":"eyedropper","sizes":ColorSampleSettings.sizes,"sources":ColorSampleSource.allCases.map(\.rawValue),"native":"Sample Size, five layer sources, Show Sampling Ring; drag updates foreground, Option captures background. Ring upper half is new color and lower half is the captured color. Shift Color Sampler remains unavailable.","history":"Pure sampling and tool settings create no document history or dirty state. foreground/background target changes the active shared paint context; sampling overrides leave settings unchanged.","authorization":"configure requires native preferenceChangesEnabled; sampling requires an idle shared document and current revision. Cancellation, revocation and stale document/session/palette/settings/view state reject publication.","persistence":"Shared controller preferences; factory candidate Point Sample/All Layers/ring on. Production persists settings; isolated validation uses memory only. Exact Photoshop factory defaults remain unqualified.","numericPolicy":"Integer encoded/Float32 linear RGB averaging, alpha-weighted, visible pixels only, clipped at image bounds. Opaque paint color with separate average coverage. Current layer uses native raw layer coordinates; other sources use bounded regional composition. Exact Photoshop alpha/profile/rounding/source semantics and output remain unqualified.","limits":"At most101x101 sampling region; renderer content-specific limits still apply. Persistent Color Sampler points, external-desktop drag, physical stylus/hover/60fps and complete B07 remain open.","Adobe":"No dedicated operation in the pinned Photoshop v2 HTTP contract. No new route, UXP runtime or actionJSON support is claimed."]}
  @MainActor static func state(_ store:EditorStore)->[String:Any]{["settings":BrushAPI.json(store.eyedropperSettings),"available":store.canUseEyedropper,"displayedChannel":store.eyedropperUsesDisplayedTarget,"gestureActive":store.eyedropperGesture != nil,"persistentSamplersSupported":false]}
  static func settings(_ command:AutomationCommand,base:ColorSampleSettings)throws->ColorSampleSettings{
    var value=base
    if command.parameters["size"] != nil {value.size=try command.integer("size",range:1...101)}
    if command.parameters["source"] != nil {guard let source=ColorSampleSource(rawValue:try command.string("source"))else{throw AutomationFailure(status:400,message:"Choose a supported sampling source.")};value.source=source}
    if let ring=command.parameters["showRing"]{guard case .bool(let flag)=ring else{throw AutomationFailure(status:400,message:"showRing must be boolean.")};value.showRing=flag}
    do{try value.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)};return value
  }
}
@MainActor extension AutomationService {
  func executeColorSample(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws->AutomationResponse {
    let store=document.store,operation=try command.string("operation")
    let settings=try ColorSamplingAPI.settings(command,base:store.eyedropperSettings)
    if operation == "configure" {
      guard Set(command.parameters.keys).isSubset(of:["operation","size","source","showRing"]),command.parameters.count>1 else{throw AutomationFailure(status:400,message:"Configure takes a nonempty size/source/showRing patch.")}
      guard preferenceChangesEnabled else{throw AutomationFailure(status:403,message:"Enable preference changes in the native API window before configuring Eyedropper defaults.")}
      try Task.checkCancellation();try store.eyedropperPreferences.set(settings)
      return .json(["revision":revision(store),"eyedropper":ColorSamplingAPI.state(store)])
    }
    guard operation == "sample",command.parameters["showRing"]==nil else{throw AutomationFailure(status:400,message:"Choose sample with x/y; showRing is a configure setting.")}
    let x=try command.number("x",range:0...300000),y=try command.number("y",range:0...300000)
    let target:ColorSampleTarget
    if command.parameters["target"] != nil {guard let v=ColorSampleTarget(rawValue:try command.string("target"))else{throw AutomationFailure(status:400,message:"Choose none, foreground or background.")};target=v}else{target = .none}
    let layerID:UUID?=try command.parameters["layerID"].map{_ in try command.actionUUID("layerID")}
    if let layerID {guard store.document.layers.contains(where:{$0.id==layerID}),settings.source != .all,settings.source != .allNoAdjustments else{throw AutomationFailure(status:400,message:"An explicit layer must exist and use Current Layer or Current & Below.")}}
    if store.eyedropperUsesDisplayedTarget,command.parameters["source"] != nil || layerID != nil{throw AutomationFailure(status:422,message:"Channel-target sampling uses the displayed channel; explicit layer sources are unavailable.")}
    guard !previewBusy else{throw AutomationFailure(status:429,message:"A preview or color sample is already running.")}
    let input=try store.colorSamplingInput(),epoch=generation,expectedToken=token,session=store.sessionGeneration,palette=store.paintPalette.revision,preferences=store.eyedropperPreferences.revision,display=store.channelCompositeRevision
    previewBusy=true;defer{previewBusy=false}
    let prepare=prepareColorSample
    let worker=Task.detached(priority:.userInitiated){try prepare(input,x,y,settings,layerID ?? input.document.activeLayerID)}
    let result:ColorSampleResult
    do{result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}}catch is CancellationError{throw CancellationError()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    prune();try Task.checkCancellation()
    guard isRunning,generation==epoch,token==expectedToken,shares.contains(where:{$0.id==shareID}),command.revision==revision(store),store.sessionGeneration==session,store.document==input.document,store.paintPalette.revision==palette,store.eyedropperPreferences.revision==preferences,input.displayed==nil || store.channelCompositeRevision==display else{throw AutomationFailure(status:409,message:"Sampling context changed or sharing ended. Refresh and retry.")}
    try preflight(document);store.setSampledColor(result.color,target:target)
    return .json(["revision":revision(store),"color":["r":result.color.r,"g":result.color.g,"b":result.color.b,"a":result.color.a],"coverage":result.coverage,"region":["x":result.region.x,"y":result.region.y,"width":result.region.width,"height":result.region.height],"visitedPixels":result.visitedPixels,"contributingPixels":result.contributingPixels,"eyedropper":ColorSamplingAPI.state(store)])
  }
}
