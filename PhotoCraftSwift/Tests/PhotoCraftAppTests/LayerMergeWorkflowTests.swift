import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class LayerMergeWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var d = try CraftDocument(width: 5, height: 4)
    d.layers.append(
      Layer(
        name: "Top",
        content: .raster(
          try Surface(width: 3, height: 2, fill: Pixel(0.7, 0.2, 0.1, 0.6)))))
    d.activeLayerID = d.layers[1].id
    return EditorStore(document: d)
  }
  @MainActor func testDefaultMergeRoutingUndoAndCancellation() async throws {
    for operation in LayerMergeOperation.allCases {
      let s = try store()
      s.renderTask?.cancel()
      let before = s.document
      XCTAssertEqual(s.menuMergeOperation, .down)
      if operation == .selected { s.selectedLayerIDs = Set(s.document.layers.map(\.id)) }
      XCTAssertTrue(s.canMerge(operation))
      s.merge(operation)
      await s.geometryTask?.value
      s.renderTask?.cancel()
      XCTAssertNil(s.error)
      XCTAssertEqual(s.document.layers.count, 1)
      XCTAssertEqual(s.selectedLayerIDs, Set([try XCTUnwrap(s.document.activeLayerID)]))
      XCTAssertEqual(s.session.undoStack.last?.label, operation.rawValue)
      s.undo()
      s.renderTask?.cancel()
      XCTAssertEqual(s.document, before)
      s.selectedLayerIDs = Set(s.document.layers.map(\.id))
      s.merge(.selected)
      s.geometryTask?.cancel()
      await s.geometryTask?.value
      s.renderTask?.cancel()
      XCTAssertEqual(s.document, before)
    }
  }
  @MainActor func testUnavailableContextsAndFactoryShortcuts() throws {
    let s = try store()
    s.renderTask?.cancel()
    s.geometryBusy = true
    XCTAssertFalse(s.canMerge(.down))
    s.geometryBusy = false
    s.perform(.visibility(s.document.layers[0].id, false))
    s.renderTask?.cancel()
    XCTAssertEqual(s.menuMergeOperation, .selected)
    XCTAssertFalse(s.canMerge(.down))
    XCTAssertFalse(s.canMerge(.visible))
    try PhotoshopMenuTests().withMenus { _, menu in
      let layer = try XCTUnwrap(menu.item(withTitle: "Layer")?.submenu)
      let merge = try XCTUnwrap(layer.item(withTitle: "Merge Layers"))
      let visible = try XCTUnwrap(layer.item(withTitle: "Merge Visible"))
      XCTAssertEqual(merge.action, #selector(AppDelegate.mergeLayers))
      XCTAssertEqual(merge.keyEquivalent, "e")
      XCTAssertEqual(merge.keyEquivalentModifierMask, .command)
      XCTAssertEqual(visible.action, #selector(AppDelegate.mergeVisible))
      XCTAssertEqual(visible.keyEquivalent, "e")
      XCTAssertEqual(visible.keyEquivalentModifierMask, [.command, .shift])
      XCTAssertNil(layer.item(withTitle: "Flatten Image")?.action)
    }
  }
}
