import AppKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AppleTextRuntimeWorkflowTests: XCTestCase {
  func assertCapability(_ value: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertEqual(Set(value.keys), ["available", "message", "reason"], file: file, line: line)
    let available = try XCTUnwrap(value["available"] as? Bool, file: file, line: line)
    let reason = try XCTUnwrap((value["reason"] as? String).flatMap(AICapabilityReason.init(rawValue:)), file: file, line: line)
    XCTAssertEqual(available, reason == .ready, file: file, line: line)
    XCTAssertFalse((value["message"] as? String ?? "").isEmpty, file: file, line: line)
  }
  @MainActor func testRealHTTPReadinessReportsBothTextPathsWithoutStartingWorkOrChangingHistory() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelAIWork(); doc.store.cancelReviewedEditPlan(); doc.store.renderTask?.cancel() }
      try service.share(doc); let share = try XCTUnwrap(service.shares.first)
      let base = "/v1/documents/\(share.id)", source = doc.store.document, revision = service.revision(doc.store)
      let imageResponse = try await h.request(service, path: base + "/ai")
      XCTAssertEqual(imageResponse.0.statusCode, 200)
      let image = try XCTUnwrap(JSONSerialization.jsonObject(with: imageResponse.1) as? [String: Any])
      try self.assertCapability(["available": try XCTUnwrap(image["available"]), "message": try XCTUnwrap(image["message"]), "reason": try XCTUnwrap(image["reason"])])
      try self.assertCapability(try XCTUnwrap(image["textModel"] as? [String: Any]))
      XCTAssertEqual(Set(image.keys).subtracting(["revision"]), Set(try XCTUnwrap(AIImageAPI.stateSchema["required"] as? [String])))
      let planResponse = try await h.request(service, path: base + "/edit-plan")
      XCTAssertEqual(planResponse.0.statusCode, 200)
      let plan = try XCTUnwrap(JSONSerialization.jsonObject(with: planResponse.1) as? [String: Any])
      let providers = try XCTUnwrap(plan["providers"] as? [[String: Any]])
      XCTAssertEqual(providers.compactMap { $0["id"] as? String }, ["onDevice", "privateCloudCompute"])
      for provider in providers { var status = provider; status.removeValue(forKey: "id"); try self.assertCapability(status) }
      let cloud = try XCTUnwrap(providers.last)
      if LocalAI.platform.available && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 && !LocalAI.privateCloudComputeEntitled {
        XCTAssertEqual(cloud["reason"] as? String, "missingEntitlement"); XCTAssertEqual(cloud["available"] as? Bool, false)
      }
      let reasonSchema = try XCTUnwrap(AICapabilityAPI.schema["properties"] as? [String: Any])
      let reasons = try XCTUnwrap((reasonSchema["reason"] as? [String: Any])?["enum"] as? [String])
      XCTAssertEqual(Set(reasons), Set(AICapabilityReason.allCases.map(\.rawValue)))
      XCTAssertEqual(service.revision(doc.store), revision); XCTAssertEqual(doc.store.document, source)
      XCTAssertFalse(doc.store.aiBusy); XCTAssertFalse(doc.store.editPlanBusy)
      XCTAssertNil(doc.store.editPlanReview); XCTAssertNil(doc.store.imageGenerationJob); XCTAssertNil(doc.store.promptRefinementID)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try imageResponse.1.write(to: URL(fileURLWithPath: path).appendingPathComponent("apple-image-state.json"))
        try planResponse.1.write(to: URL(fileURLWithPath: path).appendingPathComponent("apple-plan-state.json"))
      }
    }
  }
  @MainActor func testUnavailableDirectCloudLeavesDraftAndDocumentIntactAndSuppliedPlansStillWork() async throws {
    let capability = EditPlanProvider.privateCloudCompute.capability
    XCTAssertFalse(capability.available, "Ordinary XCTest is not provisioned for managed PCC requests.")
    let s = try ReviewedEditPlanTests().store()
    defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document
    s.editPlanPrompt = "Invert the selected layer."; s.editPlanProvider = .privateCloudCompute
    await s.proposeReviewedEditPlan()
    XCTAssertEqual(s.editPlanReview?.phase, "failed"); XCTAssertEqual(s.editPlanReview?.error, capability.message)
    XCTAssertEqual(s.editPlanPrompt, "Invert the selected layer.")
    XCTAssertNil(s.editPlanReview?.prepared); XCTAssertFalse(s.geometryBusy); XCTAssertTrue(s.canReviewEditPlan)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
    try await s.prepareReviewedEditPlan(NativeEditPlan(summary: "Owned supplied plan", operations: [.invert]))
    XCTAssertEqual(s.editPlanReview?.origin, .supplied); XCTAssertTrue(s.canApplyEditPlan)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
    try s.applyReviewedEditPlan(try XCTUnwrap(s.editPlanReview).id)
    XCTAssertEqual(s.session.undoStack.count, 1)
    await s.undo(); XCTAssertEqual(s.document, source)
  }
}
