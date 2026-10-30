import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class CanvasPresentationTests: XCTestCase {
  @MainActor func testRequestRevisionsStayDistinctFromAcceptedPresentation() async throws {
    let store = EditorStore(document: try CraftDocument(width: 120, height: 80))
    await store.renderTask?.value
    let request = store.revision, presented = store.canvasPresentationRevision
    XCTAssertGreaterThan(presented, 0)
    store.render()
    XCTAssertEqual(store.revision, request + 1)
    XCTAssertEqual(store.canvasPresentationRevision, presented)
    store.render()
    XCTAssertEqual(store.revision, request + 2)
    XCTAssertEqual(store.canvasPresentationRevision, presented)
    await store.renderTask?.value
    XCTAssertEqual(store.canvasPresentationRevision, presented + 1)
    XCTAssertEqual(store.revision, request + 2)
    XCTAssertEqual(store.image?.width, 120)
  }

  @MainActor func testCancelledPreparationDoesNotPublishAndZoomStillPresents() async throws {
    let store = EditorStore(document: try CraftDocument(width: 120, height: 80))
    await store.renderTask?.value
    let presented = store.canvasPresentationRevision
    store.render(); store.renderTask?.cancel(); await store.renderTask?.value
    XCTAssertEqual(store.canvasPresentationRevision, presented)
    store.updateViewport(size: CGSize(width: 240, height: 160), backingScale: 1)
    store.setZoom(0.5, center: true); await store.renderTask?.value
    XCTAssertGreaterThan(store.canvasPresentationRevision, presented)
    let preview = try XCTUnwrap(store.canvasRasterPreview)
    XCTAssertEqual(preview.presentation?.image.width, 60)
    XCTAssertEqual(preview.presentation?.image.height, 40)
    XCTAssertEqual(preview.base.width, 120)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
