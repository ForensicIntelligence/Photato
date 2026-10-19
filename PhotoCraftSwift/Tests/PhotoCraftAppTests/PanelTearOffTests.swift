import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

@MainActor private final class PanelDragInfo: NSObject, NSDraggingInfo {
  let draggingPasteboard = NSPasteboard.withUniqueName()
  var draggingDestinationWindow: NSWindow?
  var draggingSourceOperationMask: NSDragOperation = .move
  var draggingLocation = NSPoint(x: 100, y: 120)
  var draggedImageLocation: NSPoint { draggingLocation }
  nonisolated var draggedImage: NSImage? { nil }
  var draggingSource: Any? { nil }
  var draggingSequenceNumber = 1
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 1
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }
  func slideDraggedImage(to screenPoint: NSPoint) {}
  nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL)
    -> [String]?
  {
    nil
  }
  func enumerateDraggingItems(
    options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}
  func resetSpringLoading() {}
  func write(_ payload: PanelDockPayload) {
    draggingPasteboard.clearContents()
    let item = NSPasteboardItem()
    payload.write(to: item)
    draggingPasteboard.writeObjects([item])
  }
}

final class PanelTearOffTests: XCTestCase {
  @MainActor func fixture() throws -> (
    CraftDocumentController, CraftNSDocument, PanelTearOffCoordinator
  ) {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let document = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 8, height: 6, name: "Drag fixture"))
    controller.addDocument(document)
    document.makeWindowControllers()
    document.store.renderTask?.cancel()
    controller.documentWindows.floatingPanels.presentsWindows = false
    let drag = controller.documentWindows.panelDragging
    drag.presentsBackdrops = false
    drag.screenFrames = {
      [
        NSRect(x: -1280, y: 0, width: 1280, height: 800),
        NSRect(x: 0, y: 0, width: 1440, height: 900),
      ]
    }
    return (controller, document, drag)
  }
  @MainActor func cleanup(_ controller: CraftDocumentController) {
    let windows = controller.documentWindows
    windows.panelDragging.finish()
    windows.panelDragging.presentsBackdrops = true
    windows.panelDragging.screenFrames = { NSScreen.screens.map(\.frame) }
    windows.floatingPanels.presentsWindows = true
    for document in controller.documents { document.close() }
  }
  @MainActor func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
  }

  @MainActor func testCancelledTearOffLeavesLayoutBytesUndoAndTemporaryWindowsUnchanged() throws {
    let (controller, document, drag) = try fixture()
    defer { cleanup(controller) }
    let original = controller.workspaces.layout
    let bytes = try document.data(ofType: CraftNSDocument.nativeType)
    let payload = PanelDockPayload(
      library: controller.workspaces.identity, source: .panel(.gradients))
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 18, y: 32)))
    XCTAssertEqual(drag.backdrops.count, 2)
    XCTAssertEqual(drag.backdrops.map(\.frame), drag.screenFrames())
    for window in drag.backdrops {
      XCTAssertFalse(window.canBecomeMain)
      XCTAssertFalse(window.canBecomeKey)
      XCTAssertFalse(window.hasShadow)
      XCTAssertFalse(window.isOpaque)
      XCTAssertTrue(window.isExcludedFromWindowsMenu)
      XCTAssertFalse(window.isVisible, "Test must not show desktop surfaces")
    }
    XCTAssertEqual(
      controller.workspaces.layout, original, "Beginning a drag must not detach a panel")
    drag.finish()
    XCTAssertNil(drag.activePayload)
    XCTAssertTrue(drag.backdrops.isEmpty)
    XCTAssertFalse(drag.drop(payload, at: NSPoint(x: 400, y: 600)))
    XCTAssertEqual(controller.workspaces.layout, original)
    XCTAssertEqual(try document.data(ofType: CraftNSDocument.nativeType), bytes)
    XCTAssertTrue(document.store.session.undoStack.isEmpty)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testCommittedPanelAndGroupDropsPreserveGrabAnchorAndFloatingSize() throws {
    let (controller, _, drag) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let panel = PanelDockPayload(library: library.identity, source: .panel(.gradients))
    XCTAssertTrue(drag.begin(panel, anchor: NSPoint(x: 18, y: 32)))
    XCTAssertTrue(drag.drop(panel, at: NSPoint(x: -800, y: 620)))
    let group = try XCTUnwrap(library.panelDock.groups.first { $0.panels == [.gradients] })
    XCTAssertEqual(group.floatingFrame?.rect, NSRect(x: -818, y: 350, width: 322, height: 302))
    XCTAssertFalse(
      drag.drop(panel, at: .zero), "A second callback cannot commit against a changed layout")
    drag.finish()
    let payload = PanelDockPayload(library: library.identity, source: .group(group.id))
    library.recordFloatingPanelFrame(
      group.id, frame: NSRect(x: -800, y: 200, width: 450, height: 550))
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 10, y: 30)))
    XCTAssertTrue(drag.drop(payload, at: NSPoint(x: 200, y: 750)))
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == group.id }?.floatingFrame?.rect,
      NSRect(x: 190, y: 230, width: 450, height: 550))
    try library.panelDock.validate()
  }

  @MainActor func testRejectsForeignStaleLockedModalAndNonfiniteDrops() throws {
    let (controller, document, drag) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let payload = PanelDockPayload(library: library.identity, source: .group("layers"))
    XCTAssertFalse(drag.begin(.init(library: UUID(), source: .group("layers")), anchor: .zero))
    XCTAssertFalse(drag.begin(payload, anchor: NSPoint(x: CGFloat.nan, y: 0)))
    XCTAssertTrue(drag.begin(payload, anchor: .zero))
    XCTAssertFalse(drag.accepts(.init(library: library.identity, source: .group("color"))))
    XCTAssertFalse(drag.drop(payload, at: NSPoint(x: CGFloat.infinity, y: 100)))
    XCTAssertFalse(drag.drop(payload, at: NSPoint(x: 100001, y: 100)))
    try library.setWorkspaceLocked(true)
    XCTAssertFalse(drag.accepts(payload))
    XCTAssertFalse(drag.drop(payload, at: NSPoint(x: 400, y: 400)))
    try library.setWorkspaceLocked(false)
    document.store.showAI = true
    XCTAssertFalse(drag.accepts(payload))
    document.store.showAI = false
    library.selectPanel(.paths)
    XCTAssertFalse(drag.accepts(payload), "A changed layout invalidates the captured drag")
    XCTAssertTrue(drag.begin(payload, anchor: .zero))
    try library.save(name: "Other workspace")
    XCTAssertFalse(
      drag.accepts(payload), "Changing workspace with identical layout still cancels the old drag")
    XCTAssertTrue(drag.begin(payload, anchor: .zero))
    let second = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 4, height: 4))
    controller.addDocument(second)
    second.makeWindowControllers()
    second.store.renderTask?.cancel()
    XCTAssertFalse(
      drag.accepts(payload), "A different active document cannot receive an old panel drag")
    XCTAssertNil(drag.activePayload)
    XCTAssertTrue(
      drag.backdrops.isEmpty, "Changing documents immediately retires temporary desktop targets")
    XCTAssertNil(library.panelDock.groups.first { $0.id == "layers" }?.floatingFrame)
  }

  @MainActor func testAncestorReceiverUsesNativePasteboardAndScreenCoordinates() throws {
    let (controller, _, drag) = try fixture()
    defer { cleanup(controller) }
    let payload = PanelDockPayload(
      library: controller.workspaces.identity, source: .panel(.patterns))
    let frameWindow = try XCTUnwrap(controller.documentWindows.applicationFrame?.window)
    let receiver = try XCTUnwrap(frameWindow.contentView as? PanelTearOffContainer)
    let info = PanelDragInfo()
    info.draggingDestinationWindow = frameWindow
    info.write(payload)
    defer { info.draggingPasteboard.releaseGlobally() }
    XCTAssertEqual(receiver.draggingEntered(info), [])
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 5, y: 30)))
    XCTAssertEqual(receiver.draggingEntered(info), .move)
    XCTAssertTrue(receiver.prepareForDragOperation(info))
    let point = frameWindow.convertPoint(toScreen: info.draggingLocation)
    XCTAssertTrue(receiver.performDragOperation(info))
    let floating = try XCTUnwrap(
      controller.workspaces.panelDock.groups.first { $0.panels == [.patterns] }?.floatingFrame)
    XCTAssertEqual(floating.x, point.x - 5)
    XCTAssertEqual(floating.rect.maxY, point.y + 30)
    XCTAssertEqual(receiver.draggingUpdated(info), [])
  }

  @MainActor func testCommandOverNativeTabFloatsWhileOrdinaryDropGroups() throws {
    let (controller, _, drag) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let window = try XCTUnwrap(controller.documentWindows.applicationFrame?.window)
    let content = try XCTUnwrap(window.contentView)
    content.layoutSubtreeIfNeeded()
    let target = try XCTUnwrap(
      descendants(content).compactMap { $0 as? PanelDockTabButton }.first { $0.title == "Layers" })
    let payload = PanelDockPayload(library: library.identity, source: .panel(.gradients))
    let info = PanelDragInfo()
    info.draggingDestinationWindow = window
    info.write(payload)
    info.draggingLocation = target.convert(NSPoint(x: 2, y: 10), to: nil)
    defer { info.draggingPasteboard.releaseGlobally() }
    XCTAssertTrue(drag.begin(payload, anchor: .zero))
    target.dragModifiers = { [] }
    XCTAssertEqual(target.draggingEntered(info), .move)
    XCTAssertTrue(target.prepareForDragOperation(info))
    XCTAssertTrue(target.performDragOperation(info))
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "layers" }?.panels,
      [.gradients, .layers, .channels, .paths])
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 7, y: 30)))
    target.dragModifiers = { [.command] }
    XCTAssertEqual(target.draggingUpdated(info), .move)
    XCTAssertTrue(target.prepareForDragOperation(info))
    XCTAssertTrue(target.performDragOperation(info))
    XCTAssertNotNil(library.panelDock.groups.first { $0.panels == [.gradients] }?.floatingFrame)
    XCTAssertEqual(
      library.panelDock.groups.first { $0.id == "layers" }?.panels, [.layers, .channels, .paths])
  }

  @MainActor func testCommandOverBoundaryFloatsWithoutInsertionHighlight() throws {
    let (controller, _, drag) = try fixture()
    defer { cleanup(controller) }
    let window = try XCTUnwrap(controller.documentWindows.applicationFrame?.window)
    let content = try XCTUnwrap(window.contentView)
    content.layoutSubtreeIfNeeded()
    let target = try XCTUnwrap(descendants(content).compactMap { $0 as? PanelDockDropView }.first)
    let payload = PanelDockPayload(library: controller.workspaces.identity, source: .group("color"))
    let info = PanelDragInfo()
    info.write(payload)
    info.draggingDestinationWindow = window
    defer { info.draggingPasteboard.releaseGlobally() }
    XCTAssertTrue(drag.begin(payload, anchor: .zero))
    target.dragModifiers = { [] }
    XCTAssertEqual(target.draggingUpdated(info), .move)
    XCTAssertTrue(target.highlighted)
    target.dragModifiers = { [.command] }
    XCTAssertEqual(target.draggingUpdated(info), .move)
    XCTAssertFalse(target.highlighted)
    XCTAssertTrue(target.performDragOperation(info))
    XCTAssertNotNil(
      controller.workspaces.panelDock.groups.first { $0.id == "color" }?.floatingFrame)
    drag.finish()
    XCTAssertEqual(target.draggingUpdated(info), [])
    XCTAssertFalse(target.performDragOperation(info))
  }

  @MainActor func testCommitCleanupCannotEndANewerDragAndDeactivationCancels() async throws {
    let (controller, _, drag) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let first = PanelDockPayload(library: library.identity, source: .panel(.gradients))
    let second = PanelDockPayload(library: library.identity, source: .panel(.patterns))
    XCTAssertTrue(drag.begin(first, anchor: .zero))
    XCTAssertTrue(drag.drop(first, at: NSPoint(x: 300, y: 500)))
    XCTAssertTrue(drag.begin(second, anchor: .zero))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(drag.activePayload, second)
    XCTAssertEqual(drag.backdrops.count, 2)
    let before = library.layout
    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    XCTAssertNil(drag.activePayload)
    XCTAssertTrue(drag.backdrops.isEmpty)
    XCTAssertEqual(library.layout, before)
    XCTAssertTrue(drag.begin(second, anchor: .zero))
    XCTAssertTrue(drag.drop(second, at: NSPoint(x: 400, y: 600)))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertNil(drag.activePayload)
    XCTAssertTrue(drag.backdrops.isEmpty)
  }
  @MainActor func testWindowChromeReceiversFloatFromFrameAndPanelTitlebars() throws {
    let (controller, _, drag) = try fixture()
    defer { cleanup(controller) }
    let library = controller.workspaces
    let payload = PanelDockPayload(library: library.identity, source: .group("color"))
    let frameWindow = try XCTUnwrap(
      controller.documentWindows.applicationFrame?.window as? DocumentWorkspaceWindow)
    let info = PanelDragInfo()
    info.write(payload)
    info.draggingDestinationWindow = frameWindow
    defer { info.draggingPasteboard.releaseGlobally() }
    info.draggingLocation = NSPoint(x: 150, y: frameWindow.frame.height - 8)
    XCTAssertTrue(drag.begin(payload, anchor: NSPoint(x: 8, y: 30)))
    XCTAssertEqual(frameWindow.draggingEntered(info), .move)
    XCTAssertTrue(frameWindow.prepareForDragOperation(info))
    XCTAssertTrue(frameWindow.performDragOperation(info))
    controller.documentWindows.floatingPanels.synchronize()
    let panel = try XCTUnwrap(
      controller.documentWindows.floatingPanels.controllers["color"]?.window as? FloatingPanelWindow
    )
    let second = PanelDockPayload(library: library.identity, source: .panel(.layers))
    info.write(second)
    info.draggingDestinationWindow = panel
    info.draggingLocation = NSPoint(x: 150, y: panel.frame.height - 8)
    XCTAssertTrue(drag.begin(second, anchor: NSPoint(x: 10, y: 25)))
    XCTAssertEqual(panel.draggingEntered(info), .move)
    XCTAssertTrue(panel.prepareForDragOperation(info))
    XCTAssertTrue(panel.performDragOperation(info))
    XCTAssertNotNil(library.panelDock.groups.first { $0.panels == [.layers] }?.floatingFrame)
    drag.finish()
    XCTAssertEqual(panel.draggingUpdated(info), [])
    XCTAssertFalse(frameWindow.performDragOperation(info))
  }

  @MainActor func testNativeContainerDoesNotChangeHostedWorkspacePixels() async throws {
    let _ = NSApplication.shared
    let owner = DocumentWindows()
    var results: [[UInt8]] = []
    for mode in 0..<2 {
      let store = EditorStore(
        document: try CraftNSDocument.blankModel(width: 64, height: 48, name: "Shadow"))
      store.renderTask?.cancel()
      store.surface = try Renderer.composite(store.document)
      store.image = try RasterIO.displayImage(XCTUnwrap(store.surface))
      store.rendering = false
      store.zoom = 5
      WorkspaceLayoutDiagnostics.log(
        "numeric.fixture", ["mode": mode, "owner": store.identity.uuidString])
      let host = NSHostingView(rootView: WorkspaceView(store: store))
      host.frame = NSRect(x: 0, y: 0, width: 1000, height: 650)
      let root: NSView
      if mode == 0 {
        root = host
      } else {
        root = PanelTearOffContainer(content: host, coordinator: owner.panelDragging)
      }
      let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = root
      window.appearance = NSAppearance(named: .darkAqua)
      window.layoutIfNeeded()
      root.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(200))
      window.layoutIfNeeded()
      root.layoutSubtreeIfNeeded()
      // Compare the same native capture boundary. Capturing an NSView ancestor instead
      // of the NSHostingView changes offscreen shadow compositing even without a layout change.
      let captured: NSView = host
      WorkspaceLayoutDiagnostics.log(
        "numeric.capture", ["mode": mode, "owner": store.identity.uuidString])
      let rep = try XCTUnwrap(captured.bitmapImageRepForCachingDisplay(in: captured.bounds))
      captured.cacheDisplay(in: captured.bounds, to: rep)
      if let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
          .write(to: url.appendingPathComponent("tear-off-container-\(mode).png"))
        print(
          "Workspace capture \(mode): \(rep.pixelsWide)x\(rep.pixelsHigh), row \(rep.bytesPerRow)")
      }
      let data = try XCTUnwrap(rep.bitmapData)
      results.append(
        Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh)))
      if WorkspaceLayoutDiagnostics.enabled,
        let directory = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]
      {
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        root.layoutSubtreeIfNeeded()
        WorkspaceLayoutDiagnostics.log(
          "numeric.late", ["mode": mode, "owner": store.identity.uuidString])
        try WorkspaceLayoutDiagnostics.writeImage(
          host,
          to: URL(fileURLWithPath: directory).appendingPathComponent(
            "tear-off-container-\(mode)-late.png"))
      }
      window.close()
    }
    XCTAssertEqual(results[0].count, results[1].count)
    XCTAssertTrue(
      results[0] == results[1],
      "The native drop container must preserve every hosted workspace pixel")
  }

}
