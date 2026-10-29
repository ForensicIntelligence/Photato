import AppKit
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

/// Shared decoding/encoding for native document workflows and local API transfers.
enum DocumentIO {
  enum Format: String, CaseIterable, Sendable {
    case native = "photato", psd, psb, png, jpeg, tiff

    init?(fileExtension: String) {
      switch fileExtension.lowercased() {
      case "pcswift": self = .native
      case "jpg", "jpe": self = .jpeg
      case "tif": self = .tiff
      case let value: self.init(rawValue: value)
      }
    }

    var contentType: UTType {
      switch self {
      case .native: return UTType(exportedAs: "local.photocraft.swift.document")
      case .psd: return UTType("com.adobe.photoshop-image")!
      case .psb: return UTType(importedAs: "com.adobe.photoshop-large-image", conformingTo: .image)
      case .png: return .png
      case .jpeg: return .jpeg
      case .tiff: return .tiff
      }
    }
    var title: String {
      switch self {
      case .native: return "Photato"
      case .psd: return "Photoshop"
      case .psb: return "Large Document Format"
      case .png: return "PNG"
      case .jpeg: return "JPEG"
      case .tiff: return "TIFF"
      }
    }
    var copyDescription: String {
      switch self {
      case .native: return "Keeps all editable Photato content. The open document stays unchanged."
      case .psd, .psb:
        return "Keeps supported layers and masks. Unsupported content must be saved as Photato."
      case .png:
        return "Saves a flattened image with transparency. 32-bit content is converted to 16-bit."
      case .jpeg:
        return "Saves a flattened 8-bit image using the selected quality and format. Transparent areas use the selected matte, white by default."
      case .tiff:
        return "Saves at the current 8-, 16- or 32-bit depth. Select Layers to keep supported editable content, or leave it off for a flattened copy."
      }
    }
    var mediaType: String {
      switch self {
      case .native: return "application/vnd.photato.document"
      case .psd: return "image/vnd.adobe.photoshop"
      case .psb: return "application/x-photoshop"
      case .png: return "image/png"
      case .jpeg: return "image/jpeg"
      case .tiff: return "image/tiff"
      }
    }
  }

  static func isNativeFile(_ url: URL) -> Bool {
    if let format = DocumentOpenFormat.detect(url) { return format == .native }
    return Format(fileExtension: url.pathExtension.lowercased()) == .native
  }

  /// Preserve the actual container, including extensionless or mislabeled files.
  static func sourceFormat(_ url: URL) -> Format? {
    DocumentOpenFormat.detect(url)?.persistenceFormat
  }

  static let maximumUploadBytes = 64 * 1_024 * 1_024
  static let maximumDownloadBytes = 128 * 1_024 * 1_024
  static let readableTypes = [
    "local.photocraft.swift.document", PcraftImport.contentTypeIdentifier, "com.adobe.photoshop-image",
    "com.adobe.photoshop-large-image", "com.adobe.pdf", "public.png",
    "com.apple.quicktime-movie", "public.mpeg-4", "com.apple.m4v-video", "public.camera-raw-image", "com.adobe.raw-image", "public.jpeg", "public.tiff", "public.heic", "com.microsoft.bmp", "com.compuserve.gif",
  ]
  static let uploadTypes =
    Format.allCases.map(\.mediaType) + MovieIO.mediaTypes + RawSourceIO.mediaTypes + [PcraftImport.mediaType, "image/heic", "image/bmp", "image/gif"]
  // The filename-tag fallback also works in SwiftPM/test hosts, whose main
  // bundle does not declare our imported UTI to Launch Services.
  static var pcraftContentType: UTType {
    UTType(filenameExtension: "pcraft", conformingTo: .data)
      ?? UTType(importedAs: PcraftImport.contentTypeIdentifier, conformingTo: .data)
  }
  static var readableContentTypes: [UTType] {
    readableTypes.compactMap { $0 == PcraftImport.contentTypeIdentifier ? pcraftContentType : UTType($0) }
  }

  static func decode(
    _ data: Data, native: Bool, name: String, rasterByteLimit: Int = 1_073_741_824
  ) throws -> CraftDocument {
    try Task.checkCancellation()
    let document: CraftDocument
    if native { document = try NativeArchive.decode(data, rasterByteLimit: rasterByteLimit) }
    else if MovieIO.recognizes(data) { document = try MovieIO.decode(data,name:name,maximumBytes:rasterByteLimit) }
    else if PcraftImport.recognizes(data) {
      document = try PcraftImport.read(data, rasterByteLimit: rasterByteLimit)
    } else if RawSourceIO.recognizes(data) { document = try RawSourceIO.open(data,fileName:name) }
    else if AnimationGIF.recognizes(data) { document = try AnimationGIF.read(data, name: name, rasterByteLimit: rasterByteLimit) }
    else { document = try RasterIO.read(data, name: name) }
    // Native archives also cross the colour-engine boundary here, before sharing/display.
    _ = try ColorManagement.space(for: document)
    return document
  }

  static func read(_ url: URL) throws -> CraftDocument {
    guard url.isFileURL else { throw CraftError.invalid("Choose a local document file.") }
    if DocumentOpenFormat.detect(url) == .pdf {throw CraftError.unsupported("Use File > Open and the Import PDF dialog to choose pages and render settings.")}
    if PcraftImport.recognizes(url) { return try PcraftImport.read(url) }
    if DocumentOpenFormat.detect(url) == .movie { return try MovieIO.read(url) }
    if RawSourceIO.recognizes(url) { return try RawSourceIO.read(url) }
    if !isNativeFile(url) {
      let model = try RasterIO.read(url)
      _ = try ColorManagement.space(for: model)
      return model
    }
    return try readNative(url)
  }
  static func readNative(_ url: URL) throws -> CraftDocument {
    let document = try NativeArchive.read(url)
    _ = try ColorManagement.space(for: document)
    return document
  }

  static func encode(_ document: CraftDocument, format: Format) throws -> Data {
    try encode(document, format: format, options: .init())
  }
  static func encode(_ document: CraftDocument, format: Format,
    options: RasterEncodingOptions) throws -> Data {
    try Task.checkCancellation()
    try options.validate(for: format.contentType)
    switch format {
    case .native: return try NativeArchive.encodeChunked(document)
    case .psd, .psb:
      return try PSDCodec.writeRasterLayers(document,
        compression: options.psdLayerCompression?.codec ?? .zipPrediction,
        format: format == .psd ? .psd : .psb,
        compositeCompression: options.psdCompositeCompression?.codec ?? .raw)
    case .png: return try RasterIO.encoded(document, type: .png, options: options)
    case .jpeg: return try RasterIO.encoded(document, type: .jpeg, options: options)
    case .tiff: return try RasterIO.encoded(document, type: .tiff, options: options)
    }
  }

  @MainActor static func configureOpenPanel(_ panel: NSOpenPanel) {
    panel.allowedContentTypes = readableContentTypes
    panel.allowsOtherFileTypes = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
  }
}
