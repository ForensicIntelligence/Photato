import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PaintingAPI {
  static let commands=["paint.configure","paint.tool","paint.mixer"]
  static func options(_ tool:PaintTool)->[String:Any] {
    let unit=BrushAPI.number(),flag=BrushAPI.flag
    let fields:[String:Any]
    switch tool {
    case .brush:fields=[:]
    case .pencil:fields=["autoErase":flag]
    case .colorReplacement:fields=["sampling":BrushAPI.enumeration(PaintSampling.allCases.map(\.rawValue)),"limits":BrushAPI.enumeration(PaintLimits.allCases.map(\.rawValue)),"tolerance":unit,"replacementMode":BrushAPI.enumeration([BlendMode.hue,.saturation,.color,.luminosity].map(\.rawValue)),"antiAlias":flag]
    case .backgroundEraser:fields=["sampling":BrushAPI.enumeration(PaintSampling.allCases.map(\.rawValue)),"limits":BrushAPI.enumeration(PaintLimits.allCases.map(\.rawValue)),"tolerance":unit,"protectForeground":flag]
    case .magicEraser:fields=["tolerance":unit,"contiguous":flag,"antiAlias":flag,"sampleAllLayers":flag]
    case .mixerBrush:fields=["wet":unit,"load":unit,"mix":unit,"flow":unit,"sampleAllLayers":flag,"loadAfterStroke":flag,"cleanAfterStroke":flag,"loadSolidColorOnly":flag]
    case .patternStamp:fields=["aligned":flag,"impressionist":flag,"placement":BrushAPI.object(["scale":BrushAPI.number(1,1000),"angle":BrushAPI.number(-360000,360000),"phaseX":BrushAPI.number(-1_000_000,1_000_000),"phaseY":BrushAPI.number(-1_000_000,1_000_000)])]
    }
    return BrushAPI.object(fields)
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "tool":return BrushAPI.enumeration(PaintTool.allCases.map(\.rawValue))
    case "options":return ["anyOf":PaintTool.allCases.map{options($0)}]
    case "operation":return BrushAPI.enumeration(["load","clean","sample"])
    case "x","y":return BrushAPI.number(-1_000_000,1_000_000)
    case "size":return BrushAPI.number(0.5,2048)
    case "color":return BrushAPI.color
    case "allLayers","solid":return BrushAPI.flag
    case "patternID":return ["type":"string","minLength":1,"maxLength":255]
    default:return BrushAPI.schema(key)
    }
  }
  static func decodeOptions(_ value:AutomationValue?,tool:PaintTool,base:PaintToolOptions)throws->PaintToolOptions {
    guard let value else{return base}
    do {let raw=try BrushAPI.merge(value,schema:options(tool),base:BrushAPI.json(base),path:"options");let decoded=try JSONDecoder().decode(PaintToolOptions.self,from:JSONSerialization.data(withJSONObject:raw));try decoded.validate();return decoded}
    catch let e as AutomationFailure {throw e} catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static var capabilities:[String:Any] {
    ["commands":commands,"tools":PaintTool.allCases.map(\.rawValue),"options":Dictionary(uniqueKeysWithValues:PaintTool.allCases.map{($0.rawValue,options($0))}),
     "targets":["pixels","layerMask","smartFilterMask","alpha","quickMask"],
    "hiddenQuickMask":"Painting a hidden Quick Mask is rejected422, matching native gesture entry. The real PaintingEdit request target is validated before preparing and again before commit; show the mask to paint. Other channel-filter operations keep their separate policy.",
     "targetLimits":"Color Replacement, Background Eraser and Magic Eraser require ordinary pixel layers. Other tools also support grayscale masks/channels. Brush/Pencil automatically create a layer above nonraster content where the document mode permits layers. Background conversion follows the current native representation.",
     "modeStorage":"Previews and commits reconcile RGB, Grayscale, CMYK and Lab components, Indexed palette indices or Bitmap bits before returning a prepared edit. Untouched native samples and duplicate palette indices are retained. Indexed and Bitmap remain flat; full Photoshop mode-dependent tool availability and numerical equivalence remain unqualified.",
     "mixer":"Load/Clean/Sample change session paint only; stroke commit updates remaining paint atomically. Option-click sampling and API sample share solid/varied source preparation.",
     "pattern":"Existing native/document patterns by ID; aligned phase persists, explicit phaseX/phaseY override it. Impressionist deposits a sampled pattern color per dab.",
     "limits":"4096 API samples, 200000 generated spacing steps, 134217728 raster visits; one footprint and Magic Eraser sample at most16MP. Mixer loads at most256x256. 4MiB API request limit.",
     "fidelity":"Independent native algorithms. Exact Adobe output/physical tablet and complete brush-resource actionJSON compatibility remain open; no invented Adobe route."]
  }
}
extension AutomationCommand {
  func paintTool()throws->PaintTool {
    guard let tool=PaintTool(rawValue:try string("tool")) else{throw AutomationFailure(status:400,message:"Unknown painting tool.")};return tool
  }
  @MainActor func paintingRequest(store:EditorStore)throws->PaintToolRequest {
    let tool=try paintTool(),d=store.document
    var base=store.brush;base.backgroundColor=store.backgroundColor
    if parameters["presetID"] != nil {base=try store.brushes.preset(actionUUID("presetID")).applying(to:base)}
    let brush=try BrushAPI.decode(parameters["brush"],base:base)
    guard let raw=parameters["points"] else{throw AutomationFailure(status:400,message:"points required.")}
    let values=try BrushAPI.merge(raw,schema:BrushAPI.schema("points")) as! [[String:Any]]
    let points=try values.map{v in var v=v;if v["pressure"]==nil{v["pressure"]=1};return try JSONDecoder().decode(StrokePoint.self,from:JSONSerialization.data(withJSONObject:v))}
    let options=try PaintingAPI.decodeOptions(parameters["options"],tool:tool,base:store.paintToolOptions[tool] ?? .defaults(for:tool))
    let targetName=try parameters["target"].map{_ in try string("target")} ?? "pixels"
    let target:PaintTarget
    if targetName=="alpha" || targetName=="quickMask" {
      guard parameters["layerID"]==nil,targetName=="alpha" || parameters["channelID"]==nil else{throw AutomationFailure(status:400,message:"Irrelevant painting target fields.")}
      target = .channel(targetName=="quickMask" ? .quickMask:try .alpha(actionUUID("channelID")))
    } else {
      guard parameters["channelID"]==nil,let id=try parameters["layerID"].map({_ in try actionUUID("layerID")}) ?? d.activeLayerID else{throw AutomationFailure(status:400,message:"A layer target is required.")}
      switch targetName {case "pixels":target = .pixels(id);case "layerMask":target = .layerMask(id);case "smartFilterMask":target = .smartFilterMask(id);default:throw AutomationFailure(status:400,message:"Unknown painting target.")}
    }
    var request=PaintToolRequest(tool:tool,target:target,points:points,brush:brush,options:options);request.mixer=store.mixerPaint
    if tool == .patternStamp {
      let id=try parameters["patternID"].map{_ in try string("patternID")} ?? store.patterns.selected?.id
      request.pattern=(d.patterns ?? []).first{$0.id==id} ?? store.patterns.items.first{$0.id==id}
      var explicitPhase=false
      if case .object(let p)=parameters["options"],case .object(let q)=p["placement"] {explicitPhase=q["phaseX"] != nil || q["phaseY"] != nil}
      if !explicitPhase,let first=points.first {
        let origin=options.aligned && store.patternStampID==id ? store.patternStampOrigin ?? PathPoint(first.x,first.y):PathPoint(first.x,first.y)
        request.options.placement.phaseX=Float(origin.x);request.options.placement.phaseY=Float(origin.y)
      }
    } else if parameters["patternID"] != nil {throw AutomationFailure(status:400,message:"patternID is only valid for Pattern Stamp.")}
    do {try request.validate()} catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
    return request
  }
}
@MainActor extension EditorStore {
  var paintingState:[String:Any] {
    let settings=Dictionary(uniqueKeysWithValues:PaintTool.allCases.map{tool in
      let values=BrushAPI.json(paintToolOptions[tool] ?? .defaults(for:tool)) as? [String:Any] ?? [:]
      let keys=Set((PaintingAPI.options(tool)["properties"] as? [String:Any] ?? [:]).keys)
      return (tool.rawValue,values.filter{keys.contains($0.key)})
    })
    return ["settings":settings,"mixer":["reservoir":mixerPaint.reservoir.map{BrushAPI.json($0)} ?? NSNull(),"pickup":mixerPaint.pickup.map{BrushAPI.json($0)} ?? NSNull(),"amount":mixerPaint.amount,"tipWidth":mixerPaint.tip?.width ?? 0,"tipHeight":mixerPaint.tip?.height ?? 0],"patternOrigin":patternStampOrigin.map{BrushAPI.json($0)} ?? NSNull(),"patternID":patternStampID as Any? ?? NSNull(),"patterns":((document.patterns ?? [])+patterns.items).map{["id":$0.id,"name":$0.displayName]},"gestureActive":brushGesture != nil]
  }
}
extension AutomationService {
  func configurePainting(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws {
    let store=document.store
    if command.name=="paint.configure" {
      let tool=try command.paintTool();store.paintToolOptions[tool]=try PaintingAPI.decodeOptions(command.parameters["options"],tool:tool,base:store.paintToolOptions[tool] ?? .defaults(for:tool));return
    }
    let operation=try command.string("operation")
    let fields:[String:Set<String>]=["load":["color"],"clean":[],"sample":["x","y","size","layerID","allLayers","solid"]]
    guard let allowed=fields[operation],Set(command.parameters.keys).subtracting(["operation"]).isSubset(of:allowed) else{throw AutomationFailure(status:400,message:"Unknown or irrelevant Mixer operation fields.")}
    if operation=="clean" {store.mixerPaint.clean();return}
    if operation=="load" {
      var color=store.brush.color
      if let value=command.parameters["color"] {let json=try BrushAPI.merge(value,schema:BrushAPI.color);color=try JSONDecoder().decode(Pixel.self,from:JSONSerialization.data(withJSONObject:json))}
      store.mixerPaint.load(color);return
    }
    func flag(_ key:String,_ fallback:Bool)throws->Bool {guard let v=command.parameters[key] else{return fallback};guard case .bool(let b)=v else{throw AutomationFailure(status:400,message:"Invalid \(key).")};return b}
    let options=store.paintToolOptions[.mixerBrush] ?? .defaults(for:.mixerBrush)
    guard let layerID=try command.parameters["layerID"].map({_ in try command.actionUUID("layerID")}) ?? store.document.activeLayerID else{throw AutomationFailure(status:400,message:"Choose a source layer.")}
    let point=try PathPoint(command.number("x",range:-1_000_000...1_000_000),command.number("y",range:-1_000_000...1_000_000)),size=try command.parameters["size"].map{_ in try command.number("size",range:0.5...2048)} ?? store.brush.size
    let all=try flag("allLayers",options.sampleAllLayers),solid=try flag("solid",options.loadSolidColorOnly),original=store.document,generation=store.layerPanelGeneration,expectedToken=token
    store.geometryBusy=true;defer{if store.layerPanelGeneration==generation{store.geometryBusy=false;store.geometryTask=nil}}
    let worker=Task.detached(priority:.userInitiated){try PaintingPreparation.loadMixer(in:original,layerID:layerID,point:point,size:size,allLayers:all,solid:solid)}
    store.geometryTask=Task {await withTaskCancellationHandler{_ = try? await worker.value} onCancel:{worker.cancel()}}
    let state=try await withTaskCancellationHandler{try await worker.value} onCancel:{worker.cancel()}
    try Task.checkCancellation();prune()
    guard store.geometryTask?.isCancelled != true,isRunning,token==expectedToken,shares.contains(where:{$0.id==shareID}),store.layerPanelGeneration==generation,store.document==original,revision(store)==command.revision else{throw AutomationFailure(status:409,message:"Mixer sampling was cancelled or sharing/state changed.")}
    store.mixerPaint=state
  }
}
