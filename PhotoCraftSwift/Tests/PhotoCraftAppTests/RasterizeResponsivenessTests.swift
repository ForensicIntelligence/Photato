import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RasterizeResponsivenessTests: XCTestCase {
  private func mainThreadProbe() -> Bool { Thread.isMainThread }
  func gradient(width: Int, height: Int, depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: depth, name: "Owned rasterization")
    document.layers[0].name = "Gradient"
    document.layers[0].content = .gradientFill(GradientFill(dither: false))
    return document
  }
  /// Opt-in wall-clock evidence, not a CI timing assertion or display-rate claim.
  @MainActor func testMeasuredRasterizationSubmission() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_RASTERIZE_REPORT"] else { return }
    var cases: [[String: Any]] = []
    for (width, height) in [(1200, 800), (6000, 4000)] {
      let original = try gradient(width: width, height: height)
      let store = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary())
      defer { store.geometryTask?.cancel(); store.renderTask?.cancel() }
      store.renderTask?.cancel(); await store.renderTask?.value
      let started = ProcessInfo.processInfo.systemUptime
      store.rasterize()
      let returned = ProcessInfo.processInfo.systemUptime
      let busyAtReturn = store.geometryBusy
      await store.geometryTask?.value
      let committed = ProcessInfo.processInfo.systemUptime
      store.renderTask?.cancel(); await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1)
      guard case .raster(let pixels) = try XCTUnwrap(store.activeLayer).content else { return XCTFail("No rasterized content") }
      XCTAssertEqual(pixels.width, width); XCTAssertEqual(pixels.height, height)
      var legacyMS: Double?
      if ProcessInfo.processInfo.environment["PHOTATO_RASTERIZE_LEGACY_REFERENCE"] == "1" {
        let legacy = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary())
        defer { legacy.renderTask?.cancel() }
        legacy.renderTask?.cancel(); await legacy.renderTask?.value
        let layer = try XCTUnwrap(legacy.activeLayer)
        let legacyStarted = ProcessInfo.processInfo.systemUptime
        // Exact pre-change ordinary native expression, replayed in this binary.
        legacy.perform(.rasterize(layer.id, try Renderer.layerSurface(layer, in: original)))
        legacyMS = (ProcessInfo.processInfo.systemUptime - legacyStarted) * 1000
        XCTAssertEqual(legacy.document, store.document)
      }
      cases.append(["width": width, "height": height, "submit_main_actor_ms": (returned-started)*1000,
        "legacy_sync_reference_ms": legacyMS as Any? ?? NSNull(),
        "commit_elapsed_ms": (committed-started)*1000, "busy_at_return": busyAtReturn,
        "history_entries": store.session.undoStack.count, "source_unchanged": original.layers[0].isCanvasFill,
        "main_actor_call": mainThreadProbe()])
    }
    let report: [String: Any] = ["cases": cases,
      "scope": "Owned RGB8 Gradient Fill rasterization; time spent in the MainActor rasterize() call and through geometry completion. Initial/final preview publication excluded. Two individual samples, not p95 or physical display/input evidence. Optional legacy_sync_reference_ms replays the pinned old synchronous expression in the current optimized process; it is not an old normal binary measurement."]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
  }
}

extension RasterizeResponsivenessTests {
  func fixture(_ kind: String, depth: PixelDepth) throws -> CraftDocument {
    var d = try gradient(width: 32, height: 24, depth: depth)
    switch kind {
    case "fill": d.layers[0].content = .fill(Pixel(0.3, 0.5, 0.7, 0.8))
    case "text": d.layers[0].content = .text(TextContent(text: "O", size: 12))
    case "shape":
      d.layers[0].content = .shape(ShapeContent(kind: .ellipse, width: 12, height: 8, color: Pixel(0.2, 0.5, 0.8)))
      d.layers[0].affine = .translation(4, 3) * .rotation(15)
    case "raster", "smart":
      d.layers[0].content = .raster(try Surface(width: 12, height: 8, depth: depth, fill: Pixel(0.3, 0.5, 0.8, 0.7)))
      d.layers[0].x = -2; d.layers[0].y = 3
      if kind == "smart" { try SmartObjectIO.convert(in: d, selected: [d.layers[0].id]).apply(to: &d) }
    default: break
    }
    d.layers[0].mask = try Surface(width: 32, height: 24, depth: depth, fill: Pixel(0.65, 0.65, 0.65))
    d.layers[0].opacity = 0.8
    return d
  }
  @MainActor func testNativeWorkerMatchesLegacyAndHTTPBytesHistoryAtEveryDepth() async throws {
    for depth in PixelDepth.allCases { for kind in ["gradient", "fill", "text", "shape", "raster", "smart"] {
      let original = try fixture(kind, depth: depth), layer = original.layers[0]
      var expected = original
      // The pinned pre-change ordinary native expression is the output reference.
      try Command.rasterize(layer.id, Renderer.layerSurface(layer, in: original)).apply(to: &expected)
      let native = EditorStore(document: original, actions: ActionLibrary())
      defer { native.geometryTask?.cancel(); native.renderTask?.cancel() }
      native.rasterize()
      XCTAssertTrue(native.geometryBusy); XCTAssertEqual(native.document, original)
      await native.geometryTask?.value
      XCTAssertNil(native.error); XCTAssertEqual(native.document, expected, "\(kind)/\(depth)")
      XCTAssertEqual(native.session.undoStack.count, 1); XCTAssertFalse(native.geometryBusy)
      XCTAssertEqual(try NativeArchive.encodeChunked(native.document), try NativeArchive.encodeChunked(expected))
      let undo = await native.requestHistory(redo: false).value; XCTAssertTrue(undo); XCTAssertEqual(native.document, original)
      let redo = await native.requestHistory(redo: true).value; XCTAssertTrue(redo); XCTAssertEqual(native.document, expected)
      let helper = AutomationTests()
      try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: original); try service.share(document)
        let status = try await helper.edit(service, document, "layer.rasterize", ["layerID": layer.id.uuidString])
        XCTAssertEqual(status, 200); XCTAssertEqual(document.store.document, expected)
        XCTAssertEqual(try NativeArchive.encodeChunked(document.store.document), try NativeArchive.encodeChunked(expected))
        XCTAssertEqual(document.store.session.undoStack.count, 1)
        let undone = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undone, 200); XCTAssertEqual(document.store.document, original)
        let redone = try await helper.edit(service, document, "history.redo"); XCTAssertEqual(redone, 200); XCTAssertEqual(document.store.document, expected)
      }
    } }
  }
  @MainActor func testCancellationStaleSessionBusyLockedAndModalDoNotCommit() async throws {
    for mode in ["cancel", "stale", "busy", "locked", "modal"] {
      var original = try fixture("gradient", depth: .u8)
      if mode == "locked" { original.layers[0].locked = true }
      let store = EditorStore(document: original, actions: ActionLibrary())
      defer { store.geometryTask?.cancel(); store.renderTask?.cancel() }
      if mode == "busy" { store.geometryBusy = true }
      if mode == "modal" { store.beginFileInfo() }
      store.rasterize()
      if mode == "cancel" { store.geometryTask?.cancel() }
      var expected = original
      if mode == "stale" { expected.name = "Replacement session"; store.session = EditorSession(document: expected) }
      await store.geometryTask?.value
      XCTAssertEqual(store.document, expected, mode); XCTAssertTrue(store.session.undoStack.isEmpty, mode)
      if mode == "locked" { XCTAssertNotNil(store.error) }
      if mode != "busy" { XCTAssertFalse(store.geometryBusy, mode) }
    }
  }
  @MainActor func testAPIGuardsAndSharedPreparationMetadataRemainExplicit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let original = try fixture("gradient", depth: .u8)
      document.store.session = EditorSession(document: original); try service.share(document)
      let parameters: [String: Any] = ["layerID": original.layers[0].id.uuidString]
      let stale = try await helper.edit(service, document, "layer.rasterize", parameters, revision: "stale"); XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "layer.rasterize", parameters); XCTAssertEqual(busy, 409)
      document.store.geometryBusy = false
      let invalid = try await helper.edit(service, document, "layer.rasterize", ["layerID": UUID().uuidString]); XCTAssertGreaterThanOrEqual(invalid, 400)
      XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertNotNil(SmartObject.apiCapabilities["rasterizationPreparation"])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: SmartObject.apiCapabilities))
      XCTAssertEqual(AutomationCommand.definitions.count, 258)
    }
  }
}
