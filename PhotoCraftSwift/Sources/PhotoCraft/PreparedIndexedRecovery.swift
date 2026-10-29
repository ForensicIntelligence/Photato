import AppKit
import PhotoCraftCore
import PhotoCraftImaging

struct PreparedIndexedRecovery: Sendable {
  let entry: RecoveryIndexEntry
  let contents: NativeArchive.RecoveryContents
  let stamp: RecoveryFileStamp
  let sourceFormat: DocumentIO.Format?

  static func read(_ entry: RecoveryIndexEntry) throws -> Self {
    try read(entry, allowance: .unrestricted)
  }
  static func read(_ entry: RecoveryIndexEntry, allowance: RecoveryReadAllowance) throws -> Self {
    try RecoverySourceReader.withStableMetadata {
      try Task.checkCancellation()
      guard let stamp = try RecoveryFileStamp.read(entry.backupURL), stamp.isRegular else {
        throw RecoveryIndexFailure.invalid
      }
      let reader = try RecoverySourceReader(entry.backupURL)
      let result = try NativeArchive.readRecovery(entry.backupURL, rasterByteLimit: allowance.rasterBytes,
        maximumMetadataBytes: allowance.metadataBytes)
      guard !result.invalidContext, let context = RecoverySnapshotContext.decode(result.context),
        context.recoveryID == entry.recoveryID, context.snapshotID == entry.snapshotID,
        context.documentID == entry.documentID, result.document.id == entry.documentID,
        context.sourceURL == entry.sourceURL else { throw RecoveryIndexFailure.invalid }
      _ = try ColorManagement.space(for: result.document)
      _ = try reader.finish()
      guard try RecoveryFileStamp.read(entry.backupURL) == stamp else { throw RecoveryIndexFailure.changed }
      let sourceFormat = entry.sourceURL.flatMap { source -> DocumentIO.Format? in
        guard (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return DocumentIO.sourceFormat(source)
      }
      try Task.checkCancellation()
      return .init(entry: entry, contents: result, stamp: stamp, sourceFormat: sourceFormat)
    }
  }
  func validateUnchanged() throws {
    guard try RecoveryFileStamp.read(entry.backupURL) == stamp else { throw RecoveryIndexFailure.changed }
  }
}

/// Keep AppKit's real recovery factory and its private change-count/autosave
/// bookkeeping. Only the synchronous native read consumes the prepared value.
/// This scoped, single-use handoff never remains installed across an await.
@MainActor final class RecoveryReadHandoff {
  private static var current: RecoveryReadHandoff?
  let prepared: PreparedIndexedRecovery
  private var consumed = false
  init(_ prepared: PreparedIndexedRecovery) { self.prepared = prepared }

  static func consume(_ url: URL) -> NativeArchive.RecoveryContents? {
    guard let current, !current.consumed,
      RecoverySourceRecord.canonical(url) == RecoverySourceRecord.canonical(current.prepared.entry.backupURL)
    else { return nil }
    current.consumed = true
    return current.prepared.contents
  }
  static func sourceHint(_ source: URL) -> PreparedIndexedRecovery? {
    guard let current, current.prepared.entry.sourceURL == source else { return nil }
    return current.prepared
  }
  static func makeDocument(_ prepared: PreparedIndexedRecovery,
    controller: CraftDocumentController, source: URL?) throws -> CraftNSDocument
  {
    guard current == nil else { throw RecoveryIndexFailure.busy }
    try prepared.validateUnchanged()
    let handoff = RecoveryReadHandoff(prepared)
    current = handoff
    defer { current = nil }
    guard let document = try controller.makeDocument(for: source,
      withContentsOf: prepared.entry.backupURL, ofType: CraftNSDocument.nativeType) as? CraftNSDocument
    else { throw RecoveryIndexFailure.invalid }
    do {
      guard handoff.consumed else { throw RecoveryIndexFailure.invalid }
      try prepared.validateUnchanged()
      return document
    } catch {
      // A failed unpublished factory result must not delete an external backup.
      document.autosavedContentsFileURL = nil
      document.fileURL = nil
      document.close()
      throw error
    }
  }
}
