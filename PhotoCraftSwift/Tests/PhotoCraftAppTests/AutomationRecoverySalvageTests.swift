import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationRecoverySalvageTests: XCTestCase {
  let base = "/v1/recovery/salvage"
  func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  @MainActor func fixture() throws -> (URL, RecoveryIndexStore, URL, CraftDocument) {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let index = RecoveryIndexStore(directoryURL: folder.appendingPathComponent("recovery"))
    let (_, backup, model) = try RecoveryIndexTests().seed(index)
    try Data("damaged registration".utf8).write(to: XCTUnwrap(index.indexURL))
    index.reload()
    return (folder, index, backup, model)
  }
  @MainActor func testPermissionSchemasPrivacyAndNativeEquivalentCopies() async throws {
    let (folder, index, backup, model) = try fixture(), api = AutomationTests()
    let originalBytes = try Data(contentsOf: backup)
    try await api.withService(recoveryIndex: index) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.close() } }
      let denied = try await api.request(service, path: base)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setRecoveryBackupsEnabled(true)
      let s = service.controller.recoveryMaintenance.salvage
      let scan = try await api.request(service, path: base + "/scan", body: ["revision": s.revision.uuidString])
      XCTAssertEqual(scan.0.statusCode, 200)
      let state = try object(scan.1)
      let schema = try XCTUnwrap(AutomationService.recoverySalvageCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertFalse(String(decoding: scan.1, as: UTF8.self).contains(folder.path))
      XCTAssertFalse(String(decoding: scan.1, as: UTF8.self).contains("bookmark"))
      let id = try XCTUnwrap(s.items.first?.id)
      let body = ["revision": s.revision.uuidString, "id": id.uuidString]
      let native = try await s.download(id, revision: s.revision, maximumBytes: DocumentIO.maximumDownloadBytes)
      let remote = try await api.request(service, path: base + "/download", body: body)
      XCTAssertEqual(remote.0.statusCode, 200); XCTAssertEqual(remote.1, native)
      XCTAssertEqual(native, try NativeArchive.encodeChunked(model))
      let opened = try await api.request(service, path: base + "/open-copy", body: body)
      XCTAssertEqual(opened.0.statusCode, 201); XCTAssertEqual(try object(opened.1)["shared"] as? Bool, false)
      let copy = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== original })
      var normalized = copy.store.document; normalized.id = model.id
      XCTAssertEqual(normalized, model); XCTAssertNil(copy.fileURL); XCTAssertNil(copy.recoverySnapshotContext)
      XCTAssertTrue(copy.isDocumentEdited); XCTAssertTrue(service.shares.isEmpty)
      XCTAssertEqual(try Data(contentsOf: backup), originalBytes)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      let capabilities = try await api.request(service, path: "/v1/capabilities")
      XCTAssertNotNil(try object(capabilities.1)["recoverySalvage"])
    }
  }
  @MainActor func testResetRequiresConfirmationNoOpenDocumentsAndPreservesBytes() async throws {
    let (_, index, backup, _) = try fixture(), api = AutomationTests()
    let bad = try Data(contentsOf: XCTUnwrap(index.indexURL)), bytes = try Data(contentsOf: backup)
    try await api.withService(recoveryIndex: index) { service, original in
      service.setRecoveryBackupsEnabled(true)
      let s = service.controller.recoveryMaintenance.salvage
      try await s.scan(revision: s.revision)
      let body: [String: Any] = ["revision": s.revision.uuidString, "confirmed": true]
      let rejected = try await api.request(service, path: base + "/reset-index", body: ["revision": s.revision.uuidString])
      XCTAssertEqual(rejected.0.statusCode, 400)
      let busy = try await api.request(service, path: base + "/reset-index", body: body)
      XCTAssertEqual(busy.0.statusCode, 409)
      original.close()
      try await s.scan(revision: s.revision)
      let reset = try await api.request(service, path: base + "/reset-index",
        body: ["revision": s.revision.uuidString, "confirmed": true])
      XCTAssertEqual(reset.0.statusCode, 200)
      XCTAssertNil(index.loadError); XCTAssertTrue(index.entries.isEmpty)
      let copies = try FileManager.default.contentsOfDirectory(at: XCTUnwrap(index.directoryURL),
        includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Index-preserved-") }
      XCTAssertEqual(copies.count, 1); XCTAssertEqual(try Data(contentsOf: copies[0]), bad)
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
      let refreshed = RecoveryIndexStore(directoryURL: index.directoryURL)
      XCTAssertTrue(refreshed.entries.isEmpty); XCTAssertNil(refreshed.loadError)
    }
  }
  @MainActor func testInvalidBusyStaleUnknownAndUnauthenticatedRequests() async throws {
    let (_, index, _, _) = try fixture(), api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      service.setRecoveryBackupsEnabled(true)
      let s = service.controller.recoveryMaintenance.salvage
      try await s.scan(revision: s.revision)
      let id = try XCTUnwrap(s.items.first?.id)
      let cases: [([String: Any], Int)] = [
        (["revision": "invalid", "id": id.uuidString], 400),
        (["revision": UUID().uuidString, "id": id.uuidString], 409),
        (["revision": s.revision.uuidString, "id": UUID().uuidString], 404),
        (["revision": s.revision.uuidString, "id": id.uuidString, "path": "/private/file"], 400),
      ]
      for (body, status) in cases {
        let response = try await api.request(service, path: base + "/download", body: body)
        XCTAssertEqual(response.0.statusCode, status)
      }
      index.isMaintaining = true
      let busy = try await api.request(service, path: base + "/scan", body: ["revision": s.revision.uuidString])
      index.isMaintaining = false
      XCTAssertEqual(busy.0.statusCode, 409)
      let media = try await api.request(service, path: base + "/scan", body: ["revision": s.revision.uuidString],
        headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      let denied = try await api.request(service, path: base, authenticate: false)
      XCTAssertEqual(denied.0.statusCode, 401)
    }
  }
  @MainActor func testRevocationDuringScanReadAndDownloadCannotPublish() async throws {
    for action in ["scan", "open-copy", "download"] {
      let (_, index, _, _) = try fixture(), api = AutomationTests()
      try await api.withService(recoveryIndex: index) { service, original in
        service.setRecoveryBackupsEnabled(true)
        let s = service.controller.recoveryMaintenance.salvage, gate = OpeningGate()
        try await s.scan(revision: s.revision)
        let id = try XCTUnwrap(s.items.first?.id), revision = s.revision
        if action == "scan" {
          s.scanner = { url in
            try await Task.detached { gate.wait(); return try RecoverySalvageScan.read(url) }.value
          }
        } else {
          s.reader = { item in
            try await Task.detached { gate.wait(); return try RecoverySalvageScan.decode(item) }.value
          }
        }
        var body: [String: Any] = ["revision": revision.uuidString]
        if action != "scan" { body["id"] = id.uuidString }
        let pending = Task { try await api.request(service, path: base + "/" + action, body: body) }
        try await DocumentOpeningTests().wait(gate)
        service.setRecoveryBackupsEnabled(false)
        gate.release()
        let response = try await pending.value
        XCTAssertEqual(response.0.statusCode, 403)
        XCTAssertEqual(service.controller.documents.count, 1)
        XCTAssertTrue(service.controller.documents.first === original)
        XCTAssertEqual(s.revision, revision); XCTAssertFalse(index.isMaintaining)
      }
    }
  }
}
