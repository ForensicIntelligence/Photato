import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class LayerRevealLifecycleTests: XCTestCase {
  @MainActor private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
  }

  @MainActor private final class Fixture {
    let document: CraftNSDocument
    let tracker = LayerRevealTracker()
    let eyes = LayerEyeTracking()
    let view = LayerRevealScrollView()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
    let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 700))
    let window: NSWindow
    let target: UUID

    init() throws {
      document = try LayerRevealTests().fixture(tall: true)
      let store = document.store
      target = store.document.layers.last!.id
      _ = tracker.appear(store)
      store.beginLayerName(target)
      view.request = try XCTUnwrap(tracker.rename(store))
      view.store = store
      view.tracker = tracker
      view.eyes = eyes
      eyes.revealView = view
      view.visibleIDs = store.layersInPanel().map(\.id)
      view.frame = content.bounds
      content.addSubview(view)
      scroll.documentView = content
      window = NSWindow(contentRect: scroll.frame, styleMask: [], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
    }

    func attach() { window.contentView = scroll }
    func addEye(y: CGFloat, height: CGFloat = 36) -> LayerEyeButton {
      let button = LayerEyeButton()
      button.store = document.store
      button.layerID = target
      button.tracking = eyes
      button.frame = NSRect(x: 0, y: y, width: 22, height: height)
      eyes.buttons.add(button)
      content.addSubview(button)
      return button
    }
    func close() {
      tracker.end()
      view.stopObserving()
      window.close()
      document.close()
    }
  }

  @MainActor func testPendingRevealWaitsForAttachmentAndActualRowThenLeavesManualScrollAlone()
    throws
  {
    let f = try Fixture()
    defer { f.close() }
    XCTAssertFalse(f.view.revealIfReady())
    XCTAssertNotNil(f.tracker.currentRequest)
    f.attach()
    XCTAssertFalse(f.view.revealIfReady(), "Estimated visibility cannot acknowledge an absent row")
    XCTAssertNotNil(f.tracker.currentRequest)
    let eye = f.addEye(y: 403)
    XCTAssertTrue(f.view.revealIfReady())
    XCTAssertNil(f.tracker.currentRequest)
    let row = f.scroll.contentView.convert(eye.bounds, from: eye).insetBy(dx: 0, dy: -3)
    XCTAssertEqual(f.scroll.contentView.bounds.maxY, row.maxY, accuracy: 0.5)
    f.scroll.contentView.scroll(to: .zero)
    XCTAssertFalse(f.view.revealIfReady())
    XCTAssertEqual(f.scroll.contentView.bounds.minY, 0)
    XCTAssertFalse(f.document.isDocumentEdited)
    XCTAssertTrue(f.document.store.session.undoStack.isEmpty)
  }

  @MainActor func testPendingRevealRejectsOldRowSizeAndUsesActualPositionInsteadOfEstimate() throws
  {
    let f = try Fixture()
    defer { f.close() }
    f.attach()
    f.view.rowHeight = 70
    let eye = f.addEye(y: 503)
    XCTAssertFalse(f.view.revealIfReady())
    XCTAssertNotNil(f.tracker.currentRequest)
    eye.setFrameSize(NSSize(width: 22, height: 64))
    XCTAssertTrue(f.view.revealIfReady())
    XCTAssertEqual(f.scroll.contentView.bounds.maxY, 570, accuracy: 0.5)
    XCTAssertNil(f.tracker.currentRequest)
  }

  @MainActor func testCachedRowClippedByLazyAncestorCannotAcknowledgeRequest() throws {
    let f = try Fixture()
    defer { f.close() }
    f.attach()
    let eye = f.addEye(y: 403)
    let slice = FlippedView(frame: NSRect(x: 0, y: 400, width: 200, height: 1))
    slice.clipsToBounds = true
    f.content.addSubview(slice)
    slice.addSubview(eye)
    eye.frame.origin.y = 3
    var approaches: [UUID] = []
    f.view.approach = { approaches.append($0) }
    XCTAssertFalse(f.view.revealIfReady())
    XCTAssertEqual(approaches, [f.target])
    XCTAssertNotNil(f.tracker.currentRequest)
    slice.setFrameSize(NSSize(width: 200, height: 42))
    XCTAssertTrue(f.view.revealIfReady())
    XCTAssertNil(f.tracker.currentRequest)
  }

  @MainActor func testSelectionObservationCannotEraseConcurrentRenameCancellationGuard() throws {
    let f = try Fixture()
    defer { f.close() }
    f.view.request = try XCTUnwrap(f.tracker.track(f.document.store))
    XCTAssertEqual(f.view.request?.nameDraftID, f.document.store.layerNameDraft?.id)
    f.attach()
    _ = f.addEye(y: 403)
    f.document.store.finishLayerName(cancel: true)
    XCTAssertFalse(f.view.revealIfReady())
    XCTAssertEqual(f.scroll.contentView.bounds.minY, 0)
  }

  @MainActor func testPendingRevealDoesNotScrollAfterDocumentReadOrRenameCancellation() throws {
    for read in [false, true] {
      let f = try Fixture()
      defer { f.close() }
      f.attach()
      _ = f.addEye(y: 503)
      if read {
        let saved = try f.document.data(ofType: CraftNSDocument.nativeType)
        try f.document.read(from: saved, ofType: CraftNSDocument.nativeType)
      } else {
        f.document.store.finishLayerName(cancel: true)
      }
      XCTAssertFalse(f.view.revealIfReady())
      XCTAssertEqual(f.scroll.contentView.bounds.minY, 0)
      XCTAssertNil(f.tracker.currentRequest)
    }
  }

  @MainActor func testHostedLargeListRenameSurvivesRepeatedThumbnailResizeAndDistantSelection()
    async throws
  {
    let helper = LayerRevealTests()
    let document = try helper.fixture(tall: true)
    defer { document.close() }
    let store = document.store
    var model = store.document
    for index in 0..<120 {
      model.layers.append(Layer(name: "Distant row \(index)", content: .fill(.clear)))
    }
    store.session = EditorSession(document: model)
    store.select(model.layers.last!.id)
    let window = try await helper.host(store)
    defer { window.close() }
    let targets = [model.layers[0].id, model.layers.last!.id, model.layers[17].id]
    for (index, size) in (LayerThumbnailSize.allCases + LayerThumbnailSize.allCases.reversed())
      .enumerated()
    {
      try store.workspaceLibrary.setLayerPanelOptions(.init(thumbnailSize: size))
      let target = targets[index % targets.count]
      store.beginLayerName(target)
      try await helper.settle(window)
      let eye = try XCTUnwrap(helper.eye(target, in: window))
      helper.assertVisible(eye)
      XCTAssertEqual(eye.bounds.height, size.controlHeight, accuracy: 0.5)
      let field = try XCTUnwrap(
        helper.descendants(window.contentView!).compactMap {
          $0 as? LayerNameField.NameField
        }.first { $0.draftID == store.layerNameDraft?.id })
      XCTAssertGreaterThan(field.visibleRect.intersection(field.bounds).width, 24)
      XCTAssertNotNil(field.currentEditor())
      store.finishLayerName(cancel: true)
    }
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
