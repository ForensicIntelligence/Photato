import AppKit
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

/// Shared decoding/encoding for native document workflows and local API transfers.
enum DocumentIO {
  enum Format: String, CaseIterable, Sendable {
    case native = "photato", psd, png, jpeg, tiff

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
      case .png: return .png
      case .jpeg: return .jpeg
      case .tiff: return .tiff
      }
    }
    var title: String {
      switch self {
      case .native: return "Photato"
      case .psd: return "Photoshop"
      case .png: return "PNG"
      case .jpeg: return "JPEG"
      case .tiff: return "TIFF"
      }
    }
    var copyDescription: String {
      switch self {
      case .native: return "Keeps all editable Photato content. The open document stays unchanged."
      case .psd:
        return "Keeps supported layers and masks. Unsupported content must be saved as Photato."
      case .png:
        return "Saves a flattened image with transparency. 32-bit content is converted to 16-bit."
      case .jpeg:
        return "Saves a flattened 8-bit image at 95% quality, with white behind transparent areas."
      case .tiff:
        return "Saves a flattened image with transparency. 32-bit content is converted to 16-bit."
      }
    }
    var mediaType: String {
      switch self {
      case .native: return "application/vnd.photato.document"
      case .psd: return "image/vnd.adobe.photoshop"
      case .png: return "image/png"
      case .jpeg: return "image/jpeg"
      case .tiff: return "image/tiff"
      }
    }
  }

  static func isNativeFile(_ url: URL) -> Bool {
    Format(fileExtension: url.pathExtension.lowercased()) == .native
  }

  /// Use the actual image container for save-back, including mislabeled files.
  /// ImageIO identifies the source without decoding its pixel data here.
  static func sourceFormat(_ url: URL) -> Format? {
    if isNativeFile(url) { return .native }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let type = CGImageSourceGetType(source)
    else { return nil }
    return Format(typeIdentifier: type as String)
  }

  static let maximumUploadBytes = 64 * 1_024 * 1_024
  static let maximumDownloadBytes = 128 * 1_024 * 1_024
  static let readableTypes = [
    "local.photocraft.swift.document", "com.adobe.photoshop-image", "public.png",
    "public.jpeg", "public.tiff", "public.heic", "com.microsoft.bmp", "com.compuserve.gif",
  ]
  static let uploadTypes =
    Format.allCases.map(\.mediaType) + ["image/heic", "image/bmp", "image/gif"]

  static func decode(
    _ data: Data, native: Bool, name: String, rasterByteLimit: Int = 1_073_741_824
  ) throws -> CraftDocument {
    try Task.checkCancellation()
    return native
      ? try NativeArchive.decode(data, rasterByteLimit: rasterByteLimit)
      : try RasterIO.read(data, name: name)
  }

  static func read(_ url: URL) throws -> CraftDocument {
    guard url.isFileURL else { throw CraftError.invalid("Choose a local document file.") }
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 512 * 1_024 * 1_024 else {
      throw CraftError.invalid("Document exceeds the 512 MiB input limit.")
    }
    return try decode(
      Data(contentsOf: url, options: .mappedIfSafe),
      native: isNativeFile(url),
      name: url.deletingPathExtension().lastPathComponent)
  }

  static func encode(_ document: CraftDocument, format: Format) throws -> Data {
    try Task.checkCancellation()
    switch format {
    case .native: return try NativeArchive.encode(document)
    case .psd: return try PSDCodec.writeRasterLayers(document)
    case .png: return try RasterIO.encoded(document, type: .png)
    case .jpeg: return try RasterIO.encoded(document, type: .jpeg)
    case .tiff: return try RasterIO.encoded(document, type: .tiff)
    }
  }

  @MainActor static func configureOpenPanel(_ panel: NSOpenPanel) {
    panel.allowedContentTypes = readableTypes.compactMap { UTType($0) }
    panel.allowsOtherFileTypes = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
  }
}
