import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class ViewportTests: XCTestCase {
  @MainActor func fixture(width: Int = 100, height: Int = 50) throws -> EditorStore {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: width, height: height))
    store.renderTask?.cancel()
    return store
  }

  func testZoomStepsMatchExecutedOriginalRustFloatBits() throws {
    struct Oracle: Decodable {
      let input_bits: UInt32
      let direction: Int
      let output_bits: UInt32
    }
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "viewport-zoom-rust", withExtension: "json", subdirectory: "Fixtures"))
    let cases = try JSONDecoder().decode([Oracle].self, from: Data(contentsOf: url))
    XCTAssertEqual(cases.count, 220)
    for item in cases {
      let actual = CanvasViewport.step(
        from: Double(Float(bitPattern: item.input_bits)), inward: item.direction > 0)
      XCTAssertEqual(Float(actual).bitPattern, item.output_bits)
    }
    XCTAssertEqual(CanvasViewport.step(from: 1, inward: true), 2)
    XCTAssertEqual(CanvasViewport.step(from: 32, inward: true), 32)
  }

  @MainActor func testMenuZoomFromInitialFitMovesInRequestedDirectionAndPreservesDocument() throws {
    let app = AppDelegate()
    defer { for document in app.controller.documents { document.close() } }
    let doc = try DocumentWorkspaceTests().fixture(app.controller, name: "Viewport")
    let original = doc.store.document
    XCTAssertEqual(doc.store.effectiveZoom, 1)
    app.zoomIn()
    XCTAssertEqual(doc.store.zoom, 2)
    app.zoomOut()
    XCTAssertEqual(doc.store.zoom, 1)
    doc.store.pan = CGSize(width: 40, height: -20)
    let before = doc.store.viewport.documentPoint(at: CGPoint(x: 450, y: 350))
    app.zoomIn()
    app.actual()
    let after = doc.store.viewport.documentPoint(at: CGPoint(x: 450, y: 350))
    XCTAssertEqual(before.x, after.x, accuracy: 1e-9)
    XCTAssertEqual(before.y, after.y, accuracy: 1e-9)
    XCTAssertEqual(doc.store.document, original)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }

  @MainActor func testInitialFitResolvesOnceAndExplicitFitUsesCurrentViewport() throws {
    let store = try fixture()
    store.updateViewport(size: CGSize(width: 80, height: 60), backingScale: 1)
    XCTAssertEqual(store.zoom, 0.4, accuracy: 1e-9)
    store.updateViewport(size: CGSize(width: 240, height: 140), backingScale: 1)
    XCTAssertEqual(store.zoom, 0.4, accuracy: 1e-9)
    store.pan = CGSize(width: 20, height: -40)
    store.fit()
    XCTAssertEqual(store.zoom, 2, accuracy: 1e-9)
    XCTAssertEqual(store.pan, .zero)
    let small = try fixture(width: 8, height: 6)
    small.updateViewport(size: CGSize(width: 900, height: 700), backingScale: 2)
    XCTAssertEqual(small.zoom, 1, "Small documents start at 100%, not a huge fit enlargement")
  }

  func testActualPixelsAndDocumentCoordinatesAccountForBackingScale() {
    for backing in [1.0, 2.0] {
      let view = CanvasViewport(
        documentSize: CGSize(width: 64, height: 32),
        size: CGSize(width: 800, height: 600), backingScale: backing, zoom: 1, pan: .zero)
      XCTAssertEqual(view.imageRect.width * backing, 64)
      XCTAssertEqual(view.imageRect.height * backing, 32)
      let point = CGPoint(
        x: view.imageRect.minX + 13 / backing, y: view.imageRect.minY + 7 / backing)
      XCTAssertEqual(view.documentPoint(at: point), CGPoint(x: 13, y: 7))
    }
  }

  @MainActor func testZoomAnchorsPointerAndMenuCenterWithoutChangingHistory() throws {
    let store = try fixture()
    store.updateViewport(size: CGSize(width: 800, height: 600), backingScale: 2)
    store.pan = CGSize(width: 47, height: -19)
    let original = store.document
    for anchor in [CGPoint(x: 123, y: 234), CGPoint(x: 400, y: 300)] {
      let expected = store.viewport.documentPoint(at: anchor)
      for zoom in [0.25, 0.6667, 1, 2, 32] {
        store.setZoom(zoom, anchoredAt: anchor)
        let actual = store.viewport.documentPoint(at: anchor)
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-8)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-8)
      }
    }
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testMovingBetweenBackingScalesPreservesDocumentCenterAndZoom() throws {
    let store = try fixture()
    let size = CGSize(width: 800, height: 600)
    store.updateViewport(size: size, backingScale: 1)
    store.setZoom(2)
    store.pan = CGSize(width: 120, height: -38)
    let center = CGPoint(x: 400, y: 300)
    let expected = store.viewport.documentPoint(at: center)
    store.updateViewport(size: size, backingScale: 2)
    XCTAssertEqual(store.zoom, 2)
    XCTAssertEqual(store.pan, CGSize(width: 60, height: -19))
    XCTAssertEqual(store.viewport.documentPoint(at: center), expected)
    store.updateViewport(size: size, backingScale: 1)
    XCTAssertEqual(store.pan, CGSize(width: 120, height: -38))
    XCTAssertEqual(store.viewport.documentPoint(at: center), expected)
  }

  @MainActor func testDetachedCanvasCannotOverwriteCurrentDocumentViewport() throws {
    let store = try fixture()
    store.updateViewport(size: CGSize(width: 800, height: 600), backingScale: 2)
    store.pan = CGSize(width: 20, height: -10)
    let detached = CraftCanvas(store: store)
    detached.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
    detached.queueViewportUpdate()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    XCTAssertEqual(store.viewportSize, CGSize(width: 800, height: 600))
    XCTAssertEqual(store.viewportBackingScale, 2)
    XCTAssertEqual(store.pan, CGSize(width: 20, height: -10))
  }

  func testPercentageParsingAndDisplayRejectInvalidInput() throws {
    let en = Locale(identifier: "en_US")
    let fr = Locale(identifier: "fr_FR")
    XCTAssertEqual(
      try XCTUnwrap(CanvasViewport.parsePercentage(" 66.67% ", locale: en)), 0.6667, accuracy: 1e-12
    )
    XCTAssertEqual(CanvasViewport.parsePercentage("125,5%", locale: fr), 1.255)
    XCTAssertEqual(CanvasViewport.parsePercentage("3200%", locale: en), 32)
    for value in ["", "0", "-50", "NaN", "inf", "3201", "50junk", "50%%", "1,200"] {
      XCTAssertNil(CanvasViewport.parsePercentage(value, locale: en), value)
    }
    XCTAssertEqual(CanvasViewport.parsePercentage(CanvasViewport.percentage(32)), 32)
    XCTAssertEqual(CanvasViewport.bounded(.nan), 1)
    XCTAssertEqual(CanvasViewport.bounded(-1), 0.01)
  }

  @MainActor func testNativePercentageCommitCancelAndDocumentReplacementKeepCorrectTarget() throws {
    let a = try fixture()
    let b = try fixture()
    a.setZoom(1)
    b.setZoom(1)
    var activated = 0
    let coordinator = ZoomPercentageField.Coordinator(
      ZoomPercentageField(store: a) {
        activated += 1
        return true
      })
    let field = NSTextField()
    let editor = NSTextView()
    XCTAssertTrue(coordinator.control(field, textShouldBeginEditing: editor))
    XCTAssertEqual(activated, 1)
    field.stringValue = "50%"
    coordinator.submit(field)
    XCTAssertEqual(a.zoom, 0.5)
    field.stringValue = "nonsense"
    coordinator.submit(field)
    XCTAssertEqual(a.zoom, 0.5)
    field.stringValue = "200%"
    XCTAssertTrue(
      coordinator.control(
        field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    coordinator.submit(field)
    XCTAssertEqual(a.zoom, 0.5)
    XCTAssertTrue(coordinator.control(field, textShouldBeginEditing: editor))
    coordinator.parent = ZoomPercentageField(store: b)
    field.stringValue = "200%"
    coordinator.submit(field)
    XCTAssertEqual(a.zoom, 0.5)
    XCTAssertEqual(b.zoom, 1)
    XCTAssertTrue(a.session.undoStack.isEmpty && b.session.undoStack.isEmpty)
  }

  @MainActor func testScrollerUsesLogicalCanvasScaleAndHonorsActivationGuard() throws {
    let store = try fixture()
    store.updateViewport(size: CGSize(width: 800, height: 600), backingScale: 2)
    store.setZoom(1)
    var allowed = false
    var calls = 0
    let parent = CanvasScroller(store: store, vertical: false) {
      calls += 1
      return allowed
    }
    XCTAssertEqual(parent.range, 850)
    let coordinator = CanvasScroller.Coordinator(parent)
    let scroller = NSScroller()
    scroller.doubleValue = 0
    coordinator.changed(scroller)
    XCTAssertEqual(store.pan, .zero)
    allowed = true
    coordinator.changed(scroller)
    XCTAssertEqual(store.pan.width, 425)
    XCTAssertEqual(calls, 2)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testCanvasScrollActivatesTargetBeforeNavigationAndAnchorsOptionZoom() throws {
    let store = try fixture()
    let canvas = CraftCanvas(store: store)
    canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    store.setZoom(1)
    var allowed = false
    var calls = 0
    canvas.activateDocument = {
      calls += 1
      return allowed
    }
    // Build an event value and deliver it only to this test-owned view; nothing is posted to the OS.
    let cg = try XCTUnwrap(
      CGEvent(
        scrollWheelEvent2Source: nil, units: .pixel,
        wheelCount: 2, wheel1: 20, wheel2: 10, wheel3: 0))
    let scroll = try XCTUnwrap(NSEvent(cgEvent: cg))
    canvas.scrollWheel(with: scroll)
    XCTAssertEqual(store.pan, .zero)
    allowed = true
    canvas.scrollWheel(with: scroll)
    XCTAssertEqual(store.pan.width, -scroll.scrollingDeltaX)
    XCTAssertEqual(store.pan.height, -scroll.scrollingDeltaY)
    cg.flags = .maskAlternate
    let zoom = try XCTUnwrap(NSEvent(cgEvent: cg))
    let point = canvas.convert(zoom.locationInWindow, from: nil)
    let expected = canvas.viewport.documentPoint(at: point)
    canvas.scrollWheel(with: zoom)
    let actual = canvas.viewport.documentPoint(at: point)
    XCTAssertEqual(actual.x, expected.x, accuracy: 1e-8)
    XCTAssertEqual(actual.y, expected.y, accuracy: 1e-8)
    XCTAssertEqual(calls, 3)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
