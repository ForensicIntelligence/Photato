import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class CrossLayerPathWorkflowTests: XCTestCase {
  func makeDocument() throws -> CraftDocument {
    var source = try PathTransformWorkflowTests().document()
    let second = VectorPath(components: [.init(knots: [
      .init(.init(120, 26)), .init(.init(160, 29)), .init(.init(153, 84)), .init(.init(124, 92))
    ], closed: true)])
    var layer = Layer(name: "Modifier mask", content: .raster(try Surface(width: 35, height: 35, fill: .white)))
    layer.x = 100; layer.y = 30
    layer.vectorMask = .init(path: second)
    var third = Layer(name: "Shape contour", content: .shape(.init(kind: .rectangle, width: 18, height: 24, color: .black)))
    third.x = 99; third.y = 96
    source.layers += [layer, third]
    return source
  }

  @MainActor func testPanelRangeAndCommandToggleKeepPathFocusSeparate() throws {
    let source = try makeDocument(), saved = try XCTUnwrap(source.paths?.first)
    let store = EditorStore(document: source)
    defer { store.renderTask?.cancel() }
    let first = PathTarget.saved(saved.id), second = PathTarget.shape(source.layers[2].id)
    let third = PathTarget.vectorMask(source.layers[1].id)
    XCTAssertEqual(store.pathPanelTargets, [first, second, third])
    store.choosePathPanelRow(first, modifiers: [])
    store.choosePathPanelRow(third, modifiers: .command)
    XCTAssertEqual(store.selectedPathChoices.map(\.target), [third, first])
    XCTAssertEqual(store.pathTarget, third)
    store.choosePathPanelRow(first, modifiers: .shift)
    XCTAssertEqual(store.selectedPathChoices.map(\.target), [first, second, third])
    XCTAssertEqual(store.pathTarget, first)
    store.choosePathPanelRow(second, modifiers: .command)
    XCTAssertEqual(store.selectedPathChoices.map(\.target), [first, third])
    XCTAssertEqual(store.pathTarget, first)
    store.choosePathPanelRow(first, modifiers: .command)
    XCTAssertEqual(store.pathTarget, third)
    XCTAssertEqual(store.selectedPathChoices.map(\.target), [third])
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testCanvasRefocusesAnAnchorAndMarqueeTransformsBothPathsAndRecordsAction() async throws {
    var source = try makeDocument()
    source.selection = .init(x: 3, y: 4, width: 8, height: 9)
    let saved = try XCTUnwrap(source.paths?.first), maskID = source.layers[1].id
    let first = PathTarget.saved(saved.id), second = PathTarget.vectorMask(maskID)
    let store = EditorStore(document: source)
    defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.choosePathPanelRow(first, modifiers: [])
    store.choosePathPanelRow(second, modifiers: .command)
    XCTAssertEqual(store.tool, .directSelection)
    store.beginPath(at: .init(21, 16), tolerance: 2)
    store.endPathGesture()
    XCTAssertEqual(store.pathTarget, first)
    XCTAssertTrue(store.pathPanelIsSelected(second))
    let active = store.document
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    defer { window.contentView = nil; window.close() }
    let events = SelectedPixelMoveWorkflowTests()
    let start = CGPoint(x: 173, y: 43), end = CGPoint(x: 13, y: 5)
    canvas.mouseDown(with: events.mouse(.leftMouseDown, start, canvas: canvas, window: window))
    canvas.mouseDragged(with: events.mouse(.leftMouseDragged, end, canvas: canvas, window: window))
    XCTAssertEqual(store.pathMarquee?.previewChoices?.count, 2)
    canvas.mouseUp(with: events.mouse(.leftMouseUp, end, canvas: canvas, window: window))
    let choice = PathTransformSelection.anchors([.init(component: 0, knot: 0), .init(component: 0, knot: 1)])
    let expectedChoices = [PathTransformChoice(first, selection: choice), .init(second, selection: choice)]
    XCTAssertEqual(store.selectedPathChoices, expectedChoices)
    XCTAssertEqual(store.pathChoicesForTransform.transformTitle, "Transform Points")
    XCTAssertEqual(store.document, active)
    XCTAssertTrue(store.session.undoStack.isEmpty)

    try store.session.startActionRecording(name: "Cross-layer path edit")
    store.beginTransform()
    let draft = try XCTUnwrap(store.transformDraft), session = try XCTUnwrap(store.selectionTransform)
    XCTAssertEqual(draft.pathChoices, expectedChoices)
    XCTAssertEqual(draft.pathTransformTitle, "Transform Points")
    let moved = draft.selectionApplying(.translation(13, -2))
    store.updateTransform(moved)
    await SelectedPixelTransformWorkflowTests().settle(session)
    XCTAssertNil(session.error)
    XCTAssertEqual(session.vectorPreviews.count, 2)
    XCTAssertNotNil(session.pixelPreview)
    XCTAssertEqual(store.document, active)
    store.commitTransform()
    await session.commitTask?.value
    XCTAssertNil(session.error)
    var expected = active
    try Command.transformPaths(.init(choices: expectedChoices, matrix: moved.selectionProjection)).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    XCTAssertEqual(store.document.selection, source.selection)
    XCTAssertEqual(store.session.undoStack.count, 1)
    var file = ActionLibraryFile()
    file.actions = [try XCTUnwrap(store.session.actionRecording?.snapshot)]
    let loaded = try ActionLibraryFile.decode(file.encoded())
    XCTAssertEqual(loaded.version, 77)
    var replay = active
    try loaded.actions[0].apply(to: &replay)
    XCTAssertEqual(replay, expected)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, active)
    XCTAssertTrue(store.pathPanelIsSelected(second))
  }

  @MainActor func testAuthenticatedMultiPathSelectionAndTransformAreAtomic() async throws {
    let source = try makeDocument(), saved = try XCTUnwrap(source.paths?.first)
    let maskID = source.layers[1].id
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: source)
      try service.share(document)
      let entries = [["target": "saved", "id": saved.id.uuidString],
                     ["target": "vectorMask", "id": maskID.uuidString]]
      let selected = try await helper.edit(service, document, "paths.select",
        ["targets": entries, "focus": entries[0], "marquee": ["start": ["x": 173,"y": 43], "end": ["x": 13,"y": 5]]])
      XCTAssertEqual(selected, 200)
      XCTAssertEqual(store.selectedPathChoices.count, 2)
      XCTAssertEqual(store.pathTarget, .saved(saved.id))
      XCTAssertEqual(store.document, source)
      let raw = try JSONDecoder().decode(AutomationValue.self,
        from: JSONSerialization.data(withJSONObject: store.pathState))
      XCTAssertNoThrow(try BrushAPI.merge(raw, schema: PathAPI.stateSchema))
      let parameters: [String: Any] = ["targets": entries, "matrix": ProjectiveTransform(.translation(2, 3)).values]
      let duplicate = try await helper.edit(service, document, "paths.transform",
        parameters.merging(["targets": [entries[0],entries[0]]]) { _, supplied in supplied })
      XCTAssertEqual(duplicate, 400)
      XCTAssertEqual(store.document, source)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      let transformed = try await helper.edit(service, document, "paths.transform", parameters)
      XCTAssertEqual(transformed, 200)
      var expected = source
      try Command.transformPaths(.init(choices: [.init(.saved(saved.id)),.init(.vectorMask(maskID))],
        matrix: .init(.translation(2, 3)))).apply(to: &expected)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }
}
