import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class TransformWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var d = try CraftDocument(width: 40, height: 30)
    var layer = Layer(
      name: "Shape",
      content: .shape(ShapeContent(kind: .rectangle, width: 10, height: 6, color: Pixel(1, 0, 0))))
    layer.x = 4
    layer.y = 3
    d.layers = [layer]
    d.activeLayerID = layer.id
    let store = EditorStore(document: d)
    store.renderTask?.cancel()
    return store
  }
  @MainActor func testTransformPreviewCancelDoesNotMutateDocumentOrHistory() throws {
    let s = try store()
    let original = s.document
    s.beginTransform()
    var draft = try XCTUnwrap(s.transformDraft)
    draft.angle = 45
    draft.scaleX = 150
    s.updateTransform(draft)
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, original)
    XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertNotEqual(s.previewDocument, original)
    s.cancelTransform()
    s.renderTask?.cancel()
    XCTAssertEqual(s.previewDocument, original)
    XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testTransformCommitCreatesOneUndoStepAndPreservesLiveShape() async throws {
    let s = try store()
    let original = s.document
    s.beginTransform()
    var draft = try XCTUnwrap(s.transformDraft)
    draft.angle = 90
    draft.scaleX = 200
    draft.scaleY = 200
    s.updateTransform(draft)
    s.commitTransform()
    await s.geometryTask?.value
    s.renderTask?.cancel()
    XCTAssertNil(s.error)
    XCTAssertNil(s.transformDraft)
    XCTAssertEqual(s.session.undoStack.count, 1)
    guard case .shape = s.document.layers[0].content else { return XCTFail("Shape rasterized") }
    XCTAssertNotEqual(s.document, original)
    await s.undo()
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, original)
    await s.redo()
    s.renderTask?.cancel()
    XCTAssertNotEqual(s.document, original)
  }
  func testTransformHandlesMaintainOppositeAnchorAndOptionCenter() {
    let draft = TransformDraft(
      layerID: UUID(), bounds: IntRect(x: 10, y: 20, width: 100, height: 50))
    let from = draft.handles[4]
    let scaled = draft.dragging(
      handle: 4, from: from, to: CGPoint(x: 210, y: 120), shift: false, option: false)
    XCTAssertEqual(scaled.scaleX, 200, accuracy: 1e-8)
    XCTAssertEqual(scaled.scaleY, 200, accuracy: 1e-8)
    XCTAssertEqual(scaled.handles[0], draft.handles[0])
    let centered = draft.dragging(
      handle: 4, from: from, to: CGPoint(x: 160, y: 95), shift: false, option: true)
    XCTAssertEqual(centered.centerX, draft.centerX)
    XCTAssertEqual(centered.centerY, draft.centerY)
    XCTAssertEqual(centered.scaleX, 200, accuracy: 1e-8)
    let stretched = draft.dragging(
      handle: 4, from: from, to: CGPoint(x: 210, y: 70), shift: true, option: false)
    XCTAssertEqual(stretched.scaleX, 200, accuracy: 1e-8)
    XCTAssertEqual(stretched.scaleY, 100, accuracy: 1e-8)
  }
  @MainActor func testAutoSelectFindsRotatedShapeInDocumentCoordinates() async throws {
    let s = try store()
    let selected = try XCTUnwrap(s.activeLayer?.id)
    s.performGeometry(.transform(selected, .translation(20, 0) * .rotation(90), .nearest))
    await s.geometryTask?.value
    s.renderTask?.cancel()
    let other = Layer(name: "Other", content: .raster(try Surface(width: 1, height: 1)))
    s.perform(.addLayer(other))
    s.renderTask?.cancel()
    XCTAssertEqual(s.document.activeLayerID, other.id)
    s.autoSelectLayer(at: CGPoint(x: 15, y: 6))
    XCTAssertEqual(s.document.activeLayerID, selected)
    let bounds = try XCTUnwrap(s.activeLayerBounds)
    XCTAssertEqual(bounds, IntRect(x: 11, y: 4, width: 6, height: 10))
  }
  @MainActor func testCancelledBackgroundGeometryLeavesOriginalDocument() async throws {
    let s = try store()
    let original = s.document
    s.performGeometry(.imageSize(80, 60, 300, .bicubic))
    s.geometryTask?.cancel()
    await s.geometryTask?.value
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, original)
    XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertFalse(s.geometryBusy)
  }
  func testPreparedResultRejectsChangedDocument() throws {
    let d = try CraftDocument(width: 8, height: 8)
    let prepared = try PreparedEdit(command: .imageSize(16, 16, 72, .nearest), document: d)
    var session = EditorSession(document: d)
    try session.execute(.renameLayer(d.layers[0].id, "Changed"))
    let changed = session.document
    XCTAssertThrowsError(try session.executePrepared(prepared))
    XCTAssertEqual(session.document, changed)
  }
  @MainActor func testRasterizeTransformedShapePreservesVisibleBoundsAndMask() async throws {
    let s = try store()
    s.addMask()
    let id = try XCTUnwrap(s.activeLayer?.id)
    s.performGeometry(.transform(id, .translation(20, 0) * .rotation(90), .nearest))
    await s.geometryTask?.value
    s.renderTask?.cancel()
    let before = try Renderer.composite(s.document)
    s.rasterize()
    s.renderTask?.cancel()
    XCTAssertNil(s.error)
    XCTAssertNil(s.activeLayer?.affine)
    XCTAssertEqual(try Renderer.composite(s.document), before)
  }
}
