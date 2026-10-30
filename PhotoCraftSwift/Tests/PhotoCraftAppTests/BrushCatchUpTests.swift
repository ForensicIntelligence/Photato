import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BrushCatchUpTests: XCTestCase {
  @MainActor func testHeldPointerContinuesWithoutMouseEvents() async throws {
    let store = EditorStore(document: try CraftDocument(width: 160, height: 80), brushes: BrushLibrary())
    store.tool = .brush; store.brush.size = 6; store.brush.color = .black
    store.brushOptions.smoothing.amount = 0.9; store.brushOptions.smoothing.catchUpOnEnd = false
    let canvas = CraftCanvas(store: store)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 240),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = canvas; window.makeKeyAndOrderFront(nil)
    defer { store.cancelBrush(); store.renderTask?.cancel(); window.contentView = nil; window.close() }
    let began = ProcessInfo.processInfo.systemUptime
    func event(_ type: NSEvent.EventType, x: Double, time: Double) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(canvas.viewPoint(CGPoint(x: x, y: 40)), to: nil),
        modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1))
    }
    canvas.mouseDown(with: try event(.leftMouseDown, x: 20, time: began))
    canvas.mouseDragged(with: try event(.leftMouseDragged, x: 140, time: began + 0.001))
    var initial = store.document
    try XCTUnwrap(store.brushPreviewCommand).apply(to: &initial)
    let before = try Renderer.composite(initial)
    try await Task.sleep(for: .milliseconds(240))
    XCTAssertGreaterThan(try XCTUnwrap(store.brushGesture).points.count, 2,
      "A held smoothed stroke must advance without another pointer event")
    XCTAssertFalse(store.surface == before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    canvas.mouseUp(with: try event(.leftMouseUp, x: 140, time: ProcessInfo.processInfo.systemUptime))
    XCTAssertNil(canvas.airbrushTimer); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testReleaseTailIsAbsentFromLivePreview() async throws {
    let document = try CraftDocument(width: 160, height: 80)
    let store = EditorStore(document: document, brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.size = 6; store.brush.color = .black
    store.brushOptions.smoothing.amount = 0.9; store.brushOptions.smoothing.catchUpOnEnd = true
    store.beginBrush(.init(x: 20, y: 40, time: 0), zoom: 1)
    store.extendBrush(.init(x: 140, y: 40, time: 1))
    await store.brushPreviewTask?.value; await store.renderTask?.value
    let gesture = try XCTUnwrap(store.brushGesture)
    var brush = gesture.brush; brush.settings!.smoothing.catchUpOnEnd = false
    var held = document
    try Command.stroke(gesture.layerID, gesture.points, brush).apply(to: &held)
    XCTAssertTrue(store.surface == (try Renderer.composite(held)), "Catch-up on release must wait for release")
    var released = document; try gesture.command.apply(to: &released)
    XCTAssertFalse(held == released)
    store.finishBrush(); await store.geometryTask?.value
    XCTAssertTrue(store.document == released); XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testTimedSamplesRetainTabletDataStopAndReplayThroughHTTP() async throws {
    let helper = AutomationTests()
    try await helper.withService(brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, native in
      let doc = try CraftDocument(width: 160, height: 80), store = native.store
      store.session = EditorSession(document: doc); store.tool = .brush; store.brush.size = 6
      store.brushOptions.smoothing.amount = 0.85; store.brushOptions.flow = 0.5
      try service.share(native)
      store.beginBrush(.init(x: 20, y: 40, time: 0), zoom: 1)
      let target = StrokePoint(x: 140, y: 40, pressure: 0.4, tiltX: 12, tiltY: -23, rotation: 45, wheel: 0.7, time: 1)
      store.extendBrush(target)
      for i in 1...160 {
        if let p = store.advanceStationaryBrush(time: Double(i) * 1000 / 60) {
          XCTAssertEqual(p.x, target.x); XCTAssertEqual(p.y, target.y); XCTAssertEqual(p.pressure, target.pressure)
          XCTAssertEqual(p.tiltX, target.tiltX); XCTAssertEqual(p.tiltY, target.tiltY)
          XCTAssertEqual(p.rotation, target.rotation); XCTAssertEqual(p.wheel, target.wheel)
        }
      }
      let gesture = try XCTUnwrap(store.brushGesture), points = gesture.points, brush = gesture.brush
      XCTAssertGreaterThan(points.count, 2); XCTAssertLessThan(points.count, 160)
      XCTAssertFalse(gesture.needsStationarySample)
      XCTAssertNil(store.advanceStationaryBrush(time: 4000)); XCTAssertNil(store.advanceStationaryBrush(time: .nan))
      XCTAssertEqual(gesture.points.count, points.count)
      XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { ($0.time ?? 0) <= ($1.time ?? 0) })
      var held = doc; try XCTUnwrap(store.brushPreviewCommand).apply(to: &held)
      await store.brushPreviewTask?.value; await store.renderTask?.value
      XCTAssertTrue(store.surface == (try Renderer.composite(held)))
      XCTAssertTrue(store.document == doc); XCTAssertTrue(store.session.undoStack.isEmpty)
      let parameters: [String: Any] = ["points": BrushAPI.json(points), "brush": BrushAPI.json(brush)]
      var status = try await helper.edit(service, native, "paint.stroke", parameters); XCTAssertEqual(status, 409)
      store.finishBrush(); await store.geometryTask?.value; let committed = store.document
      XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertTrue(store.document == doc)
      status = try await helper.edit(service, native, "paint.stroke", parameters); XCTAssertEqual(status, 200)
      XCTAssertTrue(store.document == committed); XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertTrue(store.document == doc)
      _ = await store.requestHistory(redo: true).value; XCTAssertTrue(store.document == committed)
      let metadata = try XCTUnwrap((BrushAPI.capabilities["interactivePreview"] as? [String: Any])?["stationarySmoothing"] as? [String: Any])
      XCTAssertEqual(metadata["targetHz"] as? Int, 60)
      XCTAssertEqual(metadata["releaseTailDuringPreview"] as? Bool, false)
    }
  }

  @MainActor func testDisabledModesAndStaleDocumentDoNotGenerateSamples() async throws {
    let store = EditorStore(document: try CraftDocument(width: 64, height: 48), brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }; store.tool = .brush
    for variant in 0..<3 {
      store.brushOptions.smoothing.amount = variant == 0 ? 0 : 0.8
      store.brushOptions.smoothing.catchUp = variant != 1; store.brushOptions.smoothing.pulledString = variant == 2
      store.beginBrush(.init(x: 5, y: 20, time: 0), zoom: 1); store.extendBrush(.init(x: 50, y: 20, time: 1))
      XCTAssertNil(store.advanceStationaryBrush(time: 100)); XCTAssertEqual(store.brushGesture?.points.count, 2)
      store.cancelBrush()
    }
    store.brushOptions.smoothing.pulledString = false
    store.beginBrush(.init(x: 5, y: 20, time: 0), zoom: 1); store.extendBrush(.init(x: 50, y: 20, time: 1))
    XCTAssertNil(store.advanceStationaryBrush(time: 0)); XCTAssertNil(store.advanceStationaryBrush(time: 3_600_001))
    store.session = EditorSession(document: try CraftDocument(width: 32, height: 32))
    XCTAssertNil(store.advanceStationaryBrush(time: 100)); XCTAssertNil(store.brushGesture)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testFallbackPencilMixerEraserAndMaskPreviewsExcludeReleaseTail() async throws {
    for tool in [EditorTool.brush, .pencil, .mixerBrush, .eraser] {
      var doc = try CraftDocument(width: 96, height: 64)
      doc.layers[0].content = .raster(try Surface(width: 96, height: 64, fill: Pixel(0.5, 0.4, 0.3)))
      let store = EditorStore(document: doc, brushes: BrushLibrary())
      defer { store.cancelBrush(); store.renderTask?.cancel() }
      store.tool = tool; store.brush.size = 5; store.brushOptions.smoothing.amount = 0.9
      store.brushOptions.symmetry.mode = .vertical; store.brushOptions.symmetry.center = .init(48, 32)
      store.beginBrush(.init(x: 15, y: 25, time: 0), zoom: 1); store.extendBrush(.init(x: 80, y: 25, time: 1))
      let gesture = try XCTUnwrap(store.brushGesture)
      XCTAssertTrue(gesture.needsStationarySample); XCTAssertNil(store.interactiveBrushPreview)
      var held = doc
      if var request = gesture.paintingRequest {
        request.brush.settings!.smoothing.catchUpOnEnd = false
        try Command.painting(PaintingPreparation.prepare(request, in: doc)).apply(to: &held)
      } else {
        var brush = gesture.brush; brush.settings!.smoothing.catchUpOnEnd = false
        try Command.stroke(gesture.layerID, gesture.points, brush).apply(to: &held)
      }
      await store.brushPreviewTask?.value; await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertTrue(store.surface == (try Renderer.composite(held)), tool.rawValue)
      XCTAssertNotNil(store.advanceStationaryBrush(time: 100))
      store.finishBrush(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1)
    }
    var doc = try CraftDocument(width: 96, height: 64); doc.layers[0].mask = try Surface(width: 96, height: 64, fill: .white)
    let store = EditorStore(document: doc, brushes: BrushLibrary()); defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.selectMask(doc.layers[0].id); store.brush.color = .black; store.brush.size = 6
    store.brushOptions.smoothing.amount = 0.9
    store.beginBrush(.init(x: 10, y: 20, time: 0), zoom: 1); store.extendBrush(.init(x: 80, y: 20, time: 1))
    let gesture = try XCTUnwrap(store.brushGesture); var brush = gesture.brush; brush.settings!.smoothing.catchUpOnEnd = false
    var held = doc; try Command.maskStroke(gesture.layerID, gesture.points, brush).apply(to: &held)
    await store.brushPreviewTask?.value; await store.renderTask?.value
    XCTAssertTrue(store.surface == (try Renderer.composite(held))); XCTAssertNotNil(store.advanceStationaryBrush(time: 100))
  }

  @MainActor func testClockStopsOnToolChangeDetachDeactivationAndEscape() async throws {
    for ending in 0..<4 {
      let store = EditorStore(document: try CraftDocument(width: 64, height: 48), brushes: BrushLibrary())
      store.tool = .brush; store.brushOptions.smoothing.amount = 0.9
      let canvas = CraftCanvas(store: store)
      let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = canvas; window.makeKeyAndOrderFront(nil)
      defer { store.cancelBrush(); store.renderTask?.cancel(); window.contentView = nil; window.close() }
      store.beginBrush(.init(x: 5, y: 20, time: 0), zoom: 1); store.extendBrush(.init(x: 55, y: 20, time: 1))
      canvas.synchronizeBrushClock(); XCTAssertNotNil(canvas.airbrushTimer)
      switch ending {
      case 0: store.tool = .move; canvas.synchronizeTool()
      case 1: window.contentView = nil
      case 2: NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
      default:
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        canvas.keyDown(with: escape)
      }
      XCTAssertNil(canvas.airbrushTimer); XCTAssertNil(store.brushGesture); XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testAirbrushStillBuildsUpAndSettledSmoothingRestartsOnMovement() async throws {
    let doc = try CraftDocument(width: 64, height: 48)
    let store = EditorStore(document: doc, brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.size = 8; store.brush.color = .black
    store.brushOptions.buildUp = true; store.brushOptions.flow = 0.1
    store.beginBrush(.init(x: 20, y: 20, time: 0), zoom: 1)
    await store.brushPreviewTask?.value; await store.renderTask?.value
    let initial = store.surface
    XCTAssertNotNil(store.advanceStationaryBrush(time: 500))
    await store.brushPreviewTask?.value; await store.renderTask?.value
    XCTAssertFalse(store.surface == initial); XCTAssertTrue(store.document == doc)
    store.cancelBrush(); store.brushOptions.buildUp = false; store.brushOptions.smoothing.amount = 0.8
    store.beginBrush(.init(x: 5, y: 20, time: 0), zoom: 1); store.extendBrush(.init(x: 50, y: 20, time: 1))
    for i in 1...120 { store.advanceStationaryBrush(time: Double(i) * 1000 / 60) }
    XCTAssertFalse(try XCTUnwrap(store.brushGesture).needsStationarySample)
    // A long elapsed gap can itself consume catch-up in the existing kernel.
    // Move immediately after the last generated sample to exercise clock restart.
    let nextTime = try XCTUnwrap(store.brushGesture?.points.last?.time) + 1
    store.extendBrush(.init(x: 20, y: 35, time: nextTime))
    XCTAssertTrue(try XCTUnwrap(store.brushGesture).needsStationarySample)
    XCTAssertNotNil(store.advanceStationaryBrush(time: nextTime + 17))
  }
}
