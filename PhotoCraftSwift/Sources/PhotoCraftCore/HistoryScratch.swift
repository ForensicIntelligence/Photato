import CryptoKit
import Darwin
import Foundation

/// Private ephemeral storage, shared by value-copy sessions and retained snapshots.
/// The lock protects deduplication, disk accounting and ownership. Files are immutable
/// once published. Scratch is not a recovery archive and deliberately does not fsync.
final class HistoryScratchStore: @unchecked Sendable {
  static let maximumBlobBytes = 512 * 1024 * 1024
  static let chunkBytes = 64 * 1024
  private struct WeakBlob {
    let token: UUID
    weak var value: HistoryScratchBlob?
  }
  let directory: URL
  private let limit: Int
  private let lock = NSLock()
  private var blobs: [String: WeakBlob] = [:]
  private var used = 0
  private var cleanupErrors = 0
  var allocatedBytes: Int { lock.withLock { used } }
  var cleanupFailureCount: Int { lock.withLock { cleanupErrors } }

  init(parent: URL?, limit: Int) throws {
    try Task.checkCancellation()
    let parent = parent ?? FileManager.default.temporaryDirectory
    guard parent.isFileURL, limit >= 0 else {
      throw CraftError.invalid("Invalid history scratch location or size limit.")
    }
    directory = parent.appendingPathComponent(
      "PhotatoHistory-" + UUID().uuidString, isDirectory: true)
    self.limit = limit
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
  }
  deinit { try? FileManager.default.removeItem(at: directory) }

  func put(_ data: Data) throws -> HistoryScratchBlob {
    try Task.checkCancellation()
    guard data.count <= Self.maximumBlobBytes else {
      throw CraftError.invalid("History data exceeds the current scratch block limit.")
    }
    let digest = Self.digest(data)
    lock.lock()
    defer { lock.unlock() }
    if let existing = blobs[digest]?.value { return existing }
    guard data.count <= limit - used else {
      throw CraftError.invalid("History scratch storage is full. The edit was not applied.")
    }
    // A new lifetime gets a unique pathname even for the same digest. A concurrent
    // last-reference cleanup must never unlink a newly created replacement blob.
    let token = UUID()
    let url = directory.appendingPathComponent(token.uuidString)
    let fd = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600) } ?? -1
    }
    guard fd >= 0 else { throw Self.posixError() }
    var complete = false
    var closed = false
    defer {
      if !closed { Darwin.close(fd) }
      if !complete {
        let result = url.withUnsafeFileSystemRepresentation { $0.map { unlink($0) } ?? -1 }
        if result != 0 && errno != ENOENT {
          cleanupErrors += 1
          used += data.count  // Conservatively charge a failed partial-file cleanup.
        }
      }
    }
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        try Task.checkCancellation()
        let amount = pwrite(
          fd, bytes.baseAddress!.advanced(by: offset),
          min(Self.chunkBytes, bytes.count - offset), off_t(offset))
        if amount < 0 {
          if errno == EINTR { continue }
          throw Self.posixError()
        }
        guard amount > 0 else {
          throw CraftError.invalid("History scratch write made no progress.")
        }
        offset += amount
      }
    }
    try Task.checkCancellation()
    let closeResult = Darwin.close(fd)
    closed = true
    guard closeResult == 0 else { throw Self.posixError() }
    let blob = HistoryScratchBlob(
      store: self, url: url, token: token, digest: digest, count: data.count)
    blobs[digest] = WeakBlob(token: token, value: blob)
    used += data.count
    complete = true
    return blob
  }

  fileprivate func release(_ blob: HistoryScratchBlob) {
    lock.lock()
    defer { lock.unlock() }
    let result = blob.url.withUnsafeFileSystemRepresentation { $0.map { unlink($0) } ?? -1 }
    if result == 0 || errno == ENOENT { used -= blob.count } else { cleanupErrors += 1 }  // Keep failed cleanup charged to the disk budget.
    if blobs[blob.digest]?.token == blob.token { blobs.removeValue(forKey: blob.digest) }
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

final class HistoryScratchBlob: Sendable {
  let store: HistoryScratchStore
  let url: URL
  let token: UUID
  let digest: String
  let count: Int
  init(store: HistoryScratchStore, url: URL, token: UUID, digest: String, count: Int) {
    self.store = store
    self.url = url
    self.token = token
    self.digest = digest
    self.count = count
  }
  deinit { store.release(self) }
  func read() throws -> Data {
    try Task.checkCancellation()
    let fd = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK) } ?? -1
    }
    guard fd >= 0 else { throw HistoryScratchStore.posixError() }
    defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw HistoryScratchStore.posixError() }
    guard info.st_mode & S_IFMT == S_IFREG, info.st_size == count else {
      throw CraftError.invalid("History scratch data was replaced or truncated.")
    }
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        try Task.checkCancellation()
        let amount = pread(
          fd, bytes.baseAddress!.advanced(by: offset),
          min(HistoryScratchStore.chunkBytes, bytes.count - offset), off_t(offset))
        if amount < 0 {
          if errno == EINTR { continue }
          throw HistoryScratchStore.posixError()
        }
        guard amount > 0 else { throw CraftError.invalid("History scratch data was truncated.") }
        offset += amount
      }
    }
    guard HistoryScratchStore.digest(data) == digest else {
      throw CraftError.invalid(
        "History scratch integrity check failed. The document was not changed.")
    }
    return data
  }
}

extension CodingUserInfoKey {
  static let historyTileEncoder = CodingUserInfoKey(rawValue: "Photato.HistoryTileEncoder")!
  static let historyTileDecoder = CodingUserInfoKey(rawValue: "Photato.HistoryTileDecoder")!
}

// Each context belongs exclusively to one synchronous encode/decode. It is never
// shared with another task; @unchecked meets Foundation's userInfo value constraint.
final class HistoryTileEncoder: ComponentBlobEncoding, @unchecked Sendable {
  let store: HistoryScratchStore
  let supportsComponentPages = true
  var references: [String: HistoryScratchBlob] = [:]
  init(_ store: HistoryScratchStore) { self.store = store }
  func storeBytes(_ data: Data) throws -> String {
    let blob = try store.put(data)
    references[blob.digest] = blob
    return blob.digest
  }
}
/// Only arrays already owned by the current restored document. This value is
/// replaced on navigation and discarded by editing; it never retains older states.
struct HistoryDecodedTiles: Sendable {
  let tiles: [String: [Pixel]]
  var bytes: Int { tiles.values.reduce(0) { $0 + $1.count * MemoryLayout<Pixel>.stride } }
}

final class HistoryTileDecoder: ComponentBlobDecoding, @unchecked Sendable {
  let references: [String: HistoryScratchBlob]
  let supportsComponentPages = true
  let usesMappedComponents = true
  private let componentBudget = ComponentScratchBudget()
  func reserveComponentScratch(bytes: Int) throws { try componentBudget.reserve(bytes) }
  private var tiles: [String: [Pixel]] = [:]
  private var reusableTiles: [String: [Pixel]]
  private let tileDecoder = TileArchive.Decoder()
  init(_ references: [String: HistoryScratchBlob], reusing: HistoryDecodedTiles? = nil) {
    self.references = references
    reusableTiles = reusing?.tiles ?? [:]
  }
  var decodedTiles: HistoryDecodedTiles { HistoryDecodedTiles(tiles: tiles) }
  func clear() {
    tiles = [:]
    reusableTiles = [:]
  }
  func bytes(_ digest: String, maximumBytes: Int) throws -> Data {
    guard let blob = references[digest] else {
      throw CraftError.invalid("Missing history scratch reference.")
    }
    guard blob.count <= maximumBytes else {
      throw CraftError.invalid("History blob exceeds the decoded payload limit.")
    }
    return try blob.read()
  }
  func tile(_ digest: String) throws -> [Pixel] {
    if let cached = tiles[digest] { return cached }
    // A previously verified array does not excuse missing or corrupt disk data.
    // Recheck this snapshot's owned blob before sharing the current array.
    let data = try bytes(digest, maximumBytes: TileArchive.byteCount + 1)
    let decoded: [Pixel]
    if let reused = reusableTiles.removeValue(forKey: digest) {
      decoded = reused
    } else {
      decoded = try tileDecoder.decode(data)
    }
    tiles[digest] = decoded
    return decoded
  }
}

final class HistorySnapshot: Sendable {
  private struct Envelope: Codable {
    var magic = "PhotatoScratch"
    var version = 1
    var document: CraftDocument
  }
  let metadata: HistoryScratchBlob
  let references: [String: HistoryScratchBlob]
  init(_ document: CraftDocument, store: HistoryScratchStore) throws {
    try Task.checkCancellation()
    try document.validate()
    let context = HistoryTileEncoder(store)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    encoder.userInfo[.historyTileEncoder] = context
    let data = try encoder.encode(Envelope(document: document))
    metadata = try store.put(data)
    references = context.references
  }
  func restore() throws -> CraftDocument {
    try restore(reusing: nil).document
  }
  func restore(reusing tiles: HistoryDecodedTiles?) throws
    -> (document: CraftDocument, tiles: HistoryDecodedTiles)
  {
    try Task.checkCancellation()
    let context = HistoryTileDecoder(references, reusing: tiles)
    // Failed decoder/error objects must not prolong the lifetime of raster arrays.
    // The returned value owns only the arrays referenced by the restored document.
    defer { context.clear() }
    let decoder = PropertyListDecoder()
    decoder.userInfo[.historyTileDecoder] = context
    decoder.userInfo[.rasterDecodeBudget] = RasterDecodeBudget(bytes: 1_073_741_824)
    let envelope = try decoder.decode(Envelope.self, from: metadata.read())
    guard envelope.magic == "PhotatoScratch", envelope.version == 1 else {
      throw CraftError.invalid("Invalid history snapshot.")
    }
    try envelope.document.validate()
    try Task.checkCancellation()
    return (envelope.document, context.decodedTiles)
  }
}
