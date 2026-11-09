import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SkyCanvasContainmentTests: XCTestCase {
  @MainActor private func fixture() throws -> SkyWorkspace {
    let document = try CraftNSDocument.blankModel(width: 3072, height: 3072)
    let model = SkyWorkspace(document: document, library: SkyLibrary())
    func image(_ color: NSColor) throws -> CGImage {
      let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32,
        bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
      return try XCTUnwrap(context.makeImage())
    }
    model.originalImage = try image(.blue)
    model.previewImage = try image(.green)
    model.maskImage = try image(.red)
    return model
  }

  @MainActor func testZoomPanResizeContainOriginalPreviewMaskAndBrushFeedback() throws {
    let model = try fixture(), canvas = SkyCanvasView()
    defer { model.close() }
    canvas.model = model
    let width = 420, height = 340, origin = CGPoint(x: 70, y: 60)
    let scenarios: [(CGSize, Double, CGSize)] = [
      (.init(width: 250, height: 210), 4, .zero),
      (.init(width: 250, height: 210), 16, .init(width: -190, height: -160)),
      (.init(width: 140, height: 95), 8, .init(width: 170, height: 120))]
    for (index, scenario) in scenarios.enumerated() {
      canvas.frame = CGRect(origin: .zero, size: scenario.0)
      model.zoom = scenario.1; model.pan = scenario.2
      for mode in 0..<3 {
        model.showOriginal = mode == 0; model.showMask = mode == 2
        model.stroke = SkyMaskStroke(points: [.init(x: -6000, y: -6000), .init(x: 9000, y: 9000)],
          size: 5000, hardness: 1, opacity: 1, add: mode != 1)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.85, green: 0.05, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let before = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        context.translateBy(x: origin.x, y: origin.y)
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let after = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        let viewport = CGRect(origin: origin, size: scenario.0)
        var changedOutside = 0, changedInside = 0
        for y in 0..<height { for x in 0..<width {
          let offset = (y * width + x) * 4
          if before[offset..<offset + 4] != after[offset..<offset + 4] {
            if viewport.contains(CGPoint(x: Double(x) + 0.5, y: Double(height - y) - 0.5)) {
              changedInside += 1
            } else { changedOutside += 1 }
          }
        } }
        XCTAssertEqual(changedOutside, 0, "Sky drawing escaped scenario \(index), mode \(mode)")
        XCTAssertGreaterThan(changedInside, 100, "Clipping must retain visible canvas content")
        if let root = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
           let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
          try png.write(to: URL(fileURLWithPath: root).appendingPathComponent("sky-clip-\(index)-\(mode).png"))
        }
      }
    }
    XCTAssertTrue(canvas.clipsToBounds)
    XCTAssertTrue(canvas.layer?.masksToBounds == true)
  }

  @MainActor func testScrollZoomAndHandPanPreserveChromeHitRegionsAndDocument() throws {
    _ = NSApplication.shared
    let model = try fixture(), original = model.original, canvas = SkyCanvasView()
    defer { model.close() }
    // These are test-owned event values delivered directly to the view, never posted to the OS.
    model.input = try SkyReplacementInput.prepare(model.original)
    let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 460, height: 360),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 460, height: 360))
    window.contentView = root
    canvas.model = model; canvas.frame = CGRect(x: 20, y: 45, width: 280, height: 250)
    root.addSubview(canvas)
    let header = NSButton(title: "Sky tool", target: nil, action: nil)
    header.frame = CGRect(x: 20, y: 310, width: 100, height: 30); root.addSubview(header)
    let footer = NSButton(title: "Cancel", target: nil, action: nil)
    footer.frame = CGRect(x: 20, y: 5, width: 100, height: 30); root.addSubview(footer)
    let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
      wheelCount: 2, wheel1: 500, wheel2: -350, wheel3: 0))
    let scroll = try XCTUnwrap(NSEvent(cgEvent: cg))
    model.zoom = 4
    canvas.scrollWheel(with: scroll)
    XCTAssertEqual(model.pan.width, -scroll.scrollingDeltaX)
    XCTAssertEqual(model.pan.height, -scroll.scrollingDeltaY)
    let zoom = model.zoom
    cg.flags = .maskAlternate
    let zoomEvent = try XCTUnwrap(NSEvent(cgEvent: cg))
    let anchor = canvas.convert(zoomEvent.locationInWindow, from: nil)
    let documentPoint = model.viewport.documentPoint(at: anchor)
    canvas.scrollWheel(with: zoomEvent)
    XCTAssertNotEqual(model.zoom, zoom)
    XCTAssertEqual(model.viewport.documentPoint(at: anchor).x, documentPoint.x, accuracy: 1e-8)
    XCTAssertEqual(model.viewport.documentPoint(at: anchor).y, documentPoint.y, accuracy: 1e-8)
    model.tool = .hand; model.zoom = 4; model.pan = .zero
    func mouse(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
        modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1))
    }
    canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 100, y: 100)))
    canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 400, y: -250)))
    canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 400, y: -250)))
    XCTAssertEqual(model.pan, CGSize(width: 300, height: -350))
    XCTAssertFalse(canvas.panning); XCTAssertFalse(canvas.cursorPointerDown)
    XCTAssertTrue(root.hitTest(CGPoint(x: 70, y: 325)) === header)
    XCTAssertTrue(root.hitTest(CGPoint(x: 70, y: 20)) === footer)
    XCTAssertFalse(canvas.ownsToolCursor(atWindowPoint: root.convert(CGPoint(x: 70, y: 325), to: nil)))
    XCTAssertFalse(canvas.ownsToolCursor(atWindowPoint: root.convert(CGPoint(x: 70, y: 20), to: nil)))
    XCTAssertEqual(model.original, original); XCTAssertTrue(model.undoStates.isEmpty)
    XCTAssertNil(model.stroke); XCTAssertNil(model.edit)
  }
}
