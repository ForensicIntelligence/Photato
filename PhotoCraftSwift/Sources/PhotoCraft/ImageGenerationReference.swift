import AppKit
import CryptoKit
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

/// Describes the image supplied by Photato, not a provider-confirmed final input.
struct ImageGenerationReferenceRecord: Codable, Equatable, Sendable {
  let version: Int
  let sha256: String
  let byteCount: Int
  let mediaType: String
  let width: Int
  let height: Int
  let previewWidth: Int
  let previewHeight: Int
  // Optional so existing version-1 records retain their exact default encoding.
  var requestedUse: ImageReferenceUse? = nil
  func recording(_ use: ImageReferenceUse) -> Self {
    var result = self; result.requestedUse = use == .inspiration ? nil : use; return result
  }
  func validate() throws {
    guard version == 1, sha256.count == 64,
      sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
      byteCount > 0, byteCount <= ImageGenerationReference.maximumBytes,
      ["image/png", "image/jpeg", "image/tiff", "image/heic"].contains(mediaType),
      width > 0, height > 0, width <= 300000, height <= 300000,
      width <= ImageGenerationReference.maximumPixels / height,
      previewWidth > 0, previewHeight > 0,
      previewWidth <= 2048, previewHeight <= 2048 else {
      throw CraftError.invalid("Invalid image-generation reference record.")
    }
  }
}

struct ImageGenerationReference: Sendable {
  static let maximumBytes = 16 * 1024 * 1024
  static let maximumBase64Characters = ((maximumBytes + 2) / 3) * 4
  static let maximumAPIRequestBytes = maximumBase64Characters + 16384
  static let maximumPixels = 64 * 1024 * 1024
  static let recordKey = "PtRI"
  let id = UUID()
  let record: ImageGenerationReferenceRecord
  let image: CGImage

  static func prepare(_ data: Data) throws -> Self {
    try Task.checkCancellation()
    guard !data.isEmpty, data.count <= maximumBytes,
      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      CGImageSourceGetCount(source) == 1,
      let type = CGImageSourceGetType(source) as String?,
      let mediaType = [UTType.png.identifier: "image/png", UTType.jpeg.identifier: "image/jpeg",
        UTType.tiff.identifier: "image/tiff", UTType.heic.identifier: "image/heic"][type],
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let h = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      let width = Int(exactly: w.doubleValue), let height = Int(exactly: h.doubleValue),
      width > 0, height > 0, width <= 300000, height <= 300000,
      width <= maximumPixels / height else {
      throw CraftError.invalid("Choose one still PNG, JPEG, TIFF or HEIC reference, up to16MiB and64megapixels. Document size limits are independent.")
    }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
      kCGImageSourceShouldCacheImmediately: true]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw CraftError.invalid("The reference image could not be decoded.")
    }
    try Task.checkCancellation()
    let record = ImageGenerationReferenceRecord(version: 1,
      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      byteCount: data.count, mediaType: mediaType, width: width, height: height,
      previewWidth: image.width, previewHeight: image.height)
    try record.validate()
    return .init(record: record, image: image)
  }

  static func read(_ url: URL) throws -> Data {
    guard url.isFileURL else { throw CraftError.invalid("Choose a local reference image.") }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size > 0, size <= maximumBytes else {
      throw CraftError.invalid("Choose a regular local reference image up to16MiB.")
    }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var data = Data()
    while true {
      try Task.checkCancellation()
      let part = try handle.read(upToCount: min(65536, maximumBytes - data.count + 1)) ?? Data()
      if part.isEmpty { break }
      guard part.count <= maximumBytes - data.count else { throw CraftError.invalid("The reference image exceeds16MiB.") }
      data.append(part)
    }
    return data
  }

  static func record(in layer: Layer) throws -> ImageGenerationReferenceRecord? {
    guard let bytes = layer.sourceTags?[recordKey] else { return nil }
    guard bytes.count <= 4096 else { throw CraftError.invalid("Image-reference metadata exceeds its limit.") }
    let record = try JSONDecoder().decode(ImageGenerationReferenceRecord.self, from: bytes)
    try record.validate(); return record
  }
  static func attach(_ record: ImageGenerationReferenceRecord?, to layer: Layer) throws -> Layer {
    guard let record else { return layer }
    try record.validate()
    var result = layer
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    result.sourceTags = result.sourceTags ?? [:]
    result.sourceTags?[recordKey] = try encoder.encode(record)
    return result
  }
}

extension EditorStore {
  func removeImageReference() {
    guard !aiBusy else { return }
    imageReference = nil; imageReferenceUse = .inspiration; aiError = nil
  }
  func chooseImageReference() {
    guard !aiBusy, imageGenerationIntent == .image, let window = NSApp.keyWindow else { return }
    let revision = sessionGeneration, lifecycle = layerPanelGeneration
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
    panel.allowsMultipleSelection = false
    panel.message = "Choose an image to guide generation. The system can replace or reinterpret this visual reference."
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url, let self, self.showAI,
        self.sessionGeneration == revision, self.layerPanelGeneration == lifecycle else { return }
      self.loadImageReference(url)
    }
  }
  func loadImageReference(_ url: URL) {
    guard !aiBusy, imageGenerationIntent == .image, imageGenerationSourceAvailable() else { return }
    let id = UUID(), revision = sessionGeneration, lifecycle = layerPanelGeneration
    let previous = imageReference?.id, prepare = imageReferencePreparation
    imageReferenceImportID = id; aiBusy = true; aiError = nil
    aiTask = Task { [weak self] in
      let worker = Task.detached(priority: .userInitiated) {
        try await prepare(ImageGenerationReference.read(url))
      }
      do {
        let reference = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        guard let self, self.imageReferenceImportID == id else { return }
        defer { self.imageReferenceImportID = nil; self.aiBusy = false; self.aiTask = nil }
        guard self.imageGenerationSourceAvailable(), self.showAI, self.sessionGeneration == revision,
          self.layerPanelGeneration == lifecycle, self.imageGenerationIntent == .image,
          self.imageReference?.id == previous else { self.aiError = "The document or reference changed. The imported reference was not applied."; return }
        self.imageReference = reference
      } catch {
        guard let self, self.imageReferenceImportID == id else { return }
        self.imageReferenceImportID = nil; self.aiBusy = false; self.aiTask = nil
        if !(error is CancellationError) { self.aiError = error.localizedDescription }
      }
    }
  }
}
