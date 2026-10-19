import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class GradientFillWorkflowTests: XCTestCase {
  @MainActor func testCreateCapturesColorsPreviewCancelCommitAndOneUndo() async throws {
    var doc = try CraftDocument(width: 80, height: 60)
    doc.selection = .init(x: 10, y: 10, width: 40, height: 30)
    let store = EditorStore(document: doc)
    defer { store.renderTask?.cancel() }
    store.brush.color = Pixel(0.8, 0.2, 0.3)
    XCTAssertTrue(store.canBeginGradientFill)
    store.beginGradientFill()
    XCTAssertFalse(store.canBeginPatternFill)
    XCTAssertEqual(
      store.gradientFillDraft?.fill.gradient.colors.first?.color, .rgb(store.brush.color))
    store.brush.color = .white
    store.gradientFillDraft?.fill.placement.scale = 1.5
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, doc)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    var preview = doc
    try XCTUnwrap(store.gradientFillDraft).command.apply(to: &preview)
    XCTAssertEqual(
      try XCTUnwrap(store.surface).rgbaData(depth: .f32),
      try Renderer.composite(preview).rgbaData(depth: .f32))
    store.gradientFillDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(
      try XCTUnwrap(store.surface).rgbaData(depth: .f32),
      try Renderer.composite(doc).rgbaData(depth: .f32))
    store.cancelGradientFill()
    XCTAssertNil(store.gradientFillDraft)
    store.beginGradientFill()
    store.gradientFillDraft?.fill.placement.angle = 30
    store.commitGradientFill()
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.session.undoStack.count, 1)
    guard case .gradientFill(let fill) = store.activeLayer?.content else { return XCTFail() }
    XCTAssertEqual(fill.placement.angle, 30)
    XCTAssertNotNil(store.activeLayer?.mask)
    let result = store.document
    store.undo()
    XCTAssertEqual(store.document, doc)
    store.redo()
    XCTAssertEqual(store.document, result)
  }
  @MainActor func testCanvasDragKeyboardCancelAndCommitDoNotPaintUnderDraft() async throws {
    let store = EditorStore(
      document: try CraftDocument(width: 100, height: 80), patterns: PatternLibrary())
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("brush"))
    let original = store.document
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
    func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) throws -> NSEvent {
      let p = canvas.viewPoint(CGPoint(x: x, y: y))
      return try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: canvas.convert(p, to: nil), modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    func key(_ text: String, _ code: UInt16) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
          context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
          keyCode: code))
    }
    store.beginGradientFill()
    canvas.mouseDown(with: try mouse(.leftMouseDown, 30, 30))
    canvas.mouseDragged(with: try mouse(.leftMouseDragged, 37, 35))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 37, 35))
    XCTAssertEqual(store.gradientFillDraft?.fill.placement.offsetX, 0.07)
    XCTAssertEqual(store.gradientFillDraft?.fill.placement.offsetY, 0.0625)
    XCTAssertTrue(store.document == original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    canvas.keyDown(with: try key("\u{1b}", 53))
    XCTAssertNil(store.gradientFillDraft)
    XCTAssertTrue(store.document == original)
    store.beginGradientFill()
    store.gradientFillDraft?.fill.aligned = false
    canvas.mouseDown(with: try mouse(.leftMouseDown, 30, 30))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 37, 35))
    XCTAssertEqual(store.gradientFillDraft?.fill.placement.offsetX, 0.07)
    canvas.keyDown(with: try key("\r", 36))
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.gradientFillDraft)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.document.layers.count, 2)
  }
  @MainActor func testEditingReplacementLocksAndCancelledCommit() async throws {
    let store = EditorStore(document: try CraftDocument(width: 40, height: 30))
    defer { store.renderTask?.cancel() }
    store.beginGradientFill()
    store.commitGradientFill()
    await store.geometryTask?.value
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.beginGradientFill(editing: id)
    let initial = try XCTUnwrap(store.gradientFillDraft?.fill)
    store.dragGradientFill(from: initial, x: 12, y: -6)
    XCTAssertEqual(store.gradientFillDraft?.fill.placement.offsetX, 0.3)
    XCTAssertEqual(store.gradientFillDraft?.fill.placement.offsetY, -0.2)
    store.chooseGradient(.foregroundToTransparent)
    XCTAssertEqual(store.gradientFillDraft?.fill.gradient.opacity.last?.opacity, 0)
    let before = store.document
    store.commitGradientFill()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.perform(.lock(id, true))
    XCTAssertFalse(store.canEditGradientFill(id))
    store.beginGradientFill(editing: id)
    XCTAssertNil(store.gradientFillDraft)
  }
}
