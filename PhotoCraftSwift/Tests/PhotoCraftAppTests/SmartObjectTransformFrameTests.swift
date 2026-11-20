import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SmartObjectTransformFrameTests: XCTestCase {
  private func source(_ format: PSDFileFormat? = nil) throws -> CraftDocument {
    let pixels = try Surface(width: 12, height: 8, fill: Pixel(0.1, 0.4, 0.8))
    let bytes = try RasterIO.encoded(pixels)
    var document = try CraftDocument(width: 100, height: 100)
    var layer = try SmartObjectIO.placed(data: bytes, fileName: "Owned.png", in: document, fit: false)
    if format != nil {
      let link = try LinkedSmartObjectSource(reference: "file:///does-not-exist/Owned.png",
        contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
      layer.smartObject = try layer.smartObject?.linked(to: link)
    }
    layer.x = 40
    layer.y = 20
    layer.affine = .rotation(90) * .scale(2, 3)
    try Command.addLayer(layer).apply(to: &document)
    if let format {
      document = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      let reopened = try XCTUnwrap(document.layers.last)
      XCTAssertNotNil(try reopened.linkedSmartObjectPreview())
      document.activeLayerID = reopened.id
    }
    return document
  }

  private func assertPoint(_ point: CGPoint, _ x: Double, _ y: Double,
                           file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(point.x, x, accuracy: 1e-8, file: file, line: line)
    XCTAssertEqual(point.y, y, accuracy: 1e-8, file: file, line: line)
  }

  @MainActor func testReopenedLinkedPhotoshopFilesStartWithTheSavedArtworkCorners() throws {
    for format in [PSDFileFormat.psd, .psb] {
      let original = try source(format)
      let store = EditorStore(document: original)
      defer { store.renderTask?.cancel() }
      store.beginTransform()
      let draft = try XCTUnwrap(store.transformDraft)
      XCTAssertEqual(draft.delta, .identity)
      XCTAssertEqual(draft.displayedAngle, 90, accuracy: 1e-8)
      assertPoint(draft.handles[0], 40, 20)
      assertPoint(draft.handles[2], 40, 44)
      assertPoint(draft.handles[4], 16, 44)
      assertPoint(draft.handles[6], 16, 20)
      store.cancelTransform()
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  func testShearedArtworkDragsInSourceAxesAndKeepsOppositeAndCustomPivots() throws {
    let placement = Transform2D(a: 2, b: 1, c: 0.5, d: 2, tx: 10, ty: 11)
    let artwork = SmartObjectGeometry(transform: placement, width: 12, height: 8)
    let draft = try TransformDraft(layerID: UUID(), bounds: artwork.bounds(), artwork: artwork)
    let start = draft.handles[4]
    XCTAssertEqual(draft.hitHandle(at: start, tolerance: 0.5), 4)
    XCTAssertEqual(draft.hitHandle(at: CGPoint(x: 37, y: 12), tolerance: 0.5), 8)
    XCTAssertEqual(draft.hitHandle(at: CGPoint(x: 24, y: 25), tolerance: 0.5), -1)
    let stretched = draft.dragging(handle: 4, from: start, to: start + CGPoint(x: 12, y: 6), shift: true, option: false)
    XCTAssertEqual(stretched.scaleX, 150, accuracy: 1e-8)
    XCTAssertEqual(stretched.scaleY, 100, accuracy: 1e-8)
    assertPoint(stretched.handles[0], 10, 11)
    assertPoint(stretched.handles[4], 50, 45)

    let anchored = try draft.settingReferencePoint(.init(17, 18))
    let centered = anchored.dragging(handle: 4, from: start,
      to: start + CGPoint(x: 10.5, y: 10.5), shift: false, option: true)
    XCTAssertEqual(centered.scaleX, 150, accuracy: 1e-8)
    XCTAssertEqual(centered.scaleY, 150, accuracy: 1e-8)
    XCTAssertEqual(centered.transformReferencePoint.x, 17, accuracy: 1e-8)
    XCTAssertEqual(centered.transformReferencePoint.y, 18, accuracy: 1e-8)
    assertPoint(centered.handles[4], 48.5, 49.5)
  }

  @MainActor func testCanvasSideDragUsesModifiersCursorAndOneUndoOnCommit() async throws {
    _ = NSApplication.shared
    let original = try source(.psd)
    let store = EditorStore(document: original)
    let canvas = CraftCanvas(store: store)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 440, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = canvas
    canvas.frame = try XCTUnwrap(window.contentView).bounds
    store.updateViewport(size: canvas.bounds.size, backingScale: 1)
    store.setZoom(4, center: true)
    canvas.synchronizeViewport()
    defer { store.cancelTransform(); store.renderTask?.cancel(); window.contentView = nil; window.close() }
    store.beginTransform()
    let handle = PathPoint(28, 44), end = PathPoint(28, 56)
    let events = TransformReferenceTests()
    canvas.cursorLocationInView = canvas.viewPoint(.init(x: handle.x, y: handle.y))
    XCTAssertEqual(canvas.toolCursor, .symbol("arrow.up.and.down", .constrain))
    canvas.mouseDown(with: try events.mouse(.leftMouseDown, handle, .shift, canvas))
    XCTAssertEqual(canvas.transformHandle, 3)
    canvas.mouseDragged(with: try events.mouse(.leftMouseDragged, end, .shift, canvas))
    var draft = try XCTUnwrap(store.transformDraft)
    XCTAssertEqual(draft.scaleX, 150, accuracy: 1e-8)
    XCTAssertEqual(draft.scaleY, 100, accuracy: 1e-8)
    XCTAssertEqual(canvas.toolCursor, .symbol("arrow.up.and.down"))
    canvas.updateCursorModifiers(.option)
    draft = try XCTUnwrap(store.transformDraft)
    XCTAssertEqual(draft.scaleX, 200, accuracy: 1e-8)
    XCTAssertEqual(draft.scaleY, 200, accuracy: 1e-8)
    XCTAssertEqual(canvas.toolCursor, .symbol("arrow.up.and.down", .constrainCenter))
    canvas.updateCursorModifiers(.shift)
    canvas.mouseUp(with: try events.mouse(.leftMouseUp, end, .shift, canvas))
    XCTAssertEqual(store.document, original)
    let pixels = try Renderer.composite(store.previewDocument).rgbaData(depth: .u8)
    store.commitTransform()
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    let layer = try XCTUnwrap(store.activeLayer)
    let placed = try layer.smartObjectSourceTransform()
    XCTAssertEqual(placed, Transform2D(a: 0, b: 3, c: -3, d: 0, tx: 40, ty: 20))
    XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), pixels)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testAbsoluteAngleOptionsAndDocumentFlipKeepChosenArtworkCorner() throws {
    let store = EditorStore(document: try source())
    defer { store.cancelTransform(); store.renderTask?.cancel() }
    store.beginTransform()
    try store.setTransformReference(anchor: .topRight)
    let angle = WorkspaceView(store: store).transformBinding(\.angle)
    XCTAssertEqual(angle.wrappedValue, 90, accuracy: 1e-8)
    angle.wrappedValue = 0
    var draft = try XCTUnwrap(store.transformDraft)
    XCTAssertEqual(angle.wrappedValue, 0, accuracy: 1e-8)
    assertPoint(draft.handles[0], 16, 44)
    assertPoint(draft.handles[2], 40, 44)
    store.transformLayer(horizontal: true)
    draft = try XCTUnwrap(store.transformDraft)
    assertPoint(draft.handles[0], 64, 44)
    assertPoint(draft.handles[2], 40, 44)
    assertPoint(draft.handles[4], 40, 68)
    XCTAssertTrue(draft.collectionProjective)
    store.chooseSelectionTransformMode(.distort)
    draft = try XCTUnwrap(store.transformDraft)
    let corner = draft.handles[0]
    let distorted = draft.selectionDragging(handle: 0, from: corner, to: corner + CGPoint(x: 2, y: -1),
                                             mode: .distort, shift: false, option: false)
    let projection = try distorted.selectionProjection
    XCTAssertNil(try projection.affineValue())
    let originalCorner = draft.sourcePoint(0, 0)
    let mapped = try projection.point(originalCorner.x, originalCorner.y)
    assertPoint(CGPoint(x: mapped.x, y: mapped.y), 66, 43)
    let originalOpposite = draft.sourcePoint(1, 1)
    let opposite = try projection.point(originalOpposite.x, originalOpposite.y)
    assertPoint(CGPoint(x: opposite.x, y: opposite.y), 40, 68)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testHTTPFrameStateDescribesTheDeltaUsedByTheExistingTransformCommand() async throws {
    let original = try source(.psb)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      store.session = EditorSession(document: original)
      try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id)
      store.beginTransform()
      let opened = try XCTUnwrap(store.transformDraft)
      let point = opened.handles[3]
      store.updateTransform(opened.dragging(handle: 3, from: point, to: point + CGPoint(x: 0, y: 12),
                                             shift: true, option: false))
      let response = try await helper.request(service, path: "/v1/documents/\(share)")
      XCTAssertEqual(response.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let reference = try XCTUnwrap(json["transformReference"] as? [String: Any])
      let encoded = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: reference))
      XCTAssertNoThrow(try BrushAPI.merge(encoded, schema: TransformReferenceAPI.stateSchema))
      let frame = try XCTUnwrap(reference["artworkFrame"] as? [String: Any])
      let corners = try XCTUnwrap(frame["corners"] as? [[String: Double]])
      XCTAssertEqual(corners, [["x": 40, "y": 20], ["x": 40, "y": 56], ["x": 16, "y": 56], ["x": 16, "y": 20]])
      XCTAssertEqual(frame["angleDegrees"] as? Double, 90)
      let delta = try XCTUnwrap(frame["delta"] as? [String: Any])
      XCTAssertEqual(delta["d"] as? Double, 1.5)
      XCTAssertEqual(delta["ty"] as? Double, -10)
      let expected = try Renderer.composite(store.previewDocument).rgbaData(depth: .u8)
      store.cancelTransform()
      let layerID = try XCTUnwrap(store.activeLayer?.id.uuidString)
      let result = try await helper.edit(service, document, "layer.transform", delta.merging(["layerID": layerID]) { first, _ in first })
      XCTAssertEqual(result, 200)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }
}

private func + (left: CGPoint, right: CGPoint) -> CGPoint {
  CGPoint(x: left.x + right.x, y: left.y + right.y)
}
