import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class FocusWorkflowTests: XCTestCase {
  @MainActor func store(_ tool: FocusTool, empty: Bool = false) throws -> EditorStore {
    var doc = try CraftDocument(width: 72, height: 56, depth: .u16)
    var pixels = try Surface(width: 72, height: 56, depth: .u16)
    for y in 0..<56 {
      for x in 0..<72 { pixels.setPixel(x: x, y: y, Pixel(x < 30 ? 0.8 : 0.2, 0.2, 0.5)) }
    }
    doc.layers[0].content = .raster(pixels)
    if empty {
      let retouch = Layer(
        name: "Retouch", content: .raster(try Surface(width: 1, height: 1, depth: .u16)))
      doc.layers.append(retouch)
      doc.activeLayerID = retouch.id
    }
    let s = EditorStore(document: doc, cloneState: CloneSources())
    s.chooseTool(WorkspaceCatalog.tool(tool.rawValue.lowercased()))
    s.retouchSettings.brush.size = 12
    s.retouchSettings.brush.hardness = 1
    s.retouchSettings.brush.pressureSize = false
    s.retouchSettings.focus.strength = 0.8
    s.retouchSettings.focus.protectDetail = false
    return s
  }
  @MainActor func stop(_ s: EditorStore) {
    s.cancelClone()
    s.renderTask?.cancel()
    s.clonePrepareTask?.cancel()
    s.geometryTask?.cancel()
    s.cloneOverlayTask?.cancel()
  }
  @MainActor func paint(_ s: EditorStore) {
    s.beginClone(.init(x: s.tool == .smudge ? 24.5 : 29.5, y: 24.5))
    if s.tool == .smudge { s.extendClone(.init(x: 40.5, y: 24.5)) }
  }
  @MainActor func finish(_ s: EditorStore) async {
    s.finishClone()
    await s.clonePrepareTask?.value
    await s.geometryTask?.value
    await s.renderTask?.value
  }
  @MainActor func testPreviewCancelAndOneUndoForAllTools() async throws {
    for kind in FocusTool.allCases {
      let s = try store(kind)
      defer { stop(s) }
      let before = s.document
      paint(s)
      await s.clonePrepareTask?.value
      await s.renderTask?.value
      XCTAssertNil(s.error)
      XCTAssertEqual(s.document, before)
      XCTAssertTrue(s.session.undoStack.isEmpty)
      let preview = try XCTUnwrap(s.surface)
      XCTAssertNotEqual(preview, try Renderer.composite(before))
      s.cancelClone()
      await s.renderTask?.value
      XCTAssertEqual(s.document, before)
      XCTAssertEqual(s.surface, try Renderer.composite(before))
      paint(s)
      await finish(s)
      XCTAssertNil(s.error)
      XCTAssertEqual(s.session.undoStack.count, 1)
      XCTAssertEqual(s.surface, preview)
      let after = s.document
      await s.undo()
      XCTAssertEqual(s.document, before)
      await s.redo()
      XCTAssertEqual(s.document, after)
    }
  }
  @MainActor func testSampleAllLayersCapturesSettingsAndSourceAndLeavesBaseUntouched() async throws
  {
    for kind in FocusTool.allCases {
      let s = try store(kind, empty: true)
      defer { stop(s) }
      let before = s.document
      s.retouchSettings.focus.sampleAllLayers = true
      paint(s)
      // Changing shared settings cannot change a captured gesture or source request.
      s.retouchSettings.focus.sampleAllLayers = false
      s.retouchSettings.focus.strength = 0
      await finish(s)
      XCTAssertNil(s.error)
      XCTAssertEqual(s.document.layers[0], before.layers[0])
      XCTAssertEqual(s.session.undoStack.count, 1)
      guard case .raster(let p) = s.activeLayer?.content else { return XCTFail("Expected raster") }
      XCTAssertGreaterThan(p.pixel(x: 29, y: 24).a, 0.9)
      XCTAssertNil(s.cloneState.slot.source)
      XCTAssertNil(s.cloneState.slot.anchor)
      await s.undo()
      XCTAssertEqual(s.document, before)
    }
  }
  @MainActor func testIndependentToolsLocksAndCancelledSwitch() async throws {
    let s = try store(.blur)
    defer { stop(s) }
    s.retouchSettings.focus.strength = 0.2
    s.chooseTool(WorkspaceCatalog.tool("sharpen"))
    XCTAssertEqual(s.retouchSettings.focus.strength, 0.5)
    s.retouchSettings.focus.protectDetail = false
    s.chooseTool(WorkspaceCatalog.tool("smudge"))
    XCTAssertTrue(s.retouchSettings.focus.protectDetail)
    s.chooseTool(WorkspaceCatalog.tool("blur"))
    XCTAssertEqual(s.retouchSettings.focus.strength, 0.2)
    let before = s.document
    paint(s)
    s.chooseTool(WorkspaceCatalog.tool("brush"))
    await s.clonePrepareTask?.value
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
    s.chooseTool(WorkspaceCatalog.tool("blur"))
    s.perform(.lock(s.activeLayer!.id, true))
    XCTAssertFalse(s.canClone)
    paint(s)
    XCTAssertNil(s.cloneDraft)
    XCTAssertNotNil(s.error)
  }
  @MainActor func testCanvasOptionFingerPaintingDragBracketsAndEscape() async throws {
    let s = try store(.smudge, empty: true)
    defer { stop(s) }
    s.brush.color = Pixel(0.9, 0.1, 0.3)
    let canvas = CraftCanvas(store: s)
    canvas.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
    func mouse(_ type: NSEvent.EventType, _ x: Double, _ flags: NSEvent.ModifierFlags = []) throws
      -> NSEvent
    {
      let point = canvas.viewPoint(CGPoint(x: x, y: 24.5))
      return try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: canvas.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    func key(_ text: String, _ code: UInt16) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
          context: nil,
          characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }
    canvas.keyDown(with: try key("]", 30))
    XCTAssertEqual(s.retouchSettings.brush.size, 17)
    canvas.keyDown(with: try key("[", 33))
    XCTAssertEqual(s.retouchSettings.brush.size, 12)
    canvas.mouseDown(with: try mouse(.leftMouseDown, 24.5, .option))
    XCTAssertEqual(s.cloneDraft?.focusOptions.fingerPainting, true)
    s.brush.color = .black
    canvas.mouseDragged(with: try mouse(.leftMouseDragged, 40.5, .option))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 40.5, .option))
    await s.clonePrepareTask?.value
    await s.geometryTask?.value
    await s.renderTask?.value
    XCTAssertNil(s.error)
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertFalse(s.retouchSettings.focus.fingerPainting)
    guard case .raster(let pixels) = s.activeLayer?.content else {
      return XCTFail("Expected raster")
    }
    XCTAssertGreaterThan(pixels.pixel(x: 24, y: 24).r, 0.8)
    let before = s.document
    canvas.mouseDown(with: try mouse(.leftMouseDown, 30, .option))
    canvas.keyDown(with: try key("\u{1b}", 53))
    await s.clonePrepareTask?.value
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
  }
}
