import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class InteractivePaintingWorkflowTests: XCTestCase {
  @MainActor func testQueuedSamplesPreviewCancelCommitHistoryAndStaleCompletion() async throws {
    var doc = try CraftDocument(width: 256, height: 192)
    doc.layers[0].content = .raster(try Surface(width: 256, height: 192, fill: .white))
    doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.1, 0.2))))
    let store = EditorStore(document: doc, brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.size = 24; await store.renderTask?.value
    store.beginBrush(.init(x: 20, y: 50, time: 0), zoom: 1)
    let worker = try XCTUnwrap(store.interactiveBrushPreview)
    for i in 1...200 { store.extendBrush(.init(x: 20 + Double(i), y: 60 + sin(Double(i) / 8) * 20, time: Double(i))) }
    await store.brushPreviewTask?.value; await store.renderTask?.value
    XCTAssertTrue(store.interactiveBrushPreview === worker, "An idle preview must retain its incremental worker")
    var expected = doc; try XCTUnwrap(store.brushGesture?.command).apply(to: &expected)
    XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
    XCTAssertNotNil(store.canvasRasterPreview); XCTAssertEqual(store.document, doc)
    store.finishBrush(); await store.geometryTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, expected); XCTAssertNotNil(store.canvasRasterPreview)
    XCTAssertEqual((store.brushState["preview"] as? [String: Any])?["displayedSamples"] as? Int, 201)
    XCTAssertEqual(store.session.undoStack.count, 1); XCTAssertNil(store.interactiveBrushPreview)
    await store.undo(); XCTAssertEqual(store.document, doc)
    store.beginBrush(.init(x: 50, y: 50), zoom: 1); store.extendBrush(.init(x: 80, y: 70))
    let pending = store.brushPreviewTask; store.cancelBrush(); await pending?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, doc); XCTAssertNotNil(store.canvasRasterPreview)
    store.beginBrush(.init(x: 10, y: 10), zoom: 1)
    store.session = EditorSession(document: try CraftDocument(width: 32, height: 32))
    store.extendBrush(.init(x: 20, y: 20)); await store.renderTask?.value
    XCTAssertNil(store.brushGesture); XCTAssertEqual(store.document.width, 32)
  }
  @MainActor func testEventCaptureRestoresSettingAndCoordinatesMultipleCanvases() {
    XCTAssertEqual((BrushAPI.capabilities["interactivePreview"] as? [String: Any])?["targetFPS"] as? Int, 60)
    let initial = NSEvent.isMouseCoalescingEnabled
    defer { NSEvent.isMouseCoalescingEnabled = initial }
    for previous in [true, false] {
      NSEvent.isMouseCoalescingEnabled = previous
      let first = DrawingEventCapture(), second = DrawingEventCapture()
      first.begin(); first.begin(); second.begin(); XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
      first.end(); XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
      second.end(); second.end(); XCTAssertEqual(NSEvent.isMouseCoalescingEnabled, previous)
    }
  }
  @MainActor func testAbandonedCaptureRestoresInputOnRelease() {
    let previous = NSEvent.isMouseCoalescingEnabled
    defer { NSEvent.isMouseCoalescingEnabled = previous }
    NSEvent.isMouseCoalescingEnabled = true
    var capture: DrawingEventCapture? = DrawingEventCapture()
    weak var released = capture
    capture?.begin(); XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
    capture = nil
    XCTAssertNil(released); XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
  }
  @MainActor func testWindowDeactivationRestoresInputAndCancelsGesture() async throws {
    let before = NSEvent.isMouseCoalescingEnabled
    let store = EditorStore(document: try CraftDocument(width: 64, height: 64), brushes: BrushLibrary())
    let canvas = CraftCanvas(store: store)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    defer { canvas.drawingEvents.end(); window.contentView = nil; store.renderTask?.cancel() }
    window.contentView = canvas; store.tool = .brush
    store.beginBrush(.init(x: 10, y: 10), zoom: 1); canvas.drawingEvents.begin()
    XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    XCTAssertNil(store.brushGesture); XCTAssertEqual(NSEvent.isMouseCoalescingEnabled, before)
    await store.renderTask?.value
  }

  @MainActor func testChannelViewCannotSeedAnOrdinaryPreviewCache() async throws {
    var doc = try CraftDocument(width: 128, height: 96)
    doc.layers[0].content = .raster(try Surface(width: 128, height: 96, fill: Pixel(0.2, 0.7, 0.9)))
    let store = EditorStore(document: doc, brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; await store.renderTask?.value
    store.channelView = RGBChannelView(preview: .red); await store.renderTask?.value
    XCTAssertFalse(store.ordinaryCanvasImage); XCTAssertNil(store.canvasRasterPreview)
    store.beginBrush(.init(x: 25, y: 25), zoom: 1); await store.brushPreviewTask?.value
    store.channelView = RGBChannelView(); await store.renderTask?.value
    let actual = try XCTUnwrap(store.image?.dataProvider?.data) as Data
    let expected = try ColorManagement.displayImage(XCTUnwrap(store.surface), in: doc)
    XCTAssertEqual(actual, expected.dataProvider!.data! as Data)
    XCTAssertTrue(store.ordinaryCanvasImage)
    store.setZoom(0.4); await store.renderTask?.value
    XCTAssertEqual(store.canvasRasterPreview?.presentation?.image.width, 52)
    store.setZoom(1); await store.renderTask?.value
    XCTAssertNil(store.canvasRasterPreview?.presentation)
  }

}

extension InteractivePaintingWorkflowTests {
  @MainActor func testCheckerboardCacheMatchesDecorationAndInvalidatesForViewport() throws {
    let cache = CanvasCheckerboard(), viewport = CGRect(x: 0, y: 0, width: 320, height: 240)
    for backing in [1.0, 2.0] {
      for entry in [(CGRect(x: 20, y: 15, width: 280, height: 200), 2.0), (CGRect(x: -60, y: -30, width: 500, height: 400), 6.0)] {
        func draw(cached: Bool) throws -> Data {
          let w = Int(320 * backing), h = Int(240 * backing)
          let c = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          c.translateBy(x: 0, y: Double(h)); c.scaleBy(x: backing, y: -backing)
          if cached { cache.draw(in: c, viewport: viewport, imageRect: entry.0, cell: entry.1, backing: backing) }
          else { CanvasCheckerboard.paint(in: c, viewport: viewport, imageRect: entry.0, cell: entry.1) }
          return Data(bytes: c.data!, count: w * h * 4)
        }
        let before = cache.rebuildCount, expected = try draw(cached: false)
        XCTAssertEqual(try draw(cached: true), expected)
        XCTAssertEqual(cache.rebuildCount, before + 1)
        XCTAssertEqual(try draw(cached: true), expected); XCTAssertEqual(cache.rebuildCount, before + 1)
      }
    }
  }
}
