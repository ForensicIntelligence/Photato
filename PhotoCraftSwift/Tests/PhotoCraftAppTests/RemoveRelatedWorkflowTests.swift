import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct RelatedFixtureDetector: RemoveRelatedElementDetecting {
  func scores(in image: Surface, for element: RemoveRelatedElement) async throws -> [Float] {
    let size = RemoveRelatedElements.side
    var scores = [Float](repeating: 0, count: size * size)
    for y in 0..<size {
      for x in 0..<size {
        let pixel = image.pixel(x: (2 * x + 1) * image.width / (2 * size), y: (2 * y + 1) * image.height / (2 * size))
        if element == .shadow, pixel.r > 0.9, pixel.g < 0.1 { scores[y * size + x] = 0.95 }
        if element == .reflection, pixel.b > 0.9, pixel.g < 0.1 { scores[y * size + x] = 0.95 }
      }
    }
    return scores
  }
}

final class RemoveRelatedWorkflowTests: XCTestCase {
  @MainActor func testNativeAndHTTPReviewSelectTheEffectsWithoutChangingTheSource() async throws {
    var source = try CraftDocument(width: 96, height: 88)
    var pixels = try Surface(width: 96, height: 88, fill: Pixel(0.4, 0.4, 0.4))
    for y in 39..<48 { for x in 45..<59 { pixels.setPixel(x: x, y: y, Pixel(1, 0, 0)) } }
    for y in 37..<43 { for x in 62..<68 { pixels.setPixel(x: x, y: y, Pixel(1, 0, 0)) } }
    for y in 52..<61 { for x in 34..<42 { pixels.setPixel(x: x, y: y, Pixel(0, 0, 1)) } }
    source.layers[0].content = .raster(pixels)
    source.layers[0].locked = true
    let stroke = RemoveStroke(size: 3, points: [[29, 29], [45, 29], [45, 47], [29, 47], [29, 29]])
    let refine = RemoveStroke(size: 3, subtract: true, points: [[59.5, 44.5]])
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      let store = doc.store
      store.session = EditorSession(document: source); store.tool = .remove
      store.removeRelatedDetector = RelatedFixtureDetector()
      store.removeLocalPreparation = { request, original in
        let guides = try RemovePreparation.generativeGuides(request, document: original)
        return try RemovePreparation.prepareGenerative(request, source: original, prepared: guides) { _, _ in
          try Surface(width: 512, height: 512, fill: Pixel(0.2, 0.8, 0.3))
        }
      }
      try store.armRelatedElements(); try store.appendRemoveStroke(stroke)
      XCTAssertEqual(store.document, source)
      XCTAssertTrue(store.removeDraft?.requiresExplicitApply == true)
      let suggestions = try await store.detectRelatedElements()
      XCTAssertEqual(suggestions.map(\.element), [.shadow, .reflection])
      XCTAssertFalse(store.canFindRelatedElements)
      XCTAssertTrue(store.removeDraft?.strokes.isEmpty == true)
      let shadows = try XCTUnwrap(suggestions.first?.coverage)
      XCTAssertGreaterThan(shadows.coverage(x: 50, y: 44), 0)
      XCTAssertGreaterThan(shadows.coverage(x: 59, y: 44), 0)
      XCTAssertEqual(shadows.coverage(x: 64, y: 40), 0)
      XCTAssertEqual(store.document, source)
      try store.updateRelatedElements([.shadow])
      try store.appendRemoveStroke(refine)
      let request = try XCTUnwrap(store.removeDraft).request
      let reviewed = try RemovePreparation.markCoverage(request, in: source)
      XCTAssertEqual(reviewed.coverage(x: 59, y: 44), 0)
      XCTAssertGreaterThan(reviewed.coverage(x: 50, y: 44), 0)
      store.applyRemove()
      await store.geometryTask?.value; await store.removeCompletionTask?.value
      XCTAssertNil(store.error); XCTAssertFalse(store.removeRelatedArmed)
      let changed = store.document
      XCTAssertEqual(changed.layers.count, 2); XCTAssertEqual(changed.layers[0], source.layers[0])
      XCTAssertEqual(store.session.undoStack.count, 1)
      let expected = try Renderer.composite(changed).rgbaData(depth: .u8)
      await store.undo(); XCTAssertEqual(store.document, source)

      try service.share(doc)
      let begin = try await helper.edit(service, doc, RemoveToolAPI.name, ["operation": "beginRelatedElements"])
      XCTAssertEqual(begin, 200)
      let mark = try await helper.edit(service, doc, RemoveToolAPI.name,
        ["operation": "stroke", "stroke": ["size": stroke.size, "points": stroke.points]])
      XCTAssertEqual(mark, 200); XCTAssertEqual(store.document, source)
      let premature = try await helper.edit(service, doc, RemoveToolAPI.name, ["operation": "apply"])
      XCTAssertEqual(premature, 409)
      let find = try await helper.edit(service, doc, RemoveToolAPI.name, ["operation": "findRelatedElements"])
      XCTAssertEqual(find, 200)
      let malformed = try await helper.edit(service, doc, RemoveToolAPI.name,
        ["operation": "configureRelatedElements", "enabledElements": ["shadow", "shadow"]])
      XCTAssertEqual(malformed, 400)
      let configure = try await helper.edit(service, doc, RemoveToolAPI.name,
        ["operation": "configureRelatedElements", "enabledElements": ["shadow"]])
      XCTAssertEqual(configure, 200)
      let refinement = try await helper.edit(service, doc, RemoveToolAPI.name,
        ["operation": "stroke", "stroke": ["size": refine.size, "subtract": true, "points": refine.points]])
      XCTAssertEqual(refinement, 200)
      let application = try await helper.edit(service, doc, RemoveToolAPI.name, ["operation": "apply"])
      XCTAssertEqual(application, 200)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertEqual(store.document, source)
    }
  }
}
