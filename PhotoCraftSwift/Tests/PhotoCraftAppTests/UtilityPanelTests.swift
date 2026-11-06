import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class UtilityPanelTests: XCTestCase {
  // Literal previous catalog, independent of the current factory constructor.
  let legacy = """
    {"groups":[
      {"id":"color","panels":["Color","Swatches","Gradients","Patterns"],"selected":"Gradients","collapsed":false,"preferredHeight":207},
      {"id":"properties","panels":["Properties","Adjustments","Libraries"],"selected":"Adjustments","collapsed":true,"floatingFrame":{"x":100,"y":200,"width":410,"height":350},"columnID":"left"},
      {"id":"layers","panels":["Layers","Channels","Paths"],"selected":"Channels","collapsed":false}
    ],"hidden":["Swatches"],"columns":[{"id":"left","side":"left","width":410,"collapsed":false,"iconWidth":140},{"id":"main","side":"right"}]}
    """

  func testLegacyCatalogMigrationRetainsExistingTopologyAndAddsUtilitiesOnce() throws {
    let data = Data(legacy.utf8)
    let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let groups = try JSONDecoder().decode(
      [PanelDockGroup].self,
      from: JSONSerialization.data(withJSONObject: original["groups"]!))
    let dock = try JSONDecoder().decode(PanelDock.self, from: data)
    XCTAssertEqual(Array(dock.groups.prefix(3)), groups)
    XCTAssertEqual(dock.hidden, [.swatches, .cloneSource, .character, .paragraph])
    XCTAssertEqual(dock.orderedColumns.map(\.id), ["left", "utility", "main"])
    XCTAssertEqual(dock.orderedColumns[0].width, 410)
    XCTAssertEqual(dock.orderedColumns[0].iconWidth, 140)
    XCTAssertEqual(dock.catalogVersion, 3)
    XCTAssertEqual(dock.groups.dropFirst(3).map(\.panels), [[.history], [.cloneSource], [.character, .paragraph]])
    XCTAssertEqual(try JSONDecoder().decode(PanelDock.self, from: JSONEncoder().encode(dock)), dock)
    var noColumns = original
    noColumns.removeValue(forKey: "columns")
    var oldGroups = noColumns["groups"] as! [[String: Any]]
    oldGroups[1].removeValue(forKey: "columnID")
    noColumns["groups"] = oldGroups
    let beforeColumns = try JSONDecoder().decode(
      PanelDock.self, from: JSONSerialization.data(withJSONObject: noColumns))
    XCTAssertEqual(beforeColumns.orderedColumns.map(\.id), ["utility", "main"])
    XCTAssertEqual(beforeColumns.groups[1].floatingFrame, groups[1].floatingFrame)
  }

  func testMigrationRejectsCorruptOldCatalogAndUnknownVersions() throws {
    let original = try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as! [String: Any]
    var missing = original
    var groups = missing["groups"] as! [[String: Any]]
    groups[0]["panels"] = ["Color", "Gradients", "Patterns"]
    missing["groups"] = groups
    var duplicate = original
    groups = duplicate["groups"] as! [[String: Any]]
    groups[0]["panels"] = ["Color", "Color", "Gradients", "Patterns"]
    duplicate["groups"] = groups
    var future = original
    future["catalogVersion"] = 99
    var badHidden = original
    badHidden["hidden"] = ["History"]
    var tooManyColumns = original
    tooManyColumns["columns"] =
      [["id": "main", "side": "right"], ["id": "left", "side": "left"]]
      + (0..<10).map { ["id": "unused-\($0)", "side": "right"] }
    for bad in [missing, duplicate, future, badHidden, tooManyColumns] {
      XCTAssertThrowsError(
        try JSONDecoder().decode(
          PanelDock.self, from: JSONSerialization.data(withJSONObject: bad)))
    }
  }

  func testMigrationAvoidsExistingUtilityColumnAndGroupIdentifierCollisions() throws {
    var original = try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as! [String: Any]
    var columns = original["columns"] as! [[String: Any]]
    columns[0]["id"] = "utility"
    original["columns"] = columns
    var groups = original["groups"] as! [[String: Any]]
    groups[0]["id"] = "history"
    groups[1]["id"] = "cloneSource"
    groups[1]["columnID"] = "utility"
    original["groups"] = groups
    let dock = try JSONDecoder().decode(
      PanelDock.self, from: JSONSerialization.data(withJSONObject: original))
    XCTAssertEqual(dock.groups[0].id, "history")
    XCTAssertEqual(dock.groups[1].id, "cloneSource")
    XCTAssertEqual(dock.orderedColumns[0].id, "utility")
    XCTAssertEqual(dock.orderedColumns[0].width, 410)
    XCTAssertEqual(Set(dock.groups.map(\.id)).count, dock.groups.count)
    let utilities = dock.groups.filter { $0.panels.contains(.history) || $0.panels.contains(.cloneSource) }
    XCTAssertTrue(utilities.allSatisfy { $0.dockColumnID != "utility" })
    XCTAssertEqual(try JSONDecoder().decode(PanelDock.self, from: JSONEncoder().encode(dock)), dock)
  }

  @MainActor func testMigratedWorkspaceCanSaveResetAndReopenWithoutDiscardingOldState() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Workspaces.json")
    var data =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(WorkspaceState()))
      as! [String: Any]
    var workspaces = data["workspaces"] as! [[String: Any]]
    var layout = workspaces[0]["lastUsed"] as! [String: Any]
    layout["panelDock"] = try JSONSerialization.jsonObject(with: Data(legacy.utf8))
    workspaces[0]["lastUsed"] = layout
    data["workspaces"] = workspaces
    let bytes = try JSONSerialization.data(withJSONObject: data)
    try bytes.write(to: url)
    let library = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(library.error)
    XCTAssertEqual(try Data(contentsOf: url), bytes, "Loading must not overwrite the original file")
    let migrated = library.layout
    try library.save(name: "Old Retouch")
    library.movePanels(.panel(.history), to: .group("layers", before: .channels))
    library.selectPanel(.cloneSource, reveal: true)
    try library.flush()
    let reopened = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(reopened.error)
    XCTAssertEqual(reopened.layout, library.layout)
    try reopened.reset()
    XCTAssertEqual(reopened.layout, migrated)
    data["workspaces"] = [["name": "Essentials", "saved": layout, "lastUsed": layout]]
    let invalid = try JSONSerialization.data(withJSONObject: data)
    try invalid.write(to: url)
    let rejected = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNotNil(rejected.error)
    XCTAssertThrowsError(try rejected.flush())
    XCTAssertEqual(try Data(contentsOf: url), invalid)
  }

  @MainActor func testUtilitiesShareDockVisibilityAndRetainLocationsAcrossHideRevealAndLock() throws
  {
    let library = WorkspaceLibrary()
    XCTAssertTrue(library.panelDock.hidden.contains(.cloneSource))
    XCTAssertEqual(
      library.panelDock.visibleColumns(library.layout.visibility).map(\.id), ["utility", "main"])
    for panel in [WorkspacePanel.history, .cloneSource] {
      library.selectPanel(panel, reveal: true)
      XCTAssertTrue(library.movePanels(.panel(panel), to: .newColumn(.left, before: nil)))
      let group = try XCTUnwrap(library.panelDock.groups.first { $0.panels.contains(panel) })
      library.closePanels([panel])
      library.layout.visibility.togglePanels(includingTools: true)
      library.selectPanel(panel, reveal: true)
      XCTAssertTrue(library.layout.visibility.rail)
      XCTAssertEqual(
        library.panelDock.groups.first { $0.id == group.id }?.dockColumnID, group.dockColumnID)
      XCTAssertFalse(library.panelDock.hidden.contains(panel))
      try library.setWorkspaceLocked(true)
      XCTAssertFalse(library.movePanels(.panel(panel), to: .group("color", before: nil)))
      library.closePanels([panel])
      library.selectPanel(panel, reveal: true)
      XCTAssertFalse(library.panelDock.hidden.contains(panel))
      try library.setWorkspaceLocked(false)
    }
  }

  @MainActor func testHistoryNavigatesBackwardForwardAndBranchesWithoutChangingOtherDocuments()
    async throws
  {
    let store = EditorStore(document: try CraftDocument(width: 3, height: 2))
    let other = EditorStore(document: try CraftDocument(width: 2, height: 2))
    defer {
      store.renderTask?.cancel()
      other.renderTask?.cancel()
    }
    let otherBefore = other.document
    let original = store.document
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.renameLayer(id, "First"))
    let first = store.document
    store.perform(.opacity(id, 0.5))
    store.perform(.visibility(id, false))
    let last = store.document
    XCTAssertEqual(
      store.historyStateLabels,
      ["Earliest available state", "Rename Layer", "Layer Opacity", "Layer Visibility"])
    await store.selectHistoryState(1).value
    XCTAssertEqual(store.document, first)
    XCTAssertEqual(store.session.redoStack.count, 2)
    XCTAssertEqual(store.historyStateLabels.count, 4)
    await store.selectHistoryState(3).value
    XCTAssertEqual(store.document, last)
    await store.selectHistoryState(0).value
    XCTAssertEqual(store.document, original)
    await store.selectHistoryState(1).value
    store.perform(.renameLayer(id, "Branch"))
    XCTAssertTrue(store.session.redoStack.isEmpty)
    XCTAssertEqual(store.historyStateLabels.count, 3)
    XCTAssertEqual(other.document, otherBefore)
    XCTAssertTrue(other.session.undoStack.isEmpty)
  }

  @MainActor func testHistoryRejectsDraftBusyAndInvalidTargetsWithoutCancellingTheDraft()
    async throws
  {
    let store = EditorStore(document: try EditableLifecycleModel.make(width: 3, height: 2))
    defer { store.renderTask?.cancel() }
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.renameLayer(id, "Edited"))
    let before = store.document
    for index in [-1, 99] { await store.selectHistoryState(index).value }
    XCTAssertEqual(store.document, before)
    store.beginLevels()
    XCTAssertNotNil(store.levelsDraft)
    XCTAssertFalse(store.canNavigateHistory)
    await store.selectHistoryState(0).value
    XCTAssertNotNil(store.levelsDraft)
    XCTAssertEqual(store.document, before)
    store.cancelLevels()
    store.geometryBusy = true
    await store.selectHistoryState(0).value
    XCTAssertEqual(store.document, before)
    store.geometryBusy = false
    await store.selectHistoryState(0).value
    XCTAssertNotEqual(store.document, before)
  }

  @MainActor func testHistoryUsesEarliestRetainedStateAfterHistoryLimitTrimming() async throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    defer { store.renderTask?.cancel() }
    store.session = EditorSession(document: store.document, historyLimit: 2)
    let id = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.renameLayer(id, "One"))
    store.perform(.renameLayer(id, "Two"))
    let earliest = store.document
    store.perform(.renameLayer(id, "Three"))
    store.perform(.renameLayer(id, "Four"))
    let latest = store.document
    XCTAssertEqual(store.historyStateLabels.count, 3)
    await store.selectHistoryState(0).value
    XCTAssertEqual(store.document, earliest)
    await store.selectHistoryState(2).value
    XCTAssertEqual(store.document, latest)
  }

  @MainActor func testEmbeddedCloneContentFitsMinimumDockWidthAndPreservesSharedSources() throws {
    _ = NSApplication.shared
    let state = CloneSources()
    let store = try CloneWorkflowTests().makeStore(state: state)
    defer { CloneWorkflowTests().stop(store) }
    store.setCloneSource(at: .init(3.5, 3.5))
    let before = store.document
    let host = NSHostingView(rootView: WorkspaceView(store: store).dockContent(.cloneSource))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 275, height: 500), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let controls = fields(host).filter(\.isEditable)
    XCTAssertGreaterThanOrEqual(controls.count, 5)
    for field in controls {
      let rect = field.convert(field.bounds, to: host)
      XCTAssertGreaterThanOrEqual(rect.minX, 0)
      XCTAssertLessThanOrEqual(rect.maxX, host.bounds.width)
    }
    CloneSourcePanel(state: state, target: store, embedded: true).number(
      \.rotation, range: -180...180
    ).wrappedValue = 30
    XCTAssertEqual(state.slot.rotation, 30)
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testWindowCommandsRevealRetainedUtilitiesAndFloatingHostsFollowActiveDocument()
    throws
  {
    try PhotoshopMenuTests().withMenus { app, menu in
      let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
      let a = CraftNSDocument(model: try CraftDocument(width: 3, height: 2))
      let b = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      let windows = controller.documentWindows
      windows.floatingPanels.presentsWindows = false
      defer {
        a.close()
        b.close()
        windows.floatingPanels.dismissAll()
        windows.floatingPanels.presentsWindows = true
      }
      for doc in [a, b] {
        controller.addDocument(doc)
        doc.makeWindowControllers()
        doc.store.renderTask?.cancel()
      }
      let before = try [a, b].map { try $0.data(ofType: CraftNSDocument.nativeType) }
      let library = controller.workspaces
      for panel in [WorkspacePanel.history, .cloneSource] {
        library.closePanels([panel])
        library.layout.visibility.rail = false
        let submenu = try XCTUnwrap(menu.item(withTitle: "Window")?.submenu)
        let item = try XCTUnwrap(submenu.item(withTitle: panel.rawValue))
        XCTAssertTrue(app.validateMenuItem(item))
        submenu.performActionForItem(at: submenu.index(of: item))
        XCTAssertFalse(library.panelDock.hidden.contains(panel))
        XCTAssertTrue(library.layout.visibility.rail)
        let frame = FloatingPanelFrame(NSRect(x: 100, y: 150, width: 322, height: 400))
        XCTAssertTrue(library.floatPanels(.panel(panel), frame: frame))
      }
      windows.floatingPanels.synchronize()
      XCTAssertEqual(windows.floatingPanels.controllers.count, 2)
      XCTAssertTrue(windows.activate(a))
      windows.floatingPanels.synchronize()
      for host in windows.floatingPanels.controllers.values {
        XCTAssertTrue((host.window as? FloatingPanelWindow)?.documents?.activeDocument === a)
      }
      XCTAssertTrue(windows.activate(b))
      windows.floatingPanels.synchronize()
      for host in windows.floatingPanels.controllers.values {
        XCTAssertTrue((host.window as? FloatingPanelWindow)?.documents?.activeDocument === b)
      }
      XCTAssertEqual(try [a, b].map { try $0.data(ofType: CraftNSDocument.nativeType) }, before)
      XCTAssertTrue([a, b].allSatisfy { $0.store.session.undoStack.isEmpty })
    }
  }
}
