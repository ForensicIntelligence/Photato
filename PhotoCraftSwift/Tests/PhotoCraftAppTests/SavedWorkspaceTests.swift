import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class SavedWorkspaceTests: XCTestCase {
  func temporaryURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    return directory.appendingPathComponent("Workspaces.json")
  }

  @MainActor func testSavedResetTargetAndLastUsedLayoutPersistIndependently() throws {
    let url = try temporaryURL()
    let library = WorkspaceLibrary(persistenceURL: url)
    library.layout.dockWidth = 390
    library.layout.doubleTools = true
    library.layout.colorTab = .gradients
    try library.save(name: " Retouch ")
    let saved = library.layout
    library.layout.dockWidth = 280
    library.layout.visibility.properties = false
    let lastUsed = library.layout
    try library.select("Essentials")
    XCTAssertEqual(library.layout.dockWidth, 390, "Switch restores the last-used Essentials layout")
    try library.reset()
    XCTAssertEqual(library.layout, WorkspaceLayout())
    try library.select("Retouch")
    XCTAssertEqual(library.layout, lastUsed)
    let reopened = WorkspaceLibrary(persistenceURL: url)
    XCTAssertNil(reopened.error)
    XCTAssertEqual(reopened.activeName, "Retouch")
    XCTAssertEqual(reopened.layout, lastUsed)
    try reopened.reset()
    XCTAssertEqual(reopened.layout, saved)
    XCTAssertEqual(WorkspaceLibrary(persistenceURL: url).layout, saved)
  }

  @MainActor func testNamesReplacementAndDeleteGuardsKeepExistingWorkspaces() throws {
    let library = WorkspaceLibrary()
    for name in [
      "", "   ", "Essentials", "photography", "Essentials (Default)", "bad\nname",
      String(repeating: "x", count: 257),
    ] {
      XCTAssertThrowsError(try library.save(name: name), name)
    }
    try library.save(name: "Retouch")
    let original = library.state
    XCTAssertThrowsError(try library.save(name: "RETOUCH"))
    XCTAssertThrowsError(try library.delete("Retouch"))
    XCTAssertThrowsError(try library.delete("Essentials"))
    XCTAssertThrowsError(try library.select("Missing"))
    XCTAssertEqual(library.state, original)
    library.layout.dockWidth = 401
    try library.save(name: "Retouch", replacing: true)
    library.layout.dockWidth = 300
    try library.reset()
    XCTAssertEqual(library.layout.dockWidth, 401)
    try library.save(name: "Design/Print")
    try library.delete("Retouch")
    XCTAssertEqual(library.customNames, ["Design/Print"])
    XCTAssertEqual(library.activeName, "Design/Print")
  }

  @MainActor func testWriteFailureDoesNotPublishPresetOrReplacePreviousFile() throws {
    enum Failure: Error { case injected }
    let url = try temporaryURL()
    let first = WorkspaceLibrary(persistenceURL: url)
    try first.save(name: "Kept")
    let original = try Data(contentsOf: url)
    let failing = WorkspaceLibrary(persistenceURL: url, writer: { _, _ in throw Failure.injected })
    let state = failing.state
    XCTAssertThrowsError(try failing.save(name: "Unsaved"))
    XCTAssertThrowsError(try failing.select("Essentials"))
    XCTAssertEqual(failing.state, state)
    XCTAssertEqual(try Data(contentsOf: url), original)
    failing.layout.doubleTools = true
    XCTAssertThrowsError(try failing.flush())
    XCTAssertNotNil(failing.error)
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  @MainActor func testMalformedUnknownAndOversizedFilesArePreserved() throws {
    let url = try temporaryURL()
    var wrongVersion = WorkspaceState()
    wrongVersion.version = 2
    var missingActive = WorkspaceState()
    missingActive.active = "Missing"
    var dimensions = WorkspaceState()
    dimensions.workspaces[0].lastUsed.dockWidth = -1
    var duplicate = WorkspaceState()
    duplicate.workspaces.append(duplicate.workspaces[0])
    var overwrittenFactory = WorkspaceState()
    overwrittenFactory.workspaces[0].saved.doubleTools = true
    let encoder = JSONEncoder()
    let invalid =
      try [wrongVersion, missingActive, dimensions, duplicate, overwrittenFactory].map(
        encoder.encode)
      + [Data("invalid JSON".utf8), Data(repeating: 32, count: WorkspaceState.maximumBytes + 1)]
    for bytes in invalid {
      try bytes.write(to: url)
      let library = WorkspaceLibrary(persistenceURL: url)
      XCTAssertNotNil(library.error)
      XCTAssertEqual(library.layout, WorkspaceLayout())
      XCTAssertThrowsError(try library.save(name: "Must not overwrite"))
      XCTAssertThrowsError(try library.flush())
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }

  @MainActor func testRapidLayoutChangesCoalesceAndAutosaveFinalArrangement() async throws {
    let url = try temporaryURL()
    let saved = expectation(description: "Debounced layout written")
    saved.assertForOverFulfill = true
    var writes = 0
    let library = WorkspaceLibrary(
      persistenceURL: url,
      writer: { data, url in
        try data.write(to: url, options: .atomic)
        writes += 1
        saved.fulfill()
      })
    for width in 280...400 { library.resizeDock(to: Double(width)) }
    library.layout.layersTab = .paths
    await fulfillment(of: [saved], timeout: 3)
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(WorkspaceLibrary(persistenceURL: url).layout, library.layout)
  }

  @MainActor func testAllControllerDocumentsShareLayoutWithoutEditingOrChangingViewport() throws {
    let library = WorkspaceLibrary()
    let controller = CraftDocumentController(workspaces: library)
    XCTAssertTrue(controller.workspaces === library)
    let a = CraftNSDocument(model: try CraftDocument(width: 3, height: 4))
    let b = CraftNSDocument(model: try CraftDocument(width: 5, height: 6))
    defer {
      controller.removeDocument(a)
      controller.removeDocument(b)
    }
    for document in [a, b] {
      document.store.renderTask?.cancel()
      controller.addDocument(document)
    }
    let pixelsA = try a.data(ofType: CraftNSDocument.nativeType)
    let pixelsB = try b.data(ofType: CraftNSDocument.nativeType)
    a.store.zoom = 3.25
    a.store.pan = CGSize(width: 9, height: -4)
    b.store.zoom = 0.75
    b.store.pan = CGSize(width: -2, height: 6)
    a.store.workspace.color = false
    a.store.colorTab = .patterns
    library.resizeDock(to: 409)
    XCTAssertFalse(b.store.workspace.color)
    XCTAssertEqual(b.store.colorTab, .patterns)
    XCTAssertEqual(WorkspaceView(store: b.store).dockWidth, 409)
    try library.save(name: "Shared")
    b.store.workspace.layers = false
    try library.reset()
    XCTAssertTrue(a.store.workspace.layers)
    XCTAssertFalse(a.store.workspace.color)
    try library.select("Essentials")
    try library.reset()
    XCTAssertEqual(a.store.workspace, WorkspaceVisibility())
    XCTAssertEqual(try a.data(ofType: CraftNSDocument.nativeType), pixelsA)
    XCTAssertEqual(try b.data(ofType: CraftNSDocument.nativeType), pixelsB)
    XCTAssertEqual(a.store.zoom, 3.25)
    XCTAssertEqual(a.store.pan, CGSize(width: 9, height: -4))
    XCTAssertEqual(b.store.zoom, 0.75)
    XCTAssertEqual(b.store.pan, CGSize(width: -2, height: 6))
    for document in [a, b] {
      XCTAssertFalse(document.isDocumentEdited)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
    controller.removeDocument(a)
    controller.removeDocument(b)
    library.layout.doubleTools = true
    controller.addDocument(a)
    XCTAssertTrue(WorkspaceView(store: a.store).doubleTools)
    // Asking AppKit for the controller again must preserve application state.
    XCTAssertTrue(CraftDocumentController() === controller)
    XCTAssertTrue(CraftDocumentController().workspaces === library)
  }

  @MainActor func testWorkspaceMenuDispatchCheckmarksDynamicResetAndDraftGuard() throws {
    try PhotoshopMenuTests().withMenus { app, _ in
      let menu = try XCTUnwrap(app.workspaceMenu)
      let library = app.controller.workspaces
      let essentials = try XCTUnwrap(menu.item(withTitle: "Essentials (Default)"))
      let reset = try XCTUnwrap(menu.item(withTitle: "Reset Essentials"))
      let delete = try XCTUnwrap(menu.item(withTitle: "Delete Workspace…"))
      XCTAssertTrue(app.validateMenuItem(essentials))
      XCTAssertEqual(essentials.state, .on)
      XCTAssertFalse(app.validateMenuItem(delete))
      try library.save(name: "Retouch")
      library.layout.dockWidth = 409
      app.menuNeedsUpdate(menu)
      app.menuNeedsUpdate(menu)
      XCTAssertEqual(menu.items.filter { $0.title == "Retouch" }.count, 1)
      XCTAssertEqual(reset.title, "Reset Retouch")
      let custom = try XCTUnwrap(menu.item(withTitle: "Retouch"))
      XCTAssertTrue(app.validateMenuItem(custom))
      XCTAssertEqual(custom.state, .on)
      menu.performActionForItem(at: menu.index(of: reset))
      XCTAssertEqual(library.layout.dockWidth, 322)
      menu.performActionForItem(at: menu.index(of: essentials))
      XCTAssertEqual(library.activeName, "Essentials")
      XCTAssertTrue(app.validateMenuItem(delete))
      menu.performActionForItem(at: menu.index(of: custom))
      XCTAssertEqual(library.activeName, "Retouch")
      let document = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      document.store.renderTask?.cancel()
      app.controller.addDocument(document)
      app.controller.documentWindows.activeDocument = document
      defer {
        app.controller.documentWindows.activeDocument = nil
        app.controller.removeDocument(document)
      }
      document.store.geometryBusy = true
      XCTAssertFalse(app.validateMenuItem(essentials))
      app.selectEssentialsWorkspace()
      XCTAssertEqual(library.activeName, "Retouch")
      XCTAssertEqual(
        menu.item(withTitle: "Lock Workspace")?.action, #selector(AppDelegate.lockWorkspace))
      XCTAssertNil(menu.item(withTitle: "Photography")?.action)
    }
  }

  @MainActor func testNativeWorkspaceDialogsExposeOnlySupportedCaptureAndDeletionChoices() throws {
    _ = NSApplication.shared
    let app = AppDelegate()
    try app.controller.workspaces.save(name: "Retouch")
    try app.controller.workspaces.save(name: "Print")
    let (new, name) = app.makeNewWorkspaceAlert()
    let (delete, picker) = app.makeDeleteWorkspaceAlert()
    XCTAssertEqual(name.accessibilityLabel(), "Workspace name")
    XCTAssertEqual(picker.itemTitles, ["Retouch"])
    let stack = try XCTUnwrap(new.accessoryView as? NSStackView)
    let capture = stack.arrangedSubviews.compactMap { $0 as? NSButton }
    XCTAssertEqual(
      capture.map(\.title), ["Panel Locations", "Keyboard Shortcuts", "Menus", "Toolbar"])
    XCTAssertEqual(capture.map(\.state), [.on, .off, .off, .off])
    XCTAssertTrue(capture.allSatisfy { !$0.isEnabled })
    XCTAssertEqual(new.buttons.map(\.title), ["Save", "Cancel"])
    XCTAssertEqual(delete.buttons.map(\.title), ["Delete", "Cancel"])
    if let output = ProcessInfo.processInfo.environment["PHOTATO_WORKSPACE_LAYOUT_OUTPUT"] {
      for (name, alert) in [("new-workspace", new), ("delete-workspace", delete)] {
        alert.window.appearance = NSAppearance(named: .darkAqua)
        alert.layout()
        let view = try XCTUnwrap(alert.window.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
      }
    }
  }
}
