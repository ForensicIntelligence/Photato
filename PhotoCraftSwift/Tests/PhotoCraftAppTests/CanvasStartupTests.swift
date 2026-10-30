import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class CanvasStartupTests: XCTestCase {
  @MainActor private func store() throws -> EditorStore {
    var doc = try CraftDocument(width: 1200, height: 800)
    doc.layers[0].content = .raster(try Surface(width: 1200, height: 800, fill: Pixel(0.2, 0.4, 0.6)))
    return EditorStore(document: doc)
  }
  @MainActor private func assertPresentation(_ store: EditorStore, file: StaticString = #filePath, line: UInt = #line) throws {
    let preview = try XCTUnwrap(store.canvasRasterPreview, file: file, line: line)
    let scale = min(1, store.effectiveZoom)
    let width = max(1, Int(ceil(Double(store.document.width) * scale)))
    let height = max(1, Int(ceil(Double(store.document.height) * scale)))
    XCTAssertEqual(preview.presentation?.image.width ?? preview.base.width, width, file: file, line: line)
    XCTAssertEqual(preview.presentation?.image.height ?? preview.base.height, height, file: file, line: line)
    XCTAssertNil(store.error, file: file, line: line)
    XCTAssertFalse(store.rendering, file: file, line: line)
    XCTAssertTrue(store.session.undoStack.isEmpty, file: file, line: line)
  }

  @MainActor func testFirstLayoutPreparesTheResolvedViewportBeforeAnyStroke() async throws {
    let store = try store(), original = store.document
    XCTAssertNil(store.image)
    store.updateViewport(size: .init(width: 960, height: 640), backingScale: 1)
    await store.renderTask?.value
    try assertPresentation(store)
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testInitialExplicitZoomSupersedesPendingPresentation() async throws {
    let store = try store(), original = store.document
    XCTAssertNil(store.image)
    store.setZoom(0.25, center: true)
    await store.renderTask?.value
    try assertPresentation(store)
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testLatestPendingZoomWinsAndMagnificationReturnsToFullResolution() async throws {
    let store = try store(), original = store.document
    store.updateViewport(size: .init(width: 500, height: 400), backingScale: 2)
    for zoom in [0.25, 0.5, 0.75, 0.125] { store.setZoom(zoom, center: true) }
    await store.renderTask?.value
    try assertPresentation(store)
    store.setZoom(2)
    await store.renderTask?.value
    try assertPresentation(store)
    XCTAssertNil(store.canvasRasterPreview?.presentation)
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testArtboardFitRefreshesItsPresentationWithoutChangingDocumentOrHistory() async throws {
    let store = try store(), original = store.document
    await store.renderTask?.value
    store.fitArtboard(.init(x: 100, y: 50, width: 1100, height: 750))
    await store.renderTask?.value
    try assertPresentation(store)
    XCTAssertEqual(store.document, original)
    let rect = store.viewport.imageRect
    let center = CGPoint(x: rect.minX + 650 * store.viewport.scale, y: rect.minY + 425 * store.viewport.scale)
    XCTAssertEqual(center.x, store.viewportSize.width / 2, accuracy: 1e-9)
    XCTAssertEqual(center.y, store.viewportSize.height / 2, accuracy: 1e-9)
  }

  /// Same document and production zoom call with/without an explicit extra warmup.
  /// Timings are evidence only; no wall-clock assertion on shared machines.
  @MainActor func testLargeImageStartupAtRequestedZoom() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_STARTUP_REPORT"] else { return }
    var doc = try CraftDocument(width: 6000, height: 4000)
    var pixels = try Surface(width: 6000, height: 4000)
    pixels.mapPixels { x, y, _ in Pixel(Float(x % 127)/126, Float(y % 97)/96, Float((x+y)%53)/52) }
    doc.layers[0].content = .raster(pixels)
    doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.02, 0.1))))
    var cases: [[String: Any]] = []
    for tool in [EditorTool.dodge, .blur, .smudge] {
      for warm in [false, true] {
        let state = CloneSources(); state.showOverlay = false
        let store = EditorStore(document: doc, cloneState: state)
        store.tool = tool; store.retouchSettings.brush.size = 64
        store.retouchSettings.brush.pressureSize = false
        let setup = ProcessInfo.processInfo.systemUptime
        store.setZoom(0.15, center: true)
        await store.renderTask?.value
        if warm { store.render(); await store.renderTask?.value }
        let ready = ProcessInfo.processInfo.systemUptime
        let width = store.canvasRasterPreview?.presentation?.image.width ?? store.image?.width ?? 0
        store.beginClone(.init(x: 200, y: 250))
        store.extendClone(.init(x: 232, y: 258))
        await store.clonePrepareTask?.value; await store.retouchPreviewTask?.value; await store.renderTask?.value
        let initialMS = (ProcessInfo.processInfo.systemUptime-ready)*1000
        XCTAssertNil(store.error); XCTAssertEqual(store.retouchPreviewSampleCount, 2)
        var expected = doc; try XCTUnwrap(store.cloneDraft?.previewCommand).apply(to: &expected)
        XCTAssertTrue(expected != doc, "The moving startup stroke must change pixels")
        XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
        cases.append(["tool": tool.rawValue, "extra_warmup": warm, "width": 6000, "height": 4000,
          "requested_scale": 0.15, "ready_presentation_width": width, "expected_presentation_width": 900,
          "setup_ms": (ready-setup)*1000, "first_source_and_preview_ms": initialMS,
          "preview_matches_command": true, "changes_document": true, "samples_preserved": 2])
        store.cancelClone(); await store.renderTask?.value
      }
    }
    try JSONSerialization.data(withJSONObject: ["cases": cases,
      "scope": "Release EditorStore24MP64px retouch startup after the actual setZoom path, paired with explicit extra render warmup. CPU publication only; setup cost reported separately. Owned RGB8 pattern plus adjustment. No physical-display or Photoshop pixel-equivalence claim."], options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: path))
  }
}
