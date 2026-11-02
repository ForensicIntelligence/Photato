import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Published create-composite subset. Unknown fields fail explicitly.
enum AdobeCompositeEdit: Sendable {
  case background(AdobeBackgroundEdit)
  case properties(AdobeProtectionEdit)
  case smartObject(AdobeSmartObjectEdit)
  case text(AdobeTextEdit)
  case exposure(AdobeExposureEdit)
  init(_ raw: Any, path: String) throws {
    if let object=raw as? [String:Any],object["type"] as? String=="background_layer"{self = .background(try AdobeBackgroundEdit(raw,path:path))
    }else if let object = raw as? [String: Any], object["adjustments"] != nil { self = .exposure(try AdobeExposureEdit(raw,path:path))
    } else if let object = raw as? [String: Any], object["type"] as? String == "text_layer", object["text"] != nil { self = .text(try AdobeTextEdit(raw, path: path))
    } else if let object = raw as? [String: Any], object["smartObject"] != nil || (object["operation"] as? [String: Any])?["type"] as? String == "add" {
      self = .smartObject(try AdobeSmartObjectEdit(raw, path: path))
    } else { self = .properties(try AdobeProtectionEdit(raw, path: path)) }
  }
  var resource: URL? {switch self{case .smartObject(let edit):edit.url;case .background(let edit):edit.url;default:nil}}
  func apply(to session: inout EditorSession, resources: [URL: Data], fontOptions: AdobeTypeFontOptions = try! .init()) throws {
    switch self {
    case .background(let edit):try edit.apply(to:&session,resources:resources)
    case .exposure(let edit): try edit.apply(to:&session)
    case .text(let edit): try edit.apply(to: &session, fontOptions: fontOptions)
    case .properties(let edit): try edit.apply(to: &session)
    case .smartObject(let edit): try edit.apply(to: &session, resources: resources)
    }
  }
}

struct AdobeSmartObjectEdit: Sendable {
  let adding: Bool
  let name: String?
  let identifier: Int32?
  let url: URL?
  let autoResize: Bool
  let isLinked:Bool?
  let transformMode: String?
  let visible: Bool?
  let clipped: Bool?
  let propertyEdit: AdobeProtectionEdit?
  init(_ raw: Any, path: String) throws {
    typealias Object = AdobeActionsRequest.Object
    let object = try Object(raw, at: path, allowed: ["operation", "type", "name", "id", "smartObject", "transformMode", "isVisible", "isClipped", "protection", "layerEffects"])
    guard try object.string("type") == "smart_object_layer" else { throw AdobeAPIError.unsupported("This add/edit operation requires smart_object_layer.") }
    let operation = try object.object("operation", allowed: ["type", "placement"])
    let verb = try operation.string("type")
    guard ["add", "edit"].contains(verb) else { throw AdobeAPIError.unsupported("Only add/edit Smart Objects are implemented.") }
    adding = verb == "add"
    if adding {
      let placement = try operation.object("placement", allowed: ["type"])
      guard try placement.string("type") == "top" else { throw AdobeAPIError.unsupported("Smart Object add currently supports top placement.") }
      guard object.fields["id"] == nil else { throw AdobeAPIError.unsupported("Explicit IDs on added layers are not supported.") }
    } else if operation.fields["placement"] != nil { throw AdobeAPIError.invalid("An edit cannot have placement.") }
    name = try object.fields["name"].map { _ in try object.string("name") }
    if let name, name.isEmpty || name.utf16.count > 65_535 { throw AdobeAPIError.invalid("Invalid layer name.") }
    identifier = try object.fields["id"].map { _ in Int32(try object.integer("id", range: Int(Int32.min)...Int(Int32.max))) }
    if !adding && ((name == nil) == (identifier == nil)) { throw AdobeAPIError.invalid("Provide exactly one layer reference, name or id.") }
    let smart = try object.object("smartObject", allowed: adding ? ["isLinked", "smartObjectFile"] : ["isLinked", "smartObjectFile", "autoResize"])
    isLinked=try smart.optionalBool("isLinked")
    if isLinked==true,smart.fields["autoResize"] != nil {throw AdobeAPIError.invalid("autoResize applies only to embedded replacements.")}
    autoResize = try smart.optionalBool("autoResize") ?? true
    if smart.fields["smartObjectFile"] != nil {
      let file = try smart.object("smartObjectFile", allowed: ["source"])
      let source = try file.object("source", allowed: ["url"])
      url = try AdobeActionsRequest.url(source.string("url"), path: path + ".smartObject.smartObjectFile.source.url", httpsOnly: false)
    } else {
      guard !adding else { throw AdobeAPIError.invalid("Adding a Smart Object requires an external file source.") }
      url = nil
    }
    transformMode = try object.fields["transformMode"].map { _ in try object.string("transformMode") }
    guard transformMode == nil || ["none", "fit", "fill"].contains(transformMode!) else { throw AdobeAPIError.unsupported("Custom transforms are not implemented by this adapter.") }
    visible = try object.optionalBool("isVisible"); clipped = try object.optionalBool("isClipped")
    if object.fields["protection"] != nil || object.fields["layerEffects"] != nil {
      var properties: [String: Any] = ["operation": ["type": "edit"]]
      properties["name"] = name ?? "Smart Object"
      if let identifier { properties.removeValue(forKey: "name"); properties["id"] = identifier }
      properties["protection"] = object.fields["protection"]; properties["layerEffects"] = object.fields["layerEffects"]
      propertyEdit = try AdobeProtectionEdit(properties, path: path)
    } else { propertyEdit = nil }
  }
  func apply(to session: inout EditorSession, resources: [URL: Data]) throws {
    if let url,let data=resources[url],PcraftImport.recognizes(data) {
      throw AdobeAPIError.unsupported("PhotoCraft projects are Photato-only Smart Object resources; use the Photato interface.")
    }
    let id: UUID
    if adding {
      guard let url, let data = resources[url] else { throw AdobeAPIError.invalid("Missing Smart Object resource.") }
      var layer = try SmartObjectIO.placed(data: data, fileName: url.lastPathComponent.isEmpty ? "Contents" : url.lastPathComponent, in: session.document, fit: false)
      if isLinked==true,let source=layer.smartObject {layer.smartObject=try source.linked(to:.remote(url,data:data))}
      layer.name = name ?? "Smart Object"; layer.x = 0; layer.y = 0
      // Resource jobs expose only their final value. Reset active insertion context
      // so published top placement always creates a root layer.
      var root = session.document; root.activeLayerID = nil
      session = EditorSession(document: root)
      try session.execute(.addLayer(layer)); id = layer.id
    } else {
      let matches = session.document.layers.filter { layer in
        if let name { return layer.name == name }
        guard let identifier, let bytes = layer.sourceTags?["lyid"], bytes.count == 4 else { return false }
        return Int32(bitPattern: bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) == identifier
      }
      guard matches.count == 1, let layer = matches.first, let previous = layer.smartObject else { throw AdobeAPIError.invalid("Reference must identify one embedded Smart Object.") }
      id = layer.id
      if let url {
        guard let data = resources[url] else { throw AdobeAPIError.invalid("Missing replacement resource.") }
        let filename = url.lastPathComponent.isEmpty ? "Contents" : url.lastPathComponent
        if isLinked==true {
          try session.execute(LinkedSmartObjectIO.replacement(data,fileName:filename,reference:.remote(url,data:data),in:session.document,layerID:id,allInstances:false,preserveSize:false,title:"Replace Linked Smart Object"))
        } else if isLinked==false,previous.linkedSource != nil {
          try session.execute(LinkedSmartObjectIO.replacement(data,fileName:filename,reference:nil,in:session.document,layerID:id,allInstances:false,preserveSize:false,title:"Embed Linked Smart Object"))
        } else if PDFImport.recognizes(data) {
          var settings = PDFImportSettings();settings.resolution = 72
          let (object,pixels) = try PDFSmartObjectIO.embedded(data,fileName:filename,in:session.document,
            settings:settings,matching:autoResize ? previous:nil)
          try session.execute(.replaceSmartObject(id,object,pixels,preserveSize:false,allInstances:false))
        } else {
        var source = try SmartObjectIO.decode(data, fileName: filename)
        if autoResize {
          try Command.imageSize(previous.width, previous.height, previous.resolution, .bicubic).apply(to: &source)
        }
        try session.execute(SmartObjectIO.replacement(in: session.document, layerID: id, source: source,
          data: autoResize ? nil : data, fileName: autoResize ? nil : filename, preserveSize: false, allInstances: false))
        }
      }else if let isLinked,isLinked != (previous.linkedSource != nil) {
        guard !isLinked else{throw AdobeAPIError.invalid("Converting to a linked object requires smartObjectFile.")}
        guard !previous.data.isEmpty else{throw AdobeAPIError.unsupported("Provide the source asset to embed an unresolved linked object.")}
        try session.execute(LinkedSmartObjectIO.retag(session.document,layerID:id,source:previous.embedding(),allInstances:false,title:"Embed Linked Smart Object"))
      }
    }
    if let mode = transformMode, mode != "none", let layer = session.document.layers.first(where: { $0.id == id }), let source = layer.smartObject {
      let sx = Double(session.document.width)/Double(source.width), sy = Double(session.document.height)/Double(source.height)
      let scale = mode == "fit" ? min(sx, sy) : max(sx, sy)
      let target = Transform2D.translation((Double(session.document.width)-Double(source.width)*scale)/2,
        (Double(session.document.height)-Double(source.height)*scale)/2) * .scale(scale, scale)
      try session.execute(.transform(id, target * layer.coordinateTransform.inverted(), .bicubic))
    }
    if let visible { try session.execute(.visibility(id, visible)) }
    if let clipped { try session.execute(.clipping(id, clipped)) }
    if let propertyEdit { try propertyEdit.apply(to: &session) }
  }
}
