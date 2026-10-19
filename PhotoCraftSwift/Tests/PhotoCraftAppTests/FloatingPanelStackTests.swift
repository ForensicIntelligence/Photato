import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class FloatingPanelStackTests: XCTestCase {
  let frame = FloatingPanelFrame(NSRect(x: 200, y: 350, width: 350, height: 320))

  @MainActor func fixture() throws -> (
    CraftDocumentController, CraftNSDocument, FloatingPanelWindows
  ) {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let doc = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 8, height: 6, name: "Stack"))
    controller.addDocument(doc)
    doc.makeWindowControllers()
    doc.store.renderTask?.cancel()
    let panels = controller.documentWindows.floatingPanels
    panels.presentsWindows = false
    panels.screenFrames = { [NSRect(x: 0, y: 0, width: 1600, height: 1600)] }
    return (controller, doc, panels)
  }
  @MainActor func cleanup(_ controller: CraftDocumentController) {
    controller.documentWindows.panelDragging.finish()
    controller.documentWindows.panelDragging.presentsBackdrops = true
    for doc in controller.documents { doc.close() }
    let panels = controller.documentWindows.floatingPanels
    panels.dismissAll()
    panels.presentsWindows = true
    panels.screenFrames = { NSScreen.screens.map(\.visibleFrame) }
  }
  @MainActor func stack(_ library: WorkspaceLibrary) throws -> String {
    XCTAssertTrue(library.floatPanels(.group("color"), frame: frame))
    XCTAssertTrue(library.stackPanels(.group("properties"), hostID: "color", before: nil))
    return try XCTUnwrap(library.panelDock.groups.first { $0.id == "color" }).floatingHostID
  }

  @MainActor func testStackRetainsSeparateGroupsStableIdentityAndIndependentTearOff() throws {
    let library = WorkspaceLibrary()
    let id = try stack(library)
    XCTAssertNotEqual(id, "color")
    XCTAssertEqual(library.panelDock.floatingGroups(id).map(\.id), ["color", "properties"])
    XCTAssertTrue(library.stackPanels(.group("layers"), hostID: id, before: nil))
    XCTAssertEqual(
      library.panelDock.floatingGroups(id).map(\.id), ["color", "properties", "layers"])
    XCTAssertTrue(library.stackPanels(.group("layers"), hostID: id, before: "color"))
    XCTAssertEqual(
      library.panelDock.floatingGroups(id).map(\.id), ["layers", "color", "properties"])
    let before = library.panelDock
    XCTAssertFalse(library.stackPanels(.group("layers"), hostID: id, before: "layers"))
    XCTAssertEqual(library.panelDock, before)
    XCTAssertTrue(library.floatPanels(.group("color"), frame: frame))
    XCTAssertEqual(library.panelDock.floatingGroups(id).map(\.id), ["layers", "properties"])
    XCTAssertEqual(library.panelDock.floatingGroups("color").map(\.id), ["color"])
    XCTAssertTrue(library.movePanels(.group("layers"), to: .beforeGroup(nil)))
    XCTAssertEqual(library.panelDock.floatingGroups(id).map(\.id), ["properties"])
    XCTAssertNil(library.panelDock.groups.first { $0.id == "layers" }?.floatingStack)
    try library.panelDock.validate()
    XCTAssertEqual(library.panelDock.groups.flatMap(\.panels).count, WorkspacePanel.allCases.count)
  }

  @MainActor func testTabSplitAndMergePreserveHiddenPanelsSelectionAndFrameEquality() throws {
    let library = WorkspaceLibrary()
    library.closePanels([.properties])
    let id = try stack(library)
    XCTAssertEqual(library.panelDock.groups.first { $0.id == "properties" }?.selected, .adjustments)
    XCTAssertTrue(library.stackPanels(.panel(.gradients), hostID: id, before: "properties"))
    let split = try XCTUnwrap(library.panelDock.groups.first { $0.panels == [.gradients] })
    XCTAssertEqual(split.floatingHostID, id)
    let oldHeight = try XCTUnwrap(split.floatingFrame).height
    XCTAssertTrue(library.movePanels(.group(split.id), to: .group("color", before: nil)))
    let groups = library.panelDock.floatingGroups(id)
    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].selected, .gradients)
    XCTAssertLessThan(try XCTUnwrap(groups[0].floatingFrame).height, oldHeight)
    XCTAssertEqual(groups[0].floatingFrame, groups[1].floatingFrame)
    XCTAssertTrue(library.panelDock.hidden.contains(.properties))
    try library.panelDock.validate()
  }

  @MainActor func testNativeStackIsOneWindowAndClosingRevealingLeavesDockCollapsed() throws {
    let (controller, doc, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let bytes = try doc.data(ofType: CraftNSDocument.nativeType)
    let id = try stack(library)
    panels.synchronize()
    XCTAssertEqual(panels.controllers.count, 1)
    let host = try XCTUnwrap(panels.controllers[id])
    let window = try XCTUnwrap(host.window)
    XCTAssertEqual(window.title, "Color / Properties")
    XCTAssertFalse(window.canBecomeMain)
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(host.windowShouldClose(window))
    panels.synchronize()
    XCTAssertTrue(panels.controllers.isEmpty)
    library.layout.visibility.collapsedDock = true
    doc.store.reveal(ColorPanelTab.gradients)
    panels.synchronize()
    XCTAssertEqual(panels.controllers.count, 1)
    XCTAssertEqual(panels.controllers[id]?.window?.title, "Gradients")
    XCTAssertTrue(library.layout.visibility.collapsedDock)
    doc.store.reveal(PropertiesTab.adjustments)
    panels.synchronize()
    XCTAssertEqual(panels.controllers.count, 1)
    XCTAssertEqual(panels.controllers[id]?.window?.title, "Gradients / Adjustments")
    XCTAssertTrue(library.layout.visibility.collapsedDock)
    doc.store.reveal(LayersTab.layers)
    XCTAssertFalse(library.layout.visibility.collapsedDock)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), bytes)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testNativeStackCollapseResizeMovementAndLockPreserveExpandedTopEdge() throws {
    let (controller, _, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let id = try stack(library)
    panels.synchronize()
    let window = try XCTUnwrap(panels.controllers[id]?.window)
    let expanded = window.frame
    library.togglePanelGroup("color")
    panels.synchronize()
    XCTAssertLessThan(window.frame.height, expanded.height)
    XCTAssertEqual(window.frame.maxY, expanded.maxY)
    library.togglePanelGroup("properties")
    panels.synchronize()
    XCTAssertEqual(window.contentView?.bounds.height, 62)
    let collapsed = window.frame
    window.setFrame(
      NSRect(
        x: collapsed.minX + 60, y: collapsed.minY + 70,
        width: 410, height: collapsed.height), display: false)
    panels.synchronize()
    let saved = try XCTUnwrap(library.panelDock.floatingGroups(id).first?.floatingFrame)
    XCTAssertEqual(saved.height, expanded.height, accuracy: 0.001)
    XCTAssertEqual(saved.rect.maxY, expanded.maxY + 70, accuracy: 0.001)
    XCTAssertEqual(saved.width, 410)
    XCTAssertTrue(library.panelDock.floatingGroups(id).allSatisfy { $0.floatingFrame == saved })
    library.togglePanelGroup("color")
    library.togglePanelGroup("properties")
    panels.synchronize()
    XCTAssertEqual(window.frame, saved.rect)
    try library.setWorkspaceLocked(true)
    panels.synchronize()
    XCTAssertFalse(window.isMovable)
    library.recordFloatingStackFrame(
      id, frame: NSRect(x: 900, y: 900, width: 450, height: 700), hiddenHeight: 0)
    let locked = try XCTUnwrap(library.panelDock.floatingGroups(id).first?.floatingFrame)
    XCTAssertEqual(locked.x, saved.x)
    XCTAssertEqual(locked.rect.maxY, saved.rect.maxY)
    XCTAssertEqual(locked.width, 450)
  }

  @MainActor func testSizingSplittersHiddenRowsAndRejectedInputs() throws {
    let library = WorkspaceLibrary()
    let id = try stack(library)
    let dock = library.panelDock
    let expanded =
      try XCTUnwrap(dock.floatingGroups(id).first?.floatingFrame).height
      - FloatingPanelWindow.titlebarHeight
    let initial = FloatingPanelStackSizing(
      dock: dock, hostID: id, visibility: library.layout.visibility, expandedHeight: expanded)
    XCTAssertEqual(initial.rows.count, 2)
    XCTAssertEqual(initial.naturalHeight, expanded, accuracy: 0.001)
    library.resizeFloatingGroup("color", hostID: id, startingHeights: initial.heights, by: 40)
    let resized = FloatingPanelStackSizing(
      dock: library.panelDock, hostID: id, visibility: library.layout.visibility,
      expandedHeight: expanded)
    XCTAssertEqual(resized.rows[0].height, initial.rows[0].height + 40, accuracy: 0.001)
    XCTAssertEqual(resized.rows[1].height, initial.rows[1].height - 40, accuracy: 0.001)
    let before = library.layout
    library.resizeFloatingGroup("color", hostID: id, startingHeights: initial.heights, by: .nan)
    XCTAssertFalse(library.stackPanels(.group("layers"), hostID: "missing", before: nil))
    XCTAssertFalse(library.stackPanels(.group("layers"), hostID: id, before: "missing"))
    XCTAssertEqual(library.layout, before)
    try library.setWorkspaceLocked(true)
    XCTAssertFalse(library.stackPanels(.group("layers"), hostID: id, before: nil))
    library.closePanels([.color, .swatches, .gradients, .patterns])
    let hidden = FloatingPanelStackSizing(
      dock: library.panelDock, hostID: id, visibility: library.layout.visibility,
      expandedHeight: expanded)
    XCTAssertEqual(hidden.rows.map(\.id), ["properties"])
    XCTAssertEqual(hidden.rows[0].height, resized.rows[1].height, accuracy: 0.001)
  }

  @MainActor func testResizingVisibleRowsKeepsCollapsedExpandedHeight() throws {
    let (controller, _, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let id = try stack(library)
    library.togglePanelGroup("color")
    panels.synchronize()
    let host = try XCTUnwrap(panels.controllers[id])
    let window = try XCTUnwrap(host.window)
    let retained = try XCTUnwrap(host.expandedRowHeights["color"])
    let other = try XCTUnwrap(host.expandedRowHeights["properties"])
    let old = window.frame
    window.setFrame(
      NSRect(x: old.minX, y: old.minY - 100, width: old.width, height: old.height + 100),
      display: false)
    panels.synchronize()
    XCTAssertEqual(try XCTUnwrap(host.expandedRowHeights["color"]), retained, accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(host.expandedRowHeights["properties"]), other + 100, accuracy: 0.001)
    XCTAssertEqual(window.frame.maxY, old.maxY, accuracy: 0.001)
  }

  @MainActor func testNativeBoundariesStackAndGroupTabsKeepDistinctPayloads() throws {
    let (controller, _, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    library.floatPanels(.group("color"), frame: frame)
    panels.synchronize()
    let content = try XCTUnwrap(panels.controllers["color"]?.window?.contentView)
    content.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let boundary = try XCTUnwrap(descendants(content).compactMap { $0 as? PanelDockDropView }.last)
    let payload = PanelDockPayload(library: library.identity, source: .group("layers"))
    XCTAssertTrue(boundary.drop(payload))
    panels.synchronize()
    let id = try XCTUnwrap(library.panelDock.groups.first { $0.id == "layers" }).floatingHostID
    let stacked = try XCTUnwrap(panels.controllers[id]?.window?.contentView)
    stacked.layoutSubtreeIfNeeded()
    let tabs = descendants(stacked).compactMap { $0 as? PanelDockTabButton }
    XCTAssertTrue(tabs.contains { $0.payloadValue?.source == .group("color") })
    XCTAssertTrue(tabs.contains { $0.payloadValue?.source == .group("layers") })
    XCTAssertEqual(panels.controllers.count, 1)
    XCTAssertTrue(
      descendants(stacked).compactMap { $0 as? PanelDockDropView }.contains { $0.resize != nil })
  }

  @MainActor func testTearOffUsesRowSizeAndDoesNotReuseStackHostIdentity() throws {
    let (controller, _, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let id = try stack(library)
    panels.synchronize()
    let group = try XCTUnwrap(library.panelDock.groups.first { $0.id == "color" })
    let size = try XCTUnwrap(panels.tearOffSize(for: group))
    XCTAssertLessThan(size.height, try XCTUnwrap(group.floatingFrame).height)
    let drag = controller.documentWindows.panelDragging
    drag.presentsBackdrops = false
    let payload = PanelDockPayload(library: library.identity, source: .group("color"))
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 20, y: 25)))
    XCTAssertTrue(drag.drop(payload, at: NSPoint(x: 600, y: 800)))
    panels.synchronize()
    XCTAssertNotNil(panels.controllers[id])
    XCTAssertNotNil(panels.controllers["color"])
    let detached = try XCTUnwrap(library.panelDock.floatingGroups("color").first?.floatingFrame)
    XCTAssertEqual(detached.height, size.height, accuracy: 0.001)
    XCTAssertEqual(detached.width, size.width)
  }

  @MainActor func testStackPersistenceResetMigrationAndMalformedLayouts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Workspace.json")
    let library = WorkspaceLibrary(persistenceURL: url)
    let id = try stack(library)
    try library.save(name: "Stack")
    let saved = library.layout
    library.togglePanelGroup("color")
    library.closePanels([.properties])
    try library.flush()
    let restored = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(restored.error)
    XCTAssertEqual(restored.layout, library.layout)
    XCTAssertEqual(restored.panelDock.floatingGroups(id).count, 2)
    try restored.reset()
    XCTAssertEqual(restored.layout, saved)
    var malformed = restored.panelDock
    let index = try XCTUnwrap(malformed.groups.firstIndex { $0.id == "properties" })
    malformed.groups[index].floatingFrame?.x += 1
    XCTAssertThrowsError(try malformed.validate())
    malformed = restored.panelDock
    malformed.groups[index].floatingFrame = nil
    XCTAssertThrowsError(try malformed.validate())
    let old = Data(
      "{\"id\":\"old\",\"panels\":[\"Layers\"],\"selected\":\"Layers\",\"collapsed\":false}".utf8)
    XCTAssertNil(try JSONDecoder().decode(PanelDockGroup.self, from: old).floatingStack)
  }
}
