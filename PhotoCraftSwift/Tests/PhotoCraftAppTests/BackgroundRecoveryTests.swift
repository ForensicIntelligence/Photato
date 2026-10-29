import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class BackgroundRecoveryTests: XCTestCase {
  @MainActor func cleanup(_ c: CraftDocumentController) {
    c.recoveryDiscovery.reader = PreparedIndexedRecovery.read
    for doc in c.documents { doc.close() }
  }
  @MainActor func testQueuedOpenWaitsAcrossImmediatelyChainedRecoveryRetries() async throws {
    let helper = RecoveryIndexTests(), root = try helper.folder()
    let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("Recovery"))
    let c = helper.controller(index); defer { cleanup(c) }
    c.initialRecoveryFinished = true
    _ = try helper.seed(index)
    let source = try DocumentOpeningTests().fixture(root)
    let first = OpeningGate(), second = OpeningGate()
    defer { first.release(); second.release() }
    c.recoveryDiscovery.reader = { entry, allowance in
      if !first.started { first.wait() } else { second.wait() }
      try Task.checkCancellation()
      return try PreparedIndexedRecovery.read(entry, allowance: allowance)
    }
    let chained = Task {
      do { try await c.discoverIndexedRecovery(display: false) } catch is CancellationError {}
      try await c.discoverIndexedRecovery(display: false)
    }
    try await DocumentOpeningTests().wait(first)
    var callbacks = 0
    c.openDocument(withContentsOf: source, display: false) { doc, existed, error in
      callbacks += 1; XCTAssertNotNil(doc); XCTAssertFalse(existed); XCTAssertNil(error)
      XCTAssertFalse(index.isBusy)
    }
    // Let the queue suspend on the first recovery's idle continuation.
    try await Task.sleep(for: .milliseconds(30))
    c.recoveryDiscovery.cancel(try XCTUnwrap(c.recoveryDiscovery.state?.id)); first.release()
    try await DocumentOpeningTests().wait(second)
    try await Task.sleep(for: .milliseconds(30))
    XCTAssertEqual(callbacks, 0)
    XCTAssertTrue(c.documentOpening.hasPendingRequests)
    second.release(); try await chained.value
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(callbacks, 1); XCTAssertEqual(c.documents.count, 2)
  }
  @MainActor func testBackgroundCancellationPreservesBytesAndUnblocksQueuedSDKOpen() async throws {
    let helper = RecoveryIndexTests(), root = try helper.folder()
    let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("Recovery"))
    let c = helper.controller(index); defer { cleanup(c) }
    c.initialRecoveryFinished = true // This case exercises manual retry after launch.
    let (_, backup, _) = try helper.seed(index)
    let bytes = try Data(contentsOf: backup), registration = try Data(contentsOf: XCTUnwrap(index.indexURL))
    let gate = OpeningGate(); defer { gate.release() }
    c.recoveryDiscovery.reader = { entry, allowance in
      gate.wait(); try Task.checkCancellation(); return try PreparedIndexedRecovery.read(entry, allowance: allowance)
    }
    let pending = Task { try await c.discoverIndexedRecovery(display: false) }
    try await DocumentOpeningTests().wait(gate)
    XCTAssertFalse(gate.ranOnMain)
    XCTAssertTrue(index.isBusy)
    XCTAssertFalse(c.recoveryDiscovery.canStart)
    let source = try DocumentOpeningTests().fixture(root)
    var calls = 0
    c.openDocument(withContentsOf: source, display: false) { doc, existed, error in
      calls += 1; XCTAssertNotNil(doc); XCTAssertFalse(existed); XCTAssertNil(error)
      XCTAssertFalse(index.isBusy)
    }
    await Task.yield()
    XCTAssertEqual(calls, 0); XCTAssertTrue(c.documents.isEmpty)
    XCTAssertThrowsError(try helper.seed(index))
    let id = try XCTUnwrap(c.recoveryDiscovery.state?.id)
    XCTAssertFalse(c.recoveryDiscovery.cancel(UUID()))
    XCTAssertTrue(c.recoveryDiscovery.cancel(id)); gate.release()
    do { try await pending.value; XCTFail("Cancelled recovery published") } catch is CancellationError {}
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(calls, 1); XCTAssertEqual(c.documents.count, 1)
    XCTAssertFalse(c.recoveryDiscovery.cancel(id))
    XCTAssertEqual(c.recoveryDiscovery.state?.phase, "cancelled")
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), registration)
  }
  @MainActor func testPreparedFactoryPreservesAppKitDirtyAutosaveSourceAndHistoryState() async throws {
    let helper = RecoveryIndexTests(), root = try helper.folder()
    for format in [nil, DocumentIO.Format.native, .psd] {
      let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent(UUID().uuidString))
      let c = helper.controller(index)
      let model = try CraftNSDocument.blankModel(width: 3, height: 2)
      let source = format.map { root.appendingPathComponent("source." + $0.rawValue) }
      if let source, let format { try DocumentIO.encodeForPersistence(model, format: format).write(to: source) }
      let record = try source.map {
        RecoverySourceRecord.make(url: $0, format: format!, needsReview: false,
          fingerprint: try RecoverySourceReader.capture($0))
      }
      let context = RecoverySnapshotContext(recoveryID: UUID(), snapshotID: UUID(),
        documentID: model.id, sourceURL: source, source: record)
      let backup = try XCTUnwrap(index.backupURL(for: context.recoveryID))
      try index.begin(context, backupURL: backup)
      try NativeArchive.writeRecovery(model, context: context.encoded(), to: backup)
      try await c.discoverIndexedRecovery(display: false)
      let d = try XCTUnwrap(c.documents.first as? CraftNSDocument)
      await d.sourceVerificationTask?.value
      XCTAssertEqual(d.store.document, model)
      XCTAssertTrue(d.isDocumentEdited); XCTAssertFalse(d.hasUnautosavedChanges)
      XCTAssertEqual(d.fileURL.map(RecoverySourceRecord.canonical), source.map(RecoverySourceRecord.canonical))
      XCTAssertEqual(d.autosavedContentsFileURL.map(RecoverySourceRecord.canonical),
        RecoverySourceRecord.canonical(backup))
      XCTAssertEqual(d.fileType, (format ?? .native).typeIdentifier)
      XCTAssertEqual(d.recoveryGroupID, context.recoveryID)
      XCTAssertEqual(d.recoverySnapshotContext?.snapshotID, context.snapshotID)
      XCTAssertTrue(d.store.session.undoStack.isEmpty)
      XCTAssertEqual(d.fileModificationDate != nil, source != nil)
      XCTAssertEqual(d.isRecoveredSource, source != nil)
      XCTAssertEqual(d.recoverySourceStatus.rawValue, source == nil ? "none" : "unchanged")
      XCTAssertFalse(d.sourceSaveNeedsReview)
      try d.store.executeEditorCommand(.renameLayer(model.layers[0].id, "After recovery"))
      XCTAssertTrue(d.hasUnautosavedChanges)
      try await d.writeRecoverySnapshot()
      XCTAssertFalse(d.hasUnautosavedChanges); XCTAssertTrue(d.isDocumentEdited)
      XCTAssertEqual(try NativeArchive.read(XCTUnwrap(d.autosavedContentsFileURL)), d.store.document)
      cleanup(c)
    }
  }
  @MainActor func testExternalIndexAndArchiveChangesDuringDecodePreventPublication() async throws {
    let helper = RecoveryIndexTests()
    for change in ["index", "archive", "generation"] {
      let index = RecoveryIndexStore(directoryURL: try helper.folder())
      let c = helper.controller(index); defer { cleanup(c) }
      let (context, backup, _) = try helper.seed(index)
      let gate = OpeningGate(); defer { gate.release() }
      c.recoveryDiscovery.reader = { entry, allowance in
        let prepared = try PreparedIndexedRecovery.read(entry, allowance: allowance); gate.wait(); return prepared
      }
      let pending = Task { try await c.discoverIndexedRecovery(display: false) }
      try await DocumentOpeningTests().wait(gate)
      if change == "index" { try RecoveryIndexStore(directoryURL: index.directoryURL).retire(context.recoveryID) }
      else if change == "archive" { try Data("replacement".utf8).write(to: backup, options: .atomic) }
      else { c.recoveryDiscoveryGeneration = UUID() }
      let before = try Data(contentsOf: backup), registration = try Data(contentsOf: XCTUnwrap(index.indexURL))
      gate.release()
      do { try await pending.value; XCTFail(change) }
      catch { XCTAssertEqual(error as? RecoveryIndexFailure, .changed) }
      XCTAssertTrue(c.documents.isEmpty)
      XCTAssertEqual(c.recoveryDiscovery.state?.phase, "failed")
      XCTAssertEqual(try Data(contentsOf: backup), before)
      XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), registration)
    }
  }
  @MainActor func testSourceCollisionAppearingDuringDecodeCreatesSeparateCopy() async throws {
    let helper = RecoveryIndexTests(), root = try helper.folder()
    let source = try DocumentOpeningTests().fixture(root)
    let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("Recovery"))
    let c = helper.controller(index); defer { cleanup(c) }
    let (_, _, model) = try helper.seed(index, source: source)
    let gate = OpeningGate(); defer { gate.release() }
    c.recoveryDiscovery.reader = { entry, allowance in
      let value = try PreparedIndexedRecovery.read(entry, allowance: allowance); gate.wait(); return value
    }
    let pending = Task { try await c.discoverIndexedRecovery(display: false) }
    try await DocumentOpeningTests().wait(gate)
    // Simulate another AppKit restoration route publishing while decoding.
    let original = try XCTUnwrap(c.makeDocument(withContentsOf: source, ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
    c.addDocument(original)
    try original.store.executeEditorCommand(.renameLayer(original.store.document.layers[0].id, "Unsaved original"))
    let expected = original.store.document
    gate.release(); try await pending.value
    let copy = try XCTUnwrap(c.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== original })
    XCTAssertNil(copy.fileURL); XCTAssertTrue(copy.sourceSaveNeedsReview)
    XCTAssertEqual(copy.store.document, model)
    XCTAssertEqual(original.store.document, expected); XCTAssertTrue(original.isDocumentEdited)
  }
  @MainActor func testPartialCancellationKeepsPublishedDocumentAndRetryRestoresRemainder() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try helper.folder())
    let c = helper.controller(index); defer { cleanup(c) }
    let (slow, backup, a) = try helper.seed(index)
    let (_, _, b) = try helper.seed(index)
    let bytes = try Data(contentsOf: backup), gate = OpeningGate(); defer { gate.release() }
    c.recoveryDiscovery.reader = { entry, allowance in
      if entry.snapshotID == slow.snapshotID { gate.wait(); try Task.checkCancellation() }
      return try PreparedIndexedRecovery.read(entry, allowance: allowance)
    }
    let pending = Task { try await c.discoverIndexedRecovery(display: false) }
    try await DocumentOpeningTests().wait(gate)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertEqual((c.documents.first as? CraftNSDocument)?.store.document, b)
    XCTAssertEqual(c.recoveryDiscovery.state?.completedEntries, 1)
    c.recoveryDiscovery.cancel(try XCTUnwrap(c.recoveryDiscovery.state?.id)); gate.release()
    do { try await pending.value; XCTFail() } catch is CancellationError {}
    XCTAssertEqual(index.lastDiscovered, 1); XCTAssertEqual(index.entries.count, 2)
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
    c.recoveryDiscovery.reader = PreparedIndexedRecovery.read
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastDiscovered, 1); XCTAssertEqual(index.lastAlreadyOpen, 1)
    XCTAssertEqual(Set(c.documents.compactMap { ($0 as? CraftNSDocument)?.store.document.id }), [a.id, b.id])
    XCTAssertEqual(c.recoveryDiscovery.state?.phase, "completed")
  }
  @MainActor func testMissingFileReappearingBeforePruneKeepsRegistration() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try helper.folder())
    let c = helper.controller(index); defer { cleanup(c) }
    _ = try helper.seed(index)
    let (missing, backup, _) = try helper.seed(index)
    let bytes = try Data(contentsOf: backup); try FileManager.default.removeItem(at: backup)
    let gate = OpeningGate(); defer { gate.release() }
    c.recoveryDiscovery.reader = { entry, allowance in gate.wait(); return try PreparedIndexedRecovery.read(entry, allowance: allowance) }
    let pending = Task { try await c.discoverIndexedRecovery(display: false) }
    try await DocumentOpeningTests().wait(gate)
    XCTAssertEqual(index.lastMissing, 1)
    try bytes.write(to: backup); gate.release(); try await pending.value
    XCTAssertTrue(index.entries.contains { $0.snapshotID == missing.snapshotID })
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
  }
  @MainActor func testFullDecodeRejectsContextWithMismatchedDocumentIdentity() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try helper.folder())
    let c = helper.controller(index); defer { cleanup(c) }
    let (context, backup, _) = try helper.seed(index)
    try NativeArchive.writeRecovery(CraftDocument(width: 3, height: 2), context: context.encoded(), to: backup)
    XCTAssertNil(IndexedRecoveryCandidate.inspect(try XCTUnwrap(index.entries.first)).issue)
    let bytes = try Data(contentsOf: backup)
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertTrue(c.documents.isEmpty); XCTAssertEqual(index.lastInvalid, 1)
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
    XCTAssertEqual(index.entries.count, 1); XCTAssertEqual(c.recoveryDiscovery.state?.phase, "completed")
  }
}
