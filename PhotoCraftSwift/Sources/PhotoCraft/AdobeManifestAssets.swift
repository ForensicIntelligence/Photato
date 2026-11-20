import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

struct AdobeManifestThumbnail: Sendable {
  static let maximumEdge = 256
  let depth: Int
  let trim: Bool
  let type: UTType
  let mediaType: String
  let encoding: RasterEncodingOptions

  init(options: Any?, depth: Int, trim: Bool) throws {
    self.depth = depth
    self.trim = trim
    let fields = try options.map {
      try AdobeActionsRequest.Object($0, at: "exportOptions", allowed: ["mediaType", "quality", "compression", "scan"])
    }
    mediaType = try fields?.string("mediaType") ?? "image/jpeg"
    var encoding = RasterEncodingOptions()
    switch mediaType {
    case "image/jpeg":
      type = .jpeg
      guard fields?.fields["compression"] == nil else { throw AdobeAPIError.invalid("PNG compression requires image/png.") }
      if let fields, fields.fields["quality"] != nil {
        guard let index = DocumentEncodingOptions.jpegQualities.firstIndex(of: try fields.string("quality")) else {
          throw AdobeAPIError.invalid("Invalid JPEG thumbnail quality.")
        }
        encoding.jpegQuality = index * 2
      }
      if let fields, fields.fields["scan"] != nil {
        let scan = try fields.object("scan", allowed: ["type", "optimized", "scans"])
        let mode = try scan.fields["type"] == nil ? "baseline" : scan.string("type")
        switch mode {
        case "baseline":
          guard scan.fields["scans"] == nil else { throw AdobeAPIError.invalid("JPEG scan count requires progressive mode.") }
          encoding.jpegFormat = try scan.optionalBool("optimized") == true ? .optimized : .baseline
        case "progressive":
          guard scan.fields["optimized"] == nil else { throw AdobeAPIError.invalid("JPEG optimization requires baseline mode.") }
          if scan.fields["scans"] != nil {
            _ = try scan.integer("scans", range: 3...5)
            throw AdobeAPIError.unsupported("The native JPEG encoder chooses the progressive scan count.")
          }
          encoding.jpegFormat = .progressive
        default: throw AdobeAPIError.invalid("Invalid JPEG scan type.")
        }
      }
    case "image/png":
      type = .png
      guard fields?.fields["quality"] == nil, fields?.fields["scan"] == nil else {
        throw AdobeAPIError.invalid("JPEG quality and scan settings require image/jpeg.")
      }
      if let fields, fields.fields["compression"] != nil {
        guard let index = DocumentEncodingOptions.pngLevels.firstIndex(of: try fields.string("compression")) else {
          throw AdobeAPIError.invalid("Invalid PNG thumbnail compression.")
        }
        encoding.pngCompression = index
      }
    default: throw AdobeAPIError.invalid("Thumbnail exportOptions.mediaType must be image/jpeg or image/png.")
    }
    self.encoding = encoding
  }

  func encoded(_ layer: Layer, in document: CraftDocument) throws -> Data {
    if case .adjustment = layer.content {
      return try blank(width: document.width, height: document.height)
    }
    let isolated = try ImageAssetSelection.document(document, ids: [layer.id],
      crop: layer.artboard == nil ? .documentBounds : .layerBounds)
    let rendering = try Renderer.composite(isolated)
    guard let occupied = try rendering.contentBounds() else {
      return try blank(width: isolated.width, height: isolated.height)
    }
    let bounds = IntRect(x: 0, y: 0, width: rendering.width, height: rendering.height)
    let surface = try trim && occupied != bounds ? rendering.cropped(to: occupied) : rendering
    let (width, height) = thumbnailSize(width: surface.width, height: surface.height)
    let fitted = try surface.width == width && surface.height == height ? surface
      : Renderer.resize(surface, width: width, height: height)
    return try RasterIO.encoded(fitted, type: type, outputDepth: .u8, workingDocument: isolated, options: encoding)
  }

  private func blank(width: Int, height: Int) throws -> Data {
    let (width, height) = thumbnailSize(width: width, height: height)
    let surface = try Surface(width: width, height: height, fill: .white)
    return try RasterIO.encoded(surface, type: type, options: encoding)
  }

  private func thumbnailSize(width: Int, height: Int) -> (Int, Int) {
    let scale = min(1, Double(Self.maximumEdge) / Double(max(width, height)))
    return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
  }
}

struct AdobeManifestAssets {
  struct Links {
    var thumbnail: [String: String]?
    var extracted: [String: String]?
  }
  private struct Original: Hashable {
    let sourceID: UUID
    let fingerprint: String
  }

  let baseURL: URL
  let preview: AdobeManifestThumbnail?
  let extract: Bool
  private var originals: [Original: [String: String]] = [:]
  private(set) var attachments: [UUID: AdobeActionAssets.Attachment] = [:]
  private(set) var byteCount = 0

  init(baseURL: URL, preview: AdobeManifestThumbnail?, extract: Bool) {
    self.baseURL = baseURL
    self.preview = preview
    self.extract = extract
  }

  mutating func links(for layer: Layer, depth: Int, document: CraftDocument) throws -> Links {
    var result = Links()
    if let preview, preview.depth == 0 || depth <= preview.depth {
      let bytes = try preview.encoded(layer, in: document)
      result.thumbnail = try host(bytes, mediaType: preview.mediaType)
    }
    if extract, let object = layer.smartObject, object.linkedSource == nil, !object.data.isEmpty {
      let key = Original(sourceID: object.sourceID, fingerprint: object.dataFingerprint)
      if originals[key] == nil { originals[key] = try host(object.data, mediaType: "application/octet-stream") }
      result.extracted = originals[key]
    }
    return result
  }

  private mutating func host(_ bytes: Data, mediaType: String) throws -> [String: String] {
    try Task.checkCancellation()
    guard bytes.count <= AdobeActionAssets.maximumResourceBytes,
          bytes.count <= AdobeActionAssets.maximumOutputBytes - byteCount else {
      throw AdobeAPIError.invalid("Manifest assets exceed the local resource or aggregate output limit.")
    }
    let id = UUID()
    byteCount += bytes.count
    attachments[id] = .init(mediaType: mediaType, data: bytes)
    return ["mediaType": mediaType, "url": baseURL.appendingPathComponent(id.uuidString).absoluteString]
  }
}
