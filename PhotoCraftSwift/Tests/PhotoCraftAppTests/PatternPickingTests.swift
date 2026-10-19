import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class PatternPickingTests: XCTestCase {
  @MainActor func testLargeCanvasPatternPickingRetainsAlphaMaskEdgesAndUndoState() throws {
    var doc = try CraftDocument(width: 6000, height: 4000)
    let background = doc.layers[0].id
    var surface = try Surface(width: 2, height: 1, depth: .f32, fill: .white)
    surface.setPixel(x: 1, y: 0, .clear)
    let tile = try RasterPattern(name: "Picking", surface: surface)
    var layer = Layer(name: "Fill", content: .patternFill(PatternFill(patternID: tile.id)))
    layer.mask = try Surface(width: 6000, height: 4000, fill: .white)
    layer.opacity = 0.015
    try Command.addPatternFill(layer, tile).apply(to: &doc)
    let store = EditorStore(document: doc, patterns: PatternLibrary())
    store.renderTask?.cancel()
    defer { store.renderTask?.cancel() }
    store.autoSelectLayer(at: CGPoint(x: 3000.5, y: 2000.5))
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.activeLayerID, layer.id)
    store.autoSelectLayer(at: CGPoint(x: 3001.5, y: 2000.5))
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.activeLayerID, background)
    store.autoSelectLayer(at: CGPoint(x: 0.1, y: 0.5))
    store.renderTask?.cancel()
    XCTAssertEqual(
      store.document.activeLayerID, background,
      "Continuous mask coverage keeps opacity below the picking threshold")
    store.autoSelectLayer(at: CGPoint(x: CGFloat.infinity, y: 10))
    XCTAssertEqual(store.document.activeLayerID, background)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(store.document.patterns, doc.patterns)
  }
}
