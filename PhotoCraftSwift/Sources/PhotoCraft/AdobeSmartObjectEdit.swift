import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Published create-composite subset. Unknown fields fail explicitly.
enum AdobeCompositeEdit: Sendable {
  case background(AdobeBackgroundEdit)
  case properties(AdobeProtectionEdit)
  case move(AdobeLayerMoveEdit)
  case smartObject(AdobeSmartObjectEdit)
  case text(AdobeTextEdit)
  case exposure(AdobeExposureEdit)
  init(_ raw: Any, path: String) throws {
    if let object=raw as? [String:Any], (object["operation"] as? [String:Any])?["type"] as? String == "move" { self = .move(try AdobeLayerMoveEdit(raw,path:path))
    } else if let object=raw as? [String:Any],object["type"] as? String=="background_layer"{self = .background(try AdobeBackgroundEdit(raw,path:path))
    }else if let object = raw as? [String: Any], object["adjustments"] != nil { self = .exposure(try AdobeExposureEdit(raw,path:path))
    } else if let object = raw as? [String: Any], object["type"] as? String == "text_layer", object["text"] != nil { self = .text(try AdobeTextEdit(raw, path: path))
    } else if let object = raw as? [String: Any],
              object["smartObject"] != nil
                || (object["operation"] as? [String: Any])?["type"] as? String == "add"
                || (object["type"] as? String == "smart_object_layer"
                    && (object["transformMode"] != nil || object["transform"] != nil
                        || object["blendOptions"] != nil || object["pixelMask"] != nil)) {
      self = .smartObject(try AdobeSmartObjectEdit(raw, path: path))
    } else { self = .properties(try AdobeProtectionEdit(raw, path: path)) }
  }
  var resources: [URL] {
    switch self {
    case .smartObject(let edit): return [edit.url, edit.appearance.pixelMask?.source].compactMap { $0 }
    case .background(let edit): return edit.url.map { [$0] } ?? []
    default: return []
    }
  }
  func apply(to session: inout EditorSession, resources: [URL: Data], fontOptions: AdobeTypeFontOptions = try! .init()) throws {
    switch self {
    case .move(let edit):try edit.apply(to:&session)
    case .background(let edit):try edit.apply(to:&session,resources:resources)
    case .exposure(let edit): try edit.apply(to:&session)
    case .text(let edit): try edit.apply(to: &session, fontOptions: fontOptions)
    case .properties(let edit): try edit.apply(to: &session)
    case .smartObject(let edit): try edit.apply(to: &session, resources: resources)
    }
  }
}

struct AdobeSmartObjectEdit: Sendable {
  private enum Geometry: Sendable {
    case preserve
    case fit
    case fill
    case custom(AdobeSmartObjectTransform)

    init(_ object: AdobeActionsRequest.Object) throws {
      let mode = try object.fields["transformMode"].map { _ in try object.string("transformMode") } ?? "none"
      if mode == "custom" {
        guard let transform = object.fields["transform"] else {
          throw AdobeAPIError.invalid("\(object.path).transform is required in custom mode.")
        }
        self = .custom(try AdobeSmartObjectTransform(transform, path: object.path + ".transform"))
        return
      }
      guard object.fields["transform"] == nil else {
        throw AdobeAPIError.invalid("\(object.path).transform requires custom mode.")
      }
      switch mode {
      case "none": self = .preserve
      case "fit": self = .fit
      case "fill": self = .fill
      default: throw AdobeAPIError.invalid("Unknown \(object.path).transformMode.")
      }
    }
  }

  private struct Insertion: Sendable {
    enum Position: String, Sendable {
      case top, bottom, above, below, into
    }
    let position: Position
    let reference: AdobeLayerMoveEdit.Reference?

    init(_ object: AdobeActionsRequest.Object) throws {
      guard let position = Position(rawValue: try object.string("type")) else {
        throw AdobeAPIError.invalid("Unknown \(object.path).type.")
      }
      self.position = position
      if position == .top || position == .bottom {
        guard object.fields["referenceLayer"] == nil else {
          throw AdobeAPIError.invalid("Top and bottom insertion require no reference layer.")
        }
        reference = nil
      } else {
        reference = try AdobeLayerMoveEdit.Reference(object.object("referenceLayer", allowed: ["name", "id"]))
      }
    }

    func destination(in document: CraftDocument) throws -> (parent: UUID?, index: Int)? {
      if position == .top { return nil }
      if position == .bottom { return (nil, document.children(of: nil).first?.isBackground == true ? 1 : 0) }
      guard let anchor = try reference?.resolve(in: document) else {
        throw AdobeAPIError.invalid("The placement reference is unavailable.")
      }
      if position == .into {
        guard anchor.isGroup else { throw AdobeAPIError.invalid("Into placement requires a group.") }
        return (anchor.id, document.children(of: anchor.id).count)
      }
      let siblings = document.children(of: anchor.parentID)
      guard let index = siblings.firstIndex(where: { $0.id == anchor.id }) else {
        throw AdobeAPIError.invalid("The placement reference is unavailable.")
      }
      return (anchor.parentID, index + (position == .above ? 1 : 0))
    }
  }

  let adding: Bool
  let name: String?
  let identifier: Int32?
  let url: URL?
  let autoResize: Bool
  let isLinked:Bool?
  private let geometry: Geometry
  private let insertion: Insertion?
  private let contentPlacement: SmartObjectContentPlacement?
  let visible: Bool?
  let clipped: Bool?
  let propertyEdit: AdobeProtectionEdit?
  let appearance: AdobeSmartObjectAppearance
  init(_ raw: Any, path: String) throws {
    typealias Object = AdobeActionsRequest.Object
    let object = try Object(raw, at: path, allowed: ["operation", "type", "name", "id", "smartObject", "transformMode", "transform", "isVisible", "isClipped", "protection", "layerEffects", "blendOptions", "pixelMask"])
    guard try object.string("type") == "smart_object_layer" else { throw AdobeAPIError.unsupported("This add/edit operation requires smart_object_layer.") }
    let operation = try object.object("operation", allowed: ["type", "placement"])
    let verb = try operation.string("type")
    guard ["add", "edit"].contains(verb) else { throw AdobeAPIError.unsupported("Only add/edit Smart Objects are implemented.") }
    adding = verb == "add"
    if adding {
      insertion = try Insertion(operation.object("placement", allowed: ["type", "referenceLayer"]))
      guard object.fields["id"] == nil else { throw AdobeAPIError.unsupported("Explicit IDs on added layers are not supported.") }
    } else {
      guard operation.fields["placement"] == nil else { throw AdobeAPIError.invalid("An edit cannot have placement.") }
      insertion = nil
    }
    name = try object.fields["name"].map { _ in try object.string("name") }
    if let name, name.isEmpty || name.utf16.count > 65_535 { throw AdobeAPIError.invalid("Invalid layer name.") }
    identifier = try object.fields["id"].map { _ in Int32(try object.integer("id", range: Int(Int32.min)...Int(Int32.max))) }
    if !adding && ((name == nil) == (identifier == nil)) { throw AdobeAPIError.invalid("Provide exactly one layer reference, name or id.") }
    let smartKeys: Set<String> = adding ? ["isLinked", "smartObjectFile"]
      : ["isLinked", "smartObjectFile", "autoResize", "contentPlacement"]
    let smart = try object.fields["smartObject"].map { _ in try object.object("smartObject", allowed: smartKeys) }
    isLinked = try smart?.optionalBool("isLinked")
    if isLinked == true, smart?.fields["autoResize"] != nil { throw AdobeAPIError.invalid("autoResize applies only to embedded replacements.") }
    autoResize = try smart?.optionalBool("autoResize") ?? true
    if let smart, smart.fields["smartObjectFile"] != nil {
      let file = try smart.object("smartObjectFile", allowed: ["source"])
      let source = try file.object("source", allowed: ["url"])
      url = try AdobeActionsRequest.url(source.string("url"), path: path + ".smartObject.smartObjectFile.source.url", httpsOnly: false)
    } else {
      guard !adding else { throw AdobeAPIError.invalid("Adding a Smart Object requires an external file source.") }
      url = nil
    }
    if let smart, let rawPlacement = smart.fields["contentPlacement"] {
      guard url != nil, isLinked != true else {
        throw AdobeAPIError.invalid("contentPlacement requires an embedded replacement resource.")
      }
      guard smart.fields["autoResize"] == nil, object.fields["transformMode"] == nil, object.fields["transform"] == nil else {
        throw AdobeAPIError.invalid("Omit autoResize, transformMode and transform when using contentPlacement.")
      }
      contentPlacement = try SmartObjectContentPlacementAPI.parse(rawPlacement, path: smart.path + ".contentPlacement")
    } else {
      contentPlacement = nil
    }
    geometry = try Geometry(object)
    appearance = try AdobeSmartObjectAppearance(object, adding: adding)
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
      let destination = try insertion?.destination(in: session.document)
      var layer = try SmartObjectIO.placed(data: data, fileName: url.lastPathComponent.isEmpty ? "Contents" : url.lastPathComponent, in: session.document, fit: false)
      if isLinked==true,let source=layer.smartObject {layer.smartObject=try source.linked(to:.remote(url,data:data))}
      layer.name = name ?? "Smart Object"; layer.x = 0; layer.y = 0
      // Insert at the root before positioning, independent of the active layer.
      var root = session.document; root.activeLayerID = nil
      session = EditorSession(document: root)
      try session.execute(.addLayer(layer)); id = layer.id
      if let destination { try session.execute(.relocate(id, destination.parent, destination.index)) }
    } else {
      let matches = session.document.layers.filter { layer in
        if let name { return layer.name == name }
        guard let identifier, let bytes = layer.sourceTags?["lyid"], bytes.count == 4 else { return false }
        return Int32(bitPattern: bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) == identifier
      }
      guard matches.count == 1, let layer = matches.first, let previous = layer.smartObject else { throw AdobeAPIError.invalid("Reference must identify one Smart Object.") }
      id = layer.id
      if let url {
        guard let data = resources[url] else { throw AdobeAPIError.invalid("Missing replacement resource.") }
        let filename = url.lastPathComponent.isEmpty ? "Contents" : url.lastPathComponent
        if let contentPlacement {
          try session.execute(contentPlacement.replacement(in: session.document, layerID: id, data: data, fileName: filename))
        } else if isLinked==true {
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
    if let layer = session.document.layers.first(where: { $0.id == id }), let source = layer.smartObject,
       let command = try transformCommand(for: layer, source: source, in: session.document) {
      try session.execute(command)
    }
    if let visible { try session.execute(.visibility(id, visible)) }
    if let clipped { try session.execute(.clipping(id, clipped)) }
    try appearance.apply(to: &session, layerID: id, resources: resources)
    if let propertyEdit { try propertyEdit.apply(to: &session) }
  }

  private func transformCommand(for layer: Layer, source: SmartObject, in document: CraftDocument) throws -> Command? {
    let current: Transform2D
    let target: Transform2D
    switch geometry {
    case .preserve: return nil
    case .custom(let transform):
      // An unresolved linked layer displays baked pixels in cache coordinates.
      // Compose the job's requested placement in the original source coordinates.
      current = try layer.smartObjectSourceTransform()
      target = try transform.target(from: current, source: source, in: document, adding: adding)
      if target == current { return nil }
    case .fit, .fill:
      current = try layer.smartObjectSourceTransform()
      let width = Double(document.width), height = Double(document.height)
      let sx = width / Double(source.width), sy = height / Double(source.height)
      let scale = if case .fit = geometry { min(sx, sy) } else { max(sx, sy) }
      target = .translation((width - Double(source.width) * scale) / 2,
                            (height - Double(source.height) * scale) / 2) * .scale(scale, scale)
    }
    return .transform(layer.id, target * (try current.inverted()), .bicubic)
  }
}
