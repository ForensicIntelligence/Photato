import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SkyViewportTests: XCTestCase {
  func document() throws -> CraftDocument {
    var document = try CraftDocument(width: 3200, height: 3000)
    var source = try Surface(width: document.width, height: document.height, fill: Pixel(0.3, 0.6, 0.9))
    for y in 1000..<1048 { for x in 1000..<1048 {
      source.setPixel(x: x, y: y, Pixel(x.isMultiple(of: 2) ? 1 : 0, y.isMultiple(of: 2) ? 1 : 0, 0.2, x.isMultiple(of: 7) ? 0 : 1))
    } }
    document.layers[0].content = .raster(source)
    return document
  }
  @MainActor func prepared() async throws -> SkyWorkspace {
    let model = SkyWorkspace(document: try document(), library: SkyLibrary())
    await model.prepare()
    XCTAssertNil(model.error); XCTAssertTrue(model.ready)
    model.updateViewport(size: CGSize(width: 200, height: 160), backingScale: 1)
    model.setZoom(1, center: true)
    model.pan = CGSize(width: 1600 - 1024, height: 1500 - 1024)
    await model.detailTask?.value
    return model
  }
  func bytes(_ image: CGImage) throws -> Data { try XCTUnwrap(image.dataProvider?.data) as Data }

  func testVisibleTilesCoverRetinaViewportBeyondSingleBufferAndStayOnDocumentGrid() throws {
    let viewport = CanvasViewport(documentSize: CGSize(width: 300000, height: 300000),
      size: CGSize(width: 3000, height: 1700), backingScale: 2, zoom: 1, pan: .zero)
    let requests = try SkyViewportPlan.requests(for: viewport)
    XCTAssertGreaterThan(requests.reduce(0) { $0 + $1.width * $1.height }, RasterPreviewRequest.maximumPixels)
    XCTAssertLessThanOrEqual(requests.count, SkyViewportPlan.maximumTiles)
    for request in requests {
      XCTAssertEqual(request.width, request.region.width); XCTAssertEqual(request.height, request.region.height)
      XCTAssertLessThanOrEqual(request.width * request.height, 1024 * 1024)
      XCTAssertEqual(request.region.x % 1024, 0); XCTAssertEqual(request.region.y % 1024, 0)
    }
    for point in [CGPoint.zero, CGPoint(x: 2999, y: 0), CGPoint(x: 0, y: 1699), CGPoint(x: 2999, y: 1699)] {
      let p = viewport.documentPoint(at: point)
      XCTAssertTrue(requests.contains { r in p.x >= Double(r.region.x) && p.y >= Double(r.region.y) && p.x < Double(r.region.x + r.region.width) && p.y < Double(r.region.y + r.region.height) })
    }
    for zoom in [0.0001, 0.007, 0.25, 0.33, 0.5, 1, 2, 32] {
      var view = viewport; view.zoom = zoom; view.pan = CGSize(width: 100, height: -80)
      for request in try SkyViewportPlan.requests(for: view) {
        XCTAssertLessThanOrEqual(request.width, 1024); XCTAssertLessThanOrEqual(request.height, 1024)
        XCTAssertEqual(request.region, request.region.clipped(toWidth: 300000, height: 300000))
      }
    }
    var outside = viewport; outside.pan = CGSize(width: 1_000_000, height: 1_000_000)
    XCTAssertTrue(try SkyViewportPlan.requests(for: outside).isEmpty)
    var huge = viewport; huge.size = CGSize(width: 200000, height: 200000)
    XCTAssertThrowsError(try SkyViewportPlan.requests(for: huge))
  }

  @MainActor func testActualPixelFitAnchoredZoomResizeAndBackingScalePreserveGeometry() throws {
    let model = SkyWorkspace(document: try CraftDocument(width: 300000, height: 300000), library: SkyLibrary())
    defer { model.close() }
    model.updateViewport(size: CGSize(width: 1200, height: 800), backingScale: 2)
    XCTAssertLessThan(model.effectiveZoom, 0.01)
    XCTAssertEqual(model.effectiveZoom, model.viewport.fitZoom)
    let anchor = CGPoint(x: 137, y: 411), expected = model.viewport.documentPoint(at: CGPoint(x: 137, y: 411))
    model.setZoom(1, anchoredAt: anchor)
    XCTAssertEqual(model.zoomLabel, "100%"); XCTAssertEqual(model.viewport.scale, 0.5)
    XCTAssertEqual(model.viewport.documentPoint(at: anchor).x, expected.x, accuracy: 1e-8)
    XCTAssertEqual(model.viewport.documentPoint(at: anchor).y, expected.y, accuracy: 1e-8)
    model.updateViewport(size: CGSize(width: 900, height: 600), backingScale: 2)
    XCTAssertEqual(model.zoom, 1, "Resize must not silently refit")
    let center = CGPoint(x: 450, y: 300), beforeBacking = model.viewport.documentPoint(at: CGPoint(x: 450, y: 300))
    model.updateViewport(size: CGSize(width: 900, height: 600), backingScale: 1)
    XCTAssertEqual(model.viewport.documentPoint(at: center).x, beforeBacking.x, accuracy: 1e-8)
    XCTAssertEqual(model.viewport.documentPoint(at: center).y, beforeBacking.y, accuracy: 1e-8)
    model.fitViewport(); XCTAssertEqual(model.pan, .zero); XCTAssertEqual(model.zoom, model.viewport.fitZoom)
    XCTAssertTrue(model.undoStates.isEmpty)
  }

  @MainActor func testOriginalReplacementMaskTilesAndPanReuseRetainExactSourceBytes() async throws {
    let model = try await prepared(), original = model.original
    defer { model.close() }
    let source = try XCTUnwrap(model.input?.composite)
    XCTAssertEqual(model.detailTiles.count, 4)
    for tile in model.detailTiles {
      XCTAssertEqual(try bytes(tile.image), try bytes(ColorManagement.displayImage(source.cropped(to: tile.request.region), in: original)))
      XCTAssertNil(tile.mask)
    }
    let retained = model.detailTiles[0]
    model.pan.width += 1; await model.detailTask?.value
    XCTAssertTrue(try XCTUnwrap(model.detailTiles.first { $0.request == retained.request }).image === retained.image)
    let replacement = try Surface(width: original.width, height: original.height, fill: Pixel(0.9, 0.2, 0.1, 0.7))
    model.outputSurface = replacement
    var mask = try Surface(width: original.width, height: original.height, depth: .u8, fill: Pixel(0.5, 0.5, 0.5))
    mask.setPixel(x: 1023, y: 1024, .black)
    model.mask = try SelectionMask(coverage: mask); model.showMask = true
    await model.detailTask?.value
    for tile in model.detailTiles {
      XCTAssertEqual(try bytes(tile.image), try bytes(ColorManagement.displayImage(replacement.cropped(to: tile.request.region), in: original)))
      let expected = try XCTUnwrap(SelectionToolPreparation.overlay(model.mask, color: Pixel(1, 0, 0, 0.55), request: tile.request))
      XCTAssertEqual(try bytes(XCTUnwrap(tile.mask)), try bytes(expected))
    }
    model.showOriginal = true; await model.detailTask?.value
    for tile in model.detailTiles {
      XCTAssertEqual(try bytes(tile.image), try bytes(ColorManagement.displayImage(source.cropped(to: tile.request.region), in: original)))
      XCTAssertNotNil(tile.mask)
    }
    XCTAssertEqual(model.original, original); XCTAssertTrue(model.undoStates.isEmpty); XCTAssertNil(model.edit)
  }

  @MainActor func testCancelledZoomRefreshAndClosedDraftCannotPublishQueuedTiles() async throws {
    let model = try await prepared(), original = model.original
    model.pan.width += 1200
    let old = model.detailTask
    model.fitViewport()
    await old?.value
    XCTAssertTrue(model.detailTiles.isEmpty); XCTAssertFalse(model.detailBusy)
    model.setZoom(1); let prior = model.detailTask
    var next = model.state; next.settings.brightness = 10; model.change(next)
    let refreshed = model.detailTask
    model.close(); await prior?.value; await refreshed?.value
    XCTAssertNil(model.detailPlan); XCTAssertTrue(model.detailTiles.isEmpty); XCTAssertFalse(model.detailBusy)
    XCTAssertNil(model.detailError); XCTAssertNil(model.outputSurface); XCTAssertEqual(model.original, original)
    let zoom = model.zoom; model.setZoom(2); XCTAssertEqual(model.zoom, zoom)
  }

  @MainActor func testZoomToolAllModifiersMatchCursorAndKeepAnchorAndDocument() throws {
    let model = SkyWorkspace(document: try CraftDocument(width: 8000, height: 6000), library: SkyLibrary())
    defer { model.close() }
    model.input = try SkyReplacementInput.prepare(model.original)
    let canvas = SkyCanvasView(frame: CGRect(x: 0, y: 0, width: 640, height: 480)); canvas.model = model
    model.tool = .zoom
    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      model.setZoom(1, center: true)
      let modifiers = flags.enumerated().reduce(into: NSEvent.ModifierFlags()) { if bits & (1 << $1.offset) != 0 { $0.insert($1.element) } }
      let point = CGPoint(x: 123, y: 231), expected = model.viewport.documentPoint(at: CGPoint(x: 123, y: 231))
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil), modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      canvas.mouseDown(with: event)
      XCTAssertEqual(canvas.toolCursor, .symbol(modifiers.contains(.option) ? "minus.magnifyingglass":"plus.magnifyingglass"))
      XCTAssertEqual(model.zoom, CanvasViewport.step(from: 1, inward: !modifiers.contains(.option)))
      XCTAssertEqual(model.viewport.documentPoint(at: point).x, expected.x, accuracy: 1e-8)
      XCTAssertEqual(model.viewport.documentPoint(at: point).y, expected.y, accuracy: 1e-8)
      canvas.mouseUp(with: event)
    }
    XCTAssertTrue(model.undoStates.isEmpty); XCTAssertNil(model.edit); XCTAssertNil(model.stroke)
  }

  @MainActor func testExistingViewMenusNavigateSkyWithoutChangingUnderlyingDocumentViewport() throws {
    let helper = DocumentWorkspaceTests(), app = AppDelegate()
    defer { helper.cleanup(app.controller) }
    let document = try helper.fixture(app.controller, name: "Owned Sky navigation")
    let store = document.store, original = store.document
    store.zoom = 3; store.pan = CGSize(width: 12, height: 14)
    let model = SkyWorkspace(document: original, library: SkyLibrary())
    model.updateViewport(size: CGSize(width: 600, height: 400), backingScale: 2)
    store.skyWorkspace = model
    app.actual(); XCTAssertEqual(model.zoom, 1)
    app.zoomIn(); XCTAssertEqual(model.zoom, CanvasViewport.step(from: 1, inward: true))
    app.zoomOut(); XCTAssertEqual(model.zoom, 1)
    app.fit(); XCTAssertEqual(model.zoom, model.viewport.fitZoom)
    XCTAssertEqual(store.zoom, 3); XCTAssertEqual(store.pan, CGSize(width: 12, height: 14))
    XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    let menu = NSMenuItem(title: "100%", action: #selector(AppDelegate.actual), keyEquivalent: "1")
    XCTAssertTrue(app.validateMenuItem(menu)); model.committing = true; XCTAssertFalse(app.validateMenuItem(menu))
    let zoom = model.zoom; app.actual(); XCTAssertEqual(model.zoom, zoom)
    model.committing = false; store.cancelSkyReplacement(); app.actual(); XCTAssertEqual(store.zoom, 1)
  }

  @MainActor func testHTTPViewportStateSchemaChangesWithoutDocumentRevisionOrNewEditingRoute() async throws {
    let helper = AutomationTests()
    try await helper.withService(skies: SkyLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      defer { store.cancelSkyReplacement(); store.renderTask?.cancel() }
      store.session = EditorSession(document: try self.document()); try service.share(document)
      let share = try XCTUnwrap(service.shares.first?.id), original = store.document, revision = service.revision(store)
      let model = SkyWorkspace(document: original, library: store.skies); store.skyWorkspace = model
      await model.prepare(); model.updateViewport(size: CGSize(width: 200, height: 160), backingScale: 2)
      model.setZoom(1, center: true); await model.detailTask?.value
      let response = try await helper.request(service, path: "/v1/documents/\(share)")
      XCTAssertEqual(response.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let sky = try XCTUnwrap(json["sky"] as? [String: Any]), viewport = try XCTUnwrap(sky["viewport"] as? [String: Any])
      XCTAssertEqual(viewport["zoom"] as? Double, 1); XCTAssertEqual(viewport["backingScale"] as? Double, 2)
      XCTAssertFalse(viewport["detailBusy"] as? Bool ?? true)
      XCTAssertFalse((viewport["visibleTiles"] as? [[String: Any]] ?? []).isEmpty)
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: sky))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: SkyAPI.stateSchema))
      XCTAssertEqual(service.revision(store), revision); XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
      store.cancelSkyReplacement()
      XCTAssertTrue(store.skyState["viewport"] is NSNull)
      XCTAssertEqual(SkyAPI.commands, ["selection.sky", "sky.replace", "sky.library"])
    }
  }
}
