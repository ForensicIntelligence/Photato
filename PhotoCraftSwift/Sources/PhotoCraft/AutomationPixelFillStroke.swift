import Foundation
import PhotoCraftCore

enum PixelPaintAPI{
  static let commands=["pixels.fill","pixels.stroke"]
  static func schema(_ key:String)->[String:Any]{switch key{
    case "patternID":return ["type":"string","minLength":1,"maxLength":255]
    case "placement":return BrushAPI.object(["scale":BrushAPI.number(1,1000),"angle":BrushAPI.number(-360000,360000),"phaseX":BrushAPI.number(-1_000_000,1_000_000),"phaseY":BrushAPI.number(-1_000_000,1_000_000)])
    case "layerID":return VariablesAPI.uuid
    case "target":return ChannelAPI.parameterSchema("target")!
    case "color":return ["type":"array","minItems":4,"maxItems":4,"items":BrushAPI.number(0,1)]
    case "mask","preserveTransparency":return BrushAPI.flag
    case "mode":return BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue))
    case "location":return BrushAPI.enumeration(PixelStrokeLocation.allCases.map(\.rawValue))
    case "width":return BrushAPI.number(1,250,integer:true)
    default:return BrushAPI.number(0,1)
  }}
  static var settingsSchema:[String:Any]{let fields=["color":schema("color"),"opacity":schema("opacity"),"mode":schema("mode"),"preserveTransparency":schema("preserveTransparency"),"width":schema("width"),"location":schema("location")];return BrushAPI.object(fields,required:Array(fields.keys).sorted())}
  static var targetSchema:[String:Any]{BrushAPI.object(["kind":BrushAPI.enumeration(["layer","mask","channel"]),"id":["type":"string"]],required:["kind","id"])}
  static var patternSchema:[String:Any]{BrushAPI.object(["id":["type":"string"],"name":["type":"string"],"width":BrushAPI.number(1,30000,integer:true),"height":BrushAPI.number(1,30000,integer:true),"depth":BrushAPI.enumeration(PixelDepth.allCases.map(\.rawValue)),"source":BrushAPI.enumeration(["document","library"])],required:["id","name","width","height","depth","source"])}
  static var stateSchema:[String:Any]{BrushAPI.object(["patterns":["type":"array","maxItems":2048,"items":patternSchema],"patternBusy":BrushAPI.flag,"canPatternFill":BrushAPI.flag,"fillContents":["type":"string"],"available":BrushAPI.flag,"target":["anyOf":[["type":"null"],targetSchema]],"fillSettings":settingsSchema,"strokeSettings":settingsSchema,"busy":BrushAPI.flag,"hasSelection":BrushAPI.flag],required:["available","target","fillSettings","strokeSettings","busy","hasSelection","patterns","patternBusy","canPatternFill","fillContents"])}
  static var resultSchema:[String:Any]{["type":"object","required":["revision","pixelPaint"],"properties":["revision":["type":"string"],"pixelPaint":stateSchema]]}
  static var capabilities:[String:Any]{[
    "commands":commands,"stateSchema":stateSchema,"resultSchema":resultSchema,"settingsSchema":settingsSchema,
    "behavior":"Color Fill and Stroke share the native engine, UI/history/Actions41/42. Stroke uses the current selection, or unmasked raster alpha when no selection exists. Masks/channels without a selection use the canvas boundary. Inside/Center/Outside, mode, opacity and Preserve Transparency are explicit. Fill covers the selection or canvas. Shape/type/Smart Objects are never rasterized implicitly.",
    "storage":"Paged GRAY8 coverage, disc extrema and bounded target support patches; preserve all untargeted samples and original selection. Uniform full-target color fills map implicit pixels without materializing a giant plane. Sparse300000-side cases do not establish dense maximum-capacity or physical60fps acceptance.",
    "targets":"Unlocked static RGB raster layers including Background; pixel masks; alpha/spot/Quick Mask numeric planes with display inversion applied once. Preserve Transparency retains raster alpha and honors inherited locks. Other color/ink component targets, Smart Filter masks, temporal documents, richer Fill sources and complete Photoshop semantics remain open.",
    "patternFill":"pixels.fill accepts patternID instead of color, resolving document patterns before native-library patterns once at request acceptance. pixelPaint.patterns exposes IDs/names/dimensions/depth/source. Optional placement scale1–1000/angle/phase uses the existing wrapping premultiplied bilinear sampler and is a Photato API override, not an asserted Photoshop Fill-dialog control. Native default is100%/zero angle/document origin pending reference qualification. Source16MP/preset/request/action limits remain disclosed; no document megapixel cap added. Transparent texels retain destination words. Pattern alpha, blend/opacity/transparency and scalar display inversion share the paint engine; one-pixel/implicit uniform patterns retain sparse full-plane optimization. Later library changes do not modify captured work or portable replay. History/scripted Fill and exact Photoshop phase/kernel/profile/defaults/full acceptance remain open.",
    "ranges":"API RGBA0–1, opacity0–1, integer Stroke width1–250 as an explicit current working limit. The current Adobe page does not establish the Photoshop width maximum. Native initial width1/Center/Normal/100% are chosen defaults pending observation, not claimed Photoshop factory defaults. Color Fill Contents retains foreground/background/custom/black/gray/white and existing Content-Aware handoff; Pattern Contents now uses saved presets; History/scripts remain open.",
    "kernel":"Independent gray disc dilation/erosion, half-width interpolation for odd Center widths, zero outside canvas. Exact Photoshop edge, antialias, gray, blend, HDR/profile and default behavior remains unqualified.",
    "history":"One cancellable immutable prepared transaction and Undo; no-op does not dirty. API source/revision/busy/stale/revoke/target changes publish nothing. Native84 remains the maximum supported archive; old feature minima are unchanged. Solid paint Actions41 retain their minimum; Pattern Actions42 embed an immutable asset/placement and portable target.",
    "cursor":"Native dialogs and controls introduce no new canvas tool or modifier action. Existing effective tool cursors remain unchanged; opacity sliders use native control cursors. No pointer injection is added.",
    "adobe":"The pinned v2 contract has no separately qualified destructive Edit Fill/Stroke selection endpoint. No route or unverified actionJSON descriptor is invented. Existing layer-style strokes, fills and resource jobs keep their distinct contracts. Complete Adobe action/job conformance remains open."
  ]}
  static func settings(_ value:PixelPaintSettings)->[String:Any]{["color":[value.color.r,value.color.g,value.color.b,value.color.a],"opacity":value.opacity,"mode":value.mode.rawValue,"width":value.width,"location":value.location.rawValue,"preserveTransparency":value.preserveTransparency]}
  static func target(_ value:PixelPaintTarget)->[String:Any]{switch value{case .layer(let id):return ["kind":"layer","id":id.uuidString];case .mask(let id):return ["kind":"mask","id":id.uuidString];case .channel(let target):switch target{case .alpha(let id):return ["kind":"channel","id":id.uuidString];case .quickMask:return ["kind":"channel","id":"quickMask"]}}}
}
extension AutomationCommand{
  func pixelPaintRequest(patterns:[RasterPattern]=[])throws->PixelPaintRequest{
    let target:PixelPaintTarget
    if parameters["target"] != nil{guard parameters["layerID"]==nil,parameters["mask"]==nil else{throw AutomationFailure(status:400,message:"Choose a layer/mask or channel target, not both.")};target = .channel(try channelTarget())}
    else{let text=try string("layerID");guard let id=UUID(uuidString:text) else{throw AutomationFailure(status:400,message:"Invalid layer UUID.")};let mask=parameters["mask"]==nil ? false:try selectedPixelFlag("mask");target=mask ? .mask(id):.layer(id)}
    let captured:RasterPattern?,ink:Pixel
    if parameters["patternID"] != nil{guard name=="pixels.fill",parameters["color"]==nil else{throw AutomationFailure(status:400,message:"Choose a color or saved pattern for Fill, not both.")};let id=try string("patternID");guard let pattern=patterns.first(where:{$0.id==id}) else{throw AutomationFailure(status:404,message:"Pattern not found in this document or native library.")};captured=pattern;ink = .white}
    else{guard parameters["placement"]==nil else{throw AutomationFailure(status:400,message:"Pattern placement requires patternID.")};captured=nil;guard case .array(let values)=parameters["color"],values.count==4 else{throw AutomationFailure(status:400,message:"Supply color RGBA or patternID.")};let colors=try values.map{value->Float in guard case .number(let n)=value,n.isFinite,(0...1).contains(n) else{throw AutomationFailure(status:400,message:"Color components must be0–1.")};return Float(n)};ink=Pixel(colors[0],colors[1],colors[2],colors[3])}
    var placement:PatternPlacement?
    if let raw=parameters["placement"]{guard case .object(let fields)=raw else{throw AutomationFailure(status:400,message:"Pattern placement must be an object.")};var value=PatternPlacement();for (key,raw) in fields{guard case .number(let n)=raw,n.isFinite else{throw AutomationFailure(status:400,message:"Invalid pattern placement number.")};switch key{case "scale":value.scale=Float(n);case "angle":value.angle=Float(n);case "phaseX":value.phaseX=Float(n);case "phaseY":value.phaseY=Float(n);default:throw AutomationFailure(status:400,message:"Unknown pattern placement field.")}};try value.validate();placement=value}
    var settings=PixelPaintSettings(color:ink);settings.opacity=parameters["opacity"]==nil ? 1:Float(try number("opacity",range:0...1));settings.preserveTransparency=parameters["preserveTransparency"]==nil ? false:try selectedPixelFlag("preserveTransparency")
    if parameters["mode"] != nil{guard let mode=BlendMode(rawValue:try string("mode")) else{throw AutomationFailure(status:400,message:"Invalid paint mode.")};settings.mode=mode}
    let kind:PixelPaintKind=name=="pixels.fill" ? .fill:.stroke
    if kind == .stroke{settings.width=try integer("width",range:1...250);if parameters["location"] != nil{guard let location=PixelStrokeLocation(rawValue:try string("location")) else{throw AutomationFailure(status:400,message:"Invalid Stroke location.")};settings.location=location}}
    try settings.validate(kind);return .init(kind,target:target,settings:settings,pattern:captured,placement:placement)
  }
}
@MainActor extension EditorStore{
  var pixelPaintState:[String:Any]{["patterns":pixelFillPatterns.map{pattern ->[String:Any] in ["id":pattern.id,"name":pattern.displayName,"width":pattern.surface.width,"height":pattern.surface.height,"depth":pattern.surface.depth.rawValue,"source":document.pattern(pattern.id)==nil ? "library":"document"]},"patternBusy":patterns.busy,"canPatternFill":canFillWithPattern,"fillContents":lastPixelFillContents,"available":canUsePixelPaint,"target":nativePixelPaintTarget.map{PixelPaintAPI.target($0)} as Any? ?? NSNull(),"fillSettings":PixelPaintAPI.settings(lastPixelFill),"strokeSettings":PixelPaintAPI.settings(lastPixelStroke),"busy":geometryBusy,"hasSelection":document.selection != nil]}
}
