import Foundation
import PhotoCraftCore

// Native translation of PhotoCraft io/linked.rs and smart_map.rs (MIT OR Apache-2.0),
// bounded to embedded files and affine placement. Never resolve filesystem links.
enum PSDSmartObjects {
  struct File { var name: String; var data: Data }
  static func files(_ document: CraftDocument) throws -> [String: File] {
    var files: [String: File] = [:]
    for key in ["lnk2", "lnk3", "lnkD", "lnkE"] {
      guard let data = document.sourceMetadata?["psdGlobal_" + key] else { continue }
      var r = PSDReader(data: data)
      while r.remaining > 0 {
        if r.remaining < 8 {
          guard try r.consumePadding(0) else { throw CraftError.invalid("Invalid linked-file padding.") }; break
        }
        let size = try r.length(8)
        guard size <= SmartObject.maximumSourceBytes + 65_536 else { throw CraftError.unsupported("Embedded file exceeds 64 MiB.") }
        var item = try r.view(size)
        let kind = try item.string(4), version = try item.u32()
        // Photoshop 2026's owned PDF fixtures use version 8. Its additional
        // content-ID descriptor follows the embedded bytes inside this record.
        guard (1...8).contains(version) else { throw CraftError.unsupported("Unsupported linked-file version.") }
        let id = try item.string(Int(item.u8()))
        let count = try item.u32()
        guard count <= 1024 else { throw CraftError.invalid("Embedded filename is too long.") }
        var units: [UInt16] = []
        for _ in 0..<count { units.append(UInt16(try item.u16())) }
        let name = String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
        _ = try item.bytes(8)
        let length = try item.length(8)
        guard length <= SmartObject.maximumSourceBytes else { throw CraftError.unsupported("Embedded file exceeds 64 MiB.") }
        if try item.u8() != 0 {
          let bytes = try item.data.dropFirst(item.offset)
          let (_, consumed) = try PSDDescriptor.readPrefix(Data(bytes))
          _ = try item.bytes(consumed)
        }
        if kind == "liFD" {
          guard files[id] == nil else { throw CraftError.invalid("Duplicate embedded source identifier.") }
          files[id] = File(name: name, data: try item.bytes(length))
        }
        _ = try r.bytes((4 - size % 4) % 4)
      }
    }
    return files
  }
  static func descriptor(_ data: Data) throws -> PSDDescriptor {
    var r = PSDReader(data: data)
    guard try r.string(4) == "soLD", [4, 5].contains(try r.u32()) else {
      throw CraftError.unsupported("Unsupported placed-object descriptor.")
    }
    let descriptor = try PSDDescriptor.read(r.bytes(r.remaining), padding: true)
    guard descriptor["quiltWarp"] == nil else {
      throw CraftError.unsupported("Quilt warps are not yet editable.")
    }
    if let value = descriptor["frameCount"]?.number, value != 1 { throw CraftError.unsupported("Animated placed objects are not yet editable.") }
    if let value = descriptor["comp"]?.number, value != -1 { throw CraftError.unsupported("Smart Object layer comps are not yet editable.") }
    if case .object(let warp) = descriptor["warp"], case .enumerated(_, let kind) = warp["warpStyle"], kind.text != "warpNone" {
      throw CraftError.unsupported("Warped Smart Objects are not yet editable.")
    }
    return descriptor
  }
  static func restore(_ layer: inout Layer, in document: CraftDocument, files: [String: File], filterMasks: [String: PSDSmartFilters.Mask] = [:]) throws {
    guard let data = layer.sourceTags?["SoLd"] ?? layer.sourceTags?["SoLE"] else {
      if layer.sourceTags?["PlLd"] != nil { throw CraftError.unsupported("Legacy placed objects require a SoLd descriptor.") }
      return
    }
    let d = try descriptor(data)
    guard case .text(let text) = d["Idnt"], case .list(let values) = d["Trnf"], values.count == 8,
      values.allSatisfy({ $0.number?.isFinite == true }) else { throw CraftError.invalid("Invalid Smart Object placement.") }
    let id = String(decoding: text.prefix { $0 != 0 }, as: UTF16.self)
    guard let sourceID = UUID(uuidString: id), let file = files[id] else {
      throw CraftError.unsupported("Missing embedded Smart Object source; external links are not followed.")
    }
    var object: SmartObject
    let pixels: Surface
    if PDFImport.recognizes(file.data) {
      (object,pixels) = try PSDPDFSmartObjects.restore(file.data,fileName:file.name,descriptor:d,in:document)
    } else {
      for key in ["PgNm","totalPages"] {
        if let value = d[key]?.number,value != 1 {throw CraftError.unsupported("Multipage non-PDF placed objects are not yet editable.")}
      }
      let source = try SmartObjectIO.decode(file.data, fileName: file.name)
      (object,pixels) = try SmartObjectIO.embedded(document: source, in: document, originalData: file.data, fileName: file.name)
    }
    object.sourceID = sourceID
    let q = values.map { $0.number! }, w = Double(object.width), h = Double(object.height)
    let t = Transform2D(a: (q[2]-q[0])/w, b: (q[3]-q[1])/w,
      c: (q[6]-q[0])/h, d: (q[7]-q[1])/h, tx: q[0], ty: q[1])
    let corner = t.point(w, h)
    guard abs(corner.x-q[4]) < 0.001, abs(corner.y-q[5]) < 0.001 else {
      throw CraftError.unsupported("Perspective Smart Object placement is not yet editable.")
    }
    if case .list(let values) = d["nonAffineTransform"], values != d["Trnf"].flatList {
      throw CraftError.unsupported("Non-affine Smart Object placement is not yet editable.")
    }
    try t.validated()
    let maskWorld = layer.maskCoordinateTransform
    layer.x = Int(floor(t.tx)); layer.y = Int(floor(t.ty))
    layer.affine = .translation(-Double(layer.x), -Double(layer.y)) * t
    layer.smartObject = object; layer.content = .raster(pixels)
    if let filters = d["filterFX"] {
      var stack = try PSDSmartFilters.read(filters)
      guard case .text(let placed) = d["placed"] else { throw CraftError.invalid("Missing filter cache identifier.") }
      let key = String(decoding: placed.prefix { $0 != 0 }, as: UTF16.self)
      if let mask = filterMasks[key] { stack.mask = mask.pixels; stack.maskProperties.transform = mask.transform }
      layer.smartFilters = stack
    }
    if layer.mask != nil {
      var properties = layer.effectiveMaskProperties
      properties.transform = try t.inverted() * maskWorld; layer.maskProperties = properties
    }
  }
  static func placedDescriptor(_ layer: Layer) throws -> Data {
    guard let source = layer.smartObject else { throw CraftError.invalid("Missing embedded source.") }
    let pdf = try PSDPDFSmartObjects.exportSettings(source)
    guard layer.warp == nil else { throw CraftError.unsupported("Save editable Warp as Photato, or rasterize before PSD/PSB export. Warp descriptor interchange is not yet supported.") }
    guard source.stackMode == nil else { throw CraftError.unsupported("Save image stacks as Photato to preserve editable stack modes. PSD stack-mode interchange is not implemented.") }
    guard source.rawDevelopment == nil else { throw CraftError.unsupported("Save RAW Smart Objects as Photato to preserve their source and sensor settings. PSD RAW interchange is not implemented.") }
    let w = Double(source.width), h = Double(source.height), t = layer.coordinateTransform
    let points = [t.point(0, 0), t.point(w, 0), t.point(w, h), t.point(0, h)]
    let quad = PSDValue.list(points.flatMap { [.number($0.x), .number($0.y)] })
    func text(_ value: String) -> PSDValue { .text(Array((value + "\0").utf16)) }
    func ratio() -> PSDValue { .object(PSDDescriptor("null", items: [.init("numerator", .integer(0)), .init("denominator", .integer(600))])) }
    let bounds = PSDDescriptor("classFloatRect", items: [.init("Top ", .number(0)), .init("Left", .number(0)), .init("Btom", .number(h)), .init("Rght", .number(w))])
    let warp = PSDDescriptor("warp", items: [.init("warpStyle", .enumerated(PSDID("warpStyle"), PSDID("warpNone"))),
      .init("warpValue", .number(0)), .init("warpPerspective", .number(0)), .init("warpPerspectiveOther", .number(0)),
      .init("warpRotate", .enumerated(PSDID("Ornt"), PSDID("Hrzn"))), .init("bounds", .object(bounds)),
      .init("uOrder", .integer(4)), .init("vOrder", .integer(4))])
    var descriptor = PSDDescriptor("null", items: [.init("Idnt", text(source.sourceID.uuidString)), .init("placed", text(layer.id.uuidString)),
      .init("PgNm", .integer(pdf?.page ?? 1)), .init("totalPages", .integer(pdf?.pages ?? 1)), .init("Crop", .integer(pdf?.crop ?? 1)),
      .init("frameStep", ratio()), .init("duration", ratio()), .init("frameCount", .integer(1)), .init("Annt", .integer(16)), .init("Type", .integer(pdf == nil ? 2:1)),
      .init("Trnf", quad), .init("nonAffineTransform", quad), .init("warp", .object(warp)),
      .init("Sz  ", .object(PSDDescriptor("Pnt ", items: [.init("Wdth", .number(w)), .init("Hght", .number(h))]))),
      .init("Rslt", .unit(Data("#Rsl".utf8), source.resolution.bitPattern)), .init("comp", .integer(-1)),
      .init("compInfo", .object(PSDDescriptor("null", items: [.init("compID", .integer(-1)), .init("originalCompID", .integer(-1))])))])
    if let stack = layer.smartFilters { descriptor.items.append(.init("filterFX", try PSDSmartFilters.write(stack))) }
    var out = PSDWriter(); out.text("soLD"); out.n(4, 4); out.data.append(try descriptor.encoded())
    while out.data.count % 4 != 0 { out.n(0, 1) }
    return out.data
  }
  static func bakedPreview(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    let tag = try placedDescriptor(layer)
    var preview: Layer
    if layer.smartFilters != nil { preview = try SmartFilterEngine.renderedLayer(layer, in: document) }
    else {
      preview = try PDFSmartObjectIO.renderedLayer(layer,in:document); preview.smartObject = nil
      preview = try DocumentGeometry.transformLayer(preview, by: .identity, in: document)
    }
    preview.smartObject = layer.smartObject
    if preview.sourceTags == nil { preview.sourceTags = [:] }
    preview.sourceTags?["SoLd"] = tag
    preview.sourceTags?.removeValue(forKey: "SoLE"); preview.sourceTags?.removeValue(forKey: "PlLd")
    return preview
  }
  static func linkedData(_ document: CraftDocument) throws -> Data {
    var out = PSDWriter(), seen: [UUID: SmartObject] = [:]
    for object in document.layers.compactMap(\.smartObject) {
      if let previous = seen[object.sourceID] {
        guard previous == object else { throw CraftError.invalid("Conflicting shared Smart Object sources.") }; continue
      }
      seen[object.sourceID] = object
      var bytes = object.data, name = object.fileName
      if !["application/pdf", "image/png", "image/jpeg", "image/tiff", "image/vnd.adobe.photoshop", "application/x-photoshop"].contains(object.mediaType) {
        bytes = try SmartObjectIO.withNesting { try PSDCodec.writeRasterLayers(SmartObjectIO.sourceDocument(object), format: .psb) }
        name = (name as NSString).deletingPathExtension + ".psb"
      }
      guard bytes.count <= SmartObject.maximumSourceBytes else { throw CraftError.unsupported("PSD embedded source exceeds 64 MiB.") }
      var item = PSDWriter(); item.text("liFD"); item.n(7, 4)
      let id = object.sourceID.uuidString; item.n(id.utf8.count, 1); item.text(id)
      let units = Array((name + "\0").utf16); item.n(units.count, 4); for unit in units { item.n(Int(unit), 2) }
      let type = bytes.starts(with: Data("8BPS".utf8)) ? (bytes[5] == 2 ? "8BPB" : "8BPS") : object.mediaType == "application/pdf" ? "PDF " : object.mediaType == "image/png" ? "PNGf" : object.mediaType == "image/jpeg" ? "JPEG" : "TIFF"
      item.text(type); item.text("8BIM"); item.n(bytes.count, 8); item.n(0, 1); item.data.append(bytes)
      item.n(0, 4); item.n(0, 8); item.n(0, 1)
      out.n(item.data.count, 8); out.data.append(item.data)
      while out.data.count % 4 != 0 { out.n(0, 1) }
    }
    return out.data
  }
}
private extension Optional where Wrapped == PSDValue {
  var flatList: [PSDValue]? { if case .list(let values) = self { return values }; return nil }
}
