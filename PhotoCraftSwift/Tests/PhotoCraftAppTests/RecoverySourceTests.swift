import AppKit
import CryptoKit
import Darwin
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class RecoverySourceTests: XCTestCase {
  @MainActor func fixture(format: DocumentIO.Format = .native) throws
    -> (CraftDocumentController, URL, URL, CraftDocument, RecoverySourceRecord)
  {
    let controller = RecoveryLifecycleTests().controller()
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("original." + format.rawValue)
    let model = try EditableLifecycleModel.make(width: 4, height: 3)
    try DocumentIO.encodeForPersistence(model, format: format).write(to: source)
    let opened = try XCTUnwrap(controller.makeDocument(withContentsOf: source,
      ofType: format.typeIdentifier) as? CraftNSDocument)
    let record = try XCTUnwrap(opened.recoverySourceRecord)
    opened.close()
    var edited = model
    edited.layers[0].name = "Recovered edit"
    let backup = folder.appendingPathComponent("snapshot.photato")
    try NativeArchive.writeRecovery(edited, context: record.encoded(), to: backup)
    return (controller, source, backup, edited, record)
  }
  @MainActor func restore(_ controller: CraftDocumentController, source: URL, backup: URL)
    async throws -> CraftNSDocument
  {
    let doc = try XCTUnwrap(controller.makeDocument(for: source, withContentsOf: backup,
      ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
    controller.addDocument(doc)
    await doc.sourceVerificationTask?.value
    return doc
  }
  @MainActor func testAllFormatsRestoreRecordedTypeAndUnchangedSourceCanSave() async throws {
    for format in DocumentIO.Format.allCases where format != .exr { // Existing8-bit fixture; EXR has dedicated32-bit workflow coverage.
      let (controller, source, backup, expected, _) = try fixture(format: format)
      let doc = try await restore(controller, source: source, backup: backup)
      defer { doc.close() }
      XCTAssertEqual(doc.recoverySourceStatus, .unchanged)
      XCTAssertFalse(doc.sourceSaveNeedsReview)
      XCTAssertEqual(doc.persistenceFormat, format)
      XCTAssertEqual(doc.store.document, expected)
      XCTAssertTrue(doc.isDocumentEdited)
      try await doc.persistDocument(to: source, format: format, operation: .saveOperation)
      XCTAssertFalse(doc.isDocumentEdited)
      XCTAssertFalse(doc.isRecoveredSource)
      XCTAssertNotNil(doc.recoverySourceRecord)
      XCTAssertEqual(doc.recoverySourceRecord?.fingerprint.sha256,
        try RecoverySourceReader(source).finish().sha256)
      if format == .native { XCTAssertEqual(try NativeArchive.read(source), expected) }
      try doc.store.executeEditorCommand(.renameLayer(expected.layers[0].id, "Next recovery"))
      try await doc.writeRecoverySnapshot()
      let next = try NativeArchive.readRecovery(XCTUnwrap(doc.autosavedContentsFileURL))
      XCTAssertEqual(RecoverySourceRecord.decode(next.context)?.fingerprint,
        doc.recoverySourceRecord?.fingerprint)
    }
  }
  @MainActor func testChangedSameSizeAndMtimeIsDetectedByContentHash() async throws {
    let (controller, source, backup, expected, record) = try fixture()
    let originalDate = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    let file = try FileHandle(forWritingTo: source)
    try file.seek(toOffset: 16); try file.write(contentsOf: Data([0xEE])); try file.close()
    try FileManager.default.setAttributes([.modificationDate: try XCTUnwrap(originalDate)], ofItemAtPath: source.path)
    let altered = try Data(contentsOf: source)
    XCTAssertNotEqual(try RecoverySourceReader(source).finish().sha256, record.fingerprint.sha256)
    let doc = try await restore(controller, source: source, backup: backup)
    defer { doc.close() }
    XCTAssertEqual(doc.recoverySourceStatus, .changed)
    XCTAssertEqual(doc.store.document, expected)
    XCTAssertTrue(doc.sourceSaveNeedsReview)
    do { try await doc.persistDocument(to: source, format: .native, operation: .saveOperation); XCTFail() }
    catch is RecoverySourceConflict {} catch { XCTFail("Unexpected \(error)") }
    XCTAssertEqual(try Data(contentsOf: source), altered)
  }
  @MainActor func testIdenticalReplacementAndMissingOriginalRequireReview() async throws {
    for missing in [false, true] {
      let (controller, source, backup, expected, _) = try fixture()
      let bytes = try Data(contentsOf: source)
      // Keep the old inode alive at a different name to avoid immediate inode reuse.
      let retained = source.appendingPathExtension("retained")
      try FileManager.default.moveItem(at: source, to: retained)
      if !missing { try bytes.write(to: source) }
      // Deliberately remove the bookmark so this test targets the registered path.
      var record = try XCTUnwrap(RecoverySourceRecord.decode(NativeArchive.readRecovery(backup).context))
      record.bookmark = nil
      try NativeArchive.writeRecovery(expected, context: record.encoded(), to: backup)
      let doc = try await restore(controller, source: source, backup: backup)
      defer { doc.close() }
      XCTAssertEqual(doc.recoverySourceStatus, missing ? .missing : .replaced)
      XCTAssertTrue(doc.sourceSaveNeedsReview)
      XCTAssertEqual(doc.store.document, expected)
      XCTAssertEqual(try Data(contentsOf: retained), bytes)
    }
  }
  @MainActor func testBookmarkFindsMovedOriginal() async throws {
    let (controller, source, backup, expected, record) = try fixture()
    XCTAssertNotNil(record.bookmark)
    let moved = source.deletingLastPathComponent().appendingPathComponent("renamed.photato")
    try FileManager.default.moveItem(at: source, to: moved)
    let doc = try await restore(controller, source: source, backup: backup)
    defer { doc.close() }
    XCTAssertEqual(doc.recoverySourceStatus, .moved)
    XCTAssertEqual(doc.fileURL.map(RecoverySourceRecord.canonical), RecoverySourceRecord.canonical(moved))
    XCTAssertFalse(doc.sourceSaveNeedsReview)
    try await doc.persistDocument(to: moved, format: .native, operation: .saveOperation)
    XCTAssertEqual(try NativeArchive.read(moved), expected)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
  }
  @MainActor func testOccupiedOldPathNeverAuthorizesReplacingAnUnrelatedFile() async throws {
    let (controller, source, backup, expected, _) = try fixture()
    let moved = source.appendingPathExtension("moved")
    try FileManager.default.moveItem(at: source, to: moved)
    let originalBytes = try Data(contentsOf: moved)
    let replacement = Data("unrelated content".utf8)
    try replacement.write(to: source)
    let doc = try await restore(controller, source: source, backup: backup)
    defer { doc.close() }
    // Foundation currently resolves an occupied old path first. The independent
    // fingerprint must refuse it; locating the displaced original requires review.
    XCTAssertEqual(doc.recoverySourceStatus, .replaced)
    XCTAssertTrue(doc.sourceSaveNeedsReview)
    XCTAssertEqual(doc.store.document, expected)
    XCTAssertEqual(try Data(contentsOf: source), replacement)
    XCTAssertEqual(try Data(contentsOf: moved), originalBytes)
  }
  @MainActor func testChangedSourceAfterVerificationRejectsLateSaveAndSaveAsCanProceed() async throws {
    let (controller, source, backup, expected, _) = try fixture()
    let doc = try await restore(controller, source: source, backup: backup)
    defer { doc.close() }
    let changed = Data("external edit during output preparation".utf8)
    do {
      try await doc.persistDocument(to: source, format: .native, operation: .saveOperation,
        encoder: { model, _ in
          try changed.write(to: source)
          return try NativeArchive.encodeChunked(model)
        })
      XCTFail("Save must reject the changed original")
    } catch is RecoverySourceConflict {} catch { XCTFail("Unexpected \(error)") }
    XCTAssertTrue(doc.sourceSaveNeedsReview)
    XCTAssertTrue(doc.isDocumentEdited)
    XCTAssertEqual(try Data(contentsOf: source), changed)
    let destination = source.deletingLastPathComponent().appendingPathComponent("reviewed.photato")
    try await doc.persistDocument(to: destination, format: .native, operation: .saveAsOperation)
    XCTAssertFalse(doc.sourceSaveNeedsReview)
    XCTAssertFalse(doc.isRecoveredSource)
    XCTAssertEqual(try NativeArchive.read(destination), expected)
    XCTAssertEqual(try Data(contentsOf: source), changed)
    XCTAssertNil(try NativeArchive.readRecovery(destination).context)
  }
  @MainActor func testForeignMalformedAndFutureRecordsCannotAuthorizeWriteBack() async throws {
    for mode in 0..<3 {
      let (controller, source, backup, expected, record) = try fixture()
      let bytes: Data
      if mode == 0 {
        var foreign = record; foreign.originalURL = source.appendingPathExtension("foreign"); foreign.bookmark = nil
        bytes = try foreign.encoded()
      } else if mode == 1 {
        var future = record; future.version = 999; bytes = try future.encoded()
      } else { bytes = Data("invalid json".utf8) }
      try NativeArchive.writeRecovery(expected, context: bytes, to: backup)
      let doc = try await restore(controller, source: source, backup: backup)
      defer { doc.close() }
      XCTAssertEqual(doc.recoverySourceStatus, .unverified)
      XCTAssertTrue(doc.sourceSaveNeedsReview)
      XCTAssertEqual(doc.store.document, expected)
      let ordinary = try XCTUnwrap(controller.makeDocument(withContentsOf: backup,
        ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
      defer { ordinary.close() }
      XCTAssertEqual(ordinary.fileURL, backup)
      XCTAssertFalse(ordinary.isRecoveredSource)
      XCTAssertEqual(ordinary.recoverySourceStatus, .none)
      XCTAssertEqual(try DocumentIO.decode(Data(contentsOf: backup), native: true, name: "upload"), expected)
    }
  }
  @MainActor func testCloseCancelsVerificationAndPreservesFormatSpecificReview() async throws {
    let (controller, source, backup, expected, initial) = try fixture(format: .psb)
    var record = initial; record.needsFormatReview = true
    try NativeArchive.writeRecovery(expected, context: record.encoded(), to: backup)
    let closed = try XCTUnwrap(controller.makeDocument(for: source, withContentsOf: backup,
      ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
    let task = closed.sourceVerificationTask
    closed.close()
    await task?.value
    XCTAssertEqual(closed.recoverySourceStatus, .none)
    XCTAssertNil(closed.recoverySourceRecord)
    // Closing removes AppKit's owned recovery file; recreate the disposable fixture.
    try NativeArchive.writeRecovery(expected, context: record.encoded(), to: backup)
    let doc = try await restore(controller, source: source, backup: backup)
    defer { doc.close() }
    XCTAssertEqual(doc.recoverySourceStatus, .unchanged)
    XCTAssertTrue(doc.sourceSaveNeedsReview)
    XCTAssertEqual(doc.persistenceFormat, .psb)
  }
  @MainActor func testRevertRefreshesRecordAndUndoRetainsTheLastSavedSource() async throws {
    let (controller, source, backup, _, _) = try fixture()
    let doc = try await restore(controller, source: source, backup: backup)
    defer { doc.close() }
    var revised = try EditableLifecycleModel.make(width: 4, height: 3)
    revised.layers[0].name = "New original"
    try NativeArchive.write(revised, to: source)
    try await doc.revertDocument()
    XCTAssertEqual(doc.store.document.layers, revised.layers)
    XCTAssertNotEqual(doc.store.document.id, revised.id)  // Revert preserves the editing session's ID.
    XCTAssertFalse(doc.isRecoveredSource)
    XCTAssertEqual(doc.recoverySourceRecord?.fingerprint.sha256,
      try RecoverySourceReader(source).finish().sha256)
    let record = doc.recoverySourceRecord?.fingerprint
    let undone = await doc.store.undo()
    XCTAssertTrue(undone)
    XCTAssertEqual(doc.recoverySourceRecord?.fingerprint, record)
  }
  @MainActor func testHTTPRecoveryContextStateAndSaveConflictMatchNative() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let source = folder.appendingPathComponent("source.photato")
      try await document.persistDocument(to: source, format: .native, operation: .saveAsOperation)
      try document.store.executeEditorCommand(.renameLayer(document.store.document.layers[0].id, "API recovery"))
      try service.share(document)
      let status = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(status, 200)
      _ = try XCTUnwrap(document.recoverySourceRecord)
      let recovered = try NativeArchive.readRecovery(XCTUnwrap(document.autosavedContentsFileURL))
      XCTAssertEqual(recovered.document, document.store.document)
      XCTAssertEqual(RecoverySourceRecord.decode(recovered.context)?.fingerprint,
        document.recoverySourceRecord?.fingerprint)
      let state = document.recoverySourceState
      XCTAssertEqual(Set(state.keys), Set(try XCTUnwrap(AutomationService.recoverySourceSchema["required"] as? [String])))
      XCTAssertFalse(String(describing: state).contains(source.path))
      document.isRecoveredSource = true
      document.recoverySourceStatus = .checking
      service.setDocumentSavesEnabled(true)
      let busy = try await api.edit(service, document, "document.save")
      XCTAssertEqual(busy, 409)
      document.recoverySourceStatus = .unchanged
      document.saveEncoder = { model, _ in
        try Data("changed while saving".utf8).write(to: source)
        return try NativeArchive.encodeChunked(model)
      }
      let rejected = try await api.edit(service, document, "document.save")
      XCTAssertEqual(rejected, 409)
      XCTAssertTrue(document.sourceSaveNeedsReview)
      XCTAssertEqual(document.recoverySourceStatus, .changed)
      XCTAssertEqual(try Data(contentsOf: source), Data("changed while saving".utf8))
      document.saveEncoder = nil
    }
  }
  func testDeletedOriginalUnderAliasedTemporaryDirectoryKeepsSourceAssociation() throws {
    let folder = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
      .appendingPathComponent("photato-source-alias-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("original.photato")
    try Data([1, 2, 3]).write(to: url)
    var record = RecoverySourceRecord.make(url: url, format: .native, needsReview: false,
      fingerprint: try RecoverySourceReader.capture(url))
    record.bookmark = nil
    let alias = URL(fileURLWithPath: "/tmp/" + folder.lastPathComponent + "/original.photato")
    let canonical = RecoverySourceRecord.canonical(url)
    try FileManager.default.removeItem(at: url)
    XCTAssertEqual(RecoverySourceRecord.canonical(url), canonical)
    XCTAssertEqual(RecoverySourceRecord.canonical(alias), canonical)
    XCTAssertEqual(record.verify(registeredURL: alias).status, .missing)
  }
  func testReaderRejectsMutationNonregularAndOutOfBoundsRecords() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("data")
    try Data([1, 2, 3]).write(to: url)
    let reader = try RecoverySourceReader(url)
    try Data([1, 9, 3]).write(to: url)
    XCTAssertThrowsError(try reader.finish())
    XCTAssertThrowsError(try RecoverySourceReader(folder))
    var record = RecoverySourceRecord.make(url: url, format: .native, needsReview: false,
      fingerprint: try RecoverySourceReader(url).finish())
    record.bookmark = Data(count: 65_537)
    XCTAssertNil(RecoverySourceRecord.decode(try record.encoded()))
    record.bookmark = nil; record.fingerprint.sha256 = "invalid"
    XCTAssertNil(RecoverySourceRecord.decode(try record.encoded()))
  }
}


extension RecoverySourceTests {
  func testSourceFingerprintAllowsLargeNativeFileWithoutChangingBackupBudget() throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:folder)}
    let file=folder.appendingPathComponent("owned-large-source.photato")
    XCTAssertTrue(FileManager.default.createFile(atPath:file.path,contents:nil))
    let handle=try FileHandle(forWritingTo:file);defer{try? handle.close()}
    let count=NativeArchive.maximumBytes+1
    try handle.truncate(atOffset:UInt64(count));try handle.synchronize()
    let fingerprint=try RecoverySourceReader.capture(file)
    XCTAssertEqual(fingerprint.size,count);XCTAssertTrue(fingerprint.isValid)
    let record=RecoverySourceRecord.make(url:file,format:.native,needsReview:false,fingerprint:fingerprint)
    XCTAssertTrue(record.isValid);XCTAssertNotNil(RecoverySourceRecord.decode(try record.encoded()))
    let status=record.verify(registeredURL:file,resolveBookmark:false).status
    XCTAssertEqual(status,fingerprint.volume == nil ? .unverified:.unchanged)
    try handle.seek(toOffset:0);try handle.write(contentsOf:Data([1]));try handle.synchronize()
    XCTAssertEqual(record.verify(registeredURL:file,resolveBookmark:false).status,fingerprint.volume == nil ? .unverified:.changed)
    var invalid=fingerprint;invalid.size=NativeArchive.maximumFileBytes+1;XCTAssertFalse(invalid.isValid)
    XCTAssertEqual(NativeArchive.maximumBytes,536_870_912,"Data/metadata/recovery policies remain separate")
  }
}
