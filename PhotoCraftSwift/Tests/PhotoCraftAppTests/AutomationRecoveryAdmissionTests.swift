import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationRecoveryAdmissionTests: XCTestCase {
  @MainActor func fixture() throws -> (RecoveryIndexStore, URL, CraftDocument) {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let index = RecoveryIndexStore(directoryURL: folder)
    let (_, backup, model) = try RecoveryIndexTests().seed(index)
    return (index, backup, model)
  }
  @MainActor func testHTTPDeferralSchemaPrivacyAndSuccessfulRetryUseNativeAdmission() async throws {
    let (index, backup, model) = try fixture(), bytes = try Data(contentsOf: backup)
    let api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, original in
      let c = service.controller
      defer {
        c.recoveryDiscovery.dismissProgress()
        for doc in c.documents where doc !== original { doc.close() }
      }
      service.setRecoveryManagementEnabled(true)
      c.recoveryDiscovery.memoryLimitBytes = 0
      let response = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let schema = try XCTUnwrap(AutomationService.recoveryDiscoveryCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertEqual(state["lastDeferred"] as? Int, 1)
      XCTAssertEqual(state["lastInvalid"] as? Int, 0)
      XCTAssertEqual(state["lastUnavailable"] as? Int, 0)
      let operation = try XCTUnwrap(state["operation"] as? [String: Any])
      XCTAssertEqual(operation["phase"] as? String, "completed")
      let memory = try XCTUnwrap(operation["memory"] as? [String: Any])
      XCTAssertEqual(Set(memory.keys), ["limitBytes", "estimatedUsedBytes", "availableBytes", "metadataReadLimitBytes"])
      XCTAssertEqual(memory["limitBytes"] as? Int, 0)
      XCTAssertEqual(memory["availableBytes"] as? Int, 0)
      XCTAssertEqual((operation["deferredByReason"] as? [String: Int])?["aggregate"], 1)
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains(backup.path))
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains(model.name))
      XCTAssertEqual(c.documents.count, 1); XCTAssertTrue(service.shares.isEmpty)
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
      c.recoveryDiscovery.memoryLimitBytes = RecoveryMemoryPolicy.defaultLimit
      let retry = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(retry.0.statusCode, 200)
      XCTAssertEqual(index.lastDeferred, 0); XCTAssertEqual(index.lastDiscovered, 1)
      let restored = try XCTUnwrap(c.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== original })
      XCTAssertEqual(restored.store.document, model)
      XCTAssertTrue(restored.isDocumentEdited); XCTAssertFalse(restored.hasUnautosavedChanges)
      XCTAssertTrue(service.shares.isEmpty)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testRevocationDuringAccountingReturns403WithoutPublication() async throws {
    let (index, backup, _) = try fixture(), bytes = try Data(contentsOf: backup), api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, _ in
      let c = service.controller, gate = OpeningGate(); defer { gate.release() }
      c.recoveryDiscovery.accountant = { inputs in gate.wait(); return try RecoveryMemoryInput.used(inputs) }
      service.setRecoveryManagementEnabled(true)
      let pending = Task { try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": index.revision.uuidString]) }
      try await DocumentOpeningTests().wait(gate)
      XCTAssertFalse(gate.ranOnMain)
      let response = try await api.request(service, path: "/v1/recovery")
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(c.recoveryDiscovery.state?.phase, "accounting")
      service.setRecoveryManagementEnabled(false); gate.release()
      let result = try await pending.value
      XCTAssertEqual(result.0.statusCode, 403)
      XCTAssertEqual(c.documents.count, 1); XCTAssertEqual(index.entries.count, 1)
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
      XCTAssertEqual(c.recoveryDiscovery.state?.phase, "cancelled")
    }
  }
  @MainActor func testRepeatedWorkspaceChangesDuringAccountingReturnConflict() async throws {
    let (index, backup, _) = try fixture(), bytes = try Data(contentsOf: backup), api = AutomationTests()
    try await api.withService(recoveryIndex: index) { service, original in
      let c = service.controller
      let mutate: @MainActor @Sendable () -> Void = {
        try? original.store.executeEditorCommand(.renameLayer(original.store.document.layers[0].id, UUID().uuidString))
      }
      c.recoveryDiscovery.accountant = { inputs in
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
          mutate()
          done.signal()
        }
        guard done.wait(timeout: .now() + 2) == .success else { throw CancellationError() }
        return try RecoveryMemoryInput.used(inputs)
      }
      service.setRecoveryManagementEnabled(true)
      let response = try await api.request(service, path: "/v1/recovery/retry",
        body: ["revision": index.revision.uuidString])
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertEqual(c.documents.count, 1); XCTAssertEqual(index.lastDiscovered, 0)
      XCTAssertEqual(c.recoveryDiscovery.state?.phase, "failed")
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains(backup.path))
    }
  }
}
