import CryptoKit
import Foundation

/// Embedded file plus source-space pixels held by Layer.content. Placement belongs
/// to the layer, so transforms never overwrite these source pixels.
public struct SmartObject: Equatable, Sendable, Codable {
  public static let maximumSourceBytes = 64 * 1_024 * 1_024
  public static let maximumArchive95SourceBytes = 256 * 1_024 * 1_024
  public static let maximumDocumentSourceBytes = 512 * 1_024 * 1_024
  public static let maximumFileBackedSourceBytes = 2 * 1_024 * 1_024 * 1_024
  public static let largeSourceArchiveVersion = 95
  public static let fileBackedArchiveVersion = 96
  public static let streamingSourceArchiveVersion = 97

  public static func photoshopSourceVersion(_ header: Data) -> Int? {
    guard header.count >= 6, header.prefix(4).elementsEqual("8BPS".utf8),
      header[header.startIndex + 4] == 0 else { return nil }
    let version = Int(header[header.startIndex + 5])
    return (1...2).contains(version) ? version : nil
  }

  public static func maximumEmbeddedBytes(forHeader header: Data) -> Int {
    if photoshopSourceVersion(header) != nil || header.starts(with: "PHOTATO\0".utf8) {
      return maximumDocumentSourceBytes
    }
    return maximumSourceBytes
  }
  public static func maximumLocalEmbeddedBytes(forHeader header: Data) -> Int {
    maximumEmbeddedBytes(forHeader: header) == maximumSourceBytes
      ? maximumSourceBytes : maximumFileBackedSourceBytes
  }
  public static func maximumEmbeddedBytes(for source: EmbeddedSourceBytes) -> Int {
    source.isFileBacked ? maximumLocalEmbeddedBytes(forHeader: source.data) : maximumEmbeddedBytes(forHeader: source.data)
  }
  private static func isLayeredDocument(_ mediaType: String) -> Bool {
    ["application/vnd.photato.document", "image/vnd.adobe.photoshop", "application/x-photoshop"].contains(mediaType)
  }
  public var sourceID: UUID
  public var fileName: String
  public var mediaType: String
  private var original: EmbeddedSourceBytes
  public var sourceBytes: EmbeddedSourceBytes { original }
  public var data: Data {
    get { original.data }
    set {
      original = .memory(newValue)
      dataDigest = newValue.count <= Self.maximumDocumentSourceBytes ? Self.fingerprint(newValue) : ""
    }
  }
  private var dataDigest=""
  public var dataFingerprint:String{dataDigest.isEmpty ? Self.fingerprint(data):dataDigest}
  private static func fingerprint(_ value:Data)->String{SHA256.hash(data:value).map{String(format:"%02x",$0)}.joined()}
  mutating func retainVerifiedOriginal(_ source: EmbeddedSourceBytes, digest: String) {
    original = source
    dataDigest = digest
  }
  public var width: Int
  public var height: Int
  public var stackMode: ImageStackMode?
  public var layerComps: SmartObjectLayerComps?
  public var rawDevelopment: RawDevelopment?
  public var pdfSource: PDFSmartObjectSource?
  public var linkedSource: LinkedSmartObjectSource?
  public var resolution: Double
  public var revision: String {
    if let id = layerComps?.selectedID {
      var source = self; source.layerComps?.selectedID = nil
      return Self.fingerprint(Data((source.revision + "\0layer-comp:" + id.uuidString).utf8))
    }
    if linkedSource==nil,stackMode==nil,rawDevelopment==nil,pdfSource==nil,layerComps?.selectedID==nil{return dataFingerprint}
    var bytes:Data
    if let linkedSource {
      bytes=Data(("linked:"+linkedSource.kind.rawValue+":"+linkedSource.reference+":"+(linkedSource.contentHash ?? "unverified")+":\(linkedSource.byteLength)").utf8)
    }else{bytes=data}
    if let stackMode { bytes.append(Data(("\0stack:" + stackMode.rawValue).utf8)) }
    if let rawDevelopment { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; bytes.append((try? encoder.encode(rawDevelopment)) ?? Data()) }
    if let pdfSource { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; bytes.append(Data("\0pdf-size:\(width)x\(height)@\(resolution)\0pdf:".utf8)); bytes.append((try? encoder.encode(pdfSource)) ?? Data()) }
    return SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
  }
  public init(sourceID: UUID = UUID(), fileName: String, mediaType: String, data: Data,
    width: Int, height: Int, resolution: Double = 72, rawDevelopment: RawDevelopment? = nil, stackMode: ImageStackMode? = nil, pdfSource: PDFSmartObjectSource? = nil, linkedSource: LinkedSmartObjectSource? = nil) throws {
    try self.init(sourceID: sourceID, fileName: fileName, mediaType: mediaType, source: .memory(data),
      width: width, height: height, resolution: resolution, rawDevelopment: rawDevelopment,
      stackMode: stackMode, pdfSource: pdfSource, linkedSource: linkedSource)
  }
  public init(sourceID: UUID = UUID(), fileName: String, mediaType: String, source: EmbeddedSourceBytes,
    width: Int, height: Int, resolution: Double = 72, rawDevelopment: RawDevelopment? = nil,
    stackMode: ImageStackMode? = nil, pdfSource: PDFSmartObjectSource? = nil, linkedSource: LinkedSmartObjectSource? = nil) throws {
    self.linkedSource = linkedSource
    self.pdfSource = pdfSource
    self.stackMode = stackMode
    self.rawDevelopment = rawDevelopment
    self.sourceID = sourceID; self.fileName = fileName; self.mediaType = mediaType
    original = source; self.width = width; self.height = height; self.resolution = resolution
    try validate();dataDigest=original.fingerprint
  }
  /// Cached fingerprints keep source appearance checks independent of file size.
  /// They are derived locally and never trusted from an archive.
  func matchesAppearanceIdentity(_ b:SmartObject)->Bool {
    fileName==b.fileName && mediaType==b.mediaType && width==b.width && height==b.height
      && resolution==b.resolution && stackMode==b.stackMode && rawDevelopment==b.rawDevelopment
      && pdfSource==b.pdfSource && linkedSource==b.linkedSource && layerComps==b.layerComps && (linkedSource != nil || dataFingerprint==b.dataFingerprint)
  }
  public static func ==(a:SmartObject,b:SmartObject)->Bool {
    a.sourceID==b.sourceID && a.fileName==b.fileName && a.mediaType==b.mediaType && a.width==b.width && a.height==b.height
      && a.resolution==b.resolution && a.stackMode==b.stackMode && a.rawDevelopment==b.rawDevelopment
      && a.pdfSource==b.pdfSource && a.linkedSource==b.linkedSource && a.layerComps==b.layerComps
      && (a.linkedSource != nil || a.data==b.data)
  }
  public func sharesSource(with other: SmartObject) -> Bool {
    var a = self, b = other; a.stackMode = nil; b.stackMode = nil; a.layerComps = nil; b.layerComps = nil; return a == b
  }
  public func validate() throws {
    let canRetainLargeSource = (linkedSource == nil || linkedSource?.kind == .file && original.isFileBacked) && (
      (mediaType == "application/vnd.photato.document" && data.starts(with: "PHOTATO\0".utf8))
        || (mediaType == "image/vnd.adobe.photoshop" && Self.photoshopSourceVersion(data) == 1)
        || (mediaType == "application/x-photoshop" && Self.photoshopSourceVersion(data) == 2))
    guard (!data.isEmpty || linkedSource != nil),
      data.count <= (canRetainLargeSource ? Self.maximumEmbeddedBytes(for: original) : Self.maximumSourceBytes),
      !fileName.isEmpty, fileName.utf8.count <= 1024,
      !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("\0"),
      (["application/vnd.photato.document", "application/vnd.photocraft.project", "image/vnd.adobe.photoshop", "application/x-photoshop",
        "application/pdf", "image/x-camera-raw", "image/x-adobe-dng", "image/png", "image/jpeg", "image/tiff", "image/heic", "image/bmp", "image/gif"].contains(mediaType) || (mediaType=="application/octet-stream" && linkedSource != nil)),
      resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Invalid embedded Smart Object source or source size limit exceeded.")
    }
    guard ["image/x-camera-raw","image/x-adobe-dng"].contains(mediaType) == (rawDevelopment != nil) else { throw CraftError.invalid("RAW sources require their development settings.") }
    guard stackMode == nil || rawDevelopment == nil else { throw CraftError.invalid("Developed RAW sources must be converted into a layered Smart Object before stacking.") }
    guard (mediaType == "application/pdf") == (pdfSource != nil), pdfSource == nil || stackMode == nil else { throw CraftError.invalid("PDF Smart Objects require page metadata and cannot use image-stack modes.") }
    try layerComps?.validate()
    guard layerComps == nil || (rawDevelopment == nil && pdfSource == nil) else { throw CraftError.invalid("RAW/PDF sources do not contain native Layer Comps.") }
    try linkedSource?.validate()
    try pdfSource?.validate()
    try rawDevelopment?.validate()
    _ = try Surface(width: width, height: height)
  }
  private enum CodingKeys: CodingKey { case sourceID, fileName, mediaType, data, sourceBlob, width, height, resolution, rawDevelopment, stackMode, pdfSource, linkedSource, layerComps }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sourceID = try c.decode(UUID.self, forKey: .sourceID)
    fileName = try c.decode(String.self, forKey: .fileName)
    mediaType = try c.decode(String.self, forKey: .mediaType)
    width = try c.decode(Int.self, forKey: .width); height = try c.decode(Int.self, forKey: .height)
    resolution = try c.decode(Double.self, forKey: .resolution)
    pdfSource = try c.decodeIfPresent(PDFSmartObjectSource.self, forKey: .pdfSource)
    linkedSource = try c.decodeIfPresent(LinkedSmartObjectSource.self, forKey: .linkedSource)
    layerComps = try c.decodeIfPresent(SmartObjectLayerComps.self, forKey: .layerComps)
    stackMode = try c.decodeIfPresent(ImageStackMode.self, forKey: .stackMode)
    rawDevelopment = try c.decodeIfPresent(RawDevelopment.self, forKey: .rawDevelopment)
    if linkedSource != nil {
      guard !c.contains(.sourceBlob),!c.contains(.data) else{throw CraftError.invalid("Linked native sources must not archive their original file bytes.")}
      original = .memory(Data())
    } else if c.contains(.sourceBlob) {
      guard !c.contains(.data), let context = decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding else {
        throw CraftError.invalid("Embedded source blobs require their owned archive context.")
      }
      let isLayeredDocument = Self.isLayeredDocument(mediaType)
      let identifier = try c.decode(String.self, forKey: .sourceBlob)
      if isLayeredDocument, let paged = context as? any EmbeddedSourceBlobDecoding {
        original = try paged.embeddedSourceBytes(identifier)
      } else {
        original = .memory(try context.bytes(identifier,
          maximumBytes: isLayeredDocument ? Self.maximumDocumentSourceBytes : Self.maximumSourceBytes))
      }
    } else { original = .memory(try c.decode(Data.self, forKey: .data)) }
    if !original.isFileBacked {
      try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?
        .reserve(tiles: (data.count + TileArchive.byteCount - 1) / TileArchive.byteCount)
    }
    try validate();dataDigest=original.fingerprint
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(sourceID, forKey: .sourceID); try c.encode(fileName, forKey: .fileName)
    try c.encode(mediaType, forKey: .mediaType); try c.encode(width, forKey: .width)
    try c.encode(height, forKey: .height); try c.encode(resolution, forKey: .resolution)
    try c.encodeIfPresent(rawDevelopment,forKey:.rawDevelopment)
    try c.encodeIfPresent(stackMode,forKey:.stackMode)
    try c.encodeIfPresent(layerComps,forKey:.layerComps)
    try c.encodeIfPresent(pdfSource,forKey:.pdfSource)
    try c.encodeIfPresent(linkedSource,forKey:.linkedSource)
    if linkedSource != nil {return}
    if Self.isLayeredDocument(mediaType), case .file(let source) = original,
      let context = encoder.userInfo[.historyTileEncoder] as? any EmbeddedSourceBlobEncoding {
      try c.encode(context.retainEmbeddedSource(source, digest: dataFingerprint), forKey: .sourceBlob)
    } else if let context = encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {
      try c.encode(context.storeBytes(data), forKey: .sourceBlob)
    } else { try c.encode(data, forKey: .data) }
  }
}

extension Layer {
  public var kindLabel: String { smartObject == nil ? content.label : "Smart Object" }
}

extension CraftDocument {
  public var requiresSmartObjectArchive: Bool { layers.contains { $0.smartObject != nil } }
  mutating func embedSmartObject(replacing selected: Set<UUID>, with layer: Layer) throws {
    guard !selected.isEmpty, selected.isSubset(of: Set(layers.map(\.id))), layer.smartObject != nil else {
      throw CraftError.invalid("Select layers to convert to a Smart Object.")
    }
    let roots = layers.filter { selected.contains($0.id) && Set(ancestors(of: $0.id).map(\.id)).isDisjoint(with: selected) }
    guard let first = roots.first, roots.allSatisfy({ $0.parentID == first.parentID }) else {
      throw CraftError.invalid("Select layers in the same group.")
    }
    let members = roots.reduce(into: Set<UUID>()) { $0.formUnion(subtreeIDs($1.id)) }
    guard members.allSatisfy({ !isLocked($0) }) else { throw CraftError.invalid("Unlock the selected layers and their groups.") }
    let upper = layers.lastIndex { members.contains($0.id) }!
    let insertion = layers[..<upper].filter { !members.contains($0.id) }.count
    layers.removeAll { members.contains($0.id) }
    var replacement = layer; replacement.parentID = first.parentID
    let links=Set(roots.compactMap(\.linkID));if links.count==1,roots.allSatisfy({$0.linkID != nil}){replacement.linkID=links.first;replacement.linkDisabled=roots.allSatisfy{$0.linkDisabled == true} ? true:nil;if let tag=first.sourceTags?["PhLG"]{if replacement.sourceTags==nil{replacement.sourceTags=[:]};replacement.sourceTags?["PhLG"]=tag}}
    layers.insert(replacement, at: insertion); activeLayerID = replacement.id
  }
  mutating func replaceSmartObject(_ id: UUID, source: SmartObject, pixels: Surface,
    preserveSize: Bool, allInstances: Bool, instancePixels: [UUID: Surface] = [:]) throws {
    guard let original = layers.first(where: { $0.id == id }), let old = original.smartObject else {
      throw CraftError.invalid("Select an embedded Smart Object.")
    }
    let indices = layers.indices.filter { layers[$0].id == id || (allInstances && layers[$0].smartObject?.sourceID == old.sourceID) }
    guard indices.allSatisfy({ !isImageLocked(layers[$0].id) }) else {
      throw CraftError.invalid("Unlock every affected Smart Object instance before replacing its content.")
    }
    for i in indices {
      var updated = source
      updated.stackMode = layers[i].smartObject?.stackMode
      if let selected = layers[i].smartObject?.layerComps?.selectedID {
        guard updated.layerComps?.entries.contains(where: { $0.id == selected }) == true, instancePixels[layers[i].id] != nil else { throw CraftError.invalid("A selected source Layer Comp is missing or was not rendered. Choose Last Document State before replacing it.") }
      }
      updated.layerComps?.selectedID = layers[i].smartObject?.layerComps?.selectedID
      try updated.validate()
      guard updated.stackMode == nil || instancePixels[layers[i].id] != nil else { throw CraftError.invalid("Missing rendered image stack cache.") }
      updated.sourceID = allInstances ? old.sourceID : source.sourceID
      let oldCoordinateTransform = layers[i].coordinateTransform
      let oldMaskTransform = layers[i].maskCoordinateTransform
      if let preview=try layers[i].linkedSmartObjectPreview() {
        if let warp = preview.warp { layers[i].warp = warp }
        if let projection = preview.projectiveSourceToCache {
          layers[i].sourceProjection = projection
        } else {
          let full = oldCoordinateTransform * preview.sourceToCache
          layers[i].x = Int(floor(full.tx)); layers[i].y = Int(floor(full.ty))
          layers[i].affine = .translation(-Double(layers[i].x), -Double(layers[i].y)) * full
        }
        try layers[i].setLinkedSmartObjectPreview(nil)
      }
      let scale = Transform2D.scale(Double(source.width)/Double(layers[i].smartObject!.width), Double(source.height)/Double(layers[i].smartObject!.height))
      if let mesh = layers[i].warp?.mesh {
        layers[i].warp?.mesh?.points = mesh.points.map { $0.transformed(scale) }
      }
      if let cylinder = layers[i].warp?.cylinder, scale != .identity {
        layers[i].warp?.cylinder = cylinder.scaled(x: scale.a, y: scale.d)
      }
      if let frame = layers[i].warp?.sourceBounds {
        layers[i].warp?.sourceBounds = .init(x:frame.x*scale.a,y:frame.y*scale.d,width:frame.width*scale.a,height:frame.height*scale.d)
      }
      if preserveSize {
        if let projection=layers[i].sourceProjection {
          if scale != .identity {
            layers[i].sourceProjection = try projection.preceded(by: scale.inverted())
          }
        } else {
          let full = layers[i].coordinateTransform * (try scale.inverted())
          layers[i].x = Int(floor(full.tx)); layers[i].y = Int(floor(full.ty))
          layers[i].affine = .translation(-Double(layers[i].x), -Double(layers[i].y)) * full
        }
      }
      if layers[i].mask != nil, layers[i].coordinateTransform != oldCoordinateTransform {
        var properties = layers[i].effectiveMaskProperties
        properties.transform = try layers[i].coordinateTransform.inverted() * oldMaskTransform
        layers[i].maskProperties = properties
      }
      layers[i].smartObject = updated; layers[i].content = .raster(instancePixels[layers[i].id] ?? pixels)
      layers[i].sourceTags?.removeValue(forKey: "SoLd"); layers[i].sourceTags?.removeValue(forKey: "SoLE")
      layers[i].sourceTags?.removeValue(forKey: "PlLd")
    }
  }
}
