import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationBackgroundRecoveryTests: XCTestCase {
  @MainActor func testHTTPProgressPrivacyAndCancellationDuringRetry() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try helper.folder())
    let (_, backup, _) = try helper.seed(index), bytes = try Data(contentsOf: backup)
    let api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      let c = service.controller, gate = OpeningGate(); defer { gate.release() }
      c.recoveryDiscovery.reader = { entry, allowance in gate.wait(); try Task.checkCancellation(); return try PreparedIndexedRecovery.read(entry, allowance: allowance) }
      service.setRecoveryManagementEnabled(true)
      let pending = Task { try await api.request(service, path: "/v1/recovery/retry", body: ["revision": index.revision.uuidString]) }
      try await DocumentOpeningTests().wait(gate)
      XCTAssertFalse(gate.ranOnMain)
      let response = try await api.request(service, path: "/v1/recovery")
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let operation = try XCTUnwrap(state["operation"] as? [String: Any])
      let schema = try XCTUnwrap(AutomationService.recoveryDiscoveryCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertEqual(Set(operation.keys), ["id", "active", "phase", "totalEntries", "completedEntries", "cancellationRequested", "canCancel", "memory", "deferredByReason"])
      XCTAssertEqual(operation["phase"] as? String, "decoding")
      XCTAssertEqual(operation["active"] as? Bool, true)
      XCTAssertEqual(operation["canCancel"] as? Bool, true)
      XCTAssertEqual(state["canRetry"] as? Bool, false)
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains(backup.path))
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains("Recovered"))
      let id = try XCTUnwrap(operation["id"] as? String)
      for (body, code) in [(["operationID": "bad"], 400), (["operationID": UUID().uuidString], 409),
        (["operationID": id, "extra": "bad"], 400)] {
        let invalid = try await api.request(service, path: "/v1/recovery/cancel", body: body)
        XCTAssertEqual(invalid.0.statusCode, code)
      }
      let media = try await api.request(service, path: "/v1/recovery/cancel",
        body: ["operationID": id], headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      let cancelled = try await api.request(service, path: "/v1/recovery/cancel", body: ["operationID": id])
      XCTAssertEqual(cancelled.0.statusCode, 200)
      gate.release()
      let retry = try await pending.value
      XCTAssertEqual(retry.0.statusCode, 409)
      XCTAssertEqual(c.documents.count, 1); XCTAssertTrue(service.shares.isEmpty)
      XCTAssertNil(service.ownedRecoveryDiscovery)
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
      let stale = try await api.request(service, path: "/v1/recovery/cancel", body: ["operationID": id])
      XCTAssertEqual(stale.0.statusCode, 409)
      service.setRecoveryManagementEnabled(false)
      let denied = try await api.request(service, path: "/v1/recovery/cancel", body: ["operationID": id])
      XCTAssertEqual(denied.0.statusCode, 403)
    }
  }
  @MainActor func testRevocationCancelsOwnedRetryButLeavesNativeRecoveryRunning() async throws {
    let helper = RecoveryIndexTests(), api = AutomationTests()
    for owned in [true, false] {
      let index = RecoveryIndexStore(directoryURL: try helper.folder())
      _ = try helper.seed(index)
      try await api.withService(recoveryIndex: index) { service, original in
        let c = service.controller, gate = OpeningGate()
        defer { gate.release(); for doc in c.documents where doc !== original { doc.close() } }
        c.recoveryDiscovery.reader = { entry, allowance in gate.wait(); try Task.checkCancellation(); return try PreparedIndexedRecovery.read(entry, allowance: allowance) }
        service.setRecoveryManagementEnabled(true)
        let pending: Task<Int, Error> = Task {
          if owned { return try await api.request(service, path: "/v1/recovery/retry", body: ["revision": index.revision.uuidString]).0.statusCode }
          try await c.discoverIndexedRecovery(display: false); return 200
        }
        try await DocumentOpeningTests().wait(gate)
        service.setRecoveryManagementEnabled(false)
        XCTAssertEqual(c.recoveryDiscovery.state?.cancellationRequested, owned)
        gate.release()
        let code = try await pending.value
        XCTAssertEqual(code, owned ? 403 : 200)
        XCTAssertEqual(c.documents.count, owned ? 1 : 2)
        XCTAssertTrue(service.shares.isEmpty)
      }
    }
  }
  @MainActor func testUploadCannotPublishAcrossCompletedRecoveryGeneration() async throws {
    let gate = OpeningGate(); defer { gate.release() }
    let api = AutomationTests()
    try await api.withService(documentDecoder: { data, native, name in
      gate.wait(); return try DocumentIO.decodeUpload(data, native: native, name: name)
    }) { service, _ in
      service.setDocumentTransfersEnabled(true)
      let bytes = try NativeArchive.encode(CraftDocument(width: 3, height: 2))
      let pending = Task { try await AutomationOpeningTests().upload(service, bytes: bytes, type: DocumentIO.Format.native.mediaType) }
      try await DocumentOpeningTests().wait(gate)
      try await service.controller.discoverIndexedRecovery(display: false)
      XCTAssertFalse(service.controller.recoveryIndex.isBusy)
      gate.release()
      let response = try await pending.value
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertEqual(service.controller.documents.count, 1); XCTAssertTrue(service.shares.isEmpty)
    }
  }
}
