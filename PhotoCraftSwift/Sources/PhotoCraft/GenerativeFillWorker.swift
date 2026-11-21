import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Core ML may terminate its caller on a GPU runtime exception. Run prompt
/// inference in a copy of the app process so the editor can discard a failed job.
enum GenerativeFillWorker {
  static let argument = "--local-generative-fill-worker"
  private static let side = LocalGenerativeFill.side
  private static let area = side * side
  private static let maximumConfigurationBytes = LocalGenerationGuide.byteCount + 1024 * 1024
  private static let maximumRequestBytes = 8 * 1_024 * 1_024
  private static let maximumReplyBytes = 16 * 1_024 * 1_024
  private static let signal = Data([1])
  private static let stopped = CraftError.unavailable("Local model inference stopped unexpectedly. Try Generate again.")

  private struct Configuration: Codable {
    let bookmark: Data
    let instructions: Bool
    let guide: LocalGenerationGuide?
    let guideBookmark: Data?
  }

  private struct Request: Codable {
    let prompt: String
    let seeds: [UInt32]
    let image: Data
    let mask: Data
    let mode: LocalGenerativeFill.PromptMode
  }

  private struct Reply: Codable {
    var pixels: [Data] = []
    var error: String?
  }

  static func run(
    model: URL, bookmark: Data? = nil, prompt: String, seeds: [UInt32], image: [Float], mask: [Float],
    mode: LocalGenerativeFill.PromptMode = .fill, instructions: Bool = false, executable override: URL? = nil,
    guide: LocalGenerationGuide? = nil, guideBookmark: Data? = nil
  ) throws -> [Surface] {
    try withSession(model: model, bookmark: bookmark, instructions: instructions, executable: override,
      guide: guide, guideBookmark: guideBookmark) { session in
      try session.predict(prompt: prompt, seeds: seeds, image: image, mask: mask, mode: mode)
    }
  }

  /// The worker and its model are scoped to one edit, including all its windows.
  static func withSession<Result>(
    model: URL, bookmark: Data? = nil, instructions: Bool = false, executable override: URL? = nil,
    guide: LocalGenerationGuide? = nil, guideBookmark: Data? = nil, _ body: (Session) throws -> Result
  ) throws -> Result {
    try Task.checkCancellation()
    guard let executable = override ?? executableURL() else {
      throw CraftError.unavailable("The local inference worker is unavailable.")
    }
    let files = FileManager.default
    let directory = files.temporaryDirectory.appending(path: "Photato-Inference-\(UUID().uuidString)", directoryHint: .isDirectory)
    try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? files.removeItem(at: directory) }

    guard (guide == nil) == (guideBookmark == nil), guide == nil || !instructions else {
      throw CraftError.unavailable("Choose the model for the reference image.")
    }
    try guide?.validate()
    let configuration = Configuration(bookmark: try bookmark ?? GenerativeFillModelPreference.bookmark(for: model),
      instructions: instructions, guide: guide, guideBookmark: guideBookmark)
    try write(configuration, to: directory.appending(path: "model.plist"))
    let process = Process()
    let pipe = Pipe()
    let input = pipe.fileHandleForWriting
    // A child can exit between an isRunning check and a signal write.
    guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
      throw CraftError.unavailable("Could not configure local model inference.")
    }
    process.executableURL = executable
    process.arguments = [argument, directory.path]
    process.standardInput = pipe
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try Task.checkCancellation()
    do { try process.run() }
    catch { throw CraftError.unavailable("Could not start local model inference.") }
    try? pipe.fileHandleForReading.close()
    let session = Session(process: process, input: input, directory: directory)
    defer { session.close() }
    let result = try body(session)
    try Task.checkCancellation()
    return result
  }

  final class Session {
    private let process: Process
    private let input: FileHandle
    private let directory: URL

    fileprivate init(process: Process, input: FileHandle, directory: URL) {
      self.process = process
      self.input = input
      self.directory = directory
    }

    func predict(
      prompt: String, seeds: [UInt32], image: [Float], mask: [Float], mode: LocalGenerativeFill.PromptMode = .fill
    ) throws -> [Surface] {
      try Task.checkCancellation()
      guard process.isRunning else { throw stopped }
      let requestURL = directory.appending(path: "request.plist")
      let replyURL = directory.appending(path: "reply.plist")
      let request = Request(prompt: prompt, seeds: seeds, image: image.withUnsafeBytes { Data($0) },
        mask: mask.withUnsafeBytes { Data($0) }, mode: mode)
      try write(request, to: requestURL)
      do { try input.write(contentsOf: signal) }
      catch { throw stopped }

      let files = FileManager.default
      while !files.fileExists(atPath: replyURL.path) {
        try Task.checkCancellation()
        if !process.isRunning {
          // A reported model error may be published just before the child exits.
          guard files.fileExists(atPath: replyURL.path) else { throw stopped }
          break
        }
        Thread.sleep(forTimeInterval: 0.05)
      }
      try Task.checkCancellation()
      let reply = try read(Reply.self, at: replyURL, maximumBytes: maximumReplyBytes)
      try files.removeItem(at: requestURL)
      try files.removeItem(at: replyURL)
      if let error = reply.error { throw CraftError.unavailable(error) }
      guard reply.pixels.count == seeds.count else {
        throw CraftError.invalid("Local model inference returned an incomplete variation set.")
      }
      return try reply.pixels.map(surface)
    }

    fileprivate func close() {
      try? input.close()
      if Task.isCancelled || !waitForExit() {
        if process.isRunning { process.terminate() }
        // A stuck Core ML call must not keep the editing job alive after Cancel.
        if !waitForExit(), process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
      }
      process.waitUntilExit()
    }

    private func waitForExit() -> Bool {
      let deadline = ContinuousClock.now + .seconds(1)
      while process.isRunning, ContinuousClock.now < deadline {
        Thread.sleep(forTimeInterval: 0.025)
      }
      return !process.isRunning
    }
  }

  static func runChild(directory: URL) -> Int32 {
    guard directory.lastPathComponent.hasPrefix("Photato-Inference-") else { return 1 }
    let input = FileHandle.standardInput
    let requestURL = directory.appending(path: "request.plist")
    let replyURL = directory.appending(path: "reply.plist")
    do {
      guard try waitForRequest(input) else { return 0 }
      let config = try read(Configuration.self, at: directory.appending(path: "model.plist"),
        maximumBytes: maximumConfigurationBytes)
      guard let model = GenerativeFillModelPreference.resolve(config.bookmark) else {
        throw CraftError.unavailable("Choose the local prompt model again to restore access.")
      }
      let serve: (LocalGenerativeFill.PromptPredictor) throws -> Void = { predict in
        repeat {
          let request = try read(Request.self, at: requestURL, maximumBytes: maximumRequestBytes)
          let image = try floats(request.image, count: area * 3)
          let mask = try floats(request.mask, count: area)
          let results = try predict(image, mask, request.prompt, request.seeds, request.mode)
          let reply = Reply(pixels: try results.map { try $0.rgbaData(depth: .f32) })
          try writeReply(reply, to: replyURL)
        } while try waitForRequest(input)
      }
      if config.instructions {
        try LocalGenerativeFill.withInstructionPredictor(at: model, serve)
      } else {
        let guideModel = config.guideBookmark.flatMap(GenerativeFillModelPreference.resolve)
        try LocalGenerativeFill.withPromptPredictor(at: model, guide: config.guide, guideModel: guideModel, serve)
      }
      return 0
    } catch {
      try? writeReply(Reply(error: error.localizedDescription), to: replyURL)
      return 1
    }
  }

  private static func waitForRequest(_ input: FileHandle) throws -> Bool {
    guard let received = try input.read(upToCount: 1), !received.isEmpty else { return false }
    guard received == signal else {
      throw CraftError.invalid("Invalid local inference request signal.")
    }
    return true
  }

  private static func executableURL() -> URL? {
    if ProcessInfo.processInfo.processName == "xctest",
      let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_GENERATIVE_FILL_EXECUTABLE"] {
      return URL(fileURLWithPath: path)
    }
    let executable = Bundle.main.executableURL
    return executable?.lastPathComponent == "Photato" ? executable : nil
  }

  private static func read<T: Decodable>(_ type: T.Type, at url: URL, maximumBytes: Int) throws -> T {
    let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard attributes.isRegularFile == true, let size = attributes.fileSize,
      (1...maximumBytes).contains(size) else { throw CraftError.invalid("Invalid local inference data.") }
    return try PropertyListDecoder().decode(type, from: Data(contentsOf: url))
  }

  private static func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    try encoder.encode(value).write(to: url, options: .withoutOverwriting)
  }

  private static func writeReply(_ value: Reply, to url: URL) throws {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    try encoder.encode(value).write(to: url, options: .atomic)
  }

  private static func floats(_ data: Data, count: Int) throws -> [Float] {
    guard data.count == count * MemoryLayout<Float>.stride else {
      throw CraftError.invalid("The local inference worker returned invalid sample dimensions.")
    }
    var values = [Float](repeating: 0, count: count)
    _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
    return values
  }

  private static func surface(_ data: Data) throws -> Surface {
    let values = try floats(data, count: area * 4)
    var result = try Surface(width: side, height: side, depth: .f32)
    for y in 0..<side {
      try Task.checkCancellation()
      for x in 0..<side {
        let i = (y * side + x) * 4
        result.setPixel(x: x, y: y, Pixel(values[i], values[i + 1], values[i + 2], values[i + 3]))
      }
    }
    return result
  }
}
