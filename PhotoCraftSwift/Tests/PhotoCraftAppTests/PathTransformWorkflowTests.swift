import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PathTransformWorkflowTests: XCTestCase {
  func testPathTransformRegistryAndTypedAnchorResponse() throws {
    let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == PathTransformAPI.name })
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    XCTAssertEqual(ActionLibraryFile.maximumVersion, AutomationTests.expectedActionVersion)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(definition.schema))
    XCTAssertTrue(JSONSerialization.isValidJSONObject(PathTransformAPI.capabilities))
    let id = UUID()
    let anchors = [PathTransformAnchor(component: 0, knot: 2), .init(component: 1, knot: 3)]
    func command(_ selection: [[String: Int]]) throws -> AutomationCommand {
      try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
        "command": "path.transform", "revision": "test", "parameters": [
          "target": "saved", "id": id.uuidString, "matrix": ProjectiveTransform.identity.values,
          "anchors": selection
        ]
      ]))
    }
    let entries = anchors.map { ["component": $0.component, "knot": $0.knot] }
    let request = try command(entries).pathTransformOptions()
    XCTAssertEqual(request.target, .saved(id))
    XCTAssertEqual(request.selection, .anchors(anchors))
    XCTAssertThrowsError(try command([entries[0], entries[0]]).pathTransformOptions())
    let output = PathTransformAPI.selection(request.selection)
    let json = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: output))
    XCTAssertNoThrow(try BrushAPI.merge(json, schema: PathTransformAPI.selectionSchema))
  }

  func document() throws -> CraftDocument {
    var document = try CraftDocument(width: 180, height: 130)
    let path = VectorPath(components: [
      .init(knots: [
        .init(.init(21, 16), outgoing: .init(43, 12)),
        .init(.init(90, 18), incoming: .init(68, 33)),
        .init(.init(86, 75)),
        .init(.init(17, 68))
      ], closed: true),
      .init(knots: [.init(.init(115, 44)), .init(.init(144, 49)), .init(.init(138, 73))],
            closed: true, operation: .subtract)
    ])
    let layer = Layer(name: "Photato path", content: .raster(try Surface(width: 180, height: 130, fill: .white)))
    document.layers = [layer]
    document.activeLayerID = layer.id
    document.paths = [NamedPath(name: "Panel path", path: path)]
    return document
  }

  @MainActor func testClickSelectingShapeContoursAndAnchorsDoesNotEditTheShape() throws {
    var before = try CraftDocument(width: 100, height: 100)
    var layer = Layer(name: "Live rectangle", content: .shape(.init(kind: .rectangle, width: 40,
                                                                    height: 30, color: .white)))
    layer.x = 15; layer.y = 9
    before.layers = [layer]
    before.activeLayerID = layer.id
    let path = try XCTUnwrap(layer.shapePath())
    let knot = try XCTUnwrap(path.components.first?.knots.first)
    let store = EditorStore(document: before)
    defer { store.renderTask?.cancel() }
    for tool in [EditorTool.pathSelection, .directSelection] {
      store.selectPath(.shape(layer.id))
      store.tool = tool
      store.beginPath(at: knot.anchor, tolerance: 2)
      store.endPathGesture()
      XCTAssertEqual(store.document, before)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertTrue(store.canBeginPathTransform)
    }
  }

  @MainActor func testSelectedAnchorsUseNativeCanvasModifiersPreviewReturnAndUndo() async throws {
    let before = try document()
    let saved = try XCTUnwrap(before.paths?.first)
    let store = EditorStore(document: before)
    defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.selectPath(.saved(saved.id))
    store.tool = .directSelection
    store.beginPath(at: .init(21, 16), tolerance: 2)
    store.endPathGesture()
    store.beginPath(at: .init(90, 18), tolerance: 2, extending: true)
    store.endPathGesture()
    let selection = PathTransformSelection.anchors([.init(component: 0, knot: 0), .init(component: 0, knot: 1)])
    XCTAssertEqual(store.pathTransformSelection, selection)
    XCTAssertEqual(store.document, before)
    store.beginTransform()
    let draft = try XCTUnwrap(store.transformDraft)
    let session = try XCTUnwrap(store.selectionTransform)
    XCTAssertEqual(draft.pathTarget, .saved(saved.id))
    XCTAssertEqual(draft.pathSelection, selection)
    XCTAssertEqual(draft.pathSelection.transformTitle, "Transform Points")
    XCTAssertEqual(store.tool, .directSelection)
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    defer { window.contentView = nil; window.close() }

    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    canvas.cursorLocationInView = canvas.viewPoint(draft.handles[0])
    for bits in 0..<16 {
      let modifiers = flags.enumerated().reduce(NSEvent.ModifierFlags()) {
        bits & (1 << $1.offset) != 0 ? $0.union($1.element) : $0
      }
      canvas.updateCursorModifiers(modifiers)
      let mode = draft.selectionMode(handle: 0, modifiers: modifiers)
      XCTAssertEqual(canvas.toolCursor, ToolCursor.selectionTransform(mode, handle: 0, flags: modifiers,
                                                                      proportional: draft.proportional))
    }
    let mouse = SelectedPixelMoveWorkflowTests()
    let start = draft.handles[0], destination = CGPoint(x: start.x + 9, y: start.y + 2)
    canvas.mouseDown(with: mouse.mouse(.leftMouseDown, start, canvas: canvas, window: window, flags: .command))
    canvas.mouseDragged(with: mouse.mouse(.leftMouseDragged, destination, canvas: canvas, window: window, flags: []))
    canvas.mouseUp(with: mouse.mouse(.leftMouseUp, destination, canvas: canvas, window: window))
    let moved = try XCTUnwrap(store.transformDraft)
    let matrix = try moved.selectionProjection
    XCTAssertNil(try matrix.affineValue())
    let timer = Date().addingTimeInterval(5)
    while session.previewBusy || session.loading || session.vectorPreview == nil {
      if Date() >= timer { break }
      await Task.yield()
    }
    XCTAssertNotNil(session.vectorPreview)
    XCTAssertEqual(store.document, before)
    let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: "\r", charactersIgnoringModifiers: "\r",
                                           isARepeat: false, keyCode: 36))
    try store.session.startActionRecording(name: "Path Distort")
    canvas.keyDown(with: key)
    await session.commitTask?.value
    XCTAssertNil(session.error)
    XCTAssertNil(store.transformDraft)
    var expected = before
    try Command.transformPath(.init(target: .saved(saved.id), selection: selection, matrix: matrix)).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    XCTAssertEqual(store.session.undoStack.count, 1)
    let action = try XCTUnwrap(store.session.actionRecording?.snapshot)
    var library = ActionLibraryFile()
    library.actions = [action]
    XCTAssertEqual(try ActionLibraryFile.decode(library.encoded()).version, 76)
    var replay = before
    replay.paths = [NamedPath(name: saved.name, path: saved.path, isWorkPath: saved.isWorkPath)]
    try action.apply(to: &replay)
    XCTAssertEqual(replay.paths?.first?.path, expected.paths?.first?.path)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, before)
  }

  @MainActor func testAuthenticatedPathTransformMatchesNativeMaskAndPreservesLayerContent() async throws {
    var before = try document()
    let saved = try XCTUnwrap(before.paths?.first)
    let layerID = before.layers[0].id
    var mask = VectorMask(path: saved.path)
    mask.linked = true; mask.density = Float(170) / 255
    before.layers[0].vectorMask = mask
    let store = EditorStore(document: before)
    defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.selectPath(.vectorMask(layerID))
    store.tool = .pathSelection
    store.beginPath(at: .init(21, 16), tolerance: 2)
    store.endPathGesture()
    XCTAssertEqual(store.pathTransformSelection, .components([0]))
    XCTAssertEqual(store.pathTransformSelection.transformTitle, "Transform Path")
    store.beginTransform()
    let draft = try XCTUnwrap(store.transformDraft)
    let session = try XCTUnwrap(store.selectionTransform)
    let corner = draft.handles[0]
    let edit = draft.selectionDragging(handle: 0, from: corner, to: .init(x: corner.x + 8, y: corner.y),
                                       mode: .perspective, shift: false, option: false)
    let matrix = try edit.selectionProjection
    store.updateTransform(edit)
    await SelectedPixelTransformWorkflowTests().settle(session)
    XCTAssertNotNil(session.pixelPreview)
    XCTAssertNotNil(session.vectorPreview)
    XCTAssertNil(session.error)
    store.commitTransform()
    await session.commitTask?.value
    XCTAssertNil(session.error)
    let expected = store.document
    XCTAssertNotEqual(before, expected)
    XCTAssertEqual(expected.layers[0].content, before.layers[0].content)
    XCTAssertEqual(expected.layers[0].coordinateTransform, before.layers[0].coordinateTransform)
    XCTAssertEqual(expected.layers[0].vectorMask?.path.components[1], mask.path.components[1])
    XCTAssertEqual(expected.layers[0].vectorMask?.linked, true)
    XCTAssertEqual(expected.paths, before.paths)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: before)
      try service.share(document)
      let params: [String: Any] = ["target": "vectorMask", "id": layerID.uuidString,
                                  "matrix": matrix.values, "components": [0]]
      let status = try await helper.edit(service, document, "path.transform", params)
      XCTAssertEqual(status, 200)
      XCTAssertEqual(document.store.document, expected)
      XCTAssertNil(document.store.pathTarget)
      let rejected = try await helper.edit(service, document, "path.transform",
                                           params.merging(["anchors": [["component": 0, "knot": 0]]]) { _, value in value })
      XCTAssertEqual(rejected, 400)
      XCTAssertEqual(document.store.document, expected)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      let undo = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document, before)
    }

    for format in PSDFileFormat.allCases {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(expected, format: format))
      XCTAssertEqual(reopened.layers[0].vectorMask?.path.knotCount,
                     expected.layers[0].vectorMask?.path.knotCount)
      XCTAssertEqual(reopened.layers[0].vectorMask?.linked, true)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8),
                     try Renderer.composite(expected).rgbaData(depth: .u8))
    }
  }
}
