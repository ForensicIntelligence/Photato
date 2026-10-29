import AppKit
import Darwin
import Observation
import PhotoCraftCore

/// lstat never follows the selected entry. This is a stale-read guard, not a
/// filesystem compare-and-swap against non-cooperating writers.
struct RecoveryFileStamp: Equatable, Sendable {
  let device: Int32
  let inode: UInt64
  let mode: UInt16
  let size: Int64
  let modifiedSeconds: Int
  let modifiedNanoseconds: Int
  let changedSeconds: Int
  let changedNanoseconds: Int
  var isDirectory: Bool { mode & S_IFMT == S_IFDIR }
  var isRegular: Bool { mode & S_IFMT == S_IFREG }
  static func read(_ url: URL) throws -> Self? {
    var value = stat()
    let result = url.withUnsafeFileSystemRepresentation { $0.map { lstat($0, &value) } ?? -1 }
    if result != 0 {
      if errno == ENOENT { return nil }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return .init(device: value.st_dev, inode: value.st_ino, mode: value.st_mode, size: value.st_size,
      modifiedSeconds: value.st_mtimespec.tv_sec, modifiedNanoseconds: value.st_mtimespec.tv_nsec,
      changedSeconds: value.st_ctimespec.tv_sec, changedNanoseconds: value.st_ctimespec.tv_nsec)
  }
}

struct RecoverySalvageSnapshot: Equatable, Sendable {
  let directory: URL
  let root: RecoveryFileStamp?
  let archives: RecoveryFileStamp?
  let index: RecoveryFileStamp?
  static func read(_ directory: URL) throws -> Self {
    let root = try RecoveryFileStamp.read(directory)
    guard root?.isDirectory != false else { throw RecoveryIndexFailure.invalid }
    let archives = try RecoveryFileStamp.read(directory.appendingPathComponent("Archives"))
    guard archives?.isDirectory != false else { throw RecoveryIndexFailure.invalid }
    return .init(directory: directory, root: root, archives: archives,
      index: try RecoveryFileStamp.read(directory.appendingPathComponent("Index.json")))
  }
  func validate() throws {
    guard try Self.read(directory) == self else { throw RecoveryIndexFailure.changed }
  }
}

struct RecoverySalvageItem: Identifiable, Sendable {
  let id: UUID
  let url: URL
  let stamp: RecoveryFileStamp
  let name: String
  let contextKind: String
  let sourceURL: URL?
  var registration: String = "unknown"
}

struct RecoverySalvageScan: Sendable {
  static let maximumEntries = 1024
  let snapshot: RecoverySalvageSnapshot
  let items: [RecoverySalvageItem]
  let examined: Int

  static func read(_ directory: URL) throws -> Self {
    let snapshot = try RecoverySalvageSnapshot.read(directory)
    guard snapshot.archives != nil else { return .init(snapshot: snapshot, items: [], examined: 0) }
    let archives = directory.appendingPathComponent("Archives", isDirectory: true)
    // Stream the immediate directory; do not recursively enumerate or allocate an
    // unbounded contentsOfDirectory array before enforcing the entry limit.
    let handle = archives.withUnsafeFileSystemRepresentation { $0.flatMap { opendir($0) } }
    guard let handle else { throw RecoveryIndexFailure.unreadable }
    defer { closedir(handle) }
    var items: [RecoverySalvageItem] = []
    var examined = 0
    while true {
      try Task.checkCancellation()
      errno = 0
      guard let entry = readdir(handle) else {
        guard errno == 0 else { throw RecoveryIndexFailure.unreadable }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
          String(cString: $0)
        }
      }
      if name == "." || name == ".." { continue }
      examined += 1
      guard examined <= maximumEntries else { throw RecoveryIndexFailure.limit }
      let url = archives.appendingPathComponent(name)
      guard url.pathExtension.lowercased() == "photato",
        let stamp = try RecoveryFileStamp.read(url), stamp.isRegular,
        stamp.size >= 0, stamp.size <= NativeArchive.maximumBytes else { continue }
      var kind = "unverified"
      var source: URL?
      do {
        if let data = try NativeArchive.readRecoveryContext(url) {
          if let context = RecoverySnapshotContext.decode(data) {
            kind = "current"; source = context.sourceURL
          } else if let legacy = RecoverySourceRecord.decode(data) {
            kind = "legacy"; source = legacy.originalURL
          }
        } else { kind = "none" }
      } catch is CancellationError { throw CancellationError() }
      catch { /* A damaged context may coexist with a fully readable document. */ }
      guard try RecoveryFileStamp.read(url) == stamp else { throw RecoveryIndexFailure.changed }
      items.append(.init(id: UUID(), url: url, stamp: stamp,
        name: source?.lastPathComponent ?? name, contextKind: kind, sourceURL: source))
    }
    try snapshot.validate()
    return .init(snapshot: snapshot, items: items.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent },
      examined: examined)
  }
  static func decode(_ item: RecoverySalvageItem) throws -> CraftDocument {
    try Task.checkCancellation()
    guard try RecoveryFileStamp.read(item.url) == item.stamp, item.stamp.isRegular else {
      throw RecoveryIndexFailure.changed
    }
    let reader = try RecoverySourceReader(item.url)
    // Copy only document contents. Recovery provenance is never adopted here,
    // including when its independent checksum/version is invalid.
    let model = try NativeArchive.read(item.url)
    _ = try reader.finish()
    guard try RecoveryFileStamp.read(item.url) == item.stamp else { throw RecoveryIndexFailure.changed }
    return model
  }
}

@MainActor @Observable final class RecoverySalvage {
  unowned let manager: RecoveryMaintenance
  private(set) var revision = UUID()
  private(set) var items: [RecoverySalvageItem] = []
  private(set) var examined = 0
  private(set) var lastError: String?
  private(set) var snapshot: RecoverySalvageSnapshot?
  private var indexRevision: UUID?
  @ObservationIgnored var scanner: @Sendable (URL) async throws -> RecoverySalvageScan = { url in
    let worker = Task.detached(priority: .utility) { try RecoverySalvageScan.read(url) }
    return try await withTaskCancellationHandler(operation: { try await worker.value },
      onCancel: { worker.cancel() })
  }
  @ObservationIgnored var reader: @Sendable (RecoverySalvageItem) async throws -> CraftDocument = { item in
    let worker = Task.detached(priority: .utility) { try RecoverySalvageScan.decode(item) }
    return try await withTaskCancellationHandler(operation: { try await worker.value },
      onCancel: { worker.cancel() })
  }
  init(manager: RecoveryMaintenance) { self.manager = manager }
  var isStale: Bool { snapshot == nil || lastError != nil || indexRevision != manager.index.revision }
  var canScan: Bool { manager.canStart && manager.index.directoryURL != nil }
  var canResetIndex: Bool {
    canScan && !isStale && manager.controller.documents.isEmpty && manager.index.loadError != nil
      && snapshot?.index?.isRegular == true
      && (snapshot?.index?.size ?? Int64.max) <= RecoveryIndexStore.maximumBytes
  }
  private func check(_ expected: UUID, validate: () throws -> Void, scanned: Bool = true) throws {
    try Task.checkCancellation()
    try validate()
    guard revision == expected else { throw RecoveryIndexFailure.changed }
    if scanned {
      guard !isStale, let snapshot else { throw RecoveryIndexFailure.changed }
      try snapshot.validate()
    }
  }
  private func perform<T>(_ operation: () async throws -> T) async throws -> T {
    do {
      return try await manager.performSalvage {
        lastError = nil
        return try await operation()
      }
    } catch {
      lastError = "Recovery salvage did not finish. Scan again to review the current files."
      throw error
    }
  }
  func scan(revision expected: UUID, validate: () throws -> Void = {}) async throws {
    try await perform {
      try check(expected, validate: validate, scanned: false)
      guard let directory = manager.index.directoryURL else { throw RecoveryIndexFailure.invalid }
      manager.index.reload()
      let token = manager.index.revision
      let before = try RecoverySalvageSnapshot.read(directory)
      let result = try await scanner(directory)
      try check(expected, validate: validate, scanned: false)
      try result.snapshot.validate()
      guard token == manager.index.revision, before == result.snapshot else {
        throw RecoveryIndexFailure.changed
      }
      let registrations = Dictionary(grouping: manager.index.entries) {
        RecoverySourceRecord.canonical($0.backupURL)
      }
      items = result.items.map { candidate in
        var item = candidate
        if manager.index.loadError == nil {
          let records = registrations[RecoverySourceRecord.canonical(item.url)] ?? []
          item.registration = records.isEmpty ? "unregistered"
            : records.allSatisfy { $0.state == .retired } ? "retired" : "registered"
        }
        return item
      }
      snapshot = result.snapshot; examined = result.examined
      indexRevision = token; revision = UUID()
    }
  }
  private func model(_ id: UUID, revision expected: UUID, validate: () throws -> Void) async throws
    -> CraftDocument
  {
    try check(expected, validate: validate)
    guard let item = items.first(where: { $0.id == id }) else { throw RecoveryIndexFailure.invalid }
    let model = try await reader(item)
    try check(expected, validate: validate)
    return model
  }
  func openCopy(_ id: UUID, revision expected: UUID, display: Bool,
    validate: () throws -> Void = {}) async throws -> CraftNSDocument
  {
    try await perform {
      var model = try await model(id, revision: expected, validate: validate)
      model.id = UUID()
      let document = CraftNSDocument(model: model)
      document.displayName = model.name + " (Recovered Copy)"
      document.updateChangeCount(.changeDone)
      manager.controller.addDocument(document)
      if display { document.makeWindowControllers(); document.showWindows() }
      return document
    }
  }
  func download(_ id: UUID, revision expected: UUID, maximumBytes: Int,
    validate: () throws -> Void = {}) async throws -> Data
  {
    try await perform {
      let model = try await model(id, revision: expected, validate: validate)
      let worker = Task.detached(priority: .utility) {
        try NativeArchive.encodeChunked(model, maximumBytes: maximumBytes)
      }
      let result = try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
      try check(expected, validate: validate)
      return result
    }
  }
  func saveCopy(_ id: UUID, revision expected: UUID, to destination: URL) async throws {
    try await perform {
      let model = try await model(id, revision: expected, validate: {})
      guard destination.isFileURL, let directory = manager.index.directoryURL else {
        throw RecoveryIndexFailure.invalid
      }
      let target = RecoverySourceRecord.canonical(destination)
      let base = RecoverySourceRecord.canonical(directory)
      guard target != base, !target.path.hasPrefix(base.path + "/"),
        !items.contains(where: { $0.sourceURL.map(RecoverySourceRecord.canonical) == target }),
        !manager.controller.documents.contains(where: {
          $0.fileURL.map(RecoverySourceRecord.canonical) == target
        }) else { throw RecoveryIndexFailure.invalid }
      let worker = Task.detached(priority: .utility) {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        try NativeArchive.write(model, to: destination)
      }
      try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
    }
  }
  @discardableResult func resetIndex(revision expected: UUID,
    validate: () throws -> Void = {}) async throws -> URL
  {
    try await perform {
      try check(expected, validate: validate)
      guard manager.controller.documents.isEmpty else { throw RecoveryIndexFailure.busy }
      let preserved = try manager.index.resetUnreadable()
      items = []; snapshot = nil; indexRevision = nil; examined = 0; revision = UUID()
      return preserved
    }
  }
}
