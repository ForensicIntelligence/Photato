import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class RecoveryIndexTests: XCTestCase {
  @MainActor func folder() throws -> URL {
    let result = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: result) }
    return result
  }
  @MainActor func controller(_ index: RecoveryIndexStore) -> CraftDocumentController {
    _ = NSApplication.shared
    return CraftDocumentController(workspaces: WorkspaceLibrary(), recoveryIndex: index)
  }
  @MainActor func seed(_ index: RecoveryIndexStore, source: URL? = nil,
    model: CraftDocument? = nil, group: UUID = UUID(), ready: Bool = true)
    throws -> (RecoverySnapshotContext, URL, CraftDocument)
  {
    let model = try model ?? CraftNSDocument.blankModel(width: 4, height: 3, name: "Recovered")
    let record = try source.map {
      RecoverySourceRecord.make(url: $0, format: .native, needsReview: false,
        fingerprint: try RecoverySourceReader.capture($0))
    }
    let context = RecoverySnapshotContext(recoveryID: group, snapshotID: UUID(),
      documentID: model.id, sourceURL: source, source: record)
    let target = try XCTUnwrap(index.backupURL(for: group))
    try index.begin(context, backupURL: target)
    try NativeArchive.writeRecovery(model, context: context.encoded(), to: target)
    if ready { try index.finish(context.snapshotID) }
    return (context, target, model)
  }
  @MainActor func testIntentCommitReloadAndRetirementRetainExactToken() throws {
    let index = RecoveryIndexStore(directoryURL: try folder())
    let (first, target, model) = try seed(index)
    let next = RecoverySnapshotContext(recoveryID: first.recoveryID, snapshotID: UUID(),
      documentID: model.id, sourceURL: nil, source: nil)
    try index.begin(next, backupURL: target)
    let loaded = RecoveryIndexStore(directoryURL: index.directoryURL)
    XCTAssertEqual(loaded.entries.count, 2)
    XCTAssertEqual(IndexedRecoveryCandidate.inspect(loaded.entries[0]).context?.snapshotID, first.snapshotID)
    XCTAssertEqual(IndexedRecoveryCandidate.inspect(loaded.entries[1]).issue, .invalid)
    try NativeArchive.writeRecovery(model, context: next.encoded(), to: target)
    XCTAssertEqual(IndexedRecoveryCandidate.inspect(loaded.entries[1]).context?.snapshotID, next.snapshotID)
    try loaded.finish(next.snapshotID)
    XCTAssertEqual(loaded.entries.count, 1)
    XCTAssertEqual(loaded.entries.first?.state, .ready)
    try loaded.retire(first.recoveryID)
    XCTAssertEqual(loaded.entries.first?.state, .retired)
    let revision = loaded.revision
    try loaded.retire(first.recoveryID)
    XCTAssertEqual(loaded.revision, revision)
    loaded.reload()
    XCTAssertEqual(loaded.revision, revision)
    XCTAssertEqual(loaded.entries.first?.state, .retired)
  }
  @MainActor func testCorruptOversizedAndExternalIndexAreNotOverwritten() throws {
    for bytes in [Data("invalid".utf8), Data(repeating: 32, count: RecoveryIndexStore.maximumBytes + 1)] {
      let root = try folder(), url = root.appendingPathComponent("Index.json")
      try bytes.write(to: url)
      let index = RecoveryIndexStore(directoryURL: root)
      XCTAssertNotNil(index.loadError)
      XCTAssertThrowsError(try seed(index))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    let index = RecoveryIndexStore(directoryURL: try folder())
    let (context, _, _) = try seed(index)
    let other = RecoveryIndexStore(directoryURL: index.directoryURL)
    try other.retire(context.recoveryID)
    let external = try Data(contentsOf: XCTUnwrap(index.indexURL))
    XCTAssertThrowsError(try index.finish(context.snapshotID))
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), external)
    XCTAssertNotNil(index.writeError)
  }
  @MainActor func testIndexRejectsForeignPathsSymlinksAndMismatchedSource() throws {
    let root = try folder(), index = RecoveryIndexStore(directoryURL: root)
    let outside = root.appendingPathComponent("unrelated.photato")
    let context = RecoverySnapshotContext(recoveryID: UUID(), snapshotID: UUID(),
      documentID: UUID(), sourceURL: nil, source: nil)
    XCTAssertThrowsError(try index.begin(context, backupURL: outside))
    let target = try XCTUnwrap(index.backupURL(for: context.recoveryID))
    try Data("unrelated".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
    XCTAssertThrowsError(try index.backupURL(for: context.recoveryID))
    XCTAssertEqual(try Data(contentsOf: outside), Data("unrelated".utf8))
    let (valid, backup, _) = try seed(index)
    let entry = RecoveryIndexEntry(recoveryID: valid.recoveryID, snapshotID: valid.snapshotID,
      documentID: valid.documentID, sequence: 1, backupURL: backup, sourceURL: outside, state: .ready)
    XCTAssertEqual(IndexedRecoveryCandidate.inspect(entry).issue, .invalid)
  }
  @MainActor func testPrivateBackupSurvivesDeletedOriginalFolderAndReopensExactly() async throws {
    let root = try folder(), sourceFolder = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    let source = sourceFolder.appendingPathComponent("original.photato")
    let original = try CraftNSDocument.blankModel(width: 3, height: 2)
    try NativeArchive.write(original, to: source)
    let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("private"))
    let c = controller(index)
    let doc = try XCTUnwrap(c.makeDocument(withContentsOf: source, ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
    c.addDocument(doc)
    try doc.store.executeEditorCommand(.renameLayer(original.activeLayerID!, "Edited"))
    try await doc.writeRecoverySnapshot()
    let target = try XCTUnwrap(doc.autosavedContentsFileURL)
    XCTAssertTrue(target.path.contains("/private/Archives/"))
    XCTAssertEqual(index.entries.first?.state, .ready)
    XCTAssertEqual(try NativeArchive.read(source), original)
    let expected = doc.store.document
    let abandonedBytes = try Data(contentsOf: target)
    // Release the original controller membership without normal-close cleanup to
    // simulate abandoned state. Actual process interruption is qualified separately.
    c.removeDocument(doc)
    doc.autosavedContentsFileURL = nil
    doc.close()
    // AppKit normal close may remove the file even after clearing its property.
    // Recreate only this owned fixture; real SIGKILL coverage does not do this.
    try abandonedBytes.write(to: target)
    try FileManager.default.removeItem(at: sourceFolder)
    try await c.discoverIndexedRecovery(display: false)
    let restored = try XCTUnwrap(c.documents.compactMap { $0 as? CraftNSDocument }.first)
    defer { restored.close() }
    await restored.sourceVerificationTask?.value
    XCTAssertEqual(restored.store.document, expected)
    XCTAssertEqual(restored.recoverySourceStatus, .missing)
    XCTAssertTrue(restored.sourceSaveNeedsReview)
    XCTAssertTrue(restored.isDocumentEdited)
    XCTAssertEqual(index.lastDiscovered, 1)
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastDiscovered, 0)
    XCTAssertEqual(index.lastAlreadyOpen, 1)
    XCTAssertEqual(c.documents.count, 1)
  }
  @MainActor func testDiscoveryChoosesCommittedArchiveOnEitherSideOfIndexFinalization() async throws {
    for publishNew in [false, true] {
      let index = RecoveryIndexStore(directoryURL: try folder())
      let c = controller(index)
      let (old, target, model) = try seed(index)
      var nextModel = model; nextModel.layers[0].name = "New snapshot"
      let next = RecoverySnapshotContext(recoveryID: old.recoveryID, snapshotID: UUID(),
        documentID: model.id, sourceURL: nil, source: nil)
      try index.begin(next, backupURL: target)
      if publishNew { try NativeArchive.writeRecovery(nextModel, context: next.encoded(), to: target) }
      try await c.discoverIndexedRecovery(display: false)
      let doc = try XCTUnwrap(c.documents.first as? CraftNSDocument)
      XCTAssertEqual(doc.store.document, publishNew ? nextModel : model)
      XCTAssertEqual(index.entries.count, 1)
      XCTAssertEqual(index.entries.first?.snapshotID, publishNew ? next.snapshotID : old.snapshotID)
      doc.close()
      try await c.discoverIndexedRecovery(display: false)
      XCTAssertTrue(c.documents.isEmpty)
      XCTAssertTrue(index.entries.isEmpty)
    }
  }
  @MainActor func testCollisionRecoversSeparateUnsavedDocumentAndPreservesOriginal() async throws {
    let root = try folder(), source = root.appendingPathComponent("original.photato")
    let original = try CraftNSDocument.blankModel(width: 3, height: 2)
    try NativeArchive.write(original, to: source)
    let index = RecoveryIndexStore(directoryURL: root.appendingPathComponent("private"))
    var edited = original; edited.layers[0].name = "Uncommitted"
    _ = try seed(index, source: source, model: edited)
    let c = controller(index)
    let open = try c.makeDocument(withContentsOf: source, ofType: CraftNSDocument.nativeType)
    c.addDocument(open)
    defer { for doc in c.documents { doc.close() } }
    try await c.discoverIndexedRecovery(display: false)
    let recovered = try XCTUnwrap(c.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== open })
    XCTAssertNil(recovered.fileURL)
    XCTAssertTrue(recovered.sourceSaveNeedsReview)
    XCTAssertEqual(recovered.store.document, edited)
    XCTAssertEqual(try NativeArchive.read(source), original)
  }
  @MainActor func testMissingPrunesButInvalidAndRetiredBytesArePreserved() async throws {
    let index = RecoveryIndexStore(directoryURL: try folder())
    let c = controller(index)
    let (_, missing, _) = try seed(index)
    try FileManager.default.removeItem(at: missing)
    let (_, invalid, _) = try seed(index)
    let unrelated = Data("unexpected file".utf8); try unrelated.write(to: invalid)
    let (retired, retiredURL, _) = try seed(index)
    let old = try Data(contentsOf: retiredURL)
    try index.retire(retired.recoveryID)
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertTrue(c.documents.isEmpty)
    XCTAssertEqual(index.lastMissing, 1)
    XCTAssertEqual(index.lastInvalid, 1)
    XCTAssertEqual(index.entries.count, 2)
    XCTAssertEqual(try Data(contentsOf: invalid), unrelated)
    XCTAssertEqual(try Data(contentsOf: retiredURL), old)
  }
  @MainActor func testIndexFailureBeforeAndAfterArchiveWriteCanRetry() async throws {
    for failingWrite in [1, 2] {
      var calls = 0
      let index = RecoveryIndexStore(directoryURL: try folder()) { data, url in
        calls += 1
        if calls == failingWrite { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
      }
      let c = controller(index)
      let doc = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 3, height: 2))
      c.addDocument(doc)
      defer { doc.close() }
      try doc.store.executeEditorCommand(.renameLayer(doc.store.document.activeLayerID!, "Edit"))
      do { try await doc.writeRecoverySnapshot(); XCTFail("Injected index write must fail") } catch {}
      XCTAssertTrue(doc.lastRecoveryWriteFailed)
      XCTAssertNotNil(doc.recoveryRegistrationError)
      XCTAssertTrue(doc.hasUnautosavedChanges)
      if failingWrite == 2 {
        let entry = try XCTUnwrap(index.entries.first)
        XCTAssertEqual(entry.state, .intent)
        XCTAssertEqual(IndexedRecoveryCandidate.inspect(entry).context?.snapshotID, entry.snapshotID)
      }
      try await doc.writeRecoverySnapshot()
      XCTAssertNil(doc.recoveryRegistrationError)
      XCTAssertFalse(doc.lastRecoveryWriteFailed)
      XCTAssertEqual(index.entries.count, 1)
      XCTAssertEqual(index.entries.first?.state, .ready)
      XCTAssertEqual(try NativeArchive.read(XCTUnwrap(doc.autosavedContentsFileURL)), doc.store.document)
    }
  }
  @MainActor func testDiscoveryCancellationAndBusyDoNotPublishDocuments() async throws {
    let index = RecoveryIndexStore(directoryURL: try folder())
    let c = controller(index)
    _ = try seed(index)
    var validations = 0
    do {
      try await c.discoverIndexedRecovery(display: false) {
        validations += 1
        if validations >= 3 { throw CancellationError() }
      }
      XCTFail()
    } catch is CancellationError {} catch { XCTFail("\(error)") }
    XCTAssertTrue(c.documents.isEmpty)
    XCTAssertEqual(index.entries.count, 1)
    XCTAssertNotNil(index.discoveryError)
    index.isDiscovering = true
    do { try await c.discoverIndexedRecovery(display: false); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .busy) }
    index.isDiscovering = false
  }
  @MainActor func testHTTPRecoveryPermissionSchemaStaleBusyAndRevocation() async throws {
    let api = AutomationTests()
    try await api.withService { service, doc in
      let index = service.controller.recoveryIndex
      let read = try await api.request(service, path: "/v1/recovery")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: read.1) as? [String: Any])
      XCTAssertEqual(read.0.statusCode, 200)
      let schema = try XCTUnwrap(AutomationService.recoveryDiscoveryCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertFalse(state["canRetry"] as? Bool ?? true)
      let body: [String: Any] = ["revision": index.revision.uuidString]
      let path = "/v1/recovery/retry"
      let denied = try await api.request(service, path: path, body: body)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setRecoveryManagementEnabled(true)
      let generation = service.recoveryManagementGeneration
      for (bad, expected) in [
        (["revision": "bad"] as [String: Any], 400),
        (["revision": UUID().uuidString], 409),
        (["revision": index.revision.uuidString, "path": "/private"], 400),
      ] {
        let response = try await api.request(service, path: path, body: bad)
        XCTAssertEqual(response.0.statusCode, expected)
      }
      let media = try await api.request(service, path: path, body: body, headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      doc.fileOperationBusy = true
      let busy = try await api.request(service, path: path, body: body)
      doc.fileOperationBusy = false
      XCTAssertEqual(busy.0.statusCode, 409)
      let valid = try await api.request(service, path: path, body: body)
      XCTAssertEqual(valid.0.statusCode, 200)
      XCTAssertFalse(doc.isDocumentEdited)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      service.stop()
      XCTAssertFalse(service.recoveryManagementEnabled)
      XCTAssertThrowsError(try service.validateRecoveryManagement(generation))
    }
  }
  @MainActor func testHTTPRecoveryUsesNativeDecoderWithoutAutomaticallySharing() async throws {
    let api = AutomationTests()
    let index = RecoveryIndexStore(directoryURL: try folder())
    let (_, _, model) = try seed(index, ready: false)
    try await api.withService(recoveryIndex: index) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.close() } }
      service.setRecoveryManagementEnabled(true)
      let response = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(response.0.statusCode, 200)
      let doc = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }
        .first { $0 !== original })
      XCTAssertEqual(doc.store.document, model)
      XCTAssertTrue(doc.isDocumentEdited)
      XCTAssertTrue(service.shares.isEmpty)
      XCTAssertEqual(index.lastDiscovered, 1)
      XCTAssertEqual(doc.recoveryRegistrationState["status"] as? String, "ready")
      let stale = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": UUID().uuidString])
      XCTAssertEqual(stale.0.statusCode, 409)
    }
  }
  @MainActor func testHTTPUnreadableIndexReportsSanitizedFailureAndPreservesBytes() async throws {
    let root = try folder(), url = root.appendingPathComponent("Index.json")
    let bytes = Data("invalid private pathname should not be reported".utf8)
    try bytes.write(to: url)
    let index = RecoveryIndexStore(directoryURL: root)
    let api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      service.setRecoveryManagementEnabled(true)
      let response = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(response.0.statusCode, 422)
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains(root.path))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }
  @MainActor func testHTTPExternalIndexChangeRequiresRefreshedRevision() async throws {
    let index = RecoveryIndexStore(directoryURL: try folder())
    let (context, _, _) = try seed(index)
    let api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      let old = index.revision
      let external = RecoveryIndexStore(directoryURL: index.directoryURL)
      try external.retire(context.recoveryID)
      service.setRecoveryManagementEnabled(true)
      let response = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": old.uuidString])
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertNotEqual(index.revision, old)
      XCTAssertEqual(index.entries.first?.state, .retired)
      XCTAssertEqual(service.controller.documents.count, 1)
    }
  }
  @MainActor func testUntitledLaunchRequestBeforeDidFinishWaitsForIndexedRecovery() async throws {
    _ = NSApplication.shared
    let index = RecoveryIndexStore(directoryURL: try folder())
    let (_, _, model) = try seed(index)
    let delegate = AppDelegate(workspaces: WorkspaceLibrary(), recoveryIndex: index)
    let c = delegate.controller
    defer { for doc in c.documents { doc.close() } }
    XCTAssertTrue(delegate.applicationOpenUntitledFile(NSApp))
    XCTAssertTrue(c.pendingUntitledRequest)
    XCTAssertTrue(c.documents.isEmpty)
    c.startIndexedRecovery()
    await c.initialRecoveryTask?.value
    XCTAssertTrue(c.initialRecoveryFinished)
    XCTAssertFalse(c.pendingUntitledRequest)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertEqual((c.documents.first as? CraftNSDocument)?.store.document, model)
  }
}
