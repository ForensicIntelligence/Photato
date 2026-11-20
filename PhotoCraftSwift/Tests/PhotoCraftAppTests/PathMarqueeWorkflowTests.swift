import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class PathMarqueeWorkflowTests: XCTestCase {
  private let firstPair: PathTransformSelection = .anchors([
    .init(component: 0, knot: 0), .init(component: 0, knot: 1)
  ])

  @MainActor
  private func makeCanvas(_ store: EditorStore) -> (CraftCanvas, NSWindow) {
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    return (canvas, window)
  }

  @MainActor
  func testReverseCanvasMarqueePreviewsThenSelectsOnlyPathAnchorsForCommandT() throws {
    var before = try PathTransformWorkflowTests().document()
    before.selection = .init(x: 12, y: 13, width: 26, height: 25)
    let id = try XCTUnwrap(before.paths?.first?.id)
    let store = EditorStore(document: before)
    store.selectPath(.saved(id))
    store.tool = .directSelection
    let (canvas, window) = makeCanvas(store)
    defer { store.cancelTransform(); store.renderTask?.cancel(); window.contentView = nil; window.close() }
    let events = SelectedPixelMoveWorkflowTests()
    let start = CGPoint(x: 105, y: 35), end = CGPoint(x: 10, y: 3)
    canvas.mouseDown(with: events.mouse(.leftMouseDown, start, canvas: canvas, window: window))
    XCTAssertNotNil(store.pathMarquee)
    XCTAssertFalse(store.canBeginPathTransform)
    canvas.mouseDragged(with: events.mouse(.leftMouseDragged, end, canvas: canvas, window: window))
    XCTAssertEqual(store.pathMarquee?.preview, firstPair)
    XCTAssertEqual(store.pathTransformSelection, .all)
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    canvas.mouseUp(with: events.mouse(.leftMouseUp, end, canvas: canvas, window: window))
    XCTAssertNil(store.pathMarquee)
    XCTAssertEqual(store.pathTransformSelection, firstPair)
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginTransform()
    XCTAssertEqual(store.transformDraft?.pathSelection, firstPair)
    XCTAssertEqual(store.transformDraft?.pathTarget, .saved(id))
    XCTAssertEqual(store.document.selection, before.selection)
  }

  @MainActor
  func testShiftMarqueeKeepsEnclosedAnchorsAndEscapeOrFocusLossDiscardsPreview() throws {
    let before = try PathTransformWorkflowTests().document()
    let id = try XCTUnwrap(before.paths?.first?.id)
    let store = EditorStore(document: before)
    store.selectPath(.saved(id))
    store.tool = .directSelection
    store.pathTransformSelection = .anchors([.init(component: 0, knot: 0)])
    let (canvas, window) = makeCanvas(store)
    defer { store.renderTask?.cancel(); window.contentView = nil; window.close() }
    let events = SelectedPixelMoveWorkflowTests()
    let start = CGPoint(x: 105, y: 35), end = CGPoint(x: 10, y: 3)
    canvas.mouseDown(with: events.mouse(.leftMouseDown, start, canvas: canvas, window: window, flags: .shift))
    canvas.mouseDragged(with: events.mouse(.leftMouseDragged, end, canvas: canvas, window: window, flags: []))
    XCTAssertEqual(store.pathMarquee?.preview, firstPair)
    XCTAssertEqual(canvas.toolCursor, EditorTool.directSelection.cursor(modifiers: .shift))
    canvas.mouseUp(with: events.mouse(.leftMouseUp, end, canvas: canvas, window: window))
    XCTAssertEqual(store.pathTransformSelection, firstPair)

    for escape in [true, false] {
      let pointer = CGPoint(x: 103, y: 103), other = CGPoint(x: 152, y: 43)
      canvas.mouseDown(with: events.mouse(.leftMouseDown, pointer, canvas: canvas, window: window))
      canvas.mouseDragged(with: events.mouse(.leftMouseDragged, other, canvas: canvas, window: window))
      XCTAssertNotNil(store.pathMarquee?.preview)
      if escape {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
          timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
          charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        canvas.keyDown(with: event)
      } else {
        canvas.clearCursorInput()
      }
      XCTAssertNil(store.pathMarquee)
      canvas.mouseUp(with: events.mouse(.leftMouseUp, other, canvas: canvas, window: window))
      XCTAssertEqual(store.pathTransformSelection, firstPair)
    }
    canvas.mouseDown(with: events.mouse(.leftMouseDown, start, canvas: canvas, window: window))
    canvas.mouseUp(with: events.mouse(.leftMouseUp, start, canvas: canvas, window: window))
    XCTAssertEqual(store.pathTransformSelection, .anchors([]))
    XCTAssertFalse(store.canBeginPathTransform)
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor
  func testAuthenticatedMaskMarqueeSharesSelectionAndRejectsConflictingRequests() async throws {
    var before = try PathTransformWorkflowTests().document()
    let path = try XCTUnwrap(before.paths?.first?.path)
    let id = before.layers[0].id
    before.layers[0].vectorMask = VectorMask(path: path)
    before.selection = .init(x: 0, y: 0, width: 3, height: 5)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: before)
      try service.share(document)
      let rectangle = ["start": ["x": 105, "y": 35], "end": ["x": 10, "y": 3]]
      let parameters: [String: Any] = ["vectorMaskLayerID": id.uuidString, "tool": "directSelection",
                                      "marquee": rectangle]
      let selected = try await helper.edit(service, document, "path.configure", parameters)
      XCTAssertEqual(selected, 200)
      XCTAssertEqual(store.pathTarget, .vectorMask(id))
      XCTAssertEqual(store.pathTransformSelection, self.firstPair)
      XCTAssertEqual(store.document, before)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      let state = try JSONDecoder().decode(AutomationValue.self,
        from: JSONSerialization.data(withJSONObject: store.pathState))
      XCTAssertNoThrow(try BrushAPI.merge(state, schema: PathAPI.stateSchema))

      let second = ["start": ["x": 15, "y": 5], "end": ["x": 24, "y": 19]]
      let extended = try await helper.edit(service, document, "path.configure",
        ["vectorMaskLayerID": id.uuidString, "marquee": second, "extend": true])
      XCTAssertEqual(extended, 200)
      XCTAssertEqual(store.pathTransformSelection, self.firstPair)
      let invalid = try await helper.edit(service, document, "path.configure",
        ["layerID": id.uuidString, "vectorMaskLayerID": id.uuidString, "marquee": rectangle])
      XCTAssertEqual(invalid, 400)
      store.beginPath(at: .init(105, 35), tolerance: 2, allowsMarquee: true)
      XCTAssertNotNil(store.pathMarquee)
      let busy = try await helper.edit(service, document, "path.configure", parameters)
      XCTAssertEqual(busy, 409)
      store.cancelPathMarquee()
      XCTAssertEqual(store.pathTransformSelection, self.firstPair)
      XCTAssertEqual(store.document, before)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
}
