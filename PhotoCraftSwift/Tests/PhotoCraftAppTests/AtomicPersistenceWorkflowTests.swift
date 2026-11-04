import AppKit
import Darwin
import Foundation
import XCTest

@testable import PhotoCraft
@testable import PhotoCraftCore

final class AtomicPersistenceWorkflowTests: XCTestCase {
  enum Failure: Sendable { case write, flush, rename }
  func encoder(_ failure: Failure) -> RecoveryEncoder {
    { model, url, context in
      var operations = AtomicFileWriter.Operations()
      switch failure {
      case .write:
        operations.write = { _, _, _, _ in
          errno = ENOSPC
          return -1
        }
      case .flush:
        operations.fullSynchronize = { _ in
          errno = EIO
          return -1
        }
      case .rename:
        operations.rename = { _, _, _ in
          errno = EACCES
          return -1
        }
      }
      try NativeArchive.write(model, to: url, recoveryContext: context) {
        try AtomicFileWriter(to: $0, maximumBytes: $1, operations: operations)
      }
    }
  }
  func testRasterPreparedOutputUsesSamePermissionsAndSymlinkSemantics() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try DocumentSaveWorkflowTests().fixture()
    for format in [DocumentIO.Format.png, .jpeg, .tiff] {
      let output = try DocumentIO.prepareOutput(model, format: format, persistence: false)
      guard case .data(let bytes) = output else { return XCTFail("Expected raster Data") }
      let target = folder.appendingPathComponent(format.rawValue)
      try Data([9]).write(to: target)
      try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
      let link = folder.appendingPathComponent(format.rawValue + "-link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
      try output.write(to: link)
      XCTAssertEqual(try Data(contentsOf: target), bytes)
      XCTAssertEqual(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
      XCTAssertEqual(
        (try FileManager.default.attributesOfItem(atPath: target.path))[.posixPermissions] as? Int,
        0o640)
    }
  }
  @MainActor func testNativeRecoveryWriteFlushAndRenameFailuresRetainPriorSnapshotAndRetry()
    async throws
  {
    _ = NSApplication.shared
    for failure in [Failure.write, .flush, .rename] {
      let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 4, height: 3))
      defer { document.close() }
      let layer = try XCTUnwrap(document.store.document.activeLayerID)
      try document.store.executeEditorCommand(.renameLayer(layer, "Previous backup"))
      try await document.writeRecoverySnapshot()
      let backup = try XCTUnwrap(document.autosavedContentsFileURL)
      let previous = try Data(contentsOf: backup)
      try document.store.executeEditorCommand(.renameLayer(layer, "Current edits"))
      let model = document.store.document
      let revision = document.store.revision
      let history = document.store.session.undoStack.count
      document.recoveryEncoder = encoder(failure)
      do {
        try await document.writeRecoverySnapshot()
        XCTFail("Expected storage error")
      } catch {}
      XCTAssertEqual(try Data(contentsOf: backup), previous)
      XCTAssertEqual(document.store.document, model)
      XCTAssertEqual(document.store.revision, revision)
      XCTAssertEqual(document.store.session.undoStack.count, history)
      XCTAssertTrue(document.lastRecoveryWriteFailed)
      XCTAssertTrue(document.hasUnautosavedChanges)
      XCTAssertFalse(document.recoveryWriteBusy)
      XCTAssertFalse(document.fileOperationBusy)
      document.recoveryEncoder = NativeRecoveryWriting.write
      try await document.writeRecoverySnapshot()
      XCTAssertEqual(
        try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), model)
      XCTAssertFalse(document.lastRecoveryWriteFailed)
    }
  }
  @MainActor func testHTTPRecoveryFlushFailureMatchesNativeStateAndCanRetry() async throws {
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
      let model = document.store.document
      let revision = document.store.revision
      document.recoveryEncoder = encoder(.flush)
      let failed = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(failed, 422)
      XCTAssertEqual(try Data(contentsOf: backup), previous)
      XCTAssertEqual(document.store.document, model)
      XCTAssertEqual(document.store.revision, revision)
      let response = try await api.request(service, path: "/v1/documents/\(id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual((state["recovery"] as? [String: Any])?["lastWriteFailed"] as? Bool, true)
      document.recoveryEncoder = NativeRecoveryWriting.write
      let retry = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(retry, 200)
      XCTAssertEqual(
        try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), model)
      let caps = try await api.request(service, path: "/v1/capabilities")
      let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any])
      let policy = try XCTUnwrap(dictionary["atomicPersistence"] as? [String: Any])
      XCTAssertEqual(policy["maximumWriteBytes"] as? Int, 65536)
      XCTAssertEqual(
        policy["unsupportedFullSyncErrors"] as? [String], ["EINVAL", "ENOTSUP", "ENOSYS"])
      XCTAssertTrue((policy["limits"] as? String)?.contains("power-loss") == true)
    }
  }
  @MainActor func testPreferencesFlushFailureRetainsDiskModelTimerAndRevisionThroughHTTP()
    async throws
  {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("RecoverySettings.json")
    let initial = RecoveryPreferencesStore(url: target)
    try initial.commit(.init(enabled: false, intervalMinutes: 5), revision: initial.revision)
    let before = try Data(contentsOf: target)
    let failing = RecoveryPreferencesStore(url: target) { data, url in
      var operations = AtomicFileWriter.Operations()
      operations.fullSynchronize = { _ in
        errno = EIO
        return -1
      }
      let writer = try AtomicFileWriter(to: url, operations: operations)
      defer { writer.discard() }
      try writer.append(data)
      try writer.commit()
    }
    let revision = failing.revision
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }, recoveryPreferences: failing) {
      service, document in
      service.setPreferenceChangesEnabled(true)
      let response = try await api.request(
        service, path: "/v1/preferences/recovery",
        body: ["revision": revision.uuidString, "enabled": true, "intervalMinutes": 10])
      XCTAssertEqual(response.0.statusCode, 422)
      XCTAssertEqual(try Data(contentsOf: target), before)
      XCTAssertEqual(failing.value, .init(enabled: false, intervalMinutes: 5))
      XCTAssertEqual(failing.revision, revision)
      XCTAssertEqual(service.controller.autosavingDelay, 0)
      XCTAssertFalse(document.isDocumentEdited)
    }
  }
}
