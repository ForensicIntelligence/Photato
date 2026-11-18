import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class NativeCanvasTimingTests: XCTestCase {
  @MainActor func testContinuousInputInHostedNativeWorkspace() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_NATIVE_FRAME_REPORT"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let large = ProcessInfo.processInfo.environment["PHOTATO_NATIVE_LARGE_FRAME"] == "1"
    let (width, height, zoom) = large ? (6000, 4000, 0.125) : (1200, 800, 0.5)
    let tools: [EditorTool] = large ? [.brush] : [.brush, .blur, .dodge, .smudge]
    var results: [[String: Any]] = []
    for tool in tools {
      var document = try CraftDocument(width: width, height: height)
      var pixels = try Surface(width: width, height: height)
      pixels.mapPixels { x, y, _ in Pixel(Float(x % 127) / 126, Float(y % 97) / 96, 0.4) }
      document.layers[0].content = .raster(pixels)
      if large {
        document.layers.append(Layer(name: "Brightness", content: .adjustment(.brightnessContrast(0.05, 0.1))))
        document.layers.append(Layer(name: "Contrast", content: .adjustment(.brightnessContrast(-0.05, 0.1))))
      }
      let store = EditorStore(document: document, cloneState: CloneSources(), brushes: BrushLibrary())
      store.tool = tool; store.brush.size = large ? 64 : 30; store.brush.color = .black
      if tool == .brush { store.brushOptions.smoothing.amount = 0 }
      store.retouchSettings.brush.size = 30; store.retouchSettings.brush.pressureSize = false
      let trace = CanvasFrameTrace(directory: directory); store.canvasFrameTrace = trace
      let host = NSHostingView(rootView: WorkspaceView(store: store))
      let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1380, height: 930),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.title = "Photato owned timing fixture"
      window.contentView = host; window.makeKeyAndOrderFront(nil)
      defer {
        store.cancelBrush(); store.cancelClone(); store.renderTask?.cancel()
        window.contentView = nil; window.close()
      }
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(150))
      store.setZoom(zoom, center: true); await store.renderTask?.value
      try await Task.sleep(for: .milliseconds(100))
      let began = ProcessInfo.processInfo.systemUptime
      // Drive the same store gesture entry points at120Hz while the actual
      // WorkspaceView/CanvasHost/AppKit run loop displays accepted previews.
      // No direct draw(), synthetic NSEvent or physical-input claim is involved.
      for i in 0..<240 {
        let delay = began + Double(i) / 120 - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let point = StrokePoint(x: 150 * (large ? 4 : 1) + Double(i) * (large ? 10 : 2),
          y: (250 + sin(Double(i) / 15) * 80) * (large ? 4 : 1),
          time: Double(i) * 1000 / 120)
        if tool == .brush {
          if i == 0 { store.beginBrush(point, zoom: store.effectiveZoom) } else { store.extendBrush(point) }
        } else {
          if i == 0 { store.beginClone(point) } else { store.extendClone(point) }
        }
      }
      await store.clonePrepareTask?.value; await store.brushPreviewTask?.value
      await store.retouchPreviewTask?.value; await store.renderTask?.value
      try await Task.sleep(for: .milliseconds(100))
      let events = trace.events
      let inputs = events.filter { $0.kind == "input" }
      let ready = events.filter { $0.kind == "ready" }
      let invalidations = events.filter { $0.kind == "invalidate" }
      let draws = events.filter { $0.kind == "draw" && $0.revision != nil }
      XCTAssertEqual(inputs.count, 240); XCTAssertEqual(inputs.last?.samples, 240)
      XCTAssertFalse(ready.isEmpty); XCTAssertFalse(draws.isEmpty)
      XCTAssertEqual(invalidations.map(\.revision), ready.map(\.revision))
      // No pointer geometry changes in this store-driven fixture. Preparing the
      // next preview must not redraw the previously accepted pixels every time.
      XCTAssertLessThanOrEqual(draws.count, ready.count + max(8, ready.count / 5))
      XCTAssertEqual(trace.droppedEvents, 0); XCTAssertNil(store.error)
      var expected = document
      let command = try XCTUnwrap(tool == .brush ? store.brushGesture?.command : store.cloneDraft?.command)
      try command.apply(to: &expected)
      XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
      if tool == .brush { store.cancelBrush() } else { store.cancelClone() }
      let writer = try XCTUnwrap(trace.flush()); let written = await writer.value
      let url = try XCTUnwrap(written)
      results.append(["tool": tool.rawValue, "trace": url.lastPathComponent,
        "input_count": inputs.count, "ready_count": ready.count,
        "invalidate_count": invalidations.count, "draw_count": draws.count,
        "distinct_drawn_revisions": Set(draws.compactMap(\.revision)).count,
        "display_callbacks": events.filter { $0.kind == "displayCallback" }.count,
        "physical_presentation_measured": false, "pixels_match_complete_native_command": true])
    }
    let report: [String: Any] = ["cases": results,
      "scope": "Owned raster in a native WorkspaceView. 240 store-generated samples at 120 Hz. Actual AppKit draw callbacks and display-link markers. Physical input, input-to-photon and Photoshop pixel equivalence remain unqualified.",
      "width": width, "height": height, "zoom": zoom, "layered": large]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
  }
}
