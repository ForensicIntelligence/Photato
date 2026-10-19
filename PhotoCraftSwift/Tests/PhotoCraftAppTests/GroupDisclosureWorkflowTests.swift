import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class GroupDisclosureWorkflowTests: XCTestCase {
  @MainActor func fixture() throws -> CraftNSDocument {
    // Match product startup: register the custom controller before any standalone
    // NSDocument operation can cause AppKit to create its base-class singleton.
    _ = NSApplication.shared
    _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    var model = try CraftDocument(width: 8, height: 6)
    let base = Layer(name: "Base", content: .fill(.white))
    let outer = Layer(name: "Outer", content: .group(.init()))
    var inner = Layer(name: "Inner", content: .group(.init()))
    inner.parentID = outer.id
    var child = Layer(
      name: "Deep child",
      content: .shape(.init(kind: .rectangle, width: 3, height: 2, color: .black)))
    child.parentID = inner.id
    let other = Layer(name: "Other", content: .group(.init(expanded: false)))
    model.layers = [base, child, inner, outer, other]
    model.activeLayerID = child.id
    let document = CraftNSDocument(model: model)
    document.store.renderTask?.cancel()
    document.store.renderTask = nil
    return document
  }

  @MainActor func testSingleDisclosurePreservesCleanStateSelectionHistoryAndRender() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    let before = store.document
    let outer = before.layers[3].id
    store.selectedLayerIDs = [before.layers[1].id, before.layers[2].id]
    store.surface = try Renderer.composite(before)
    store.image = try RasterIO.displayImage(XCTUnwrap(store.surface))
    let image = store.image
    let revision = store.revision
    store.toggleGroupDisclosure(outer)
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    XCTAssertTrue(store.document.layers[2].group!.expanded)
    XCTAssertEqual(store.document.activeLayerID, before.activeLayerID)
    XCTAssertEqual(store.selectedLayerIDs, [before.layers[1].id, before.layers[2].id])
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertEqual(store.revision, revision)
    XCTAssertTrue(store.image === image)
    XCTAssertNil(store.renderTask)
    XCTAssertEqual(try Renderer.composite(store.document), store.surface)
    XCTAssertEqual(store.layersInPanel().map(\.name), ["Other", "Outer", "Base"])
    store.toggleGroupDisclosure(outer)
    XCTAssertEqual(store.document, before)
  }

  @MainActor func testOptionClickUsesClickedStateForEveryLockedNestedAndHiddenGroup() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    let outer = store.document.layers[3].id
    let other = store.document.layers[4].id
    store.perform(.lock(outer, true))
    store.perform(.visibility(outer, false))
    let history = store.session.undoStack.count
    doc.updateChangeCount(.changeCleared)
    // Other is collapsed: Option-click opens all groups, including hidden locked Outer.
    store.toggleGroupDisclosure(other, modifiers: .option)
    XCTAssertTrue(store.document.layers.filter(\.isGroup).allSatisfy { $0.group!.expanded })
    store.toggleGroupDisclosure(other, modifiers: .option)
    XCTAssertTrue(store.document.layers.filter(\.isGroup).allSatisfy { !$0.group!.expanded })
    XCTAssertFalse(store.document.layers[3].visible)
    XCTAssertTrue(store.document.layers[3].locked)
    XCTAssertEqual(store.session.undoStack.count, history)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testCollapseAllPreservesRedoAndSavesPanelMetadataWithoutDirtying() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    let base = store.document.layers[0].id
    store.perform(.opacity(base, 0.5))
    store.perform(.opacity(base, 0.3))
    store.undo()
    doc.updateChangeCount(.changeCleared)
    let undo = store.session.undoStack.map(\.document)
    let redo = store.session.redoStack.map(\.document)
    XCTAssertTrue(store.canChangeGroupDisclosure())
    store.collapseAllLayerGroups()
    store.collapseAllLayerGroups()
    XCTAssertEqual(store.session.undoStack.map(\.document), undo)
    XCTAssertEqual(store.session.redoStack.map(\.document), redo)
    XCTAssertFalse(doc.isDocumentEdited)
    let saved = try NativeArchive.decode(doc.data(ofType: CraftNSDocument.nativeType))
    XCTAssertTrue(saved.layers.filter(\.isGroup).allSatisfy { !$0.group!.expanded })
    let reopened = CraftNSDocument(model: saved)
    defer { reopened.close() }
    XCTAssertFalse(reopened.isDocumentEdited)
    XCTAssertTrue(
      reopened.store.document.layers.filter(\.isGroup).allSatisfy { !$0.group!.expanded })
  }

  @MainActor func testStaleNonGroupModalAndVisibilityDraftRequestsAreRejected() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    let original = store.document
    let outer = original.layers[3].id
    for mutate: (Bool) -> Void in [
      { store.geometryBusy = $0 }, { store.confirmingLayerDeletion = $0 },
      { store.showAI = $0 }, { store.showGaps = $0 },
    ] {
      mutate(true)
      XCTAssertFalse(store.canChangeGroupDisclosure(outer))
      store.toggleGroupDisclosure(outer, modifiers: .option)
      store.collapseAllLayerGroups()
      mutate(false)
      XCTAssertEqual(store.document, original)
    }
    store.toggleGroupDisclosure(UUID(), modifiers: .option)
    store.toggleGroupDisclosure(original.layers[0].id, modifiers: .option)
    XCTAssertEqual(store.document, original)
    let token = try XCTUnwrap(store.beginLayerVisibilityDrag(outer))
    store.toggleGroupDisclosure(outer)
    store.collapseAllLayerGroups()
    XCTAssertEqual(store.layerVisibilityDraft?.id, token)
    XCTAssertEqual(store.document, original)
    store.finishLayerVisibilityDrag(token, cancel: true)
    let plain = try GroupWorkflowTests().store()
    defer { plain.renderTask?.cancel() }
    XCTAssertFalse(plain.canChangeGroupDisclosure())
    plain.collapseAllLayerGroups()
    XCTAssertTrue(plain.session.undoStack.isEmpty)
  }

  @MainActor func testInlineRenameCommitsOnceBeforeDisclosure() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    let outer = store.document.layers[3].id
    store.beginLayerName(outer)
    store.layerNameDraft?.text = "Renamed folder"
    store.toggleGroupDisclosure(outer)
    XCTAssertEqual(store.document.layers[3].name, "Renamed folder")
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    XCTAssertNil(store.layerNameDraft)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.first?.label, "Rename Layer")
    XCTAssertTrue(doc.isDocumentEdited)
  }

  @MainActor func testFiltersFindHiddenDescendantsWithoutOpeningTheirGroups() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    store.collapseAllLayerGroups()
    XCTAssertEqual(store.layersInPanel().map(\.name), ["Other", "Outer", "Base"])
    XCTAssertEqual(store.layersInPanel(search: "DEEP").map(\.name), ["Deep child"])
    XCTAssertEqual(store.layersInPanel(kind: "Shape layer").map(\.name), ["Deep child"])
    XCTAssertTrue(store.document.layers.filter(\.isGroup).allSatisfy { !$0.group!.expanded })
    let child = store.document.layers[1].id
    store.beginLayerName(child)
    XCTAssertTrue(store.layersInPanel(search: "No matching names").contains { $0.id == child })
    store.finishLayerName(cancel: true)
    XCTAssertTrue(store.layersInPanel(search: "No matching names").isEmpty)
  }

  @MainActor func testDisclosurePreservesOptionEyeRestorationSnapshot() throws {
    let doc = try fixture()
    let store = doc.store
    defer { doc.close() }
    let child = store.document.layers[1].id
    let outer = store.document.layers[3].id
    let original = LayerOrganization.visibility(in: store.document)
    store.toggleLayerVisibility(child, modifiers: .option)
    XCTAssertNotNil(store.layerVisibilityIsolation)
    let count = store.session.undoStack.count
    store.toggleGroupDisclosure(outer)
    XCTAssertNotNil(store.layerVisibilityIsolation)
    XCTAssertEqual(store.session.undoStack.count, count)
    store.toggleLayerVisibility(child, modifiers: .option)
    XCTAssertEqual(LayerOrganization.visibility(in: store.document), original)
    XCTAssertFalse(store.document.layers[3].group!.expanded)
  }

  @MainActor func event(
    _ type: NSEvent.EventType, in window: NSWindow, point: NSPoint = NSPoint(x: 7, y: 18),
    modifiers: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1))
  }

  @MainActor func testNativeDisclosureRoutesClickOptionAndAccessibilityWithoutSelecting() throws {
    let doc = try fixture()
    let store = doc.store
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer {
      window.close()
      doc.close()
    }
    let button = LayerGroupDisclosureButton()
    button.store = store
    button.layerID = store.document.layers[3].id
    button.frame = NSRect(x: 0, y: 0, width: 14, height: 36)
    window.contentView?.addSubview(button)
    let active = store.document.activeLayerID
    button.mouseDown(with: try event(.leftMouseDown, in: window))
    button.mouseUp(with: try event(.leftMouseUp, in: window))
    XCTAssertFalse(store.document.layers[3].group!.expanded)
    button.performClick(nil)
    XCTAssertTrue(store.document.layers[3].group!.expanded)
    button.mouseDown(with: try event(.leftMouseDown, in: window, modifiers: .option))
    button.mouseUp(with: try event(.leftMouseUp, in: window))
    XCTAssertTrue(store.document.layers.filter(\.isGroup).allSatisfy { !$0.group!.expanded })
    XCTAssertEqual(store.document.activeLayerID, active)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testNativeDisclosureRejectsDragCancellationStaleStateAndReboundDocument() throws {
    let doc = try fixture()
    let store = doc.store
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer {
      window.close()
      doc.close()
    }
    let button = LayerGroupDisclosureButton()
    button.store = store
    button.layerID = store.document.layers[3].id
    button.frame = NSRect(x: 0, y: 0, width: 14, height: 36)
    window.contentView?.addSubview(button)
    for cancel in [false, true] {
      button.mouseDown(with: try event(.leftMouseDown, in: window))
      if cancel {
        button.cancelOperation(nil)
      } else {
        button.mouseDragged(
          with: try event(.leftMouseDragged, in: window, point: NSPoint(x: 12, y: 18)))
      }
      button.mouseUp(with: try event(.leftMouseUp, in: window))
      XCTAssertTrue(store.document.layers[3].group!.expanded)
    }
    button.mouseDown(with: try event(.leftMouseDown, in: window))
    store.toggleGroupDisclosure(button.layerID)
    button.mouseUp(with: try event(.leftMouseUp, in: window))
    XCTAssertFalse(store.document.layers[3].group!.expanded, "A stale mouse-up cannot toggle again")
    button.mouseDown(with: try event(.leftMouseDown, in: window))
    let other = CraftNSDocument(model: store.document)
    defer { other.close() }
    XCTAssertEqual(other.store.document.id, store.document.id)
    XCTAssertNotEqual(other.store.identity, store.identity)
    button.store = other.store
    button.layerID = other.store.document.layers[3].id
    button.mouseUp(with: try event(.leftMouseUp, in: window))
    XCTAssertFalse(other.store.document.layers[3].group!.expanded)
    XCTAssertTrue(other.store.session.undoStack.isEmpty)
  }

  @MainActor func testHostedDisclosureHasNativeHitTargetAndRetainsEyeColumn() async throws {
    let doc = try fixture()
    let store = doc.store
    store.workspaceLibrary.resizeProperties(to: 150)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1380, height: 900), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer {
      window.close()
      doc.close()
    }
    let host = NSHostingView(rootView: WorkspaceView(store: store))
    host.frame = NSRect(x: 0, y: 0, width: 1380, height: 900)
    window.contentView = host
    try await Task.sleep(for: .milliseconds(200))
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let controls = descendants(host).compactMap { $0 as? LayerGroupDisclosureButton }
    XCTAssertEqual(controls.count, 3)
    var hitCount = 0
    for button in controls {
      XCTAssertEqual(button.bounds.size, NSSize(width: 14, height: 36))
      let visible = button.visibleRect.intersection(button.bounds)
      if !visible.isEmpty {
        let point = host.superview!.convert(NSPoint(x: visible.midX, y: visible.midY), from: button)
        XCTAssertTrue(host.hitTest(point) === button)
        hitCount += 1
      }
      XCTAssertNotNil(button.accessibilityValue())
    }
    XCTAssertGreaterThan(hitCount, 0)
    XCTAssertEqual(descendants(host).compactMap { $0 as? LayerEyeButton }.count, 5)
  }
}
