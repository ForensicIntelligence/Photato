import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationRecoveryBackupsTests: XCTestCase {
  let base = "/v1/recovery/backups"
  func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  @MainActor func fixture() throws -> (URL, RecoveryIndexStore, RecoverySnapshotContext, URL, CraftDocument) {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let index = RecoveryIndexStore(directoryURL: folder.appendingPathComponent("recovery"))
    let source = folder.appendingPathComponent("Confidential-name.photato")
    let original = try CraftNSDocument.blankModel(width: 4, height: 3, name: "Recovered")
    try NativeArchive.write(original, to: source)
    let (context, backup, model) = try RecoveryIndexTests().seed(index,
      source: source, model: original)
    return (folder, index, context, backup, model)
  }
  @MainActor func testSeparatePermissionSchemasAndMetadataPrivacy() async throws {
    let (folder, index, _, _, _) = try fixture(), api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      service.setRecoveryManagementEnabled(true)
      let denied = try await api.request(service, path: base)
      XCTAssertEqual(denied.0.statusCode, 403)
      XCTAssertFalse(String(decoding: denied.1, as: UTF8.self).contains("Confidential"))
      service.setRecoveryBackupsEnabled(true)
      let inspect = try await api.request(service, path: base + "/inspect",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(inspect.0.statusCode, 200)
      let state = try object(inspect.1)
      let schema = try XCTUnwrap(AutomationService.recoveryBackupsCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      let items = try XCTUnwrap(state["items"] as? [[String: Any]])
      XCTAssertEqual(items.count, 1)
      XCTAssertEqual(items[0]["name"] as? String, "Confidential-name.photato")
      XCTAssertFalse(String(decoding: inspect.1, as: UTF8.self).contains(folder.path))
      XCTAssertFalse(String(decoding: inspect.1, as: UTF8.self).contains("bookmark"))
      XCTAssertEqual(items[0]["status"] as? String, "available")
      XCTAssertEqual(state["availableEntries"] as? Int, 511)
      let generation = service.recoveryBackupsGeneration
      service.stop()
      XCTAssertFalse(service.recoveryBackupsEnabled)
      XCTAssertThrowsError(try service.validateRecoveryBackups(generation))
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testHTTPOpenCopyAndDownloadMatchNativeWithoutSharingOrPrivateContext() async throws {
    let (_, index, context, backup, model) = try fixture(), api = AutomationTests()
    let backupBytes = try Data(contentsOf: backup)
    try await api.withService(recoveryIndex: index) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setRecoveryBackupsEnabled(true)
      XCTAssertFalse(service.recoveryManagementEnabled)
      XCTAssertFalse(service.documentTransfersEnabled)
      let body: [String: Any] = ["revision": index.revision.uuidString, "id": context.recoveryID.uuidString]
      let download = try await api.request(service, path: base + "/download", body: body)
      XCTAssertEqual(download.0.statusCode, 200)
      XCTAssertEqual(download.1, try NativeArchive.encodeChunked(model))
      let copy = try await api.request(service, path: base + "/open-copy", body: body)
      XCTAssertEqual(copy.0.statusCode, 201)
      XCTAssertEqual(try object(copy.1)["shared"] as? Bool, false)
      let recovered = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }
        .first { $0 !== original })
      var actual = recovered.store.document; actual.id = model.id
      XCTAssertEqual(actual, model)
      XCTAssertNil(recovered.fileURL); XCTAssertNil(recovered.recoverySnapshotContext)
      XCTAssertTrue(recovered.isDocumentEdited)
      XCTAssertTrue(service.shares.isEmpty)
      XCTAssertTrue(service.controller.recoveryPreferences.recentDocuments.isEmpty)
      XCTAssertEqual(try Data(contentsOf: backup), backupBytes)
    }
  }
  @MainActor func testInvalidStaleBusyAndCleanupConfirmationRequestsPreserveBytes() async throws {
    let (_, index, context, backup, _) = try fixture(), api = AutomationTests()
    let bytes = try Data(contentsOf: backup)
    try await api.withService(recoveryIndex: index) { service, _ in
      service.setRecoveryBackupsEnabled(true)
      let good: [String: Any] = ["revision": index.revision.uuidString, "id": context.recoveryID.uuidString, "confirmed": true]
      let bad: [([String: Any], Int)] = [
        (["revision": "bad", "id": context.recoveryID.uuidString, "confirmed": true], 400),
        (["revision": UUID().uuidString, "id": context.recoveryID.uuidString, "confirmed": true], 409),
        (["revision": index.revision.uuidString, "id": UUID().uuidString, "confirmed": true], 404),
        (["revision": index.revision.uuidString, "id": context.recoveryID.uuidString], 400),
        (["revision": index.revision.uuidString, "id": context.recoveryID.uuidString, "confirmed": false], 400),
        (["revision": index.revision.uuidString, "id": context.recoveryID.uuidString, "confirmed": true, "path": backup.path], 400),
      ]
      for (body, expected) in bad {
        let response = try await api.request(service, path: base + "/forget", body: body)
        XCTAssertEqual(response.0.statusCode, expected)
      }
      let wrongType = try await api.request(service, path: base + "/forget", body: good,
        headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(wrongType.0.statusCode, 415)
      index.isMaintaining = true
      let busy = try await api.request(service, path: base + "/forget", body: good)
      index.isMaintaining = false
      XCTAssertEqual(busy.0.statusCode, 409)
      let unauthenticated = try await api.request(service, path: base, authenticate: false)
      XCTAssertEqual(unauthenticated.0.statusCode, 401)
      XCTAssertEqual(index.entries.count, 1)
      let removed = try await api.request(service, path: base + "/forget", body: good)
      XCTAssertEqual(removed.0.statusCode, 200)
      XCTAssertTrue(index.entries.isEmpty)
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
    }
  }
  @MainActor func testPermissionRevocationDuringReadCannotPublishOrDownload() async throws {
    for action in ["open-copy", "download", "trash"] {
      let (_, index, context, backup, _) = try fixture(), api = AutomationTests()
      let bytes = try Data(contentsOf: backup)
      try await api.withService(recoveryIndex: index) { service, original in
        let manager = service.controller.recoveryMaintenance, gate = OpeningGate()
        manager.reader = { entries, decode in
          try await Task.detached {
            gate.wait()
            return try PreparedRecoveryBackup.read(entries, decode: decode)
          }.value
        }
        service.setRecoveryBackupsEnabled(true)
        var body: [String: Any] = ["revision": index.revision.uuidString, "id": context.recoveryID.uuidString]
        if action == "trash" { body["confirmed"] = true }
        let pending = Task { try await api.request(service, path: base + "/" + action, body: body) }
        try await DocumentOpeningTests().wait(gate)
        XCTAssertTrue(manager.isBusy)
        service.setRecoveryBackupsEnabled(false)
        gate.release()
        let response = try await pending.value
        XCTAssertEqual(response.0.statusCode, 403)
        XCTAssertEqual(service.controller.documents.count, 1)
        XCTAssertTrue(service.controller.documents.first === original)
        XCTAssertEqual(index.entries.first?.state, .ready)
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertFalse(manager.isBusy)
      }
    }
  }
  @MainActor func testMoveCommitCompletesCleanupAfterRevocationAndMissingCleanupWorks() async throws {
    let (folder, index, context, backup, _) = try fixture(), api = AutomationTests()
    let bytes = try Data(contentsOf: backup)
    try await api.withService(recoveryIndex: index) { service, _ in
      let manager = service.controller.recoveryMaintenance
      let moved = folder.appendingPathComponent("owned-moved.photato")
      manager.trasher = { prepared in
        await MainActor.run { service.setRecoveryBackupsEnabled(false) }
        try FileManager.default.moveItem(at: prepared.entry.backupURL, to: moved)
        return moved
      }
      service.setRecoveryBackupsEnabled(true)
      let response = try await api.request(service, path: base + "/trash", body: [
        "revision": index.revision.uuidString, "id": context.recoveryID.uuidString, "confirmed": true])
      XCTAssertEqual(response.0.statusCode, 403)
      XCTAssertTrue(index.entries.isEmpty)
      XCTAssertEqual(try Data(contentsOf: moved), bytes)
      let (_, missing, _) = try RecoveryIndexTests().seed(index)
      try FileManager.default.removeItem(at: missing)
      service.setRecoveryBackupsEnabled(true)
      let pruned = try await api.request(service, path: base + "/remove-missing",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(pruned.0.statusCode, 200)
      XCTAssertTrue(index.entries.isEmpty)
    }
  }
  @MainActor func testExternalIndexChangeDuringReadRejectsPublication() async throws {
    let (_, index, context, _, _) = try fixture(), api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      let gate = OpeningGate()
      service.controller.recoveryMaintenance.reader = { entries, decode in
        try await Task.detached {
          gate.wait()
          return try PreparedRecoveryBackup.read(entries, decode: decode)
        }.value
      }
      service.setRecoveryBackupsEnabled(true)
      let pending = Task { try await api.request(service, path: base + "/open-copy",
        body: ["revision": index.revision.uuidString, "id": context.recoveryID.uuidString]) }
      try await DocumentOpeningTests().wait(gate)
      let external = RecoveryIndexStore(directoryURL: index.directoryURL)
      try external.retire(context.recoveryID)
      gate.release()
      let response = try await pending.value
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertEqual(service.controller.documents.count, 1)
      XCTAssertEqual(external.entries.first?.state, .retired)
    }
  }
}
