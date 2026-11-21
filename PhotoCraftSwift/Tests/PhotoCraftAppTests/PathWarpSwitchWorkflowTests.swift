import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class PathWarpSwitchWorkflowTests: XCTestCase {
  @MainActor func testSwitchKeepsWarpControlsAndProjectedCanvasDragThenCommitsVersion79() async throws {
    let original = try CrossLayerPathWorkflowTests().makeDocument()
    let store = EditorStore(document: original)
    defer { store.cancelWarp(); store.cancelTransform(); store.renderTask?.cancel() }
    let saved = try XCTUnwrap(original.paths?.first?.id)
    store.choosePathPanelRow(.saved(saved), modifiers: [])
    store.choosePathPanelRow(.vectorMask(original.layers[1].id), modifiers: .command)
    let source = store.document
    try store.session.startActionRecording(name: "Warp and adjust placement")
    store.beginTransform()
    let preWarp = try XCTUnwrap(store.transformDraft).selectionApplying(.translation(7, 5))
    store.updateTransform(preWarp)
    store.beginPathWarp()
    let model = try XCTUnwrap(store.pathWarp)
    model.grid(3)
    while model.rendering { await model.task?.value }
    XCTAssertTrue(model.ready)
    let grid = try XCTUnwrap(model.settings.mesh)
    let initialEdit = try XCTUnwrap(model.pathEdit)

    store.returnToPathTransform()
    let session = try XCTUnwrap(store.selectionTransform)
    XCTAssertNil(store.pathWarp)
    XCTAssertEqual(store.transformDraft?.bounds, try initialEdit.bounds())
    XCTAssertEqual(store.previewDocument, initialEdit.result)
    var transform = try XCTUnwrap(store.transformDraft)
    transform.selectionQuad?[0].x += 11
    transform.selectionQuad?[0].y -= 12
    store.updateTransform(transform)
    await SelectedPixelTransformWorkflowTests().settle(session)
    XCTAssertNil(session.error)
    let after = try transform.selectionProjection
    XCTAssertNil(try after.affineValue())
    XCTAssertEqual(session.warpPreview?.request.matrixAfter, after)
    XCTAssertEqual(store.pathWarpState["mode"] as? String, "freeTransform")
    let publishedState = try JSONDecoder().decode(AutomationValue.self,
      from: JSONSerialization.data(withJSONObject: store.pathWarpState))
    XCTAssertNoThrow(try BrushAPI.merge(publishedState, schema: PathGroupsAPI.warpStateSchema))
    let projectedPreview = try XCTUnwrap(session.warpPreview)
    store.beginPathWarp()
    XCTAssertNil(store.transformDraft)
    XCTAssertTrue(store.pathWarp === model)
    XCTAssertEqual(model.settings.mesh, grid)
    XCTAssertEqual(model.pathProjection, after)
    XCTAssertEqual(store.previewDocument, projectedPreview.result)
    XCTAssertEqual(store.document, source)
    XCTAssertTrue(store.session.undoStack.isEmpty)

    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 680, height: 520)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = CraftCanvas(store: store)
    window.contentView = canvas
    canvas.frame = frame
    canvas.synchronizeViewport()
    defer { window.contentView = nil; window.close() }
    let local = try XCTUnwrap(grid.points.first)
    let moved = PathPoint(local.x + 6, local.y + 4)
    let displayStart = try after.point(local.x, local.y)
    let displayEnd = try after.point(moved.x, moved.y)
    let start = CGPoint(x: displayStart.x, y: displayStart.y)
    let end = CGPoint(x: displayEnd.x, y: displayEnd.y)
    let events = SelectedPixelMoveWorkflowTests()
    canvas.mouseDown(with: events.mouse(.leftMouseDown, start, canvas: canvas, window: window))
    XCTAssertEqual(canvas.toolCursor, .closedHand)
    canvas.mouseDragged(with: events.mouse(.leftMouseDragged, end, canvas: canvas, window: window))
    canvas.mouseUp(with: events.mouse(.leftMouseUp, end, canvas: canvas, window: window))
    while model.rendering { await model.task?.value }
    let control = try XCTUnwrap(model.settings.mesh?.points.first)
    XCTAssertEqual(control.x, moved.x, accuracy: 1e-8)
    XCTAssertEqual(control.y, moved.y, accuracy: 1e-8)

    store.returnToPathTransform()
    let finalSession = try XCTUnwrap(store.selectionTransform)
    let finalDraft = try XCTUnwrap(store.transformDraft).selectionApplying(.translation(-3, 6))
    store.updateTransform(finalDraft)
    await SelectedPixelTransformWorkflowTests().settle(finalSession)
    let final = try XCTUnwrap(finalSession.warpPreview)
    XCTAssertEqual(final.request.matrixAfter, try after.followed(by: finalDraft.selectionProjection))
    XCTAssertEqual(store.document, source)
    store.commitTransform()
    await finalSession.commitTask?.value
    XCTAssertEqual(store.document, final.result)
    XCTAssertEqual(store.session.undoStack.count, 1)
    var library = ActionLibraryFile()
    library.actions = [try XCTUnwrap(store.session.actionRecording?.snapshot)]
    let restored = try ActionLibraryFile.decode(library.encoded())
    XCTAssertEqual(restored.version, 79)
    var playback = source
    try restored.actions[0].apply(to: &playback)
    XCTAssertEqual(playback, final.result)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, source)

    store.beginPathWarp()
    let cancelled = try XCTUnwrap(store.pathWarp)
    cancelled.choose(.arc)
    while cancelled.rendering { await cancelled.task?.value }
    store.returnToPathTransform()
    XCTAssertNotNil(store.selectionTransform)
    let keys = MagneticLassoWorkflowTests()
    canvas.keyDown(with: try keys.key(53))
    XCTAssertNil(store.transformDraft)
    XCTAssertNil(store.selectionTransform)
    XCTAssertNil(store.pathWarp)
    XCTAssertEqual(store.document, source)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testAuthenticatedWarpWithBothMatricesAndInvalidFollowUp() async throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let saved = try XCTUnwrap(source.paths?.first?.id), layer = source.layers[1].id
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: source)
      try service.share(document)
      let before = ProjectiveTransform(.translation(4, 8))
      let after = try ProjectiveTransform([1, 0.07, 6, 0, 1, -1, 0.0008, 0.0007, 1])
      let targets = [["target": "saved", "id": saved.uuidString],
                     ["target": "vectorMask", "id": layer.uuidString]]
      let fields: [String: Any] = [
        "targets": targets, "matrix": before.values, "settings": ["style": "flag", "bend": 36],
        "matrixAfter": after.values
      ]
      let invalid = fields.merging(["matrixAfter": Array(repeating: 0, count: 9)]) { _, new in new }
      let rejected = try await helper.edit(service, document, "paths.warp", invalid)
      XCTAssertEqual(rejected, 400)
      XCTAssertEqual(store.document, source)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      let status = try await helper.edit(service, document, "paths.warp", fields)
      XCTAssertEqual(status, 200)
      var settings = WarpDefinition()
      settings.style = .flag
      settings.bend = 36
      let request = PathWarpRequest(choices: [.init(.saved(saved)), .init(.vectorMask(layer))],
                                    matrix: before, settings: settings, matrixAfter: after)
      let expected = try PathWarpEdit.prepare(request, in: source)
      XCTAssertEqual(store.document, expected.result)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }
}
