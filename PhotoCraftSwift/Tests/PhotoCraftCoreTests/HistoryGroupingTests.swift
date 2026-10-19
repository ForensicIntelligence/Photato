import PhotoCraftCore
import XCTest

final class HistoryGroupingTests: XCTestCase {
  func testOpacityDragIsOneHistoryStep() throws {
    var session = EditorSession(document: try CraftDocument(width: 2, height: 2))
    let id = try XCTUnwrap(session.document.activeLayerID)
    session.beginCoalescing()
    for opacity: Float in [0.9, 0.7, 0.5, 0.25] { try session.execute(.opacity(id, opacity)) }
    session.endCoalescing()
    XCTAssertEqual(session.undoStack.count, 1)
    session.undo()
    XCTAssertEqual(session.document.layers[0].opacity, 1)
    session.redo()
    XCTAssertEqual(session.document.layers[0].opacity, 0.25)
  }
}
extension HistoryGroupingTests {
  func testHistoryRespectsMemoryBudget() throws {
    var document = try CraftDocument(width: 64, height: 64)
    var surface = try Surface(width: 64, height: 64)
    surface.setPixel(x: 1, y: 1, .white)
    document.layers[0].content = .raster(surface)
    var session = EditorSession(document: document, historyByteLimit: 65_536)
    let id = try XCTUnwrap(document.activeLayerID)
    try session.execute(.renameLayer(id, "first"))
    try session.execute(.renameLayer(id, "second"))
    XCTAssertEqual(session.undoStack.count, 1)
    session.undo()
    XCTAssertEqual(session.document.layers[0].name, "first")
  }
}
