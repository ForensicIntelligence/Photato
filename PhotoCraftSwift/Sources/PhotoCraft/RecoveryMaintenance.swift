import AppKit
import Darwin
import Observation
import PhotoCraftCore

struct RecoveryBackupItem: Identifiable, Sendable {
  enum Status: String, Sendable { case available, missing, invalid, unavailable }
  let id: UUID
  let entry: RecoveryIndexEntry
  let registration: RecoveryIndexEntry.State
  let status: Status
  let bytes: Int?
  let modified: Date?
  var name: String { entry.sourceURL?.lastPathComponent ?? "Unsaved document" }

  static func inspect(_ entries: [RecoveryIndexEntry]) -> Self {
    precondition(!entries.isEmpty)
    let sorted = entries.sorted { $0.sequence > $1.sequence }
    var chosen = sorted[0]
    var status: Status = .invalid
    for entry in sorted {
      let result = IndexedRecoveryCandidate.inspect(entry)
      if result.context != nil { chosen = entry; status = .available; break }
      switch result.issue {
      case .missing: status = .missing
      case .unavailable: status = .unavailable
      default: status = .invalid
      }
    }
    let attributes = try? chosen.backupURL.resourceValues(
      forKeys: [.fileSizeKey, .contentModificationDateKey])
    return .init(id: chosen.recoveryID, entry: chosen, registration: sorted[0].state,
      status: status, bytes: attributes?.fileSize, modified: attributes?.contentModificationDate)
  }
}

struct PreparedRecoveryBackup: Sendable {
  let entry: RecoveryIndexEntry
  let model: CraftDocument?
  let fingerprint: RecoverySourceFingerprint

  static func read(_ entries: [RecoveryIndexEntry], decode: Bool) throws -> Self {
    try RecoverySourceReader.withStableMetadata {
      try Task.checkCancellation()
      let item = RecoveryBackupItem.inspect(entries)
      guard item.status == .available else { throw RecoveryIndexFailure.invalid }
      let entry = item.entry
      guard (try? entry.backupURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
      else { throw RecoveryIndexFailure.invalid }
      let reader = try RecoverySourceReader(entry.backupURL)
      let model: CraftDocument?
      if decode {
        let result = try NativeArchive.readRecovery(entry.backupURL)
        guard !result.invalidContext, let context = RecoverySnapshotContext.decode(result.context),
          context.recoveryID == entry.recoveryID, context.snapshotID == entry.snapshotID,
          context.documentID == entry.documentID, result.document.id == entry.documentID,
          context.sourceURL == entry.sourceURL else { throw RecoveryIndexFailure.invalid }
        model = result.document
      } else {
        guard IndexedRecoveryCandidate.inspect(entry).context != nil else { throw RecoveryIndexFailure.invalid }
        model = nil
      }
      return .init(entry: entry, model: model, fingerprint: try reader.finish())
    }
  }

  static func moveToTrash(_ prepared: Self) throws -> URL {
    var coordinationError: NSError?
    var operationError: Error?
    var result: NSURL?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(writingItemAt: prepared.entry.backupURL, options: .forMoving,
      error: &coordinationError) { url in
        do {
          try Task.checkCancellation()
          guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
            IndexedRecoveryCandidate.inspect(prepared.entry).context != nil,
            try RecoverySourceReader.capture(url) == prepared.fingerprint
          else { throw RecoveryIndexFailure.changed }
          try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        } catch { operationError = error }
      }
    if let error = operationError ?? coordinationError { throw error }
    guard let result else { throw RecoveryIndexFailure.invalid }
    return result as URL
  }
}

@MainActor @Observable final class RecoveryMaintenance {
  typealias Reader = @Sendable ([RecoveryIndexEntry], Bool) async throws -> PreparedRecoveryBackup
  typealias Trasher = @Sendable (PreparedRecoveryBackup) async throws -> URL
  unowned let controller: CraftDocumentController
  private(set) var items: [RecoveryBackupItem] = []
  private(set) var inspectedRevision: UUID?
  private(set) var lastError: String?
  private(set) var generation = UUID()
  @ObservationIgnored lazy var salvage = RecoverySalvage(manager: self)
  @ObservationIgnored var reader: Reader = { entries, decode in
    let worker = Task.detached(priority: .utility) { try PreparedRecoveryBackup.read(entries, decode: decode) }
    return try await withTaskCancellationHandler(operation: { try await worker.value },
      onCancel: { worker.cancel() })
  }
  @ObservationIgnored var trasher: Trasher = { prepared in
    let worker = Task.detached(priority: .utility) { try PreparedRecoveryBackup.moveToTrash(prepared) }
    return try await withTaskCancellationHandler(operation: { try await worker.value },
      onCancel: { worker.cancel() })
  }
  init(controller: CraftDocumentController) { self.controller = controller }
  func performSalvage<T>(_ body: () async throws -> T) async throws -> T {
    guard canStart else { throw RecoveryIndexFailure.busy }
    index.isMaintaining = true
    generation = UUID()
    defer { index.isMaintaining = false }
    return try await body()
  }
  var index: RecoveryIndexStore { controller.recoveryIndex }
  var isBusy: Bool { index.isMaintaining }
  var isStale: Bool { inspectedRevision != index.revision }
  var canStart: Bool {
    !index.isBusy && !controller.recoveryPreferencesBusy && controller.documentOpening.canStart
  }
  func isOpen(_ id: UUID) -> Bool {
    controller.documents.contains {
      guard let doc = $0 as? CraftNSDocument else { return false }
      return doc.recoveryGroupID == id || doc.recoverySnapshotContext?.recoveryID == id
    }
  }
  private func check(_ revision: UUID, validate: () throws -> Void) throws {
    try Task.checkCancellation()
    try validate()
    try index.validateCurrentRevision(revision)
  }
  private func group(_ id: UUID) throws -> [RecoveryIndexEntry] {
    let entries = index.entries.filter { $0.recoveryID == id }
    guard !entries.isEmpty else { throw RecoveryIndexFailure.invalid }
    return entries
  }
  private func perform<T>(_ revision: UUID?, validate: () throws -> Void,
    body: (UUID) async throws -> T) async throws -> T
  {
    guard canStart else { throw RecoveryIndexFailure.busy }
    index.reload()
    let revision = revision ?? index.revision
    try check(revision, validate: validate)
    index.isMaintaining = true
    generation = UUID()
    lastError = nil
    defer { index.isMaintaining = false }
    do { return try await body(revision) }
    catch {
      lastError = "The backup operation did not finish. Refresh the list to review its current state."
      throw error
    }
  }
  func refresh(revision: UUID? = nil, validate: () throws -> Void = {}) async throws {
    try await perform(revision, validate: validate) { revision in
      let groups = Dictionary(grouping: index.entries, by: \.recoveryID).values.map { Array($0) }
      let worker = Task.detached(priority: .utility) {
        try groups.map { group in
          try Task.checkCancellation()
          return RecoveryBackupItem.inspect(group)
        }.sorted { $0.entry.sequence > $1.entry.sequence }
      }
      let result = try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
      try check(revision, validate: validate)
      items = result
      inspectedRevision = revision
    }
  }
  func openCopy(_ id: UUID, revision: UUID, display: Bool,
    validate: () throws -> Void = {}) async throws -> CraftNSDocument
  {
    try await perform(revision, validate: validate) { revision in
      let prepared = try await reader(group(id), true)
      try check(revision, validate: validate)
      guard var model = prepared.model else { throw RecoveryIndexFailure.invalid }
      // A recovered copy is a separate document; retain all layer/content values.
      model.id = UUID()
      let document = CraftNSDocument(model: model)
      document.displayName = model.name + " (Recovered Copy)"
      document.updateChangeCount(.changeDone)
      controller.addDocument(document)
      if display { document.makeWindowControllers(); document.showWindows() }
      return document
    }
  }
  func download(_ id: UUID, revision: UUID, maximumBytes: Int,
    validate: () throws -> Void = {}) async throws -> Data
  {
    try await perform(revision, validate: validate) { revision in
      let prepared = try await reader(group(id), true)
      try check(revision, validate: validate)
      guard let model = prepared.model else { throw RecoveryIndexFailure.invalid }
      let worker = Task.detached(priority: .utility) {
        try NativeArchive.encodeChunked(model, maximumBytes: maximumBytes)
      }
      let data = try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
      try check(revision, validate: validate)
      return data
    }
  }
  func saveCopy(_ id: UUID, revision: UUID, to destination: URL) async throws {
    try await perform(revision, validate: {}) { revision in
      guard destination.isFileURL else { throw RecoveryIndexFailure.invalid }
      let canonical = RecoverySourceRecord.canonical(destination)
      guard !index.entries.contains(where: {
        RecoverySourceRecord.canonical($0.backupURL) == canonical
          || $0.sourceURL.map(RecoverySourceRecord.canonical) == canonical
      }), canonical != index.indexURL.map(RecoverySourceRecord.canonical)
      else { throw CraftError.invalid("Choose a new file outside the original and recovery locations.") }
      if let directory = index.directoryURL {
        let base = RecoverySourceRecord.canonical(directory).path + "/"
        guard !canonical.path.hasPrefix(base) else { throw RecoveryIndexFailure.invalid }
      }
      let prepared = try await reader(group(id), true)
      try check(revision, validate: {})
      guard let model = prepared.model else { throw RecoveryIndexFailure.invalid }
      let worker = Task.detached(priority: .utility) {
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        try NativeArchive.write(model, to: destination)
      }
      try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
    }
  }
  func forget(_ id: UUID, revision: UUID, validate: () throws -> Void = {}) async throws {
    try await perform(revision, validate: validate) { revision in
      _ = try group(id)
      guard !isOpen(id) else { throw RecoveryIndexFailure.busy }
      try check(revision, validate: validate)
      try index.removeGroups([id])
      items.removeAll { $0.id == id }
      inspectedRevision = nil
    }
  }
  @discardableResult func trash(_ id: UUID, revision: UUID,
    validate: () throws -> Void = {}) async throws -> URL
  {
    try await perform(revision, validate: validate) { revision in
      guard !isOpen(id) else { throw RecoveryIndexFailure.busy }
      let prepared = try await reader(group(id), false)
      try check(revision, validate: validate)
      guard !isOpen(id) else { throw RecoveryIndexFailure.busy }
      // Persist retirement before moving. An interruption never restores a
      // deliberately discarded backup automatically through this index.
      try index.retireSnapshot(prepared.entry.snapshotID)
      inspectedRevision = nil
      let retiredRevision = index.revision
      let result = try await trasher(prepared)
      // Once the move begins, finish registration cleanup even if API access
      // ends. The response cannot undo a completed filesystem operation.
      try index.validateCurrentRevision(retiredRevision)
      try index.removeGroups([id])
      items.removeAll { $0.id == id }
      return result
    }
  }
  @discardableResult func removeMissing(revision: UUID,
    validate: () throws -> Void = {}) async throws -> Int
  {
    try await perform(revision, validate: validate) { revision in
      let groups = Dictionary(grouping: index.entries, by: \.recoveryID).values.map { Array($0) }
      let worker = Task.detached(priority: .utility) {
        try groups.compactMap { group -> UUID? in
          try Task.checkCancellation()
          return RecoveryBackupItem.inspect(group).status == .missing ? group.first?.recoveryID : nil
        }
      }
      let missing = try await withTaskCancellationHandler(operation: { try await worker.value },
        onCancel: { worker.cancel() })
      try check(revision, validate: validate)
      var ids: Set<UUID> = []
      for id in missing where !isOpen(id) {
        let entry = try group(id)[0]
        var info = stat()
        let result = entry.backupURL.withUnsafeFileSystemRepresentation {
          $0.map { lstat($0, &info) } ?? -1
        }
        if result == -1 && errno == ENOENT { ids.insert(id) }
      }
      try index.removeGroups(ids)
      items.removeAll { ids.contains($0.id) }
      inspectedRevision = nil
      return ids.count
    }
  }
}
