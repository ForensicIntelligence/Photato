import CoreFoundation
import Foundation
import PhotoCraftCore

/// Published v2 create-composite Exposure layer add/edit contract. The native
/// transfer is shared with desktop/Photato; Adobe service pixel equality is open.
struct AdobeExposureEdit: Sendable {
  static var capabilities: [String:Any] {[
    "route":"POST /v2/create-composite","layerType":"adjustment_layer","operations":["add","edit"],
    "placements":["top","bottom","above","below","into"],"references":"Exactly one unique name or signed32-bit PSD layer id; added ids are generated.",
    "adjustmentsSchema":["type":"object","additionalProperties":false,"required":["type","exposure"],"properties":["type":["const":"exposure"],"exposure":["type":"object","additionalProperties":false,"properties":["exposureValue":["type":"number","minimum":-20,"maximum":20,"default":0],"offset":["type":"number","minimum":-0.5,"maximum":0.5,"default":0],"gammaCorrection":["type":"number","minimum":0.01,"maximum":9.99,"default":1]]]]],
    "behavior":"New layers use defaults; edits retain omitted controls. Native selection masks, visibility/clipping/protection/supported dropShadow and editable expA PSD/PSB are retained. Resource jobs are isolated from desktop history.",
    "limitations":"RGB8/16/32. Pure2.2 RGB8/16 source approximation, linear RGB32 retaining HDR. Full ICC, grayscale/native mode editing, presets, eyedroppers, Photoshop exact output, actionJSON descriptors and physical platform acceptance remain open."
  ]}
  let raw: Data
  init(_ value: Any, path: String) throws {
    typealias Object = AdobeActionsRequest.Object
    let object = try Object(value,at:path,allowed:["operation","type","name","id","adjustments","isVisible","isClipped","protection","layerEffects"])
    if let type = object.fields["type"], type as? String != "adjustment_layer" {
      throw AdobeAPIError.invalid("Exposure requires adjustment_layer.")
    }
    let adjustment = try object.object("adjustments",allowed:["type","exposure"])
    guard try adjustment.string("type") == "exposure" else {
      throw AdobeAPIError.unsupported("This adjustment-layer adapter supports Exposure.")
    }
    _ = try adjustment.object("exposure",allowed:["exposureValue","offset","gammaCorrection"])
    raw = try JSONSerialization.data(withJSONObject:value)
  }
  func apply(to session: inout EditorSession) throws {
    typealias Object = AdobeActionsRequest.Object
    let object = try Object(JSONSerialization.jsonObject(with:raw),at:"Exposure",allowed:["operation","type","name","id","adjustments","isVisible","isClipped","protection","layerEffects"])
    let operation = try object.object("operation",allowed:["type","placement"])
    let verb = try operation.string("type")
    guard ["add","edit"].contains(verb) else { throw AdobeAPIError.unsupported("Exposure requires add or edit.") }
    func reference(_ fields:[String:Any]) throws -> Layer {
      guard (fields["name"] == nil) != (fields["id"] == nil) else { throw AdobeAPIError.invalid("Provide one unique layer name or id.") }
      let ref = try Object(fields,at:"layer reference",allowed:["name","id"])
      let name = try ref.fields["name"].map { _ in try ref.string("name") }
      let id = try ref.fields["id"].map { _ in Int32(try ref.integer("id",range:Int(Int32.min)...Int(Int32.max))) }
      let matches = session.document.layers.filter { layer in
        if let name { return layer.name == name }
        guard let id, let bytes=layer.sourceTags?["lyid"], bytes.count==4 else { return false }
        return Int32(bitPattern:bytes.reduce(UInt32(0)){($0<<8)|UInt32($1)}) == id
      }
      guard matches.count==1,let layer=matches.first else { throw AdobeAPIError.invalid("Layer reference must match exactly once.") }
      return layer
    }
    let adding = verb == "add"
    var previous = ExposureAdjustment()
    let existing: Layer?
    if adding {
      guard object.fields["type"] as? String == "adjustment_layer", object.fields["id"] == nil else { throw AdobeAPIError.invalid("Added Exposure requires adjustment_layer and a generated id.") }
      existing = nil
    } else {
      guard operation.fields["placement"] == nil else { throw AdobeAPIError.invalid("An edit cannot have placement.") }
      let layer = try reference(object.fields.filter { ["name","id"].contains($0.key) })
      guard case .adjustment(.classic(let value))=layer.content,let settings=value.exposureSettings else { throw AdobeAPIError.unsupported("Exposure edit requires an existing Exposure layer.") }
      existing=layer;previous=settings
    }
    let values = try object.object("adjustments",allowed:["type","exposure"]).object("exposure",allowed:["exposureValue","offset","gammaCorrection"])
    func number(_ key:String,_ fallback:Float)throws->Float {
      guard let raw=values.fields[key] else { return fallback }
      guard let n=raw as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,Float(n.doubleValue).isFinite else { throw AdobeAPIError.invalid("Invalid Exposure number.") }
      return Float(n.doubleValue)
    }
    let settings = try ExposureAdjustment(exposure:number("exposureValue",previous.exposure),offset:number("offset",previous.offset),gammaCorrection:number("gammaCorrection",previous.gammaCorrection))
    try settings.validate()
    let id: UUID
    if let existing {
      id=existing.id;try session.execute(.replaceContent(id,.adjustment(.classic(.exposure(settings)))))
    } else {
      let placement = try operation.object("placement",allowed:["type","referenceLayer"])
      let kind = try placement.string("type")
      guard ["top","bottom","above","below","into"].contains(kind) else { throw AdobeAPIError.invalid("Unknown Exposure placement.") }
      let parent: UUID?, position: Int
      if ["top","bottom"].contains(kind) {
        guard placement.fields["referenceLayer"] == nil else { throw AdobeAPIError.invalid("Absolute placement cannot have a reference.") }
        parent=nil;position=kind == "top" ? session.document.children(of:nil).count:0
      } else {
        let target = try reference(placement.object("referenceLayer",allowed:["name","id"]).fields)
        if kind == "into" {
          guard target.isGroup else { throw AdobeAPIError.invalid("Into placement requires a group.") }
          parent=target.id;position=session.document.children(of:target.id).count
        } else {
          parent=target.parentID
          position=(session.document.children(of:parent).firstIndex{$0.id==target.id} ?? 0)+(kind == "above" ? 1:0)
        }
      }
      let name = try object.fields["name"].map { _ in try object.string("name") } ?? "Exposure"
      let layer = try ClassicAdjustment.exposure(settings).layer(in:session.document,name:name)
      id=layer.id;try session.execute(.addLayer(layer));try session.execute(.relocate(id,parent,position))
    }
    if let visible = try object.optionalBool("isVisible") { try session.execute(.visibility(id,visible)) }
    if let clipped = try object.optionalBool("isClipped") { try session.execute(.clipping(id,clipped)) }
    if object.fields["protection"] != nil || object.fields["layerEffects"] != nil {
      // Apply properties after content using its newly assigned unique name.
      // Duplicate names cannot safely address a newly added layer here.
      let layer = session.document.layers.first{$0.id==id}!
      var properties:[String:Any]=["name":layer.name,"operation":["type":"edit"]]
      if let bytes=layer.sourceTags?["lyid"],bytes.count==4 {
        properties.removeValue(forKey:"name");properties["id"]=Int32(bitPattern:bytes.reduce(UInt32(0)){($0<<8)|UInt32($1)})
      }
      properties["protection"]=object.fields["protection"];properties["layerEffects"]=object.fields["layerEffects"]
      try AdobeProtectionEdit(properties,path:"Exposure properties").apply(to:&session)
    }
  }
}
