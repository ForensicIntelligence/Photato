import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class InteractivePaintingPerformanceTests: XCTestCase {
  @MainActor func testMeasuredStrokeRelease() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_STROKE_COMMIT_REPORT"] else { return }
    var reports: [[String: Any]] = []
    for (width, height) in [(1200, 800), (6000, 4000)] {
      for smoothing in [0.0, 0.8] {
        var document = try CraftDocument(width: width, height: height)
        var pixels = try Surface(width: width, height: height)
        pixels.mapPixels { x, y, _ in Pixel(Float(x) / Float(width), Float(y) / Float(height), 0.4) }
        document.layers[0].content = .raster(pixels)
        let store = EditorStore(document: document, brushes: BrushLibrary())
        defer { store.cancelBrush(); store.renderTask?.cancel() }
        store.tool = .brush; store.brush.size = 64; store.brush.color = .black
        store.brushOptions.flow = 0.3; store.brushOptions.spacing = 0.1
        store.brushOptions.smoothing.amount = smoothing
        store.brushPreviewFrameInterval = 0
        store.updateViewport(size: CGSize(width: 960, height: 640), backingScale: 1)
        store.setZoom(min(1, 900 / Double(width)), center: true); await store.renderTask?.value
        for i in 0..<480 {
          let t = Double(i) / 479
          let point = StrokePoint(x: 100 + t * Double(width - 200),
            y: Double(height) * (0.5 + 0.25 * sin(t * .pi * 6)),
            pressure: Float(0.6 + 0.4 * sin(t * .pi)), time: Double(i) * 1000 / 120)
          if i == 0 { store.beginBrush(point, zoom: store.effectiveZoom) } else { store.extendBrush(point) }
          if i % 16 == 15 { await store.brushPreviewTask?.value; await store.renderTask?.value }
        }
        let command = try XCTUnwrap(store.brushGesture?.command)
        let prepareStart = ProcessInfo.processInfo.systemUptime
        let reference = try PreparedEdit(command: command, document: document)
        let prepareMS = (ProcessInfo.processInfo.systemUptime - prepareStart) * 1000
        var expected = EditorSession(document: document); try expected.executePrepared(reference)
        let releaseStart = ProcessInfo.processInfo.systemUptime
        store.finishBrush()
        let submitMS = (ProcessInfo.processInfo.systemUptime - releaseStart) * 1000
        await store.geometryTask?.value
        let committedMS = (ProcessInfo.processInfo.systemUptime - releaseStart) * 1000
        await store.renderTask?.value
        let visibleMS = (ProcessInfo.processInfo.systemUptime - releaseStart) * 1000
        XCTAssertNil(store.error); XCTAssertTrue(store.document == expected.document)
        XCTAssertEqual(store.session.undoStack.count, 1)
        reports.append(["width": width, "height": height, "brush_size": 64, "points": 480,
          "smoothing": smoothing, "full_prepare_ms": prepareMS, "release_submit_ms": submitMS,
          "release_commit_ms": committedMS, "release_render_ms": visibleMS,
          "native_pixels_match": true, "history_entries": store.session.undoStack.count])
      }
    }
    try JSONSerialization.data(withJSONObject: ["cases": reports,
      "scope": "Owned dense RGB8 gradients,480 curved timed samples in batches of16,64px brush at30% flow/10% spacing, optional80% smoothing. Preview pacing disabled to isolate release service cost. Release timings include native preparation/history/render publication, not physical input or display latency."], options: [.prettyPrinted, .sortedKeys])
      .write(to: URL(fileURLWithPath: path))
  }
  /// Opt-in wall-clock evidence, not a timing assertion on shared CI hardware.
  @MainActor func testMeasuredPreviewPipeline() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_INTERACTIVE_REPORT"] else { return }
    var reports: [[String: Any]] = []
    for (width, height, size) in [(1024, 768, 32.0), (2048, 1536, 64.0), (6000, 4000, 64.0)] {
      var doc = try CraftDocument(width: width, height: height)
      doc.layers[0].content = .raster(try Surface(width: width, height: height, fill: .white))
      let store = EditorStore(document: doc, brushes: BrushLibrary())
      store.zoom = 1
      store.brushPreviewFrameInterval = 0 // Measure service cost without intentional frame pacing.
      store.tool = .brush; store.brush.size = size; store.brush.color = Pixel(0.1, 0.3, 0.9)
      await store.renderTask?.value
      var input: [Double] = [], preview: [Double] = []
      for i in 0..<48 {
        let point = StrokePoint(x: 100 + Double(i) * 8, y: 180 + sin(Double(i) / 6) * 60, time: Double(i) * 16.667)
        let start = ProcessInfo.processInfo.systemUptime
        if i == 0 { store.beginBrush(point, zoom: 1) } else { store.extendBrush(point) }
        input.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        await store.brushPreviewTask?.value
        await store.renderTask?.value
        preview.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        XCTAssertNil(store.error)
      }
      var expected = doc
      try XCTUnwrap(store.brushGesture?.command).apply(to: &expected)
      XCTAssertEqual(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)), nil)
      func summary(_ values: [Double]) -> [String: Any] {
        let ordered = values.sorted()
        return ["median_ms": ordered[ordered.count / 2], "p95_ms": ordered[Int(Double(ordered.count - 1) * 0.95)], "max_ms": ordered.last!, "samples_ms": values]
      }
      reports.append(["width": width, "height": height, "brush_size": size, "samples": 48,
        "input": summary(input), "input_to_preview": summary(preview), "preview_matches_command": true])
      store.cancelBrush(); await store.renderTask?.value
    }
    try JSONSerialization.data(withJSONObject: ["cases": reports,
      "scope": "Release in-process EditorStore input through published render snapshot; 48 sequential samples per case on a white RGB8 layer. Frame pacing disabled to measure service cost. Excludes physical display presentation and AppKit event delivery. No universal 60fps claim."], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
  }
}

extension InteractivePaintingPerformanceTests {
  @MainActor func testDenseLayeredAndContinuousInputPerformance() async throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_INTERACTIVE_EXTENDED_REPORT"] else { return }
    var reports: [[String: Any]] = []
    for (width, height, size) in [(1200, 800, 30.0), (2048, 1536, 64.0), (6000, 4000, 64.0), (2048, 1536, 256.0)] {
      var doc = try CraftDocument(width: width, height: height)
      var pixels = try Surface(width: width, height: height)
      pixels.mapPixels { x, y, _ in Pixel(Float(x) / Float(width), Float(y) / Float(height), 0.4) }
      doc.layers[0].content = .raster(pixels)
      doc.layers.append(Layer(name: "Brightness", content: .adjustment(.brightnessContrast(0.05, 0.1))))
      doc.layers.append(Layer(name: "Contrast", content: .adjustment(.brightnessContrast(-0.05, 0.1))))
      let store = EditorStore(document: doc, brushes: BrushLibrary())
      store.tool = .brush; store.brush.size = size; store.brush.color = .black
      await store.renderTask?.value
      let canvas = CraftCanvas(store: store); canvas.frame = CGRect(x: 0, y: 0, width: 960, height: 640)
      store.updateViewport(size: canvas.bounds.size, backingScale: 1)
      store.setZoom(min(1, 900 / Double(width)), center: true)
      await store.renderTask?.value
      let context = try XCTUnwrap(CGContext(data: nil, width: 960, height: 640,
        bitsPerComponent: 8, bytesPerRow: 960 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      var inputMS: [Double] = [], renderMS: [Double] = [], drawMS: [Double] = []
      var seenFrames = 0
      let began = ProcessInfo.processInfo.systemUptime
      //120Hz event stream for2 seconds, independent of preview completion.
      for i in 0..<240 {
        let due = began + Double(i) / 120
        let delay = due - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let t = ProcessInfo.processInfo.systemUptime
        let point = StrokePoint(x: 150 + Double(i) * 2, y: 250 + sin(Double(i) / 15) * 80, time: Double(i) * 1000 / 120)
        if i == 0 { store.beginBrush(point, zoom: store.effectiveZoom) } else { store.extendBrush(point) }
        inputMS.append((ProcessInfo.processInfo.systemUptime - t) * 1000)
        if store.brushPreviewFrameCount != seenFrames {
          seenFrames = store.brushPreviewFrameCount; renderMS.append(store.brushPreviewRenderMS)
          let draw = ProcessInfo.processInfo.systemUptime
          NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
          canvas.draw(canvas.bounds); NSGraphicsContext.restoreGraphicsState()
          drawMS.append((ProcessInfo.processInfo.systemUptime - draw) * 1000)
        }
      }
      await store.brushPreviewTask?.value; await store.renderTask?.value
      let elapsed = ProcessInfo.processInfo.systemUptime - began
      XCTAssertEqual(store.brushPreviewSampleCount, 240)
      var expected = doc; try XCTUnwrap(store.brushGesture?.command).apply(to: &expected)
      XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
      func statistics(_ samples: [Double]) -> [String: Any] {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return ["count": 0] }
        return ["count": sorted.count, "median_ms": sorted[sorted.count / 2],
          "p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)], "max_ms": sorted.last!]
      }
      reports.append(["width": width, "height": height, "brush_size": size,
        "input": statistics(inputMS), "render": statistics(renderMS), "appkit_draw": statistics(drawMS),
        "frames": store.brushPreviewFrameCount, "samples_preserved": store.brushPreviewSampleCount,
        "elapsed_seconds": elapsed])
      store.cancelBrush(); await store.renderTask?.value
    }
    try JSONSerialization.data(withJSONObject: ["cases": reports,
      "scope": "Dense RGB8 gradient plus two adjustments,120Hz timed input,60Hz preview pacing and960x640 offscreen AppKit draws. CPU timings; physical display presentation is not measured."], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
  }
}
