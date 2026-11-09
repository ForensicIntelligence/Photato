import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class SinglePixelMarqueeWorkflowTests: XCTestCase {
  @MainActor private func fixture(_ tool: EditorTool) throws -> (EditorStore, CraftCanvas) {
    let store = EditorStore(document: try CraftDocument(width: 8, height: 6))
    store.renderTask?.cancel()
    store.chooseTool(WorkspaceCatalog.tool(tool == .rowMarquee ? "rowMarquee" : "columnMarquee"))
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 300, height: 240)
    store.updateViewport(size: canvas.bounds.size, backingScale: 1)
    store.setZoom(8, center: true)
    return (store, canvas)
  }
  @MainActor private func mouse(_ canvas: CraftCanvas, _ kind: NSEvent.EventType,
    _ x: Double, _ y: Double, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    let location = canvas.convert(CGPoint(x: canvas.imageRect.minX + x * canvas.scale,
      y: canvas.imageRect.minY + y * canvas.scale), to: nil)
    return try XCTUnwrap(NSEvent.mouseEvent(with: kind, location: location,
      modifierFlags: flags, timestamp: 1, windowNumber: 0, context: nil,
      eventNumber: 1, clickCount: 1, pressure: 1))
  }
  @MainActor private func key(_ keyCode: UInt16) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 1, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: keyCode))
  }
  func testGeometryUsesOneWholeRowOrColumnAndRejectsNonfiniteCoordinates() throws {
    XCTAssertEqual(SinglePixelMarquee.row.rectangle(at: 2.9, width: 8, height: 6), .init(x: 0, y: 2, width: 8, height: 1))
    XCTAssertEqual(SinglePixelMarquee.column.rectangle(at: 3.1, width: 8, height: 6), .init(x: 3, y: 0, width: 1, height: 6))
    XCTAssertEqual(SinglePixelMarquee.row.rectangle(at: -100, width: 8, height: 6)?.y, 0)
    XCTAssertEqual(SinglePixelMarquee.column.rectangle(at: 100, width: 8, height: 6)?.x, 7)
    for coordinate in [Double.nan, .infinity, -.infinity] {
      XCTAssertNil(SinglePixelMarquee.row.rectangle(at: coordinate, width: 8, height: 6))
    }
  }
  @MainActor func testClickAndDragPreviewCommitOnlyTheReleaseRowWithOneUndo() async throws {
    let (store, canvas) = try fixture(.rowMarquee)
    defer { store.renderTask?.cancel() }
    let original = store.document
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 1.2, 1.2))
    canvas.mouseDragged(with: try mouse(canvas, .leftMouseDragged, 6.4, 3.8))
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(canvas.end?.y ?? -1, 3.8, accuracy: 0.0001)
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 2.1, 4.1))
    await store.geometryTask?.value; await store.renderTask?.value
    XCTAssertNil(store.error)
    for y in 0..<6 { for x in 0..<8 {
      XCTAssertEqual(store.document.selectionCoverage(x: x, y: y), y == 4 ? 1 : 0)
    } }
    XCTAssertEqual(store.document.layers, original.layers)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let changed = store.document
    await store.undo(); XCTAssertEqual(store.document, original)
    await store.redo(); XCTAssertEqual(store.document, changed)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 0.1, 2.1))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 0.1, 2.1))
    await store.geometryTask?.value
    XCTAssertEqual(store.document.selectionCoverage(x: 7, y: 2), 1)
    XCTAssertEqual(store.document.selectionCoverage(x: 7, y: 4), 0)
  }
  @MainActor func testBothToolsAllSixteenModifiersCaptureModeAndRestoreHover() async throws {
    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for tool: EditorTool in [.rowMarquee, .columnMarquee] {
      let (store, canvas) = try fixture(tool)
      defer { store.renderTask?.cancel() }
      let original = store.document
      let symbol = tool == .rowMarquee ? "rectangle" : "rectangle.portrait"
      for bits in 0..<16 {
        let modifiers = flags.enumerated().reduce(NSEvent.ModifierFlags()) {
          bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element)
        }
        store.session = EditorSession(document: original)
        let mode: SelectionMode = modifiers.contains([.shift, .option]) ? .intersect
          : modifiers.contains(.shift) ? .add : modifiers.contains(.option) ? .subtract : .replace
        canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 2.1, 3.1, modifiers))
        XCTAssertEqual(canvas.selectionDragMode, mode)
        canvas.updateCursorModifiers([])
        XCTAssertEqual(canvas.toolCursor, .selection(symbol, mode))
        canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 2.1, 3.1))
        await store.geometryTask?.value
        XCTAssertNil(store.error)
        var expected = original
        let rect = tool == .rowMarquee ? IntRect(x: 0, y: 3, width: 8, height: 1)
          : IntRect(x: 2, y: 0, width: 1, height: 6)
        try Command.selectShape(.rectangle(rect), mode, false, 0).apply(to: &expected)
        XCTAssertEqual(store.document, expected, "\(tool) modifiers \(bits)")
        XCTAssertEqual(canvas.toolCursor, expected.selection != nil && expected.selectionCoverage(x:2,y:3) >= 0.5 ? .symbol("arrow.up.and.down.and.arrow.left.and.right") : .selection(symbol, .replace))
      }
    }
  }
  @MainActor func testFeatherCapturedAndEscapeOrToolChangeDiscardsDraft() async throws {
    let (store, canvas) = try fixture(.columnMarquee)
    defer { store.renderTask?.cancel() }
    let original = store.document
    store.selectionFeather = 1
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 3.1, 1))
    store.selectionFeather = 0
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 3.1, 5))
    await store.geometryTask?.value
    var expected = original
    try Command.selectShape(.rectangle(.init(x: 3, y: 0, width: 1, height: 6)), .replace, false, 1).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    let history = store.session.undoStack.count
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 6.1, 1))
    canvas.keyDown(with: try key(53))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 6.1, 1))
    XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, history)
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 6.1, 1))
    store.chooseTool(WorkspaceCatalog.tool("brush")); canvas.synchronizeTool()
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 6.1, 1))
    XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, history)
    store.chooseTool(WorkspaceCatalog.tool("columnMarquee")); canvas.synchronizeTool()
    canvas.mouseDown(with: try mouse(canvas, .leftMouseDown, 6.1, 1, .shift))
    canvas.clearCursorInput()
    XCTAssertEqual(canvas.toolCursor, .selection("rectangle.portrait", .replace))
    canvas.mouseUp(with: try mouse(canvas, .leftMouseUp, 6.1, 1))
    XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, history)
  }
  @MainActor func testAPIRowColumnModesUndoAndArchiveMatchNativeSelectionCommands() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      var original = try CraftDocument(width: 8, height: 6)
      try Command.selectShape(.rectangle(.init(x: 1, y: 1, width: 4, height: 3)), .replace, false, 0).apply(to: &original)
      for axis in ["row", "column"] { for mode in SelectionMode.allCases {
        document.store.session = EditorSession(document: original)
        let rect = axis == "row" ? IntRect(x: 0, y: 2, width: 8, height: 1) : IntRect(x: 2, y: 0, width: 1, height: 6)
        var expected = EditorSession(document: original)
        try expected.execute(.selectShape(.rectangle(rect), mode, false, 0))
        let status = try await helper.edit(service, document, "selection.shape", ["shape": [axis: 2], "mode": SelectionToolAPI.modeName(mode), "antiAlias": false])
        XCTAssertEqual(status, 200); await document.store.renderTask?.value
        XCTAssertNil(document.store.error); XCTAssertEqual(document.store.document, expected.document)
        XCTAssertEqual(try NativeArchive.decode(try NativeArchive.encode(document.store.document)), expected.document)
        let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
        await document.store.renderTask?.value; XCTAssertEqual(document.store.document, original)
        let redo = try await helper.edit(service, document, "history.redo"); XCTAssertEqual(redo, 200)
        await document.store.renderTask?.value; XCTAssertEqual(document.store.document, expected.document)
      } }
      let before = document.store.document
      for shape: [String: Any] in [["row": 6], ["column": 8], ["row": -1], ["row": 1.5], ["row": 1, "column": 1]] {
        let result = try await helper.edit(service, document, "selection.shape", ["shape": shape])
        XCTAssertEqual(result, 400); XCTAssertEqual(document.store.document, before)
      }
      let stale = try await helper.edit(service, document, "selection.shape", ["shape": ["row": 0]], revision: "stale")
      XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "selection.shape", ["shape": ["column": 0]])
      document.store.geometryBusy = false
      XCTAssertEqual(busy, 409); XCTAssertEqual(document.store.document, before)
    }
  }
  func testMaximumCanvasSingleRowsAndColumnsRetainPagedCoverageAndNativeRoundTrip() throws {
    for axis in [SinglePixelMarquee.row, .column] {
      var document = try CraftDocument(width: 300_000, height: 300_000)
      let rect = try XCTUnwrap(axis.rectangle(at: 299_999, width: document.width, height: document.height))
      try Command.selectShape(.rectangle(rect), .replace, false, 0).apply(to: &document)
      XCTAssertEqual(document.selectionCoverage(x: 299_999, y: 299_999), 1)
      XCTAssertEqual(document.selectionCoverage(x: 0, y: 0), 0)
      XCTAssertEqual(try NativeArchive.decodePaged(try NativeArchive.encode(document)), document)
    }
  }
  @MainActor func testNativeToolDiscoveryOptionsAndMarqueeShortcutsDoNotAssignRowColumnKeys() throws {
    let (store, _) = try fixture(.rowMarquee)
    defer { store.renderTask?.cancel() }
    XCTAssertEqual(store.tool, .rowMarquee); XCTAssertNil(store.unavailableToolID)
    XCTAssertEqual(WorkspaceCatalog.tool("rowMarquee").shortcut, "")
    XCTAssertEqual(WorkspaceCatalog.tool("columnMarquee").shortcut, "")
    XCTAssertTrue(store.canUseComponentCanvasTool)
    store.chooseTool(WorkspaceCatalog.tool("marquee"))
    XCTAssertTrue(store.chooseShortcut("m", cycle: true)); XCTAssertEqual(store.tool, .ellipticalMarquee)
    XCTAssertTrue(store.chooseShortcut("m", cycle: true)); XCTAssertEqual(store.tool, .marquee)
    XCTAssertTrue((ToolCursorAPI.capabilities["tools"] as? [String])?.contains(EditorTool.rowMarquee.id) == true)
    XCTAssertEqual(EditorTool.allCases.count, 56)
  }
}
