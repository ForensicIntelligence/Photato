import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class CanvasFrameDiagnosticsTests: XCTestCase {
  @MainActor func testReadyBrushStartsFirstFrameBeforeReturningAndKeepsTheLatestBatch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = try CraftDocument(width: 160, height: 100)
    let store = EditorStore(document: document, brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.size = 12; store.brush.color = .black
    await store.renderTask?.value
    let trace = CanvasFrameTrace(directory: directory)
    store.canvasFrameTrace = trace

    store.beginBrush(.init(x: 20, y: 25), zoom: 1)
    XCTAssertEqual(trace.events.map(\.kind), ["input", "prepare"])
    XCTAssertEqual(trace.events.last?.samples, 1)
    let startRevision = try XCTUnwrap(trace.events.last?.revision)
    for index in 1...10 {
      store.extendBrush(.init(x: Double(20 + 10 * index), y: Double(25 + 4 * index)))
    }
    XCTAssertEqual(trace.events.filter { $0.kind == "prepare" }.compactMap(\.revision), [startRevision])
    await store.brushPreviewTask?.value

    let completed = trace.events.filter { $0.kind == "ready" }
    XCTAssertEqual(completed.map(\.samples), [1, 11])
    XCTAssertEqual(Set(completed.compactMap(\.revision)).count, 2)
    let first = try XCTUnwrap(completed.first)
    let worker = try XCTUnwrap(first.worker)
    let firstAdditionalInput = try XCTUnwrap(trace.events.first { $0.kind == "input" && $0.samples == 2 })
    XCTAssertLessThanOrEqual(worker.enqueued, firstAdditionalInput.uptime)
    XCTAssertLessThanOrEqual(worker.enqueued, worker.started)
    XCTAssertLessThanOrEqual(worker.started, worker.ended)
    XCTAssertLessThanOrEqual(worker.ended, first.uptime)
    var expected = document
    try XCTUnwrap(store.brushPreviewCommand).apply(to: &expected)
    let merged = try Renderer.composite(expected)
    XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: merged))
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testCancellingEarlyWorkerKeepsUnpublishedPixelsOutOfTheCanvas() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let document = try CraftDocument(width: 160, height: 100)
    let store = EditorStore(document: document, brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.size = 12; store.brush.color = .black
    await store.renderTask?.value
    let trace = CanvasFrameTrace(directory: directory)
    store.canvasFrameTrace = trace
    let presentation = store.canvasPresentationRevision

    store.beginBrush(.init(x: 20, y: 25), zoom: 1)
    let cancelled = try XCTUnwrap(store.renderTask)
    cancelled.cancel()
    XCTAssertTrue(cancelled.isCancelled)
    await cancelled.value
    await store.brushPreviewTask?.value
    XCTAssertEqual(store.canvasPresentationRevision, presentation)
    XCTAssertTrue(trace.events.filter { $0.kind == "ready" }.isEmpty)
    XCTAssertNil(store.error)
    store.cancelBrush()
    await store.renderTask?.value
    XCTAssertEqual(store.document, document)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testFramePublicationInvalidatesOnlyAttachedCanvasesForCurrentStore() async throws {
    let first = EditorStore(document: try CraftDocument(width: 60, height: 40), brushes: BrushLibrary())
    let second = EditorStore(document: try CraftDocument(width: 60, height: 40), brushes: BrushLibrary())
    await first.renderTask?.value
    await second.renderTask?.value
    let frame = CGRect(x: 0, y: 0, width: 120, height: 80)
    let firstCanvas = CraftCanvas(store: first)
    let secondCanvas = CraftCanvas(store: first)
    let firstWindow = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    let secondWindow = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    firstWindow.isReleasedWhenClosed = false
    secondWindow.isReleasedWhenClosed = false
    firstWindow.contentView = firstCanvas
    secondWindow.contentView = secondCanvas
    defer {
      firstWindow.contentView = nil; secondWindow.contentView = nil
      firstWindow.close(); secondWindow.close()
    }

    // AppKit can clear needsDisplay when it processes the view. Count the
    // notifications at delivery instead of sampling the later state of that flag.
    @MainActor func invalidations(from store: EditorStore) async throws -> Int {
      let trace = CanvasFrameTrace(directory: FileManager.default.temporaryDirectory)
      store.canvasFrameTrace = trace
      store.tool = .brush
      defer {
        store.canvasFrameTrace = nil
        store.cancelBrush()
      }
      store.beginBrush(.init(x: 15, y: 15), zoom: 1)
      await store.brushPreviewTask?.value
      await store.renderTask?.value
      let accepted = try XCTUnwrap(trace.events.last { $0.kind == "ready" })
      XCTAssertNotNil(store.image)
      return trace.events.filter { $0.kind == "invalidate" && $0.revision == accepted.revision }.count
    }

    let both = try await invalidations(from: first)
    XCTAssertEqual(both, 2)
    firstCanvas.store = second
    let remaining = try await invalidations(from: first)
    let rebound = try await invalidations(from: second)
    XCTAssertEqual(remaining, 1)
    XCTAssertEqual(rebound, 1)
    firstWindow.contentView = nil
    let detached = try await invalidations(from: second)
    XCTAssertEqual(detached, 0)
    XCTAssertTrue(first.session.undoStack.isEmpty); XCTAssertTrue(second.session.undoStack.isEmpty)
  }

  @MainActor func testOptInBoundsCorrelationAndStalePreview() async throws {
    XCTAssertNil(CanvasFrameTrace.fromEnvironment([:]))
    XCTAssertNil(CanvasFrameTrace.fromEnvironment(["PHOTATO_CANVAS_TRACE_DIR": "relative"]))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var now = 1.0
    let trace = CanvasFrameTrace(directory: directory, limit: 12, clock: { now })
    trace.begin(tool: "Brush", eventTimestamp: 500)
    now = 1.002; let first = try XCTUnwrap(trace.beginFrame(samples: 1, revision: 10))
    now = 1.003; trace.input(samples: 2, eventTimestamp: 501)
    now = 1.005; trace.prepared(first)
    let draw = trace.beginDraw(); now = 1.006; trace.drew(draw)
    let row = try XCTUnwrap(trace.events.last)
    XCTAssertEqual(row.kind, "draw"); XCTAssertEqual(row.samples, 1)
    XCTAssertEqual(row.revision, 10); XCTAssertEqual(row.inputUptime, 1)
    XCTAssertEqual(try XCTUnwrap(row.durationMS), 1, accuracy: 0.000001)
    for count in 3...30 { trace.input(samples: count) }
    trace.end(cancelled: true)
    XCTAssertEqual(trace.events.count, 12); XCTAssertGreaterThan(trace.droppedEvents, 0)
    let task = try XCTUnwrap(trace.flush())
    let written = await task.value; let url = try XCTUnwrap(written)
    let report = try JSONDecoder().decode(CanvasFrameTrace.Report.self, from: Data(contentsOf: url))
    XCTAssertEqual(report.outcome, "cancelled"); XCTAssertFalse(report.physicalPresentationMeasured)
    XCTAssertEqual(report.events.count, 12); XCTAssertEqual(report.droppedEvents, trace.droppedEvents)
    trace.begin(tool: "Blur"); trace.prepared(first)
    XCTAssertEqual(trace.events.map(\.kind), ["input"])
    trace.end(cancelled: false)
    let nextTask = try XCTUnwrap(trace.flush()); let nextWritten = await nextTask.value; let nextURL = try XCTUnwrap(nextWritten)
    XCTAssertNotEqual(url, nextURL)
    let next = try JSONDecoder().decode(CanvasFrameTrace.Report.self, from: Data(contentsOf: nextURL))
    XCTAssertEqual(next.outcome, "committed")
  }

  @MainActor func testRealPaintingPreviewAndDrawTracePreservePixelsHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var doc = try CraftDocument(width: 120, height: 80)
    doc.layers[0].content = .raster(try Surface(width: 120, height: 80, fill: .white))
    let store = EditorStore(document: doc, brushes: BrushLibrary())
    let trace = CanvasFrameTrace(directory: directory); store.canvasFrameTrace = trace
    store.tool = .brush; store.brush.size = 12; store.brush.color = .black
    let canvas = CraftCanvas(store: store); canvas.frame = CGRect(x: 0, y: 0, width: 240, height: 160)
    store.updateViewport(size: canvas.bounds.size, backingScale: 1); store.setZoom(1, center: true)
    await store.renderTask?.value
    store.beginBrush(.init(x: 15, y: 20), zoom: 1, eventTimestamp: 100)
    for i in 1...20 { store.extendBrush(.init(x: Double(15 + i * 3), y: 20 + sin(Double(i)) * 10), eventTimestamp: 100 + Double(i) / 120) }
    await store.brushPreviewTask?.value; await store.renderTask?.value
    let gesture = try XCTUnwrap(store.brushGesture)
    var expected = doc; try XCTUnwrap(store.brushPreviewCommand).apply(to: &expected)
    XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
    let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8,
      bytesPerRow: 960, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    canvas.draw(canvas.bounds); NSGraphicsContext.restoreGraphicsState()
    let accepted = try XCTUnwrap(trace.events.last(where: { $0.kind == "ready" }))
    let drawn = try XCTUnwrap(trace.events.last(where: { $0.kind == "draw" }))
    XCTAssertEqual(drawn.revision, accepted.revision); XCTAssertEqual(drawn.samples, 21)
    XCTAssertGreaterThanOrEqual(drawn.uptime, accepted.uptime)
    var committed = doc; try gesture.command.apply(to: &committed)
    store.finishBrush(); await store.geometryTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, committed)
    XCTAssertFalse(trace.active); XCTAssertEqual(store.session.undoStack.count, 1)
    let task = try XCTUnwrap(trace.flush()); let written = await task.value; let url = try XCTUnwrap(written)
    let report = try JSONDecoder().decode(CanvasFrameTrace.Report.self, from: Data(contentsOf: url))
    XCTAssertEqual(report.events.filter { $0.kind == "input" }.count, 21)
    XCTAssertEqual(report.events.first?.eventTimestamp, 100)
    XCTAssertEqual(report.droppedEvents, 0)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(Set(json.keys), ["version", "stroke", "tool", "outcome", "droppedEvents", "events", "physicalPresentationMeasured"])
    await store.undo(); XCTAssertEqual(store.document, doc)
  }

  @MainActor func testRetouchCancellationProbeAndAPIContract() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = EditorStore(document: try CraftDocument(width: 60, height: 40), brushes: BrushLibrary())
    store.tool = .dodge; store.canvasFrameTrace = CanvasFrameTrace(directory: directory)
    let canvas = CraftCanvas(store: store); canvas.frame = CGRect(x: 0, y: 0, width: 120, height: 80)
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = canvas; window.orderFront(nil)
    defer { store.cancelClone(); store.renderTask?.cancel(); window.contentView = nil; window.close() }
    canvas.synchronizeFrameProbe(); XCTAssertNil(canvas.frameProbe)
    store.beginClone(.init(x: 10, y: 15), eventTimestamp: 10)
    store.extendClone(.init(x: 12, y: 16), eventTimestamp: 10.01)
    canvas.synchronizeFrameProbe(); XCTAssertNotNil(canvas.frameProbe)
    await store.retouchPreviewTask?.value; await store.renderTask?.value
    XCTAssertTrue(store.canvasFrameTrace!.events.contains { $0.kind == "ready" })
    store.cancelClone(); canvas.synchronizeFrameProbe(); XCTAssertNil(canvas.frameProbe)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    let task = try XCTUnwrap(store.canvasFrameTrace?.flush()); _ = await task.value
    let capabilities = try XCTUnwrap(BrushAPI.capabilities["interactivePreview"] as? [String: Any])
    let diagnostic = try XCTUnwrap(capabilities["diagnostics"] as? [String: Any])
    XCTAssertEqual(diagnostic["maximumEvents"] as? Int, 20_000)
    XCTAssertEqual(diagnostic["physicalPresentationMeasured"] as? Bool, false)
    XCTAssertEqual(diagnostic["enabledByDefault"] as? Bool, false)
  }
}
