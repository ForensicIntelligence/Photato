import CryptoKit
import Foundation

/// Embedded file plus source-space pixels held by Layer.content. Placement belongs
/// to the layer, so transforms never overwrite these source pixels.
public struct SmartObject: Equatable, Sendable, Codable {
  public static let maximumSourceBytes = 64 * 1_024 * 1_024
  public var sourceID: UUID
  public var fileName: String
  public var mediaType: String
  public var data: Data
  public var width: Int
  public var height: Int
  public var stackMode: ImageStackMode?
  public var rawDevelopment: RawDevelopment?
  public var pdfSource: PDFSmartObjectSource?
  public var resolution: Double
  public var revision: String {
    var bytes = data
    if let stackMode { bytes.append(Data(("\0stack:" + stackMode.rawValue).utf8)) }
    if let rawDevelopment { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; bytes.append((try? encoder.encode(rawDevelopment)) ?? Data()) }
    if let pdfSource { let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; bytes.append(Data("\0pdf-size:\(width)x\(height)@\(resolution)\0pdf:".utf8)); bytes.append((try? encoder.encode(pdfSource)) ?? Data()) }
    return SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
  }
  public init(sourceID: UUID = UUID(), fileName: String, mediaType: String, data: Data,
    width: Int, height: Int, resolution: Double = 72, rawDevelopment: RawDevelopment? = nil, stackMode: ImageStackMode? = nil, pdfSource: PDFSmartObjectSource? = nil) throws {
    self.pdfSource = pdfSource
    self.stackMode = stackMode
    self.rawDevelopment = rawDevelopment
    self.sourceID = sourceID; self.fileName = fileName; self.mediaType = mediaType
    self.data = data; self.width = width; self.height = height; self.resolution = resolution
    try validate()
  }
  public func sharesSource(with other: SmartObject) -> Bool {
    var a = self, b = other; a.stackMode = nil; b.stackMode = nil; return a == b
  }
  public func validate() throws {
    guard !data.isEmpty, data.count <= Self.maximumSourceBytes,
      !fileName.isEmpty, fileName.utf8.count <= 1024,
      !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains("\0"),
      ["application/vnd.photato.document", "image/vnd.adobe.photoshop", "application/x-photoshop",
        "application/pdf", "image/x-camera-raw", "image/x-adobe-dng", "image/png", "image/jpeg", "image/tiff", "image/heic", "image/bmp", "image/gif"].contains(mediaType),
      resolution.isFinite, (1...100_000).contains(resolution) else {
      throw CraftError.invalid("Invalid embedded Smart Object source or 64 MiB source limit exceeded.")
    }
    guard ["image/x-camera-raw","image/x-adobe-dng"].contains(mediaType) == (rawDevelopment != nil) else { throw CraftError.invalid("RAW sources require their development settings.") }
    guard stackMode == nil || rawDevelopment == nil else { throw CraftError.invalid("Developed RAW sources must be converted into a layered Smart Object before stacking.") }
    guard (mediaType == "application/pdf") == (pdfSource != nil), pdfSource == nil || stackMode == nil else { throw CraftError.invalid("PDF Smart Objects require page metadata and cannot use image-stack modes.") }
    try pdfSource?.validate()
    try rawDevelopment?.validate()
    _ = try Surface(width: width, height: height)
  }
  private enum CodingKeys: CodingKey { case sourceID, fileName, mediaType, data, sourceBlob, width, height, resolution, rawDevelopment, stackMode, pdfSource }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sourceID = try c.decode(UUID.self, forKey: .sourceID)
    fileName = try c.decode(String.self, forKey: .fileName)
    mediaType = try c.decode(String.self, forKey: .mediaType)
    width = try c.decode(Int.self, forKey: .width); height = try c.decode(Int.self, forKey: .height)
    resolution = try c.decode(Double.self, forKey: .resolution)
    pdfSource = try c.decodeIfPresent(PDFSmartObjectSource.self, forKey: .pdfSource)
    stackMode = try c.decodeIfPresent(ImageStackMode.self, forKey: .stackMode)
    rawDevelopment = try c.decodeIfPresent(RawDevelopment.self, forKey: .rawDevelopment)
    if c.contains(.sourceBlob) {
      guard !c.contains(.data), let context = decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding else {
        throw CraftError.invalid("Embedded source blobs require their owned archive context.")
      }
      data = try context.bytes(c.decode(String.self, forKey: .sourceBlob), maximumBytes: Self.maximumSourceBytes)
    } else { data = try c.decode(Data.self, forKey: .data) }
    try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?
      .reserve(tiles: (data.count + TileArchive.byteCount - 1) / TileArchive.byteCount)
    try validate()
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(sourceID, forKey: .sourceID); try c.encode(fileName, forKey: .fileName)
    try c.encode(mediaType, forKey: .mediaType); try c.encode(width, forKey: .width)
    try c.encode(height, forKey: .height); try c.encode(resolution, forKey: .resolution)
    try c.encodeIfPresent(rawDevelopment,forKey:.rawDevelopment)
    try c.encodeIfPresent(stackMode,forKey:.stackMode)
    try c.encodeIfPresent(pdfSource,forKey:.pdfSource)
    if let context = encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {
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
      try updated.validate()
      guard updated.stackMode == nil || instancePixels[layers[i].id] != nil else { throw CraftError.invalid("Missing rendered image stack cache.") }
      updated.sourceID = allInstances ? old.sourceID : source.sourceID
      let oldMaskTransform = layers[i].maskCoordinateTransform
      if let mesh = layers[i].warp?.mesh {
        let scale = Transform2D.scale(Double(source.width)/Double(layers[i].smartObject!.width), Double(source.height)/Double(layers[i].smartObject!.height))
        layers[i].warp?.mesh?.points = mesh.points.map { $0.transformed(scale) }
      }
      if preserveSize {
        let full = layers[i].coordinateTransform * .scale(Double(layers[i].smartObject!.width) / Double(source.width), Double(layers[i].smartObject!.height) / Double(source.height))
        layers[i].x = Int(floor(full.tx)); layers[i].y = Int(floor(full.ty))
        layers[i].affine = .translation(-Double(layers[i].x), -Double(layers[i].y)) * full
      }
      if layers[i].mask != nil {
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
