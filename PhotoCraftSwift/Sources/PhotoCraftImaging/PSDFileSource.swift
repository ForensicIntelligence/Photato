import Darwin
import Foundation
import PhotoCraftCore

/// Owns a regular-file descriptor for the entire decode. Positioned reads avoid
/// mmap faults if another process truncates the file. A small shared page cache
/// accommodates interleaved RGB/alpha/mask scanlines without retaining the file.
final class PSDFileSource {
  private struct MetadataChanged: LocalizedError {
    var errorDescription: String? { PSDFileSource.changedError().localizedDescription }
  }
  static let pageBytes = 64 * 1024
  static let maximumCachedPages = 8
  struct Metrics {
    var readCalls = 0
    var maximumReadBytes = 0
    var peakCachedBytes = 0
  }
  private struct Identity: Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int
    init(_ value: stat) {
      device = value.st_dev
      inode = value.st_ino
      size = value.st_size
      modifiedSeconds = value.st_mtimespec.tv_sec
      modifiedNanoseconds = value.st_mtimespec.tv_nsec
      changedSeconds = value.st_ctimespec.tv_sec
      changedNanoseconds = value.st_ctimespec.tv_nsec
    }
    func sameFileAndModification(as other: Self) -> Bool {
      device == other.device && inode == other.inode && size == other.size
        && modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
    }
  }
  let count: Int
  private let descriptor: Int32
  private let url: URL
  private let identity: Identity
  private let lock = NSLock()
  private var cache: [Int: Data] = [:]
  private var recentPages: [Int] = []
  private var counters = Metrics()
  var metrics: Metrics {
    lock.lock()
    defer { lock.unlock() }
    return counters
  }

  init(_ url: URL, maximumBytes: Int = PSDCodec.maximumFileBytes) throws {
    try Task.checkCancellation()
    guard url.isFileURL, maximumBytes >= 0 else {
      throw CraftError.invalid("Choose a local regular image file.")
    }
    let opened = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NONBLOCK) } ?? -1
    }
    guard opened >= 0 else { throw Self.posixError() }
    var transferred = false
    defer { if !transferred { Darwin.close(opened) } }
    var details = stat()
    guard fstat(opened, &details) == 0 else { throw Self.posixError() }
    guard details.st_mode & S_IFMT == S_IFREG else {
      throw CraftError.invalid("Choose a regular image file, not a directory or device.")
    }
    guard let size = Int(exactly: details.st_size), size >= 0, size <= maximumBytes else {
      throw CraftError.invalid("Image exceeds the configured file input limit.")
    }
    self.url = url
    descriptor = opened
    identity = Identity(details)
    count = size
    transferred = true
  }

  deinit { Darwin.close(descriptor) }

  /// macOS can attach provenance to a just-saved file. Restart from a fresh
  /// descriptor once, with the same inode, size and modification time.
  static func withStableMetadata<T>(_ url: URL, read: (PSDFileSource) throws -> T) throws -> T {
    let original = try PSDFileSource(url)
    do {
      return try read(original)
    } catch is MetadataChanged {
      try Task.checkCancellation()
      let retry = try PSDFileSource(url)
      guard retry.identity.sameFileAndModification(as: original.identity) else { throw changedError() }
      do { return try read(retry) } catch is MetadataChanged { throw changedError() }
    }
  }

  /// Metadata callers may materialize a bounded block; channel callers request
  /// rows/chunks. Every physical read is at most one page regardless of count.
  func bytes(at offset: Int, count: Int) throws -> Data {
    try Task.checkCancellation()
    guard offset >= 0, count >= 0, offset <= self.count, count <= self.count - offset else {
      throw CraftError.invalid("Truncated or invalid image file range.")
    }
    lock.lock()
    defer { lock.unlock() }
    var result = Data()
    result.reserveCapacity(count)
    var at = offset
    let end = offset + count
    while at < end {
      try Task.checkCancellation()
      let pageIndex = at / Self.pageBytes
      let page = try readPage(pageIndex)
      let within = at % Self.pageBytes
      let length = min(end - at, page.count - within)
      guard length > 0 else { throw CraftError.invalid("Truncated image file.") }
      result.append(page[within..<within + length])
      at += length
    }
    return result
  }

  func validateUnchanged() throws {
    try Task.checkCancellation()
    lock.lock()
    defer { lock.unlock() }
    try validateDescriptor(verifyPath: true)
  }

  private func validateDescriptor(verifyPath: Bool = false) throws {
    var current = stat()
    guard fstat(descriptor, &current) == 0 else { throw Self.posixError() }
    let opened = Identity(current)
    guard opened.sameFileAndModification(as: identity) else { throw Self.changedError() }
    guard verifyPath || opened != identity else { return }
    var pathIdentity = stat()
    let status = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.fstatat(AT_FDCWD, $0, &pathIdentity, 0) } ?? -1
    }
    let named = Identity(pathIdentity)
    guard status == 0, named.sameFileAndModification(as: identity) else { throw Self.changedError() }
    guard opened == identity, named == identity else { throw MetadataChanged() }
  }

  private func readPage(_ index: Int) throws -> Data {
    if let cached = cache[index] {
      recentPages.removeAll { $0 == index }
      recentPages.append(index)
      return cached
    }
    try validateDescriptor()
    let offset = index * Self.pageBytes
    let length = min(Self.pageBytes, count - offset)
    var page = Data(count: length)
    var received = 0
    while received < length {
      try Task.checkCancellation()
      let requested = length - received
      var readError: Int32 = 0
      let amount = page.withUnsafeMutableBytes { target in
        let result = pread(
          descriptor, target.baseAddress!.advanced(by: received), requested,
          off_t(offset + received))
        readError = errno
        return result
      }
      counters.readCalls += 1
      counters.maximumReadBytes = max(counters.maximumReadBytes, requested)
      if amount < 0 {
        if readError == EINTR { continue }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(readError))
      }
      guard amount > 0 else { throw CraftError.invalid("Truncated image file during decoding.") }
      received += amount
    }
    try validateDescriptor()
    if recentPages.count == Self.maximumCachedPages {
      cache.removeValue(forKey: recentPages.removeFirst())
    }
    cache[index] = page
    recentPages.append(index)
    counters.peakCachedBytes = max(
      counters.peakCachedBytes, cache.values.reduce(0) { $0 + $1.count })
    return page
  }

  private static func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
  }
  private static func changedError() -> CraftError {
    .invalid("The image file changed while it was being read. Open it again.")
  }
}

/// A small synthesized header and validated ranges from the original container.
final class PSDByteSequence {
  struct Input {
    let storage: PSDByteStorage
    let start: Int
    let count: Int
  }

  private struct Part {
    let input: Input
    let offset: Int
    var end: Int { offset + input.count }
  }

  private let parts: [Part]
  private let original: PSDByteStorage
  let count: Int

  init(_ inputs: [Input], original: PSDByteStorage) throws {
    self.original = original
    var position = 0
    var result: [Part] = []
    for input in inputs where input.count > 0 {
      guard input.start >= 0, input.start <= input.storage.count,
        input.count <= input.storage.count - input.start,
        input.count <= Int.max - position else {
        throw CraftError.invalid("Invalid Photoshop byte extent.")
      }
      result.append(Part(input: input, offset: position))
      position += input.count
    }
    self.parts = result
    self.count = position
  }

  private func part(containing offset: Int) -> Int {
    var low = 0, high = parts.count
    while low < high {
      let middle = low + (high - low) / 2
      if offset >= parts[middle].end { low = middle + 1 }
      else { high = middle }
    }
    return low
  }

  func bytes(at offset: Int, count: Int) throws -> Data {
    if count == 0 { return Data() }
    var index = part(containing: offset)
    let first = parts[index]
    if count <= first.end - offset {
      return try first.input.storage.bytes(at: first.input.start + offset - first.offset, count: count)
    }
    var position = offset
    let end = offset + count
    var result = Data()
    result.reserveCapacity(count)
    while position < end {
      let part = parts[index]
      let length = min(end, part.end) - position
      result.append(try part.input.storage.bytes(at: part.input.start + position - part.offset, count: length))
      position += length
      index += 1
    }
    return result
  }

  func padding(at offset: Int, count: Int, byte: UInt8) throws -> Bool {
    var index = part(containing: offset)
    var position = offset
    let end = offset + count
    while position < end {
      let part = parts[index]
      let length = min(end, part.end) - position
      guard try part.input.storage.padding(at: part.input.start + position - part.offset,
        count: length, byte: byte) else { return false }
      position += length
      index += 1
    }
    return true
  }

  func validateUnchanged() throws { try original.validateUnchanged() }
}

enum PSDByteStorage {
  case memory(Data)
  case file(PSDFileSource)
  case assembled(PSDByteSequence)

  var count: Int {
    switch self {
    case .memory(let data): return data.count
    case .file(let source): return source.count
    case .assembled(let source): return source.count
    }
  }
  func bytes(at offset: Int, count: Int) throws -> Data {
    switch self {
    case .memory(let data):
      return data.subdata(in: data.startIndex + offset..<data.startIndex + offset + count)
    case .file(let source): return try source.bytes(at: offset, count: count)
    case .assembled(let source): return try source.bytes(at: offset, count: count)
    }
  }
  func number(at offset: Int, count: Int) throws -> UInt64 {
    switch self {
    case .memory(let data):
      var value: UInt64 = 0
      for index in data.startIndex + offset..<data.startIndex + offset + count {
        value = (value << 8) | UInt64(data[index])
      }
      return value
    case .file, .assembled:
      return try bytes(at: offset, count: count).reduce(0) { ($0 << 8) | UInt64($1) }
    }
  }
  func padding(at offset: Int, count: Int, byte: UInt8) throws -> Bool {
    switch self {
    case .memory(let data):
      return data.withUnsafeBytes { bytes in
        (offset..<offset + count).allSatisfy { bytes[$0] == byte }
      }
    case .assembled(let source):
      return try source.padding(at: offset, count: count, byte: byte)
    case .file(let source):
      var at = offset
      while at < offset + count {
        let length = min(PSDFileSource.pageBytes, offset + count - at)
        guard try source.bytes(at: at, count: length).allSatisfy({ $0 == byte }) else {
          return false
        }
        at += length
      }
      return true
    }
  }
  func validateUnchanged() throws {
    switch self {
    case .memory: break
    case .file(let source): try source.validateUnchanged()
    case .assembled(let source): try source.validateUnchanged()
    }
  }
}
