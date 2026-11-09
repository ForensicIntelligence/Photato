import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum BrushAPI {
  static func number(_ lo:Double=0,_ hi:Double=1,integer:Bool=false)->[String:Any] { ["type":integer ? "integer":"number","minimum":lo,"maximum":hi] }
  static var flag:[String:Any] { ["type":"boolean"] }
  static func enumeration(_ values:[String])->[String:Any] { ["type":"string","enum":values] }
  static func object(_ fields:[String:Any],required:[String]=[])->[String:Any] { ["type":"object","additionalProperties":false,"properties":fields,"required":required] }
  static var bitmap:[String:Any] { var s=object(["width":number(1,2500,integer:true),"height":number(1,2500,integer:true),"bytes":["type":"string","contentEncoding":"base64","maxLength":8_333_336]],required:["width","height","bytes"]);s["type"]=["object","null"];return s }
  static var color:[String:Any] { object(Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,number())}),required:["r","g","b","a"]) }
  static func dynamic(maximum:Double=1)->[String:Any] { object(["jitter":number(0,maximum),"control":enumeration(BrushControl.allCases.map(\.rawValue)),"fadeSteps":number(1,10000,integer:true),"minimum":number()]) }
  static var settings:[String:Any] {
    let unit=number(),angle=number(-360,360),spacing=number(0.01,10),mask=enumeration(BrushMaskMode.allCases.map(\.rawValue))
    var fields:[String:Any]=["tip":bitmap,"spacing":spacing,"angle":angle,"roundness":number(0.01,1),"flow":unit,"mode":enumeration(BlendMode.allCases.map(\.rawValue)),"seed":number(0,9_007_199_254_740_991,integer:true),"zoom":number(0.01,64),"buildUpRate":number(0.1,1000),"lockedSections":["type":"array","maxItems":BrushSettings.sections.count,"uniqueItems":true,"items":enumeration(BrushSettings.sections)]]
    for k in ["spacingEnabled","flipX","flipY","pressureSize","pressureOpacity","aliased","noise","wetEdges","buildUp","protectTexture"] { fields[k]=flag }
    fields["shape"]=object(["enabled":flag,"size":dynamic(),"angle":dynamic(),"roundness":dynamic(),"tiltScale":number(0,2),"flipX":flag,"flipY":flag,"projection":flag])
    fields["scattering"]=object(["enabled":flag,"amount":dynamic(maximum:10),"bothAxes":flag,"count":number(1,16,integer:true),"countJitter":dynamic()])
    fields["texture"]=object(["enabled":flag,"pattern":enumeration(BrushTexture.Pattern.allCases.map(\.rawValue)),"bitmap":bitmap,"scale":spacing,"brightness":number(-1,1),"contrast":number(-1,1),"invert":flag,"eachTip":flag,"mode":mask,"depth":unit,"depthJitter":dynamic(),"seed":number(0,9_007_199_254_740_991,integer:true)])
    fields["dual"]=object(["enabled":flag,"mode":mask,"tip":bitmap,"size":number(0.5,2048),"hardness":unit,"roundness":number(0.01,1),"angle":angle,"spacing":spacing,"scatter":number(0,10),"bothAxes":flag,"count":number(1,16,integer:true),"flip":flag])
    fields["colorDynamics"]=object(["enabled":flag,"perTip":flag,"foregroundBackground":dynamic(),"hue":unit,"saturation":unit,"brightness":unit,"purity":number(-1,1)])
    fields["transfer"]=object(["enabled":flag,"opacity":dynamic(),"flow":dynamic()])
    fields["pose"]=object(["enabled":flag,"tiltX":number(-90,90),"tiltY":number(-90,90),"rotation":angle,"pressure":unit,"overrideTilt":flag,"overrideRotation":flag,"overridePressure":flag])
    fields["smoothing"]=object(["amount":unit,"pulledString":flag,"catchUp":flag,"catchUpOnEnd":flag,"adjustForZoom":flag])
    fields["symmetry"]=object(["mode":enumeration(BrushSymmetry.Mode.allCases.map(\.rawValue)),"center":object(["x":number(-1_000_000,1_000_000),"y":number(-1_000_000,1_000_000)]),"count":number(2,12,integer:true)])
    return object(fields)
  }
  static var brush:[String:Any] { object(["size":number(0.5,2048),"hardness":number(),"opacity":number(),"color":color,"backgroundColor":color,"erase":flag,"settings":settings]) }
  static var point:[String:Any] { object(["x":number(-1_000_000,1_000_000),"y":number(-1_000_000,1_000_000),"pressure":number(),"tiltX":number(-90,90),"tiltY":number(-90,90),"rotation":number(-360,360),"wheel":number(),"time":number(0,3_600_000)],required:["x","y"]) }
  static let operations=["list","select","save","define","rename","delete","move","import","export"]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "brush":return brush
    case "points":return ["type":"array","minItems":1,"maxItems":4096,"items":point]
    case "operation":return enumeration(operations)
    case "target":return enumeration(["pixels","layerMask","smartFilterMask","alpha","quickMask"])
    case "format":return enumeration(["photatobrushes","abr"])
    case "index":return number(0,511,integer:true)
    case "includeSize","includeToolSettings","includeColor":return flag
    case "data":return ["type":"string","contentEncoding":"base64","maxLength":3_000_000]
    case "eraserMode":return enumeration(EraserMode.allCases.map(\.rawValue))
    case "zoom":return number(0.01,64)
    case "texturePatternID":return ["type":"string","minLength":1,"maxLength":255]
    case "layerID","presetID","channelID":return ["type":"string","format":"uuid"]
    default:return ["type":"string","minLength":1,"maxLength":255]
    }
  }
  static func json<T:Encodable>(_ value:T)->Any { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(value))) ?? NSNull() }
  /// Validate against the published tree before merging defaults; JSONDecoder alone ignores unknown keys.
  static func merge(_ value:AutomationValue,schema:[String:Any],base:Any?=nil,path:String="brush")throws->Any {
    func fail()->AutomationFailure { .init(status:400,message:"Invalid or unknown \(path).") }
    if let constant=schema["const"] {
      switch value {
      case .number(let n):guard let c=constant as? NSNumber,CFGetTypeID(c) != CFBooleanGetTypeID(),n==c.doubleValue else{throw fail()}
      case .bool(let b):guard let c=constant as? NSNumber,CFGetTypeID(c)==CFBooleanGetTypeID(),b==c.boolValue else{throw fail()}
      case .string(let v):guard let c=constant as? String,c==v else{throw fail()}
      default:throw fail()
      }
      return value.jsonValue
    }
    if let variants=(schema["anyOf"] ?? schema["oneOf"]) as? [[String:Any]] {
      let matches=variants.compactMap { variant -> Any? in
        var selectedBase=base
        if schema["oneOf"] != nil,let old=base as? [String:Any],let fields=variant["properties"] as? [String:Any],!Set(old.keys).isSubset(of:Set(fields.keys)){selectedBase=nil}
        return try? merge(value,schema:variant,base:selectedBase,path:path)
      }
      guard !matches.isEmpty,schema["oneOf"]==nil || matches.count==1 else{throw fail()};return matches[0]
    }
    if case .null=value,schema["type"] as? String == "null" {return NSNull()}
    if case .null=value,(schema["type"] as? [String])?.contains("null")==true { return NSNull() }
    switch (schema["type"] as? String) ?? (schema["type"] as? [String])?.first {
    case "object":
      guard case .object(let fields)=value,let properties=schema["properties"] as? [String:[String:Any]],Set(fields.keys).isSubset(of:Set(properties.keys)) else { throw fail() }
      var output=base as? [String:Any] ?? [:]
      for (key,v) in fields { output[key]=try merge(v,schema:properties[key]!,base:output[key],path:path+"."+key) }
      guard Set(schema["required"] as? [String] ?? []).isSubset(of:Set(output.keys)) else { throw fail() };return output
    case "array":
      guard case .array(let values)=value,values.count >= (schema["minItems"] as? Int ?? 0),values.count <= (schema["maxItems"] as? Int ?? 4096),let item=schema["items"] as? [String:Any] else { throw fail() }
      let array=try values.map{try merge($0,schema:item,path:path+"[]")}
      if schema["uniqueItems"] as? Bool == true,let strings=array as? [String],Set(strings).count != strings.count { throw fail() };return array
    case "number","integer":
      guard case .number(let n)=value,n.isFinite,n >= (schema["minimum"] as? Double ?? -Double.greatestFiniteMagnitude),n <= (schema["maximum"] as? Double ?? Double.greatestFiniteMagnitude),schema["type"] as? String != "integer" || n.rounded()==n else { throw fail() };return n
    case "boolean":guard case .bool(let b)=value else { throw fail() };return b
    case "string":
      guard case .string(let s)=value,s.count >= (schema["minLength"] as? Int ?? 0),s.count <= (schema["maxLength"] as? Int ?? 8_400_000) else { throw fail() }
      if let allowed=schema["enum"] as? [String],!allowed.contains(s) { throw fail() };return s
    default:throw fail()
    }
  }
  static func decode(_ value:AutomationValue?,base:Brush)throws->Brush {
    var base=base;base.settings=base.settings ?? .init()
    guard let value else { try BrushPainter.validate(base,points:[]);return base }
    do { let raw=try merge(value,schema:brush,base:json(base));let b=try JSONDecoder().decode(Brush.self,from:JSONSerialization.data(withJSONObject:raw));try BrushPainter.validate(b,points:[]);return b }
    catch let e as AutomationFailure { throw e } catch { throw AutomationFailure(status:400,message:"Invalid brush: \(error.localizedDescription)") }
  }
  static var retouchPreviewSchema: [String: Any] {
    object(["targetFPS": ["type": "integer", "const": 60], "active": flag,
      "queuedSamples": number(0, 100_000, integer: true), "publishedFrames": number(0, Double(Int.max), integer: true),
      "displayedSamples": number(0, 100_000, integer: true), "lastRenderMilliseconds": number(0, Double.greatestFiniteMagnitude),
      "performanceGuarantee": ["type": "boolean", "const": false]],
      required: ["targetFPS", "active", "queuedSamples", "publishedFrames", "displayedSamples", "lastRenderMilliseconds", "performanceGuarantee"])
  }
  static var capabilities:[String:Any] { ["eraserModes":["modes":EraserMode.allCases.map(\.rawValue),"configure":"brush.configure.eraserMode changes native tool mode without image history","stroke":"paint.stroke with explicit eraserMode resolves and captures ordinary Brush settings; optionalzoom defaults to the brush zoom. Omission retains legacy brush.erase behavior.","blockScreenSize":16,"blockQuantization":"floor16/zoom; zero footprint is a no-op, not a minimum1pixel","state":"brush.eraserMode","stateSchemaExtension":["type":"object","properties":["eraserMode":enumeration(EraserMode.allCases.map(\.rawValue))],"required":["eraserMode"],"additionalProperties":true],"history":"Existing native stroke/mask/channel and Actions snapshots; mode changes do not mutate stored brush settings.","eraseToHistory":false,"optionAlternate":"Unavailable until a real history source is implemented; native Option-start rejects, cursor shows unavailable.","formats":"260typed commands/native88/Actions54 unchanged","fidelity":"Six ownedRGB8single-click PSreferences; wider kernels/contexts/defaults/continuousstrokes/physical qualification remain open"],"libraryTextureSelection":["parameter":"brush.configure.texturePatternID","textureLoadingSchema":["type":"boolean"],"source":"pattern.library stable pattern ID; grouped desktop Choose Pattern uses the same preparation","snapshot":"Immutable BrushBitmap; later library edits/removal do not affect captured brushes, presets, strokes or Actions","maximumDimension":2500,"resizes":false,"conversion":"Existing ABR encoded-RGB luminance .2126R+.7152G+.0722B, multiplied by alpha, rounded to8bit; exact Photoshop conversion remains unqualified","history":"Changes tool state only; following strokes use normal native/API Undo and Actions","cancellation":"Cancellable worker with document/session/settings/library/revocation guards; complete patch publishes atomically","versions":"260commands/native88/Actions54 unchanged"],"sectionToggles":BrushSectionToggle.apiCapabilities,"paintColorStateSchema":PaintColorPair.stateSchema,"sharedPaintColors":["scope":"Documents in one application controller share remembered image, auxiliary and layer/Smart Filter mask foreground-background pairs; production startup restores them from application defaults. Native document archives do not contain the palette.","history":"Color/target changes leave document pixels, Undo and dirty state unchanged. Brush size/settings remain document-local. Started strokes retain their captured Brush.","revision":"Any shared pair change advances brush-dependent revisions for all attached documents; old API revisions reject before mutation. Removing a document detaches its palette snapshot.","coordinates":"Existing Brush Pixel coordinates are retained; cross-profile/CMM, custom-gray conversion and complete component parity remain unqualified.","adobe":"No new published Adobe colour-palette operation or route."],"paintColorContexts":"Quick Mask and saved auxiliary targets share an auxiliary pair, initially black/white. Pixel layer masks and Smart Filter masks share a distinct mask pair, initially white/black. Image editing restores the image pair. Returning to an image or path target clears Smart Filter mask editing, restoring native/API image command availability; supported prepared mask edits retain their captured valid target and view. channel.view target layerMask/smartFilterMask with layerID selects the native mask; maskEditingTarget reports the owner. X/D and brush.configure affect the active pair; D uses its target defaults. brush.colors retains image/auxiliary and adds mask plus context=mask. Three pairs persist in bounded v2 preferences with non-destructive v1 image/auxiliary migration. Palette/target changes leave document history and native archive versions unchanged. Existing Brush Pixel coordinates remain; Photoshop profile/custom-gray conversion, component contexts and restart defaults retain qualification.","retouchPreviewStateSchema":retouchPreviewSchema,"interactivePreview":["targetFPS":60,"diagnostics":["environment":"PHOTATO_CANVAS_TRACE_DIR","format":"Per-stroke JSON v1 with bounded input receipt, preparation, accepted preview, AppKit draw and display callback timings; optional native event timestamps. No document names, paths, pixels or coordinates.","maximumEvents":20000,"enabledByDefault":false,"physicalPresentationMeasured":false],"retouching":"Paced Clone Stamp, Healing, Spot Healing marker, Dodge/Burn/Sponge and Blur/Sharpen/Smudge previews; retained coverage for fixed-grid Clone Stamp and Spot Healing markers, retained Float32 working tiles for Dodge/Burn/Sponge, and retained neighborhood/pickup buffers for interior fixed-grid Blur/Sharpen/Smudge. Eligible Clone Stamp, Dodge/Burn/Sponge and Blur/Sharpen/Smudge retain validated preview work through release and append only unseen samples. In-flight work finishes before one shared history commit. Healing Brush and Spot Healing always use their complete final algorithms; a healing marker is never committed as pixels. Boundary and expanding-storage Focus strokes use complete preparation. Existing complete algorithms and history remain authoritative; semantic retouch Actions21 resample portable sources, and retouch.stroke shares these native commands with explicit source guards.","pixelBrush":"Incremental ordinary RGB raster strokes retain validated coverage through release, prepare only missing samples and the release tail, and record the original stroke command in shared history/Actions. In-flight preview work finishes before retained commitment. Dual tips, symmetry and auxiliary targets use full stroke preparation.","maskBrush":"Eligible static RGB layer-mask and Adjustment Brush gestures retain canonical grayscale coverage and original command metadata through one history/Actions commit. Changed mask grids rebuild from the original source; ordinary masks omit the release tail while dragging, Adjustment Brush retains its existing full-tail preview. Dependent Light presentation pause applies only to ordinary masks. Dual tips, symmetry, object masks, auxiliary targets, document modes and reconciliation use complete preparation. paint.stroke and adjustmentBrush.stroke replay complete requests; no streaming or physical60fps guarantee.","stationarySmoothing":["targetHz":60,"tools":["brush","pencil","mixerBrush","eraser"],"requiresCatchUp":true,"pulledStringSupported":false,"settleDistanceDocumentPixels":0.01,"releaseTailDuringPreview":false,"replay":"Native held samples retain the last tablet attributes and elapsed time; paint.stroke replays explicitly supplied samples without a wall clock. Catch-up on release is applied only by final commands. Build-up shares the bounded native clock."],"display":"Regional canvas display-buffer updates and cached area-filtered minification. Canvas invalidation follows accepted presentation revisions independently of render-request/API revisions; live strokes do not pulse the document busy indicator for each preview. Painting input preserves every sample without invalidating unchanged previews; retouch pointer damage covers old/new outlines and source markers, with full image invalidation for an unclipped source overlay. Magnified redraw boundaries align to source and backing pixels; fractional pan or noncommensurate zoom uses a full redraw to preserve nearest-neighbor sampling. Initial layout, zoom during loading and Artboard fit prepare presentation at the requested scale before editing. Committing the native zoom field returns keyboard focus to the workspace; external zoom changes supersede an unfinished percentage draft. Proof/channel/complex-mode views use the full display path.","validation":"Native surface storage retains finite-sample validation across safe edits, avoiding repeated full-image scans at stroke startup. Imported data and structural constraints remain validated.","performanceGuarantee":false],"commands":["brush.configure","brush.presets","paint.stroke"],"brushSchema":brush,"pointSchema":point,"presetFormat":"photatobrushes","presetVersion":1,"targets":["pixels","layerMask","smartFilterMask","alpha","quickMask"],"coordinates":"Document pixels; time is milliseconds since stroke start. Optional pressure/tilt in degrees/rotation/wheel. Seed gives reproducible dynamics. Configure patches the current tool; paint snapshots it and creates one Undo step.","limits":"4096 samples per API stroke, 100000 native samples, 200000 generated dabs, 134217728 raster visits; each sparse coverage map at most128MiB. Command body4MiB; inline preset import base64 at most3000000 characters. Native preset files64MiB/512 brushes. API resource limits may be narrower than desktop.","adobe":"No dedicated freehand brush endpoint in the pinned v2 contract. ABR import/export is a native transport subset. Unqualified brush action descriptors/resources currently reject explicitly; this is not a claim of complete execute-actions brush support.","hiddenQuickMask":"paint.stroke channel targets and paint.tool prepared requests reject hidden Quick Mask painting422 without pixels/history. Showing the overlay restores the same targets. Native/API filtering has its separate policy.","fidelity":"Physical bristle simulation, Photoshop exact pixel kernels, full ABR fields and live tablet qualification remain open."] }
}
@MainActor extension EditorStore {
  var retouchPreviewState: [String: Any] {
    ["targetFPS": 60, "active": cloneDraft != nil, "queuedSamples": cloneDraft?.points.count ?? 0,
     "publishedFrames": retouchPreviewFrameCount, "displayedSamples": retouchPreviewSampleCount,
     "lastRenderMilliseconds": retouchPreviewRenderMS, "performanceGuarantee": false]
  }
  var brushState:[String:Any] { ["eraserMode":eraserMode.rawValue,"textureLoading":brushTextureLoading,"preview":["targetFPS":60,"publishedFrames":brushPreviewFrameCount,"displayedSamples":brushPreviewSampleCount,"lastRenderMilliseconds":brushPreviewRenderMS],"brush":BrushAPI.json(brush),"colors":paintColorState,"selectedPresetID":selectedBrushID?.uuidString as Any? ?? NSNull(),"libraryRevision":brushes.revision,"gestureActive":brushGesture != nil,"loadError":brushes.loadError as Any? ?? NSNull(),"presets":brushes.file.presets.map{["id":$0.id.uuidString,"name":$0.name,"group":$0.group,"includeSize":$0.includeSize,"includeToolSettings":$0.includeToolSettings,"includeColor":$0.includeColor]}] }
}
extension AutomationCommand {
  func brushStroke(document:CraftDocument,current:Brush,library:BrushPresetFile)throws->Command {
    let target=try parameters["target"].map{_ in try string("target")} ?? "pixels"
    var base=current
    if parameters["presetID"] != nil { let id=try actionUUID("presetID");guard let p=library.presets.first(where:{$0.id==id}) else {throw AutomationFailure(status:404,message:"Unknown preset.")};base=p.applying(to:base) }
    var b=try BrushAPI.decode(parameters["brush"],base:base)
    guard let input=parameters["points"] else {throw AutomationFailure(status:400,message:"points required.")}
    let array=try BrushAPI.merge(input,schema:BrushAPI.schema("points")) as! [[String:Any]]
    var points:[StrokePoint]
    do { points=try array.map{raw in var raw=raw;if raw["pressure"]==nil{raw["pressure"]=1};return try JSONDecoder().decode(StrokePoint.self,from:JSONSerialization.data(withJSONObject:raw))};try BrushPainter.validate(b,points:points) }
    catch {throw AutomationFailure(status:400,message:"Invalid stroke: \(error.localizedDescription)")}
    if parameters["eraserMode"] != nil {
      guard let mode=EraserMode(rawValue:try string("eraserMode")) else { throw AutomationFailure(status:400,message:"Unknown eraser mode.") }
      let zoom=try parameters["zoom"].map{_ in try number("zoom",range:0.01...64)} ?? b.settings?.zoom ?? 1
      b.settings = b.settings ?? .init(); b.settings!.zoom=zoom
      b.erase=true
      do { if let resolved=try EraserBrush.resolve(b,mode:mode,zoom:zoom) { b=resolved } else { points=[] } }
      catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
    } else if parameters["zoom"] != nil { throw AutomationFailure(status:400,message:"zoom requires an explicit eraserMode.") }
    if target=="alpha" || target=="quickMask" {
      guard parameters["layerID"]==nil,target=="alpha" || parameters["channelID"]==nil else {throw AutomationFailure(status:400,message:"Irrelevant stroke target fields.")}
      let plane:ChannelPlaneTarget=target=="quickMask" ? .quickMask:try .alpha(actionUUID("channelID"));return .channel(.stroke(plane,points,b))
    }
    guard parameters["channelID"]==nil,let id=try parameters["layerID"].map({_ in try actionUUID("layerID")}) ?? document.activeLayerID,document.layers.contains(where:{$0.id==id}) else {throw AutomationFailure(status:400,message:"Choose a valid layer target.")}
    switch target {
    case "pixels":
      let layer=document.layers.first{$0.id==id}!
      let ordinary:Bool;if case .raster=layer.content {ordinary=layer.smartObject==nil}else{ordinary=false}
      if !ordinary && !b.erase {return .painting(try PaintingPreparation.prepare(.init(tool:.brush,target:.pixels(id),points:points,brush:b),in:document))}
      return .stroke(id,points,b)
    case "layerMask":return .maskStroke(id,points,b)
    case "smartFilterMask":return .smartFilterMask(id,.maskStroke(id,points,b))
    default:throw AutomationFailure(status:400,message:"Unknown paint target.")
    }
  }
}
extension AutomationService {
  func manageBrushes(_ command:AutomationCommand,store:EditorStore,shareID:UUID)async throws->[String:Any] {
    if command.name=="brush.configure" {
      var base = store.brush; base.backgroundColor = store.backgroundColor
      let configured = try BrushAPI.decode(command.parameters["brush"],base:base)
      let eraserMode: EraserMode?
      if command.parameters["eraserMode"] != nil {
        guard let mode=EraserMode(rawValue:try command.string("eraserMode")) else { throw AutomationFailure(status:400,message:"Unknown eraser mode.") }
        eraserMode=mode
      } else { eraserMode=nil }
      if command.parameters["texturePatternID"] != nil {
        let patternID = try command.string("texturePatternID")
        guard !patternID.isEmpty,patternID.count <= 255 else { throw AutomationFailure(status:400,message:"texturePatternID needs1–255characters.") }
        guard store.canChooseBrushTexture else { throw AutomationFailure(status:409,message:"Finish the current edit or pattern load before choosing a brush texture.") }
        guard store.patterns.items.contains(where: { $0.id == patternID }) else { throw AutomationFailure(status:404,message:"Unknown brush texture pattern.") }
        let expectedToken = token, expectedRevision = command.revision
        do {
          try await store.chooseBrushTexture(patternID, configured: configured, authorize: {
            self.prune()
            guard self.isRunning, self.token == expectedToken, self.shares.contains(where: { $0.id == shareID }), self.revision(store) == expectedRevision else {
              throw AutomationFailure(status:409,message:"Brush texture selection cancelled because document sharing or state changed.")
            }
          })
        } catch let error as AutomationFailure { throw error }
        catch is BrushTextureSelectionError { throw AutomationFailure(status:409,message:"Document, brush or pattern library changed during texture selection.") }
        catch is CancellationError { throw AutomationFailure(status:409,message:"Brush texture selection cancelled.") }
        catch { throw AutomationFailure(status:422,message:error.localizedDescription) }
      } else {
        store.brush = configured; store.backgroundColor = configured.backgroundColor ?? store.backgroundColor
      }
      if let eraserMode { store.eraserMode=eraserMode }
      return ["state":store.brushState,"revision":revision(store)]
    }
    let op=try command.string("operation")
    let allowed:[String:Set<String>]=["list":[],"select":["presetID"],"save":["name","group","includeSize","includeToolSettings","includeColor"],"define":["name","group"],"rename":["presetID","name","group"],"delete":["presetID"],"move":["presetID","index"],"import":["data","format"],"export":["presetID","format"]]
    guard let fields=allowed[op],Set(command.parameters.keys).subtracting(["operation"]).isSubset(of:fields) else {throw AutomationFailure(status:400,message:"Unknown or irrelevant brush preset parameter.")}
    func flag(_ key:String,_ fallback:Bool)throws->Bool { guard let v=command.parameters[key] else{return fallback};guard case .bool(let b)=v else{throw AutomationFailure(status:400,message:"\(key) must be boolean.")};return b }
    func format()throws->Bool { guard command.parameters["format"] != nil else{return false};let s=try command.string("format");guard ["abr","photatobrushes"].contains(s) else{throw AutomationFailure(status:400,message:"Unknown brush format.")};return s=="abr" }
    var warnings:[String]=[]
    switch op {
    case "select":try store.selectBrush(command.actionUUID("presetID"))
    case "save":_ = try store.saveBrush(name:command.string("name"),group:command.parameters["group"]==nil ? "My Brushes":command.string("group"),includeSize:flag("includeSize",true),includeToolSettings:flag("includeToolSettings",true),includeColor:flag("includeColor",false))
    case "define":
      let expectedToken=token,expectedRevision=command.revision
      _ = try await store.defineBrush(name:command.string("name"),group:command.parameters["group"]==nil ? "My Brushes":command.string("group")) {
        self.prune()
        guard self.isRunning,self.token==expectedToken,self.shares.contains(where:{$0.id==shareID}),self.revision(store)==expectedRevision else {throw AutomationFailure(status:409,message:"Brush definition cancelled because document sharing or state changed.")}
      }
    case "rename":var p=try store.brushes.preset(command.actionUUID("presetID"));p.name=try command.string("name");if command.parameters["group"] != nil{p.group=try command.string("group")};try store.brushes.save(p)
    case "delete":let id=try command.actionUUID("presetID");try store.brushes.remove(id);if store.selectedBrushID==id{store.selectedBrushID=nil}
    case "move":try store.brushes.move(command.actionUUID("presetID"),to:command.integer("index",range:0...511))
    case "import":
      guard case .string(let text)=command.parameters["data"],text.utf8.count<=3_000_000,let data=Data(base64Encoded:text) else {throw AutomationFailure(status:400,message:"Supply bounded base64 brush data.")};warnings=try store.brushes.importData(data,abr:format())
    case "export":let abr=try format();let id=try command.parameters["presetID"].map{_ in try command.actionUUID("presetID")};return ["state":store.brushState,"revision":revision(store),"format":abr ? "abr":"photatobrushes","data":try store.brushes.exportData(id,abr:abr).base64EncodedString()]
    default:break
    }
    return ["state":store.brushState,"revision":revision(store),"warnings":warnings]
  }
}
