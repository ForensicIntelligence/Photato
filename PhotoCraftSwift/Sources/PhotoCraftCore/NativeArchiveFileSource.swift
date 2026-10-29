import Darwin
import Foundation

/// Retains the opened regular file, checks observed identity changes, and bounds
/// each physical read. No mmap accesses are made by the chunked archive reader.
final class NativeArchiveFileSource {
  private struct MetadataChanged: Error {}
  static let chunkBytes = 64 * 1024
  /// AppKit and filesystem services can update attributes after a save completes.
  /// Retry the entire read once, with a fresh descriptor and all integrity checks.
  /// Never accept bytes from an attempt whose observed identity changed.
  static func withStableMetadata<T>(_ read: () throws -> T) throws -> T {
    for attempt in 0...1 {
      do { return try read() } catch is MetadataChanged {
        try Task.checkCancellation()
        if attempt == 1 {
          throw CraftError.invalid("The native document changed while reading. Open it again.")
        }
      }
    }
    preconditionFailure("Bounded read must return or throw")
  }
  let count: Int
  private let descriptor: Int32
  private let url: URL
  private let identity: Identity
  private(set) var maximumReadBytes = 0
  private struct Identity: Equatable {
    var device: dev_t
    var inode: ino_t
    var size: off_t
    var modified: Int
    var modifiedNS: Int
    var changed: Int
    var changedNS: Int
    init(_ s: stat) {
      device = s.st_dev
      inode = s.st_ino
      size = s.st_size
      modified = s.st_mtimespec.tv_sec
      modifiedNS = s.st_mtimespec.tv_nsec
      changed = s.st_ctimespec.tv_sec
      changedNS = s.st_ctimespec.tv_nsec
    }
    func sameFileAndModification(as other: Self) -> Bool {
      device == other.device && inode == other.inode && size == other.size
        && modified == other.modified && modifiedNS == other.modifiedNS
    }
  }
  init(_ url: URL, maximumBytes: Int = NativeArchive.maximumBytes) throws {
    try Task.checkCancellation()
    guard url.isFileURL else { throw CraftError.invalid("Choose a local native document.") }
    let fd = url.withUnsafeFileSystemRepresentation {
      $0.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
    }
    guard fd >= 0 else { throw Self.posixError() }
    var owned = false
    defer { if !owned { Darwin.close(fd) } }
    var s = stat()
    guard fstat(fd, &s) == 0 else { throw Self.posixError() }
    guard s.st_mode & S_IFMT == S_IFREG, let count = Int(exactly: s.st_size), count >= 0,
      count <= maximumBytes
    else {
      throw CraftError.invalid("Choose a regular document within the native file size limit.")
    }
    self.count = count
    self.url = url
    descriptor = fd
    identity = Identity(s)
    owned = true
  }
  deinit { Darwin.close(descriptor) }
  func read(at offset: Int, count: Int) throws -> Data {
    try Task.checkCancellation()
    guard offset >= 0, count >= 0, offset <= self.count, count <= self.count - offset else {
      throw CraftError.invalid("Invalid native archive range.")
    }
    try validateUnchanged()
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { bytes in
      var done = 0
      while done < bytes.count {
        try Task.checkCancellation()
        let requested = min(Self.chunkBytes, bytes.count - done)
        let amount = pread(
          descriptor, bytes.baseAddress!.advanced(by: done), requested, off_t(offset + done))
        maximumReadBytes = max(maximumReadBytes, requested)
        if amount < 0 {
          if errno == EINTR { continue }
          throw Self.posixError()
        }
        guard amount > 0 else {
          throw CraftError.invalid("Native archive was truncated while reading.")
        }
        done += amount
      }
    }
    try validateUnchanged()
    return data
  }
  func validateUnchanged() throws {
    try Task.checkCancellation()
    var current = stat()
    var path = stat()
    guard fstat(descriptor, &current) == 0 else { throw Self.posixError() }
    let status = url.withUnsafeFileSystemRepresentation {
      $0.map { fstatat(AT_FDCWD, $0, &path, 0) } ?? -1
    }
    guard status == 0,
      Identity(current).sameFileAndModification(as: identity),
      Identity(path).sameFileAndModification(as: identity)
    else {
      throw CraftError.invalid("The native document changed while reading. Open it again.")
    }
    guard Identity(current) == identity, Identity(path) == identity else {
      throw MetadataChanged()
    }
  }
  static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
