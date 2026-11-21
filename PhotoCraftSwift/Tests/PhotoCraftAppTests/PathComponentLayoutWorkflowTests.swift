import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PathComponentLayoutWorkflowTests: XCTestCase {
  private func fixture() throws -> (CraftDocument, NamedPath) {
    var document = try CraftDocument(width: 200, height: 190)
    let components = [(10.25, 12.5, 25.5, 21.0), (55.75, 52.5, 20.25, 16.25),
                      (127.5, 91.75, 27.5, 26.0), (170.5, 145.5, 15.0, 20.0)].map { x, y, width, height in
      let corners = [PathPoint(x, y), .init(x+width, y), .init(x+width, y+height), .init(x, y+height)]
      return PathComponent(knots: corners.map { PathKnot($0) }, closed: true)
    }
    let path = NamedPath(name: "Layout", path: .init(components: components), isWorkPath: true)
    let background = Layer(name: "White", content: .raster(try Surface(width: 200, height: 190, fill: .white)))
    document.layers = [background]
    document.activeLayerID = background.id
    document.paths = [path]
    return (document, path)
  }

  @MainActor func testCanvasShiftClickMenuUndoAndReloadEditablePath() async throws {
    let (source, saved) = try fixture()
    let store = EditorStore(document: source)
    store.tool = .pathSelection
    store.choosePathPanelRow(.saved(saved.id), modifiers: [])
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    let events = SelectedPixelMoveWorkflowTests()
    defer { window.contentView = nil; window.close(); store.renderTask?.cancel() }
    func click(_ point: CGPoint, extending: Bool = false) {
      let flags: NSEvent.ModifierFlags = extending ? .shift : []
      canvas.mouseDown(with: events.mouse(.leftMouseDown, point, canvas: canvas, window: window, flags: flags))
      canvas.mouseUp(with: events.mouse(.leftMouseUp, point, canvas: canvas, window: window, flags: flags))
    }
    func menu() throws -> NSMenu {
      try XCTUnwrap(canvas.menu(for: events.mouse(.rightMouseDown, .init(x: 21, y: 25), canvas: canvas, window: window)))
    }
    click(.init(x: 20, y: 24))
    XCTAssertEqual(try menu().items.map(\.isEnabled), [false, false])
    click(.init(x: 64, y: 61), extending: true)
    XCTAssertEqual(try menu().items.map(\.isEnabled), [true, false])
    click(.init(x: 142, y: 102), extending: true)
    XCTAssertEqual(try menu().items.map(\.isEnabled), [true, true])
    let item = try XCTUnwrap(menu().item(withTitle: "Distribute Paths")?.submenu?.item(withTitle: "Horizontal Centers"))
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.pathTransformSelection, .components([0, 1, 2]))
    let request = PathComponentLayoutRequest(target: .saved(saved.id), components: [0, 1, 2],
                                             operation: .distribute(.horizontalCenter))
    let expected = try PathComponentLayout.geometry(request, in: source).path
    XCTAssertEqual(store.document.paths?.first?.path, expected)
    XCTAssertEqual(store.session.undoStack.map(\.label), [request.label])
    XCTAssertEqual(try Renderer.composite(source), try Renderer.composite(store.document))
    for format in PSDFileFormat.allCases {
      let decoded = try PSDCodec.read(PSDCodec.writeRasterLayers(store.document, format: format))
      let path = try XCTUnwrap(decoded.paths?.first?.path)
      XCTAssertEqual(path.knotCount, expected.knotCount)
      for (actual, truth) in zip(path.components.flatMap(\.knots), expected.components.flatMap(\.knots)) {
        XCTAssertEqual(actual.anchor.x, truth.anchor.x, accuracy: 0.001)
        XCTAssertEqual(actual.anchor.y, truth.anchor.y, accuracy: 0.001)
      }
    }
    let edited = store.document
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, source)
    _ = await store.requestHistory(redo: true).value
    XCTAssertEqual(store.document, edited)
  }

  @MainActor func testRecordedActionRecomputesAlignmentOnAnotherEditableWorkPath() async throws {
    let (source, saved) = try fixture()
    let store = EditorStore(document: source)
    defer { store.renderTask?.cancel() }
    store.tool = .pathSelection
    store.selectPath(.saved(saved.id))
    store.pathTransformSelection = .components([0, 1, 2])
    try store.session.startActionRecording(name: "Align path components")
    store.arrangePathComponents(.align(.left))
    await store.geometryTask?.value
    let action = try XCTUnwrap(store.session.actionRecording?.snapshot)
    guard case .layoutPathComponents = action.steps.first?.operation else {
      return XCTFail("The Action should recompute layout during replay.")
    }
    var library = ActionLibraryFile()
    library.actions = [action]
    let encoded = try library.encoded()
    let decoded = try ActionLibraryFile.decode(encoded)
    XCTAssertEqual(decoded.version, 80)
    var other = source
    var copy = saved
    copy.id = UUID()
    copy.path.components[0].knots = copy.path.components[0].knots.map { $0.transformed(.translation(6, 0)) }
    other.paths = [copy]
    let expected = try PathComponentLayout.geometry(
      .init(target: .saved(copy.id), components: [0, 1, 2], operation: .align(.left)), in: other).path
    try decoded.actions[0].apply(to: &other)
    XCTAssertEqual(other.paths?.first?.path, expected)
    XCTAssertNotEqual(other.paths?.first?.path, store.document.paths?.first?.path)
  }

  @MainActor func testAuthenticatedLayoutRejectsBadTargetsAndReturnsComponentSelection() async throws {
    let (source, saved) = try fixture()
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, window in
      let store = window.store
      store.session = EditorSession(document: source)
      store.choosePathPanelRow(.saved(saved.id), modifiers: [])
      store.pathTransformSelection = .components([0, 1, 2])
      try service.share(window)
      let id = try XCTUnwrap(service.shares.first?.id)
      let route = "/v1/documents/\(id)/commands"
      let fields: [String: Any] = ["target": "saved", "id": saved.id.uuidString,
                                   "components": [2, 0, 1],
                                   "layout": ["operation": "distribute", "edge": "Horizontally"]]
      let invalidMode = try await helper.edit(service, window, "paths.layout", fields.merging(
        ["layout": ["operation": "align", "edge": "Horizontally"]]) { _, invalid in invalid })
      XCTAssertEqual(invalidMode, 400)
      let invalidCount = try await helper.edit(service, window, "paths.layout", fields.merging(
        ["components": [1, 2]]) { _, invalid in invalid })
      XCTAssertEqual(invalidCount, 422)
      XCTAssertEqual(store.document, source)
      let revision = service.revision(store)
      let response = try await helper.request(service, path: route, body: [
        "command": "paths.layout", "revision": revision, "parameters": fields
      ])
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let selected = try XCTUnwrap(state["pathTransformSelection"] as? [String: Any])
      XCTAssertEqual(selected["components"] as? [Int], [0, 1, 2])
      let exposed = try XCTUnwrap(state["pathComponentLayout"] as? [String: Any])
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: exposed))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: PathComponentLayoutAPI.stateSchema))
      let expected = try PathComponentLayout.geometry(
        .init(target: .saved(saved.id), components: [0, 1, 2], operation: .distribute(.horizontally)), in: source).path
      XCTAssertEqual(store.document.paths?.first?.path, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let stale = try await helper.edit(service, window, "paths.layout", fields, revision: revision)
      XCTAssertEqual(stale, 409)
    }
  }
}
