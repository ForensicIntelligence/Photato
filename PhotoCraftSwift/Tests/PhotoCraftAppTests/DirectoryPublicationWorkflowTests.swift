import AppKit
import Darwin
import Foundation
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore

final class DirectoryPublicationWorkflowTests: XCTestCase {
  final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: (CraftDocument?, String, Int)?
    func record(_ document: CraftDocument?, _ error: NSError) {
      lock.withLock { recorded = (document, error.domain, error.code) }
    }
    func value() -> (CraftDocument?, String, Int)? { lock.withLock { recorded } }
  }
  func encoder(_ probe: Probe) -> RecoveryEncoder {
    { model, url, context in
      var operations = AtomicFileWriter.Operations()
      operations.synchronizeDirectory = { _ in errno = EIO; return -1 }
      do {
        try NativeArchive.write(model, to: url, recoveryContext: context) {
          try AtomicFileWriter(to: $0, maximumBytes: $1, operations: operations)
        }
      } catch {
        // Observe the writer's actual target before enclosing AppKit cleanup.
        probe.record(try? NativeArchive.read(url), error as NSError)
        throw error
      }
    }
  }
  @MainActor func testNativeRecoveryDirectoryFailureRetainsEditingStateAndCanRetry() async throws {
    _ = NSApplication.shared
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 4, height: 3))
    defer { document.close() }
    let layer = try XCTUnwrap(document.store.document.activeLayerID)
    try document.store.executeEditorCommand(.renameLayer(layer, "Previous backup"))
    try await document.writeRecoverySnapshot()
    let backup = try XCTUnwrap(document.autosavedContentsFileURL)
    let previous = try Data(contentsOf: backup)
    try document.store.executeEditorCommand(.renameLayer(layer, "Current edits"))
    let model = document.store.document, revision = document.store.revision
    let history = document.store.session.undoStack.count
    let probe = Probe(); document.recoveryEncoder = encoder(probe)
    do { try await document.writeRecoverySnapshot(); XCTFail("Expected directory persistence failure") }
    catch {
      XCTAssertTrue(error.localizedDescription.contains("unconfirmed"), String(describing: error))
      XCTAssertEqual((error as NSError).domain, AtomicFileWriter.PublicationFailure.errorDomain)
      XCTAssertEqual((error as NSError).userInfo["PhotatoFilePublished"] as? Bool, true)
    }
    let observed = try XCTUnwrap(probe.value())
    XCTAssertEqual(observed.0, model)
    XCTAssertEqual(observed.1, AtomicFileWriter.PublicationFailure.errorDomain)
    XCTAssertEqual(observed.2, Int(EIO))
    XCTAssertEqual(try Data(contentsOf: backup), previous)
    XCTAssertEqual(document.store.document, model)
    XCTAssertEqual(document.store.revision, revision)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertTrue(document.lastRecoveryWriteFailed)
    XCTAssertTrue(document.hasUnautosavedChanges)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertFalse(document.fileOperationBusy)
    document.recoveryEncoder = NativeRecoveryWriting.write
    try await document.writeRecoverySnapshot()
    XCTAssertFalse(document.lastRecoveryWriteFailed)
    XCTAssertFalse(document.hasUnautosavedChanges)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertEqual(try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), model)
    XCTAssertEqual(document.store.session.undoStack.count, history)
  }
  @MainActor func testHTTPRecoveryDirectoryFailureReportsErrorAndSharedStateThenRetries() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      defer { document.close() }
      let layer = try XCTUnwrap(document.store.document.activeLayerID)
      try document.store.executeEditorCommand(.renameLayer(layer, "Previous"))
      try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let first = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(first, 200)
      let backup = try XCTUnwrap(document.autosavedContentsFileURL)
      let previous = try Data(contentsOf: backup)
      try document.store.executeEditorCommand(.renameLayer(layer, "Newer"))
      let model = document.store.document, revision = document.store.revision
      let history = document.store.session.undoStack.count
      let probe = Probe(); document.recoveryEncoder = encoder(probe)
      let response = try await api.request(service, path: "/v1/documents/\(id)/commands",
        body: ["command": "document.autosave", "revision": service.revision(document.store), "parameters": [:]])
      XCTAssertEqual(response.0.statusCode, 422)
      XCTAssertTrue(String(decoding: response.1, as: UTF8.self).contains("unconfirmed"), String(decoding: response.1, as: UTF8.self))
      XCTAssertEqual(try XCTUnwrap(probe.value()).0, model)
      XCTAssertEqual(try Data(contentsOf: backup), previous)
      XCTAssertEqual(document.store.document, model)
      XCTAssertEqual(document.store.revision, revision)
      XCTAssertEqual(document.store.session.undoStack.count, history)
      let current = try await api.request(service, path: "/v1/documents/\(id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: current.1) as? [String: Any])
      let recovery = try XCTUnwrap(state["recovery"] as? [String: Any])
      XCTAssertEqual(recovery["lastWriteFailed"] as? Bool, true)
      XCTAssertEqual(recovery["hasUnautosavedChanges"] as? Bool, true)
      XCTAssertEqual(recovery["isWriting"] as? Bool, false)
      document.recoveryEncoder = NativeRecoveryWriting.write
      let retry = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(retry, 200)
      XCTAssertEqual(try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), model)
      XCTAssertFalse(document.lastRecoveryWriteFailed)
      let caps = try await api.request(service, path: "/v1/capabilities")
      let values = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any])
      let policy = try XCTUnwrap(values["atomicPersistence"] as? [String: Any])
      let synchronization = try XCTUnwrap(policy["directorySynchronization"] as? [String: Any])
      XCTAssertEqual(synchronization["required"] as? Bool, true)
      XCTAssertEqual(synchronization["phase"] as? String, "after-relative-rename")
      let failure = try XCTUnwrap(policy["postPublicationFailure"] as? [String: Any])
      XCTAssertEqual(failure["domain"] as? String, AtomicFileWriter.PublicationFailure.errorDomain)
      XCTAssertEqual(failure["filePublished"] as? Bool, true)
      XCTAssertTrue((failure["scope"] as? String)?.contains("NSDocument") == true)
    }
  }
  @MainActor func testHTTPPreferencesDirectoryFailureKeepsConfirmedTimerAndRejectsStaleDiskRetry() async throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("RecoverySettings.json")
    let initial = RecoveryPreferencesStore(url: target)
    try initial.commit(.init(enabled: false, intervalMinutes: 5), revision: initial.revision)
    let before = try Data(contentsOf: target)
    let failing = RecoveryPreferencesStore(url: target) { data, url in
      var operations = AtomicFileWriter.Operations()
      operations.synchronizeDirectory = { _ in errno = EIO; return -1 }
      let writer = try AtomicFileWriter(to: url, operations: operations)
      defer { writer.discard() }; try writer.append(data); try writer.commit()
    }
    let revision = failing.revision, recentRevision = failing.recentRevision
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }, recoveryPreferences: failing) { service, document in
      service.setPreferenceChangesEnabled(true)
      let body: [String: Any] = ["revision": revision.uuidString, "enabled": true, "intervalMinutes": 15]
      let response = try await api.request(service, path: "/v1/preferences/recovery", body: body)
      XCTAssertEqual(response.0.statusCode, 422)
      XCTAssertTrue(String(decoding: response.1, as: UTF8.self).contains("unconfirmed"))
      XCTAssertNotEqual(try Data(contentsOf: target), before)
      XCTAssertEqual(failing.value, .init(enabled: false, intervalMinutes: 5))
      XCTAssertEqual(failing.revision, revision)
      XCTAssertEqual(failing.recentRevision, recentRevision)
      XCTAssertEqual(service.controller.autosavingDelay, 0)
      XCTAssertFalse(document.isDocumentEdited)
      let retry = try await api.request(service, path: "/v1/preferences/recovery", body: body)
      XCTAssertEqual(retry.0.statusCode, 409)
      XCTAssertTrue(String(decoding: retry.1, as: UTF8.self).contains("restart Photato"))
      // An explicit new store models restart; no silent disk adoption during failure.
      let reloaded = RecoveryPreferencesStore(url: target)
      XCTAssertNil(reloaded.loadError)
      XCTAssertEqual(reloaded.value, .init(enabled: true, intervalMinutes: 15))
      try reloaded.commit(.init(enabled: false, intervalMinutes: 5), revision: reloaded.revision)
      XCTAssertEqual(RecoveryPreferencesStore(url: target).value, .init(enabled: false, intervalMinutes: 5))
    }
  }
  @MainActor func testRecentFileDirectoryFailureDoesNotClaimDiskHistoryWasPreserved() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("RecoverySettings.json")
    let settings = RecoveryPreferencesStore(url: target) { data, url in
      var operations = AtomicFileWriter.Operations()
      operations.synchronizeDirectory = { _ in errno = EIO; return -1 }
      let writer = try AtomicFileWriter(to: url, operations: operations)
      defer { writer.discard() }; try writer.append(data); try writer.commit()
    }
    let owned = folder.appendingPathComponent("owned.photato")
    try NativeArchive.write(try EditableLifecycleModel.make(width: 4, height: 3), to: owned)
    let revision = settings.revision, recentRevision = settings.recentRevision
    settings.remember(owned)
    XCTAssertTrue(settings.recentDocuments.isEmpty)
    XCTAssertEqual(settings.revision, revision)
    XCTAssertEqual(settings.recentRevision, recentRevision)
    XCTAssertTrue(settings.recentWriteError?.contains("may already contain the new history") == true)
    XCTAssertTrue(settings.recentWriteError?.contains("Restart Photato") == true)
    let reloaded = RecoveryPreferencesStore(url: target)
    XCTAssertNil(reloaded.loadError)
    XCTAssertEqual(reloaded.recentDocuments.map(\.url), [owned.standardizedFileURL.resolvingSymlinksInPath()])
  }
  @MainActor func testRecoveryPublicationFailureIsScopedToOneSnapshotAndConsumedOnce() throws {
    let state = RecoveryWriteState(), model = try EditableLifecycleModel.make(width: 4, height: 3)
    let id = state.begin(model, context: nil, encoder: NativeRecoveryWriting.write)
    let other = UUID(), failure = AtomicFileWriter.PublicationFailure(posixCode: EIO)
    state.recordPublicationFailure(failure, for: other)
    XCTAssertNil(state.takePublicationFailure(for: id))
    state.recordPublicationFailure(failure, for: id)
    state.finish(id)
    XCTAssertNil(state.current())
    XCTAssertNil(state.takePublicationFailure(for: other))
    XCTAssertEqual(state.takePublicationFailure(for: id)?.posixCode, EIO)
    XCTAssertNil(state.takePublicationFailure(for: id))
    let next = state.begin(model, context: nil, encoder: NativeRecoveryWriting.write)
    state.recordPublicationFailure(failure, for: id)
    state.finish(next)
    XCTAssertNil(state.takePublicationFailure(for: next))
    let third = state.begin(model, context: nil, encoder: NativeRecoveryWriting.write)
    state.recordPublicationFailure(failure, for: third)
    state.finish(third)
    let fourth = state.begin(model, context: nil, encoder: NativeRecoveryWriting.write)
    XCTAssertNil(state.takePublicationFailure(for: third))
    state.finish(fourth)
  }
}
