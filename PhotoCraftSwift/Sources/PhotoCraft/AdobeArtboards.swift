import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging

/// Published create-artboard request envelope, using a deliberately bounded local
/// output/input subset. The shared command produces real native artboard groups.
struct AdobeArtboardRequest: Sendable {
  struct Image: Sendable { let source: URL; let name: String? }
  let images: [Image]
  let spacing: Int
  let request: AdobeActionsRequest
  var input: URL { images[0].source }
  init(data: Data) throws {
    guard data.count <= AdobeActionsRequest.maximumBodyBytes else { throw AdobeAPIError.invalid("Artboard request exceeds4MiB.") }
    let raw: Any
    do { raw = try JSONSerialization.jsonObject(with: data) } catch { throw AdobeAPIError(status: 400, code: "invalid_json", message: "Expected a JSON object.") }
    let root = try AdobeActionsRequest.Object(raw, at: "request", allowed: ["images", "outputs", "artboardSpacing"])
    spacing = try root.fields["artboardSpacing"] == nil ? 50 : root.integer("artboardSpacing", range: 0...32768)
    images = try root.array("images", count: 1...25).map { raw in
      let image = try AdobeActionsRequest.Object(raw, at: "images[]", allowed: ["source", "name"])
      let source = try image.object("source", allowed: ["url"])
      let url = try AdobeActionsRequest.url(source.string("url"), path: "images[].source.url", httpsOnly: false)
      let name = try image.fields["name"] == nil ? nil : image.string("name")
      if let name, !(1...255).contains(name.count) { throw AdobeAPIError.invalid("Artboard names require1–255 characters.") }
      return Image(source: url, name: name)
    }
    let outputs = try root.array("outputs", count: 1...25)
    for raw in outputs {
      guard let object = raw as? [String: Any], let type = object["mediaType"] as? String, ["image/png", "image/jpeg", "image/tiff", "application/json"].contains(type) else { throw AdobeAPIError.unsupported("This local artboard adapter supports PNG, JPEG, TIFF and JSON. Editable PSD/PSDC artboard output is not implemented.") }
    }
    // Reuse the audited destination/encoding contract parser. The empty composite
    // edit list is never executed; assembly below owns the image workflow.
    request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: ["image": ["source": ["url": images[0].source.absoluteString]], "edits": ["layers": []], "outputs": outputs]), createComposite: true, artboardOutputs: true)
  }
  func document(resources: [URL: Data]) throws -> CraftDocument {
    var sources: [CraftDocument] = []
    var total = 0, width = spacing * (images.count - 1), height = 1
    for image in images {
      try Task.checkCancellation()
      guard let bytes = resources[image.source], !bytes.isEmpty, bytes.count <= AdobeActionAssets.maximumResourceBytes else { throw AdobeAPIError.invalid("Missing or oversized image resource.") }
      total += bytes.count
      guard total <= AdobeActionAssets.maximumOutputBytes else { throw AdobeAPIError.invalid("Artboard resources exceed128MiB.") }
      let source = try DocumentIO.decodeUpload(bytes, native: false, name: image.name ?? "Image")
      guard !PcraftImport.recognizes(bytes) else { throw AdobeAPIError.unsupported("Native Photato/PhotoCraft inputs are not part of the Adobe contract.") }
      try AdobeActionAssets.check(source)
      width += source.width; height = max(height, source.height); sources.append(source)
      guard width <= 32768, width <= AdobeActionAssets.maximumArtboardPixels / height else { throw AdobeAPIError.invalid("Combined artboard canvas exceeds the local4MP flattening limit.") }
    }
    var output = try CraftDocument(width: width, height: height, name: "Artboards")
    output.layers = []; output.activeLayerID = nil
    var x = 0
    for (index, source) in sources.enumerated() {
      let pixels = try ColorManagement.converted(Renderer.composite(source), from: source, to: output)
      var child = Layer(name: images[index].name ?? source.name, content: .raster(pixels)); child.x = x
      output.layers.append(child)
      try Command.artboard(.create(name: images[index].name ?? "\(source.width) x \(source.height)", bounds: .init(x: x, y: 0, width: source.width, height: source.height), background: .clear, children: [child.id])).apply(to: &output)
      x += source.width + spacing
    }
    try AdobeActionAssets.check(output); return output
  }
  func execute(resources: [URL: Data]) throws -> [AdobeActionAssets.Encoded] {
    try AdobeActionAssets.encode(request, document: document(resources: resources), resources: resources)
  }
  /// Document/layer fields follow Adobe's published manifest examples. Artboard
  /// identifiers/bounds form a local subset; rich Adobe descriptor parity is open.
  static func manifest(_ document: CraftDocument) throws -> Data {
    let ids = Dictionary(uniqueKeysWithValues: document.layers.enumerated().map { ($0.element.id, document.layers.count==1 && $0.element.isBackground ? 0:$0.offset+1) })
    func bounds(_ r: IntRect) -> [String: Int] { ["left": r.x, "top": r.y, "right": r.x + r.width, "bottom": r.y + r.height] }
    func layer(_ value: Layer) throws -> [String: Any] {
      let rect = try value.artboardBounds ?? Renderer.layoutBounds(value, in: document, stored: true)
      var result: [String: Any] = ["id": ids[value.id]!, "name": value.name, "type": value.isGroup ? "group_layer" : "pixel_layer", "visible": value.visible, "protection": document.isLocked(value.id) ? ["all"] : ["none"]]
      if value.isBackground {result["type"]="background_layer";result["background"]=["canConvertToLayer":BackgroundLayer.canConvert(document,layerID:value.id)]}
      if let rect { result["bounds"] = bounds(rect) }
      if let object=value.smartObject {
        result["type"]="smart_object_layer"
        let t=try value.smartObjectSourceTransform(),w=Double(object.width),h=Double(object.height)
        let quad=[t.point(0,0),t.point(w,0),t.point(w,h),t.point(0,h)].flatMap{[$0.x,$0.y]}
        var fields:[String:Any]=["type":"smartObject","transform":quad]
        if let link=object.linkedSource {
          let path=URL(string:link.reference).flatMap{$0.isFileURL ? $0.path:nil} ?? link.reference
          fields["fileInfo"]=["relative":object.fileName,"name":object.fileName,"path":path,"fileType":(object.fileName as NSString).pathExtension,"linked":true]
        }
        result["smartObject"]=["isSmartObject":true,"isLinked":object.linkedSource != nil,"isValid":true,"smartObjectData":fields]
      }
      if value.isGroup { result["children"] = try document.layers.filter { $0.parentID == value.id }.map(layer) }
      return result
    }
    return try JSONSerialization.data(withJSONObject: ["document": ["name": document.name, "width": document.width, "height": document.height, "depth": 8, "mode": "rgb"], "layers": try document.layers.filter { $0.parentID == nil }.map(layer), "artboards": document.artboards.map { ["id": ids[$0.id]!, "name": $0.name, "bounds": bounds($0.artboardBounds!)] }], options: [.sortedKeys])
  }
}
