import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RetouchPerformanceTests: XCTestCase {
  @MainActor func testMeasuredRetouchRelease() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_RETOUCH_RELEASE_REPORT"] else { return }
    var reports: [[String: Any]] = []
    let tools: [EditorTool] = [.cloneStamp, .healingBrush, .spotHealing, .dodge, .burn, .sponge, .blur, .sharpen, .smudge]
    for (width, height) in [(1200, 800), (6000, 4000)] {
      for tool in tools {
        let store = try await makeStore(width: width, height: height, tool: tool)
        defer { store.cancelClone(); store.renderTask?.cancel() }
        store.retouchPreviewFrameInterval = 0
        store.beginClone(.init(x: 200, y: 250)); await settle(store)
        for i in 1..<240 {
          store.extendClone(.init(x: 200 + Double(i) * 1.2, y: 250 + sin(Double(i) / 12) * 40))
          if i % 16 == 15 { await settle(store) }
        }
        await settle(store)
        let original = store.document, command = try XCTUnwrap(store.cloneDraft?.command)
        let start = ProcessInfo.processInfo.systemUptime
        let reference = try PreparedEdit(command: command, document: original)
        let prepareMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        var expected = EditorSession(document: original); try expected.executePrepared(reference)
        let release = ProcessInfo.processInfo.systemUptime
        store.finishClone()
        let submitMS = (ProcessInfo.processInfo.systemUptime - release) * 1000
        await store.geometryTask?.value
        let commitMS = (ProcessInfo.processInfo.systemUptime - release) * 1000
        await store.renderTask?.value
        let renderMS = (ProcessInfo.processInfo.systemUptime - release) * 1000
        XCTAssertNil(store.error); XCTAssertTrue(store.document == expected.document)
        XCTAssertEqual(store.session.undoStack.count, 1)
        reports.append(["tool": tool.rawValue, "width": width, "height": height,
          "brush_size": store.retouchSettings.brush.size, "points": 240,
          "full_prepare_ms": prepareMS, "release_submit_ms": submitMS,
          "release_commit_ms": commitMS, "release_render_ms": renderMS,
          "native_pixels_match": true, "history_entries": store.session.undoStack.count])
      }
    }
    try JSONSerialization.data(withJSONObject: ["cases": reports,
      "scope": "Owned dense RGB8 plus one adjustment,240 curved samples in batches of16,30px/64px brush at0.96MP/24MP. Preview pacing disabled. Release service and render publication, not physical input/display latency. Healing tools retain their complete final algorithms."], options: [.prettyPrinted, .sortedKeys])
      .write(to: URL(fileURLWithPath: path))
  }
  @MainActor private func makeStore(width: Int, height: Int, tool: EditorTool) async throws -> EditorStore {
    var doc = try CraftDocument(width: width, height: height)
    var pixels = try Surface(width: width, height: height)
    for y in 0..<height {
      for x in 0..<width {
        pixels.setPixel(x: x, y: y, Pixel(Float(x % 127) / 126, Float(y % 97) / 96, Float((x + y) % 53) / 52))
      }
    }
    doc.layers[0].content = .raster(pixels)
    doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.02, 0.1))))
    let state = CloneSources(); state.showOverlay = false
    let store = EditorStore(document: doc, cloneState: state)
    store.tool = tool; store.retouchSettings.brush.size = width > 2000 ? 64 : 30
    store.retouchSettings.brush.pressureSize = false
    store.setCloneSource(at: .init(80, 80)); store.setZoom(min(1, 900 / Double(width)), center: true)
    await store.renderTask?.value
    return store
  }
  @MainActor private func settle(_ store: EditorStore) async {
    await store.clonePrepareTask?.value; await store.retouchPreviewTask?.value; await store.renderTask?.value
  }
  private func stats(_ values: [Double]) -> [String: Any] {
    let ordered = values.sorted()
    guard !ordered.isEmpty else { return ["count": 0] }
    return ["count": ordered.count, "median_ms": ordered[ordered.count / 2],
      "p95_ms": ordered[Int(Double(ordered.count - 1) * 0.95)], "max_ms": ordered.last!]
  }
  @MainActor func testRetouchPreviewServiceAndContinuousInput() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_RETOUCH_REPORT"] else { return }
    var reports: [[String: Any]] = []
    let tools: [EditorTool] = [.cloneStamp, .healingBrush, .spotHealing, .dodge, .burn, .sponge, .blur, .sharpen, .smudge]
    for tool in tools {
      let store = try await makeStore(width: 1200, height: 800, tool: tool)
      store.retouchPreviewFrameInterval = 0
      let began = ProcessInfo.processInfo.systemUptime
      store.beginClone(.init(x: 200, y: 250)); await settle(store)
      let initialMS = (ProcessInfo.processInfo.systemUptime - began) * 1000
      var service: [Double] = []
      for i in 1..<24 {
        let start = ProcessInfo.processInfo.systemUptime
        store.extendClone(.init(x: 200 + Double(i) * 4, y: 250 + sin(Double(i) / 6) * 30))
        await settle(store)
        service.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        XCTAssertNil(store.error)
      }
      var expected = store.document
      try XCTUnwrap(store.cloneDraft?.previewCommand).apply(to: &expected)
      XCTAssertEqual(store.retouchPreviewSampleCount, 24)
      XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
      reports.append(["tool": tool.rawValue, "width": 1200, "height": 800,
        "initial_source_and_preview_ms": initialMS, "service": stats(service), "preview_matches_command": true])
      store.cancelClone(); await settle(store)
    }
    var continuous: [[String: Any]] = []
    for (tool, width, height) in [(EditorTool.cloneStamp, 1200, 800), (.cloneStamp, 6000, 4000), (.blur, 1200, 800), (.smudge, 1200, 800)] {
      let store = try await makeStore(width: width, height: height, tool: tool)
      store.beginClone(.init(x: 200, y: 250)); await settle(store)
      let beforeFrames = store.retouchPreviewFrameCount
      var input: [Double] = []
      let began = ProcessInfo.processInfo.systemUptime
      for i in 1..<240 {
        let delay = began + Double(i) / 120 - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let start = ProcessInfo.processInfo.systemUptime
        store.extendClone(.init(x: 200 + Double(i) * 1.2, y: 250 + sin(Double(i) / 12) * 40))
        input.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      }
      let duringFrames = store.retouchPreviewFrameCount - beforeFrames
      let inputEnd = ProcessInfo.processInfo.systemUptime
      await settle(store)
      let finalTime = ProcessInfo.processInfo.systemUptime
      XCTAssertNil(store.error); XCTAssertEqual(store.retouchPreviewSampleCount, 240)
      var expected = store.document; try XCTUnwrap(store.cloneDraft?.previewCommand).apply(to: &expected)
      XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
      continuous.append(["tool": tool.rawValue, "width": width, "height": height,
        "input": stats(input), "frames_during_input": duringFrames,
        "input_seconds": inputEnd - began, "final_drain_ms": (finalTime - inputEnd) * 1000,
        "total_frames": store.retouchPreviewFrameCount - beforeFrames,
        "samples_preserved": store.retouchPreviewSampleCount, "preview_matches_command": true])
      store.cancelClone(); await settle(store)
    }
    let report: [String: Any] = ["sequential": reports, "continuous": continuous,
      "scope": "Release EditorStore CPU preview measurements on dense RGB8 plus one adjustment; sequential pacing disabled, continuous120Hz input for2 seconds. Source setup is separate. Spot Healing measures its marker preview, not completed healing. No physical display timing or Photoshop pixel-equivalence claim."]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
  }
  @MainActor func testLargeImageRetouchCadence() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_LARGE_RETOUCH_REPORT"] else { return }
    var reports: [[String: Any]] = []
    for tool in [EditorTool.dodge, .burn, .sponge, .blur, .sharpen, .smudge] {
      let store = try await makeStore(width: 6000, height: 4000, tool: tool)
      let started = ProcessInfo.processInfo.systemUptime
      store.beginClone(.init(x: 200, y: 250)); await settle(store)
      let initialMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
      let beforeFrames = store.retouchPreviewFrameCount
      let began = ProcessInfo.processInfo.systemUptime
      var input: [Double] = [], renders: [Double] = []
      var frames = store.retouchPreviewFrameCount
      for i in 1..<240 {
        let delay = began + Double(i) / 120 - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let start = ProcessInfo.processInfo.systemUptime
        store.extendClone(.init(x: 200 + Double(i)*1.2, y: 250 + sin(Double(i)/12)*40))
        input.append((ProcessInfo.processInfo.systemUptime - start)*1000)
        if store.retouchPreviewFrameCount != frames {
          renders.append(store.retouchPreviewRenderMS); frames = store.retouchPreviewFrameCount
        }
      }
      let during = store.retouchPreviewFrameCount - beforeFrames
      let ended = ProcessInfo.processInfo.systemUptime
      await settle(store)
      let drained = ProcessInfo.processInfo.systemUptime
      XCTAssertNil(store.error); XCTAssertEqual(store.retouchPreviewSampleCount, 240)
      var expected = store.document; try XCTUnwrap(store.cloneDraft?.previewCommand).apply(to: &expected)
      XCTAssertTrue(expected != store.document, "The \(tool) performance case must change pixels")
      XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
      reports.append(["tool": tool.rawValue, "width": 6000, "height": 4000, "brush_size": store.retouchSettings.brush.size,
        "first_source_and_preview_ms": initialMS, "input": stats(input), "sampled_render": stats(renders),
        "frames_during_input": during, "input_seconds": ended-began,
        "final_drain_ms": (drained-ended)*1000, "total_frames": store.retouchPreviewFrameCount-beforeFrames,
        "samples_preserved": store.retouchPreviewSampleCount, "preview_matches_command": true, "changes_document": expected != store.document])
      store.cancelClone(); await settle(store)
    }
    try JSONSerialization.data(withJSONObject: ["cases": reports,
      "scope": "Release CPU snapshot publication; dense24MP RGB8 plus adjustment;64px brush;240 input samples at120Hz. Physical display timing and Photoshop equivalence are not measured."], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
  }

}
