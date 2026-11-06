import AppKit
import QuartzCore
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SelectionAntsTests: XCTestCase {
  @MainActor func fixture(_ depth: PixelDepth = .u8) async throws -> (EditorStore, CraftCanvas, NSWindow) {
    _ = NSApplication.shared; _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    var document = try CraftDocument(width: 80, height: 50, depth: depth)
    var raster = try Surface(width: 80, height: 50, depth: depth, fill: .white)
    for y in 8..<28 { for x in 10..<40 { raster.setPixel(x: x, y: y, Pixel(1, 0, 0)) } }
    document.layers[0].content = .raster(raster)
    document.setCoverageSelection(try SelectionMask.make(.rectangle(.init(x: 10, y: 8, width: 30, height: 20)), width: 80, height: 50, antiAlias: false))
    let store = EditorStore(document: document, actions: ActionLibrary())
    let canvas = CraftCanvas(store: store); canvas.frame = .init(x: 0, y: 0, width: 400, height: 250)
    let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = canvas
    store.updateViewport(size: canvas.bounds.size, backingScale: 1); store.setZoom(2, center: true)
    await store.renderTask?.value; canvas.synchronizeSelectionAnts()
    return (store, canvas, window)
  }
  @MainActor func close(_ store: EditorStore, _ canvas: CraftCanvas, _ window: NSWindow) {
    store.renderTask?.cancel(); store.geometryTask?.cancel()
    window.contentView = nil; window.close()
  }
  @MainActor func testCoreAnimationRepeatsCachedScreenSpaceStrokesWithoutCanvasRedrawOrDocumentMutation() async throws {
    let (store, canvas, window) = try await fixture(); defer { close(store, canvas, window) }
    let overlay = try XCTUnwrap(canvas.selectionAnts), source = store.document
    let bytes = try NativeArchive.encodeChunked(source, minimumVersion: 86)
    let image = store.image, path = store.selectionPath, generation = store.sessionGeneration, status = store.status
    var dirty = 0; store.onChange = { _ in dirty += 1 }
    overlay.synchronize(environment: .init())
    let stroke = overlay.committed
    XCTAssertTrue(stroke.isAnimating); XCTAssertFalse(stroke.layer.isHidden)
    let animation = try XCTUnwrap(stroke.black.animation(forKey: SelectionAntsStroke.animationKey) as? CABasicAnimation)
    XCTAssertEqual(animation.keyPath, "lineDashPhase"); XCTAssertEqual(animation.duration, 0.8)
    XCTAssertEqual(animation.repeatCount, .infinity)
    let from = try XCTUnwrap(animation.fromValue as? NSNumber).doubleValue
    let to = try XCTUnwrap(animation.toValue as? NSNumber).doubleValue
    XCTAssertEqual(to, from + 8)
    XCTAssertEqual(stroke.black.lineDashPattern, [4, 4]); XCTAssertEqual(stroke.black.lineWidth, 1)
    let updates = stroke.pathUpdates
    canvas.needsDisplay = false
    for _ in 0..<500 { overlay.synchronize(environment: .init()) }
    XCTAssertEqual(stroke.pathUpdates, updates); XCTAssertFalse(canvas.needsDisplay)
    XCTAssertTrue(store.image === image); XCTAssertTrue(store.selectionPath === path)
    XCTAssertEqual(store.sessionGeneration, generation); XCTAssertEqual(store.status, status)
    XCTAssertEqual(store.document, source); XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertEqual(dirty, 0)
    XCTAssertEqual(try NativeArchive.encodeChunked(store.document, minimumVersion: 86), bytes)
    XCTAssertTrue(canvas.hitTest(.init(x: 40, y: 40)) === canvas)
  }
  @MainActor func testLifecyclePolicyStopsAndRestoresWithoutLeakingAnimationOnDetach() async throws {
    let (store, canvas, window) = try await fixture(); defer { close(store, canvas, window) }
    let overlay = try XCTUnwrap(canvas.selectionAnts)
    var variants = [SelectionAntsEnvironment]()
    var e = SelectionAntsEnvironment(); e.attached = false; variants.append(e)
    e = .init(); e.applicationActive = false; variants.append(e)
    e = .init(); e.keyWindow = false; variants.append(e)
    e = .init(); e.windowVisible = false; variants.append(e)
    e = .init(); e.unoccluded = false; variants.append(e)
    e = .init(); e.minimized = true; variants.append(e)
    e = .init(); e.hidden = true; variants.append(e)
    e = .init(); e.reduceMotion = true; variants.append(e)
    for environment in variants {
      overlay.synchronize(environment: .init()); XCTAssertTrue(overlay.committed.isAnimating)
      overlay.synchronize(environment: environment); XCTAssertFalse(overlay.committed.isAnimating)
      XCTAssertFalse(overlay.committed.layer.isHidden, "Paused playback retains the selection border.")
    }
    overlay.synchronize(environment: .init()); canvas.isHidden = true
    XCTAssertFalse(overlay.committed.isAnimating)
    canvas.isHidden = false; overlay.synchronize(environment: .init())
    window.contentView = nil
    XCTAssertFalse(overlay.committed.isAnimating); XCTAssertFalse(overlay.preview.isAnimating)
    overlay.synchronize(); XCTAssertFalse(overlay.committed.isAnimating)
    XCTAssertNotNil(overlay.committed.black.path)
  }
  @MainActor func testExistingHoleContourMapsThroughZoomPanAndBackingWithoutChangingCoverageAtAnyDepth() async throws {
    for depth in PixelDepth.allCases {
      let (store, canvas, window) = try await fixture(depth); defer { close(store, canvas, window) }
      let coverage = try SelectionMask(width: 3, height: 3, bytes: [255,255,255,255,0,255,255,255,127])
      let contour = try SelectionOutline.path(coverage).path
      var plane = [UInt8](repeating: 0, count: 80 * 50)
      let samples: [UInt8] = [255,255,255,255,0,255,255,255,127]
      for y in 0..<3 { for x in 0..<3 { plane[y * 80 + x] = samples[y * 3 + x] } }
      var original = store.document
      original.setCoverageSelection(try SelectionMask(width: 80, height: 50, bytes: plane))
      store.session = EditorSession(document: original)
      for zoom in [0.5, 1.0, 4.0] {
        store.setZoom(zoom, center: true); store.pan = .init(width: 7, height: -5)
        await store.renderTask?.value
        let overlay = try XCTUnwrap(canvas.selectionAnts); overlay.synchronize(environment: .init())
        let mapped = try XCTUnwrap(overlay.committed.black.path)
        XCTAssertEqual(mapped.boundingBoxOfPath.origin.x, canvas.imageRect.minX, accuracy: 0.000001)
        XCTAssertEqual(mapped.boundingBoxOfPath.origin.y, canvas.imageRect.minY, accuracy: 0.000001)
        XCTAssertEqual(mapped.boundingBoxOfPath.width, 3 * canvas.scale, accuracy: 0.000001)
        var a = 0, b = 0
        contour.applyWithBlock { if $0.pointee.type == .addLineToPoint { a += 1 } }
        mapped.applyWithBlock { if $0.pointee.type == .addLineToPoint { b += 1 } }
        XCTAssertEqual(a, b); XCTAssertGreaterThan(a, 4)
        XCTAssertEqual(overlay.committed.black.lineWidth, 1)
      }
      XCTAssertEqual(store.document, original)
    }
  }
  @MainActor func testCreationPreviewsUseSeparateImageClippedLayersAndEndWithoutStaleGeometry() async throws {
    let (store, canvas, window) = try await fixture(); defer { close(store, canvas, window) }
    let source = store.document, overlay = try XCTUnwrap(canvas.selectionAnts)
    for tool in [EditorTool.marquee, .ellipticalMarquee, .rowMarquee, .columnMarquee, .objectSelection] {
      store.tool = tool; canvas.start = .init(x: 12, y: 10); canvas.end = .init(x: 30, y: 25)
      overlay.synchronize(environment: .init())
      XCTAssertTrue(overlay.preview.isAnimating); XCTAssertFalse(overlay.preview.layer.isHidden)
      XCTAssertEqual(overlay.preview.clip.path?.boundingBoxOfPath, canvas.visibleRect.intersection(canvas.imageRect))
      XCTAssertNotNil(overlay.committed.black.path)
      canvas.start = nil; canvas.end = nil; overlay.synchronize(environment: .init())
      XCTAssertTrue(overlay.preview.layer.isHidden); XCTAssertFalse(overlay.preview.isAnimating)
    }
    store.tool = .selectionBrush; overlay.synchronize(environment: .init())
    XCTAssertTrue(overlay.committed.layer.isHidden); XCTAssertFalse(overlay.committed.isAnimating)
    store.tool = .marquee; canvas.start = .init(x: 12, y: 10); canvas.end = .init(x: 30, y: 25); canvas.panningGesture = true
    overlay.synchronize(environment: .init()); XCTAssertTrue(overlay.preview.layer.isHidden)
    XCTAssertEqual(store.document, source); XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testDeselectUndoAndTransformPreviewSwitchOnlyTheirExistingSelectionGeometry() async throws {
    let (store, canvas, window) = try await fixture(); defer { close(store, canvas, window) }
    let source = store.document, overlay = try XCTUnwrap(canvas.selectionAnts)
    store.performGeometry(.selection(nil)); await store.geometryTask?.value; await store.renderTask?.value
    overlay.synchronize(environment: .init()); XCTAssertTrue(overlay.committed.layer.isHidden)
    let undone = await store.requestHistory(redo: false).value; XCTAssertTrue(undone); await store.renderTask?.value
    overlay.synchronize(environment: .init()); XCTAssertFalse(overlay.committed.layer.isHidden)
    XCTAssertEqual(store.document, source)
    store.beginSelectionTransform(); await store.selectionTransform?.task?.value
    overlay.synchronize(environment: .init()); XCTAssertNotNil(overlay.committed.black.path)
    store.cancelTransform(); overlay.synchronize(environment: .init())
    XCTAssertEqual(store.document, source)
  }
  @MainActor func testMaximumSparseCanvasBorderDoesNotAllocateFullCanvasOrReduceSourceExtent() throws {
    let source = try CraftDocument(width: 300000, height: 300000)
    let store = EditorStore(document: source, actions: ActionLibrary()); store.renderTask?.cancel()
    defer { store.renderTask?.cancel() }
    var selected = source; selected.selection = .init(x: 1, y: 1, width: 299998, height: 299998)
    store.session = EditorSession(document: selected)
    let canvas = CraftCanvas(store: store); canvas.frame = .init(x: 0, y: 0, width: 400, height: 250)
    store.setZoom(0.001, center: true)
    let overlay = try XCTUnwrap(canvas.selectionAnts)
    overlay.synchronize(environment: .init())
    XCTAssertNotNil(overlay.committed.black.path); XCTAssertEqual(overlay.committed.black.path?.boundingBoxOfPath, canvas.selectionViewRect(selected.selection!))
    XCTAssertEqual(store.document.width, 300000); XCTAssertEqual(store.document.height, 300000)
    XCTAssertEqual(store.document, selected); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertLessThanOrEqual(overlay.committed.pathUpdates, 2)
  }
  @MainActor func testAPIReportsPresentationPolicyWithoutChangingRevisionArchiveOrMenus() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); await document.store.renderTask?.value
      let source = document.store.document, revision = service.revision(document.store)
      let bytes = try NativeArchive.encodeChunked(source, minimumVersion: 86)
      let path = "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))"
      let result = try await helper.request(service, path: path)
      XCTAssertEqual(result.0.statusCode, 200)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result.1) as? [String: Any])
      let state = try XCTUnwrap(object["selectionDisplay"] as? [String: Any])
      XCTAssertEqual(state["playbackControlledByNativeWindow"] as? Bool, true)
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: state))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: SelectionAntsAPI.stateSchema))
      XCTAssertEqual(SelectionAntsAPI.capabilities["presentationOnly"] as? Bool, true)
      XCTAssertTrue((SelectionAntsAPI.capabilities["adobe"] as? String)?.contains("No published") == true)
      XCTAssertEqual(service.revision(document.store), revision); XCTAssertEqual(document.store.document, source)
      XCTAssertEqual(try NativeArchive.encodeChunked(document.store.document, minimumVersion: 86), bytes)
      XCTAssertEqual(AutomationCommand.definitions.count, 249)
    }
  }
  @MainActor func testOwnedRasterSnapshotsShowMovingDashesAndKeepInteriorClear() async throws {
    let stroke = SelectionAntsStroke()
    stroke.update(.rectangle(.init(x: 30, y: 25, width: 90, height: 60)), bounds: .init(x: 0, y: 0, width: 160, height: 110), visible: .init(x: 0, y: 0, width: 160, height: 110), backing: 1, animate: false)
    var frames = [Data]()
    for phase in [0.0, 4.0] {
      stroke.black.lineDashPhase = CGFloat(phase)
      let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 110, bitsPerComponent: 8, bytesPerRow: 640, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      stroke.layer.render(in: context)
      let data = Data(bytes: try XCTUnwrap(context.data), count: 160 * 110 * 4); frames.append(data)
      XCTAssertEqual(data[(50 * 160 + 60) * 4 + 3], 0, "Selection border must not fill its interior.")
      XCTAssertEqual(data[(5 * 160 + 5) * 4 + 3], 0)
      if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let image = try XCTUnwrap(context.makeImage()); let rep = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("selection-ants-phase-\(Int(phase)).png"))
      }
    }
    XCTAssertNotEqual(frames[0], frames[1])
    let (store, canvas, window) = try await fixture(); defer { close(store, canvas, window) }
    canvas.display()
    let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 250, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let root = try XCTUnwrap(canvas.layer)
    root.render(in: context)
    let pixels = Data(bytes: try XCTUnwrap(context.data), count: 400 * 250 * 4)
    var redBounds = [400, 250, -1, -1]
    for y in 0..<250 { for x in 0..<400 {
      let i = (y * 400 + x) * 4
      if pixels[i] > 200 && pixels[i + 1] < 80 && pixels[i + 2] < 80 {
        redBounds[0] = min(redBounds[0], x); redBounds[1] = min(redBounds[1], y)
        redBounds[2] = max(redBounds[2], x); redBounds[3] = max(redBounds[3], y)
      }
    } }
    XCTAssertGreaterThan(redBounds[2], redBounds[0], "Owned red selection artwork must be visible.")
    var darkAtRedTop = 0
    if redBounds[2] > redBounds[0] {
      for y in max(0, redBounds[1] - 2)...min(249, redBounds[1] + 2) {
        for x in (redBounds[0] + 4)..<(redBounds[2] - 3) {
          let i = (y * 400 + x) * 4
          if pixels[i] < 200 && pixels[i + 1] < 200 && pixels[i + 2] < 200 { darkAtRedTop += 1 }
        }
      }
    }
    XCTAssertGreaterThan(darkAtRedTop, 0, "The native border must follow the selected artwork, including its vertical orientation.")
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let geometry: [String: Any] = ["redBounds": redBounds, "darkPixelsAtRedTop": darkAtRedTop,
        "rootGeometryFlipped": root.isGeometryFlipped, "viewFlipped": canvas.isFlipped,
        "borderGeometryFlipped": canvas.selectionAnts?.committed.layer.isGeometryFlipped ?? false]
      try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]).write(to: URL(fileURLWithPath: folder).appendingPathComponent("selection-ants-native-geometry.json"))
      let image = try XCTUnwrap(context.makeImage()); let rep = NSBitmapImageRep(cgImage: image)
      try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent("selection-ants-native-canvas.png"))
    }
  }
}
