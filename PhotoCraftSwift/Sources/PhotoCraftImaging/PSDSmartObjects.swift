import Foundation
import PhotoCraftCore

// Native translation of PhotoCraft io/linked.rs and smart_map.rs (MIT OR Apache-2.0),
// for affine placement. External references stay as locators.
enum PSDSmartObjects {
  struct File {
    var name: String
    var source: EmbeddedSourceBytes
    var data: Data { source.data }
    var link: LinkedSmartObjectSource?
    var fileType: String
    var fileTypeBytes: Data?
    init(name: String, source: EmbeddedSourceBytes, fileType: String, fileTypeBytes: Data?) {
      self.name = name
      self.source = source
      self.fileType = fileType
      self.fileTypeBytes = fileTypeBytes
    }
    init(name: String, data: Data, link: LinkedSmartObjectSource? = nil, fileType: String = "", fileTypeBytes: Data? = nil) {
      self.init(name: name, source: .memory(data), fileType: fileType, fileTypeBytes: fileTypeBytes)
      self.link = link
    }
  }
  static let linkKeys = ["lnk2", "lnk3", "lnkD", "lnkE"]
  static func files(_ document: CraftDocument, readers: [PSDReader]? = nil,
    paging: PSDRasterPaging.Context? = nil) throws -> [String: File] {
    var files: [String: File] = [:]
    let sources = readers ?? linkKeys.compactMap { key in
      document.sourceMetadata?["psdGlobal_" + key].map { PSDReader(data: $0) }
    }
    for var r in sources {
      while r.remaining > 0 {
        if r.remaining < 8 {
          guard try r.consumePadding(0) else { throw CraftError.invalid("Invalid linked-file padding.") }; break
        }
        let size = try r.length(8)
        guard size <= SmartObject.maximumFileBackedSourceBytes + 65_536 else {
          throw CraftError.unsupported("Embedded Photoshop record exceeds its size limit.")
        }
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
        let typeBytes=try item.bytes(4),type=String(decoding:typeBytes,as:UTF8.self);_ = try item.bytes(4)
        let length = try item.length(8)
        guard length <= (kind == "liFD" ? SmartObject.maximumFileBackedSourceBytes : SmartObject.maximumSourceBytes) else {
          throw CraftError.unsupported("Linked or embedded file exceeds its size limit.")
        }
        if try item.u8() != 0 {
          _ = try PSDDescriptor.readPrefix(&item)
        }
        if kind == "liFD" || kind == "liFE" {
          guard files[id]==nil else{throw CraftError.invalid("Duplicate linked source identifier.")}
          if kind == "liFE" {
            files[id] = try PSDLinkedSmartObjects.read(&item, version: version, length: length,
              name: name, type: type, typeBytes: typeBytes, paging: paging)
          } else {
            if length > SmartObject.maximumSourceBytes {
              var prefix = item
              guard SmartObject.photoshopSourceVersion(try prefix.bytes(6)) != nil else {
                throw CraftError.unsupported("Only PSD or PSB originals may exceed 64 MiB in a Photoshop container.")
              }
            }
            let source: EmbeddedSourceBytes
            if length > SmartObject.maximumArchive95SourceBytes, let paging {
              source = .file(try item.retainSource(length, in: paging.backing))
            } else {
              try paging?.admitRetainedSource(bytes: length)
              source = .memory(try item.retainedBytes(length))
            }
            files[id] = File(name: name, source: source, fileType: type, fileTypeBytes: typeBytes)
          }
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
    if case .object(let warp) = descriptor["warp"], case .enumerated(_, let kind) = warp["warpStyle"], kind.text != "warpNone" {
      throw CraftError.unsupported("Warped Smart Objects are not yet editable.")
    }
    return descriptor
  }
  static func placedIdentifier(in descriptor: PSDDescriptor) -> String? {
    guard case .text(let text) = descriptor["placed"] else { return nil }
    return String(decoding: text.prefix { $0 != 0 }, as: UTF16.self)
  }

  static func placedIdentifier(for layer: Layer) -> String {
    // The saved spelling also keys the filter cache. A duplicate has a fresh
    // layer ID even when it inherits the original's source tags.
    if let raw = layer.sourceTags?["SoLd"] ?? layer.sourceTags?["SoLE"],
      let original = try? descriptor(raw),
      let id = placedIdentifier(in: original), UUID(uuidString: id) == layer.id
    {
      return id
    }
    return layer.id.uuidString
  }

  struct Placement {
    let descriptor: PSDDescriptor
    let file: File
    let sourceID: UUID
    let selectedComp: Int32
  }

  struct PlacementQuads {
    let base: [Double]
    let content: [Double]

    init(_ descriptor: PSDDescriptor) throws {
      func points(_ key: String) throws -> [Double] {
        guard case .list(let values) = descriptor[key], values.count == 8,
              values.allSatisfy({ $0.number?.isFinite == true }) else {
          throw CraftError.invalid("Invalid Smart Object placement corners.")
        }
        return values.compactMap(\.number)
      }
      base = try points("Trnf")
      content = try descriptor["nonAffineTransform"] == nil ? base : points("nonAffineTransform")
    }

    func affine(width: Int, height: Int) -> Transform2D? {
      let q = content, w = Double(width), h = Double(height)
      let placement = Transform2D(a: (q[2] - q[0]) / w, b: (q[3] - q[1]) / w,
                                  c: (q[6] - q[0]) / h, d: (q[7] - q[1]) / h, tx: q[0], ty: q[1])
      let corner = placement.point(w, h)
      let tolerance = content == base ? 0.001 : 1e-9
      return abs(corner.x - q[4]) < tolerance && abs(corner.y - q[5]) < tolerance ? placement : nil
    }

    func projective(width: Int, height: Int) throws -> ProjectiveTransform {
      let corners = stride(from: 0, to: content.count, by: 2).map { PathPoint(content[$0], content[$0 + 1]) }
      let projection = try SelectionTransform.projection(bounds: .init(x: 0, y: 0, width: width, height: height), corners: corners)
      _ = try projection.bounds(width: width, height: height)
      return projection
    }
  }

  static func placement(_ layer: Layer, files: [String: File]) throws -> Placement {
    guard let data = layer.sourceTags?["SoLd"] ?? layer.sourceTags?["SoLE"] else {
      throw CraftError.unsupported("Legacy placed objects require a SoLd descriptor.")
    }
    let d = try descriptor(data)
    guard case .text(let text) = d["Idnt"] else { throw CraftError.invalid("Invalid Smart Object identity.") }
    _ = try PlacementQuads(d)
    let id = String(decoding: text.prefix { $0 != 0 }, as: UTF16.self)
    guard let sourceID = UUID(uuidString: id), let file = files[id] else {
      throw CraftError.unsupported("Missing embedded Smart Object source; external links are not followed.")
    }
    let selectedComp = try d["comp"].map { try PSDLayerComps.integer($0) } ?? -1
    return Placement(descriptor: d, file: file, sourceID: sourceID, selectedComp: selectedComp)
  }

  static func restore(_ layer: inout Layer, placement: Placement, in document: CraftDocument,
      filterMasks: [String: PSDSmartFilters.Mask], decodedSource: CraftDocument?) throws {
    let d = placement.descriptor, file = placement.file
    let selectedComp = placement.selectedComp, sourceID = placement.sourceID
    if file.link != nil,file.data.isEmpty {
      guard selectedComp == -1 else { throw CraftError.unsupported("Locate the linked original before importing its selected child comp. Cached-only PSD comp descriptors remain unqualified.") }
      try PSDLinkedSmartObjects.restore(&layer,descriptor:d,file:file,sourceID:sourceID,filterMasks:filterMasks);return
    }
    var object: SmartObject
    let pixels: Surface
    if PDFImport.recognizes(file.data) {
      guard selectedComp == -1 else { throw CraftError.unsupported("PDF Smart Objects do not expose layered comp selections.") }
      (object,pixels) = try PSDPDFSmartObjects.restore(file.data,fileName:file.name,descriptor:d,in:document)
    } else {
      for key in ["PgNm","totalPages"] {
        if let value = d[key]?.number,value != 1 {throw CraftError.unsupported("Multipage non-PDF placed objects are not yet editable.")}
      }
      let source = try decodedSource ?? SmartObjectIO.decode(file.source, fileName: file.name)
      var placed = try SmartObjectIO.embedded(document: source, in: document, original: file.source, fileName: file.name)
      if selectedComp != -1 {
        guard var choices = placed.0.layerComps else { throw CraftError.invalid("Selected source comp is missing.") }
        choices.selectedID = PSDLayerComps.uuid(selectedComp); try choices.validate(); placed.0.layerComps = choices
        placed.1 = try SmartObjectLayerCompIO.pixels(source, compID: choices.selectedID, stackMode: nil, in: document)
      }
      (object,pixels) = placed
    }
    object.sourceID = sourceID
    if let link=file.link {object=try object.linked(to:link)}
    let quads = try PlacementQuads(d)
    let maskWorld = layer.maskCoordinateTransform
    let maskFrame: Transform2D
    var savedPreview: (pixels: Surface, x: Int, y: Int)?
    if let affine = quads.affine(width: object.width, height: object.height) {
      try affine.validated()
      layer.x = Int(floor(affine.tx)); layer.y = Int(floor(affine.ty))
      layer.affine = .translation(-Double(layer.x), -Double(layer.y)) * affine
      maskFrame = affine
    } else {
      guard object.pdfSource == nil else {
        throw CraftError.unsupported("PDF perspective interchange is not yet supported.")
      }
      layer.sourceProjection = try quads.projective(width: object.width, height: object.height)
      if case .raster(let cache) = layer.content,
         cache.width > 1 || cache.height > 1 || cache.pixel(x: 0, y: 0).a > 0 {
        savedPreview = (cache, layer.x, layer.y)
      }
      layer.x = 0; layer.y = 0; layer.affine = nil
      maskFrame = .identity
    }
    layer.smartObject = object; layer.content = .raster(pixels)
    if let filters = d["filterFX"] {
      var stack = try PSDSmartFilters.read(filters)
      guard let key = placedIdentifier(in: d) else { throw CraftError.invalid("Missing filter cache identifier.") }
      if let mask = filterMasks[key] { stack.mask = mask.pixels; stack.maskProperties.transform = mask.transform }
      layer.smartFilters = stack
    }
    if layer.mask != nil {
      var properties = layer.effectiveMaskProperties
      properties.transform = try maskFrame.inverted() * maskWorld; layer.maskProperties = properties
    }
    if let savedPreview {
      layer.importedSmartAppearance = try .init(layer: layer, pixels: savedPreview.pixels, x: savedPreview.x, y: savedPreview.y)
    }
  }
  static func placedDescriptor(_ layer: Layer) throws -> Data {
    guard let source = layer.smartObject else { throw CraftError.invalid("Missing embedded source.") }
    guard (layer.importedSmartAppearance == nil || layer.sourceProjection != nil),
          source.mediaType != "application/vnd.photocraft.project" else {
      throw CraftError.unsupported("Save source Smart Object appearance as Photato until editable PSD/PSB mapping is qualified.")
    }
    if let descriptor=try PSDLinkedSmartObjects.unresolvedDescriptor(layer,source:source){return descriptor}
    let selectedComp: Int32
    if let selected = source.layerComps?.selectedID {
      selectedComp = try PSDLayerComps.identifiers(source.layerComps!.entries.map(\.id))[selected]!
    } else { selectedComp = -1 }
    let pdf = try PSDPDFSmartObjects.exportSettings(source)
    guard layer.warp == nil || (layer.sourceProjection != nil && layer.warp?.isIdentity == true) else { throw CraftError.unsupported("Save editable Warp as Photato, or rasterize before PSD/PSB export. Warp descriptor interchange is not yet supported.") }
    guard source.stackMode == nil else { throw CraftError.unsupported("Save image stacks as Photato to preserve editable stack modes. PSD stack-mode interchange is not implemented.") }
    guard source.rawDevelopment == nil else { throw CraftError.unsupported("Save RAW Smart Objects as Photato to preserve their source and sensor settings. PSD RAW interchange is not implemented.") }
    let w = Double(source.width), h = Double(source.height)
    let (baseQuad, placedQuad) = try encodedQuads(layer, source: source)
    func text(_ value: String) -> PSDValue { .text(Array((value + "\0").utf16)) }
    func ratio() -> PSDValue { .object(PSDDescriptor("null", items: [.init("numerator", .integer(0)), .init("denominator", .integer(600))])) }
    let bounds = PSDDescriptor("classFloatRect", items: [.init("Top ", .number(0)), .init("Left", .number(0)), .init("Btom", .number(h)), .init("Rght", .number(w))])
    let warp = PSDDescriptor("warp", items: [.init("warpStyle", .enumerated(PSDID("warpStyle"), PSDID("warpNone"))),
      .init("warpValue", .number(0)), .init("warpPerspective", .number(0)), .init("warpPerspectiveOther", .number(0)),
      .init("warpRotate", .enumerated(PSDID("Ornt"), PSDID("Hrzn"))), .init("bounds", .object(bounds)),
      .init("uOrder", .integer(4)), .init("vOrder", .integer(4))])
    var descriptor = PSDDescriptor("null", items: [.init("Idnt", text(source.sourceID.uuidString)), .init("placed", text(placedIdentifier(for: layer))),
      .init("PgNm", .integer(pdf?.page ?? 1)), .init("totalPages", .integer(pdf?.pages ?? 1)), .init("Crop", .integer(pdf?.crop ?? 1)),
      .init("frameStep", ratio()), .init("duration", ratio()), .init("frameCount", .integer(1)), .init("Annt", .integer(16)), .init("Type", .integer(pdf == nil ? 2:1)),
      .init("Trnf", baseQuad), .init("nonAffineTransform", placedQuad), .init("warp", .object(warp)),
      .init("Sz  ", .object(PSDDescriptor("Pnt ", items: [.init("Wdth", .number(w)), .init("Hght", .number(h))]))),
      .init("Rslt", .unit(Data("#Rsl".utf8), source.resolution.bitPattern)), .init("comp", .integer(selectedComp)),
      .init("compInfo", .object(PSDDescriptor("null", items: [.init("compID", .integer(selectedComp)), .init("originalCompID", .integer(-1))])))])
    if let stack = layer.smartFilters { descriptor.items.append(.init("filterFX", try PSDSmartFilters.write(stack))) }
    var out = PSDWriter(); out.text("soLD"); out.n(4, 4); out.data.append(try descriptor.encoded())
    while out.data.count % 4 != 0 { out.n(0, 1) }
    return out.data
  }

  static func encodedQuads(_ layer: Layer, source: SmartObject) throws -> (PSDValue, PSDValue) {
    let w = Double(source.width), h = Double(source.height)
    let positions = [PathPoint(0, 0), .init(w, 0), .init(w, h), .init(0, h)]
    func encode(_ numbers: [Double]) -> PSDValue { .list(numbers.map(PSDValue.number)) }
    if let projection = try layer.smartObjectSourceProjection() {
      guard source.pdfSource == nil else {
        throw CraftError.unsupported("PDF perspective interchange is not yet supported.")
      }
      if let saved = layer.sourceTags?["SoLd"] ?? layer.sourceTags?["SoLE"],
         let old = try? PlacementQuads(descriptor(saved)), old.affine(width: source.width, height: source.height) == nil,
         let original = try? old.projective(width: source.width, height: source.height) {
        if let cached = try layer.linkedSmartObjectPreview()?.projectiveSourceToCache {
          if try original.followed(by: layer.coordinateTransform.inverted()) == cached {
            return (encode(old.base), encode(old.content))
          }
        } else if layer.coordinateTransform == .identity, original == layer.sourceProjection {
          return (encode(old.base), encode(old.content))
        }
      }
      let points = try positions.map { try projection.point($0.x, $0.y) }
      let xs = points.map(\.x), ys = points.map(\.y)
      let left = xs.min()!, top = ys.min()!, right = xs.max()!, bottom = ys.max()!
      return (encode([left, top, right, top, right, bottom, left, bottom]), encode(points.flatMap { [$0.x, $0.y] }))
    }
    let affine = try layer.smartObjectSourceTransform()
    let quad = encode(positions.flatMap { p in let q = affine.point(p.x, p.y); return [q.x, q.y] })
    return (quad, quad)
  }
  static func bakedPreview(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    let tag = try placedDescriptor(layer)
    var preview: Layer
    let projectedLinkCache = try layer.linkedSmartObjectPreview()?.projectiveSourceToCache != nil
    if !projectedLinkCache && (layer.smartFilters != nil || layer.sourceProjection != nil) {
      preview = try SmartFilterEngine.renderedLayer(layer, in: document)
    }
    else {
      let linked=layer.smartObject?.linkedSource != nil
      preview = try PDFSmartObjectIO.renderedLayer(layer,in:document)
      // Preserve numerical mask coverage in document coordinates before changing
      // the raster's local frame. RGBA resampling would ignore gray outside values.
      if linked {preview=try PSDMaskExport.prepared(preview)}
      preview.smartObject = nil
      preview = try DocumentGeometry.transformLayer(preview, by: .identity, in: document,
        method:linked ? .bilinear:.bicubic,clampRasterEdges:!linked)
    }
    preview.smartObject = layer.smartObject
    preview.sourceTags?.removeValue(forKey:"PhLC")
    // Native-only file-type hint is emitted in liFE, never as a PSD layer tag.
    preview.sourceTags?.removeValue(forKey:"PhFT")
    if preview.sourceTags == nil { preview.sourceTags = [:] }
    preview.sourceTags?["SoLd"] = tag
    preview.sourceTags?.removeValue(forKey: "SoLE"); preview.sourceTags?.removeValue(forKey: "PlLd")
    return preview
  }
  /// Separate headers and padding from original bytes so a file save can write
  /// each source directly to the same bounded output as the layer planes.
  static func linkedData(_ document: CraftDocument) throws -> [Data] {
    var chunks: [Data] = []
    var seen: [UUID: SmartObject] = [:], opaqueTypes: [UUID: Data] = [:]
    for layer in document.layers {
      guard let object=layer.smartObject else{continue}
      if object.linkedSource != nil,object.mediaType=="application/octet-stream",object.data.isEmpty {
        let hint=layer.sourceTags?["PhFT"] ?? Data(repeating:32,count:4)
        guard hint.count==4,opaqueTypes[object.sourceID]==nil || opaqueTypes[object.sourceID]==hint else{throw CraftError.invalid("Conflicting opaque linked file types.")};opaqueTypes[object.sourceID]=hint
      }
      if let previous = seen[object.sourceID] {
        guard previous.sharesSource(with: object) else { throw CraftError.invalid("Conflicting shared Smart Object sources.") }; continue
      }
      seen[object.sourceID] = object
      if object.linkedSource != nil {
        var record = PSDWriter()
        try PSDLinkedSmartObjects.append(object, typeHint: layer.sourceTags?["PhFT"], to: &record)
        chunks.append(record.data)
        continue
      }
      var original = object.sourceBytes, name = object.fileName
      if !["application/pdf", "image/png", "image/jpeg", "image/tiff", "image/vnd.adobe.photoshop", "application/x-photoshop"].contains(object.mediaType) {
        original = try SmartObjectIO.withNesting {
          let child = try SmartObjectIO.sourceDocument(object)
          if SmartObjectIO.requiresFileOutput(child) {
            return .file(try PSDCodec.writeFileBackedEmbeddedSmartObject(child))
          }
          return .memory(try PSDCodec.writeEmbeddedSmartObject(child))
        }
        name = (name as NSString).deletingPathExtension + ".psb"
      }
      let bytes = original.data
      let layeredLimit = original.isFileBacked
        ? SmartObject.maximumFileBackedSourceBytes : SmartObject.maximumDocumentSourceBytes
      let limit = SmartObject.photoshopSourceVersion(bytes) != nil ? layeredLimit : SmartObject.maximumSourceBytes
      guard bytes.count <= limit else { throw CraftError.unsupported("PSD embedded source exceeds its file format's limit.") }
      var item = PSDWriter(); item.text("liFD"); item.n(7, 4)
      let id = object.sourceID.uuidString; item.n(id.utf8.count, 1); item.text(id)
      let units = Array((name + "\0").utf16); item.n(units.count, 4); for unit in units { item.n(Int(unit), 2) }
      let type = bytes.starts(with: Data("8BPS".utf8)) ? (bytes[5] == 2 ? "8BPB" : "8BPS") : object.mediaType == "application/pdf" ? "PDF " : object.mediaType == "image/png" ? "PNGf" : object.mediaType == "image/jpeg" ? "JPEG" : "TIFF"
      item.text(type); item.text("8BIM"); item.n(bytes.count, 8); item.n(0, 1)
      let tailBytes = 4 + 8 + 1 // Empty child document ID, asset time and lock.
      let length = item.data.count + bytes.count + tailBytes
      var header = PSDWriter()
      header.n(length, 8)
      header.data.append(item.data)
      chunks.append(header.data)
      chunks.append(bytes)
      chunks.append(Data(count: tailBytes + (4 - length % 4) % 4))
    }
    return chunks
  }
}
private extension Optional where Wrapped == PSDValue {
  var flatList: [PSDValue]? { if case .list(let values) = self { return values }; return nil }
}
