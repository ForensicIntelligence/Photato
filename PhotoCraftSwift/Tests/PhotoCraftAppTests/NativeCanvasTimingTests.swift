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
    var results: [[String: Any]] = []
    for tool in [EditorTool.brush, .blur, .dodge, .smudge] {
      var document = try CraftDocument(width: 1200, height: 800)
      var pixels = try Surface(width: 1200, height: 800)
      pixels.mapPixels { x, y, _ in Pixel(Float(x % 127) / 126, Float(y % 97) / 96, 0.4) }
      document.layers[0].content = .raster(pixels)
      let store = EditorStore(document: document, cloneState: CloneSources(), brushes: BrushLibrary())
      store.tool = tool; store.brush.size = 30; store.brush.color = .black
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
      store.setZoom(0.5, center: true); await store.renderTask?.value
      try await Task.sleep(for: .milliseconds(100))
      let began = ProcessInfo.processInfo.systemUptime
      // Drive the same store gesture entry points at120Hz while the actual
      // WorkspaceView/CanvasHost/AppKit run loop displays accepted previews.
      // No direct draw(), synthetic NSEvent or physical-input claim is involved.
      for i in 0..<240 {
        let delay = began + Double(i) / 120 - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let point = StrokePoint(x: 150 + Double(i) * 2, y: 250 + sin(Double(i) / 15) * 80,
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
      let draws = events.filter { $0.kind == "draw" && $0.revision != nil }
      XCTAssertEqual(inputs.count, 240); XCTAssertEqual(inputs.last?.samples, 240)
      XCTAssertFalse(ready.isEmpty); XCTAssertFalse(draws.isEmpty)
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
        "draw_count": draws.count, "distinct_drawn_revisions": Set(draws.compactMap(\.revision)).count,
        "display_callbacks": events.filter { $0.kind == "displayCallback" }.count,
        "physical_presentation_measured": false, "pixels_match_complete_native_command": true])
    }
    let report: [String: Any] = ["cases": results,
      "scope": "Owned1200x800 native WorkspaceView at50%,30px tool,240 store-generated samples at120Hz. Actual AppKit draw callbacks and display-link markers; no direct offscreen draw, physical input, input-to-photon or Photoshop pixel-equivalence claim."]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
  }
}
