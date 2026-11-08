import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum SelectionToolAPI {
  static let commands=["selection.configure","selection.quick","selection.object","selection.brush"]
  static let modes:[String:SelectionMode]=["replace":.replace,"add":.add,"subtract":.subtract,"intersect":.intersect]
  static var stateSchema:[String:Any] {
    let fields:[String:Any]=["available":BrushAPI.flag,"canSelectSubject":BrushAPI.flag,"objectMode":schema("objectMode"),"objectSelectionMode":schema("mode"),"paintSelectionMode":schema("mode"),"sampleAllLayers":BrushAPI.flag,"enhanceEdge":BrushAPI.flag,"overlayColor":BrushAPI.color,"previewActive":BrushAPI.flag]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var resultSchema:[String:Any] {
    var fields=ForegroundSelection.apiStateSchema["properties"] as! [String:Any]
    fields["selectionTools"]=stateSchema;fields["revision"]=["type":"string"]
    return ["type":"object","required":["revision","selectionTools","selection","selectionHasSoftCoverage"],"properties":fields]
  }
  static func modeName(_ value:SelectionMode)->String {modes.first{$0.value==value}!.key}
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "mode":return BrushAPI.enumeration(["replace","add","subtract","intersect"])
    case "objectMode":return BrushAPI.enumeration(ObjectSelectionMode.allCases.map(\.rawValue))
    case "sampleAllLayers","enhanceEdge","objectFinderEnabled","hardEdge":return BrushAPI.flag
    case "overlayColor","finderOverlayColor":return BrushAPI.color
    case "region":
      let point=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000)],required:["x","y"])
      let rect=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000,integer:true),"y":BrushAPI.number(-1_000_000,1_000_000,integer:true),"width":BrushAPI.number(1,1_000_000,integer:true),"height":BrushAPI.number(1,1_000_000,integer:true)],required:["x","y","width","height"])
      let polygon:[String:Any]=["type":"array","minItems":3,"maxItems":4096,"items":point]
      return ["oneOf":[BrushAPI.object(["point":point],required:["point"]),BrushAPI.object(["rectangle":rect],required:["rectangle"]),BrushAPI.object(["polygon":polygon],required:["polygon"])]]
    default:return BrushAPI.schema(key)
    }
  }
  static var subjectSelectionCapability:[String:Any] {
    ["command":"selection.subject","tools":["objectSelection","quickSelection","magicWand"],
      "availabilityField":"selectionTools.canSelectSubject",
      "sampleAllLayersField":"selectionTools.sampleAllLayers",
      "samplingFieldsByTool":["objectSelection":"selectionTools.sampleAllLayers","quickSelection":"selectionTools.sampleAllLayers","magicWand":"magicWand.settings.sampleAllLayers"],
      "parameters":"Explicit active layerID, sampleAllLayers and mode replace reproduce the Options bar action. API defaults remain false/replace; it does not inherit tool settings.",
      "native":"Captures the visible tool's Sample All Layers setting at click, including Magic Wand's separate setting; Properties/Menu sampling preference is retained independently. One selection Undo, source pixels retained.",
      "limits":"See subjectDetection: Apple Vision, macOS14+, 8,388,608 pixels,6000 per side; composite RGB editing target and active raster layer. Busy/draft/active selection stroke disables the native action.",
      "modifiers":"No alternate modifier action on this button; canvas cursors/gesture modes remain unchanged."]
  }
  static var capabilities:[String:Any] {
    ["commands":commands,"stateSchema":stateSchema,"resultSchema":resultSchema,"subjectSelection":subjectSelectionCapability,"algorithms":["finder":"Cached local Vision foreground-instance masks, hover overlays and shared selection; see objectFinder capabilities.","quick":"Native Swift port of PhotoCraft GMM/geodesic seeded graph cut and full-resolution band refinement.","object":"Native rectangle/lasso GrabCut; point selection uses Apple's local Vision foreground instances.","brush":"Native grayscale mask painting with soft coverage and additive/subtractive strokes."],"limits":"16MP canvas;4096 stroke/polygon samples;160000 working graph pixels and192-pixel boundary tiles. Enhance Edge8,388,608 pixels. Point inference8,388,608 pixels and6000 per side. Requests4MiB; source image remains unmodified.","contexts":"RGB document target. Current-layer analysis renders raster/Smart Object, type, shape and fill content in document coordinates with masks; layer styles are excluded as before. Sample All Layers explicitly chooses the visible composite. Groups and adjustments require that explicit composite choice. Locked layers can be sampled. No component/channel-specific analysis yet.","history":"One native selection transaction; frozen previews and cancellation. Action-library version4 saves explicit resulting coverage, with original canvas dimensions; detection is not rerun during replay.","qualification":"Photoshop pixel/model/default/source-kind eligibility/complete Object Finder and physical/live parity remain open. No dedicated Adobe selection-tool route is invented."]
  }
}
extension AutomationCommand {
  func selectionMode(_ fallback:SelectionMode)throws->SelectionMode {
    guard parameters["mode"] != nil else{return fallback}
    guard let mode=SelectionToolAPI.modes[try string("mode")] else{throw AutomationFailure(status:400,message:"Unknown selection mode.")};return mode
  }
  @MainActor func selectionToolRequest(store:EditorStore)throws->SelectionToolRequest {
    let kind:SelectionToolKind=name == "selection.quick" ? .quick:(name == "selection.brush" ? .brush:.object)
    var result=store.selectionToolRequest(kind)
    result.mode=try selectionMode(kind == .object ? store.selectionMode:store.selectionPaintMode)
    result.layerID=try parameters["layerID"].map{_ in try actionUUID("layerID")} ?? store.activeLayer?.id
    result.sampleAllLayers=try adjustmentBrushFlag("sampleAllLayers",store.selectionSampleAllLayers)
    result.hardEdge=try adjustmentBrushFlag("hardEdge",store.objectFinderHardEdge)
    result.enhanceEdge=try adjustmentBrushFlag("enhanceEdge",store.selectionEnhanceEdge)
    result.brush=try BrushAPI.decode(parameters["brush"],base:store.brush)
    if kind == .object {
      guard let value=parameters["region"] else{throw AutomationFailure(status:400,message:"Object Selection needs a region.")}
      let raw=try BrushAPI.merge(value,schema:SelectionToolAPI.schema("region"),path:"region") as! [String:Any]
      if let point=raw["point"] as? [String:Double] {result.points=[.init(x:point["x"]!,y:point["y"]!)]}
      if let rect=raw["rectangle"] as? [String:Double] {result.region = .rectangle(.init(x:Int(rect["x"]!),y:Int(rect["y"]!),width:Int(rect["width"]!),height:Int(rect["height"]!)))}
      if let points=raw["polygon"] as? [[String:Double]] {result.region = .polygon(points.map{.init($0["x"]!,$0["y"]!)})}
    }else {
      guard let value=parameters["points"] else{throw AutomationFailure(status:400,message:"Selection painting needs points.")}
      let raw=try BrushAPI.merge(value,schema:BrushAPI.schema("points"),path:"points") as! [[String:Any]]
      result.points=try raw.map{v in var v=v;if v["pressure"]==nil{v["pressure"]=1};return try JSONDecoder().decode(StrokePoint.self,from:JSONSerialization.data(withJSONObject:v))}
    }
    do{try result.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    return result
  }
}
@MainActor extension EditorStore {
  var selectionToolsState:[String:Any] {
    ["available":canUseSelectionTools,"canSelectSubject":canSelectSubjectFromToolOptions,"objectMode":objectSelectionMode.rawValue,"objectSelectionMode":SelectionToolAPI.modeName(selectionMode),"paintSelectionMode":SelectionToolAPI.modeName(selectionPaintMode),"sampleAllLayers":selectionSampleAllLayers,"enhanceEdge":selectionEnhanceEdge,"overlayColor":BrushAPI.json(selectionOverlayColor),"previewActive":brushGesture?.selection != nil]
  }
}
extension AutomationService {
  func configureSelectionTools(_ command:AutomationCommand,store:EditorStore)throws {
    let mode=try command.selectionMode(store.selectionPaintMode),all=try command.adjustmentBrushFlag("sampleAllLayers",store.selectionSampleAllLayers),enhance=try command.adjustmentBrushFlag("enhanceEdge",store.selectionEnhanceEdge)
    let object:ObjectSelectionMode
    if command.parameters["objectMode"] != nil {guard let value=ObjectSelectionMode(rawValue:try command.string("objectMode")) else{throw AutomationFailure(status:400,message:"Unknown object selection mode.")};object=value}else{object=store.objectSelectionMode}
    let brush=try BrushAPI.decode(command.parameters["brush"],base:store.brush)
    var color=store.selectionOverlayColor
    if let v=command.parameters["overlayColor"] {let raw=try BrushAPI.merge(v,schema:BrushAPI.color,base:BrushAPI.json(color),path:"overlayColor");color=try JSONDecoder().decode(Pixel.self,from:JSONSerialization.data(withJSONObject:raw))}
    let enabled=try command.adjustmentBrushFlag("objectFinderEnabled",store.objectFinderEnabled),hard=try command.adjustmentBrushFlag("hardEdge",store.objectFinderHardEdge)
    var finderColor=store.objectFinderColor
    if let v=command.parameters["finderOverlayColor"] {let raw=try BrushAPI.merge(v,schema:BrushAPI.color,base:BrushAPI.json(finderColor),path:"finderOverlayColor");finderColor=try JSONDecoder().decode(Pixel.self,from:JSONSerialization.data(withJSONObject:raw))}
    store.objectFinderEnabled=enabled;store.objectFinderHardEdge=hard;store.objectFinderColor=finderColor
    if command.parameters["mode"] != nil {store.selectionMode=mode;store.selectionPaintMode=mode}
    store.objectSelectionMode=object;store.selectionSampleAllLayers=all;store.selectionEnhanceEdge=enhance;store.brush=brush;store.selectionOverlayColor=color;store.render()
  }
}
