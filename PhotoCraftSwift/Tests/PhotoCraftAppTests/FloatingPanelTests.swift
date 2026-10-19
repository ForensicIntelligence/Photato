import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class FloatingPanelTests: XCTestCase {
  let frame = FloatingPanelFrame(NSRect(x: 240, y: 250, width: 322, height: 360))

  @MainActor func fixture() throws -> (
    CraftDocumentController, CraftNSDocument, FloatingPanelWindows
  ) {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let doc = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 8, height: 6, name: "First"))
    controller.addDocument(doc)
    doc.makeWindowControllers()
    doc.store.renderTask?.cancel()
    let panels = controller.documentWindows.floatingPanels
    panels.presentsWindows = false
    panels.screenFrames = { [NSRect(x: 0, y: 0, width: 1440, height: 900)] }
    return (controller, doc, panels)
  }
  @MainActor func cleanup(_ controller: CraftDocumentController) {
    for document in controller.documents { document.close() }
    controller.documentWindows.floatingPanels.dismissAll()
    controller.documentWindows.floatingPanels.presentsWindows = true
    controller.documentWindows.floatingPanels.screenFrames = {
      NSScreen.screens.map(\.visibleFrame)
    }
  }

  @MainActor func testEveryPanelCanFloatMergeAndDockWithoutDuplication() throws {
    for panel in WorkspacePanel.allCases {
      let library = WorkspaceLibrary()
      XCTAssertTrue(library.floatPanels(.panel(panel), frame: frame))
      var dock = library.panelDock
      let floating = try XCTUnwrap(dock.groups.first { $0.panels == [panel] })
      XCTAssertEqual(floating.floatingFrame, frame)
      XCTAssertEqual(floating.selected, panel)
      XCTAssertFalse(dock.dockedGroups(library.layout.visibility).contains { $0.id == floating.id })
      XCTAssertFalse(
        PanelDockSizing(layout: library.layout, height: 650).rows.contains { $0.id == floating.id })
      let target = try XCTUnwrap(dock.groups.first { $0.id != floating.id })
      XCTAssertTrue(
        library.movePanels(.panel(target.panels[0]), to: .group(floating.id, before: panel)))
      dock = library.panelDock
      XCTAssertEqual(dock.groups.first { $0.id == floating.id }?.floatingFrame, frame)
      XCTAssertTrue(library.movePanels(.group(floating.id), to: .beforeGroup("layers")))
      XCTAssertNil(library.panelDock.groups.first { $0.id == floating.id }?.floatingFrame)
      try library.panelDock.validate()
      XCTAssertEqual(Set(library.panelDock.groups.flatMap(\.panels)), Set(WorkspacePanel.allCases))
    }
  }

  @MainActor func testWholeGroupHiddenSelectionLockAndInvalidRequests() throws {
    let library = WorkspaceLibrary()
    library.closePanels([.color])
    XCTAssertTrue(library.floatPanels(.group("color"), frame: frame))
    XCTAssertEqual(library.panelDock.groups[0].selected, .swatches)
    XCTAssertTrue(library.panelDock.hidden.contains(.color))
    let before = library.layout
    XCTAssertFalse(library.floatPanels(.group("missing"), frame: frame))
    var bad = frame
    bad.x = .infinity
    XCTAssertFalse(library.floatPanels(.panel(.layers), frame: bad))
    XCTAssertEqual(library.layout, before)
    try library.setWorkspaceLocked(true)
    XCTAssertFalse(library.floatPanels(.panel(.layers), frame: frame))
    XCTAssertFalse(library.movePanels(.group("color"), to: .beforeGroup(nil)))
    XCTAssertEqual(library.layout, before)
    library.togglePanelGroup("color")
    library.recordFloatingPanelFrame("color", frame: NSRect(x: 800, y: 700, width: 350, height: 46))
    let moved = try XCTUnwrap(library.panelDock.groups[0].floatingFrame)
    XCTAssertEqual(moved.x, frame.x)
    XCTAssertEqual(moved.rect.maxY, frame.rect.maxY)
    XCTAssertEqual(moved.width, 350)
    XCTAssertEqual(moved.height, 360)
  }

  @MainActor func testOldTopologyMigrationFloatingSaveResetAndMalformedPreservation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Workspaces.json")
    let old = Data(
      "{\"id\":\"old\",\"panels\":[\"Layers\",\"Channels\",\"Paths\"],\"selected\":\"Channels\",\"collapsed\":false}"
        .utf8)
    XCTAssertNil(try JSONDecoder().decode(PanelDockGroup.self, from: old).floatingFrame)
    let library = WorkspaceLibrary(persistenceURL: url)
    library.floatPanels(.group("layers"), frame: frame)
    try library.save(name: "Floating")
    let saved = library.layout
    library.recordFloatingPanelFrame(
      "layers", frame: NSRect(x: -300, y: 180, width: 500, height: 600))
    library.closePanels([.channels])
    try library.flush()
    let restored = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(restored.error)
    XCTAssertEqual(restored.layout, library.layout)
    try restored.reset()
    XCTAssertEqual(restored.layout, saved)
    var malformed = restored.state
    malformed.workspaces[1].lastUsed.panelDock?.groups[2].floatingFrame?.width = -1
    let bytes = try JSONEncoder().encode(malformed)
    try bytes.write(to: url)
    let rejected = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNotNil(rejected.error)
    XCTAssertThrowsError(try rejected.flush())
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }

  func testFloatingFramesRecoverMissingDisplaysAndRejectUnsafeValues() throws {
    let screens = [
      NSRect(x: 0, y: 30, width: 1440, height: 870),
      NSRect(x: -1920, y: 0, width: 1920, height: 1080),
    ]
    XCTAssertEqual(frame.fitted(to: screens), frame.rect)
    let left = FloatingPanelFrame(NSRect(x: -1800, y: 200, width: 300, height: 500))
    XCTAssertEqual(left.fitted(to: screens), left.rect)
    XCTAssertEqual(left.fitted(to: [screens[0]]), NSRect(x: 0, y: 200, width: 300, height: 500))
    let outside = FloatingPanelFrame(NSRect(x: 4000, y: 4000, width: 2000, height: 2000))
    XCTAssertEqual(outside.fitted(to: [screens[0]]), screens[0])
    XCTAssertEqual(frame.fitted(to: []), frame.rect)
    for invalid in [Double.nan, .infinity, -.infinity, -1, 0, 100001] {
      var bad = frame
      bad.width = invalid
      XCTAssertFalse(bad.isValid)
      var dock = PanelDock(layout: .init())
      dock.groups[0].floatingFrame = bad
      XCTAssertThrowsError(try dock.validate())
    }
  }

  @MainActor func testNativeHostsCloseRevealCollapseDockAndDoNotOwnDocuments() throws {
    let (controller, doc, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let bytes = try doc.data(ofType: CraftNSDocument.nativeType)
    library.floatPanels(.group("layers"), frame: frame)
    panels.synchronize()
    let host = try XCTUnwrap(panels.controllers["layers"])
    let window = try XCTUnwrap(host.window as? FloatingPanelWindow)
    XCTAssertFalse(window.canBecomeMain)
    XCTAssertTrue(window.canBecomeKey)
    XCTAssertTrue(window.becomesKeyOnlyIfNeeded)
    XCTAssertTrue(window.hidesOnDeactivate)
    XCTAssertTrue(window.isFloatingPanel)
    XCTAssertEqual(window.frame, frame.rect)
    XCTAssertEqual(window.title, "Layers")
    XCTAssertEqual(controller.documents.count, 1)
    XCTAssertEqual(doc.windowControllers.count, 0)
    XCTAssertFalse(doc.windowForSheet === window)
    XCTAssertTrue(window.documents?.activeDocument === doc)
    library.togglePanelGroup("layers")
    panels.synchronize()
    XCTAssertEqual(window.contentView?.bounds.height, 29)
    XCTAssertEqual(window.frame.maxY, frame.rect.maxY)
    XCTAssertEqual(library.panelDock.groups[2].floatingFrame, frame)
    library.togglePanelGroup("layers")
    panels.synchronize()
    XCTAssertEqual(window.frame, frame.rect)
    XCTAssertFalse(host.windowShouldClose(window))
    panels.synchronize()
    XCTAssertTrue(panels.controllers.isEmpty)
    XCTAssertEqual(controller.documents.count, 1)
    doc.store.reveal(LayersTab.channels)
    panels.synchronize()
    XCTAssertEqual(panels.controllers["layers"]?.window?.title, "Channels")
    XCTAssertEqual(library.panelDock.groups[2].floatingFrame, frame)
    XCTAssertTrue(library.movePanels(.group("layers"), to: .beforeGroup("color")))
    panels.synchronize()
    XCTAssertTrue(panels.controllers.isEmpty)
    XCTAssertEqual(try doc.data(ofType: CraftNSDocument.nativeType), bytes)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
  }

  @MainActor func testActiveDocumentAndKeyboardRoutingRetainTextResponderAndDialogOwner() throws {
    let (controller, a, panels) = try fixture()
    defer { cleanup(controller) }
    let b = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 4, height: 4, name: "Second"))
    controller.addDocument(b)
    b.makeWindowControllers()
    b.store.renderTask?.cancel()
    controller.workspaces.floatPanels(.group("color"), frame: frame)
    panels.synchronize()
    let window = try XCTUnwrap(panels.controllers["color"]?.window as? FloatingPanelWindow)
    func event(_ key: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "\t",
        charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: key)!
    }
    XCTAssertTrue(window.makeFirstResponder(window))
    window.sendEvent(event(48, [.control]))
    XCTAssertTrue(controller.currentDocument === a)
    XCTAssertTrue(window.documents?.activeDocument === a)
    XCTAssertTrue(a.windowForSheet === controller.documentWindows.applicationFrame?.window)
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
    let originalContent = try XCTUnwrap(window.contentView)
    let container = NSView(frame: originalContent.frame)
    window.contentView = container
    container.addSubview(originalContent)
    container.addSubview(text)
    XCTAssertTrue(window.makeFirstResponder(text))
    let visibility = a.store.workspace
    window.sendEvent(event(48, []))
    XCTAssertEqual(a.store.workspace, visibility, "Text input must not hide workspace panels")
    a.store.showAI = true
    window.sendEvent(event(48, [.control]))
    XCTAssertTrue(
      controller.currentDocument === a, "Document changes are blocked by an editing dialog")
    a.store.showAI = false
    controller.documentWindows.group(for: b)?.workspace.select(b)
    panels.synchronize()
    XCTAssertTrue(panels.controllers["color"]?.window === window)
    XCTAssertTrue(window.documents?.activeDocument === b)
    a.close()
    b.close()
    panels.synchronize()
    XCTAssertTrue(panels.controllers.isEmpty)
  }

  @MainActor func testVisibilityAndResetKeepFloatingGeometryAndScreenRecoveryDoesNotRewriteIt()
    throws
  {
    let (controller, doc, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let missing = FloatingPanelFrame(NSRect(x: -1500, y: 300, width: 322, height: 360))
    library.floatPanels(.group("color"), frame: missing)
    panels.synchronize()
    XCTAssertEqual(panels.controllers["color"]?.window?.frame.minX, 0)
    XCTAssertEqual(library.panelDock.groups[0].floatingFrame, missing)
    doc.store.workspace.togglePanels(includingTools: true)
    panels.synchronize()
    XCTAssertTrue(panels.controllers.isEmpty)
    doc.store.workspace.togglePanels(includingTools: true)
    panels.synchronize()
    XCTAssertNotNil(panels.controllers["color"])
    XCTAssertEqual(library.panelDock.groups[0].floatingFrame, missing)
    try library.setWorkspaceLocked(true)
    panels.synchronize()
    XCTAssertFalse(panels.controllers["color"]?.window?.isMovable ?? true)
    try library.reset()
    panels.synchronize()
    XCTAssertTrue(panels.controllers.isEmpty)
    XCTAssertEqual(library.layout, WorkspaceLayout())
  }

  @MainActor func testHostedFloatingTabsSelectAndNativePayloadDocksBack() throws {
    let (controller, doc, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    library.floatPanels(.group("color"), frame: frame)
    panels.synchronize()
    let window = try XCTUnwrap(panels.controllers["color"]?.window)
    let host = try XCTUnwrap(window.contentView)
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let tab = try XCTUnwrap(
      descendants(host).compactMap { $0 as? PanelDockTabButton }.first { $0.title == "Swatches" })
    let point = tab.convert(NSPoint(x: tab.bounds.midX, y: tab.bounds.midY), to: host.superview)
    let hit = host.hitTest(point)
    XCTAssertTrue(hit === tab || hit?.isDescendant(of: tab) == true)
    tab.performClick(nil)
    XCTAssertEqual(library.panelDock.groups[0].selected, .swatches)
    let payload = try XCTUnwrap(tab.payloadValue)
    XCTAssertEqual(payload.source, .panel(.swatches))
    XCTAssertTrue(library.acceptsPanelPayload(payload))
    let dockHost = NSHostingView(rootView: WorkspaceView(store: doc.store))
    dockHost.frame = NSRect(x: 0, y: 0, width: 1000, height: 650)
    let dockWindow = NSWindow(
      contentRect: dockHost.frame, styleMask: [.titled], backing: .buffered, defer: false)
    dockWindow.isReleasedWhenClosed = false
    dockWindow.contentView = dockHost
    defer { dockWindow.close() }
    dockHost.layoutSubtreeIfNeeded()
    let destination = try XCTUnwrap(
      descendants(dockHost).compactMap { $0 as? PanelDockTabButton }.first { $0.title == "Layers" })
    XCTAssertTrue(destination.drop(payload, false))
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "layers" }?.panels,
      [.swatches, .layers, .channels, .paths])
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "color" }?.panels, [.color, .gradients, .patterns])
    XCTAssertEqual(library.panelDock.groups.first { $0.id == "color" }?.floatingFrame, frame)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }
  @MainActor func testAutomaticReconciliationAndNativeResizeNotifications() async throws {
    let (controller, _, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    library.floatPanels(.group("layers"), frame: frame)
    for _ in 0..<30 where panels.controllers["layers"] == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let window = try XCTUnwrap(panels.controllers["layers"]?.window)
    let moved = NSRect(x: 600, y: 200, width: 400, height: 450)
    window.setFrame(moved, display: false)
    XCTAssertEqual(library.panelDock.groups[2].floatingFrame?.rect, moved)
    library.closePanels([.layers, .channels, .paths])
    for _ in 0..<30 where !panels.controllers.isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertTrue(
      panels.controllers.isEmpty,
      "Workspace changes must reconcile without a caller manually refreshing panels")
    library.selectPanel(.layers, reveal: true)
    for _ in 0..<30 where panels.controllers["layers"] == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(panels.controllers["layers"]?.window?.frame, moved)
  }

  @MainActor func testEmptyDockKeepsNativeReturnTargetAfterAllGroupsFloat() throws {
    let (controller, doc, panels) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    for group in library.panelDock.groups { library.floatPanels(.group(group.id), frame: frame) }
    panels.synchronize()
    XCTAssertEqual(panels.controllers.count, 4)
    XCTAssertTrue(library.panelDock.dockedGroups(library.layout.visibility).isEmpty)
    let host = NSHostingView(rootView: WorkspaceView(store: doc.store))
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 650)
    let window = NSWindow(
      contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let target = try XCTUnwrap(descendants(host).compactMap { $0 as? PanelDockDropView }.first)
    XCTAssertEqual(target.bounds.width, 12)
    XCTAssertGreaterThan(target.bounds.height, 500)
    let payload = PanelDockPayload(library: library.identity, source: .group("layers"))
    XCTAssertTrue(target.accepts(payload))
    XCTAssertTrue(target.drop(payload))
    panels.synchronize()
    XCTAssertEqual(panels.controllers.count, 3)
    XCTAssertEqual(library.panelDock.dockedGroups(library.layout.visibility).map(\.id), ["layers"])
  }

}
