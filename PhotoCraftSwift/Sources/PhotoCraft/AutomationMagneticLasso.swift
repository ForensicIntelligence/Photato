import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum MagneticLassoAPI {
  static let commands=["selection.magnetic.configure","selection.magneticLasso"]
  static var settingsSchema:[String:Any] {BrushAPI.object(["width":BrushAPI.number(1,256),"contrast":BrushAPI.number(1,100),"frequency":BrushAPI.number(0,100),"stylusPressure":BrushAPI.flag,"antiAlias":BrushAPI.flag,"feather":BrushAPI.number(0,100)])}
  static var eventSchema:[String:Any] {BrushAPI.object(["kind":BrushAPI.enumeration(MagneticLassoEvent.Kind.allCases.map(\.rawValue)),"point":BrushAPI.object(["x":BrushAPI.number(0,300_000),"y":BrushAPI.number(0,300_000)],required:["x","y"]),"pressure":BrushAPI.number(0,1),"width":BrushAPI.number(1,256)],required:["kind"])}
  static func schema(_ key:String)->[String:Any] {switch key {
    case "settings":settingsSchema
    case "events":["type":"array","minItems":1,"maxItems":8192,"items":eventSchema]
    case "mode":SelectionToolAPI.schema("mode")
    default:BrushAPI.flag
  }}
  static var stateSchema:[String:Any] {let fields:[String:Any]=["available":BrushAPI.flag,"active":BrushAPI.flag,"loading":BrushAPI.flag,"previewBusy":BrushAPI.flag,"finishing":BrushAPI.flag,"eventCount":BrushAPI.number(0,100_000,integer:true),"fasteningPoints":BrushAPI.number(0,250_000,integer:true),"settings":settingsSchema,"error":["anyOf":[["type":"null"],["type":"string"]]]];return BrushAPI.object(fields,required:Array(fields.keys).sorted())}
  static var resultSchema:[String:Any] {["type":"object","required":["revision","magneticLasso"],"properties":["revision":["type":"string"],"magneticLasso":stateSchema]]}
  static var capabilities:[String:Any] {[
    "commands":commands,"settingsSchema":settingsSchema,"eventsSchema":schema("events"),"stateSchema":stateSchema,"resultSchema":resultSchema,"defaults":BrushAPI.json(MagneticLassoSettings()),
    "algorithm":"Independent native RGB gradient ridge search normal to pointer travel, pointer-distance penalty, pressure-dependent width and distance-based automatic fastening. Photoshop exact path/pixel/default equivalence unqualified.",
    "input":"Visible RGB8/RGB16 composite converted to SDR sRGB; source pixels/profile/depth unchanged.32-bit unavailable as documented by Adobe. No new dense canvas admission cap; existing API shared-document limits remain.",
    "events":"Ordered move/anchor/freehand/straight events have point{x,y} in canvas coordinates. Optional pressure0–1 defaults0 (mouse). remove has no point/width; width has only width1–256. Native/HTTP replay share the incremental tracer; straightClose skips magnetic closure. Mode captured at native start; API explicit replace/add/subtract/intersect.",
    "controls":"Width1–256, Contrast1–100%, Frequency0–100, tablet pressure, Feather0–100 and anti-alias. L/Shift-L use the existing factory tool group; [/] adjust width. Delete removes to the preceding fastening point. Return/double-click/Command-click/start-point close; Esc/Command-period cancel. Option-click gives a straight segment and Option-drag freehand after the initial selection modifier is released.",
    "history":"One Magnetic Lasso native transaction and existing coverage Actions. Configure updates tool settings without history; selection command commits one edit. Preview/Cancel/tool-change/document-read/close cancel unpublished work. Revision/busy/revocation guards use existing native preparation.",
    "limits":"Native100000 events/250000 generated points; API8192 events and4MiB body,128MiB/4,194,304-pixel/8,000-layer sharing. Sparse maximum dimensions and physical60fps/full dense capacity remain qualification gates.",
    "adobe":"No dedicated published Magnetic Lasso route. Unverified semantic actionJSON descriptors remain unsupported; native coverage Actions is distinct."
  ]}
}
extension AutomationCommand {
  func magneticOptions(base:MagneticLassoSettings = .init())throws->MagneticLassoSettings {
    do {
      let raw=try parameters["settings"].map{try BrushAPI.merge($0,schema:MagneticLassoAPI.settingsSchema,base:BrushAPI.json(base),path:"magnetic settings")} ?? BrushAPI.json(base)
      let settings=try JSONDecoder().decode(MagneticLassoSettings.self,from:JSONSerialization.data(withJSONObject:raw));try settings.validate();return settings
    }catch let failure as AutomationFailure {throw failure}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  func magneticEvents()throws->[MagneticLassoEvent] {
    guard let value=parameters["events"] else {throw AutomationFailure(status:400,message:"Magnetic Lasso requires events.")}
    let raw=try BrushAPI.merge(value,schema:MagneticLassoAPI.schema("events"),path:"events") as! [[String:Any]]
    do {return try raw.map{raw in var object=raw;if object["pressure"]==nil{object["pressure"]=0};let event=try JSONDecoder().decode(MagneticLassoEvent.self,from:JSONSerialization.data(withJSONObject:object));try event.validate();return event}}
    catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
}
@MainActor extension EditorStore {
  var magneticLassoState:[String:Any] {
    ["available":canBeginMagneticLasso,"active":magneticDraft != nil,"loading":magneticDraft?.loading ?? false,"previewBusy":magneticDraft?.processing ?? false,"finishing":magneticDraft?.finishing ?? false,"eventCount":magneticDraft?.events.count ?? 0,"fasteningPoints":magneticDraft?.trace.anchors.count ?? 0,"settings":BrushAPI.json(nativeMagneticSettings),"error":magneticDraft?.error as Any? ?? NSNull()]
  }
}
