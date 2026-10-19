import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class PatternFillWorkflowTests: XCTestCase {
  @MainActor func testCreatePreviewCancelAndCommitCaptureTileWithOneUndoStep() async throws {
    var doc = try CraftDocument(width: 80, height: 60)
    doc.selection = .init(x: 10, y: 10, width: 40, height: 30)
    let library = PatternLibrary()
    library.selectedID = library.items[4].id
    let preset = try XCTUnwrap(library.selected)
    let store = EditorStore(document: doc, patterns: library)
    defer { store.renderTask?.cancel() }
    XCTAssertTrue(store.canBeginPatternFill)
    store.beginPatternFill()
    store.patternFillDraft?.fill.placement.scale = 150
    store.render()
    await store.renderTask?.value
    XCTAssertTrue(store.document == doc)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    var preview = doc
    try XCTUnwrap(store.patternFillDraft).command.apply(to: &preview)
    XCTAssertEqual(
      try XCTUnwrap(store.surface).rgbaData(depth: .f32),
      try Renderer.composite(preview).rgbaData(depth: .f32))
    store.patternFillDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(
      try XCTUnwrap(store.surface).rgbaData(depth: .f32),
      try Renderer.composite(doc).rgbaData(depth: .f32))
    XCTAssertFalse(store.canBeginPatternFill)
    store.cancelPatternFill()
    XCTAssertNil(store.patternFillDraft)
    XCTAssertTrue(store.document == doc)
    store.beginPatternFill()
    store.patternFillDraft?.fill.placement.angle = 30
    store.commitPatternFill()
    try await library.remove(preset.id)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.document.pattern(preset.id), preset)
    guard case .patternFill(let fill) = store.activeLayer?.content else {
      return XCTFail("Expected editable fill")
    }
    XCTAssertEqual(fill.placement.angle, 30)
    XCTAssertNotNil(store.activeLayer?.mask)
    let result = store.document
    store.undo()
    XCTAssertTrue(store.document == doc)
    store.redo()
    XCTAssertTrue(store.document == result)
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
    store.beginPatternFill()
    canvas.mouseDown(with: try mouse(.leftMouseDown, 30, 30))
    canvas.mouseDragged(with: try mouse(.leftMouseDragged, 37, 35))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 37, 35))
    XCTAssertEqual(store.patternFillDraft?.fill.placement.phaseX, 7)
    XCTAssertEqual(store.patternFillDraft?.fill.placement.phaseY, 5)
    XCTAssertTrue(store.document == original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    canvas.keyDown(with: try key("\u{1b}", 53))
    XCTAssertNil(store.patternFillDraft)
    XCTAssertTrue(store.document == original)
    store.beginPatternFill()
    store.patternFillDraft?.fill.linked = false
    canvas.mouseDown(with: try mouse(.leftMouseDown, 30, 30))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 37, 35))
    XCTAssertEqual(store.patternFillDraft?.fill.placement.phaseX, 0)
    canvas.keyDown(with: try key("\r", 36))
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.patternFillDraft)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.document.layers.count, 2)
  }
  @MainActor func testEditingReplacementSnapLocksAndCancelledBackgroundCommit() async throws {
    let library = PatternLibrary()
    let store = EditorStore(document: try CraftDocument(width: 40, height: 30), patterns: library)
    defer { store.renderTask?.cancel() }
    store.beginPatternFill()
    store.commitPatternFill()
    await store.geometryTask?.value
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.beginPatternFill(editing: id)
    let initial = try XCTUnwrap(store.patternFillDraft?.fill)
    store.dragPatternFill(from: initial, x: 12, y: -8)
    XCTAssertEqual(store.patternFillDraft?.fill.placement.phaseX, 12)
    store.snapPatternFill()
    XCTAssertEqual(store.patternFillDraft?.fill.placement.phaseX, 0)
    XCTAssertEqual(store.patternFillDraft?.fill.placement.phaseY, 0)
    let replacement = library.items[4]
    store.choosePattern(replacement)
    XCTAssertEqual(store.patternFillDraft?.pattern, replacement)
    let before = store.document
    store.commitPatternFill()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertTrue(store.document == before)
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.choosePattern(replacement)
    XCTAssertEqual(store.session.undoStack.count, 2)
    guard case .patternFill(let result) = store.activeLayer?.content else {
      return XCTFail("Expected pattern fill")
    }
    XCTAssertEqual(result.patternID, replacement.id)
    store.perform(.lock(id, true))
    XCTAssertFalse(store.canEditPatternFill(id))
    store.beginPatternFill(editing: id)
    XCTAssertNil(store.patternFillDraft)
  }
}
