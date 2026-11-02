import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class DocumentWorkspaceTests: XCTestCase {
  @MainActor func fixture(_ controller: CraftDocumentController, name: String) throws
    -> CraftNSDocument
  {
    _ = NSApplication.shared
    let document = CraftNSDocument(
      model: try CraftDocument(width: 8, height: 6, name: name))
    document.store.renderTask?.cancel()
    controller.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    return document
  }

  @MainActor func cleanup(_ controller: CraftDocumentController) {
    for document in controller.documents { document.close() }
  }

  @MainActor func testOpeningDocumentsSharesOneRealWindowAndRoutesActiveDocument() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let group = try XCTUnwrap(controller.documentWindows.current)
    let window = try XCTUnwrap(group.window)
    XCTAssertEqual(controller.documentWindows.groups.count, 1)
    XCTAssertEqual(group.workspace.documents.count, 2)
    XCTAssertTrue(a.windowForSheet === window)
    XCTAssertTrue(b.windowForSheet === window)
    XCTAssertTrue(controller.currentDocument === b)
    XCTAssertTrue(controller.document(for: window) === b)
    XCTAssertFalse(window.tabGroup?.isTabBarVisible == true)
    window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(window.frame.width, 1000)
    XCTAssertGreaterThanOrEqual(window.frame.height, 650)
    group.workspace.select(a)
    XCTAssertTrue(controller.currentDocument === a)
    XCTAssertTrue(controller.document(for: window) === a)
    XCTAssertEqual(window.title, "Photato - A")
    a.displayName = "Renamed document"
    XCTAssertEqual(window.title, "Photato - Renamed document")
    group.workspace.select(b)
    XCTAssertEqual(window.title, "Photato - B")
    controller.documentWindows.float(b)
    XCTAssertEqual(controller.documentWindows.current?.window?.title, "Photato - B")
    controller.documentWindows.consolidate()
    XCTAssertEqual(group.workspace.documents.count, 2)
  }

  @MainActor func testSwitchingPreservesIndependentUndoPixelsAndNativeSaveData() async throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let originalB = b.store.document
    a.store.perform(.visibility(a.store.document.layers[0].id, false))
    a.store.renderTask?.cancel()
    let changedA = a.store.document
    let group = try XCTUnwrap(controller.documentWindows.current)
    group.workspace.select(a)
    XCTAssertTrue(group.window?.isDocumentEdited == true)
    group.workspace.select(b)
    XCTAssertTrue(group.window?.isDocumentEdited == false)
    XCTAssertEqual(b.store.document, originalB)
    XCTAssertEqual(a.store.session.undoStack.count, 1)
    XCTAssertTrue(b.store.session.undoStack.isEmpty)
    XCTAssertEqual(try NativeArchive.decode(a.data(ofType: CraftNSDocument.nativeType)), changedA)
    XCTAssertEqual(try NativeArchive.decode(b.data(ofType: CraftNSDocument.nativeType)), originalB)
    group.workspace.select(a)
    await a.store.undo()
    a.store.renderTask?.cancel()
    XCTAssertTrue(a.store.document.layers[0].visible)
    XCTAssertEqual(b.store.document, originalB)
  }

  @MainActor func testApplicationReopenRaisesWorkspaceWithoutCreatingAnotherBlank() throws {
    let app = AppDelegate()
    defer { cleanup(app.controller) }
    let document = try fixture(app.controller, name: "Existing")
    XCTAssertTrue(app.applicationOpenUntitledFile(NSApp))
    XCTAssertFalse(app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
    XCTAssertEqual(app.controller.documents.count, 1)
    XCTAssertEqual(app.controller.documentWindows.groups.count, 1)
    XCTAssertTrue(app.controller.currentDocument === document)
  }

  @MainActor func testTabSwitchRetainsWorkspaceToolSettingsAndIndependentViewport() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    a.store.chooseTool(WorkspaceCatalog.tool("brush"))
    a.store.brush.size = 37
    a.store.brush.color = Pixel(0.25, 0.5, 0.75)
    a.store.workspace.collapsedDock = true
    a.store.layersTab = .channels
    a.store.zoom = 2
    a.store.pan = CGSize(width: 12, height: -8)
    let b = try fixture(controller, name: "B")
    XCTAssertEqual(b.store.tool, .brush)
    XCTAssertEqual(b.store.brush, a.store.brush)
    XCTAssertTrue(b.store.workspace.collapsedDock)
    XCTAssertEqual(b.store.layersTab, .channels)
    XCTAssertEqual(b.store.zoom, 0)
    XCTAssertEqual(b.store.pan, .zero)
    b.store.chooseTool(WorkspaceCatalog.tool("eraser"))
    let group = try XCTUnwrap(controller.documentWindows.current)
    group.workspace.select(a)
    XCTAssertEqual(a.store.tool, .eraser)
    XCTAssertEqual(a.store.zoom, 2)
    XCTAssertEqual(a.store.pan, CGSize(width: 12, height: -8))
    XCTAssertTrue(controller.documents.allSatisfy { !$0.isDocumentEdited })
  }

  @MainActor func testNativeWindowRoutesControlTabAndReverseWithoutDocumentEdits() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let c = try fixture(controller, name: "C")
    let group = try XCTUnwrap(controller.documentWindows.current)
    let window = try XCTUnwrap(group.window)
    func event(_ flags: NSEvent.ModifierFlags) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: flags,
          timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\t",
          charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    }
    window.sendEvent(try event(.control))
    XCTAssertTrue(controller.currentDocument === a)
    window.sendEvent(try event([.control, .shift]))
    XCTAssertTrue(controller.currentDocument === c)
    window.sendEvent(try event([.control, .shift]))
    XCTAssertTrue(controller.currentDocument === b)
    XCTAssertTrue(controller.documents.allSatisfy { !$0.isDocumentEdited })
  }

  @MainActor func testTabOrderReorderAndCycleWrapWithoutChangingDocuments() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let c = try fixture(controller, name: "C")
    let windows = controller.documentWindows
    let workspace = try XCTUnwrap(windows.current?.workspace)
    workspace.cycle(backwards: false)
    XCTAssertTrue(workspace.activeDocument === a)
    workspace.cycle(backwards: true)
    XCTAssertTrue(workspace.activeDocument === c)
    XCTAssertTrue(windows.moveTab(c.store.identity.uuidString, before: a))
    XCTAssertEqual(workspace.documents.map(\.displayName), ["C", "A", "B"])
    workspace.cycle(backwards: true)
    XCTAssertTrue(workspace.activeDocument === b)
    XCTAssertFalse(windows.moveTab("foreign payload", before: a))
    XCTAssertFalse(windows.moveTab(a.store.identity.uuidString, before: a))
    XCTAssertTrue(controller.documents.allSatisfy { !$0.isDocumentEdited })
  }

  @MainActor func testFloatMoveAcrossWindowsAndConsolidateRetainDocumentIdentity() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let c = try fixture(controller, name: "C")
    let windows = controller.documentWindows
    let originalWindow = a.windowForSheet
    windows.float(c)
    XCTAssertEqual(windows.groups.count, 2)
    XCTAssertFalse(c.windowForSheet === originalWindow)
    XCTAssertTrue(a.windowForSheet === b.windowForSheet)
    XCTAssertTrue(windows.moveTab(c.store.identity.uuidString, before: b))
    XCTAssertEqual(windows.groups.count, 1)
    XCTAssertEqual(windows.current?.workspace.documents.map(\.displayName), ["A", "C", "B"])
    windows.floatAll()
    XCTAssertEqual(windows.groups.count, 4)
    XCTAssertTrue(windows.applicationFrame?.workspace.documents.isEmpty == true)
    XCTAssertTrue(
      windows.groups.filter { $0.workspace.floating }.allSatisfy {
        $0.workspace.documents.count == 1
      })
    windows.consolidate()
    XCTAssertEqual(windows.groups.count, 1)
    XCTAssertEqual(
      Set(windows.current!.workspace.documents.map(\.store.identity)),
      Set([a, b, c].map(\.store.identity)))
    XCTAssertTrue(controller.currentDocument === c)
    XCTAssertEqual(controller.documents.count, 3)
    XCTAssertTrue(controller.documents.allSatisfy { !$0.isDocumentEdited })
  }

  @MainActor func testCloseReviewOfCleanTabLeavesOtherTabAndLastCloseRemovesWindow() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let windows = controller.documentWindows
    let closed = expectation(description: "Native NSDocument close review")
    windows.requestClose(b) { allowed in
      XCTAssertTrue(allowed)
      closed.fulfill()
    }
    waitForExpectations(timeout: 3)
    XCTAssertEqual(controller.documents.count, 1)
    XCTAssertTrue(controller.currentDocument === a)
    XCTAssertEqual(windows.groups.count, 1)
    a.close()
    XCTAssertTrue(controller.documents.isEmpty)
    XCTAssertTrue(windows.groups.isEmpty)
    XCTAssertNil(controller.currentDocument)
  }

  @MainActor func testSheetBlocksSwitchingFloatingReorderAndConsolidation() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let windows = controller.documentWindows
    let group = try XCTUnwrap(windows.current)
    let window = try XCTUnwrap(group.window)
    let sheet = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    sheet.isReleasedWhenClosed = false
    window.beginSheet(sheet)
    defer {
      window.endSheet(sheet)
      sheet.close()
    }
    group.workspace.select(a)
    XCTAssertTrue(group.workspace.activeDocument === b)
    windows.float(b)
    XCTAssertEqual(windows.groups.count, 1)
    XCTAssertFalse(windows.moveTab(b.store.identity.uuidString, before: a))
    windows.consolidate()
    XCTAssertEqual(group.workspace.documents.map(\.displayName), ["A", "B"])
  }

  @MainActor func testWindowMenuMaintainsNativeDocumentListWithoutAppKitHierarchy() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      defer { cleanup(app.controller) }
      let a = try fixture(app.controller, name: "A")
      let b = try fixture(app.controller, name: "B")
      let windowMenu = try XCTUnwrap(menu.item(withTitle: "Window")?.submenu)
      XCTAssertNil(NSApp.windowsMenu)
      app.menuNeedsUpdate(windowMenu)
      XCTAssertEqual(windowMenu.items.first?.title, "Arrange")
      XCTAssertNil(windowMenu.item(withTitle: "Move & Resize"))
      let rows = windowMenu.items.filter {
        $0.action == #selector(AppDelegate.selectDocumentWindow(_:))
      }
      XCTAssertEqual(rows.map(\.title), ["A", "B"])
      XCTAssertEqual(rows.map(\.state), [.off, .on])
      app.selectDocumentWindow(rows[0])
      XCTAssertTrue(app.controller.currentDocument === a)
      b.close()
      XCTAssertFalse(app.validateMenuItem(rows[1]))
      app.menuNeedsUpdate(windowMenu)
      XCTAssertEqual(
        windowMenu.items.filter { $0.action == #selector(AppDelegate.selectDocumentWindow(_:)) }
          .map(\.title), ["A"])
      let arrange = try XCTUnwrap(windowMenu.item(withTitle: "Arrange")?.submenu)
      XCTAssertEqual(
        arrange.item(withTitle: "Consolidate All to Tabs")?.action,
        #selector(AppDelegate.consolidateDocumentWindows))
      XCTAssertEqual(
        arrange.item(withTitle: "Float in Window")?.action,
        #selector(AppDelegate.floatDocumentWindow))
      XCTAssertEqual(
        arrange.item(withTitle: "Minimize")?.keyEquivalentModifierMask, [.command, .control])
      let auxiliary = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      auxiliary.isReleasedWhenClosed = false
      auxiliary.makeKeyAndOrderFront(nil)
      print(
        "WORKSPACE_TEST auxiliary key window:", NSApp.keyWindow === auxiliary,
        "actual:", NSApp.keyWindow?.title ?? "nil")
      app.close(window: auxiliary)
      XCTAssertFalse(auxiliary.isVisible)
      XCTAssertEqual(app.controller.documents.count, 1)
    }
  }
  @MainActor func testBeforeAfterInsertionAndLastSourceWindowRemovalKeepDocumentState() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let c = try fixture(controller, name: "C")
    let windows = controller.documentWindows
    let originals = [a, b, c].map { $0.store.document }
    XCTAssertTrue(windows.moveTab(a.store.identity.uuidString, relativeTo: c, after: true))
    XCTAssertEqual(windows.current?.workspace.documents.map(\.displayName), ["B", "C", "A"])
    XCTAssertTrue(windows.moveTab(a.store.identity.uuidString, relativeTo: b, after: false))
    XCTAssertEqual(windows.current?.workspace.documents.map(\.displayName), ["A", "B", "C"])
    windows.float(b)
    let oldWindow = b.windowForSheet
    XCTAssertTrue(windows.moveTab(b.store.identity.uuidString, relativeTo: c, after: true))
    XCTAssertEqual(windows.current?.workspace.documents.map(\.displayName), ["A", "C", "B"])
    XCTAssertEqual(windows.groups.count, 1)
    XCTAssertFalse(oldWindow?.isVisible == true)
    XCTAssertTrue(controller.currentDocument === b)
    XCTAssertEqual([a, b, c].map { $0.store.document }, originals)
    XCTAssertTrue(
      [a, b, c].allSatisfy { $0.store.session.undoStack.isEmpty && !$0.isDocumentEdited })
    XCTAssertFalse(windows.canMoveTab(b.store.identity.uuidString, to: b))
    XCTAssertFalse(windows.canMoveTab("foreign", to: b))
  }

  @MainActor func testNativeTabRejectsOrdinaryTextAndUnknownPrivatePayloads() throws {
    let button = DocumentTabButton()
    let board = NSPasteboard.withUniqueName()
    defer { board.clearContents() }
    button.acceptsTab = { $0 == "known-document" }
    board.setString("known-document", forType: .string)
    XCTAssertNil(button.payload(from: board))
    board.clearContents()
    board.setString("unknown", forType: DocumentTabButton.pasteboardType)
    XCTAssertNil(button.payload(from: board))
    board.clearContents()
    board.setString("known-document", forType: DocumentTabButton.pasteboardType)
    XCTAssertEqual(button.payload(from: board), "known-document")
    button.acceptsTab = { _ in false }
    XCTAssertNil(button.payload(from: board))
  }

  @MainActor func testNativeTabClickAndAccessibilityActionPreserveCloseIndependence() throws {
    let button = DocumentTabButton()
    button.frame = NSRect(x: 0, y: 0, width: 180, height: 26)
    var selected = 0
    button.selectTab = { selected += 1 }
    func event(_ type: NSEvent.EventType, x: CGFloat = 20) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: NSPoint(x: x, y: 10),
          modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
          eventNumber: 0, clickCount: 1, pressure: 1))
    }
    button.mouseDown(with: try event(.leftMouseDown))
    XCTAssertEqual(selected, 0)
    button.mouseDragged(with: try event(.leftMouseDragged, x: 21))
    button.mouseUp(with: try event(.leftMouseUp, x: 21))
    XCTAssertEqual(selected, 1)
    button.mouseUp(with: try event(.leftMouseUp))
    XCTAssertEqual(selected, 1)
    button.mouseDown(with: try event(.leftMouseDown))
    button.mouseUp(with: try event(.leftMouseUp, x: 200))
    XCTAssertEqual(selected, 1)
    button.performClick(nil)
    XCTAssertEqual(selected, 2)
  }

  @MainActor func testHostedTabHitTestingTargetsNativeButtonsAboveCanvas() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "Hit A")
    let b = try fixture(controller, name: "Hit B")
    let root = try XCTUnwrap(controller.documentWindows.current?.window?.contentView)
    func buttons(_ view: NSView) -> [DocumentTabButton] {
      (view as? DocumentTabButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
    let deadline = Date().addingTimeInterval(1)
    while buttons(root).count != 2 && Date() < deadline {
      root.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let tabs = buttons(root)
    XCTAssertEqual(tabs.count, 2)
    XCTAssertEqual(Set(tabs.map(\.documentID)), Set([a, b].map { $0.store.identity.uuidString }))
    for button in tabs {
      XCTAssertGreaterThan(button.bounds.width, 20)
      XCTAssertGreaterThan(button.bounds.height, 10)
      // NSView.hitTest takes coordinates in its superview, whose vertical axis may differ.
      let parent = try XCTUnwrap(root.superview)
      let point = parent.convert(
        NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
      let hit = root.hitTest(point)
      XCTAssertTrue(hit === button, "Tab pointer hit must not fall through to the canvas")
    }
  }

  @MainActor func testSingleDocumentFloatsWithRetainedFrameAndConsolidatesIntoOriginalWindow()
    throws
  {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let document = try fixture(controller, name: "Only")
    document.store.zoom = 1.5
    document.store.pan = CGSize(width: 3, height: -2)
    let windows = controller.documentWindows
    let frame = try XCTUnwrap(windows.applicationFrame)
    let original = document.store.document
    windows.float(document)
    let floating = try XCTUnwrap(windows.group(for: document))
    XCTAssertTrue(floating.workspace.floating)
    XCTAssertTrue(frame.workspace.documents.isEmpty)
    XCTAssertNil(frame.workspace.activeDocument)
    XCTAssertTrue(frame.window?.isVisible == true)
    XCTAssertEqual(windows.groups.count, 2)
    XCTAssertTrue(controller.currentDocument === document)
    XCTAssertTrue(controller.document(for: try XCTUnwrap(frame.window)) === document)
    XCTAssertTrue(document.windowForSheet === floating.window)
    XCTAssertTrue(floating.window?.parent === frame.window)
    XCTAssertLessThan(try XCTUnwrap(floating.window).frame.width, 1000)
    XCTAssertEqual(document.store.zoom, 1.5)
    XCTAssertEqual(document.store.pan, CGSize(width: 3, height: -2))
    windows.float(document)
    XCTAssertEqual(windows.groups.count, 2)
    windows.consolidate()
    XCTAssertEqual(windows.groups.count, 1)
    XCTAssertTrue(windows.current === frame)
    XCTAssertTrue(document.windowForSheet === frame.window)
    XCTAssertNil(floating.window?.parent)
    XCTAssertEqual(document.store.document, original)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testSharedPanelsKeepFloatingTargetWhenFrameBecomesKeyAndNewDocumentsDock() throws
  {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "Docked")
    let b = try fixture(controller, name: "Floating")
    let windows = controller.documentWindows
    let frame = try XCTUnwrap(windows.applicationFrame)
    b.store.brush.size = 43
    b.store.workspace.collapsedDock = true
    windows.float(b)
    let floating = try XCTUnwrap(windows.group(for: b))
    frame.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
    XCTAssertTrue(controller.currentDocument === b)
    XCTAssertTrue(frame.workspace.activeDocument === a)
    XCTAssertTrue(controller.document(for: try XCTUnwrap(frame.window)) === b)
    frame.workspace.select(a)
    XCTAssertTrue(controller.currentDocument === a)
    XCTAssertEqual(a.store.brush.size, 43)
    XCTAssertTrue(a.store.workspace.collapsedDock)
    a.store.brush.size = 17
    floating.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
    XCTAssertTrue(controller.currentDocument === b)
    XCTAssertEqual(b.store.brush.size, 17)
    let c = try fixture(controller, name: "New")
    XCTAssertTrue(windows.group(for: c) === frame)
    XCTAssertTrue(controller.currentDocument === c)
    XCTAssertEqual(c.store.brush.size, 17)
    XCTAssertTrue([a, b, c].allSatisfy { !$0.isDocumentEdited })
  }

  @MainActor func testFrameSheetAndPendingDialogBlockCrossWindowTargetChanges() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "Docked")
    let b = try fixture(controller, name: "Floating")
    let windows = controller.documentWindows
    windows.float(b)
    let frame = try XCTUnwrap(windows.applicationFrame)
    let window = try XCTUnwrap(frame.window)
    b.store.showAI = true
    XCTAssertFalse(windows.activate(a))
    frame.workspace.select(a)
    XCTAssertTrue(controller.currentDocument === b)
    windows.consolidate()
    XCTAssertEqual(windows.groups.count, 2)
    b.store.showAI = false
    let sheet = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    sheet.isReleasedWhenClosed = false
    window.beginSheet(sheet)
    XCTAssertFalse(windows.activate(a))
    windows.floatAll()
    XCTAssertEqual(windows.groups.count, 2)
    window.endSheet(sheet)
    sheet.close()
    XCTAssertTrue(windows.activate(a))
    XCTAssertTrue(controller.currentDocument === a)
  }

  @MainActor func testFloatingHostContainsOnlyItsCanvasAndFrameKeepsDockedCanvas() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "Docked")
    let b = try fixture(controller, name: "Floating")
    let windows = controller.documentWindows
    windows.float(b)
    let frame = try XCTUnwrap(windows.applicationFrame?.window?.contentView)
    let floating = try XCTUnwrap(windows.group(for: b)?.window?.contentView)
    func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }
    let deadline = Date().addingTimeInterval(1)
    while Date() < deadline {
      frame.layoutSubtreeIfNeeded()
      floating.layoutSubtreeIfNeeded()
      if descendants(frame, CraftCanvas.self).count == 1
        && descendants(floating, CraftCanvas.self).count == 1
      {
        break
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    let dockedCanvas = try XCTUnwrap(descendants(frame, CraftCanvas.self).first)
    let floatingCanvas = try XCTUnwrap(descendants(floating, CraftCanvas.self).first)
    XCTAssertTrue(dockedCanvas.store === a.store)
    XCTAssertTrue(floatingCanvas.store === b.store)
    XCTAssertEqual(descendants(frame, DocumentTabButton.self).count, 1)
    XCTAssertTrue(descendants(floating, DocumentTabButton.self).isEmpty)
    XCTAssertTrue(dockedCanvas.activateDocument())
    XCTAssertTrue(controller.currentDocument === a)
    XCTAssertTrue(floatingCanvas.activateDocument())
    XCTAssertTrue(controller.currentDocument === b)
    XCTAssertFalse(a.isDocumentEdited)
    XCTAssertFalse(b.isDocumentEdited)
  }

  @MainActor func testCycleTraversesFloatingDocumentsAndClosingFrameReviewsAllDocuments() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    let windows = controller.documentWindows
    let frame = try XCTUnwrap(windows.applicationFrame)
    windows.float(b)
    windows.cycle(backwards: false)
    XCTAssertTrue(controller.currentDocument === a)
    windows.cycle(backwards: true)
    XCTAssertTrue(controller.currentDocument === b)
    windows.closeGroup(frame)
    let deadline = Date().addingTimeInterval(2)
    while !controller.documents.isEmpty && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    XCTAssertTrue(controller.documents.isEmpty)
    XCTAssertTrue(windows.groups.isEmpty)
    XCTAssertNil(windows.activeDocument)
  }

  @MainActor func testFrameKeyboardInputTargetsFloatingCanvasButRetainsTextFieldResponder() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "Docked")
    let b = try fixture(controller, name: "Floating")
    let windows = controller.documentWindows
    windows.float(b)
    let frame = try XCTUnwrap(windows.applicationFrame?.window)
    let floating = try XCTUnwrap(windows.group(for: b)?.window)
    // Install actual native responders without depending on asynchronous SwiftUI creation.
    let canvasA = CraftCanvas(store: a.store)
    let canvasB = CraftCanvas(store: b.store)
    frame.contentView?.addSubview(canvasA)
    floating.contentView?.addSubview(canvasB)
    frame.makeFirstResponder(canvasA)
    floating.makeFirstResponder(canvasB)
    let tab = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: frame.windowNumber, context: nil,
        characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
    let handDown = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: frame.windowNumber, context: nil, characters: " ",
        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
    frame.sendEvent(handDown)
    XCTAssertFalse(canvasA.spaceHeld)
    XCTAssertTrue(
      canvasB.spaceHeld, "The frame forwards canvas keys to the active floating document")
    let handUp = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyUp, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: frame.windowNumber, context: nil, characters: " ",
        charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
    frame.sendEvent(handUp)
    XCTAssertFalse(canvasB.spaceHeld)
    let initialA = a.store.workspace
    let initialB = b.store.workspace
    frame.sendEvent(tab)
    XCTAssertNotEqual(a.store.workspace, initialA)
    XCTAssertEqual(a.store.workspace, b.store.workspace)
    XCTAssertNotEqual(b.store.workspace, initialB)
    XCTAssertTrue(controller.currentDocument === b)
    let field = RecordingWorkspaceTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
    frame.contentView?.addSubview(field)
    frame.makeFirstResponder(field)
    let afterTab = b.store.workspace
    frame.sendEvent(tab)
    XCTAssertEqual(field.receivedKeys, [48])
    XCTAssertEqual(b.store.workspace, afterTab)
    XCTAssertTrue(controller.currentDocument === b)
  }

  @MainActor func testClosingActiveFloatKeepsLatestSharedToolSettingsOnRemainingDocument() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    let a = try fixture(controller, name: "A")
    let b = try fixture(controller, name: "B")
    controller.documentWindows.float(b)
    b.store.brush.size = 81
    b.store.chooseTool(WorkspaceCatalog.tool("eraser"))
    b.close()
    XCTAssertTrue(controller.currentDocument === a)
    XCTAssertEqual(a.store.brush.size, 81)
    XCTAssertEqual(a.store.tool, .eraser)
    XCTAssertFalse(a.isDocumentEdited)
  }

  @MainActor func testEmptyFloatingHostNeverCreatesSharedEditingControls() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { cleanup(controller) }
    _ = try fixture(controller, name: "Active frame document")
    let transient = DocumentWorkspace(floating: true)
    transient.owner = controller.documentWindows
    let host = DocumentWorkspaceController(workspace: transient)
    defer {
      host.window?.delegate = nil
      host.close()
    }
    let root = try XCTUnwrap(host.window?.contentView)
    root.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    root.layoutSubtreeIfNeeded()
    func controls(_ view: NSView) -> [NSControl] {
      (view as? NSControl).map { [$0] } ?? view.subviews.flatMap(controls)
    }
    XCTAssertTrue(
      controls(root).isEmpty,
      "An unassigned floating host must not briefly mount the active document’s shared controls")
    XCTAssertTrue(controller.currentDocument === controller.documentWindows.activeDocument)
  }

}

/// Observe native responder dispatch without invoking process-global text services in XCTest.
@MainActor private final class RecordingWorkspaceTextView: NSTextView {
  var receivedKeys: [UInt16] = []
  override func keyDown(with event: NSEvent) { receivedKeys.append(event.keyCode) }
}
