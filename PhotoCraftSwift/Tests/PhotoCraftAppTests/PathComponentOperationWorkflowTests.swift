import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class PathComponentOperationWorkflowTests: XCTestCase {
  private func fixture() throws -> (CraftDocument, NamedPath) {
    var document = try CraftDocument(width: 200, height: 165)
    let parts = [17.0, 65, 137].map { x in
      let points = [PathPoint(x, 18), .init(x+30, 18), .init(x+30, 47), .init(x, 47)]
      return PathComponent(knots: points.map { PathKnot($0) }, closed: true)
    }
    let path = NamedPath(name: "Three shapes", path: .init(components: parts))
    document.paths = [path]
    return (document, path)
  }

  @MainActor func testNativeMarqueeStackingContextMenuHistoryAndRecordedAction() async throws {
    let (source, path) = try fixture()
    let store = EditorStore(document: source)
    store.tool = .pathSelection
    store.selectPath(.saved(path.id))
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 690, height: 570)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    defer { window.contentView = nil; window.close(); store.renderTask?.cancel() }
    let events = SelectedPixelMoveWorkflowTests()
    canvas.mouseDown(with: events.mouse(.leftMouseDown, .init(x: 4, y: 6), canvas: canvas, window: window))
    canvas.mouseDragged(with: events.mouse(.leftMouseDragged, .init(x: 102, y: 55), canvas: canvas, window: window))
    XCTAssertEqual(store.pathMarquee?.preview, .components([0, 1]))
    canvas.mouseUp(with: events.mouse(.leftMouseUp, .init(x: 102, y: 55), canvas: canvas, window: window))
    XCTAssertEqual(store.pathTransformSelection, .components([0, 1]))
    let menu = try XCTUnwrap(canvas.menu(for: events.mouse(.rightMouseDown, .init(x: 40, y: 29), canvas: canvas, window: window)))
    let arrangement = try XCTUnwrap(menu.item(withTitle: "Path Arrangement")?.submenu)
    XCTAssertEqual(arrangement.item(withTitle: "Send Shape to Back")?.isEnabled, false)
    let item = try XCTUnwrap(arrangement.item(withTitle: "Bring Shape to Front"))
    XCTAssertTrue(item.isEnabled)
    try store.session.startActionRecording(name: "Move path components")
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.pathTransformSelection, .components([1, 2]))
    let edited = store.document
    XCTAssertEqual(edited.paths?.first?.path.components, [2, 0, 1].map { path.path.components[$0] })
    XCTAssertEqual(store.session.undoStack.map(\.label), ["Bring Shape to Front"])

    let action = try XCTUnwrap(store.session.actionRecording?.snapshot)
    var file = ActionLibraryFile()
    file.actions = [action]
    let reopened = try ActionLibraryFile.decode(file.encoded())
    XCTAssertEqual(reopened.version, 81)
    var other = source
    try reopened.actions[0].apply(to: &other)
    XCTAssertEqual(other, edited)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, source)
    _ = await store.requestHistory(redo: true).value
    XCTAssertEqual(store.document, edited)
  }

  @MainActor func testAuthenticatedComponentMarqueeOverlapAndRevision() async throws {
    let (source, path) = try fixture()
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: source)
      try service.share(document)
      let selection = try await helper.edit(service, document, "paths.select", [
        "targets": [["target":"saved","id":path.id.uuidString]],
        "marquee": ["start":["x":4,"y":6], "end":["x":102,"y":55]],
        "marqueeScope": "components"
      ])
      XCTAssertEqual(selection, 200)
      XCTAssertEqual(store.tool, .pathSelection)
      XCTAssertEqual(store.pathTransformSelection, .components([0, 1]))
      let fields: [String: Any] = ["target":"saved", "id":path.id.uuidString, "components":[0, 1], "operation":"exclude"]
      let revision = service.revision(store)
      let id = try XCTUnwrap(service.shares.first?.id)
      let (response, body) = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: [
        "command":"paths.components", "revision":revision, "parameters":fields
      ])
      XCTAssertEqual(response.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual((state["pathTransformSelection"] as? [String: Any])?["components"] as? [Int], [0, 1])
      XCTAssertEqual(store.document.paths?.first?.path.components.map(\.operation), [.exclude, .exclude, .combine])
      XCTAssertEqual(store.document.paths?.first?.path.components.map(\.knots), path.path.components.map(\.knots))
      XCTAssertEqual(store.session.undoStack.count, 1)
      let stale = try await helper.edit(service, document, "paths.components", fields, revision: revision)
      XCTAssertEqual(stale, 409)
      let bad = try await helper.edit(service, document, "paths.components",
                                      fields.merging(["operation":"reverse"]) { _, value in value })
      XCTAssertEqual(bad, 400)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }
}
