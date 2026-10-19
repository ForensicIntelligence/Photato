import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ToningWorkflowTests: XCTestCase {
  @MainActor func store(_ tool: ToningTool) throws -> EditorStore {
    var doc = try CraftDocument(width: 80, height: 60, depth: .u16)
    doc.layers[0].content = .raster(
      try Surface(width: 80, height: 60, depth: .u16, fill: Pixel(0.7, 0.4, 0.3)))
    let s = EditorStore(document: doc, cloneState: CloneSources())
    s.chooseTool(WorkspaceCatalog.tool(tool.rawValue.lowercased()))
    s.retouchSettings.brush.size = 16
    s.retouchSettings.brush.hardness = 1
    s.retouchSettings.brush.pressureSize = false
    return s
  }
  @MainActor func stop(_ s: EditorStore) {
    s.cancelClone()
    s.renderTask?.cancel()
    s.geometryTask?.cancel()
    s.clonePrepareTask?.cancel()
    s.cloneOverlayTask?.cancel()
  }
  @MainActor func testAllToolsPreviewCancelCaptureAndCommitOneUndo() async throws {
    for tool in ToningTool.allCases {
      let s = try store(tool)
      defer { stop(s) }
      let before = s.document
      s.beginClone(.init(x: 40, y: 30))
      s.extendClone(.init(x: 45, y: 30))
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
      s.beginClone(.init(x: 40, y: 30))
      s.extendClone(.init(x: 45, y: 30))
      // A running stroke keeps its captured settings even if another document changes this tool.
      s.retouchSettings.toning.exposure = 0
      s.retouchSettings.brush.flow = 0
      s.finishClone()
      await s.geometryTask?.value
      await s.renderTask?.value
      XCTAssertNil(s.error)
      XCTAssertEqual(s.surface, preview)
      XCTAssertEqual(s.session.undoStack.count, 1)
      XCTAssertNil(s.cloneState.slot.source)
      XCTAssertNil(s.cloneState.slot.anchor)
      let after = s.document
      s.undo()
      XCTAssertEqual(s.document, before)
      s.redo()
      XCTAssertEqual(s.document, after)
    }
  }
  @MainActor func testIndependentSettingsLocksMaskAndToolSwitchCancellation() async throws {
    let s = try store(.burn)
    defer { stop(s) }
    s.retouchSettings.toning.range = .highlights
    s.retouchSettings.toning.exposure = 0.8
    s.chooseTool(WorkspaceCatalog.tool("dodge"))
    XCTAssertEqual(s.retouchSettings.toning.range, .midtones)
    XCTAssertEqual(s.retouchSettings.toning.exposure, 0.5)
    s.chooseTool(WorkspaceCatalog.tool("burn"))
    XCTAssertEqual(s.retouchSettings.toning.range, .highlights)
    let before = s.document
    s.beginClone(.init(x: 40, y: 30))
    s.chooseTool(WorkspaceCatalog.tool("sponge"))
    await s.renderTask?.value
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
    s.perform(.lock(s.activeLayer!.id, true))
    XCTAssertFalse(s.canClone)
    s.beginClone(.init(x: 40, y: 30))
    XCTAssertNil(s.cloneDraft)
    XCTAssertNotNil(s.error)
    s.error = nil
    s.perform(.lock(s.activeLayer!.id, false))
    s.addMask()
    s.maskEditingLayerID = s.activeLayer?.id
    s.chooseTool(WorkspaceCatalog.tool("burn"))
    s.beginClone(.init(x: 40, y: 30))
    s.finishClone()
    await s.geometryTask?.value
    await s.renderTask?.value
    XCTAssertNil(s.error)
    XCTAssertEqual(s.document.layers[0].content, before.layers[0].content)
    XCTAssertLessThan(try XCTUnwrap(s.activeLayer?.mask).pixel(x: 40, y: 30).r, 1)
  }
  @MainActor func testCanvasOCyclingBracketsOptionSwapAndEscape() async throws {
    let s = try store(.dodge)
    defer { stop(s) }
    let canvas = CraftCanvas(store: s)
    canvas.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
    func key(_ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent
    {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
          windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
          isARepeat: false, keyCode: code))
    }
    func mouse(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
      let p = canvas.viewPoint(CGPoint(x: 40, y: 30))
      return try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: canvas.convert(p, to: nil), modifierFlags: flags,
          timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    canvas.keyDown(with: try key("o", 31, .shift))
    XCTAssertEqual(s.tool, .burn)
    canvas.keyDown(with: try key("o", 31, .shift))
    XCTAssertEqual(s.tool, .sponge)
    canvas.keyDown(with: try key("o", 31, .shift))
    XCTAssertEqual(s.tool, .dodge)
    canvas.keyDown(with: try key("]", 30))
    XCTAssertEqual(s.retouchSettings.brush.size, 21)
    canvas.keyDown(with: try key("[", 33))
    XCTAssertEqual(s.retouchSettings.brush.size, 16)
    let before = s.document
    canvas.mouseDown(with: try mouse(.leftMouseDown, .option))
    XCTAssertEqual(s.cloneDraft?.toning, .burn)
    canvas.mouseUp(with: try mouse(.leftMouseUp, .option))
    await s.geometryTask?.value
    await s.renderTask?.value
    XCTAssertEqual(s.tool, .dodge)
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertLessThan(try XCTUnwrap(s.surface).pixel(x: 40, y: 30).r, 0.7)
    s.undo()
    XCTAssertEqual(s.document, before)
    canvas.mouseDown(with: try mouse(.leftMouseDown))
    canvas.keyDown(with: try key("\u{1b}", 53))
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
  }
}
