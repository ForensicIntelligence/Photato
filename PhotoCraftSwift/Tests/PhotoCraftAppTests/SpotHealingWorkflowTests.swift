import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class SpotHealingWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var d = try CraftDocument(width: 80, height: 60, depth: .u16)
    var pixels = try Surface(width: 80, height: 60, depth: .u16, fill: Pixel(0.6, 0.5, 0.4))
    for y in 28...32 { for x in 38...42 { pixels.setPixel(x: x, y: y, Pixel(0.03, 0.03, 0.03)) } }
    d.layers[0].content = .raster(pixels)
    let s = EditorStore(document: d, cloneState: CloneSources())
    s.chooseTool(WorkspaceCatalog.tool("spotHealing"))
    s.retouchSettings.brush.size = 12
    s.retouchSettings.brush.hardness = 1
    s.retouchSettings.brush.pressureSize = false
    return s
  }
  @MainActor func stop(_ s: EditorStore) {
    s.cancelClone()
    s.renderTask?.cancel()
    s.clonePrepareTask?.cancel()
    s.geometryTask?.cancel()
    s.cloneOverlayTask?.cancel()
  }
  @MainActor func finish(_ s: EditorStore) async {
    s.finishClone()
    await s.clonePrepareTask?.value
    await s.geometryTask?.value
    await s.renderTask?.value
  }
  @MainActor func testMarkerPreviewCancellationAndOneUndoForAllTypes() async throws {
    for kind in SpotHealingType.allCases {
      let s = try store()
      defer { stop(s) }
      s.retouchSettings.spotType = kind
      let before = s.document
      XCTAssertNil(s.cloneState.slot.source)
      s.beginClone(.init(x: 40, y: 30))
      await s.clonePrepareTask?.value
      await s.renderTask?.value
      XCTAssertNil(s.error)
      XCTAssertEqual(s.document, before)
      XCTAssertTrue(s.session.undoStack.isEmpty)
      XCTAssertLessThan(try XCTUnwrap(s.surface).pixel(x: 40, y: 30).r, 0.03)
      s.cancelClone()
      await s.renderTask?.value
      XCTAssertEqual(s.document, before)
      XCTAssertEqual(s.surface, try Renderer.composite(before))
      s.beginClone(.init(x: 40, y: 30))
      await finish(s)
      XCTAssertNil(s.error)
      XCTAssertEqual(s.session.undoStack.count, 1)
      XCTAssertGreaterThan(try XCTUnwrap(s.surface).pixel(x: 40, y: 30).r, 0.5)
      XCTAssertNil(s.cloneState.slot.anchor)
      XCTAssertNil(s.cloneState.slot.source)
      let after = s.document
      await s.undo()
      XCTAssertEqual(s.document, before)
      await s.redo()
      XCTAssertEqual(s.document, after)
    }
  }
  @MainActor func testSampleAllLayersCapturedOnEmptyTargetAndSettingsStayIndependent() async throws
  {
    let s = try store()
    defer { stop(s) }
    let base = s.document.layers[0]
    var empty = Layer(
      name: "Retouch", content: .raster(try Surface(width: 1, height: 1, depth: .u16)))
    empty.x = 20
    empty.y = 20
    s.perform(.addLayer(empty))
    s.select(empty.id)
    s.retouchSettings.sampling = .all
    s.retouchSettings.spotType = .proximityMatch
    s.beginClone(.init(x: 40, y: 30))
    await s.clonePrepareTask?.value
    s.retouchSettings.sampling = .current
    s.retouchSettings.spotType = .createTexture
    XCTAssertEqual(s.cloneDraft?.spot, .proximityMatch)
    await finish(s)
    XCTAssertNil(s.error)
    XCTAssertEqual(s.document.layers[0], base)
    guard case .raster(let repaired) = s.activeLayer?.content else { return XCTFail() }
    let layer = try XCTUnwrap(s.activeLayer)
    XCTAssertEqual(repaired.pixel(x: 40 - layer.x, y: 30 - layer.y).a, 1)
    XCTAssertGreaterThan(repaired.pixel(x: 40 - layer.x, y: 30 - layer.y).r, 0.5)
    XCTAssertEqual(repaired.pixel(x: 25 - layer.x, y: 25 - layer.y), .clear)
    s.chooseTool(WorkspaceCatalog.tool("healing"))
    XCTAssertEqual(s.retouchSettings.sampling, .current)
    s.chooseTool(WorkspaceCatalog.tool("spotHealing"))
    XCTAssertEqual(s.retouchSettings.spotType, .createTexture)
    s.perform(.lock(layer.id, true))
    XCTAssertFalse(s.canClone)
  }
  @MainActor func testCanvasJClickDragBracketsEscapeAndToolSwitch() async throws {
    let s = try store()
    defer { stop(s) }
    XCTAssertTrue(s.chooseShortcut("j", cycle: false))
    XCTAssertEqual(s.tool, .spotHealing)
    let canvas = CraftCanvas(store: s)
    canvas.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
    func mouse(_ type: NSEvent.EventType, _ x: Double) throws -> NSEvent {
      let p = canvas.viewPoint(CGPoint(x: x, y: 30))
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
    canvas.keyDown(with: try key("]", 30))
    XCTAssertEqual(s.retouchSettings.brush.size, 17)
    canvas.keyDown(with: try key("[", 33))
    XCTAssertEqual(s.retouchSettings.brush.size, 12)
    canvas.mouseDown(with: try mouse(.leftMouseDown, 38))
    canvas.mouseDragged(with: try mouse(.leftMouseDragged, 42))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 42))
    await s.clonePrepareTask?.value
    await s.geometryTask?.value
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertNil(s.error)
    let before = s.document
    canvas.mouseDown(with: try mouse(.leftMouseDown, 40))
    canvas.keyDown(with: try key("\u{1b}", 53))
    await s.clonePrepareTask?.value
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
    canvas.mouseDown(with: try mouse(.leftMouseDown, 40))
    s.chooseTool(WorkspaceCatalog.tool("brush"))
    await s.clonePrepareTask?.value
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
  }
}
