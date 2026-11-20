import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PathWarpWorkflowTests: XCTestCase {
  @MainActor func testContinuousWarpInputPublishesTheActiveAndLatestPreview() async throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let store = EditorStore(document: source)
    defer { store.cancelWarp(); store.renderTask?.cancel() }
    let saved = try XCTUnwrap(source.paths?.first)
    store.choosePathPanelRow(.saved(saved.id), modifiers: [])
    store.beginPathWarp()
    let warp = try XCTUnwrap(store.pathWarp)
    await warp.task?.value
    XCTAssertTrue(warp.ready)
    var published: [Double] = []
    warp.pathPreviewChanged = { [weak warp] in
      if let bend = warp?.pathEdit?.request.settings.bend { published.append(bend) }
    }
    var settings = warp.settings
    settings.style = .flag
    settings.bend = 20
    warp.change(settings)
    let first = try XCTUnwrap(warp.task)
    for bend in [40.0, 65.0] {
      settings.bend = bend
      warp.change(settings)
    }
    XCTAssertFalse(warp.ready)
    await first.value
    await warp.task?.value
    XCTAssertEqual(published, [20, 65])
    XCTAssertTrue(warp.ready)
    XCTAssertEqual(warp.pathEdit?.request.settings.bend, 65)
    XCTAssertEqual(store.document, source)
  }

  @MainActor func testCanvasSwitchToWarpDragCancelAndCommitWithRecordedHistory() async throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let store = EditorStore(document: source)
    defer { store.cancelWarp(); store.cancelTransform(); store.renderTask?.cancel() }
    let saved = try XCTUnwrap(source.paths?.first)
    store.choosePathPanelRow(.saved(saved.id), modifiers: [])
    store.choosePathPanelRow(.vectorMask(source.layers[1].id), modifiers: .command)
    let selectedSource = store.document
    let choices = store.selectedPathChoices
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
    let keys = MagneticLassoWorkflowTests()
    func start() async throws -> WarpWorkspace {
      store.beginTransform()
      let draft = try XCTUnwrap(store.transformDraft).selectionApplying(.translation(5, 7))
      store.updateTransform(draft)
      store.beginPathWarp()
      let warp = try XCTUnwrap(store.pathWarp)
      await warp.task?.value
      XCTAssertEqual(warp.pathContext?.matrix, try draft.selectionProjection)
      XCTAssertNil(store.transformDraft)
      XCTAssertEqual(store.document, selectedSource)
      XCTAssertTrue(warp.ready)
      return warp
    }
    let cancelled = try await start()
    cancelled.choose(.arc)
    await cancelled.task?.value
    canvas.keyDown(with: try keys.key(53))
    XCTAssertNil(store.pathWarp)
    XCTAssertEqual(store.document, selectedSource)
    XCTAssertTrue(store.session.undoStack.isEmpty)

    try store.session.startActionRecording(name: "Warp saved path and mask")
    let warp = try await start()
    let corner = try XCTUnwrap(warp.controls?.points.first)
    let origin = CGPoint(x: corner.x, y: corner.y)
    let destination = CGPoint(x: corner.x + 14, y: corner.y - 8)
    canvas.mouseDown(with: events.mouse(.leftMouseDown, origin, canvas: canvas, window: window))
    XCTAssertEqual(canvas.toolCursor, .closedHand)
    canvas.mouseDragged(with: events.mouse(.leftMouseDragged, destination, canvas: canvas, window: window))
    canvas.mouseUp(with: events.mouse(.leftMouseUp, destination, canvas: canvas, window: window))
    await warp.task?.value
    XCTAssertNil(warp.error)
    XCTAssertEqual(warp.settings.style, .custom)
    let edit = try XCTUnwrap(warp.pathEdit)
    XCTAssertNotEqual(edit.result, selectedSource)
    XCTAssertEqual(store.document, selectedSource)
    XCTAssertEqual(store.previewDocument, edit.result)
    canvas.keyDown(with: try keys.key(36))
    XCTAssertNil(store.pathWarp)
    XCTAssertEqual(store.document, edit.result)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.selectedPathChoices.map(\.target), choices.map(\.target))
    var library = ActionLibraryFile()
    library.actions = [try XCTUnwrap(store.session.actionRecording?.snapshot)]
    let encoded = try XCTUnwrap(try library.encoded(), "Encode recorded path Warp")
    let loaded = try XCTUnwrap(try ActionLibraryFile.decode(encoded), "Decode recorded path Warp")
    XCTAssertEqual(loaded.version, 78)
    var reopened = selectedSource
    XCTAssertNoThrow(try loaded.actions[0].apply(to: &reopened), "Replay recorded path Warp")
    XCTAssertEqual(reopened, edit.result)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, selectedSource)
  }

  @MainActor func testAuthenticatedWarpValidatesAndCommitsTheSameEditablePaths() async throws {
    let source = try CrossLayerPathWorkflowTests().makeDocument()
    let saved = try XCTUnwrap(source.paths?.first), mask = source.layers[1].id
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, window in
      window.store.session = EditorSession(document: source)
      try service.share(window)
      let targets = [["target": "saved", "id": saved.id.uuidString],
                     ["target": "vectorMask", "id": mask.uuidString]]
      let fields: [String: Any] = ["targets": targets, "settings": ["style": "flag", "bend": 32]]
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "paths.warp" })
      XCTAssertTrue(JSONSerialization.isValidJSONObject(definition.schema))
      XCTAssertTrue(JSONSerialization.isValidJSONObject(PathGroupsAPI.warpStateSchema))
      let malformed = try await helper.edit(service, window, "paths.warp",
        fields.merging(["settings": ["style": "custom"]]) { _, input in input })
      XCTAssertEqual(malformed, 400)
      XCTAssertEqual(window.store.document, source)
      let changed = try await helper.edit(service, window, "paths.warp", fields)
      XCTAssertEqual(changed, 200)
      var settings = WarpDefinition()
      settings.style = .flag
      settings.bend = 32
      let match = try PathWarpEdit.prepare(
        .init(choices: [.init(.saved(saved.id)), .init(.vectorMask(mask))], settings: settings), in: source)
      XCTAssertEqual(window.store.document, match.result)
      XCTAssertEqual(window.store.session.undoStack.count, 1)
      let path = try XCTUnwrap(match.result.paths?.first?.path)
      for format in PSDFileFormat.allCases {
        let opened = try PSDCodec.read(PSDCodec.writeRasterLayers(match.result, format: format))
        let savedPath = try XCTUnwrap(opened.paths?.first?.path)
        XCTAssertEqual(savedPath.components.map(\.closed), path.components.map(\.closed))
        XCTAssertEqual(savedPath.components.map { $0.knots.count }, path.components.map { $0.knots.count })
        let reopenedMask = try XCTUnwrap(opened.layers.first { $0.name == source.layers[1].name }?.vectorMask)
        XCTAssertEqual(reopenedMask.path.knotCount, match.result.layers[1].vectorMask?.path.knotCount)
      }
    }
  }
}
