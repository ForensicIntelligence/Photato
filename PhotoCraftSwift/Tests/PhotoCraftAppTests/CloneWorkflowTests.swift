import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class CloneWorkflowTests: XCTestCase {
  @MainActor func makeStore(state: CloneSources) throws -> EditorStore {
    var d = try CraftDocument(width: 24, height: 8, depth: .u16)
    var s = try Surface(width: 24, height: 8, depth: .u16)
    for y in 0..<8 {
      for x in 0..<24 { s.setPixel(x: x, y: y, Pixel(Float(x) / 23, Float(y) / 7, 0.25)) }
    }
    d.layers[0].content = .raster(s)
    let store = EditorStore(document: d, cloneState: state)
    store.chooseTool(WorkspaceCatalog.tool("clone"))
    state.brush.size = 2
    state.brush.hardness = 1
    state.brush.pressureSize = false
    return store
  }
  @MainActor func finish(_ store: EditorStore) async {
    store.finishClone()
    await store.clonePrepareTask?.value
    await store.geometryTask?.value
    await store.renderTask?.value
  }
  @MainActor func stop(_ store: EditorStore) {
    store.cancelClone()
    store.renderTask?.cancel()
    store.cloneOverlayTask?.cancel()
    store.clonePrepareTask?.cancel()
    store.geometryTask?.cancel()
  }
  @MainActor func pixel(_ store: EditorStore, _ x: Int) -> Pixel {
    guard case .raster(let s) = store.activeLayer?.content else { return .clear }
    return s.pixel(x: x, y: 3)
  }
  @MainActor func testAlignedAndRestartedSourcesPreviewUndoAndRedo() async throws {
    let state = CloneSources()
    let store = try makeStore(state: state)
    defer { stop(store) }
    store.setCloneSource(at: .init(3.5, 3.5))
    let original = store.document
    store.beginClone(.init(x: 10.5, y: 3.5))
    await store.clonePrepareTask?.value
    await store.renderTask?.value
    XCTAssertTrue(store.document == original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.clipboardTargetAvailable)
    XCTAssertEqual(store.surface?.pixel(x: 10, y: 3), pixel(store, 3))
    await finish(store)
    XCTAssertNil(store.error)
    XCTAssertEqual(pixel(store, 10), pixel(store, 3))
    XCTAssertEqual(state.slot.anchor, .init(10.5, 3.5))
    store.beginClone(.init(x: 14.5, y: 3.5))
    await finish(store)
    XCTAssertEqual(pixel(store, 14), pixel(store, 7))
    state.aligned = false
    store.beginClone(.init(x: 19.5, y: 3.5))
    await finish(store)
    XCTAssertEqual(pixel(store, 19), pixel(store, 3))
    XCTAssertEqual(store.session.undoStack.count, 3)
    let edited = store.document
    store.undo()
    store.undo()
    store.undo()
    XCTAssertTrue(store.document == original)
    store.redo()
    store.redo()
    store.redo()
    XCTAssertTrue(store.document == edited)
  }
  @MainActor func testCancellationToolSwitchAndMissingSourcesDoNotEdit() async throws {
    let state = CloneSources()
    let store = try makeStore(state: state)
    defer { stop(store) }
    let original = store.document
    store.beginClone(.init(x: 12.5, y: 3.5))
    XCTAssertNotNil(store.error)
    XCTAssertNil(store.cloneDraft)
    store.error = nil
    store.setCloneSource(at: .init(3.5, 3.5))
    store.beginClone(.init(x: 12.5, y: 3.5))
    await store.clonePrepareTask?.value
    store.extendClone(.init(x: 17.5, y: 3.5))
    store.cancelClone()
    await store.renderTask?.value
    XCTAssertTrue(store.document == original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertNil(state.slot.anchor)
    store.beginClone(.init(x: 12.5, y: 3.5))
    store.chooseTool(WorkspaceCatalog.tool("brush"))
    await store.clonePrepareTask?.value
    XCTAssertNil(store.cloneDraft)
    XCTAssertTrue(store.document == original)
    store.chooseTool(WorkspaceCatalog.tool("clone"))
    store.beginClone(.init(x: 12.5, y: 3.5))
    await store.clonePrepareTask?.value
    store.finishClone()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertTrue(store.document == original)
    XCTAssertNil(state.slot.anchor)
  }
  @MainActor func testFiveSourcesCrossDocumentAndClosedSource() async throws {
    let state = CloneSources()
    var source: EditorStore? = try makeStore(state: state)
    let target = try makeStore(state: state)
    defer {
      if let source { stop(source) }
      stop(target)
    }
    for i in 0..<5 {
      state.active = i
      source?.setCloneSource(at: .init(Double(i) + 1.5, 3.5))
    }
    XCTAssertEqual(state.slots.compactMap(\.source).count, 5)
    state.active = 4
    let expected = try XCTUnwrap(source).document
    target.beginClone(.init(x: 20.5, y: 3.5))
    await finish(target)
    guard case .raster(let s) = expected.layers[0].content else { return XCTFail() }
    XCTAssertEqual(pixel(target, 20), s.pixel(x: 5, y: 3))
    XCTAssertEqual(source?.document, expected)
    CloneSourcePanel(state: state, target: target).offset(true).wrappedValue = -10
    XCTAssertTrue(state.slot.target === target)
    target.beginClone(.init(x: 16.5, y: 3.5))
    await finish(target)
    XCTAssertEqual(pixel(target, 16), s.pixel(x: 6, y: 3))

    if let source { stop(source) }
    source = nil
    XCTAssertNil(state.slot.store)
    let before = target.document
    target.beginClone(.init(x: 16.5, y: 3.5))
    XCTAssertNotNil(target.error)
    XCTAssertTrue(target.document == before)
  }
  @MainActor func testAllLayersOntoEmptyLayerSelectionAndLocks() async throws {
    let state = CloneSources()
    let store = try makeStore(state: state)
    defer { stop(store) }
    store.setCloneSource(at: .init(3.5, 3.5))
    let source = pixel(store, 3)
    let empty = Layer(
      name: "Retouch", content: .raster(try Surface(width: 24, height: 8, depth: .u16)))
    store.perform(.addLayer(empty))
    store.select(empty.id)
    state.sampling = .currentAndBelow
    store.perform(.selection(.init(x: 12, y: 3, width: 1, height: 1)))
    store.beginClone(.init(x: 12.5, y: 3.5))
    await finish(store)
    XCTAssertEqual(pixel(store, 12), source)
    XCTAssertEqual(pixel(store, 11), .clear)
    store.perform(.lock(empty.id, true))
    XCTAssertFalse(store.canClone)
    let before = store.document
    store.beginClone(.init(x: 15.5, y: 3.5))
    XCTAssertTrue(store.document == before)
  }
  @MainActor func testCanvasOptionClickDragEscapeAndShortcut() async throws {
    let state = CloneSources()
    let store = try makeStore(state: state)
    defer { stop(store) }
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 340, height: 180)
    func event(_ type: NSEvent.EventType, _ x: Double, _ flags: NSEvent.ModifierFlags = []) throws
      -> NSEvent
    {
      let p = canvas.viewPoint(CGPoint(x: x, y: 3.5))
      return try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: canvas.convert(p, to: nil), modifierFlags: flags, timestamp: 0,
          windowNumber: 0,
          context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    canvas.mouseDown(with: try event(.leftMouseDown, 3.5, .option))
    canvas.mouseUp(with: try event(.leftMouseUp, 3.5, .option))
    XCTAssertEqual(state.slot.source, .init(3.5, 3.5))
    XCTAssertTrue(store.session.undoStack.isEmpty)
    canvas.mouseDown(with: try event(.leftMouseDown, 12.5))
    canvas.mouseDragged(with: try event(.leftMouseDragged, 13.5))
    canvas.mouseUp(with: try event(.leftMouseUp, 13.5))
    await store.clonePrepareTask?.value
    await store.geometryTask?.value
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertNil(store.error)
    let before = store.document
    canvas.mouseDown(with: try event(.leftMouseDown, 17.5))
    let esc = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
        keyCode: 53))
    canvas.keyDown(with: esc)
    await store.clonePrepareTask?.value
    XCTAssertNil(store.cloneDraft)
    XCTAssertTrue(store.document == before)
    XCTAssertTrue(store.chooseShortcut("s", cycle: false))
    XCTAssertEqual(store.tool, .cloneStamp)
    XCTAssertTrue(store.chooseShortcut("s", cycle: true))
    XCTAssertEqual(store.unavailableToolID, "patternStamp")
  }
  @MainActor func testOverlayTransformControlsAndWindowMenu() async throws {
    let state = CloneSources()
    let store = try makeStore(state: state)
    defer { stop(store) }
    store.setCloneSource(at: .init(2.5, 3.5))
    await store.cloneOverlayTask?.value
    XCTAssertNotNil(store.cloneOverlay)
    let panel = CloneSourcePanel(state: state)
    panel.number(\.width, range: 1...1000).wrappedValue = 200
    XCTAssertEqual(state.slot.width, 200)
    XCTAssertEqual(state.slot.height, 200)
    panel.number(\.width, range: 1...1000).wrappedValue = .infinity
    XCTAssertEqual(state.slot.width, 200)
    panel.flag(\.flipHorizontal).wrappedValue = true
    XCTAssertTrue(state.slot.flipHorizontal)
    panel.offset(true).wrappedValue = 4
    XCTAssertEqual(state.slot.source?.x, 6.5)
    _ = NSApplication.shared
    let old = NSApp.mainMenu
    let windows = NSApp.windowsMenu
    let help = NSApp.helpMenu
    defer {
      NSApp.mainMenu = old
      NSApp.windowsMenu = windows
      NSApp.helpMenu = help
    }
    AppDelegate().buildMenus()
    XCTAssertEqual(
      NSApp.mainMenu?.item(withTitle: "Window")?.submenu?.item(withTitle: "Clone Source")?.action,
      #selector(AppDelegate.cloneSourcePanel))
  }
}
