import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class HealingWorkflowTests: XCTestCase {
  @MainActor func store(_ state: CloneSources) throws -> EditorStore {
    var d = try CraftDocument(width: 128, height: 64, depth: .u16)
    var pixels = try Surface(width: 128, height: 64, depth: .u16)
    for y in 0..<64 {
      for x in 0..<128 {
        let t: Float = (x / 4) % 2 == 0 ? 0.08 : -0.08
        pixels.setPixel(
          x: x, y: y, x < 64 ? Pixel(0.2 + t, 0.3 + t, 0.5 + t) : Pixel(0.8, 0.6, 0.3))
      }
    }
    d.layers[0].content = .raster(pixels)
    let store = EditorStore(document: d, cloneState: state)
    store.chooseTool(WorkspaceCatalog.tool("healing"))
    store.retouchSettings.brush.size = 30
    store.retouchSettings.brush.hardness = 1
    store.retouchSettings.brush.pressureSize = false
    return store
  }
  @MainActor func stop(_ store: EditorStore) {
    store.cancelClone()
    store.renderTask?.cancel()
    store.clonePrepareTask?.cancel()
    store.cloneOverlayTask?.cancel()
    store.geometryTask?.cancel()
  }
  @MainActor func finish(_ store: EditorStore) async {
    store.finishClone()
    await store.clonePrepareTask?.value
    await store.geometryTask?.value
    await store.renderTask?.value
  }
  @MainActor func testPreviewAndSingleUndoWithCapturedSettingsAndSource() async throws {
    let state = CloneSources()
    let s = try store(CloneSources())
    defer { stop(s) }
    XCTAssertEqual(s.tool, .healingBrush)
    s.setCloneSource(at: .init(32, 32))
    let before = s.document
    s.beginClone(.init(x: 96, y: 32))
    await s.clonePrepareTask?.value
    await s.renderTask?.value
    XCTAssertEqual(s.document, before)
    XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertFalse(s.canBeginLevels)
    XCTAssertFalse(s.clipboardTargetAvailable)
    let preview = try XCTUnwrap(s.surface)
    XCTAssertGreaterThan(preview.pixel(x: 96, y: 32).r, 0.65)
    let captured = try XCTUnwrap(s.cloneDraft).brush
    s.retouchSettings.brush.size = 3
    XCTAssertEqual(s.cloneDraft?.brush, captured)
    await finish(s)
    XCTAssertNil(s.error)
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertEqual(try Renderer.composite(s.document), preview)
    XCTAssertEqual(s.cloneState.slot.anchor, .init(96, 32))
    let after = s.document
    await s.undo()
    XCTAssertEqual(s.document, before)
    await s.redo()
    XCTAssertEqual(s.document, after)
  }
  @MainActor func testEmptyRetouchLayerCrossDocumentContextAndCancellation() async throws {
    let state = CloneSources()
    let source = try store(state)
    let target = try store(state)
    defer {
      stop(source)
      stop(target)
    }
    source.setCloneSource(at: .init(32, 32))
    let originalSource = source.document
    let empty = Layer(
      name: "Retouch", content: .raster(try Surface(width: 2, height: 2, depth: .u16)))
    target.perform(.addLayer(empty))
    target.select(empty.id)
    state.healing.sampling = .currentAndBelow
    target.beginClone(.init(x: 96, y: 32))
    await target.clonePrepareTask?.value
    XCTAssertNotNil(target.cloneDraft?.destination)
    let before = target.document
    target.cancelClone()
    await target.renderTask?.value
    XCTAssertEqual(target.document, before)
    XCTAssertNil(state.slot.anchor)
    target.beginClone(.init(x: 96, y: 32))
    await finish(target)
    XCTAssertNil(target.error)
    XCTAssertEqual(source.document, originalSource)
    guard case .raster(let result) = target.activeLayer?.content else { return XCTFail() }
    let layer = try XCTUnwrap(target.activeLayer)
    XCTAssertEqual(result.pixel(x: 96 - layer.x, y: 32 - layer.y).a, 1)
    XCTAssertGreaterThan(result.pixel(x: 96 - layer.x, y: 32 - layer.y).r, 0.65)
    XCTAssertEqual(result.pixel(x: 10 - layer.x, y: 10 - layer.y), .clear)
    target.beginClone(.init(x: 100, y: 32))
    target.chooseTool(WorkspaceCatalog.tool("clone"))
    await target.clonePrepareTask?.value
    XCTAssertNil(target.cloneDraft)
    XCTAssertEqual(state.sampling, .current)
    XCTAssertEqual(state.healing.sampling, .currentAndBelow)
  }
  @MainActor func testCanvasSamplingDragEscapeAndJGroupUseHealing() async throws {
    let state = CloneSources()
    let s = try store(state)
    defer { stop(s) }
    let canvas = CraftCanvas(store: s)
    canvas.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
    func mouse(_ type: NSEvent.EventType, _ x: Double, _ flags: NSEvent.ModifierFlags = []) throws
      -> NSEvent
    {
      let p = canvas.viewPoint(CGPoint(x: x, y: 32))
      return try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: canvas.convert(p, to: nil), modifierFlags: flags, timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    canvas.mouseDown(with: try mouse(.leftMouseDown, 32, .option))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 32, .option))
    XCTAssertEqual(state.slot.source, .init(32, 32))
    canvas.mouseDown(with: try mouse(.leftMouseDown, 92))
    canvas.mouseDragged(with: try mouse(.leftMouseDragged, 100))
    canvas.mouseUp(with: try mouse(.leftMouseUp, 100))
    await s.clonePrepareTask?.value
    await s.geometryTask?.value
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertNil(s.error)
    XCTAssertTrue(s.chooseShortcut("j", cycle: false))
    XCTAssertEqual(s.tool, .healingBrush)
    canvas.mouseDown(with: try mouse(.leftMouseDown, 96))
    let before = s.document
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
        keyCode: 53))
    canvas.keyDown(with: escape)
    await s.clonePrepareTask?.value
    XCTAssertNil(s.cloneDraft)
    XCTAssertEqual(s.document, before)
    s.chooseTool(WorkspaceCatalog.tool("clone"))
    state.brush.size = 9
    s.chooseTool(WorkspaceCatalog.tool("healing"))
    XCTAssertEqual(s.retouchSettings.brush.size, 30)
    XCTAssertTrue(s.chooseShortcut("j", cycle: true))
    XCTAssertNil(s.unavailableToolID)
    XCTAssertEqual(s.tool, .patch)
    XCTAssertTrue(s.chooseShortcut("j", cycle: true));XCTAssertEqual(s.tool, .contentAwareMove)
    XCTAssertTrue(s.chooseShortcut("j", cycle: true));XCTAssertEqual(s.tool, .redEye)
  }
}
