import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PathIsolationWorkflowTests: XCTestCase {
  @MainActor func testBothCanvasToolsDoubleClickToIsolateAndExitWithoutChangingOutput() throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let owner = source.layers[2].id
    let target = PathTarget.shape(owner)
    let shape = try XCTUnwrap(source.layers[2].shapePath())
    let anchor = try XCTUnwrap(shape.components.first?.knots.first?.anchor)
    let saved = try XCTUnwrap(source.paths?.first)
    let store = EditorStore(document: source)
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    defer { window.contentView = nil; window.close(); store.renderTask?.cancel() }

    func click(_ point: CGPoint, count: Int) throws {
      let location = canvas.convert(canvas.viewPoint(point), to: nil)
      func event(_ type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                        timestamp: 1, windowNumber: window.windowNumber,
                                        context: nil, eventNumber: count, clickCount: count, pressure: 1))
      }
      canvas.mouseDown(with: try event(.leftMouseDown))
      canvas.mouseUp(with: try event(.leftMouseUp))
    }

    for tool in [EditorTool.pathSelection, .directSelection] {
      let fullTargetList = store.pathPanelTargets
      store.tool = tool
      store.choosePathPanelRow(.saved(saved.id), modifiers: [])
      store.choosePathPanelRow(target, modifiers: .command)
      let baseline = store.document
      let pixels = try Renderer.composite(baseline)
      let files = try PSDFileFormat.allCases.map { try PSDCodec.writeRasterLayers(baseline, format: $0) }
      let point = CGPoint(x: anchor.x, y: anchor.y)
      try click(point, count: 1)
      XCTAssertNil(store.pathIsolationLayerID)
      try click(point, count: 2)
      XCTAssertEqual(store.pathIsolationLayerID, owner)
      XCTAssertTrue(store.layerFilterIsolated)
      XCTAssertEqual(store.layersInPanel().map(\.id), [owner])
      XCTAssertEqual(store.pathPanelTargets, [target])
      XCTAssertEqual(store.selectedPathChoices.map(\.target), [target])
      XCTAssertEqual(store.document, baseline)
      XCTAssertEqual(try Renderer.composite(store.document), pixels)
      XCTAssertEqual(try PSDFileFormat.allCases.map { try PSDCodec.writeRasterLayers(store.document, format: $0) }, files)
      let empty = CGPoint(x: 8, y: 8)
      try click(empty, count: 1)
      XCTAssertEqual(store.pathIsolationLayerID, owner)
      try click(empty, count: 2)
      XCTAssertNil(store.pathIsolationLayerID)
      XCTAssertEqual(store.pathPanelTargets, fullTargetList)
      XCTAssertEqual(Set(store.layersInPanel().map(\.id)), Set(source.layers.map(\.id)))
      XCTAssertEqual(store.document, baseline)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.pathMarquee)
    }
  }

  @MainActor func testVectorMaskIsolationExitsViaSelectedFilterAndExplicitPathSelection() throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let store = EditorStore(document: source)
    defer { store.renderTask?.cancel() }
    let owner = source.layers[1].id
    let target = PathTarget.vectorMask(owner)
    let saved = try XCTUnwrap(source.paths?.first)
    store.choosePathPanelRow(target, modifiers: [])
    let baseline = store.document
    store.session.setFilteredLayerSelection(source.layers[0].id)
    try store.session.startActionRecording(name: "Path isolation")
    let revision = store.layerFilterRevisionToken
    try store.setPathIsolation(true)
    XCTAssertEqual(store.document.activeLayerID, owner)
    XCTAssertTrue(store.session.actionRecording?.snapshot.steps.isEmpty == true)
    XCTAssertNotEqual(store.layerFilterRevisionToken, revision)
    XCTAssertEqual(store.pathPanelTargets, [target])
    store.toggleLayerIsolation()
    XCTAssertNil(store.pathIsolationLayerID)
    try store.setPathIsolation(true)
    store.editLayerFilter { $0.enabled = false }
    XCTAssertNil(store.pathIsolationLayerID)
    XCTAssertFalse(store.layerPanelFilter.enabled)
    try store.setPathIsolation(true)
    store.editLayerFilter { $0.mode = .name; $0.name = "Modifier" }
    XCTAssertNil(store.pathIsolationLayerID)
    XCTAssertEqual(store.layerPanelFilter.mode, .name)
    XCTAssertEqual(store.layersInPanel().map(\.id), [owner])
    try store.setPathIsolation(true)
    store.setPathChoices([.init(target), .init(.saved(saved.id))], focus: target)
    XCTAssertEqual(store.selectedPathChoices.map(\.target), [target])
    store.selectPath(.saved(saved.id))
    XCTAssertNil(store.pathIsolationLayerID)
    XCTAssertEqual(store.pathTarget, .saved(saved.id))
    XCTAssertThrowsError(try store.setPathIsolation(true))
    XCTAssertEqual(store.document, baseline)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testLosingThePathOrChangingDocumentsClearsTheIsolation() throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let store = EditorStore(document: source)
    defer { store.renderTask?.cancel() }
    let owner = source.layers[1].id
    store.selectPath(.vectorMask(owner))
    try store.setPathIsolation(true)
    try store.executeEditorCommand(.vectorMask(owner, nil))
    XCTAssertNil(store.pathIsolationLayerID)
    XCTAssertFalse(store.layerFilterIsolated)
    XCTAssertEqual(store.session.undoStack.count, 1)

    store.selectPath(.shape(source.layers[2].id))
    try store.setPathIsolation(true)
    let other = try CraftDocument(width: 16, height: 16)
    store.session = EditorSession(document: other)
    XCTAssertNil(store.pathIsolationLayerID)
    XCTAssertFalse(store.layerFilterIsolated)
    XCTAssertTrue(store.pathPanelTargets.isEmpty)
  }

  @MainActor func testAuthenticatedIsolationStateAndStaleRevision() async throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let owner = source.layers[1].id
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, window in
      let store = window.store
      store.session = EditorSession(document: source)
      try service.share(window)
      store.selectPath(.vectorMask(owner))
      let baseline = store.document
      let revision = service.revision(store)
      let id = try XCTUnwrap(service.shares.first?.id)
      let route = "/v1/documents/\(id)/commands"
      let response = try await helper.request(service, path: route, body: [
        "command": "paths.isolate", "revision": revision, "parameters": ["enabled": true]
      ])
      XCTAssertEqual(response.0.statusCode, 200)
      let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let reported = try XCTUnwrap(payload["pathIsolation"] as? [String: Any])
      let state = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: reported))
      XCTAssertNoThrow(try BrushAPI.merge(state, schema: PathGroupsAPI.isolationStateSchema))
      XCTAssertEqual(reported["available"] as? Bool, true)
      XCTAssertEqual(reported["active"] as? Bool, true)
      XCTAssertEqual(reported["layerID"] as? String, owner.uuidString)
      let stale = try await helper.edit(service, window, "paths.isolate", ["enabled": false], revision: revision)
      XCTAssertEqual(stale, 409)
      XCTAssertEqual(store.pathIsolationLayerID, owner)
      let malformed = try await helper.edit(service, window, "paths.isolate", ["enabled": "false"])
      XCTAssertEqual(malformed, 400)
      let missing = try await helper.edit(service, window, "paths.isolate")
      XCTAssertEqual(missing, 400)
      let exited = try await helper.edit(service, window, "paths.isolate", ["enabled": false])
      XCTAssertEqual(exited, 200)
      XCTAssertNil(store.pathIsolationLayerID)
      XCTAssertEqual(store.document, baseline)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
}
