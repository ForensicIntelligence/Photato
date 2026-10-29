import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Immutable staging output held through AppKit's coordinated save. The file is
/// private to this operation; ownership automatically removes it on every exit.
enum PreparedDocumentOutput: Sendable {
  case data(Data)
  case file(PreparedDocumentFile)
  var count: Int {
    switch self {
    case .data(let bytes): return bytes.count
    case .file(let file): return file.count
    }
  }
  func write(to url: URL, destinationHidden: Bool? = nil) throws {
    try Task.checkCancellation()
    switch self {
    case .data(let bytes):
      let output = try AtomicFileWriter(to: url, maximumBytes: bytes.count,
        destinationHidden: destinationHidden)
      defer { output.discard() }
      try output.append(bytes)
      try output.commit()
    case .file(let file):
      let source = try FileHandle(forReadingFrom: file.url)
      defer { try? source.close() }
      let output = try AtomicFileWriter(to: url, destinationHidden: destinationHidden)
      defer { output.discard() }
      while let bytes = try source.read(upToCount: AtomicFileWriter.chunkBytes), !bytes.isEmpty {
        try output.append(bytes)
      }
      guard output.count == file.count else {
        throw CraftError.invalid("The prepared document file changed before saving.")
      }
      try output.commit()
    }
  }
}

final class PreparedDocumentFile: Sendable {
  let directory: URL
  let url: URL
  let count: Int
  init(_ model: CraftDocument, format: DocumentIO.Format,
    options: RasterEncodingOptions = .init()) throws {
    try options.validate(for: format.contentType)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("photato-output-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    var complete = false
    defer { if !complete { try? FileManager.default.removeItem(at: directory) } }
    let url = directory.appendingPathComponent("document")
    switch format {
    case .native: try NativeArchive.write(model, to: url)
    case .psd, .psb:
      try PSDCodec.writeRasterLayers(model, to: url,
        compression: options.psdLayerCompression?.codec ?? .zipPrediction,
        format: format == .psd ? .psd : .psb,
        compositeCompression: options.psdCompositeCompression?.codec ?? .raw)
    default: throw CraftError.unsupported("This format does not use staged native output.")
    }
    self.directory = directory
    self.url = url
    count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    complete = true
  }
  deinit { try? FileManager.default.removeItem(at: directory) }
}

extension DocumentIO {
  typealias Encoder = @Sendable (CraftDocument, Format) throws -> Data
  static func prepareOutput(
    _ document: CraftDocument, format: Format, persistence: Bool,
    options: RasterEncodingOptions = .init(), encoder: Encoder? = nil
  ) throws -> PreparedDocumentOutput {
    try Task.checkCancellation()
    let options = persistence ? persistenceOptions(options, format: format, document: document) : options
    try options.validate(for: format.contentType)
    if let encoder { return .data(try encoder(document, format)) }
    if persistence, let issue = persistenceIssue(document, format: format, options: options) {
      throw CraftError.unsupported(issue)
    }
    if format == .native || format == .psd || format == .psb {
      return .file(try PreparedDocumentFile(document, format: format, options: options))
    }
    return .data(try encode(document, format: format, options: options))
  }
}
