import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct DistractionFixture: RemoveDistractionDetecting {
  func detectDistractions(in input: Surface) async throws -> [RemoveDistractionMark] {
    try [(RemoveDistractionCategory.poles, 7), (.visualClutter, 21)].map { category, x in
      .init(category: category, mask: try SelectionMask.make(.rectangle(.init(x: x, y: 6, width: 3, height: 4)),
        width: input.width, height: input.height, antiAlias: false))
    }
  }
}

final class RemoveDistractionWorkflowTests: XCTestCase {
  @MainActor private func original() throws -> CraftDocument {
    var source = try CraftDocument(width: 35, height: 24)
    var raster = try Surface(width: source.width, height: source.height, fill: Pixel(0.6, 0.6, 0.6))
    for y in 6..<10 {
      for x in 7..<10 { raster.setPixel(x: x, y: y, Pixel(0.18, 0.16, 0.12)) }
      for x in 21..<24 { raster.setPixel(x: x, y: y, Pixel(0.13, 0.17, 0.2)) }
    }
    source.layers[0].locked = false; source.layers[0].content = .raster(raster)
    return source
  }

  @MainActor func testNativeAndAuthenticatedReviewSelectTheSamePixelsAndCommitOneUndo() async throws {
    let source = try original()
    let harness = AutomationTests()
    try await harness.withService(pressedMouseButtons: { 0 }) { service, doc in
      let store = doc.store
      store.session = EditorSession(document: source); store.tool = .remove
      store.removeSettings.mode = .generativeOff
      store.removeDistractionDetector = DistractionFixture()
      try service.share(doc)
      let detected = try await store.detectGeneralDistractions()
      XCTAssertEqual(detected.map(\.category), [.poles, .visualClutter])
      XCTAssertEqual(store.document, source); XCTAssertTrue(store.session.undoStack.isEmpty)
      try store.updateGeneralDistractions(categories: [.poles], opacity: 0.62)
      store.applyRemove(); await store.geometryTask?.value; await store.removeCompletionTask?.value
      let expected = store.document
      XCTAssertNotEqual(expected, source); XCTAssertEqual(store.session.undoStack.count, 1)
      let originalPixels = try Renderer.composite(source), actual = try Renderer.composite(expected)
      XCTAssertEqual(actual.pixel(x: 8, y: 8), originalPixels.pixel(x: 0, y: 0))
      XCTAssertEqual(actual.pixel(x: 22, y: 8), originalPixels.pixel(x: 22, y: 8))
      await store.undo(); XCTAssertEqual(store.document, source)
      let find = try await harness.edit(service, doc, RemoveToolAPI.name, ["operation": "findDistractions"])
      XCTAssertEqual(find, 200)
      let malformed = try await harness.edit(service, doc, RemoveToolAPI.name,
        ["operation": "configureDistractionReview", "enabledCategories": ["poles", "poles"]])
      XCTAssertEqual(malformed, 400)
      let edit = try await harness.edit(service, doc, RemoveToolAPI.name,
        ["operation": "configureDistractionReview", "enabledCategories": ["poles"], "overlayOpacity": 0.62])
      XCTAssertEqual(edit, 200)
      XCTAssertEqual(store.removeDraft?.distractionReview?.enabled, [.poles])
      XCTAssertEqual(store.removeDraft?.distractionReview?.overlayOpacity, 0.62)
      let apply = try await harness.edit(service, doc, RemoveToolAPI.name, ["operation": "apply"])
      XCTAssertEqual(apply, 200); XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertEqual(store.document, source)
    }
  }

  @MainActor func testDisabledCategoriesAndManualMarksWaitForExplicitApplyOrCancel() async throws {
    let source = try original()
    let store = EditorStore(document: source); store.tool = .remove
    store.removeSettings.mode = .generativeOff
    store.removeDistractionDetector = DistractionFixture()
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    _ = try await store.detectGeneralDistractions()
    try store.updateGeneralDistractions(categories: [])
    XCTAssertFalse(store.removeDraft?.hasMarks ?? true)
    XCTAssertTrue(store.beginRemoveStroke(at: CGPoint(x: 8.5, y: 7.5), alternate: false))
    store.finishRemoveStroke(at: CGPoint(x: 8.5, y: 7.5))
    XCTAssertTrue(store.removeDraft?.hasMarks ?? false)
    XCTAssertNil(store.removeApplying); XCTAssertEqual(store.document, source)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.cancelRemove()
    XCTAssertNil(store.removeDraft); XCTAssertEqual(store.document, source)
  }
}
