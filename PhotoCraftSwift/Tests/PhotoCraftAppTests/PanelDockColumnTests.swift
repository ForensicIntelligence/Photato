import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class PanelDockColumnTests: XCTestCase {
  @MainActor func column(
    _ library: WorkspaceLibrary, group: String = "properties", side: PanelDockSide = .left
  ) throws -> String {
    XCTAssertTrue(library.movePanels(.group(group), to: .newColumn(side, before: nil)))
    return try XCTUnwrap(library.panelDock.groups.first { $0.id == group }).dockColumnID
  }
  @MainActor func fixture() throws -> (CraftDocumentController, CraftNSDocument) {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let doc = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 8, height: 6, name: "Columns"))
    controller.addDocument(doc)
    doc.makeWindowControllers()
    doc.store.renderTask?.cancel()
    controller.documentWindows.floatingPanels.presentsWindows = false
    controller.documentWindows.panelDragging.presentsBackdrops = false
    return (controller, doc)
  }
  @MainActor func cleanup(_ controller: CraftDocumentController) {
    controller.documentWindows.panelDragging.finish()
    controller.documentWindows.panelDragging.presentsBackdrops = true
    for document in controller.documents { document.close() }
    controller.documentWindows.floatingPanels.dismissAll()
    controller.documentWindows.floatingPanels.presentsWindows = true
  }
  @MainActor func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  @MainActor func testEveryPanelTransfersAcrossBothSidesWithoutLossOrDuplication() throws {
    for side in PanelDockSide.allCases {
      for panel in WorkspacePanel.allCases {
        let library = WorkspaceLibrary()
        for visiblePanel in WorkspacePanel.allCases { library.selectPanel(visiblePanel, reveal: true) }
        XCTAssertTrue(library.movePanels(.panel(panel), to: .newColumn(side, before: nil)))
        let group = try XCTUnwrap(library.panelDock.groups.first { $0.panels == [panel] })
        let target = try XCTUnwrap(
          library.panelDock.orderedColumns.first { $0.id == group.dockColumnID })
        XCTAssertEqual(target.side, side)
        XCTAssertNotEqual(target.id, PanelDockColumn.primaryID)
        XCTAssertEqual(
          library.panelDock.groups(inColumn: target.id, visibility: library.layout.visibility).map(
            \.panels), [[panel]])
        XCTAssertTrue(
          library.movePanels(
            .group(group.id), to: .column(PanelDockColumn.primaryID, beforeGroup: nil)))
        XCTAssertEqual(
          Set(library.panelDock.orderedColumns.map(\.id)), ["utility", PanelDockColumn.primaryID])
        XCTAssertEqual(
          library.panelDock.groups.flatMap(\.panels).count, WorkspacePanel.allCases.count)
        try library.panelDock.validate()
      }
    }
  }

  @MainActor func testFloatingAndStackedGroupsRememberTheirOwnDockDestination() throws {
    let library = WorkspaceLibrary()
    let id = try column(library)
    let frame = FloatingPanelFrame(NSRect(x: 100, y: 100, width: 350, height: 300))
    XCTAssertTrue(library.floatPanels(.group("properties"), frame: frame))
    XCTAssertTrue(library.panelDock.orderedColumns.contains { $0.id == id })
    XCTAssertTrue(
      library.panelDock.groups(inColumn: id, visibility: library.layout.visibility).isEmpty)
    XCTAssertTrue(library.stackPanels(.group("color"), hostID: "properties", before: nil))
    let host = try XCTUnwrap(library.panelDock.groups.first { $0.id == "properties" })
      .floatingHostID
    XCTAssertEqual(library.panelDock.floatingGroups(host).count, 2)
    XCTAssertTrue(library.movePanels(.group("properties"), to: .beforeGroup(nil)))
    XCTAssertEqual(
      library.panelDock.groups(inColumn: id, visibility: library.layout.visibility).map(\.id),
      ["properties"])
    XCTAssertEqual(library.panelDock.floatingGroups(host).map(\.id), ["color"])
    XCTAssertTrue(library.movePanels(.group("color"), to: .beforeGroup(nil)))
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "color" }?.dockColumnID, PanelDockColumn.primaryID)
    try library.panelDock.validate()
  }

  @MainActor func testCloseRevealAndLockAffectOnlyTheTargetColumn() throws {
    let library = WorkspaceLibrary()
    let id = try column(library)
    library.layout.visibility.collapsedDock = true
    library.setColumnCollapsed(id, true)
    library.closePanels([.properties, .adjustments, .libraries])
    XCTAssertFalse(
      library.panelDock.visibleColumns(library.layout.visibility).contains { $0.id == id })
    library.selectPanel(.adjustments, reveal: true)
    XCTAssertEqual(library.panelDock.orderedColumns.first { $0.id == id }?.collapsed, false)
    XCTAssertTrue(library.layout.visibility.collapsedDock)
    XCTAssertEqual(library.panelDock.groups.first { $0.id == "properties" }?.selected, .adjustments)
    try library.setWorkspaceLocked(true)
    let before = library.layout
    XCTAssertFalse(library.movePanels(.group("layers"), to: .column(id, beforeGroup: nil)))
    XCTAssertFalse(library.movePanels(.group("layers"), to: .newColumn(.left, before: nil)))
    XCTAssertFalse(library.moveColumn(id, side: .right, before: nil))
    XCTAssertEqual(library.layout, before)
    library.resizeColumn(id, width: 500)
    library.setColumnCollapsed(id, true)
    XCTAssertEqual(library.columnWidth(id), 500)
    XCTAssertEqual(library.panelDock.orderedColumns.first { $0.id == id }?.collapsed, true)
  }

  @MainActor func testColumnOrderAndSideChangesRetainGroupsAndWidths() throws {
    let library = WorkspaceLibrary()
    let first = try column(library)
    let second = try column(library, group: "layers", side: .right)
    library.resizeColumn(first, width: 460)
    XCTAssertTrue(library.moveColumn(second, side: .left, before: first))
    XCTAssertEqual(
      library.panelDock.orderedColumns.filter { $0.side == .left }.map(\.id), [second, first])
    XCTAssertTrue(library.moveColumn(PanelDockColumn.primaryID, side: .left, before: second))
    XCTAssertEqual(
      library.panelDock.orderedColumns.map(\.id),
      [PanelDockColumn.primaryID, second, first, "utility"])
    XCTAssertEqual(library.columnWidth(first), 460)
    XCTAssertEqual(library.panelDock.groups.first { $0.id == "layers" }?.dockColumnID, second)
    let before = library.layout
    XCTAssertFalse(library.moveColumn(first, side: .right, before: second))
    XCTAssertFalse(library.moveColumn(first, side: .left, before: first))
    XCTAssertFalse(library.movePanels(.group("color"), to: .column(first, beforeGroup: "layers")))
    XCTAssertEqual(library.layout, before)
  }

  @MainActor func testRowSizingAndSplitterWritesStayWithinTheirColumn() throws {
    let library = WorkspaceLibrary()
    let id = try column(library)
    let properties = try XCTUnwrap(library.panelDock.groups.first { $0.id == "properties" })
    let left = PanelDockSizing(layout: library.layout, height: 600, columnID: id)
    let right = PanelDockSizing(layout: library.layout, height: 600)
    XCTAssertEqual(left.rows.map(\.id), ["properties"])
    XCTAssertEqual(right.rows.map(\.id), ["color", "layers"])
    XCTAssertEqual(left.rows.reduce(0) { $0 + $1.height + $1.gap }, 588, accuracy: 0.001)
    library.resizePanelGroup(
      "color", startingHeights: right.heights.merging(left.heights) { a, _ in a }, by: 20)
    XCTAssertEqual(library.panelDock.groups.first { $0.id == "properties" }, properties)
    XCTAssertNotNil(library.panelDock.groups.first { $0.id == "color" }?.preferredHeight)
  }

  @MainActor func testCompactPresentationKeepsColumnsReachableWithoutRewritingLayout() throws {
    let library = WorkspaceLibrary()
    for panel in WorkspacePanel.allCases { library.selectPanel(panel, reveal: true) }
    for (index, panel) in WorkspacePanel.allCases.enumerated() {
      XCTAssertTrue(
        library.movePanels(
          .panel(panel), to: .newColumn(index.isMultiple(of: 2) ? .left : .right, before: nil)))
    }
    let before = library.layout
    for width in [627.0, 687, 947, 2000, 6000] {
      let result = PanelDockColumnSizing(layout: library.layout, availableWidth: width)
      XCTAssertEqual(result.columns.count, WorkspacePanel.allCases.count)
      XCTAssertLessThanOrEqual(result.columns.reduce(0) { $0 + $1.width + 4 }, width)
      XCTAssertTrue(result.columns.allSatisfy { $0.width >= 34 && $0.width.isFinite })
    }
    XCTAssertEqual(library.layout, before)
    let original = PanelDockColumnSizing(layout: WorkspaceLayout(), availableWidth: 687)
    XCTAssertEqual(original.columns.map(\.width), [34, 322])
    XCTAssertTrue(original.columns[0].icons)
    XCTAssertFalse(original.columns[1].icons)
    try library.panelDock.validate()
  }

  @MainActor func testExplicitExpansionGetsSpaceInACompactWorkspace() throws {
    let library = WorkspaceLibrary()
    let id = try column(library)
    _ = try column(library, group: "layers", side: .right)
    library.resizeColumn(id, width: 600)
    library.setColumnCollapsed(id, true)
    library.setColumnCollapsed(id, false)
    let before = library.layout
    let sizing = PanelDockColumnSizing(
      layout: library.layout, availableWidth: 627,
      preferredColumn: library.expandedDockColumnID)
    let shown = try XCTUnwrap(sizing.columns.first { $0.id == id })
    XCTAssertFalse(shown.icons)
    XCTAssertGreaterThanOrEqual(shown.width, 275)
    XCTAssertLessThanOrEqual(sizing.columns.reduce(0) { $0 + $1.width + 4 }, 627)
    XCTAssertEqual(library.layout, before)
    library.selectPanel(.color, reveal: true)
    let revealed = PanelDockColumnSizing(
      layout: library.layout, availableWidth: 627,
      preferredColumn: library.expandedDockColumnID)
    XCTAssertFalse(
      try XCTUnwrap(revealed.columns.first { $0.id == PanelDockColumn.primaryID }).icons)
  }

  @MainActor func testColumnPersistenceMigrationResetAndMalformedFilePreservation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Workspaces.json")
    let library = WorkspaceLibrary(persistenceURL: url)
    let id = try column(library)
    library.resizeColumn(id, width: 450)
    library.resizeColumn(id, width: 150, icons: true)
    library.setColumnCollapsed(id, true)
    try library.save(name: "Columns")
    let saved = library.layout
    library.closePanels([.properties])
    try library.flush()
    let restored = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(restored.error)
    XCTAssertEqual(restored.layout, library.layout)
    try restored.reset()
    XCTAssertEqual(restored.layout, saved)
    var bad = restored.state
    bad.workspaces[1].lastUsed.panelDock?.columns?[0].width = -100
    let bytes = try JSONEncoder().encode(bad)
    try bytes.write(to: url)
    let rejected = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNotNil(rejected.error)
    XCTAssertThrowsError(try rejected.flush())
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    let old = PanelDock(layout: WorkspaceLayout())
    let oldData = try JSONEncoder().encode(old)
    let decoded = try JSONDecoder().decode(PanelDock.self, from: oldData)
    XCTAssertEqual(decoded.catalogVersion, 3)
    XCTAssertEqual(decoded.orderedColumns.map(\.id), ["utility", PanelDockColumn.primaryID])
    XCTAssertTrue(
      decoded.groups.filter { !$0.panels.contains(where: \.isUtility) }
        .allSatisfy { $0.columnID == nil })
  }

  @MainActor func testNativeHorizontalDividerResizesWidthWithoutEditingDocument() throws {
    let (controller, doc) = try fixture()
    defer { cleanup(controller) }
    let window = try XCTUnwrap(controller.documentWindows.applicationFrame?.window)
    let content = try XCTUnwrap(window.contentView)
    content.layoutSubtreeIfNeeded()
    let divider = try XCTUnwrap(
      descendants(content, PanelDockDropView.self).last { $0.horizontalResize && $0.resize != nil }
    )
    let before = try doc.data(ofType: CraftNSDocument.nativeType)
    let start = divider.convert(NSPoint(x: divider.bounds.midX, y: divider.bounds.midY), to: nil)
    func event(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: NSPoint(x: start.x + x, y: start.y), modifierFlags: [],
          timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1))
    }
    divider.mouseDown(with: try event(.leftMouseDown, x: 0))
    divider.mouseDragged(with: try event(.leftMouseDragged, x: 30))
    divider.mouseUp(with: try event(.leftMouseUp, x: 30))
    XCTAssertEqual(controller.workspaces.layout.dockWidth, 292)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), before)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }

  @MainActor func testCanvasColumnTargetsOnlyExistDuringPanelDrag() async throws {
    let (controller, _) = try fixture()
    defer { cleanup(controller) }
    let window = try XCTUnwrap(controller.documentWindows.applicationFrame?.window)
    let content = try XCTUnwrap(window.contentView)
    content.layoutSubtreeIfNeeded()
    func targets() -> [PanelDockDropView] {
      descendants(content, PanelDockDropView.self).filter {
        $0.accessibilityLabel()?.hasPrefix("New ") == true
      }
    }
    XCTAssertTrue(targets().isEmpty)
    let drag = controller.documentWindows.panelDragging
    let payload = PanelDockPayload(
      library: controller.workspaces.identity, source: .group("properties"))
    XCTAssertTrue(drag.begin(payload, anchor: .zero))
    try await Task.sleep(for: .milliseconds(100))
    content.layoutSubtreeIfNeeded()
    let left = try XCTUnwrap(targets().first { $0.accessibilityLabel() == "New left dock" })
    XCTAssertEqual(left.bounds.width, 6)
    XCTAssertTrue(left.accepts(payload))
    XCTAssertTrue(left.drop(payload))
    drag.finish()
    try await Task.sleep(for: .milliseconds(100))
    content.layoutSubtreeIfNeeded()
    XCTAssertTrue(targets().isEmpty)
    let group = try XCTUnwrap(
      controller.workspaces.panelDock.groups.first { $0.id == "properties" })
    XCTAssertEqual(
      controller.workspaces.panelDock.orderedColumns.first { $0.id == group.dockColumnID }?.side,
      .left)
  }

  @MainActor func testTearOffUsesExpandedWidthOfSourceColumn() throws {
    let (controller, doc) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let id = try column(library)
    library.resizeColumn(id, width: 510)
    library.setColumnCollapsed(id, true)
    let before = try doc.data(ofType: CraftNSDocument.nativeType)
    let drag = controller.documentWindows.panelDragging
    let payload = PanelDockPayload(library: library.identity, source: .group("properties"))
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 10, y: 10)))
    XCTAssertTrue(drag.drop(payload, at: NSPoint(x: 500, y: 600)))
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "properties" }?.floatingFrame?.width, 510)
    XCTAssertEqual(library.panelDock.groups.first { $0.id == "properties" }?.dockColumnID, id)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), before)
  }

  @MainActor func testCollapsedDockHasAccessibleNativeIconsAndRetainsPanelPayloads() throws {
    _ = NSApplication.shared
    for panel in WorkspacePanel.allCases {
      XCTAssertNotNil(NSImage(systemSymbolName: panel.dockSymbol, accessibilityDescription: nil))
    }
    let store = EditorStore(document: try CraftDocument(width: 8, height: 6))
    store.renderTask?.cancel()
    store.workspace.collapsedDock = true
    let host = NSHostingView(rootView: WorkspaceView(store: store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    let icons = descendants(host, PanelDockTabButton.self).filter { $0.image != nil }
    XCTAssertEqual(
      Set(icons.map(\.title)),
      Set(WorkspacePanel.allCases.filter { ![WorkspacePanel.cloneSource, .character, .paragraph].contains($0) }.map(\.rawValue)))
    let swatches = try XCTUnwrap(icons.first { $0.title == "Swatches" })
    XCTAssertEqual(swatches.imagePosition, .imageOnly)
    XCTAssertEqual(swatches.accessibilityLabel(), "Swatches panel")
    XCTAssertEqual(swatches.payloadValue?.source, .panel(.swatches))
    let point = swatches.convert(
      NSPoint(x: swatches.bounds.midX, y: swatches.bounds.midY), to: host.superview)
    let hit = host.hitTest(point)
    XCTAssertTrue(hit === swatches || hit?.isDescendant(of: swatches) == true)
    swatches.performClick(nil)
    XCTAssertEqual(store.colorTab, .swatches)
    XCTAssertTrue(store.workspace.collapsedDock)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testLabelDocksKeepTheToolRailVisibleAndHitTestable() throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: 8, height: 6))
    store.renderTask?.cancel()
    let library = store.workspaceLibrary
    _ = try column(library)
    XCTAssertTrue(library.movePanels(.panel(.gradients), to: .newColumn(.right, before: "main")))
    for value in library.panelDock.orderedColumns {
      library.setColumnCollapsed(value.id, true)
      library.resizeColumn(value.id, width: 140, icons: true)
    }
    let host = NSHostingView(rootView: WorkspaceView(store: store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    let well = try XCTUnwrap(descendants(host, ColorSwatchButton.self).first)
    let rect = well.convert(well.bounds, to: host)
    XCTAssertTrue(host.bounds.contains(rect), "Tool color well clipped: \(rect)")
    XCTAssertLessThan(rect.maxX, 40)
    XCTAssertTrue(well.visibleRect.contains(well.bounds))
    let hitPoint = well.convert(
      NSPoint(x: well.bounds.midX, y: well.bounds.midY), to: host.superview)
    let hit = host.hitTest(hitPoint)
    XCTAssertTrue(
      hit === well || hit?.isDescendant(of: well) == true,
      "Tool color well covered: \(String(describing: hit)) rect \(rect)")
    for tab in descendants(host, PanelDockTabButton.self) {
      let bounds = tab.convert(tab.bounds, to: host)
      XCTAssertTrue(host.bounds.contains(bounds), "Dock icon clipped: \(bounds)")
      XCTAssertGreaterThanOrEqual(bounds.minX, 40)
    }
  }
}
