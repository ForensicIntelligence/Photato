import Darwin
import Foundation
import PhotoCraftCore

/// Reads only the known manifest/content-store paths relative to a retained
/// directory descriptor. Linked Smart Objects are metadata, never file requests.
final class PcraftDirectory {
  private struct Identity: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    init(_ value: stat) {
      device = value.st_dev; inode = value.st_ino; mode = value.st_mode; size = value.st_size
      modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
      changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
    }
  }
  private let url: URL
  private let descriptor: Int32
  private let rootIdentity: Identity
  private var observed: [String: Identity] = [:]

  init(_ url: URL) throws {
    try Task.checkCancellation()
    guard url.isFileURL else { throw Self.invalid }
    let fd = url.withUnsafeFileSystemRepresentation {
      $0.map { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) } ?? -1
    }
    guard fd >= 0 else { throw Self.invalid }
    do { rootIdentity = try Self.identity(fd) } catch { Darwin.close(fd); throw error }
    descriptor = fd; self.url = url
  }
  deinit { Darwin.close(descriptor) }
  private static var invalid: CraftError {
    .invalid("Missing, changed, unsafe, or excessive PhotoCraft bundle entry.")
  }
  private static func identity(_ fd: Int32) throws -> Identity {
    var value = stat()
    guard fstat(fd, &value) == 0 else { throw invalid }
    return Identity(value)
  }
  private func record(_ name: String, _ value: Identity) throws {
    if let before = observed[name], before != value { throw Self.invalid }
    observed[name] = value
  }
  private func openEntry(_ path: String) throws -> Int32 {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard path == "manifest.json"
      || (parts.count == 2 && ["tiles", "blobs"].contains(parts[0])
        && parts[1].count == 68 && parts[1].hasSuffix(".zst")
        && parts[1].dropLast(4).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }))
    else { throw Self.invalid }
    var parent = descriptor
    if parts.count == 2 {
      parent = parts[0].withCString { openat(descriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
      guard parent >= 0 else { throw Self.invalid }
      do { try record(parts[0], Self.identity(parent)) }
      catch { Darwin.close(parent); throw error }
    }
    defer { if parent != descriptor { Darwin.close(parent) } }
    let fd = parts.last!.withCString { openat(parent, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
    guard fd >= 0 else { throw Self.invalid }
    return fd
  }
  func read(_ path: String, limit: Int) throws -> Data {
    try Task.checkCancellation()
    guard limit >= 0 else { throw Self.invalid }
    let fd = try openEntry(path); defer { Darwin.close(fd) }
    let before = try Self.identity(fd)
    guard before.mode & S_IFMT == S_IFREG, let count = Int(exactly: before.size),
      count >= 0, count <= limit else { throw Self.invalid }
    try record(path, before)
    var data = Data(count: count), at = 0
    while at < count {
      try Task.checkCancellation()
      let amount = data.withUnsafeMutableBytes {
        pread(fd, $0.baseAddress!.advanced(by: at), min(65536, count - at), off_t(at))
      }
      if amount < 0 && errno == EINTR { continue }
      guard amount > 0 else { throw Self.invalid }
      at += amount
    }
    guard try Self.identity(fd) == before else { throw Self.invalid }
    return data
  }
  func validateUnchanged() throws {
    try Task.checkCancellation()
    var current = stat()
    let result = url.withUnsafeFileSystemRepresentation {
      $0.map { lstat($0, &current) } ?? -1
    }
    guard result == 0, Identity(current) == rootIdentity,
      try Self.identity(descriptor) == rootIdentity else { throw Self.invalid }
    // Reopen all referenced files with the same no-follow policy. This also
    // revalidates intermediate directory identities after the last payload read.
    for (path, before) in Array(observed) where path != "tiles" && path != "blobs" {
      try Task.checkCancellation()
      let fd = try openEntry(path); defer { Darwin.close(fd) }
      guard try Self.identity(fd) == before else { throw Self.invalid }
    }
  }
}
