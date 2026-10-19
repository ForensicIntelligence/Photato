import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class GradientToolWorkflowTests: XCTestCase {
  @MainActor private func canvas(_ store: EditorStore) -> CraftCanvas {
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
    return canvas
  }
  @MainActor private func mouse(
    _ canvas: CraftCanvas, _ type: NSEvent.EventType,
    _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = [], clicks: Int = 1
  ) throws -> NSEvent {
    let p = canvas.viewPoint(CGPoint(x: x, y: y))
    return try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type, location: canvas.convert(p, to: nil),
        modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: clicks, pressure: 1))
  }
  @MainActor private func key(
    _ text: String, _ code: UInt16,
    flags: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
  }
  @MainActor private func storeWithGradient() throws -> EditorStore {
    var doc = try CraftDocument(width: 100, height: 80)
    let colors: [GradientColorStop] = [
      .init(0, .rgb(.black)), .init(0.25, .rgb(Pixel(1, 0, 0))),
      .init(0.75, .rgb(Pixel(0, 0, 1))), .init(1, .rgb(.white)),
    ]
    var fill = GradientFill(gradient: .init(colors: colors), aligned: false, dither: false)
    try fill.placement.setHandles(
      start: .init(10, 40), end: .init(90, 40),
      in: .init(x: 0, y: 0, width: 100, height: 80))
    try Command.addGradientFill(Layer(name: "Gradient", content: .gradientFill(fill))).apply(
      to: &doc)
    let store = EditorStore(document: doc)
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    return store
  }
  @MainActor func testCanvasLiveCreationPreviewSelectionCapturedColorsAndUndo() async throws {
    var doc = try CraftDocument(width: 100, height: 80)
    doc.selection = .init(x: 10, y: 10, width: 70, height: 50)
    let store = EditorStore(document: doc)
    defer { store.renderTask?.cancel() }
    let canvas = canvas(store)
    canvas.keyDown(with: try key("g", 5))
    XCTAssertEqual(store.tool, .gradient)
    XCTAssertNil(store.unavailableToolID)
    store.brush.color = Pixel(0.3, 0.7, 0.9)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 12, 20))
    store.brush.color = .black
    canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, 80, 40, flags: .shift))
    await store.renderTask?.value
    XCTAssertEqual(store.document, doc)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    let draft = try XCTUnwrap(store.gradientGesture)
    XCTAssertEqual(draft.fill?.gradient.colors[0].color, .rgb(Pixel(0.3, 0.7, 0.9)))
    XCTAssertEqual(draft.fill?.placement.angle, 0)
    var expected = doc
    try XCTUnwrap(draft.command).apply(to: &expected)
    XCTAssertEqual(
      try XCTUnwrap(store.surface).rgbaData(depth: .f32),
      try Renderer.composite(expected).rgbaData(depth: .f32))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 80, 40, flags: .shift))
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document, expected)
    XCTAssertNotNil(store.activeLayer?.mask)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let result = store.document
    store.undo()
    XCTAssertEqual(store.document, doc)
    store.redo()
    XCTAssertEqual(store.document, result)
    canvas.keyDown(with: try key("G", 5, flags: .shift))
    XCTAssertEqual(store.tool, .paintBucket)
    canvas.keyDown(with: try key("G", 5, flags: .shift))
    XCTAssertEqual(store.tool, .gradient)
  }
  @MainActor func testClicksEscapeToolSwitchAndSpacePanDoNotChangePixels() async throws {
    let store = EditorStore(document: try CraftDocument(width: 100, height: 80))
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    let original = store.document
    let canvas = canvas(store)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 10, 20))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 10, 20))
    XCTAssertTrue(store.session.undoStack.isEmpty)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 10, 20))
    canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, 70, 50))
    canvas.keyDown(with: try key("\u{1b}", 53))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 70, 50))
    XCTAssertNil(store.gradientGesture)
    XCTAssertEqual(store.document, original)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 10, 20))
    canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, 80, 20))
    canvas.keyDown(with: try key("b", 11))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 80, 20))
    XCTAssertEqual(store.document, original)
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    canvas.keyDown(with: try key(" ", 49))
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 10, 20))
    canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, 80, 20))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 80, 20))
    canvas.keyUp(with: try key(" ", 49))
    XCTAssertNil(store.gradientGesture)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testClassicCanvasPreviewCommitMaskFallbackAndCancellation() async throws {
    let store = EditorStore(document: try CraftDocument(width: 100, height: 80))
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    store.gradientOptions.mode = .classic
    store.gradientOptions.dither = false
    let original = store.document
    let canvas = canvas(store)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 10, 20))
    canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, 80, 60))
    await store.renderTask?.value
    XCTAssertEqual(store.document, original)
    var expected = original
    try XCTUnwrap(store.gradientGesture?.command).apply(to: &expected)
    XCTAssertEqual(
      try XCTUnwrap(store.surface).rgbaData(depth: .f32),
      try Renderer.composite(expected).rgbaData(depth: .f32))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 80, 60))
    await store.geometryTask?.value
    XCTAssertEqual(store.document, expected)
    XCTAssertEqual(store.document.layers.count, 1)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.createMask(id, .revealAll))
    store.maskEditingLayerID = id
    store.gradientOptions.mode = .live
    XCTAssertFalse(store.liveGradientMode)
    store.beginGradient(at: .init(0, 0), zoom: 1)
    store.dragGradient(to: .init(100, 0))
    XCTAssertTrue(store.gradientGesture?.stroke?.mask == true)
    let content = store.activeLayer?.content
    store.finishGradient()
    await store.geometryTask?.value
    XCTAssertEqual(store.activeLayer?.content, content)
    XCTAssertLessThan(try XCTUnwrap(store.activeLayer?.mask?.pixel(x: 2, y: 0).r), 0.1)
    let before = store.document
    store.beginGradient(at: .init(100, 0), zoom: 1)
    store.dragGradient(to: .init(0, 0))
    store.finishGradient()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testOnCanvasStopsCrossingTearOffMidpointsAndReverseHitTesting() async throws {
    let store = try storeWithGradient()
    defer { store.renderTask?.cancel() }
    let original = store.document
    store.beginGradient(at: .init(54, 40), zoom: 4)
    guard case .line = store.gradientGesture?.grip else { return XCTFail("Expected line") }
    store.finishGradient()
    await store.geometryTask?.value
    XCTAssertEqual(store.activeGradientWidget?.fill.gradient.colors.count, 5)
    store.undo()
    XCTAssertEqual(store.document, original)
    store.beginGradient(at: .init(30, 40), zoom: 4)
    XCTAssertEqual(store.gradientGesture?.grip, .color(1))
    store.dragGradient(to: .init(74, 40))
    store.finishGradient()
    await store.geometryTask?.value
    var widget = try XCTUnwrap(store.activeGradientWidget)
    XCTAssertEqual(widget.fill.gradient.colors[2].position, 0.8, accuracy: 1e-6)
    XCTAssertEqual(widget.fill.gradient.colors[2].color, .rgb(Pixel(1, 0, 0)))
    XCTAssertEqual(store.gradientSelectedStop?.index, 2)
    store.beginGradient(at: .init(74, 40), zoom: 4)
    store.dragGradient(to: .init(74, 60))
    store.finishGradient()
    await store.geometryTask?.value
    XCTAssertEqual(store.activeGradientWidget?.fill.gradient.colors.count, 3)
    store.undo()
    store.beginGradient(at: widget.point(try XCTUnwrap(widget.midpoint(1))), zoom: 4)
    XCTAssertEqual(store.gradientGesture?.grip, .midpoint(1))
    store.dragGradient(to: widget.point(0.15))
    store.finishGradient()
    await store.geometryTask?.value
    XCTAssertEqual(
      try XCTUnwrap(store.activeGradientWidget?.fill.gradient.colors[1].midpoint), 0.2,
      accuracy: 1e-5)
    store.changeGradientOption(\.reverse, true)
    await store.geometryTask?.value
    widget = try XCTUnwrap(store.activeGradientWidget)
    XCTAssertEqual(widget.hit(widget.point(0.8), tolerance: 1), .color(2))
    XCTAssertEqual(widget.point(0).x, widget.end.x, accuracy: 1e-5)
  }
  @MainActor func testEndpointsLineTranslationStyleChangesColorDraftAndDeleteKeyboard() async throws
  {
    let store = try storeWithGradient()
    defer { store.renderTask?.cancel() }
    store.beginGradient(at: .init(90, 40), zoom: 4)
    XCTAssertEqual(store.gradientGesture?.grip, .end)
    store.dragGradient(to: .init(60, 70), shift: true)
    store.finishGradient()
    await store.geometryTask?.value
    var widget = try XCTUnwrap(store.activeGradientWidget)
    XCTAssertEqual(widget.fill.placement.angle, -45, accuracy: 1e-5)
    let oldStart = widget.start
    let oldEnd = widget.end
    store.changeGradientOption(\.style, .radial)
    await store.geometryTask?.value
    widget = try XCTUnwrap(store.activeGradientWidget)
    XCTAssertEqual(widget.start.x, oldStart.x, accuracy: 1e-4)
    XCTAssertEqual(widget.start.y, oldStart.y, accuracy: 1e-4)
    XCTAssertEqual(widget.end.x, oldEnd.x, accuracy: 1e-4)
    let down = widget.point(0.55)
    store.beginGradient(at: down, zoom: 4)
    store.dragGradient(to: .init(down.x + 10, down.y - 8))
    store.finishGradient()
    await store.geometryTask?.value
    widget = try XCTUnwrap(store.activeGradientWidget)
    XCTAssertEqual(widget.start.x, oldStart.x + 10, accuracy: 1e-4)
    XCTAssertEqual(widget.start.y, oldStart.y - 8, accuracy: 1e-4)
    let p = widget.point(0.25)
    store.beginGradient(at: p, zoom: 4, clickCount: 2)
    store.finishGradient()
    XCTAssertEqual(store.gradientStopColorDraft?.index, 1)
    let before = store.document
    store.gradientStopColorDraft?.fill.gradient.colors[1].color = .rgb(Pixel(0, 1, 0))
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, before)
    store.finishGradientStopColor(apply: false)
    XCTAssertEqual(store.document, before)
    store.editSelectedGradientStop()
    store.gradientStopColorDraft?.fill.gradient.colors[1].color = .rgb(Pixel(0, 1, 0))
    store.finishGradientStopColor(apply: true)
    await store.geometryTask?.value
    XCTAssertEqual(store.activeGradientWidget?.fill.gradient.colors[1].color, .rgb(Pixel(0, 1, 0)))
    canvas(store).keyDown(with: try key("\u{7f}", 51))
    await store.geometryTask?.value
    XCTAssertEqual(store.activeGradientWidget?.fill.gradient.colors.count, 3)
    XCTAssertEqual(store.document.layers.count, 2)
  }
  @MainActor func testLiveCreationNoMaskFillMaskEditingAndLocks() async throws {
    let store = EditorStore(document: try CraftDocument(width: 100, height: 80))
    defer { store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("gradient"))
    // Classic's Transparency switch must not silently remove opacity stops in live mode.
    store.gradientOptions.gradient = .foregroundToTransparent
    store.gradientOptions.transparency = false
    store.beginGradient(at: .init(10, 10), zoom: 1)
    store.dragGradient(to: .init(90, 60))
    store.finishGradient()
    await store.geometryTask?.value
    XCTAssertNil(store.activeLayer?.mask)
    XCTAssertEqual(store.activeGradientWidget?.fill.gradient.opacity.last?.opacity, 0)
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.createMask(id, .revealAll))
    store.maskEditingLayerID = id
    XCTAssertTrue(store.liveGradientMode)
    store.beginGradient(at: .init(10, 20), zoom: 1)
    XCTAssertNotNil(store.gradientGesture?.fill)
    XCTAssertNil(store.gradientGesture?.stroke)
    store.cancelGradientGesture()
    store.perform(.lock(id, true))
    store.beginGradient(at: .init(10, 20), zoom: 1)
    XCTAssertNil(store.gradientGesture)
    XCTAssertNotNil(store.error)
    store.gradientOptions.mode = .classic
    store.beginGradient(at: .init(10, 20), zoom: 1)
    XCTAssertNil(store.gradientGesture)
    store.perform(.lock(id, false))
    store.beginGradientFill(editing: id)
    store.beginGradient(at: .init(10, 20), zoom: 1)
    XCTAssertNil(store.gradientGesture)
    store.cancelGradientFill()
  }
}
