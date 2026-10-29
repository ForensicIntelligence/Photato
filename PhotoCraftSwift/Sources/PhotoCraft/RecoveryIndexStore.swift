import Darwin
import Foundation
import Observation
import PhotoCraftCore

struct RecoveryIndexEntry: Codable, Equatable, Sendable {
  enum State: String, Codable, Sendable { case intent, ready, retired }
  let recoveryID: UUID
  let snapshotID: UUID
  let documentID: UUID
  let sequence: UInt64
  let backupURL: URL
  let sourceURL: URL?
  var state: State
}

enum RecoveryIndexFailure: LocalizedError, Equatable {
  case unreadable, changed, limit, invalid, busy
  var errorDescription: String? {
    switch self {
    case .unreadable: "The recovery index could not be read. Existing backups have been preserved."
    case .changed: "The recovery index changed outside this session. Retry recovery discovery."
    case .limit: "The recovery index is full. Review recovery information in File Handling."
    case .invalid: "Recovery information does not match the registered backup."
    case .busy: "Recovery discovery is already running."
    }
  }
}

@MainActor @Observable final class RecoveryIndexStore {
  private struct Archive: Codable {
    let version: Int
    let sequence: UInt64
    let entries: [RecoveryIndexEntry]
  }
  static let maximumBytes = 2 * 1024 * 1024
  static let maximumEntries = 512
  static let shared = RecoveryIndexStore(directoryURL:
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first?.appendingPathComponent("Photato/Recovery", isDirectory: true))
  let directoryURL: URL?
  private(set) var entries: [RecoveryIndexEntry] = []
  private(set) var revision = UUID()
  private(set) var loadError: String?
  private(set) var writeError: String?
  var isDiscovering = false
  var isMaintaining = false
  var isBusy: Bool { isDiscovering || isMaintaining }
  var lastDiscovered = 0
  var lastAlreadyOpen = 0
  var lastMissing = 0
  var lastUnavailable = 0
  var lastInvalid = 0
  var lastDeferred = 0
  var discoveryError: String?
  @ObservationIgnored private var sequence: UInt64 = 0
  @ObservationIgnored private var originalBytes: Data?
  @ObservationIgnored private let writer: (Data, URL) throws -> Void
  var indexURL: URL? { directoryURL?.appendingPathComponent("Index.json") }

  init(directoryURL: URL? = nil, writer: ((Data, URL) throws -> Void)? = nil) {
    self.directoryURL = directoryURL
    self.writer = writer ?? { data, url in
      let output = try AtomicFileWriter(to: url, maximumBytes: Self.maximumBytes)
      defer { output.discard() }
      try output.append(data)
      try output.commit()
    }
    reload()
  }
  func reload() {
    guard let indexURL else { return }
    do {
      if let directoryURL,
        (try? directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
      { throw RecoveryIndexFailure.invalid }
      let bytes = try Self.read(indexURL)
      let archive: Archive
      if let bytes {
        archive = try JSONDecoder().decode(Archive.self, from: bytes)
        guard archive.version == 1, archive.entries.count <= Self.maximumEntries,
          Set(archive.entries.map(\.snapshotID)).count == archive.entries.count,
          archive.entries.allSatisfy({ valid($0) && $0.sequence <= archive.sequence })
        else { throw RecoveryIndexFailure.invalid }
      } else { archive = .init(version: 1, sequence: 0, entries: []) }
      let changed = bytes != originalBytes || loadError != nil
      entries = archive.entries
      sequence = archive.sequence
      originalBytes = bytes
      loadError = nil
      writeError = nil
      if changed { revision = UUID() }
    } catch {
      // Keep the old in-memory view and unreadable bytes; never silently replace the index.
      loadError = RecoveryIndexFailure.unreadable.localizedDescription
    }
  }
  func prepareDirectory() throws {
    guard let directoryURL else { return }
    for directory in [directoryURL, directoryURL.appendingPathComponent("Archives", isDirectory: true)] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw RecoveryIndexFailure.invalid
      }
    }
  }
  func backupURL(for recoveryID: UUID) throws -> URL? {
    guard let directoryURL else { return nil }
    try prepareDirectory()
    let target = directoryURL.appendingPathComponent("Archives", isDirectory: true)
      .appendingPathComponent(recoveryID.uuidString.lowercased() + ".photato")
    if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
      throw RecoveryIndexFailure.invalid
    }
    do {
      let context = RecoverySnapshotContext.decode(try NativeArchive.readRecoveryContext(target))
      guard let context, context.recoveryID == recoveryID,
        entries.contains(where: { $0.snapshotID == context.snapshotID && $0.recoveryID == recoveryID })
      else { throw RecoveryIndexFailure.invalid }
    } catch {
      let value = error as NSError
      guard value.domain == NSPOSIXErrorDomain && value.code == Int(ENOENT) else { throw error }
    }
    return target
  }
  func begin(_ context: RecoverySnapshotContext, backupURL: URL) throws {
    guard !isBusy else { throw RecoveryIndexFailure.busy }
    guard sequence < UInt64.max, entries.count < Self.maximumEntries else {
      throw RecoveryIndexFailure.limit
    }
    let entry = RecoveryIndexEntry(recoveryID: context.recoveryID, snapshotID: context.snapshotID,
      documentID: context.documentID, sequence: sequence + 1,
      backupURL: RecoverySourceRecord.canonical(backupURL), sourceURL: context.sourceURL,
      state: .intent)
    guard valid(entry), !entries.contains(where: { $0.snapshotID == context.snapshotID }) else {
      throw RecoveryIndexFailure.invalid
    }
    try commit(entries + [entry], sequence: sequence + 1)
  }
  func finish(_ snapshotID: UUID) throws {
    guard var entry = entries.first(where: { $0.snapshotID == snapshotID }) else {
      throw RecoveryIndexFailure.invalid
    }
    entry.state = .ready
    try commit(entries.filter { $0.recoveryID != entry.recoveryID } + [entry], sequence: sequence)
  }
  func retire(_ recoveryID: UUID) throws {
    guard var latest = entries.filter({ $0.recoveryID == recoveryID })
      .max(by: { $0.sequence < $1.sequence }) else { return }
    if latest.state == .retired { return }
    latest.state = .retired
    try commit(entries.filter { $0.recoveryID != recoveryID } + [latest], sequence: sequence)
  }
  func retireSnapshot(_ snapshotID: UUID) throws {
    guard var entry = entries.first(where: { $0.snapshotID == snapshotID }) else {
      throw RecoveryIndexFailure.invalid
    }
    entry.state = .retired
    let next = entries.filter { $0.recoveryID != entry.recoveryID } + [entry]
    if next != entries { try commit(next, sequence: sequence) }
  }
  func removeGroups(_ ids: Set<UUID>) throws {
    try remove(Set(entries.filter { ids.contains($0.recoveryID) }.map(\.snapshotID)))
  }
  func validateCurrentRevision(_ expected: UUID) throws {
    try validateRevision(expected)
    guard loadError == nil else { throw RecoveryIndexFailure.unreadable }
    if let directoryURL {
      for url in [directoryURL, directoryURL.appendingPathComponent("Archives")] {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        else { throw RecoveryIndexFailure.invalid }
      }
    }
    if let indexURL, try Self.read(indexURL) != originalBytes { throw RecoveryIndexFailure.changed }
    guard entries.allSatisfy(valid) else { throw RecoveryIndexFailure.invalid }
  }
  func remove(_ snapshotIDs: Set<UUID>) throws {
    let next = entries.filter { !snapshotIDs.contains($0.snapshotID) }
    if next != entries { try commit(next, sequence: sequence) }
  }
  func validateRevision(_ expected: UUID) throws {
    guard revision == expected else { throw RecoveryIndexFailure.changed }
  }
  /// Explicit reset never re-registers archives: their absent/retired records may
  /// represent deliberate cleanup. Preserve the exact old bytes first.
  func resetUnreadable() throws -> URL {
    guard loadError != nil, let indexURL, let directoryURL,
      let old = try Self.read(indexURL) else { throw RecoveryIndexFailure.invalid }
    let stamp = try RecoveryFileStamp.read(indexURL)
    try prepareDirectory()
    let preserved = directoryURL.appendingPathComponent("Index-preserved-\(UUID().uuidString).json")
    let copy = try AtomicFileWriter(to: preserved, maximumBytes: Self.maximumBytes)
    defer { copy.discard() }
    try copy.append(old)
    try copy.commit()
    guard try Self.read(indexURL) == old, try RecoveryFileStamp.read(indexURL) == stamp else {
      throw RecoveryIndexFailure.changed
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Archive(version: 1, sequence: 0, entries: []))
    try writer(data, indexURL)
    entries = []; sequence = 0; originalBytes = data
    loadError = nil; writeError = nil; discoveryError = nil; revision = UUID()
    return preserved
  }
  private func valid(_ entry: RecoveryIndexEntry) -> Bool {
    guard entry.sequence > 0, entry.backupURL.isFileURL, entry.backupURL.path.utf8.count <= 16_384,
      entry.sourceURL.map({ $0.isFileURL && $0.path.utf8.count <= 16_384 }) != false
    else { return false }
    guard let directoryURL else { return true }
    let expected = directoryURL.appendingPathComponent("Archives", isDirectory: true)
      .appendingPathComponent(entry.recoveryID.uuidString.lowercased() + ".photato")
    let actualPath = RecoverySourceRecord.canonical(entry.backupURL.deletingLastPathComponent())
      .appendingPathComponent(entry.backupURL.lastPathComponent)
    let expectedPath = RecoverySourceRecord.canonical(expected.deletingLastPathComponent())
      .appendingPathComponent(expected.lastPathComponent)
    return actualPath == expectedPath
  }
  private func commit(_ next: [RecoveryIndexEntry], sequence nextSequence: UInt64) throws {
    guard loadError == nil else { throw RecoveryIndexFailure.unreadable }
    guard next.count <= Self.maximumEntries else { throw RecoveryIndexFailure.limit }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Archive(version: 1, sequence: nextSequence, entries: next))
    guard data.count <= Self.maximumBytes else { throw RecoveryIndexFailure.limit }
    do {
      if let indexURL {
        try prepareDirectory()
        guard try Self.read(indexURL) == originalBytes else { throw RecoveryIndexFailure.changed }
        try writer(data, indexURL)
      }
      entries = next
      sequence = nextSequence
      originalBytes = data
      revision = UUID()
      writeError = nil
    } catch {
      writeError = "Recovery registration could not be updated. Existing backups have been preserved."
      throw error
    }
  }
  private static func read(_ url: URL) throws -> Data? {
    let fd = url.withUnsafeFileSystemRepresentation {
      $0.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) } ?? -1
    }
    guard fd >= 0 else {
      if errno == ENOENT { return nil }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { Darwin.close(fd) }
    var before = stat()
    guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
      before.st_size >= 0, before.st_size <= maximumBytes else { throw RecoveryIndexFailure.invalid }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while result.count <= maximumBytes {
      let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
      if count < 0 {
        if errno == EINTR { continue }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
      if count == 0 { break }
      guard count <= maximumBytes - result.count else { throw RecoveryIndexFailure.limit }
      result.append(contentsOf: buffer.prefix(count))
    }
    var after = stat(), path = stat()
    let found = url.withUnsafeFileSystemRepresentation {
      $0.map { fstatat(AT_FDCWD, $0, &path, AT_SYMLINK_NOFOLLOW) } ?? -1
    }
    guard fstat(fd, &after) == 0, found == 0,
      before.st_dev == path.st_dev, before.st_ino == path.st_ino,
      before.st_size == after.st_size, before.st_size == path.st_size,
      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
      before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
      before.st_mtimespec.tv_sec == path.st_mtimespec.tv_sec,
      before.st_mtimespec.tv_nsec == path.st_mtimespec.tv_nsec,
      before.st_ctimespec.tv_sec == path.st_ctimespec.tv_sec,
      before.st_ctimespec.tv_nsec == path.st_ctimespec.tv_nsec
    else { throw RecoveryIndexFailure.changed }
    return result
  }
}
