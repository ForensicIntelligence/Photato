import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class RecoverySalvageTests: XCTestCase {
  @MainActor func fixture() throws -> (URL, RecoveryIndexStore, RecoverySnapshotContext, URL, CraftDocument) {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let index = RecoveryIndexStore(directoryURL: folder.appendingPathComponent("recovery"))
    let (context, backup, model) = try RecoveryIndexTests().seed(index)
    return (folder, index, context, backup, model)
  }
  @MainActor func controller(_ index: RecoveryIndexStore) -> CraftDocumentController {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), recoveryIndex: index)
    controller.initialRecoveryFinished = true
    return controller
  }
  @MainActor func damage(_ index: RecoveryIndexStore) throws -> Data {
    let bad = Data("an interrupted index, preserved exactly".utf8)
    try bad.write(to: XCTUnwrap(index.indexURL))
    index.reload()
    XCTAssertNotNil(index.loadError)
    return bad
  }
  @MainActor func testUnreadableIndexAllowsExactCopyExportAndResetWithoutRestoration() async throws {
    let (folder, index, _, backup, model) = try fixture()
    let bytes = try Data(contentsOf: backup), bad = try damage(index)
    let c = controller(index), salvage = c.recoveryMaintenance.salvage
    try await salvage.scan(revision: salvage.revision)
    XCTAssertEqual(salvage.items.count, 1); XCTAssertTrue(c.documents.isEmpty)
    XCTAssertTrue(salvage.canResetIndex)
    let item = try XCTUnwrap(salvage.items.first)
    XCTAssertEqual(item.contextKind, "current"); XCTAssertEqual(item.registration, "unknown")
    let output = try await salvage.download(item.id, revision: salvage.revision, maximumBytes: 1_000_000)
    XCTAssertEqual(output, try NativeArchive.encodeChunked(model))
    let saved = folder.appendingPathComponent("copy.photato")
    try await salvage.saveCopy(item.id, revision: salvage.revision, to: saved)
    XCTAssertEqual(try Data(contentsOf: saved), output)
    let copy = try await salvage.openCopy(item.id, revision: salvage.revision, display: false)
    var normalized = copy.store.document; normalized.id = model.id
    XCTAssertEqual(normalized, model); XCTAssertNotEqual(copy.store.document.id, model.id)
    XCTAssertNil(copy.fileURL); XCTAssertNil(copy.recoverySnapshotContext)
    XCTAssertTrue(copy.isDocumentEdited); XCTAssertFalse(salvage.canResetIndex)
    do { try await salvage.resetIndex(revision: salvage.revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .busy) }
    copy.close()
    try await salvage.scan(revision: salvage.revision)
    let preserved = try await salvage.resetIndex(revision: salvage.revision)
    XCTAssertEqual(try Data(contentsOf: preserved), bad)
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
    XCTAssertTrue(index.entries.isEmpty); XCTAssertNil(index.loadError)
    XCTAssertTrue(salvage.isStale)
    let fresh = RecoveryIndexStore(directoryURL: index.directoryURL)
    XCTAssertNil(fresh.loadError); XCTAssertTrue(fresh.entries.isEmpty)
    _ = try RecoveryIndexTests().seed(fresh)
    XCTAssertEqual(fresh.entries.count, 1)
  }
  @MainActor func testForgottenRetiredLegacyAndPlainArchivesStayManual() async throws {
    let (folder, index, context, backup, model) = try fixture()
    try index.removeGroups([context.recoveryID])
    let (retired, _, _) = try RecoveryIndexTests().seed(index, model: model)
    try index.retire(retired.recoveryID)
    let source = folder.appendingPathComponent("legacy-original.photato")
    try NativeArchive.write(model, to: source)
    let record = RecoverySourceRecord.make(url: source, format: .native, needsReview: false,
      fingerprint: try RecoverySourceReader.capture(source))
    let archives = backup.deletingLastPathComponent()
    let legacy = archives.appendingPathComponent("legacy.photato")
    try NativeArchive.writeRecovery(model, context: record.encoded(), to: legacy)
    let plain = archives.appendingPathComponent("plain.photato")
    try NativeArchive.encode(model).write(to: plain)
    let malformed = archives.appendingPathComponent("invalid-context.photato")
    try NativeArchive.writeRecovery(model, context: Data("invalid context".utf8), to: malformed)
    let c = controller(index), s = c.recoveryMaintenance.salvage
    let before = try Data(contentsOf: XCTUnwrap(index.indexURL))
    try await s.scan(revision: s.revision)
    XCTAssertEqual(s.items.count, 5); XCTAssertTrue(c.documents.isEmpty)
    XCTAssertEqual(Set(s.items.map(\.contextKind)), Set(["current", "legacy", "none", "unverified"]))
    XCTAssertEqual(s.items.first { $0.url == backup }?.registration, "unregistered")
    XCTAssertEqual(s.items.filter { $0.registration == "retired" }.count, 1)
    for item in s.items {
      let data = try await s.download(item.id, revision: s.revision, maximumBytes: 1_000_000)
      XCTAssertEqual(try NativeArchive.decode(data), model)
    }
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), before)
    XCTAssertFalse(s.canResetIndex)
    do { try await s.resetIndex(revision: s.revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .invalid) }
    try await s.scan(revision: s.revision)
    let id = try XCTUnwrap(s.items.first { $0.url == legacy }?.id)
    do { try await s.saveCopy(id, revision: s.revision, to: source); XCTFail() } catch {}
    XCTAssertEqual(try NativeArchive.read(source), model)
  }
  @MainActor func testSymlinksDirectoriesAndUnrelatedFilesAreNeverRead() async throws {
    let (folder, index, _, backup, _) = try fixture()
    let archives = backup.deletingLastPathComponent()
    let outside = folder.appendingPathComponent("outside.photato")
    try FileManager.default.copyItem(at: backup, to: outside)
    try FileManager.default.createSymbolicLink(at: archives.appendingPathComponent("link.photato"),
      withDestinationURL: outside)
    try FileManager.default.createDirectory(at: archives.appendingPathComponent("nested.photato"), withIntermediateDirectories: false)
    try Data([1, 2]).write(to: archives.appendingPathComponent("unrelated.txt"))
    let scan = try RecoverySalvageScan.read(try XCTUnwrap(index.directoryURL))
    XCTAssertEqual(scan.examined, 4); XCTAssertEqual(scan.items.count, 1)
    let moved = folder.appendingPathComponent("moved-archives")
    try FileManager.default.moveItem(at: archives, to: moved)
    try FileManager.default.createSymbolicLink(at: archives, withDestinationURL: moved)
    XCTAssertThrowsError(try RecoverySalvageScan.read(try XCTUnwrap(index.directoryURL)))
  }
  @MainActor func testScanLimitPublishesNothingAndEmptyMissingDirectoryWorks() async throws {
    let (_, index, _, backup, _) = try fixture()
    let c = controller(index), s = c.recoveryMaintenance.salvage
    for n in 0..<RecoverySalvageScan.maximumEntries {
      try Data().write(to: backup.deletingLastPathComponent().appendingPathComponent("unrelated-\(n)"))
    }
    do { try await s.scan(revision: s.revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .limit) }
    XCTAssertTrue(s.items.isEmpty); XCTAssertTrue(s.isStale)
    let empty = RecoveryIndexStore(directoryURL: index.directoryURL!.appendingPathComponent("absent"))
    let otherController = controller(empty), other = otherController.recoveryMaintenance.salvage
    try await other.scan(revision: other.revision)
    XCTAssertFalse(other.isStale); XCTAssertTrue(other.items.isEmpty)
    XCTAssertFalse(other.canResetIndex)
  }
  @MainActor func testChangedArchiveIndexAndStaleScanRejectWithoutPublication() async throws {
    let (_, index, _, backup, _) = try fixture(), c = controller(index)
    let s = c.recoveryMaintenance.salvage
    let old = s.revision
    try await s.scan(revision: old)
    do { try await s.scan(revision: old); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .changed) }
    try await s.scan(revision: s.revision)
    let item = try XCTUnwrap(s.items.first)
    try Data("bad payload".utf8).write(to: backup)
    do { _ = try await s.openCopy(item.id, revision: s.revision, display: false); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .changed) }
    XCTAssertTrue(c.documents.isEmpty)
    try await s.scan(revision: s.revision)
    let bad = try XCTUnwrap(s.items.first)
    do { _ = try await s.download(bad.id, revision: s.revision, maximumBytes: 1_000_000); XCTFail() }
    catch {}
    try await s.scan(revision: s.revision)
    try Data("externally changed".utf8).write(to: XCTUnwrap(index.indexURL))
    do { try await s.resetIndex(revision: s.revision); XCTFail() }
    catch { XCTAssertEqual(error as? RecoveryIndexFailure, .changed) }
    XCTAssertTrue(c.documents.isEmpty)
  }
  @MainActor func testResetFailurePreservesOldIndexAndArchiveWithReusableCopy() async throws {
    let (_, original, _, backup, _) = try fixture()
    let bad = try damage(original), bytes = try Data(contentsOf: backup)
    var fail = true
    let index = RecoveryIndexStore(directoryURL: original.directoryURL) { data, url in
      if fail { throw CocoaError(.fileWriteOutOfSpace) }
      try data.write(to: url, options: .atomic)
    }
    let c = controller(index), s = c.recoveryMaintenance.salvage
    try await s.scan(revision: s.revision)
    do { try await s.resetIndex(revision: s.revision); XCTFail() } catch {}
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(index.indexURL)), bad)
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
    let copies = try FileManager.default.contentsOfDirectory(at: XCTUnwrap(index.directoryURL),
      includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Index-preserved-") }
    XCTAssertEqual(copies.count, 1); XCTAssertEqual(try Data(contentsOf: copies[0]), bad)
    let reloaded = RecoveryIndexStore(directoryURL: index.directoryURL)
    XCTAssertNotNil(reloaded.loadError)
    fail = false
    try await s.scan(revision: s.revision)
    _ = try await s.resetIndex(revision: s.revision)
    XCTAssertNil(index.loadError); XCTAssertEqual(try Data(contentsOf: backup), bytes)
  }
  @MainActor func testOversizedOrSymlinkIndexCanScanButCannotReset() async throws {
    for symlink in [false, true] {
      let (folder, index, _, backup, _) = try fixture()
      let indexURL = try XCTUnwrap(index.indexURL)
      let data = Data(repeating: 42, count: RecoveryIndexStore.maximumBytes + 1)
      if symlink {
        try FileManager.default.removeItem(at: indexURL)
        let external = folder.appendingPathComponent("external")
        try data.write(to: external)
        try FileManager.default.createSymbolicLink(at: indexURL, withDestinationURL: external)
      } else { try data.write(to: indexURL) }
      index.reload()
      let c = controller(index), s = c.recoveryMaintenance.salvage
      try await s.scan(revision: s.revision)
      XCTAssertEqual(s.items.first?.url, backup); XCTAssertFalse(s.canResetIndex)
      do { try await s.resetIndex(revision: s.revision); XCTFail() } catch {}
      XCTAssertEqual(try Data(contentsOf: indexURL), data)
    }
  }
  @MainActor func testScanCancellationAndExternalIndexChangeWhileWorkerRuns() async throws {
    for cancel in [true, false] {
      let (_, index, _, _, _) = try fixture()
      let c = controller(index), s = c.recoveryMaintenance.salvage, gate = OpeningGate()
      s.scanner = { url in
        try await Task.detached {
          gate.wait()
          return try RecoverySalvageScan.read(url)
        }.value
      }
      let pending = Task { try await s.scan(revision: s.revision) }
      try await DocumentOpeningTests().wait(gate)
      XCTAssertTrue(index.isMaintaining); XCTAssertFalse(c.documentOpening.canStart)
      if cancel { pending.cancel() }
      else { try Data("changed during scan".utf8).write(to: XCTUnwrap(index.indexURL)) }
      gate.release()
      do { try await pending.value; XCTFail() } catch {}
      XCTAssertTrue(s.items.isEmpty); XCTAssertFalse(index.isMaintaining)
    }
  }
}
