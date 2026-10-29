import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class FillWorkflowTests: XCTestCase {
  @MainActor func testFillCreationSelectionColorUndoAndNativeArchive() async throws {
    let s = EditorStore(document: try CraftDocument(width: 16, height: 12))
    defer { s.renderTask?.cancel() }
    s.perform(.selection(IntRect(x: 2, y: 3, width: 5, height: 4)))
    let before = s.document
    s.brush.color = Pixel(0.2, 0.4, 0.6, 0.5)
    s.addSolidColorLayer()
    let fill = try XCTUnwrap(s.activeLayer)
    XCTAssertEqual(fill.content, .fill(Pixel(0.2, 0.4, 0.6)))
    XCTAssertEqual(fill.mask?.pixel(x: 2, y: 3).r, 1)
    XCTAssertEqual(fill.mask?.pixel(x: 0, y: 0).r, 0)
    await s.undo()
    XCTAssertEqual(s.document, before)
    await s.redo()
    let created = s.document
    s.setSolidColor(fill.id, color: Pixel(0.8, 0.1, 0.3))
    XCTAssertEqual(s.activeLayer?.content, .fill(Pixel(0.8, 0.1, 0.3)))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(s.document)), s.document)
    await s.undo()
    XCTAssertEqual(s.document, created)
    s.perform(.lock(fill.id, true))
    s.setSolidColor(fill.id, color: .white)
    XCTAssertEqual(s.activeLayer?.content, fill.content)
    XCTAssertNotNil(s.error)
  }
}
