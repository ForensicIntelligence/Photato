import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest
@testable import PhotoCraft

final class WorkflowGuideTests: XCTestCase {
  @MainActor func testSuggestionsFollowLayerSelectionToolOptionsAndMaskState() throws {
    let document = try CraftDocument(width: 8, height: 6)
    let store = EditorStore(document: document)
    defer { store.renderTask?.cancel() }
    let model = WorkflowGuideModel()
    XCTAssertTrue(model.suggestions.isEmpty)
    let original = WorkflowGuideSnapshot.capture(store)
    model.update(original)
    XCTAssertEqual(model.context, .layer)
    XCTAssertLessThanOrEqual(model.suggestions.count, 4)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.duplicate))
    store.tool = .marquee
    store.selectionAntiAlias.toggle()
    model.update(.capture(store))
    XCTAssertEqual(model.context, .selection)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.select))
    XCTAssertFalse(model.suggestions.contains(WorkflowGuideContent.saveSelection))
    var selection = WorkflowGuideSnapshot.capture(store)
    selection.hasSelection = true
    model.update(selection)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.saveSelection))
    selection.hasMask = true
    selection.editingMask = true
    model.update(selection)
    XCTAssertEqual(model.context, .mask)
    XCTAssertTrue(model.suggestions.contains(WorkflowGuideContent.paintMask))
    XCTAssertFalse(model.suggestions.contains(WorkflowGuideContent.addMask))
  }

  @MainActor func testWalkthroughChecksActualChangesAndPausesForDifferentDocument() throws {
    var state = WorkflowGuideSnapshot()
    state.documentID = UUID()
    state.layerID = UUID()
    state.layerName = "Owned layer"
    state.layerCount = 3
    let model = WorkflowGuideModel()
    model.update(state)
    model.start(WorkflowGuideContent.duplicate)
    XCTAssertEqual(model.walkthrough?.index, 0)
    XCTAssertTrue(model.stepObserved)
    model.next()
    XCTAssertFalse(model.stepObserved)
    var other = state
    other.documentID = UUID()
    other.layerCount += 2
    model.update(other)
    XCTAssertFalse(model.onLessonDocument)
    model.next()
    XCTAssertEqual(model.walkthrough?.index, 1)
    XCTAssertFalse(model.stepObserved)
    model.update(state)
    state.layerCount += 1
    model.update(state)
    XCTAssertTrue(model.stepObserved)
    model.next()
    XCTAssertEqual(model.walkthrough?.index, 2)
    model.back()
    XCTAssertEqual(model.walkthrough?.index, 1)
    model.end()
    XCTAssertNil(model.walkthrough)
  }

  @MainActor func testEditorClickRoutingAndNativeDuplicateUpdateTheGuide() throws {
    _ = NSApplication.shared
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    var model = try CraftDocument(width: 24, height: 18)
    model.layers[0].name = "Training layer"
    let document = CraftNSDocument(model: model)
    let store = document.store
    let layer = try XCTUnwrap(model.activeLayerID)
    store.documentController = delegate.controller
    delegate.controller.documentWindows.activeDocument = document
    defer {
      delegate.workflowGuideWindow?.window?.close()
      delegate.controller.documentWindows.activeDocument = nil
      store.renderTask?.cancel()
    }
    delegate.toggleWorkflowGuide()
    let guide = try XCTUnwrap(delegate.workflowGuideWindow?.model)
    let marquee = try XCTUnwrap(WorkspaceCatalog.tools.first { $0.native == .marquee })
    store.chooseTool(marquee)
    XCTAssertEqual(guide.context, .selection)
    store.select(layer)
    XCTAssertEqual(guide.context, .layer)
    XCTAssertEqual(guide.caption, "Selected layer · Training layer")
    XCTAssertEqual(guide.suggestions.count, 4)
    guide.start(WorkflowGuideContent.duplicate)
    guide.next()
    XCTAssertFalse(guide.stepObserved)
    store.perform(.duplicateLayer(layer))
    XCTAssertEqual(store.document.layers.count, 2)
    let deadline = Date().addingTimeInterval(1)
    while !guide.stepObserved && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertTrue(guide.stepObserved)
  }

  @MainActor func testNativeWindowMenuToggleAndMenuEvents() throws {
    _ = NSApplication.shared
    let previousMenu = NSApp.mainMenu
    let delegate = AppDelegate(workspaces: WorkspaceLibrary())
    let document = CraftNSDocument(model: try CraftDocument(width: 24, height: 18))
    delegate.controller.documentWindows.activeDocument = document
    document.store.setZoom(0.5)
    defer {
      NSApp.mainMenu = previousMenu
      delegate.workflowGuideWindow?.window?.close()
      delegate.controller.documentWindows.activeDocument = nil
      document.store.renderTask?.cancel()
    }
    delegate.installPhotoshopMenus()
    let windowMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Window")?.submenu)
    let item = try XCTUnwrap(windowMenu.item(withTitle: "Workflow Guide"))
    XCTAssertNil(delegate.workflowGuideWindow)
    XCTAssertTrue(delegate.validateMenuItem(item))
    XCTAssertEqual(item.state, .off)
    windowMenu.performActionForItem(at: windowMenu.index(of: item))
    let guide = try XCTUnwrap(delegate.workflowGuideWindow)
    let panel = try XCTUnwrap(guide.window as? NSPanel)
    XCTAssertTrue(panel.isFloatingPanel)
    XCTAssertTrue(panel.isExcludedFromWindowsMenu)
    XCTAssertEqual(panel.title, "Workflow Guide")
    XCTAssertTrue(delegate.controller.workflowGuide === guide.model)
    let viewMenu = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "View")?.submenu)
    let action = try XCTUnwrap(viewMenu.item(withTitle: "100%"))
    viewMenu.performActionForItem(at: viewMenu.index(of: action))
    XCTAssertEqual(document.store.zoom, 1)
    XCTAssertEqual(guide.model.context, .navigation)
    XCTAssertEqual(guide.model.caption, "100%")
    panel.close()
    XCTAssertNil(delegate.controller.workflowGuide)
  }
}
