import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum AdjustmentBrushAPI {
  static let commands=["adjustmentBrush.configure","adjustmentBrush.stroke","adjustmentBrush.object","adjustmentBrush.edit"]
  static func array(_ item:[String:Any],_ min:Int,_ max:Int)->[String:Any] {["type":"array","items":item,"minItems":min,"maxItems":max]}
  static func settingsSchema(_ kind:AdjustmentBrushKind)->[String:Any] {
    func n(_ a:Double=0,_ b:Double=1,_ integer:Bool=false)->[String:Any] {BrushAPI.number(a,b,integer:integer)}
    func obj(_ fields:[String:Any],_ required:[String]=[])->[String:Any] {BrushAPI.object(fields,required:required)}
    let u=n(),flag=BrushAPI.flag
    func integer(_ a:Double,_ b:Double)->[String:Any] {BrushAPI.number(a,b,integer:true)}
    switch kind {
    case .colorVibrance:
      return obj(Dictionary(uniqueKeysWithValues:ModernAdjustment.controls(for:.colorVibrance).map{($0.key,n(Double($0.minimum),Double($0.maximum),false))}))
    case .brightnessContrast:return obj(["brightness":n(-1,1,false),"contrast":n(0,10,false)])
    case .exposure:return obj(["exposure":n(-20,20,false),"offset":n(-0.5,0.5,false),"gammaCorrection":n(0.01,9.99,false)])
    case .levels:
      let channel=obj(["inputBlack":integer(0,253),"inputWhite":integer(2,255),"gamma":n(0.1,9.99,false),"outputBlack":integer(0,255),"outputWhite":integer(0,255)])
      return obj(Dictionary(uniqueKeysWithValues:["rgb","red","green","blue"].map{($0,channel)}))
    case .curves:
      let point=obj(["input":integer(0,255),"output":integer(0,255)],["input","output"])
      return obj(Dictionary(uniqueKeysWithValues:["rgb","red","green","blue"].map{($0,obj(["points":array(point,2,19)]))}))
    case .hueSaturation:
      let values=obj(["hue":integer(-180,360),"saturation":integer(-100,100),"lightness":integer(-100,100)])
      let color=obj(["hue":integer(0,360),"saturation":integer(0,100),"lightness":integer(0,100)],["hue","saturation","lightness"])
      return obj(["master":values,"colorization":values,"colorize":flag,"ranges":array(obj(["values":values,"bounds":array(integer(-360,720),4,4),"displayColor":["anyOf":[color,["type":"null"]]]],["values","bounds"]),6,6)])
    case .colorBalance:
      let values=obj(["cyanRed":integer(-100,100),"magentaGreen":integer(-100,100),"yellowBlue":integer(-100,100)])
      return obj(["shadows":values,"midtones":values,"highlights":values,"preserveLuminosity":flag])
    case .blackWhite,.vibrance,.photoFilter,.channelMixer,.selectiveColor:
      guard case .classic(let value)=kind.initial else{return obj([:])}
      let variants=ClassicAdjustment.apiSchema["oneOf"] as! [[String:Any]]
      let variant=variants.first{(($0["properties"] as? [String:Any])?["kind"] as? [String:String])?["const"]==value.kind.rawValue}!
      var fields=variant["properties"] as! [String:Any];fields.removeValue(forKey:"kind");return obj(fields)
    case .threshold,.posterize:return obj(["level":integer(kind == .threshold ? 1:2,255)])
    case .invert:return obj([:])
    case .colorLookup:return AdjustmentBrushLookupAPI.settingsSchema
    case .gradientMap:
      let color:[String:Any]=["oneOf":[obj(["rgb":obj(["_0":BrushAPI.color],["_0"])],["rgb"]),obj(["hsb":obj(["hue":n(-360000,360000,false),"saturation":u,"brightness":u],["hue","saturation","brightness"])],["hsb"]),obj(["gray":obj(["ink":u],["ink"])],["gray"])]]
      let stop=obj(["position":u,"midpoint":u,"color":color],["position","midpoint","color"])
      let opacity=obj(["position":u,"midpoint":u,"opacity":u],["position","midpoint","opacity"])
      let gradient=obj(["name":["type":"string","minLength":1,"maxLength":65535],"colors":array(stop,1,1000),"opacity":array(opacity,0,1000),"smoothness":u,"method":BrushAPI.enumeration(GradientMethod.allCases.map(\.rawValue))])
      return obj(["gradient":gradient,"reverse":flag,"dither":flag])
    }
  }
  static func settings(_ value:Adjustment)->Any {
    switch value {
    case .modern(let v) where v.kind == .colorVibrance:return v.values
    case .brightnessContrast(let b,let c):return ["brightness":b,"contrast":c]
    case .exposure(let e):return ["exposure":e]
    case .colorLookup(let v):return ["interpolation":v.interpolation.rawValue,"dither":v.dither]
    case .levels(let v):return BrushAPI.json(v);case .curves(let v):return BrushAPI.json(v)
    case .hueSaturation(let v):return BrushAPI.json(v);case .colorBalance(let v):return BrushAPI.json(v)
    case .classic(let v):return v.apiObject.filter{$0.key != "kind"}
    case .tonalSteps(let v):return ["level":v.level];case .gradientMap(let v):return BrushAPI.json(v)
    default:return [String:Any]()
    }
  }
  static func decode(_ input:AutomationValue?,kind:AdjustmentBrushKind,base:Adjustment)throws->Adjustment {
    guard let input else{return base}
    do {
      let raw=try BrushAPI.merge(input,schema:settingsSchema(kind),base:settings(base),path:"settings")
      let data=try JSONSerialization.data(withJSONObject:raw)
      func decode<T:Decodable>(_ type:T.Type)throws->T {try JSONDecoder().decode(type,from:data)}
      let value:Adjustment
      switch kind {
      case .colorVibrance:
        guard case .modern(var modern)=base,modern.kind == .colorVibrance else{throw AutomationFailure(status:400,message:"Invalid Color and vibrance base.")}
        modern.values=try decode([String:Float].self);value = .modern(modern)
      case .brightnessContrast:let v=try decode([String:Float].self);value = .brightnessContrast(v["brightness"]!,v["contrast"]!)
      case .exposure:
        let v=try decode([String:Float].self)
        // Existing gain-only brush layers retain their legacy operation until
        // the client explicitly supplies a new full-control parameter.
        if case .exposure = base, (input.jsonValue as? [String:Any])?["offset"] == nil, (input.jsonValue as? [String:Any])?["gammaCorrection"] == nil { value = .exposure(v["exposure"]!) }
        else { value = .classic(.exposure(.init(exposure:v["exposure"] ?? 0,offset:v["offset"] ?? 0,gammaCorrection:v["gammaCorrection"] ?? 1))) }
      case .levels:value = .levels(try decode(LevelsAdjustment.self));case .curves:value = .curves(try decode(CurvesAdjustment.self))
      case .hueSaturation:value = .hueSaturation(try decode(HueSaturationAdjustment.self));case .colorBalance:value = .colorBalance(try decode(ColorBalanceAdjustment.self))
      case .vibrance,.blackWhite,.photoFilter,.channelMixer,.selectiveColor:
        var fields=raw as! [String:Any];guard case .classic(let v)=kind.initial else{fatalError()};fields["kind"]=v.kind.rawValue;value = .classic(try ClassicAdjustment.decodeAPI(fields))
      case .threshold,.posterize:let v=try decode([String:Int].self);value = .tonalSteps(.init(kind:kind == .threshold ? .threshold:.posterize,level:v["level"]!))
      case .gradientMap:value = .gradientMap(try decode(GradientMapAdjustment.self));case .invert:value = .invert
      case .colorLookup:
        guard case .colorLookup(var lookup)=base else{throw AutomationFailure(status:400,message:"Invalid Color Lookup base.")}
        let fields=raw as! [String:Any]
        guard fields["lutID"]==nil,fields["preset"]==nil else{throw AutomationFailure(status:400,message:"LUT references require the shared API resolver.")}
        if fields["clearLUT"] as? Bool == true{lookup.lut=nil}
        lookup.interpolation=ColorLUT.Interpolation(rawValue:fields["interpolation"] as! String)!
        lookup.dither=fields["dither"] as! Bool;value = .colorLookup(lookup)
      }
      try value.validate();return value
    } catch let e as AutomationFailure {throw e} catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "kind":return BrushAPI.enumeration(AdjustmentBrushKind.allCases.map(\.rawValue))
    case "settings":return ["anyOf":AdjustmentBrushKind.allCases.map(settingsSchema)]
    case "subtract","newLayer","applyToObject","overlay":return BrushAPI.flag
    case "operation":return BrushAPI.enumeration(["new","replace","invert","mask"])
    case "density":return BrushAPI.number(0,1)
    case "feather":return BrushAPI.number(0,100)
    case "x","y":return BrushAPI.number(0,1_000_000)
    case "newLayerID":return ["type":"string","format":"uuid"]
    default:return BrushAPI.schema(key)
    }
  }
  static var capabilities:[String:Any] {
    ["nativeTypes":AdjustmentBrushKind.nativeKinds.map(\.rawValue),"interactivePreview":["targetFPS":60,"performanceGuarantee":false,"coverage":"Eligible static RGB local mask gestures retain validated grayscale coverage through release and preserve full-tail held previews. Grid changes rebuild original-source coverage. Object masks, dual tips, symmetry and document modes retain complete preparation.","history":"One original adjustmentBrush.stroke command per gesture; native/API settings, target IDs, seed, mask metadata, Actions and Undo/Redo remain shared.","api":"Existing adjustmentBrush.stroke accepts complete samples; no streaming endpoint or new Adobe route."],"colorVibrance":["kind":"colorVibrance","controls":["temperature","tint","vibrance","saturation"],"initial":["temperature":0,"tint":0,"vibrance":100,"saturation":0],"nativeArchiveVersion":65,"actionsVersion":61,"workflow":"Shared modern editable adjustment with a black mask; local paint/object, native Properties, Undo/Redo, archive and API partial edits retain settings. Legacy vibrance remains available for old layers/API/Actions.","qualification":"Initial brush values and 16 native types observed in installed Photoshop2026 current profile; factory defaults not proven. Modern transfer remains a work-alike, Photoshop byte equality/Use Legacy and white-balance preset/sampling controls remain open. Editable modern PSD output still rejects; no new Adobe route."],"classicRGB16GradientMap":["workingMaximum":32768,"rampPositions":4097,"arithmetic":"Integer-scaled retained stop colors; Double interpolation uses a fused second product and addition for linear ramp values. Shared native/API/history paths.","scope":"RGB16 Classic Gradient Map only; Gradient Fill, paint, RGB8 and other interpolation methods retain their implementations.","fullPhotoshopParity":false,"remaining":"A retained curved-ramp rounding residual, Smooth interpolation, dither, profile/default/corpus and physical-platform qualification remain open.","adobe":"No new route or desktop descriptor compatibility is claimed."],"hueRangeDisplayColors":["field":"settings.ranges[].displayColor","schema":"Optional H/S/L integer object; hue0...360,saturation/lightness0...100. null removes the override; missing ranges retain settings under ordinary partial edits. Replaced range arrays retain their existing complete-array contract.","behavior":"Display-only sampled swatch; pixel transfer is unchanged. Manual native range-bound edits update swatch hue while preserving sampled saturation/lightness.","versions":["native":92,"Actions":60],"adobe":"No dedicated route in the pinned Firefly v2 contract. PSD/PSB and AHU preserve represented sampled hue2 colors; full sampling and transfer fidelity remain open."],"colorLookup":AdjustmentBrushLookupAPI.capabilities,"commands":commands,"types":AdjustmentBrushKind.allCases.map{["kind":$0.rawValue,"title":$0.title,"settings":settings($0.initial),"schema":settingsSchema($0)]},"behavior":"Editable adjustment layer and mask; first paint/object and subsequent strokes each use one Undo. RGB editing target required. Existing masks retain transform, density and feather. New/subtract and disabled/locked masks reject.","objectProvider":"Apple Vision on-device instance mask, macOS14+, at most8388608 pixels and6000 per side; no foreground at point rejects, no cloud fallback.","limits":"4MiB body,4096 stroke samples; native brush limits apply. Object-mask stored raster at most16MP.","adobe":"No dedicated published Adjustment Brush route; unqualified tool/actionJSON descriptors remain unsupported. Existing classic adjustment and edit routes retain their documented subset.","legacyExposureCreationDefault":["exposure":1],"exposureCompatibility":"New API strokes or retyped layers without offset/gammaCorrection use the original gain-only Exposure. Include either new field for full controls. Existing full-control layers retain their model for partial edits. Native brush creation starts with full controls.","defaults":"Native starting values; complete Photoshop presets/defaults and exact output remain unqualified."]
  }
}
extension AutomationCommand {
  func adjustmentBrushFlag(_ key:String,_ fallback:Bool)throws->Bool {
    guard let v=parameters[key] else{return fallback};guard case .bool(let b)=v else{throw AutomationFailure(status:400,message:"Invalid \(key).")};return b
  }
  func adjustmentBrushKind(_ fallback:AdjustmentBrushKind)throws->AdjustmentBrushKind {
    guard parameters["kind"] != nil else{return fallback};guard let kind=AdjustmentBrushKind(rawValue:try string("kind")) else{throw AutomationFailure(status:400,message:"Unknown adjustment kind.")};return kind
  }
  @MainActor func adjustmentBrushRequest(store:EditorStore,object:Bool=false,decodeSettings:(@MainActor (AutomationValue?,AdjustmentBrushKind,Adjustment)throws->Adjustment)?=nil)throws->AdjustmentBrushRequest {
    let new=try adjustmentBrushFlag("newLayer",store.adjustmentBrushNewLayer)
    if new && parameters["layerID"] != nil {throw AutomationFailure(status:400,message:"newLayer and layerID cannot be combined.")}
    let id=try parameters["layerID"].map{_ in try actionUUID("layerID")} ?? (new ? nil:store.adjustmentBrushLayer?.id)
    let old:Adjustment?=id.flatMap{id in guard let layer=store.document.layers.first(where:{$0.id==id}),case .adjustment(let v)=layer.content else{return nil};return v}
    let kind=try adjustmentBrushKind(old.flatMap(AdjustmentBrushKind.init(adjustment:)) ?? store.adjustmentBrushKind)
    let base=old.flatMap{AdjustmentBrushKind(adjustment:$0)==kind ? $0:nil} ?? (kind == .exposure ? .exposure(1):kind == .colorLookup ? .colorLookup(.init()):kind.initial)
    let value=try decodeSettings?(parameters["settings"],kind,base) ?? AdjustmentBrushAPI.decode(parameters["settings"],kind:kind,base:base)
    let brush=try BrushAPI.decode(parameters["brush"],base:store.brush)
    var points:[StrokePoint]=[]
    if !object {
      guard let input=parameters["points"] else{throw AutomationFailure(status:400,message:"points required.")}
      let values=try BrushAPI.merge(input,schema:BrushAPI.schema("points")) as! [[String:Any]]
      points=try values.map{v in var v=v;if v["pressure"]==nil{v["pressure"]=1};return try JSONDecoder().decode(StrokePoint.self,from:JSONSerialization.data(withJSONObject:v))}
    }
    if id != nil && parameters["newLayerID"] != nil {throw AutomationFailure(status:400,message:"newLayerID is only for a new adjustment.")}
    let newID=try parameters["newLayerID"].map{_ in try actionUUID("newLayerID")} ?? UUID()
    let request=AdjustmentBrushRequest(layerID:id,newLayerID:newID,adjustment:value,points:points,brush:brush,subtract:try adjustmentBrushFlag("subtract",store.adjustmentBrushSubtract))
    do{try request.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)};return request
  }
}
@MainActor extension EditorStore {
  var adjustmentBrushState:[String:Any] {
    let kind=currentAdjustmentBrushKind
    let value:Adjustment;if let layer=adjustmentBrushLayer,case .adjustment(let v)=layer.content {value=v}else{value=kind.initial}
    let mask:Any
    if let layer=adjustmentBrushLayer {let p=layer.effectiveMaskProperties;mask=["density":p.density,"feather":p.feather,"enabled":p.enabled,"inverted":p.inverted] as [String:Any]} else {mask=NSNull()}
    return ["kind":kind.rawValue,"settings":AdjustmentBrushAPI.settings(value),"lookup":AdjustmentBrushLookupAPI.state(value),"layerID":adjustmentBrushLayer?.id.uuidString as Any? ?? NSNull(),"mask":mask,"newLayer":adjustmentBrushNewLayer,"subtract":adjustmentBrushSubtract,"applyToObject":adjustmentBrushObject,"overlay":adjustmentBrushOverlay,"available":canUseAdjustmentBrush]
  }
}
extension AutomationService {
  func configureAdjustmentBrush(_ command:AutomationCommand,store:EditorStore)throws {
    let kind=try command.adjustmentBrushKind(store.adjustmentBrushKind),subtract=try command.adjustmentBrushFlag("subtract",store.adjustmentBrushSubtract),object=try command.adjustmentBrushFlag("applyToObject",store.adjustmentBrushObject),overlay=try command.adjustmentBrushFlag("overlay",store.adjustmentBrushOverlay),new=try command.adjustmentBrushFlag("newLayer",store.adjustmentBrushNewLayer)
    let brush=try BrushAPI.decode(command.parameters["brush"],base:store.brush)
    store.adjustmentBrushKind=kind;store.adjustmentBrushSubtract=subtract;store.adjustmentBrushObject=object;store.adjustmentBrushOverlay=overlay;store.adjustmentBrushNewLayer=new;store.brush=brush;store.render()
  }
}
