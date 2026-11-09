import AppKit
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class ParameterizedEditWorkflowTests: XCTestCase {
  func cases() throws -> [(NativeEditOperation, Adjustment)] {
    let exposure = try NativeEditAdjustment(.exposure, parameters: ["exposure": 1, "offset": 0.02, "gammaCorrection": 1.2])
    let brightness = try NativeEditAdjustment(.brightnessContrast, parameters: ["brightness": 35, "contrast": -20])
    let hue = try NativeEditAdjustment(.hueSaturation, parameters: ["hue": 35, "saturation": -20, "lightness": 10])
    let vibrance = try NativeEditAdjustment(.vibrance, parameters: ["vibrance": 40, "saturation": -15])
    var v = ClassicAdjustment(.vibrance); v.vibrance = 40; v.saturation = -15
    return [(.adjustment(exposure), .classic(.exposure(.init(exposure: 1, offset: 0.02, gammaCorrection: 1.2)))),
      (.adjustment(brightness), .source(.init(.brightnessContrast, parameters: ["brightness": 35, "contrast": -20], options: ["legacy": false]))),
      (.adjustment(hue), .hueSaturation(.init(master: .init(hue: 35, saturation: -20, lightness: 10)))),
      (.adjustment(vibrance), .classic(v))]
  }
  @MainActor func makeStore(_ depth: PixelDepth = .u8) throws -> EditorStore {
    let store = try ReviewedEditPlanTests().store(depth)
    var source = store.document
    var mask = try Surface(width: 8, height: 6, depth: depth, fill: .white)
    mask.setPixel(x: 2, y: 2, Pixel(0.25, 0.25, 0.25))
    source.layers[0].mask = mask
    source.name = "Owned parameter plan"
    store.session = EditorSession(document: source)
    return store
  }
  @MainActor func testAllFourAdjustmentsUseNativeCommandsAtEveryDepthWithSelectionAndMask() async throws {
    for depth in PixelDepth.allCases { for (operation, adjustment) in try cases() {
      let s = try makeStore(depth); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
      let source = s.document; var expected = source
      try Command.applyAdjustment(try XCTUnwrap(source.activeLayerID), adjustment).apply(to: &expected)
      try await s.prepareReviewedEditPlan(.init(summary: "Owned explicit values", operations: [operation]))
      XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
      let review = try XCTUnwrap(s.editPlanReview)
      XCTAssertEqual(review.plan?.operations, [operation]); XCTAssertNotNil(review.prepared)
      try s.applyReviewedEditPlan(review.id)
      XCTAssertEqual(s.document, expected, "\(depth) \(operation.title)")
      XCTAssertEqual(s.document.selection, source.selection)
      XCTAssertEqual(s.document.layers[0].mask, source.layers[0].mask)
      XCTAssertEqual(s.session.undoStack.count, 1)
      await s.undo(); XCTAssertEqual(s.document, source)
      await s.redo(); XCTAssertEqual(s.document, expected)
      let reopened = try DocumentIO.decode(DocumentIO.encode(s.document, format: .native), native: true, name: source.name)
      XCTAssertEqual(reopened, expected)
    } }
  }
  @MainActor func testOrderedRepeatedAdjustmentsAndFixedEditsAreOneReversibleTransaction() async throws {
    let pairs = try cases()
    let repeated = try NativeEditOperation(name: "exposure", parameters: ["exposure": -0.5, "offset": 0, "gammaCorrection": 1])
    let operations = [pairs[0].0, pairs[2].0, repeated, .invert, pairs[3].0]
    for depth in PixelDepth.allCases {
      let s = try makeStore(depth); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
      let source = s.document, id = try XCTUnwrap(source.activeLayerID); var expected = source
      for adjustment in [pairs[0].1, pairs[2].1, .classic(.exposure(.init(exposure: -0.5))), .invert, pairs[3].1] {
        try Command.applyAdjustment(id, adjustment).apply(to: &expected)
      }
      let plan = NativeEditPlan(summary: "Owned mixed repeated operations", operations: operations)
      try await s.prepareReviewedEditPlan(plan)
      XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
      try s.applyReviewedEditPlan(try XCTUnwrap(s.editPlanReview).id)
      XCTAssertEqual(s.document, expected); XCTAssertEqual(s.session.undoStack.count, 1)
      await s.undo(); XCTAssertEqual(s.document, source)
      await s.redo(); XCTAssertEqual(s.document, expected)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let root = URL(fileURLWithPath: path)
        try DocumentIO.encode(source, format: .native).write(to: root.appendingPathComponent("parameter-plan-\(depth)-source.photato"))
        try DocumentIO.encode(s.document, format: .native).write(to: root.appendingPathComponent("parameter-plan-\(depth)-result.photato"))
        try JSONEncoder().encode(plan).write(to: root.appendingPathComponent("parameter-plan.json"))
      }
    }
  }
  @MainActor func testNeutralAdjustmentPlanDoesNotAddUndoOrDirtyChange() async throws {
    let operations = try NativeEditAdjustment.Kind.allCases.map { kind in
      NativeEditOperation.adjustment(try .init(kind, parameters: Dictionary(uniqueKeysWithValues: kind.parameters.map { ($0.name, $0.neutral) })))
    }
    let s = try makeStore(); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document
    try await s.prepareReviewedEditPlan(.init(summary: "Owned neutral adjustments", operations: operations))
    try s.applyReviewedEditPlan(try XCTUnwrap(s.editPlanReview).id)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testModelSuggestionShowsExactAdjustmentValuesBeforeApply() async throws {
    let s = try makeStore(); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document, operation = try cases()[0].0
    s.editPlanProposal = { _, _ in .init(summary: "Owned injected model suggestion; no inference", operations: [operation]) }
    await s.proposeReviewedEditPlan()
    let review = try XCTUnwrap(s.editPlanReview)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertEqual(review.plan?.operations.first, operation)
    XCTAssertTrue(try XCTUnwrap(review.plan?.operations.first?.title).contains("Gamma Correction 1.2"))
    XCTAssertTrue(s.canApplyEditPlan)
    s.cancelReviewedEditPlan(); XCTAssertFalse(s.canApplyEditPlan)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPParameterizedPlanRetainsValuesAndMatchesNativeHistory() async throws {
    let helper = AutomationTests(), source = try makeStore().document
    let pairs = try cases(), plan = NativeEditPlan(summary: "Owned HTTP values", operations: try cases().map(\.0))
    let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan))
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelReviewedEditPlan(); doc.store.renderTask?.cancel() }
      doc.store.session = EditorSession(document: source)
      try service.share(doc); service.setWorkspacePanelChangesEnabled(true)
      let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/edit-plan"
      let result = try await helper.request(service, path: path, body: ["operation": "prepare", "revision": service.revision(doc.store), "plan": value])
      XCTAssertEqual(result.0.statusCode, 200, String(decoding: result.1, as: UTF8.self))
      let response = try XCTUnwrap(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
      let returned = try XCTUnwrap(response["plan"])
      XCTAssertEqual(try NativeEditPlan.decode(JSONSerialization.data(withJSONObject: returned)), plan)
      XCTAssertEqual(doc.store.document, source); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let review = try XCTUnwrap(doc.store.editPlanReview)
      let applied = try await helper.request(service, path: path, body: ["operation": "apply", "requestID": review.id.uuidString, "revision": service.revision(doc.store)])
      XCTAssertEqual(applied.0.statusCode, 200)
      var expected = source
      for pair in pairs { try Command.applyAdjustment(try XCTUnwrap(source.activeLayerID), pair.1).apply(to: &expected) }
      XCTAssertEqual(doc.store.document, expected); XCTAssertEqual(doc.store.session.undoStack.count, 1)
      await doc.store.undo(); XCTAssertEqual(doc.store.document, source)
      await doc.store.redo(); XCTAssertEqual(doc.store.document, expected)
    }
  }
  @MainActor func testHTTPMalformedAdjustmentCannotChangeExistingPreviewOrDocument() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelReviewedEditPlan(); doc.store.renderTask?.cancel() }
      try service.share(doc); service.setWorkspacePanelChangesEnabled(true)
      try await doc.store.prepareReviewedEditPlan(.init(summary: "Retained owned preview", operations: [.invert]))
      let old = try XCTUnwrap(doc.store.editPlanReview), source = doc.store.document
      let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/edit-plan"
      let bad: [String: Any] = ["summary": "Reject", "operations": [["operation": "exposure", "parameters": ["exposure": true, "offset": 0, "gammaCorrection": 1]]]]
      let response = try await helper.request(service, path: path, body: ["operation": "prepare", "revision": service.revision(doc.store), "plan": bad])
      XCTAssertEqual(response.0.statusCode, 400)
      XCTAssertTrue(doc.store.editPlanReview === old); XCTAssertTrue(doc.store.canApplyEditPlan)
      XCTAssertEqual(doc.store.document, source); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
  func testCapabilitiesDescribeRequiredParametersAndKeepLegacyNames() throws {
    let capabilities = EditPlanAPI.capabilities
    XCTAssertEqual(capabilities["operations"] as? [String], ["autoTone", "autoContrast", "autoColor", "desaturate", "invert", "exposure", "brightnessContrast", "hueSaturation", "vibrance"])
    let choices = try XCTUnwrap(EditPlanAPI.operationSchema["oneOf"] as? [[String: Any]])
    XCTAssertEqual(choices.count, 5)
    for choice in choices.dropFirst() {
      let properties = try XCTUnwrap(choice["properties"] as? [String: Any])
      let parameters = try XCTUnwrap(properties["parameters"] as? [String: Any])
      XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
      let names = try XCTUnwrap(parameters["properties"] as? [String: Any])
      XCTAssertEqual(Set(try XCTUnwrap(parameters["required"] as? [String])), Set(names.keys))
    }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: capabilities))
  }
}
