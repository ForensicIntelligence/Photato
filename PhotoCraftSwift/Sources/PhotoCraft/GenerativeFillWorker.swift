import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Core ML may terminate its caller on a GPU runtime exception. Run prompt
/// inference in a copy of the app process so the editor can discard a failed job.
enum GenerativeFillWorker {
  static let argument = "--local-generative-fill-worker"
  private static let side = LocalGenerativeFill.side
  private static let area = side * side
  private static let maximumRequestBytes = 8 * 1_024 * 1_024
  private static let maximumReplyBytes = 16 * 1_024 * 1_024

  private struct Request: Codable {
    let bookmark: Data
    let prompt: String
    let seeds: [UInt32]
    let image: Data
    let mask: Data
  }

  private struct Reply: Codable {
    var pixels: [Data] = []
    var error: String?
  }

  static func run(
    model: URL, bookmark: Data? = nil, prompt: String, seeds: [UInt32], image: [Float], mask: [Float],
    executable override: URL? = nil
  ) throws -> [Surface] {
    try Task.checkCancellation()
    let process = Process()
    guard let executable = override ?? executableURL() else {
      throw CraftError.unavailable("The local inference worker is unavailable.")
    }
    let files = FileManager.default
    let directory = files.temporaryDirectory.appending(path: "Photato-Inference-\(UUID().uuidString)", directoryHint: .isDirectory)
    try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? files.removeItem(at: directory) }
    let request = Request(bookmark: try bookmark ?? GenerativeFillModelPreference.bookmark(for: model), prompt: prompt,
      seeds: seeds, image: image.withUnsafeBytes { Data($0) }, mask: mask.withUnsafeBytes { Data($0) })
    try write(request, to: directory.appending(path: "request.plist"))

    process.executableURL = executable
    process.arguments = [argument, directory.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() }
    catch { throw CraftError.unavailable("Could not start local model inference.") }
    while process.isRunning {
      if Task.isCancelled {
        process.terminate()
        process.waitUntilExit()
        throw CancellationError()
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    try Task.checkCancellation()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw CraftError.unavailable("Local model inference stopped unexpectedly. Try Generate again.")
    }
    let resultURL = directory.appending(path: "reply.plist")
    guard files.fileExists(atPath: resultURL.path) else {
      throw CraftError.unavailable("Local model inference finished without a result.")
    }
    let reply = try read(Reply.self, at: resultURL, maximumBytes: maximumReplyBytes)
    if let error = reply.error { throw CraftError.unavailable(error) }
    guard reply.pixels.count == seeds.count else {
      throw CraftError.invalid("Local model inference returned an incomplete variation set.")
    }
    return try reply.pixels.map(surface)
  }

  static func runChild(directory: URL) -> Int32 {
    guard directory.lastPathComponent.hasPrefix("Photato-Inference-") else { return 1 }
    let reply: Reply
    do {
      let request = try read(Request.self, at: directory.appending(path: "request.plist"), maximumBytes: maximumRequestBytes)
      guard let model = GenerativeFillModelPreference.resolve(request.bookmark) else {
        throw CraftError.unavailable("Choose the local prompt model again to restore access.")
      }
      let image = try floats(request.image, count: area * 3)
      let mask = try floats(request.mask, count: area)
      let results = try LocalGenerativeFill.predictPrompt(image: image, mask: mask, model: model,
        prompt: request.prompt, seeds: request.seeds)
      reply = Reply(pixels: try results.map { try $0.rgbaData(depth: .f32) })
    } catch {
      reply = Reply(error: error.localizedDescription)
    }
    do {
      try write(reply, to: directory.appending(path: "reply.plist"))
      return 0
    } catch {
      return 1
    }
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
