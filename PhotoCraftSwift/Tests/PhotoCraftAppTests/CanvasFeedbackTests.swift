import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class CanvasFeedbackTests: XCTestCase {
  @MainActor private func fixture(_ tool: EditorTool = .brush) async throws -> (EditorStore, CraftCanvas, NSWindow) {
    var doc = try CraftDocument(width: 1200, height: 800)
    doc.layers[0].content = .raster(try Surface(width: 1200, height: 800, fill: .white))
    let store = EditorStore(document: doc, brushes: BrushLibrary())
    store.tool = tool; store.brush.size = 24; store.brush.color = .black
    let canvas = CraftCanvas(store: store); canvas.frame = CGRect(x: 0, y: 0, width: 960, height: 640)
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = canvas; window.orderFront(nil)
    store.updateViewport(size: canvas.bounds.size, backingScale: Double(window.backingScaleFactor)); store.setZoom(0.7, center: true)
    await store.renderTask?.value
    return (store, canvas, window)
  }
  @MainActor private func event(_ type: NSEvent.EventType, _ point: CGPoint, time: Double) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
      windowNumber: 0, context: nil, eventNumber: Int(time * 1000), clickCount: 1, pressure: 1))
  }
  @MainActor func testDensePaintingSamplesPreserveCurvesPixelsAndHistory() async throws {
    for tool in [EditorTool.brush, .eraser] {
      let (store, canvas, window) = try await fixture(tool)
      defer { canvas.drawingEvents.end(); store.cancelBrush(); store.renderTask?.cancel(); window.contentView = nil; window.close() }
      canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 150, y: 200), time: 1))
      let gesture = try XCTUnwrap(store.brushGesture)
      for i in 1...1000 {
        let p = CGPoint(x: 150 + Double(i) * 0.5, y: 200 + sin(Double(i) / 30) * 60)
        canvas.mouseDragged(with: try event(.leftMouseDragged, p, time: 1 + Double(i) / 1000))
        let expected = canvas.viewport.documentPoint(at: CGPoint(x: p.x, y: canvas.bounds.height - p.y))
        XCTAssertEqual(gesture.points.last!.x, expected.x, accuracy: 0.000001)
        XCTAssertEqual(gesture.points.last!.y, expected.y, accuracy: 0.000001)
      }
      XCTAssertEqual(gesture.points.count, 1001)
      await store.brushPreviewTask?.value; await store.renderTask?.value
      var expected = gesture.original; try gesture.command.apply(to: &expected)
      XCTAssertNil(try XCTUnwrap(store.surface).changedTileBounds(comparedTo: Renderer.composite(expected)))
      XCTAssertEqual(store.brushPreviewSampleCount, 1001)
      XCTAssertEqual(store.document, gesture.original)
      canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 650, y: 200 + sin(1000.0 / 30) * 60), time: 2.001))
      await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertEqual(store.document, gesture.original)
    }
  }
  @MainActor func testSelectionAndPanKeepTheirImmediateGeometry() async throws {
    for tool in [EditorTool.marquee, .lasso, .hand] {
      let (store, canvas, window) = try await fixture(tool)
      defer { store.renderTask?.cancel(); window.contentView = nil; window.close() }
      canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: 150, y: 200), time: 1))
      canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 200, y: 240), time: 1.01))
      XCTAssertNotEqual(canvas.start, canvas.end)
      if tool == .lasso { XCTAssertEqual(canvas.lassoPoints.count, 2) }
    }
  }
}

extension CanvasFeedbackTests {
  @MainActor func testRetouchPartialRedrawMatchesFullCanvas() async throws {
    let (store, canvas, window) = try await fixture(.blur)
    defer { store.cancelClone(); store.renderTask?.cancel(); store.cloneOverlayTask?.cancel(); window.contentView = nil; window.close() }
    var pattern = try Surface(width: 1200, height: 800)
    pattern.mapPixels { x, y, _ in Pixel(Float(x % 73) / 72, Float(y % 89) / 88, 0.4) }
    var doc = store.document; doc.layers[0].content = .raster(pattern)
    store.session = EditorSession(document: doc); store.render(); await store.renderTask?.value
    let width = 960, height = 640
    func context() throws -> CGContext {
      try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }
    func draw(_ context: CGContext, damage: CGRect? = nil) -> Double {
      let began = ProcessInfo.processInfo.systemUptime
      NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      context.saveGState(); if let damage { context.clip(to: damage) }
      canvas.draw(canvas.bounds); context.restoreGState(); NSGraphicsContext.restoreGraphicsState()
      return (ProcessInfo.processInfo.systemUptime - began) * 1000
    }
    var report: [[String: Any]] = []
    for tool in [EditorTool.blur, .cloneStamp] {
      store.tool = tool; canvas.synchronizeTool()
      if tool == .cloneStamp { store.setCloneSource(at: PathPoint(450, 380)); store.refreshCloneOverlay(); await store.cloneOverlayTask?.value }
      for zoom in [0.7, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 3.33] {
        store.setZoom(zoom, center: true); await store.renderTask?.value
        for unclipped in [false, true] {
          store.cloneState.showOverlay = true; store.cloneState.clippedOverlay = !unclipped
          for pair in [(CGPoint(x: 530, y: 420), CGPoint(x: 565, y: 438)),
                       (CGPoint(x: -5, y: 15), CGPoint(x: 5, y: 25))] {
            let partial = try context(), full = try context()
            canvas.cloneHover = pair.0; _ = draw(partial)
            canvas.cloneHover = pair.1
            let damage = canvas.retouchFeedbackDamage(from: pair.0, to: pair.1)
            let partialMS = damage.isNull || damage.isEmpty ? 0 : draw(partial, damage: damage)
            let fullMS = draw(full)
            let size = width * height * 4
            let a = Data(bytes: try XCTUnwrap(partial.data), count: size)
            let b = Data(bytes: try XCTUnwrap(full.data), count: size)
            if a != b, let output = ProcessInfo.processInfo.environment["PHOTATO_FEEDBACK_DIFF_DIR"] {
              let url = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
              let tag = "\(tool)-\(zoom)-\(unclipped)"
              for (name, c) in [("partial", partial), ("full", full)] {
                let image = try XCTUnwrap(c.makeImage())
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try png.write(to: url.appendingPathComponent(tag + "-" + name + ".png"))
              }
              let different = (0..<(width * height)).filter { a[($0*4)..<($0*4+4)] != b[($0*4)..<($0*4+4)] }
              let coordinates = different.prefix(32).map { ["x": $0 % width, "y": $0 / width, "a": Array(a[($0*4)..<($0*4+4)]), "b": Array(b[($0*4)..<($0*4+4)])] as [String: Any] }
              try JSONSerialization.data(withJSONObject: ["pixels": different.count, "first": coordinates,
                "damage": [damage.origin.x, damage.origin.y, damage.width, damage.height]], options: [.prettyPrinted]).write(to: url.appendingPathComponent(tag + ".json"))
            }
            XCTAssertTrue(a == b, "Pointer damage must erase old and draw new overlays exactly: \(tool), zoom\(zoom), unclipped\(unclipped)")
            if zoom == 0.7 && (tool == .blur || !unclipped) { XCTAssertLessThan(damage.isNull ? 0 : damage.width * damage.height, canvas.bounds.width * canvas.bounds.height / 3) }
            report.append(["tool": String(describing: tool), "zoom": zoom, "unclipped": unclipped,
              "damage_pixels": damage.isNull ? 0 : damage.width * damage.height,
              "canvas_pixels": width * height, "partial_draw_ms": partialMS, "full_draw_ms": fullMS,
              "full_pixels_match": a == b])
          }
        }
      }
    }
    if let path = ProcessInfo.processInfo.environment["PHOTATO_FEEDBACK_REPORT"] {
      try JSONSerialization.data(withJSONObject: ["cases": report,
        "scope": "Offscreen AppKit CPU draws clipped to native dirty regions compared byte-for-byte with whole-canvas redraw. Not physical display frame timing."], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
    }
  }
}
