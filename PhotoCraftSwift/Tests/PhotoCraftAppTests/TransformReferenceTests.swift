import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class TransformReferenceTests: XCTestCase {
  func source(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 40, height: 30, depth: depth)
    document.layers[0].content = .raster(try Surface(width: 20, height: 10, depth: depth, fill: Pixel(1, 0.2, 0.1)))
    document.layers[0].x = 10; document.layers[0].y = 10
    return document
  }
  func assertPoint(_ actual: PathPoint, _ x: Double, _ y: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.x, x, accuracy: 1e-8, file: file, line: line)
    XCTAssertEqual(actual.y, y, accuracy: 1e-8, file: file, line: line)
  }
  func testAffineAndProjectiveCustomOriginsRetainTheirGeometryAndAnchorMath() throws {
    for selection in [false, true] {
      var draft = TransformDraft(layerID: UUID(), bounds: .init(x: 10, y: 20, width: 20, height: 10))
      draft.selection = selection
      let original = selection ? try draft.selectionProjection.values : ProjectiveTransform(draft.delta).values
      draft = try draft.settingReferencePoint(.init(0, 0))
      XCTAssertEqual(selection ? try draft.selectionProjection.values : ProjectiveTransform(draft.delta).values, original)
      assertPoint(draft.transformReferencePoint, 0, 0)
      let rotated = draft.transformNumeric(\.angle, 90)
      assertPoint(rotated.transformReferencePoint, 0, 0)
      let p = selection ? try rotated.selectionProjection.point(10, 20) : { let q = rotated.delta.point(10, 20); return PathPoint(q.x, q.y) }()
      assertPoint(p, -20, 10)
      let scaled = draft.transformNumeric(\.scaleX, 200)
      assertPoint(scaled.transformReferencePoint, 0, 0)
      let q = selection ? try scaled.selectionProjection.point(10, 20) : { let q = scaled.delta.point(10, 20); return PathPoint(q.x, q.y) }()
      assertPoint(q, 20, 40)
      let moved = draft.transformNumeric(\.centerX, 12).transformNumeric(\.centerY, -7)
      assertPoint(moved.transformReferencePoint, 12, -7)
      XCTAssertThrowsError(try draft.settingReferencePoint(.init(.infinity, 0)))
      XCTAssertThrowsError(try draft.settingReferencePoint(.init(1_000_001, 0)))
    }
    var projective = TransformDraft(layerID: UUID(), bounds: .init(x: 0, y: 0, width: 20, height: 20)); projective.selection = true
    projective.selectionQuad = [.init(2, 1), .init(19, 3), .init(16, 20), .init(0, 18)]
    let before = try projective.selectionProjection.values
    projective = try projective.settingReferencePoint(.init(-15, 12))
    XCTAssertEqual(try projective.selectionProjection.values, before)
    assertPoint(projective.transformReferencePoint, -15, 12)
    assertPoint(projective.selectionNumeric(\.angle, 30).transformReferencePoint, -15, 12)
  }
  @MainActor func testEveryExistingTargetUsesSharedMetadataWithoutPreviewOrDocumentChanges() async throws {
    for kind in 0..<6 {
      let original: CraftDocument
      let store: EditorStore
      if kind == 3 {
        original = try PixelMaskTransformWorkflowTests().fixture(); store = EditorStore(document: original, actions: ActionLibrary()); store.selectMask(original.layers[0].id); store.beginTransform()
      } else if kind == 4 {
        let value = try ChannelTransformWorkflowTests().fixture(); original = value.0; store = EditorStore(document: original, actions: ActionLibrary()); try ChannelTransformWorkflowTests().choose(store, value.1); store.beginTransform()
      } else {
        var model = try source()
        if kind < 2 { model.selection = .init(x: 11, y: 11, width: 8, height: 5) }
        original = model; store = EditorStore(document: model, actions: ActionLibrary())
        if kind == 0 { store.beginSelectionTransform() }
        else if kind == 5 { store.transformDraft = TransformDraft(layerID: model.layers[0].id, bounds: .init(x: 10, y: 10, width: 20, height: 10)) }
        else { store.beginTransform() }
      }
      defer { store.cancelTransform(); store.renderTask?.cancel() }
      await store.selectionTransform?.task?.value; await store.renderTask?.value
      let old = try XCTUnwrap(store.transformDraft), preview = store.selectionTransform?.pixelPreview?.image, image = store.image
      let bytes = try NativeArchive.encodeChunked(original, minimumVersion: 86)
      let revision = store.transformReferenceRevision
      XCTAssertFalse(store.showTransformReferencePoint)
      try store.setTransformReference(point: .init(4, 5), visible: true, expected: revision)
      let changed = try XCTUnwrap(store.transformDraft)
      XCTAssertTrue(changed.sameReferenceGeometry(as: old)); assertPoint(changed.transformReferencePoint, 4, 5)
      XCTAssertNotEqual(store.transformReferenceRevision, revision)
      XCTAssertTrue(store.image === image); XCTAssertTrue(store.selectionTransform?.pixelPreview?.image === preview)
      XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertEqual(try NativeArchive.encodeChunked(store.document, minimumVersion: 86), bytes)
      let current = store.transformReferenceRevision
      try store.setTransformReference(point: changed.transformReferencePoint, expected: current)
      XCTAssertEqual(store.transformReferenceRevision, current)
      try store.setTransformReference(anchor: .topLeft)
      XCTAssertNil(store.transformDraft?.customReferencePoint)
    }
  }
  @MainActor func testOutsidePivotNativeCommitMatchesExistingMatrixEngineWithUndoAtAllDepths() async throws {
    for depth in PixelDepth.allCases {
      let original = try source(depth), store = EditorStore(document: original, actions: ActionLibrary())
      defer { store.cancelTransform(); store.renderTask?.cancel() }
      store.beginTransform(); await store.selectionTransform?.task?.value
      try store.setTransformReference(point: .init(5, 5), visible: true)
      let draft = try XCTUnwrap(store.transformDraft)
      store.updateTransform(draft.transformNumeric(\.angle, 90))
      let projection = try XCTUnwrap(store.transformDraft).selectionProjection
      let mapped = try projection.point(10, 10); assertPoint(mapped, 0, 10)
      let session = store.selectionTransform
      store.commitTransform(); await session?.commitTask?.value; await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertNil(session?.error)
      var expected = original
      try Command.transformLayers(.init(layerIDs: [original.layers[0].id], projection: projection)).apply(to: &expected)
      XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
      let undone = await store.requestHistory(redo: false).value; XCTAssertTrue(undone); XCTAssertEqual(store.document, original)
    }
  }
  @MainActor func canvas() async throws -> (EditorStore, CraftCanvas, NSWindow) {
    _ = NSApplication.shared; _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    let store = EditorStore(document: try source(), actions: ActionLibrary()); store.beginTransform(); await store.selectionTransform?.task?.value
    let canvas = CraftCanvas(store: store); canvas.frame = .init(x: 0, y: 0, width: 400, height: 300)
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false); window.isReleasedWhenClosed = false; window.contentView = canvas
    store.updateViewport(size: canvas.bounds.size, backingScale: 1); store.setZoom(5, center: true); await store.renderTask?.value
    try store.setTransformReference(visible: true)
    return (store, canvas, window)
  }
  @MainActor func close(_ store: EditorStore, _ canvas: CraftCanvas, _ window: NSWindow) {
    canvas.cancelTransformReference(); store.cancelTransform(); store.renderTask?.cancel(); window.contentView = nil; window.close()
  }
  @MainActor func mouse(_ type: NSEvent.EventType, _ point: PathPoint, _ flags: NSEvent.ModifierFlags, _ canvas: CraftCanvas) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(.init(x: point.x, y: point.y)), to: nil), modifierFlags: flags, timestamp: 1, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
  }
  @MainActor func testNativePivotDragAllSixteenModifiersKeepsCapturedCursorAndNoPixelHistory() async throws {
    let (store, canvas, window) = try await canvas(); defer { close(store, canvas, window) }
    let source = store.document, initial = try XCTUnwrap(store.transformDraft)
    let modifiers: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      store.transformDraft = initial
      let pivot = initial.transformReferencePoint
      let flags = modifiers.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
      canvas.cursorLocationInView = canvas.viewPoint(.init(x: pivot.x, y: pivot.y)); canvas.updateCursorModifiers(flags)
      XCTAssertEqual(canvas.toolCursor, .transformReference(available: true))
      canvas.mouseDown(with: try mouse(.leftMouseDown, pivot, flags, canvas))
      XCTAssertNotNil(canvas.transformReferenceGesture); XCTAssertNotNil(store.transformReferenceGestureID)
      canvas.mouseDragged(with: try mouse(.leftMouseDragged, .init(4, 3), [], canvas))
      canvas.updateCursorModifiers([]); XCTAssertEqual(canvas.toolCursor, .transformReference(available: true))
      canvas.mouseUp(with: try mouse(.leftMouseUp, .init(4, 3), [], canvas))
      assertPoint(try XCTUnwrap(store.transformDraft).transformReferencePoint, 4, 3)
      XCTAssertNil(store.transformReferenceGestureID); XCTAssertEqual(store.document, source); XCTAssertTrue(store.session.undoStack.isEmpty)
    }
    canvas.spaceHeld = true; XCTAssertEqual(canvas.toolCursor, .openHand)
  }
  @MainActor func testEscapeFocusToolOwnerAndSourceChangesNeverRestoreOverOtherWork() async throws {
    let (store, canvas, window) = try await canvas(); defer { close(store, canvas, window) }
    let initial = try XCTUnwrap(store.transformDraft), source = store.document
    for reason in 0..<5 {
      store.transformDraft = initial
      canvas.mouseDown(with: try mouse(.leftMouseDown, initial.transformReferencePoint, [], canvas))
      canvas.mouseDragged(with: try mouse(.leftMouseDragged, .init(4, 3), [], canvas))
      if reason == 0 {
        canvas.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
        XCTAssertEqual(store.transformDraft, initial)
      } else if reason == 1 { canvas.clearCursorInput(); XCTAssertEqual(store.transformDraft, initial) }
      else if reason == 2 {
        var other = initial; other.centerX += 2; store.transformDraft = other; canvas.cancelTransformReference(); XCTAssertEqual(store.transformDraft, other)
      } else if reason == 3 {
        store.session = EditorSession(document: source); let current = store.transformDraft; canvas.cancelTransformReference(); XCTAssertEqual(store.transformDraft, current)
      } else { store.tool = .brush; canvas.synchronizeTool(); XCTAssertNil(canvas.transformReferenceGesture) }
      XCTAssertNil(store.transformReferenceGestureID); XCTAssertEqual(store.document, source)
      store.tool = .move; canvas.synchronizeTool()
    }
  }
  @MainActor func testAPIReferenceMatchesNativeAndRejectsInvalidBusyStaleAndRevokedWorkspace() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); document.store.beginTransform(); await document.store.selectionTransform?.task?.value
      let store = document.store, original = store.document, revision = service.revision(document.store)
      let params: [String: Any] = ["workspaceRevision": store.transformReferenceRevision.uuidString, "point": ["x": -2, "y": 3], "visible": true]
      let status = try await helper.edit(service, document, "transform.reference", params); XCTAssertEqual(status, 200)
      self.assertPoint(try XCTUnwrap(store.transformDraft).transformReferencePoint, -2, 3)
      XCTAssertEqual(service.revision(store), revision); XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
      let stale = try await helper.edit(service, document, "transform.reference", params); XCTAssertEqual(stale, 409)
      for patch in [["point": ["x": 1_000_001, "y": 0]], ["anchor": "missing"], ["visible": "yes"], ["point": ["x": 0, "y": 0], "anchor": "center"]] as [[String: Any]] {
        var request: [String: Any] = ["workspaceRevision": store.transformReferenceRevision.uuidString]; request.merge(patch) { _, new in new }
        let bad = try await helper.edit(service, document, "transform.reference", request); XCTAssertEqual(bad, 400)
      }
      store.transformReferenceGestureID = UUID()
      let busy = try await helper.edit(service, document, "transform.reference", ["workspaceRevision": store.transformReferenceRevision.uuidString, "visible": false]); XCTAssertEqual(busy, 409); store.transformReferenceGestureID = nil
      let unrelated = try await helper.edit(service, document, "layer.opacity", ["layerID": original.layers[0].id.uuidString, "opacity": 0.5]); XCTAssertEqual(unrelated, 409)
      let state = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: store.transformReferenceState)); XCTAssertNoThrow(try BrushAPI.merge(state, schema: TransformReferenceAPI.stateSchema))
      let route = "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))/commands"; service.revoke(try XCTUnwrap(service.shares.first?.id))
      let missing = try await helper.request(service, path: route, body: ["command": "transform.reference", "revision": revision, "parameters": ["workspaceRevision": store.transformReferenceRevision.uuidString, "visible": false]]); XCTAssertEqual(missing.0.statusCode, 404)
      XCTAssertEqual(store.document, original); XCTAssertEqual(AutomationCommand.definitions.count, 251)
    }
  }
  @MainActor func testContentAwareReadyPreviewSurvivesReferenceOnlyEditsAndOptionsFit() async throws {
    let store = EditorStore(document: try source(), actions: ActionLibrary()); defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.beginContentAwareScale(); XCTAssertNotNil(store.transformDraft)
    try store.setTransformReference(point: .init(1, 2), visible: true)
    await store.contentAwareScaleTask?.value
    XCTAssertEqual(store.contentAwareScaleReadyDraft, store.transformDraft); XCTAssertNotNil(store.contentAwareScalePrepared)
    let before = store.contentAwareScalePreview, ready = store.contentAwareScalePrepared
    try store.setTransformReference(anchor: .topLeft)
    XCTAssertEqual(store.contentAwareScaleReadyDraft, store.transformDraft); XCTAssertEqual(store.contentAwareScalePreview, before); XCTAssertNotNil(ready)
    let host = NSHostingView(rootView: TransformReferenceOptions(store: store).padding(12)); host.frame = .init(x: 0, y: 0, width: 130, height: 65); host.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(host.fittingSize.width, 160); XCTAssertLessThanOrEqual(host.fittingSize.height, 90)
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"], let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: rep); try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("transform-reference-options.png"))
    }
  }
}
