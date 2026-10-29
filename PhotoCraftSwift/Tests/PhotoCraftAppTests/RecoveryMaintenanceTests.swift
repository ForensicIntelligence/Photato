import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class RecoveryMaintenanceTests: XCTestCase {
  @MainActor func folder() throws -> URL {
    let url = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  @MainActor func controller(_ index: RecoveryIndexStore) -> CraftDocumentController {
    _ = NSApplication.shared
    let c = CraftDocumentController(workspaces: WorkspaceLibrary(), recoveryIndex: index)
    c.initialRecoveryFinished = true
    return c
  }
  @MainActor func seed(_ index: RecoveryIndexStore, source: URL? = nil)
    throws -> (RecoverySnapshotContext, URL, CraftDocument)
  {
    let model = try CraftNSDocument.blankModel(width: 4, height: 3, name: "Recovered")
    if let source { try NativeArchive.write(model, to: source) }
    return try RecoveryIndexTests().seed(index, source: source, model: model)
  }

  @MainActor func testInspectionGroupsInterruptedIntentsAndPreservesAllFiles() async throws {
    let root = try folder(), index = RecoveryIndexStore(directoryURL: root)
    let c = controller(index), manager = c.recoveryMaintenance
    let (first, target, model) = try seed(index)
    let next = RecoverySnapshotContext(recoveryID: first.recoveryID, snapshotID: UUID(),
      documentID: model.id, sourceURL: nil, source: nil)
    try index.begin(next, backupURL: target)
    let (retired, retiredURL, _) = try seed(index)
    try index.retire(retired.recoveryID)
    let (_, missingURL, _) = try seed(index)
    try FileManager.default.removeItem(at: missingURL)
    let (_, invalidURL, _) = try seed(index)
    let invalid = Data("not a recovery archive".utf8)
    try invalid.write(to: invalidURL)
    let originals = try [target, retiredURL, invalidURL].map { try Data(contentsOf: $0) }
    let indexBytes = try Data(contentsOf: XCTUnwrap(index.indexURL)), revision = index.revision
    try await manager.refresh()
    XCTAssertEqual(manager.items.count, 4)
    XCTAssertEqual(manager.items.filter { $0.status == .available }.count, 2)
    XCTAssertEqual(manager.items.filter { $0.status == .missing }.count, 1)
    XCTAssertEqual(manager.items.filter { $0.status == .invalid }.count, 1)
    XCTAssertEqual(manager.items.first { $0.id == first.recoveryID }?.entry.snapshotID, first.snapshotID)
    XCTAssertEqual(manager.items.first { $0.id == retired.recoveryID }?.registration, .retired)
    XCTAssertFalse(manager.isStale); XCTAssertFalse(manager.isBusy)
    XCTAssertEqual(index.revision, revision)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), indexBytes)
    XCTAssertEqual(try [target, retiredURL, invalidURL].map { try Data(contentsOf: $0) }, originals)
    XCTAssertTrue(c.documents.isEmpty)
  }
  @MainActor func testCopyAndExportKeepContentsWithoutRecoverySourceAssociation() async throws {
    let root = try folder(), source = root.appendingPathComponent("original.photato")
    let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("recovery"))
    let c = controller(index), manager = c.recoveryMaintenance
    let (context, target, model) = try seed(index, source: source)
    try NativeArchive.write(model, to: source)
    let sourceBytes = try Data(contentsOf: source), backupBytes = try Data(contentsOf: target)
    let revision = index.revision
    let copy = try await manager.openCopy(context.recoveryID, revision: revision, display: false)
    defer { copy.close() }
    var normalized = copy.store.document; normalized.id = model.id
    XCTAssertEqual(normalized, model)
    XCTAssertNotEqual(copy.store.document.id, model.id)
    XCTAssertNil(copy.fileURL); XCTAssertNil(copy.autosavedContentsFileURL)
    XCTAssertNil(copy.recoverySourceRecord); XCTAssertNil(copy.recoverySnapshotContext)
    XCTAssertNotEqual(copy.recoveryGroupID, context.recoveryID)
    XCTAssertTrue(copy.isDocumentEdited); XCTAssertFalse(copy.sourceSaveNeedsReview)
    XCTAssertTrue(c.recoveryPreferences.recentDocuments.isEmpty)
    let output = try await manager.download(context.recoveryID, revision: revision, maximumBytes: 1_000_000)
    XCTAssertEqual(output, try NativeArchive.encodeChunked(model))
    let destination = root.appendingPathComponent("saved-copy.photato")
    try await manager.saveCopy(context.recoveryID, revision: revision, to: destination)
    XCTAssertEqual(try Data(contentsOf: destination), output)
    XCTAssertNil(try NativeArchive.readRecovery(destination).context)
    for url in [source, target, try XCTUnwrap(index.indexURL)] {
      do { try await manager.saveCopy(context.recoveryID, revision: revision, to: url); XCTFail("Protected destination") }
      catch {}
    }
    XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    XCTAssertEqual(try Data(contentsOf: target), backupBytes)
    XCTAssertEqual(index.revision, revision)
  }
  @MainActor func testCorruptPayloadFailsFullCopyButInspectionCannotPromiseDecode() async throws {
    let index = RecoveryIndexStore(directoryURL: try folder())
    let c = controller(index), manager = c.recoveryMaintenance
    let (context, target, _) = try seed(index)
    var bytes = try Data(contentsOf: target)
    bytes[bytes.count - 1] ^= 0xff
    try bytes.write(to: target)
    let revision = index.revision
    do { _ = try await manager.openCopy(context.recoveryID, revision: revision, display: false); XCTFail() }
    catch {}
    XCTAssertTrue(c.documents.isEmpty)
    XCTAssertEqual(try Data(contentsOf: target), bytes)
    XCTAssertEqual(index.revision, revision)
    XCTAssertNotNil(manager.lastError)
    do { _ = try await manager.download(context.recoveryID, revision: revision, maximumBytes: 16); XCTFail() }
    catch {}
  }
  @MainActor func testForgetPreservesInvalidBytesAndProtectsOpenGroups() async throws {
    let index = RecoveryIndexStore(directoryURL: try folder()), c = controller(index)
    let (context, target, model) = try seed(index)
    let doc = CraftNSDocument(model: model)
    doc.recoveryGroupID = context.recoveryID
    c.addDocument(doc)
    let revision = index.revision
    do { try await c.recoveryMaintenance.forget(context.recoveryID, revision: revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .busy) }
    do { try await c.recoveryMaintenance.trash(context.recoveryID, revision: revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .busy) }
    c.removeDocument(doc); doc.recoveryGroupID = UUID(); doc.close()
    let invalid = Data("unrecognized replacement".utf8); try invalid.write(to: target)
    do { try await c.recoveryMaintenance.trash(context.recoveryID, revision: revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .invalid) }
    try await c.recoveryMaintenance.forget(context.recoveryID, revision: revision)
    XCTAssertTrue(index.entries.isEmpty)
    XCTAssertEqual(try Data(contentsOf: target), invalid)
    XCTAssertTrue(RecoveryIndexStore(directoryURL: index.directoryURL).entries.isEmpty)
  }
  @MainActor func testFullIndexCanRemoveMissingRecordsAndResumeRegistration() async throws {
    let root = try folder(), index = RecoveryIndexStore(), c = controller(index)
    let model = try CraftNSDocument.blankModel(width: 2, height: 2)
    let preserved = root.appendingPathComponent("available.photato")
    var keep: RecoverySnapshotContext!
    for n in 0..<RecoveryIndexStore.maximumEntries {
      let context = RecoverySnapshotContext(recoveryID: UUID(), snapshotID: UUID(),
        documentID: model.id, sourceURL: nil, source: nil)
      let url = n == 0 ? preserved : root.appendingPathComponent("missing-\(n)")
      try index.begin(context, backupURL: url); try index.finish(context.snapshotID)
      if n == 0 { keep = context; try NativeArchive.writeRecovery(model, context: context.encoded(), to: url) }
    }
    let next = RecoverySnapshotContext(recoveryID: UUID(), snapshotID: UUID(),
      documentID: model.id, sourceURL: nil, source: nil)
    XCTAssertThrowsError(try index.begin(next, backupURL: root.appendingPathComponent("next"))) {
      XCTAssertEqual($0 as? RecoveryIndexFailure, .limit)
    }
    let bytes = try Data(contentsOf: preserved)
    let count = try await c.recoveryMaintenance.removeMissing(revision: index.revision)
    XCTAssertEqual(count, 511)
    XCTAssertEqual(index.entries.map(\.recoveryID), [keep.recoveryID])
    try index.begin(next, backupURL: root.appendingPathComponent("next"))
    XCTAssertEqual(index.entries.count, 2)
    XCTAssertEqual(try Data(contentsOf: preserved), bytes)
  }
  @MainActor func testTrashRetiresMatchingOldSnapshotBeforeMoveAndCleansRegistration() async throws {
    let root = try folder(), index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("recovery"))
    let c = controller(index), manager = c.recoveryMaintenance
    let (first, target, model) = try seed(index)
    let next = RecoverySnapshotContext(recoveryID: first.recoveryID, snapshotID: UUID(),
      documentID: model.id, sourceURL: nil, source: nil)
    try index.begin(next, backupURL: target)
    let bytes = try Data(contentsOf: target), moved = root.appendingPathComponent("owned-trash-fixture.photato")
    manager.trasher = { prepared in
      let reloaded = await MainActor.run { RecoveryIndexStore(directoryURL: index.directoryURL) }
      await MainActor.run {
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.snapshotID, first.snapshotID)
        XCTAssertEqual(reloaded.entries.first?.state, .retired)
      }
      XCTAssertEqual(prepared.entry.snapshotID, first.snapshotID)
      try FileManager.default.moveItem(at: prepared.entry.backupURL, to: moved)
      return moved
    }
    let result = try await manager.trash(first.recoveryID, revision: index.revision)
    XCTAssertEqual(result, moved)
    XCTAssertEqual(try Data(contentsOf: moved), bytes)
    XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    XCTAssertTrue(index.entries.isEmpty)
  }
  @MainActor func testTrashFailuresOnEitherSideOfMoveLeaveRecoverableJournal() async throws {
    for afterMove in [false, true] {
      let root = try folder()
      var failWrites = false
      let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("recovery")) { data, url in
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
      }
      let c = controller(index), manager = c.recoveryMaintenance
      let (context, target, _) = try seed(index)
      let bytes = try Data(contentsOf: target), moved = root.appendingPathComponent("moved.photato")
      manager.trasher = { prepared in
        if !afterMove { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.moveItem(at: prepared.entry.backupURL, to: moved)
        await MainActor.run { failWrites = true }
        return moved
      }
      do { try await manager.trash(context.recoveryID, revision: index.revision); XCTFail() }
      catch {}
      XCTAssertFalse(manager.isBusy)
      XCTAssertEqual(index.entries.first?.state, .retired)
      let reloaded = RecoveryIndexStore(directoryURL: index.directoryURL)
      XCTAssertEqual(reloaded.entries.first?.state, .retired)
      if afterMove {
        XCTAssertEqual(try Data(contentsOf: moved), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        failWrites = false
        let removed = try await manager.removeMissing(revision: index.revision)
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(index.entries.isEmpty)
      } else {
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        try await manager.refresh()
        XCTAssertEqual(manager.items.first?.status, .available)
      }
    }
  }
  @MainActor func testAtomicForgetFailureAndExternalChangePreserveRegistration() async throws {
    let root = try folder()
    var fail = false
    let index = RecoveryIndexStore(directoryURL: root) { data, url in
      if fail { throw CocoaError(.fileWriteOutOfSpace) }
      try data.write(to: url, options: .atomic)
    }
    let c = controller(index)
    let (context, target, _) = try seed(index)
    let bytes = try Data(contentsOf: target), indexBytes = try Data(contentsOf: XCTUnwrap(index.indexURL))
    let revision = index.revision
    fail = true
    do { try await c.recoveryMaintenance.forget(context.recoveryID, revision: revision); XCTFail() }
    catch {}
    XCTAssertEqual(index.revision, revision)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), indexBytes)
    fail = false
    let external = RecoveryIndexStore(directoryURL: root)
    try external.retire(context.recoveryID)
    do { try await c.recoveryMaintenance.forget(context.recoveryID, revision: revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .changed) }
    XCTAssertEqual(index.entries.first?.state, .retired)
    XCTAssertEqual(try Data(contentsOf: target), bytes)
  }
  @MainActor func testSymlinkIsNotReadTrashedOrPruned() async throws {
    let root = try folder(), index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("recovery"))
    let c = controller(index)
    let (context, target, _) = try seed(index)
    let outside = root.appendingPathComponent("outside.photato")
    try FileManager.default.moveItem(at: target, to: outside)
    let bytes = try Data(contentsOf: outside)
    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
    try await c.recoveryMaintenance.refresh()
    XCTAssertEqual(c.recoveryMaintenance.items.first?.status, .invalid)
    do { try await c.recoveryMaintenance.trash(context.recoveryID, revision: index.revision); XCTFail() }
    catch {}
    let count = try await c.recoveryMaintenance.removeMissing(revision: index.revision)
    XCTAssertEqual(count, 0)
    XCTAssertEqual(try Data(contentsOf: outside), bytes)
    XCTAssertEqual(index.entries.count, 1)
  }
  @MainActor func testBusyMaintenanceProtectsOpeningClosingAutosaveAndFileCommands() async throws {
    let index = RecoveryIndexStore(directoryURL: try folder()), c = controller(index)
    let (context, _, model) = try seed(index)
    let document = CraftNSDocument(model: model); c.addDocument(document)
    defer { document.close() }
    index.isMaintaining = true
    defer { index.isMaintaining = false }
    XCTAssertFalse(c.documentOpening.canStart)
    XCTAssertFalse(document.canRunFileCommand)
    XCTAssertTrue(c.recoveryPreferencesBusy)
    do { try await c.discoverIndexedRecovery(display: false); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .busy) }
    do { _ = try await c.recoveryMaintenance.openCopy(context.recoveryID, revision: index.revision, display: false); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .busy) }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      document.autosave(withImplicitCancellability: true) { error in
        XCTAssertNotNil(error)
        continuation.resume()
      }
    }
  }
}
