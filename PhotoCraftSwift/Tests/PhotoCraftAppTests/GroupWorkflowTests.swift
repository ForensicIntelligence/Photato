import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class GroupWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var d = try CraftDocument(width: 20, height: 16)
    d.layers = (0..<3).map { n in
      var layer = Layer(
        name: "Shape \(n)",
        content: .shape(ShapeContent(kind: .rectangle, width: 4, height: 3, color: .white)))
      layer.x = n * 3
      layer.y = n * 2
      return layer
    }
    d.activeLayerID = d.layers[0].id
    let store = EditorStore(document: d)
    store.renderTask?.cancel()
    return store
  }
  @MainActor func testMultiselectionGroupingAndUndo() throws {
    let s = try store()
    let original = s.document
    s.select(original.layers[0].id)
    s.select(original.layers[1].id, modifiers: .command)
    XCTAssertEqual(s.selectedLayerIDs.count, 2)
    s.groupSelection()
    let group = try XCTUnwrap(s.activeLayer)
    XCTAssertTrue(group.isGroup)
    XCTAssertEqual(s.document.children(of: group.id).count, 2)
    XCTAssertEqual(s.selectedLayerIDs, [group.id])
    s.undo()
    XCTAssertEqual(s.document.layers, original.layers)
    s.renderTask?.cancel()
  }
  @MainActor func testGroupBoundsAndTransformPreviewMatchesCommittedGeometry() throws {
    let s = try store()
    let ids = s.document.layers.map(\.id)
    s.select(ids[0])
    s.select(ids[2], modifiers: .shift)
    s.groupSelection()
    let before = s.document
    XCTAssertEqual(s.activeLayerBounds, IntRect(x: 0, y: 0, width: 10, height: 7))
    s.beginTransform()
    var draft = try XCTUnwrap(s.transformDraft)
    draft.centerX += 2
    draft.centerY += 3
    s.updateTransform(draft)
    let preview = s.previewDocument
    var committed = before
    try Command.transform(draft.layerID, draft.delta, .nearest).apply(to: &committed)
    for id in ids {
      let a = try XCTUnwrap(preview.layers.first { $0.id == id })
      let b = try XCTUnwrap(committed.layers.first { $0.id == id })
      XCTAssertEqual(a.coordinateTransform, b.coordinateTransform)
    }
    s.cancelTransform()
    XCTAssertEqual(s.document, before)
    s.renderTask?.cancel()
  }
  @MainActor func testLayerPickingRespectsHiddenGroupAndClipBaseCoverage() throws {
    let s = try store()
    let ids = s.document.layers.map(\.id)
    s.perform(.clipping(ids[1], true))
    s.select(ids[2])
    // Top clipped layer covers this point, but its base does not.
    s.autoSelectLayer(at: CGPoint(x: 5, y: 3))
    XCTAssertEqual(s.activeLayer?.id, ids[2])
    s.perform(.groupLayers([ids[0], ids[1]], "Group"))
    let group = s.activeLayer!.id
    s.perform(.visibility(group, false))
    s.select(ids[2])
    s.autoSelectLayer(at: CGPoint(x: 1, y: 1))
    XCTAssertEqual(s.activeLayer?.id, ids[2])
    s.perform(.visibility(group, true))
    s.autoSelectLayer(at: CGPoint(x: 1, y: 1))
    XCTAssertEqual(s.activeLayer?.id, ids[0])
    s.renderTask?.cancel()
  }
  @MainActor func testMaskOnMovedGroupUsesDocumentSelectionCoordinates() throws {
    let s = try store()
    s.groupSelection()
    let group = s.activeLayer!.id
    s.perform(.move(group, 3, 2))
    s.perform(.selection(IntRect(x: 3, y: 2, width: 2, height: 2)))
    s.addMask()
    let layer = try XCTUnwrap(s.activeLayer)
    let mask = try MaskSampler(layer: layer)
    XCTAssertEqual(mask.coverage(x: 3.5, y: 2.5), 1)
    XCTAssertEqual(mask.coverage(x: 5.5, y: 2.5), 0)
    s.undo()
    XCTAssertNil(s.activeLayer?.mask)
    s.renderTask?.cancel()
  }
}
