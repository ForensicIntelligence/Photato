import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class LayerRevealTests: XCTestCase {
  @MainActor func fixture(tall: Bool = false) throws -> CraftNSDocument {
    let document = try GroupDisclosureWorkflowTests().fixture()
    var model = document.store.document
    if tall {
      for index in 0..<30 {
        model.layers.append(Layer(name: "Stack \(index)", content: .fill(.clear)))
      }
    }
    document.store.session = EditorSession(document: model)
    document.store.collapseAllLayerGroups()
    document.store.workspaceLibrary.resizeProperties(to: 160)
    return document
  }

  @MainActor func testFirstAppearanceAndManualCollapseRemainUnchanged() throws {
    let document = try fixture()
    defer { document.close() }
    let store = document.store
    let tracker = LayerRevealTracker()
    let before = store.document
    XCTAssertNil(tracker.track(store))
    XCTAssertEqual(store.document, before)
    _ = tracker.appear(store)
    XCTAssertNil(tracker.track(store))
    store.select(before.layers[0].id)
    _ = tracker.track(store)
    store.select(before.layers[1].id)
    XCTAssertNotNil(tracker.track(store))
    store.collapseAllLayerGroups()
    XCTAssertNil(tracker.track(store))
    XCTAssertEqual(store.document, before)
    tracker.end()
    XCTAssertNil(tracker.track(store))
    XCTAssertEqual(store.document, before)
  }

  @MainActor func testNestedLockedAncestorRevealPreservesHistoryDirtyStateAndPixels() throws {
    let document = try fixture()
    defer { document.close() }
    let store = document.store
    let child = store.document.layers[1].id
    let outer = store.document.layers[3].id
    store.perform(.lock(outer, true))
    store.perform(.opacity(store.document.layers[0].id, 0.5))
    store.undo()
    document.updateChangeCount(.changeCleared)
    store.select(store.document.layers[0].id)
    let tracker = LayerRevealTracker()
    _ = tracker.appear(store)
    let undo = store.session.undoStack.map(\.document)
    let redo = store.session.redoStack.map(\.document)
    let pixels = try Renderer.composite(store.document)
    let revision = store.revision
    store.select(child)
    let request = try XCTUnwrap(tracker.track(store))
    XCTAssertTrue(store.document.layers[2].group!.expanded)
    XCTAssertTrue(store.document.layers[3].group!.expanded)
    XCTAssertFalse(store.document.layers[4].group!.expanded)
    XCTAssertTrue(store.document.layers[3].locked)
    XCTAssertTrue(
      tracker.consume(request, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    XCTAssertEqual(store.selectedLayerIDs, [child])
    XCTAssertEqual(store.session.undoStack.map(\.document), undo)
    XCTAssertEqual(store.session.redoStack.map(\.document), redo)
    XCTAssertEqual(store.revision, revision)
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertEqual(try Renderer.composite(store.document), pixels)
  }

  @MainActor func testReadCopiedDocumentAndCloseInvalidatePendingReveal() throws {
    let document = try fixture()
    defer { document.close() }
    let store = document.store
    let saved = try document.data(ofType: CraftNSDocument.nativeType)
    let tracker = LayerRevealTracker()
    store.select(store.document.layers[0].id)
    _ = tracker.appear(store)
    store.select(store.document.layers[1].id)
    let request = try XCTUnwrap(tracker.track(store))
    try document.read(from: saved, ofType: CraftNSDocument.nativeType)
    XCTAssertFalse(
      tracker.consume(request, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    XCTAssertNil(tracker.track(store))
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    let copy = CraftNSDocument(model: store.document)
    defer { copy.close() }
    copy.store.select(copy.store.document.layers[0].id)
    XCTAssertNil(tracker.track(copy.store))
    copy.store.select(copy.store.document.layers[1].id)
    let copiedRequest = try XCTUnwrap(tracker.track(copy.store))
    XCTAssertFalse(
      tracker.consume(copiedRequest, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    _ = tracker.appear(store)
    store.select(store.document.layers[0].id)
    let closing = try XCTUnwrap(tracker.track(store))
    document.close()
    XCTAssertFalse(
      tracker.consume(closing, store: store, visibleIDs: store.layersInPanel().map(\.id)))
  }

  @MainActor func testFilteredStaleModalAndDisappearedRequestsDoNotScroll() throws {
    let document = try fixture()
    defer { document.close() }
    let store = document.store
    let tracker = LayerRevealTracker()
    _ = tracker.appear(store)
    store.select(store.document.layers[0].id)
    let filtered = try XCTUnwrap(tracker.track(store))
    XCTAssertFalse(tracker.consume(filtered, store: store, visibleIDs: []))
    store.select(store.document.layers[1].id)
    let old = try XCTUnwrap(tracker.track(store))
    store.select(store.document.layers[4].id)
    let current = try XCTUnwrap(tracker.track(store))
    XCTAssertFalse(tracker.consume(old, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    XCTAssertTrue(
      tracker.consume(current, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    store.select(store.document.layers[0].id)
    let gone = try XCTUnwrap(tracker.track(store))
    tracker.end()
    XCTAssertFalse(tracker.consume(gone, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    _ = tracker.appear(store)
    store.select(store.document.layers[1].id)
    store.showAI = true
    XCTAssertNil(tracker.track(store))
    store.showAI = false
    XCTAssertNil(tracker.track(store), "Closing a modal does not create a new selection")
  }

  @MainActor func testHistorySelectionUsesSameRevealWithoutAnotherUndoEntry() throws {
    let document = try fixture()
    defer { document.close() }
    let store = document.store
    let child = store.document.layers[1].id
    store.perform(.opacity(child, 0.6))
    store.select(store.document.layers[0].id)
    let tracker = LayerRevealTracker()
    _ = tracker.appear(store)
    store.undo()
    XCTAssertEqual(store.document.activeLayerID, child)
    XCTAssertEqual(try XCTUnwrap(tracker.track(store)).layerID, child)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(store.session.redoStack.count, 1)
    XCTAssertTrue(store.document.layers[3].group!.expanded)
    store.redo()
    XCTAssertEqual(try XCTUnwrap(tracker.track(store)).layerID, store.document.layers[0].id)
    XCTAssertNil(tracker.track(store), "Unchanged active layer must not force disclosure")
  }

  @MainActor func testRenameRequestRespectsCancellationAndOneTimeConsumption() throws {
    let document = try fixture()
    defer { document.close() }
    let store = document.store
    let tracker = LayerRevealTracker()
    _ = tracker.appear(store)
    store.beginLayerName(store.document.layers[1].id)
    let request = try XCTUnwrap(tracker.rename(store))
    XCTAssertTrue(
      tracker.consume(request, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    XCTAssertFalse(
      tracker.consume(request, store: store, visibleIDs: store.layersInPanel().map(\.id)))
    let cancelled = try XCTUnwrap(tracker.rename(store))
    store.finishLayerName(cancel: true)
    XCTAssertFalse(tracker.consume(cancelled, store: store, visibleIDs: [cancelled.layerID]))
    XCTAssertNil(tracker.rename(store))
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }
  @MainActor func settle(_ window: NSWindow) async throws {
    try await Task.sleep(for: .milliseconds(180))
    window.layoutIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
  }
  @MainActor func host(_ store: EditorStore) async throws -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: WorkspaceView(store: store))
    try await settle(window)
    return window
  }
  @MainActor func eye(_ id: UUID, in window: NSWindow) -> LayerEyeButton? {
    descendants(window.contentView!).compactMap { $0 as? LayerEyeButton }.first { $0.layerID == id }
  }
  @MainActor func capture(_ window: NSWindow, named name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else {
      return
    }
    let view = try XCTUnwrap(window.contentView)
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let url = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try XCTUnwrap(rep.representation(using: .png, properties: [:]))
      .write(to: url.appendingPathComponent(name + ".png"))
  }
  @MainActor func assertVisible(
    _ button: LayerEyeButton, file: StaticString = #filePath, line: UInt = #line
  ) {
    let visible = button.visibleRect.intersection(button.bounds)
    XCTAssertEqual(visible.height, button.bounds.height, accuracy: 0.5, file: file, line: line)
  }

  @MainActor func testHostedRevealOpensDeepGroupsAndScrollsOnlyWhenNeeded() async throws {
    let document = try fixture(tall: true)
    let store = document.store
    store.select(store.document.layers.last!.id)
    let window = try await host(store)
    defer {
      window.close()
      document.close()
    }
    let top = store.document.layers.last!.id
    let below = store.document.layers[store.document.layers.count - 2].id
    let child = store.document.layers[1].id
    let topButton = try XCTUnwrap(eye(top, in: window))
    let scroll = try XCTUnwrap(topButton.enclosingScrollView)
    let initial = scroll.contentView.bounds.origin
    assertVisible(topButton)
    try capture(window, named: "layer-reveal-before")
    assertVisible(try XCTUnwrap(eye(below, in: window)))
    store.select(below)
    try await settle(window)
    XCTAssertEqual(
      scroll.contentView.bounds.origin, initial, "Visible selection must not center the row")
    store.select(child)
    try await settle(window)
    XCTAssertTrue(store.document.layers[2].group!.expanded)
    XCTAssertTrue(store.document.layers[3].group!.expanded)
    assertVisible(try XCTUnwrap(eye(child, in: window)))
    try capture(window, named: "layer-reveal-after")
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, initial.y + 100)
    store.select(top)
    try await settle(window)
    assertVisible(try XCTUnwrap(eye(top, in: window)))
    XCTAssertLessThanOrEqual(scroll.contentView.bounds.minY, initial.y + 3)
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testHostedPartialRowUsesNearestEdgeWithoutCentering() async throws {
    let document = try fixture(tall: true)
    let store = document.store
    let top = store.document.layers.last!.id
    let below = store.document.layers[store.document.layers.count - 2].id
    store.select(top)
    let window = try await host(store)
    defer {
      window.close()
      document.close()
    }
    let button = try XCTUnwrap(eye(below, in: window))
    let scroll = try XCTUnwrap(button.enclosingScrollView)
    let content = try XCTUnwrap(scroll.documentView)
    let topButton = try XCTUnwrap(eye(top, in: window))
    let first = topButton.convert(topButton.bounds, to: content)
    let second = button.convert(button.bounds, to: content)
    // Consecutive equal-height rows have a one-point LazyVStack gap. The eye
    // is centered within the full row, including its thumbnail and padding.
    let rowHeight = second.minY - first.minY - 1
    let rowTop = second.minY - (rowHeight - button.bounds.height) / 2
    scroll.contentView.scroll(to: NSPoint(x: 0, y: rowTop + 10))
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(window)
    XCTAssertLessThan(button.visibleRect.intersection(button.bounds).height, button.bounds.height)
    store.select(below)
    try await settle(window)
    assertVisible(try XCTUnwrap(eye(below, in: window)))
    XCTAssertEqual(scroll.contentView.bounds.minY, rowTop, accuracy: 0.5)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testHostedInitialCollapseManualScrollAndRenameNavigation() async throws {
    let document = try fixture(tall: true)
    let store = document.store
    let child = store.document.layers[1].id
    let window = try await host(store)
    defer {
      window.close()
      document.close()
    }
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    let top = try XCTUnwrap(eye(store.document.layers.last!.id, in: window))
    assertVisible(top)
    let scroll = try XCTUnwrap(top.enclosingScrollView)
    let origin = scroll.contentView.bounds.origin
    store.select(store.document.layers.last!.id)
    try await settle(window)
    store.select(child)
    try await settle(window)
    assertVisible(try XCTUnwrap(eye(child, in: window)))
    scroll.contentView.scroll(to: origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    try await settle(window)
    XCTAssertEqual(scroll.contentView.bounds.origin, origin)
    store.collapseAllLayerGroups()
    try await settle(window)
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    store.beginLayerName(child)
    try await settle(window)
    assertVisible(try XCTUnwrap(eye(child, in: window)))
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    store.finishLayerName(cancel: true)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testHostedReopeningRevealsSelectionMadeWhilePanelWasHidden() async throws {
    let document = try fixture(tall: true)
    let store = document.store
    store.select(store.document.layers.last!.id)
    let window = try await host(store)
    defer {
      window.close()
      document.close()
    }
    store.layersTab = .channels
    try await settle(window)
    let child = store.document.layers[1].id
    store.select(child)
    try await settle(window)
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    store.layersTab = .layers
    try await settle(window)
    XCTAssertTrue(store.document.layers[3].group!.expanded)
    assertVisible(try XCTUnwrap(eye(child, in: window)))
    store.collapseAllLayerGroups()
    store.layersTab = .channels
    try await settle(window)
    store.layersTab = .layers
    try await settle(window)
    XCTAssertFalse(
      store.document.layers[3].group!.expanded, "Unchanged selection respects manual collapse")
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testHostedRenameReopensHiddenPanelAndExposesExistingActiveRow() async throws {
    let document = try fixture(tall: true)
    let store = document.store
    let child = store.document.layers[1].id
    let window = try await host(store)
    defer {
      window.close()
      document.close()
    }
    store.layersTab = .channels
    try await settle(window)
    store.beginLayerName(child)
    try await settle(window)
    XCTAssertEqual(store.layersTab, .layers)
    assertVisible(try XCTUnwrap(eye(child, in: window)))
    let field = descendants(window.contentView!).compactMap { $0 as? LayerNameField.NameField }
      .first { $0.draftID == store.layerNameDraft?.id }
    XCTAssertNotNil(field)
    store.finishLayerName(cancel: true)
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    XCTAssertFalse(document.isDocumentEdited)
  }
}
