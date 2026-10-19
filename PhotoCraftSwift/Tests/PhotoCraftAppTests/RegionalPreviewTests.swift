import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class RegionalPreviewTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var d = try CraftDocument(width: 200, height: 140, depth: .u16)
    var s = try Surface(width: 200, height: 140, depth: .u16)
    for y in 0..<140 {
      for x in 0..<200 { s.setPixel(x: x, y: y, Pixel(Float(x) / 199, Float(y) / 139, 0.3)) }
    }
    d.layers[0].content = .raster(s)
    return EditorStore(document: d, cloneState: CloneSources())
  }
  @MainActor func verify(_ s: EditorStore, document: CraftDocument? = nil) async throws {
    await s.renderTask?.value
    XCTAssertNil(s.error)
    let expected = try Renderer.composite(document ?? s.document)
    XCTAssertEqual(try s.surface?.rgbaData(depth: .f32), try expected.rgbaData(depth: .f32))
    XCTAssertEqual(s.renderSnapshot?.surface, s.surface)
  }
  @MainActor func stop(_ s: EditorStore) {
    s.renderTask?.cancel()
    s.clonePrepareTask?.cancel()
    s.cloneOverlayTask?.cancel()
    s.geometryTask?.cancel()
  }

  @MainActor func testClonePreviewCancelCommitUndoAndRedoReuseCorrectSnapshot() async throws {
    let s = try store()
    defer { stop(s) }
    await s.renderTask?.value
    XCTAssertEqual(s.renderSnapshot?.update, .full)
    s.chooseTool(WorkspaceCatalog.tool("clone"))
    s.cloneState.brush.size = 12
    s.cloneState.brush.hardness = 0.8
    s.setCloneSource(at: .init(10.5, 10.5))
    s.beginClone(.init(x: 90.5, y: 90.5))
    await s.clonePrepareTask?.value
    var preview = s.document
    try XCTUnwrap(s.cloneDraft?.command).apply(to: &preview)
    try await verify(s, document: preview)
    guard case .region = s.renderSnapshot?.update else { return XCTFail("Expected local preview") }
    let original = s.document
    s.extendClone(.init(x: 151.5, y: 95.5))
    s.cancelClone()
    try await verify(s)
    XCTAssertEqual(s.document, original)
    XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginClone(.init(x: 140.5, y: 90.5))
    await s.clonePrepareTask?.value
    await s.renderTask?.value
    s.finishClone()
    await s.geometryTask?.value
    try await verify(s)
    XCTAssertEqual(s.session.undoStack.count, 1)
    s.undo()
    try await verify(s)
    XCTAssertEqual(s.document, original)
    s.redo()
    try await verify(s)
    guard case .region = s.renderSnapshot?.update else { return XCTFail("Expected regional redo") }
  }

  @MainActor func testRapidEditsAndChannelSwitchKeepNewestPixelsAndSelection() async throws {
    let s = try store()
    defer { stop(s) }
    await s.renderTask?.value
    let id = try XCTUnwrap(s.activeLayer?.id)
    for i in 0..<6 {
      s.perform(.selection(IntRect(x: 64 + i, y: 64, width: 5, height: 6)))
      s.perform(.fill(id, Pixel(Float(i) / 5, 0.2, 0.7)))
    }
    try await verify(s)
    guard case .region = s.renderSnapshot?.update else { return XCTFail("Expected regional edit") }
    s.displayChannel = 0
    await s.renderTask?.value
    XCTAssertEqual(s.renderSnapshot?.update, .unchanged)
    var gray = try XCTUnwrap(s.surface)
    gray.mapPixels { _, _, p in Pixel(p.r, p.r, p.r, p.a) }
    let data = try XCTUnwrap(s.image?.dataProvider?.data) as Data
    XCTAssertEqual(data, try gray.rgbaData(depth: .u8))
    s.displayChannel = nil
    try await verify(s)
    let restored = try XCTUnwrap(s.image?.dataProvider?.data) as Data
    XCTAssertEqual(restored, try s.surface?.rgbaData(depth: .u8))
    XCTAssertEqual(s.renderSnapshot?.document.selection, s.document.selection)
  }

  @MainActor func testFailedRenderKeepsLastValidCacheAndDocumentReplacementInvalidates()
    async throws
  {
    let s = try store()
    defer { stop(s) }
    await s.renderTask?.value
    let before = try XCTUnwrap(s.renderSnapshot)
    var bad = s.document
    bad.layers[0].opacity = .nan
    s.session = EditorSession(document: bad)
    s.render()
    await s.renderTask?.value
    XCTAssertNotNil(s.error)
    XCTAssertEqual(s.renderSnapshot?.document, before.document)
    XCTAssertEqual(s.surface, before.surface)
    var replacement = before.document
    replacement.id = UUID()
    replacement.layers[0].content = .fill(.black)
    s.session = EditorSession(document: replacement)
    s.error = nil
    s.render()
    try await verify(s)
    XCTAssertEqual(s.renderSnapshot?.update, .full)
  }
}
