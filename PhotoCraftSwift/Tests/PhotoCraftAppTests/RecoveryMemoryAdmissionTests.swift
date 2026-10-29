import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class RecoveryMemoryAdmissionTests: XCTestCase {
  @MainActor func temporary() throws -> URL {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    return folder
  }
  @MainActor func cleanup(_ c: CraftDocumentController) {
    c.recoveryDiscovery.dismissProgress()
    for doc in c.documents { doc.close() }
  }
  @MainActor func testManyDocumentsDeferPreservedGroupsAndRetryAfterClose() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try temporary())
    let c = helper.controller(index); defer { cleanup(c) }
    var backups: [URL: Data] = [:]
    var ids: Set<UUID> = []
    for _ in 0..<5 {
      let (_, url, model) = try helper.seed(index)
      backups[url] = try Data(contentsOf: url); ids.insert(model.id)
    }
    let cost = RecoveryMemoryPolicy.documentCost(try CraftNSDocument.blankModel(width: 4, height: 3))
    c.recoveryDiscovery.memoryLimitBytes = cost * 2 + 65_536
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastDiscovered, 2); XCTAssertEqual(index.lastDeferred, 3)
    XCTAssertEqual(index.lastInvalid, 0); XCTAssertEqual(index.lastUnavailable, 0)
    XCTAssertEqual(c.documents.count, 2)
    XCTAssertLessThanOrEqual(try XCTUnwrap(c.recoveryDiscovery.state?.memory.estimatedUsedBytes),
      c.recoveryDiscovery.memoryLimitBytes)
    for (url, bytes) in backups { XCTAssertEqual(try Data(contentsOf: url), bytes) }
    var recovered = Set(c.documents.compactMap { ($0 as? CraftNSDocument)?.store.document.id })
    for doc in c.documents { doc.close() }
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastDiscovered, 2); XCTAssertEqual(index.lastDeferred, 1)
    recovered.formUnion(c.documents.compactMap { ($0 as? CraftNSDocument)?.store.document.id })
    for doc in c.documents { doc.close() }
    try await c.discoverIndexedRecovery(display: false)
    recovered.formUnion(c.documents.compactMap { ($0 as? CraftNSDocument)?.store.document.id })
    XCTAssertEqual(index.lastDiscovered, 1); XCTAssertEqual(index.lastDeferred, 0)
    XCTAssertEqual(recovered, ids)
  }
  @MainActor func testMetadataAndRasterCapacityAreDistinctFromInvalidBackups() async throws {
    let helper = RecoveryIndexTests()
    for kind in ["metadata", "raster", "invalid"] {
      let index = RecoveryIndexStore(directoryURL: try temporary()), c = helper.controller(index)
      defer { cleanup(c) }
      var model = try CraftDocument(width: 128, height: 128)
      if kind == "metadata" { model.sourceMetadata = ["owned": Data(repeating: 42, count: 256_000)] }
      if kind == "raster" {
        var surface = try Surface(width: 128, height: 128)
        for x in [0, 64] { for y in [0, 64] { surface.setPixel(x: x, y: y, .white) } }
        model.layers[0].content = .raster(surface)
      }
      let (_, backup, _) = try helper.seed(index, model: model)
      if kind == "invalid" { try Data("invalid".utf8).write(to: backup) }
      let bytes = try Data(contentsOf: backup)
      c.recoveryDiscovery.memoryLimitBytes = RecoveryMemoryPolicy.renderAllowance(width: 128, height: 128) + 200_000
      try await c.discoverIndexedRecovery(display: false)
      XCTAssertTrue(c.documents.isEmpty); XCTAssertEqual(index.entries.count, 1)
      XCTAssertEqual(try Data(contentsOf: backup), bytes)
      if kind == "invalid" {
        XCTAssertEqual(index.lastDeferred, 0); XCTAssertEqual(index.lastInvalid, 1)
      } else {
        XCTAssertEqual(index.lastDeferred, 1); XCTAssertEqual(index.lastInvalid, 0)
        XCTAssertEqual(c.recoveryDiscovery.state?.deferredByReason[kind], 1)
      }
    }
  }
  @MainActor func testLargeCanvasDefersBeforeFullDecoderAndSmallerBackupStillRecovers() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try temporary())
    let c = helper.controller(index); defer { cleanup(c) }
    let (_, _, small) = try helper.seed(index)
    let (_, _, large) = try helper.seed(index, model: CraftDocument(width: 2000, height: 2000))
    c.recoveryDiscovery.memoryLimitBytes = 1_048_576
    c.recoveryDiscovery.reader = { entry, allowance in
      XCTAssertNotEqual(entry.documentID, large.id, "Excessive canvas must be deferred before decoding")
      return try PreparedIndexedRecovery.read(entry, allowance: allowance)
    }
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastDeferred, 1); XCTAssertEqual(index.lastDiscovered, 1)
    XCTAssertEqual((c.documents.first as? CraftNSDocument)?.store.document, small)
  }
  @MainActor func testWorkspaceGrowthAfterDecodeDefersPublicationAndCanRetry() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try temporary())
    let c = helper.controller(index); defer { cleanup(c) }
    let (_, backup, model) = try helper.seed(index), bytes = try Data(contentsOf: backup)
    let gate = OpeningGate(); defer { gate.release() }
    c.recoveryDiscovery.memoryLimitBytes = 1_048_576
    c.recoveryDiscovery.reader = { entry, allowance in
      let prepared = try PreparedIndexedRecovery.read(entry, allowance: allowance)
      gate.wait(); return prepared
    }
    let pending = Task { try await c.discoverIndexedRecovery(display: false) }
    try await DocumentOpeningTests().wait(gate)
    let other = CraftNSDocument(model: try CraftDocument(width: 512, height: 512))
    c.addDocument(other)
    gate.release(); try await pending.value
    XCTAssertEqual(c.documents.count, 1); XCTAssertTrue(c.documents.first === other)
    XCTAssertEqual(index.lastDeferred, 1)
    XCTAssertEqual(c.recoveryDiscovery.state?.deferredByReason["workspaceGrowth"], 1)
    XCTAssertEqual(try Data(contentsOf: backup), bytes)
    other.close()
    c.recoveryDiscovery.reader = PreparedIndexedRecovery.read
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastDeferred, 0)
    XCTAssertEqual((c.documents.first as? CraftNSDocument)?.store.document, model)
  }
  @MainActor func testAccountingRunsInBackgroundAndRechecksChangedSessions() async throws {
    let helper = RecoveryIndexTests(), c = helper.controller(RecoveryIndexStore(directoryURL: try temporary()))
    defer { cleanup(c) }
    let document = CraftNSDocument(model: try CraftDocument(width: 4, height: 3)); c.addDocument(document)
    let gate = OpeningGate(); defer { gate.release() }
    c.recoveryDiscovery.accountant = { inputs in
      gate.wait(); return try RecoveryMemoryInput.used(inputs)
    }
    let pending = Task { try await c.discoverIndexedRecovery(display: false) }
    try await DocumentOpeningTests().wait(gate)
    XCTAssertFalse(gate.ranOnMain)
    XCTAssertEqual(c.recoveryDiscovery.state?.phase, "accounting")
    try document.store.executeEditorCommand(.renameLayer(document.store.document.layers[0].id, "New history"))
    gate.release(); try await pending.value
    let usage = try RecoveryMemoryInput.used(c.recoveryMemoryInputs)
    XCTAssertEqual(c.recoveryDiscovery.state?.memory.estimatedUsedBytes, usage)
    XCTAssertGreaterThan(usage, RecoveryMemoryPolicy.documentCost(document.store.document))
  }
  @MainActor func testAlreadyOpenGroupsAreNotCountedAsDeferredAndHistoryConsumesCapacity() async throws {
    let helper = RecoveryIndexTests(), index = RecoveryIndexStore(directoryURL: try temporary())
    let c = helper.controller(index); defer { cleanup(c) }
    _ = try helper.seed(index)
    try await c.discoverIndexedRecovery(display: false)
    let doc = try XCTUnwrap(c.documents.first as? CraftNSDocument)
    try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Edited"))
    _ = try helper.seed(index)
    c.recoveryDiscovery.memoryLimitBytes = RecoveryMemoryPolicy.documentCost(doc.store.document)
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(index.lastAlreadyOpen, 1); XCTAssertEqual(index.lastDeferred, 1)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertGreaterThan(try XCTUnwrap(c.recoveryDiscovery.state?.memory.estimatedUsedBytes),
      c.recoveryDiscovery.memoryLimitBytes)
  }
  @MainActor func testSeveralStartupDocumentArrivalsSettleBeforeAdmission() async throws {
    let helper = RecoveryIndexTests(), c = helper.controller(RecoveryIndexStore(directoryURL: try temporary()))
    defer { cleanup(c) }
    var arrivals = 0
    let restore: @MainActor @Sendable () -> Void = {
      if arrivals < 3 {
        c.addDocument(CraftNSDocument(model: try! CraftDocument(width: 4, height: 3)))
        arrivals += 1
      }
    }
    c.recoveryDiscovery.accountant = { inputs in
      let done = DispatchSemaphore(value: 0)
      Task { @MainActor in restore(); done.signal() }
      guard done.wait(timeout: .now() + 2) == .success else { throw CancellationError() }
      return try RecoveryMemoryInput.used(inputs)
    }
    try await c.discoverIndexedRecovery(display: false)
    XCTAssertEqual(arrivals, 3)
    XCTAssertEqual(c.documents.count, 3)
    XCTAssertEqual(c.recoveryDiscovery.state?.phase, "completed")
    XCTAssertEqual(c.recoveryDiscovery.state?.memory.estimatedUsedBytes,
      try RecoveryMemoryInput.used(c.recoveryMemoryInputs))
    XCTAssertNil(c.recoveryIndex.discoveryError)
  }
  func testPolicyThresholdsAndConservativeRenderAccountingDoNotOverflow() throws {
    XCTAssertEqual(RecoveryMemoryPolicy.limit(physicalMemory: 0), 256 * 1024 * 1024)
    XCTAssertEqual(RecoveryMemoryPolicy.limit(physicalMemory: 8 * 1024 * 1024 * 1024), 2 * 1024 * 1024 * 1024)
    XCTAssertEqual(RecoveryMemoryPolicy.limit(physicalMemory: UInt64.max), 4 * 1024 * 1024 * 1024)
    XCTAssertEqual(RecoveryMemoryPolicy.add(Int.max, 1), Int.max)
    XCTAssertEqual(RecoveryMemoryPolicy.renderAllowance(width: Int.max, height: 1), Int.max)
    var session = EditorSession(document: try CraftDocument(width: 4, height: 3))
    try session.execute(.renameLayer(session.document.layers[0].id, "History"))
    let measured = RecoveryMemoryInput(session: session, actualRenderBytes: 1_000_000)
    XCTAssertGreaterThan(measured.estimatedBytes, 1_000_000 + session.residentHistoryBytes)
  }
}
