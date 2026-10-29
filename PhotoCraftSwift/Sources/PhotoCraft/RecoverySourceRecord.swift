import CryptoKit
import Darwin
import Foundation
import PhotoCraftCore

/// Recovery-local provenance. Never included in ordinary saved/exported documents or API state.
struct RecoverySourceRecord: Codable, Sendable {
  var version = 1
  var originalURL: URL
  var format: String
  var needsFormatReview: Bool
  var fingerprint: RecoverySourceFingerprint
  var bookmark: Data?
  var scopedBookmark: Bool

  static func make(
    url: URL, format: DocumentIO.Format, needsReview: Bool,
    fingerprint: RecoverySourceFingerprint
  ) -> Self {
    let url = canonical(url)
    var scoped = true
    var bookmark = try? url.bookmarkData(options: .withSecurityScope)
    if bookmark == nil {
      scoped = false
      bookmark = try? url.bookmarkData(options: [])
    }
    if (bookmark?.count ?? 0) > 65_536 { bookmark = nil; scoped = false }
    return .init(originalURL: canonical(url), format: format.rawValue,
      needsFormatReview: needsReview, fingerprint: fingerprint, bookmark: bookmark,
      scopedBookmark: scoped)
  }
  func encoded() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= NativeArchive.maximumRecoveryContextBytes else {
      throw CraftError.invalid("Recovery source information is too large.")
    }
    return data
  }
  var isValid: Bool {
    version == 1 && originalURL.isFileURL && (originalURL.host == nil || originalURL.host == "")
      && originalURL.path.utf8.count <= 16_384 && DocumentIO.Format(rawValue: format) != nil
      && (bookmark?.count ?? 0) <= 65_536 && fingerprint.isValid
  }
  static func decode(_ data: Data?) -> Self? {
    guard let data, data.count <= NativeArchive.maximumRecoveryContextBytes else { return nil }
    if let record = try? JSONDecoder().decode(Self.self, from: data), record.isValid { return record }
    return RecoverySnapshotContext.decode(data)?.source
  }
  static func canonical(_ url: URL) -> URL {
    func resolvedPath(_ candidate: URL) -> String? {
      candidate.withUnsafeFileSystemRepresentation { path in
        guard let path, let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
      }
    }
    if let path = resolvedPath(url) { return URL(fileURLWithPath: path) }
    // Resolve the nearest existing ancestor, including when an entire source
    // folder was deleted. /var and /private/var must retain the same identity.
    var ancestor = url
    var missing: [String] = []
    while ancestor.path != "/" {
      missing.append(ancestor.lastPathComponent)
      ancestor.deleteLastPathComponent()
      if let parent = resolvedPath(ancestor) {
        return missing.reversed().reduce(URL(fileURLWithPath: parent, isDirectory: true)) {
          $0.appendingPathComponent($1)
        }
      }
    }
    return url.standardizedFileURL
  }

  struct Verification: Sendable {
    var status: RecoverySourceStatus
    var url: URL?
    var fingerprint: RecoverySourceFingerprint?
  }
  func verify(registeredURL: URL, resolveBookmark: Bool = true) -> Verification {
    let registered = Self.canonical(registeredURL)
    var resolvedURL: URL?
    if resolveBookmark, let bookmark {
      var stale = false
      var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
      if scopedBookmark { options.insert(.withSecurityScope) }
      resolvedURL = try? URL(resolvingBookmarkData: bookmark, options: options,
        relativeTo: nil, bookmarkDataIsStale: &stale)
    }
    guard registered == Self.canonical(originalURL)
      || resolvedURL.map({ $0.isFileURL && Self.canonical($0) == registered }) == true
    else { return .init(status: .unverified) }
    let candidate = resolvedURL.flatMap { $0.isFileURL ? $0 : nil } ?? registeredURL
    let access = candidate.startAccessingSecurityScopedResource()
    defer { if access { candidate.stopAccessingSecurityScopedResource() } }
    do {
      let current = try RecoverySourceReader.capture(candidate)
      guard let volume = fingerprint.volume, let currentVolume = current.volume else {
        return .init(status: .unverified)
      }
      guard volume == currentVolume, fingerprint.inode == current.inode,
        fingerprint.birthSeconds == current.birthSeconds,
        fingerprint.birthNanoseconds == current.birthNanoseconds
      else { return .init(status: .replaced) }
      guard fingerprint.size == current.size, fingerprint.sha256 == current.sha256,
        fingerprint.modifiedSeconds == current.modifiedSeconds,
        fingerprint.modifiedNanoseconds == current.modifiedNanoseconds
      else { return .init(status: .changed) }
      return .init(status: Self.canonical(candidate) == Self.canonical(originalURL) ? .unchanged : .moved,
        url: candidate, fingerprint: current)
    } catch {
      let error = error as NSError
      return .init(status: error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
        ? .missing : .unavailable)
    }
  }
}

enum RecoverySourceStatus: String, Sendable, CaseIterable {
  case none, checking, unchanged, moved, changed, replaced, missing, unavailable, unverified
  var verified: Bool { self == .unchanged || self == .moved }
}

struct RecoverySourceFingerprint: Codable, Equatable, Sendable {
  var volume: String?
  var inode: UInt64
  var birthSeconds: Int
  var birthNanoseconds: Int
  var size: Int
  var modifiedSeconds: Int
  var modifiedNanoseconds: Int
  var sha256: String
  var isValid: Bool {
    size >= 0 && size <= NativeArchive.maximumBytes && sha256.utf8.count == 64
      && sha256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
      && (0..<1_000_000_000).contains(birthNanoseconds)
      && (0..<1_000_000_000).contains(modifiedNanoseconds)
      && (volume?.utf8.count ?? 0) <= 128
  }
  var modificationDate: Date {
    Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1e9)
  }
}

/// Retain a descriptor across decode and fingerprinting; reject an observed
/// replacement or mutation. Hash with a 64 KiB buffer, including same-mtime edits.
final class RecoverySourceReader {
  private struct MetadataChanged: Error {}
  static func withStableMetadata<T>(_ read: () throws -> T) throws -> T {
    for attempt in 0...1 {
      do { return try read() } catch is MetadataChanged {
        try Task.checkCancellation()
        if attempt == 1 { throw DocumentPersistenceConflict.changed }
      }
    }
    preconditionFailure("Bounded source read must return or throw")
  }
  static func capture(_ url: URL) throws -> RecoverySourceFingerprint {
    try withStableMetadata { try RecoverySourceReader(url).finish() }
  }
  private let fd: Int32
  private let url: URL
  private let before: stat
  private let volume: String?
  init(_ url: URL) throws {
    guard url.isFileURL else { throw CraftError.invalid("Choose a local source file.") }
    let fd = url.withUnsafeFileSystemRepresentation {
      $0.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
    }
    guard fd >= 0 else { throw Self.posixError() }
    var info = stat()
    guard fstat(fd, &info) == 0 else {
      let error = Self.posixError(); Darwin.close(fd); throw error
    }
    guard info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0,
      info.st_size <= NativeArchive.maximumBytes
    else {
      Darwin.close(fd)
      throw CraftError.invalid("Recovery verification requires a regular file within the file limit.")
    }
    self.fd = fd; self.url = url; before = info
    volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
  }
  deinit { Darwin.close(fd) }
  func finish() throws -> RecoverySourceFingerprint {
    var hash = SHA256()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    var offset = 0
    while offset < before.st_size {
      try Task.checkCancellation()
      let count = min(buffer.count, Int(before.st_size) - offset)
      let amount = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, count, off_t(offset)) }
      if amount < 0 { if errno == EINTR { continue }; throw Self.posixError() }
      guard amount > 0 else { throw DocumentPersistenceConflict.changed }
      hash.update(data: Data(buffer.prefix(amount)))
      offset += amount
    }
    var after = stat(), path = stat()
    guard fstat(fd, &after) == 0 else { throw Self.posixError() }
    let result = url.withUnsafeFileSystemRepresentation {
      $0.map { fstatat(AT_FDCWD, $0, &path, 0) } ?? -1
    }
    guard result == 0, Self.same(before, after), Self.same(before, path),
      volume == (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
    else { throw DocumentPersistenceConflict.changed }
    guard before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
      before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
      before.st_ctimespec.tv_sec == path.st_ctimespec.tv_sec,
      before.st_ctimespec.tv_nsec == path.st_ctimespec.tv_nsec
    else { throw MetadataChanged() }
    return .init(volume: volume, inode: before.st_ino,
      birthSeconds: before.st_birthtimespec.tv_sec, birthNanoseconds: before.st_birthtimespec.tv_nsec,
      size: Int(before.st_size), modifiedSeconds: before.st_mtimespec.tv_sec,
      modifiedNanoseconds: before.st_mtimespec.tv_nsec,
      sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
  }
  private static func same(_ a: stat, _ b: stat) -> Bool {
    a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
      && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec
      && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
      && a.st_birthtimespec.tv_sec == b.st_birthtimespec.tv_sec
      && a.st_birthtimespec.tv_nsec == b.st_birthtimespec.tv_nsec
  }
  private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
