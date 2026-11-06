import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class PanelDockTests: XCTestCase {
  func testMoveSplitMergeAndReorderKeepEveryPanelOnce() throws {
    var dock = PanelDock(layout: .init())
    XCTAssertTrue(dock.move(.panel(.gradients), to: .group("layers", before: .channels)))
    XCTAssertEqual(
      dock.groups.filter { $0.dockColumnID == "main" }.map(\.panels),
      [
        [.color, .swatches, .patterns], [.properties, .adjustments, .libraries],
        [.layers, .gradients, .channels, .paths],
      ])
    XCTAssertEqual(dock.groups.first { $0.id == "layers" }?.selected, .gradients)
    XCTAssertTrue(dock.move(.panel(.paths), to: .beforeGroup("color")))
    XCTAssertEqual(
      dock.groups.filter { $0.dockColumnID == "main" }.map(\.panels),
      [
        [.paths], [.color, .swatches, .patterns], [.properties, .adjustments, .libraries],
        [.layers, .gradients, .channels],
      ])
    let pathsID = dock.groups[0].id
    XCTAssertTrue(dock.move(.group("properties"), to: .group(pathsID, before: .paths)))
    XCTAssertEqual(dock.groups[0].panels, [.properties, .adjustments, .libraries, .paths])
    XCTAssertEqual(dock.groups[0].selected, .properties)
    XCTAssertTrue(dock.move(.group("layers"), to: .beforeGroup(pathsID)))
    XCTAssertEqual(
      dock.groups.filter { $0.dockColumnID == "main" }.map(\.id), ["layers", pathsID, "color"])
    XCTAssertTrue(dock.move(.panel(.channels), to: .group("layers", before: .layers)))
    XCTAssertEqual(dock.groups[0].panels, [.channels, .layers, .gradients])
    try dock.validate()
    let unchanged = dock
    for (source, target) in [
      (PanelDockSource.group("missing"), PanelDockDestination.beforeGroup(nil)),
      (.panel(.color), .group("missing", before: nil)),
      (.group("layers"), .beforeGroup("layers")),
      (.panel(.layers), .group("color", before: .paths)),
      (.panel(.layers), .group("layers", before: .layers)),
      (.group("color"), .group("color", before: nil)),
    ] {
      XCTAssertFalse(dock.move(source, to: target))
      XCTAssertEqual(dock, unchanged)
    }
  }

  func testAllPanelTransfersAndMalformedTopologies() throws {
    let original = PanelDock(layout: .init())
    for panel in WorkspacePanel.allCases {
      for target in original.groups {
        for before in target.panels.map(Optional.some) + [nil] {
          var dock = original
          _ = dock.move(.panel(panel), to: .group(target.id, before: before))
          try dock.validate()
          XCTAssertEqual(dock.groups.flatMap(\.panels).count, WorkspacePanel.allCases.count)
          XCTAssertEqual(dock.groups.filter { $0.panels.contains(panel) }.count, 1)
        }
      }
    }
    var invalid = original
    invalid.groups[0].panels.append(.layers)
    XCTAssertThrowsError(try invalid.validate())
    invalid = original
    invalid.groups.removeLast()
    XCTAssertThrowsError(try invalid.validate())
    invalid = original
    invalid.groups[0].selected = .layers
    XCTAssertThrowsError(try invalid.validate())
    invalid = original
    invalid.groups[0].id = "layers"
    XCTAssertThrowsError(try invalid.validate())
    for height in [Double.nan, .infinity, -1, 28, 4001] {
      invalid = original
      invalid.groups[0].preferredHeight = height
      XCTAssertThrowsError(try invalid.validate())
    }
  }

  @MainActor func testClosedMovedPanelReopensInItsGroupWithoutChangingDocument() throws {
    let library = WorkspaceLibrary()
    let controller = CraftDocumentController(workspaces: library)
    let a = CraftNSDocument(model: try CraftDocument(width: 4, height: 3))
    let b = CraftNSDocument(model: try CraftDocument(width: 3, height: 2))
    defer {
      controller.removeDocument(a)
      controller.removeDocument(b)
    }
    for document in [a, b] {
      document.store.renderTask?.cancel()
      controller.addDocument(document)
    }
    let bytes = try [a, b].map { try $0.data(ofType: CraftNSDocument.nativeType) }
    a.store.zoom = 2.75
    b.store.zoom = 0.45
    XCTAssertTrue(library.movePanels(.panel(.gradients), to: .group("layers", before: .paths)))
    library.closePanels([.gradients])
    library.togglePanelGroup("layers")
    a.store.workspace.layers = false
    a.store.workspace.color = false
    a.store.workspace.collapsedDock = true
    b.store.reveal(ColorPanelTab.gradients)
    let group = try XCTUnwrap(library.panelDock.groups.first { $0.id == "layers" })
    XCTAssertEqual(group.selected, .gradients)
    XCTAssertFalse(group.collapsed)
    XCTAssertFalse(library.panelDock.hidden.contains(.gradients))
    XCTAssertEqual(
      library.panelDock.visiblePanels(in: group, visibility: a.store.workspace), [.gradients])
    XCTAssertEqual(a.store.colorTab, .gradients)
    XCTAssertFalse(b.store.workspace.collapsedDock)
    library.closePanels(group.panels)
    XCTAssertFalse(
      library.panelDock.visibleGroups(a.store.workspace).contains { $0.id == "layers" })
    try library.reset()
    XCTAssertEqual(library.panelDock, PanelDock(layout: .init()))
    XCTAssertEqual(try [a, b].map { try $0.data(ofType: CraftNSDocument.nativeType) }, bytes)
    XCTAssertEqual(a.store.zoom, 2.75)
    XCTAssertEqual(b.store.zoom, 0.45)
    library.closePanels([.color])
    XCTAssertTrue(library.movePanels(.group("color"), to: .group("layers", before: nil)))
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "layers" }?.selected, .swatches,
      "Moving a group selects its visible tab after the previous selection was closed")
    XCTAssertTrue([a, b].allSatisfy { !$0.isDocumentEdited && $0.store.session.undoStack.isEmpty })
  }

  @MainActor func testLegacyWorkspaceMigrationPersistenceResetAndIndependentLock() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Workspaces.json")
    // Literal step066 schema, without topology or the new application lock setting.
    let layout = """
      {"visibility":{"tools":true,"options":true,"color":true,"properties":true,"layers":true,"rail":true,"collapsedDock":false},"colorTab":"Color","propertiesTab":"Properties","layersTab":"Layers","dockWidth":322,"propertiesHeight":360,"doubleTools":false}
      """
    let legacy =
      "{\"version\":1,\"active\":\"Essentials\",\"workspaces\":[{\"name\":\"Essentials\",\"saved\":\(layout),\"lastUsed\":\(layout)}]}"
    try Data(legacy.utf8).write(to: url)
    let library = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(library.error)
    XCTAssertFalse(library.workspaceLocked)
    XCTAssertNil(library.layout.panelDock)
    library.movePanels(.panel(.gradients), to: .group("properties", before: .properties))
    library.closePanels([.swatches])
    try library.save(name: "Retouch")
    let saved = library.layout
    library.movePanels(.group("layers"), to: .beforeGroup("color"))
    let lastUsed = library.layout
    try library.setWorkspaceLocked(true)
    let reopened = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(reopened.error)
    XCTAssertTrue(reopened.workspaceLocked)
    XCTAssertEqual(reopened.layout, lastUsed)
    try reopened.reset()
    XCTAssertEqual(reopened.layout, saved)
    XCTAssertTrue(reopened.workspaceLocked)
    try reopened.select("Essentials")
    try reopened.reset()
    XCTAssertEqual(reopened.layout, WorkspaceLayout())
    XCTAssertTrue(reopened.workspaceLocked)
    try reopened.setWorkspaceLocked(false)
    XCTAssertFalse(WorkspaceLibrary(persistenceURL: url).workspaceLocked)
    var malformed = reopened.state
    malformed.workspaces[0].lastUsed.panelDock = PanelDock(layout: .init())
    malformed.workspaces[0].lastUsed.panelDock?.groups[0].panels.append(.paths)
    let bytes = try JSONEncoder().encode(malformed)
    try bytes.write(to: url)
    let rejected = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNotNil(rejected.error)
    XCTAssertThrowsError(try rejected.flush())
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testSizingPreservesFactoryAndBoundsCustomCollapsedAndSplitGroups() throws {
    for height: CGFloat in [615, 865, 1139] {
      var layout = WorkspaceLayout()
      let original = WorkspacePanelLayout(
        height: height, visibility: layout.visibility, library: false, preferredProperties: 360)
      XCTAssertEqual(
        PanelDockSizing(layout: layout, height: height).rows.map(\.height),
        [original.colorHeight, original.propertiesHeight, original.layersHeight])
      var dock = PanelDock(layout: layout)
      for panel in WorkspacePanel.allCases {
        _ = dock.move(.panel(panel), to: .beforeGroup(nil))
        layout.panelDock = dock
        for mask in 0..<8 {
          layout.visibility.color = mask & 1 != 0
          layout.visibility.properties = mask & 2 != 0
          layout.visibility.layers = mask & 4 != 0
          for collapsed in [false, true] {
            for index in layout.panelDock!.groups.indices {
              layout.panelDock!.groups[index].collapsed = collapsed
            }
            let rows = PanelDockSizing(layout: layout, height: height).rows
            XCTAssertTrue(rows.allSatisfy { $0.height.isFinite && $0.height >= 29 })
            XCTAssertLessThanOrEqual(rows.reduce(12) { $0 + $1.height + $1.gap }, height + 0.000001)
            if collapsed { XCTAssertTrue(rows.allSatisfy { $0.height == 29 }) }
          }
        }
      }
    }
  }

  @MainActor func testLockRejectsMovementButKeepsResizeCollapseAndMenuCheckmark() throws {
    try PhotoshopMenuTests().withMenus { app, _ in
      let library = app.controller.workspaces
      let lock = try XCTUnwrap(app.workspaceMenu?.item(withTitle: "Lock Workspace"))
      XCTAssertTrue(app.validateMenuItem(lock))
      XCTAssertEqual(lock.state, .off)
      app.workspaceMenu?.performActionForItem(at: app.workspaceMenu!.index(of: lock))
      XCTAssertTrue(library.workspaceLocked)
      XCTAssertTrue(app.validateMenuItem(lock))
      XCTAssertEqual(lock.state, .on)
      let before = library.layout
      XCTAssertFalse(library.movePanels(.panel(.paths), to: .beforeGroup(nil)))
      XCTAssertEqual(library.layout, before)
      let heights = PanelDockSizing(layout: library.layout, height: 865).heights
      library.resizePanelGroup("color", startingHeights: heights, by: 40)
      let resized = PanelDockSizing(layout: library.layout, height: 865).heights
      XCTAssertEqual(
        try XCTUnwrap(resized["color"]), try XCTUnwrap(heights["color"]) + 40, accuracy: 0.000001)
      XCTAssertEqual(
        try XCTUnwrap(resized["properties"]), try XCTUnwrap(heights["properties"]) - 40,
        accuracy: 0.000001)
      library.togglePanelGroup("color")
      XCTAssertTrue(library.panelDock.groups[0].collapsed)
      try library.reset()
      XCTAssertTrue(library.workspaceLocked)
      app.lockWorkspace()
      XCTAssertFalse(library.workspaceLocked)
      XCTAssertTrue(library.movePanels(.panel(.paths), to: .beforeGroup(nil)))
    }
  }

  @MainActor func testNativePrivatePayloadValidationAndPointerActions() throws {
    let library = WorkspaceLibrary()
    let button = PanelDockTabButton()
    button.frame = NSRect(x: 0, y: 0, width: 120, height: 29)
    button.accepts = { library.acceptsPanelPayload($0) }
    let board = NSPasteboard.withUniqueName()
    defer { board.clearContents() }
    board.setString("Color", forType: .string)
    XCTAssertNil(button.payload(from: board))
    for payload in [
      PanelDockPayload(library: UUID(), source: .panel(.color)),
      .init(library: library.identity, source: .group("unknown")),
    ] {
      board.clearContents()
      let item = NSPasteboardItem()
      payload.write(to: item)
      board.writeObjects([item])
      XCTAssertNil(button.payload(from: board))
    }
    board.clearContents()
    board.setData(Data(repeating: 32, count: 2049), forType: PanelDockPayload.type)
    XCTAssertNil(button.payload(from: board))
    board.clearContents()
    let item = NSPasteboardItem()
    PanelDockPayload(library: library.identity, source: .panel(.color)).write(to: item)
    board.writeObjects([item])
    XCTAssertEqual(button.payload(from: board)?.source, .panel(.color))
    try library.setWorkspaceLocked(true)
    XCTAssertNil(button.payload(from: board))
    try library.setWorkspaceLocked(false)
    library.closePanels([.color])
    XCTAssertNil(button.payload(from: board))
    var selected = 0
    var collapsed = 0
    button.select = { selected += 1 }
    button.collapse = { collapsed += 1 }
    func event(_ type: NSEvent.EventType, x: CGFloat = 20, count: Int = 1) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: .init(x: x, y: 10), modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 1))
    }
    button.mouseDown(with: try event(.leftMouseDown))
    button.mouseDragged(with: try event(.leftMouseDragged, x: 21))
    button.mouseUp(with: try event(.leftMouseUp, x: 21))
    XCTAssertEqual(selected, 1)
    button.mouseDown(with: try event(.leftMouseDown, count: 2))
    button.mouseUp(with: try event(.leftMouseUp, count: 2))
    XCTAssertEqual(collapsed, 1)
    XCTAssertEqual(selected, 1)
    button.mouseDown(with: try event(.leftMouseDown))
    button.mouseUp(with: try event(.leftMouseUp, x: 121))
    XCTAssertEqual(selected, 1)
    button.performClick(nil)
    XCTAssertEqual(selected, 2)
  }

  @MainActor func testHostedDockRoutesNativeTabAndDropToSharedLayout() throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: 8, height: 6))
    store.renderTask?.cancel()
    let original = store.document
    let host = NSHostingView(rootView: WorkspaceView(store: store))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    func settle() {
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      host.layoutSubtreeIfNeeded()
    }
    func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }
    settle()
    let buttons = descendants(host, PanelDockTabButton.self)
    XCTAssertEqual(
      Set(buttons.map(\.title).filter { !$0.isEmpty }),
      Set(WorkspacePanel.allCases.filter { ![WorkspacePanel.cloneSource, .character, .paragraph].contains($0) }.map(\.rawValue))
    )
    let gradients = try XCTUnwrap(buttons.first { $0.title == "Gradients" })
    XCTAssertEqual(gradients.accessibilityLabel(), "Gradients panel")
    // NSView.hitTest takes a point in its superview, not the flipped hosting view.
    let parent = try XCTUnwrap(host.superview)
    let point = gradients.convert(
      NSPoint(x: gradients.bounds.midX, y: gradients.bounds.midY), to: parent)
    let hit = host.hitTest(point)
    XCTAssertTrue(
      hit === gradients || hit?.isDescendant(of: gradients) == true,
      "The displayed panel tab must receive pointer input through its scroll host")
    gradients.performClick(nil)
    settle()
    XCTAssertEqual(store.colorTab, .gradients)
    let layers = try XCTUnwrap(
      descendants(host, PanelDockTabButton.self).first { $0.title == "Layers" })
    XCTAssertTrue(
      layers.drop(.init(library: store.workspaceLibrary.identity, source: .panel(.gradients)), true)
    )
    settle()
    let group = try XCTUnwrap(store.workspaceLibrary.panelDock.groups.first { $0.id == "layers" })
    XCTAssertEqual(group.panels, [.layers, .gradients, .channels, .paths])
    XCTAssertEqual(group.selected, .gradients)
    let newGradients = try XCTUnwrap(
      descendants(host, PanelDockTabButton.self).first { $0.title == "Gradients" })
    XCTAssertEqual(newGradients.accessibilityValue() as? String, "Selected")
    let splitter = try XCTUnwrap(
      descendants(host, PanelDockDropView.self).first { $0.resize != nil && !$0.horizontalResize })
    let location = splitter.convert(
      NSPoint(x: splitter.bounds.midX, y: splitter.bounds.midY), to: nil)
    func resizeEvent(_ type: NSEvent.EventType, offset: CGFloat) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: .init(x: location.x, y: location.y - offset),
          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    splitter.mouseDown(with: try resizeEvent(.leftMouseDown, offset: 0))
    splitter.mouseDragged(with: try resizeEvent(.leftMouseDragged, offset: 20))
    splitter.mouseUp(with: try resizeEvent(.leftMouseUp, offset: 20))
    XCTAssertNotNil(
      store.workspaceLibrary.panelDock.groups.first?.preferredHeight,
      "Native splitter input must publish the requested panel size")
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
