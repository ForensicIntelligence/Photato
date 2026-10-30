import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct ActionBatchSource: Sendable, Identifiable {
  let id: UUID
  let name: String
  let document: CraftDocument?
  let url: URL?
  init(id: UUID,name: String,document: CraftDocument?,url: URL?) {self.id=id;self.name=name;self.document=document;self.url=url}
  init(document: CraftDocument) { id = UUID(); name = document.name; self.document = document; url = nil }
  init(url: URL) { id = UUID(); name = url.deletingPathExtension().lastPathComponent; document = nil; self.url = url }
}
struct ActionBatchResult: Identifiable, Sendable {
  let id: UUID
  let source: String
  let output: String?
  let error: String?
  let cancelled: Bool
  var json: [String: Any] { ["source": source, "output": output as Any? ?? NSNull(), "error": error as Any? ?? NSNull(), "cancelled": cancelled] }
}
enum ActionBatch {
  static func outputName(_ source: String, index: Int, suffix: String, format: DocumentIO.Format) throws -> String {
    guard suffix.utf8.count <= 64, !suffix.contains("/"), !suffix.contains(":"), !suffix.contains("\\"), !suffix.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw CraftError.invalid("Enter a suffix without path separators (up to 64 bytes).") }
    let name = String(source.map { "/:\\".contains($0) || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? "_" : $0 }.prefix(60))
    return String(format: "%04d-", index + 1) + (name.isEmpty ? "Untitled" : name) + suffix + "." + format.rawValue
  }
  /// Prepare each source independently. Publication is atomic, creates a new file,
  /// and refuses existing destinations (including symbolic links).
  @MainActor static func run(sources: [ActionBatchSource], action: RecordedAction,
    destination: URL, format: DocumentIO.Format, options: RasterEncodingOptions = .init(),
    suffix: String = "-processed", stopOnError: Bool = false, clipboard: ClipboardContent? = nil,
    validateClipboard: @escaping @Sendable (ClipboardContent) throws -> Void = { _ in },
    validateOutput: @escaping @Sendable (CraftDocument) throws -> Void = { _ in },
    validatePublication: () throws -> Void = {},
    progress: ([ActionBatchResult]) -> Void = { _ in }) async throws -> [ActionBatchResult] {
    try action.validate()
    guard (1...256).contains(sources.count), destination.isFileURL,
      try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CraftError.invalid("Choose 1–256 sources and an output folder.") }
    _ = try outputName("test", index: 0, suffix: suffix, format: format)
    let masterWorker = Task.detached(priority: .userInitiated) { () throws -> [(UUID, CraftDocument)] in
      guard action.usesMasterPalette || action.usesExternalRetouchSources else { return [] }
      var documents: [(UUID, CraftDocument)] = [], pixels = 0, bytes = 0
      for source in sources {
        try Task.checkCancellation()
        let document: CraftDocument
        if let snapshot = source.document { document = snapshot }
        else if let url = source.url { document = try DocumentIO.read(url) }
        else { throw CraftError.invalid("Missing batch source.") }
        if !action.usesExternalRetouchSources && !(document.depth == .u8 && [.rgb, .grayscale].contains(document.colorMode)) { continue }
        try validateOutput(document)
        pixels += document.width * document.height; bytes += document.estimatedBytes
        let maximumPixels = action.usesMasterPalette ? PaletteQuantization.maximumPixels : 40_000_000
        guard pixels <= maximumPixels, bytes <= 256 * 1024 * 1024 else { throw CraftError.invalid("Action sampling sources exceed the batch pixel or256MiB limit.") }
        documents.append((source.id, document))
      }
      return documents
    }
    let masters = try await withTaskCancellationHandler { try await masterWorker.value } onCancel: { masterWorker.cancel() }
    var results: [ActionBatchResult] = []
    var stopped = false
    for (index, source) in sources.enumerated() {
      if Task.isCancelled || stopped {
        results.append(.init(id: source.id, source: source.name, output: nil, error: "Not processed.", cancelled: true)); progress(results); continue
      }
      let filename = try outputName(source.name, index: index, suffix: suffix, format: format)
      let output = destination.appendingPathComponent(filename)
      let staged = destination.appendingPathComponent(".photato-batch-\(UUID().uuidString)")
      defer { try? FileManager.default.removeItem(at: staged) }
      do {
        try validatePublication()
      } catch {
        results.append(.init(id: source.id, source: source.name, output: nil, error: error.localizedDescription, cancelled: true)); stopped = true; progress(results); continue
      }
      do {
        let worker = Task.detached(priority: .userInitiated) {
          try Task.checkCancellation()
          var document: CraftDocument
          if let master = masters.first(where: { $0.0 == source.id }) { document = master.1 }
          else if let snapshot = source.document { document = snapshot }
          else if let url = source.url { document = try DocumentIO.read(url) }
          else { throw CraftError.invalid("Missing batch source.") }
          try validateOutput(document)
          let playback = try RecordedActionRenderer.prepare(action, in: document, clipboard: clipboard, masters: masters.filter { $0.0 != source.id }.map { $0.1 }, validateClipboard: validateClipboard, validate: validateOutput)
          try playback.command.apply(to: &document)
          try validateOutput(document)
          let bytes = try DocumentIO.encode(document, format: format, options: options)
          let writer = try AtomicFileWriter(to: staged, maximumBytes: DocumentIO.maximumDownloadBytes)
          try writer.append(bytes); try writer.commit()
        }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        // Runs on the caller's actor immediately before atomic publication.
        do { try validatePublication() } catch { stopped = true; throw error }
        try FileManager.default.linkItem(at: staged, to: output)
        results.append(.init(id: source.id, source: source.name, output: filename, error: nil, cancelled: false))
      } catch is CancellationError {
        stopped = true; results.append(.init(id: source.id, source: source.name, output: nil, error: "Cancelled.", cancelled: true))
      } catch {
        results.append(.init(id: source.id, source: source.name, output: nil, error: error.localizedDescription, cancelled: stopped))
        if stopOnError { stopped = true }
      }
      progress(results)
    }
    return results
  }
}
