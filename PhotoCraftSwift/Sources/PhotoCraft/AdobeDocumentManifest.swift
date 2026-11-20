import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum AdobeLayerIdentifiers {
  private static func preferredID(_ layer: Layer, index: Int) -> Int32 {
    layer.isBackground ? 0 : Int32(index + 1)
  }

  static func stored(_ layer: Layer) -> Int32? {
    guard let data = layer.sourceTags?["lyid"], data.count == 4 else { return nil }
    return Int32(bitPattern: data.reduce(0 as UInt32) { ($0 << 8) | UInt32($1) })
  }

  /// Job-local IDs survive subsequent edits and PSD output. Explicit source
  /// identifiers take precedence over the compatibility fallback for untagged files.
  static func assigning(in document: CraftDocument) throws -> CraftDocument {
    var used = Set<Int32>()
    for layer in document.layers {
      if let id = stored(layer), !used.insert(id).inserted {
        throw AdobeAPIError.invalid("The input contains duplicate Photoshop layer IDs.")
      }
    }
    var result = document
    var spare = Int32(document.layers.count + 1)
    for i in result.layers.indices where stored(result.layers[i]) == nil {
      try Task.checkCancellation()
      let preferred = preferredID(result.layers[i], index: i)
      let id: Int32
      if used.insert(preferred).inserted {
        id = preferred
      } else {
        while used.contains(spare) { spare += 1 }
        id = spare
        used.insert(id)
        spare += 1
      }
      let bits = UInt32(bitPattern: id)
      result.layers[i].sourceTags = result.layers[i].sourceTags ?? [:]
      result.layers[i].sourceTags?["lyid"] = Data([
        UInt8(truncatingIfNeeded: bits >> 24), UInt8(truncatingIfNeeded: bits >> 16),
        UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits),
      ])
    }
    return result
  }

  /// An untagged layer only needs an explicit tag on export if its original
  /// identity can no longer be reconstructed from the output stack.
  static func omittingRedundant(in document: CraftDocument, synthesized: Set<UUID>) -> CraftDocument {
    guard document.layerComps == nil, !synthesized.isEmpty else { return document }
    var result = document
    for (index, layer) in document.layers.enumerated()
      where synthesized.contains(layer.id) && stored(layer) == preferredID(layer, index: index) {
      result.layers[index].sourceTags?.removeValue(forKey: "lyid")
    }
    return result
  }
}

struct AdobeManifestRequest: Sendable {
  static let route = "/v2/generate-manifest"
  let input: URL
  let includeXmp: Bool
  let outputs: [AdobeActionsRequest.Output]

  static var capabilities: [String: Any] {
    [
      "route": "POST " + route, "status": "/v2/status/{jobId}",
      "imageSource": "Authorized HTTP(S) PSD/PSB and supported raster resources",
      "mediaType": "application/json", "destinations": ["embedded json/string/base64", "hosted", "HTTPS URL"],
      "includeXmp": true,
      "fields": ["document", "layers", "artboards", "protection", "blendOptions", "pixelMask",
                 "userMask", "vectorMask", "smartObject", "text"],
      "layerIdentifiers": "Preserve PSD layer IDs and assign deterministic IDs to untagged layers. Use returned IDs in create-composite.",
    ]
  }

  init(data: Data) throws {
    guard data.count <= AdobeActionsRequest.maximumBodyBytes else {
      throw AdobeAPIError(status: 413, code: "validation_error", message: "Request exceeds the local 4 MiB limit.")
    }
    let raw: Any
    do { raw = try JSONSerialization.jsonObject(with: data) }
    catch { throw AdobeAPIError(status: 400, code: "invalid_json", message: "Expected a JSON request object.") }
    let root = try AdobeActionsRequest.Object(raw, at: "request", allowed: [
      "image", "includeXmp", "includeLayerThumbnails", "extractSmartObjectData",
      "maximumThumbnailDepth", "trimToTransparency", "exportOptions", "outputs",
    ])
    let image = try root.object("image", allowed: ["source"])
    let source = try image.object("source", allowed: ["url"])
    input = try AdobeActionsRequest.url(source.string("url"), path: "image.source.url", httpsOnly: false)
    includeXmp = try root.optionalBool("includeXmp") ?? false
    let thumbnails = try root.optionalBool("includeLayerThumbnails") ?? false
    let extraction = try root.optionalBool("extractSmartObjectData") ?? false
    _ = try root.optionalBool("trimToTransparency")
    if root.fields["maximumThumbnailDepth"] != nil {
      _ = try root.integer("maximumThumbnailDepth", range: 0...Int(Int32.max))
    }
    guard !thumbnails, !extraction else {
      throw AdobeAPIError.unsupported("Manifest thumbnails and extracted Smart Object assets are unavailable.")
    }
    outputs = try root.array("outputs", count: 1...25).enumerated().map { index, raw in
      let output = try AdobeActionsRequest.Object(raw, at: "outputs[\(index)]", allowed: ["destination", "mediaType"])
      guard try output.string("mediaType") == AdobeActionsRequest.MediaType.json.rawValue else {
        throw AdobeAPIError.invalid("Manifest output mediaType must be application/json.")
      }
      return .init(mediaType: .json, destination: try AdobeActionsRequest.destination(from: output, allowEmbedded: true),
                   shouldOverwrite: nil)
    }
  }

  func execute(input bytes: Data) throws -> [AdobeActionAssets.Encoded] {
    let document = try AdobeLayerIdentifiers.assigning(in: AdobeActionAssets.decode(bytes))
    let filename = input.lastPathComponent
    let data = try AdobeDocumentManifest.encode(document, title: filename.isEmpty ? document.name : filename,
                                               includeXmp: includeXmp)
    guard data.count <= AdobeActionAssets.maximumOutputBytes / outputs.count else {
      throw AdobeAPIError.invalid("Manifest outputs exceed the local aggregate output limit.")
    }
    return outputs.map { .init(output: $0, data: data) }
  }
}

enum AdobeDocumentManifest {
  static func encode(_ document: CraftDocument, title: String, includeXmp: Bool) throws -> Data {
    func bounds(_ area: IntRect) -> [String: Int] {
      ["left": area.x, "top": area.y, "right": area.x + area.width, "bottom": area.y + area.height]
    }
    let children = Dictionary(grouping: document.layers, by: \.parentID)
    let globalLight = document.globalLight ?? GlobalLight()
    let depth: Int
    switch document.depth { case .u8: depth = 8; case .u16: depth = 16; case .f32: depth = 32 }
    var info: [String: Any] = [
      "title": title, "imageMode": document.colorMode.rawValue.lowercased(), "depth": depth,
      "bounds": bounds(.init(x: 0, y: 0, width: document.width, height: document.height)),
      "resolution": document.pixelsPerInch, "iccProfile": ColorManagement.name(document),
      "globalLightingAngle": globalLight.angle, "globalLightingAltitude": globalLight.altitude,
    ]
    if includeXmp, let packet = try FileInfoMetadata.packet(document) {
      guard let xml = String(data: packet, encoding: .utf8) ?? String(data: packet, encoding: .utf16) else {
        throw AdobeAPIError.unsupported("The document XMP packet could not be decoded as XML.")
      }
      info["xmp"] = xml
    }
    let indices = Dictionary(uniqueKeysWithValues: document.layers.enumerated().map { ($0.element.id, $0.offset) })
    let linkGroups = Dictionary(grouping: document.layers.filter { $0.linkID != nil && $0.linkDisabled != true }, by: \.linkID)
    func layerEntry(_ layer: Layer) throws -> [String: Any] {
      try Task.checkCancellation()
      guard let id = AdobeLayerIdentifiers.stored(layer), let index = indices[layer.id] else {
        throw AdobeAPIError.invalid("Missing manifest layer identity.")
      }
      let type: String
      if layer.smartObject != nil { type = "smart_object_layer" }
      else if layer.isBackground { type = "background_layer" }
      else if layer.artboard != nil { type = "artboard" }
      else {
        switch layer.content {
        case .group: type = "group_layer"
        case .text: type = "text_layer"
        case .adjustment: type = "adjustment_layer"
        case .fill, .shape: type = "solid_color_layer"
        case .gradientFill: type = "gradient_layer"
        case .patternFill, .raster: type = "pixel_layer"
        }
      }
      let clipped = layer.clipped == true
      let properties = layer.effectiveMaskProperties
      let linked = layer.linkDisabled == true ? [] : (linkGroups[layer.linkID] ?? [])
        .filter { $0.id != layer.id }.compactMap(AdobeLayerIdentifiers.stored)
      let blend: [String: Any] = [
        "opacity": percent(layer.opacity), "fillOpacity": percent(layer.style?.fillOpacity ?? 1),
        "blendMode": layer.group?.passThrough == true ? "pass_through" : blendName(layer.blendMode),
        "clipped": clipped,
      ]
      var entry: [String: Any] = [
        "id": id, "index": index, "name": layer.name, "type": type, "visible": layer.visible,
        "protection": layer.protection.apiNames.isEmpty ? ["none"] : layer.protection.apiNames,
        "linked": linked, "blendOptions": blend, "layerSettings": ["clippingMask": clipped],
        "pixelMask": NSNull(), "vectorMask": NSNull(),
        "userMask": ["density": percent(properties.density), "feather": properties.feather],
      ]
      if let area = try layer.artboardBounds ?? Renderer.layoutBounds(layer, in: document, stored: true) {
        entry["bounds"] = bounds(area)
      }
      if let mask = layer.mask {
        let t = layer.maskCoordinateTransform, origin = layer.coordinateTransform
        entry["pixelMask"] = [
          "hasMask": true, "extendOpaque": properties.outside == 1, "enabled": properties.enabled,
          "linked": properties.linked, "bounds": bounds(try t.bounds(width: mask.width, height: mask.height)),
          "offset": ["horizontal": t.tx - origin.tx, "vertical": t.ty - origin.ty],
        ] as [String: Any]
      }
      if let mask = layer.vectorMask { entry["vectorMask"] = ["hasMask": !mask.path.isEmpty] }
      if let smart = layer.smartObject {
        entry["smartObject"] = try smartObject(smart, layer: layer)
      }
      if case .text(let text) = layer.content { entry["text"] = ["content": text.text] }
      if layer.isGroup {
        let contents = try (children[layer.id] ?? []).reversed().map(layerEntry)
        entry[layer.artboard == nil ? "children" : "layers"] = contents
      }
      return entry
    }
    let artboards: [[String: Any]] = document.artboards.compactMap { board in
      guard let area = board.artboardBounds, let id = AdobeLayerIdentifiers.stored(board) else { return nil }
      return ["id": id, "name": board.name, "bounds": bounds(area)]
    }
    let layers = try (children[nil] ?? []).reversed().map(layerEntry)
    return try JSONSerialization.data(withJSONObject: ["document": info, "layers": layers, "artboards": artboards],
                                      options: [.sortedKeys])
  }

  private static func percent(_ value: Float) -> Int { Int((unit(value) * 100).rounded()) }
  private static func blendName(_ mode: BlendMode) -> String {
    mode.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
  }

  private static func smartObject(_ object: SmartObject, layer: Layer) throws -> [String: Any] {
    let w = Double(object.width), h = Double(object.height)
    let corners = [PathPoint(0, 0), PathPoint(w, 0), PathPoint(w, h), PathPoint(0, h)]
    let points: [(x: Double, y: Double)]
    if let projection = layer.sourceProjection {
      points = try corners.map { corner in
        let point = try projection.point(corner.x, corner.y)
        return (point.x, point.y)
      }
    } else {
      let transform = try layer.smartObjectSourceTransform()
      points = corners.map { transform.point($0.x, $0.y) }
    }
    var file: [String: Any] = [
      "name": object.fileName, "path": object.fileName,
      "fileType": (object.fileName as NSString).pathExtension, "linked": false,
    ]
    if let source = object.linkedSource {
      file["path"] = URL(string: source.reference).flatMap { $0.isFileURL ? $0.path : nil } ?? source.reference
      file["relative"] = source.relativePath ?? object.fileName
      file["linked"] = true
    }
    let fields: [String: Any] = [
      "type": "smartObject", "transform": points.flatMap { [$0.x, $0.y] }, "fileInfo": file,
    ]
    return ["isSmartObject": true, "isLinked": object.linkedSource != nil,
            "isValid": !object.data.isEmpty || object.linkedSource != nil, "smartObjectData": fields]
  }
}
