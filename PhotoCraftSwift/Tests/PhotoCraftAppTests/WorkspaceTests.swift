import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class WorkspaceTests: XCTestCase {
  func testInspectorKeepsLayerControlsWithinEverySupportedCompactConfiguration() {
    for height: CGFloat in [615, 865, 1139] {
      for flags in 0..<8 {
        var visibility = WorkspaceVisibility()
        visibility.color = flags & 1 != 0
        visibility.properties = flags & 2 != 0
        visibility.layers = flags & 4 != 0
        for library in [false, true] {
          for requested: CGFloat in [0, 160, 360, 10000] {
            let layout = WorkspacePanelLayout(
              height: height, visibility: visibility, library: library,
              preferredProperties: requested)
            let separators: CGFloat =
              (visibility.color && (visibility.properties || visibility.layers) ? 3 : 0)
              + (visibility.properties && visibility.layers ? 5 : 0)
            XCTAssertLessThanOrEqual(
              layout.colorHeight + layout.propertiesHeight + layout.layersHeight + 12 + separators,
              height + 0.000001)
            XCTAssertEqual(layout.colorHeight > 0, visibility.color)
            XCTAssertEqual(layout.propertiesHeight > 0, visibility.properties)
            XCTAssertEqual(layout.layersHeight > 0, visibility.layers)
            if visibility.layers { XCTAssertGreaterThanOrEqual(layout.layersHeight, 220) }
            if visibility.properties { XCTAssertGreaterThanOrEqual(layout.propertiesHeight, 160) }
          }
        }
      }
    }
  }

  func testInspectorResizeAndHiddenColorUseActualAvailableSpace() {
    var visibility = WorkspaceVisibility()
    let large = WorkspacePanelLayout(
      height: 865, visibility: visibility, library: false, preferredProperties: 450)
    let compact = WorkspacePanelLayout(
      height: 615, visibility: visibility, library: false, preferredProperties: 450)
    XCTAssertEqual(large.propertiesHeight, 450)
    XCTAssertLessThan(compact.propertiesHeight, large.propertiesHeight)
    XCTAssertEqual(compact.layersHeight, 220)
    visibility.color = false
    let hiddenColor = WorkspacePanelLayout(
      height: 615, visibility: visibility, library: false, preferredProperties: 450)
    XCTAssertGreaterThan(hiddenColor.propertiesHeight, compact.propertiesHeight + 140)
    XCTAssertEqual(hiddenColor.layersHeight, 220)
    let tiny = WorkspacePanelLayout(
      height: 100, visibility: visibility, library: false, preferredProperties: .infinity)
    XCTAssertEqual(tiny.propertiesHeight, 0)
    XCTAssertGreaterThanOrEqual(tiny.layersHeight, 0)
  }

  @MainActor func testToolRailColorWellRemainsVisibleWhenCompactToolsScroll() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    store.renderTask?.cancel()
    let before = store.document
    func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }
    for columns in [false, true] {
      store.workspaceLibrary.layout.doubleTools = columns
      let host = NSHostingView(rootView: WorkspaceView(store: store).toolRail)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: columns ? 68 : 40, height: 615),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { window.close() }
      window.layoutIfNeeded()
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      host.layoutSubtreeIfNeeded()
      let well = try XCTUnwrap(descendants(host, ColorSwatchButton.self).first)
      let rect = well.convert(well.bounds, to: host)
      XCTAssertTrue(host.bounds.contains(rect), "Color well clipped: \(rect), host \(host.bounds)")
      XCTAssertTrue(well.visibleRect.contains(well.bounds))
      let scroll = try XCTUnwrap(descendants(host, NSScrollView.self).first)
      XCTAssertFalse(well.isDescendant(of: scroll))
      if !columns {
        let documentView = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(documentView.bounds.height, scroll.contentView.bounds.height)
        documentView.scroll(CGPoint(x: 0, y: documentView.bounds.height))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(well.convert(well.bounds, to: host), rect)
        XCTAssertTrue(well.visibleRect.contains(well.bounds))
      }
    }
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func workspaceEvent(_ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false)
    throws -> NSEvent
  {
    try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: "\t",
        charactersIgnoringModifiers: "\t", isARepeat: repeatKey, keyCode: 48))
  }

  @MainActor func testCanvasTabMatchesPhotoshopMixedVisibilitySequenceWithoutEditing() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    store.renderTask?.cancel()
    let before = store.document
    let canvas = CraftCanvas(store: store)
    canvas.keyDown(with: try workspaceEvent())
    XCTAssertFalse(store.workspace.hasDock)
    XCTAssertFalse(store.workspace.tools)
    XCTAssertFalse(store.workspace.options)
    canvas.keyDown(with: try workspaceEvent(.shift))
    XCTAssertTrue(store.workspace.hasInspector)
    XCTAssertFalse(store.workspace.tools)
    XCTAssertFalse(store.workspace.options)
    canvas.keyDown(with: try workspaceEvent())
    XCTAssertEqual(store.workspace, WorkspaceVisibility())
    canvas.keyDown(with: try workspaceEvent(.shift))
    XCTAssertFalse(store.workspace.hasDock)
    XCTAssertTrue(store.workspace.tools)
    XCTAssertTrue(store.workspace.options)
    canvas.keyDown(with: try workspaceEvent())
    XCTAssertEqual(store.workspace, WorkspaceVisibility())
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testPanelRevealRestoresOnlyRequestedGroupFromHiddenWorkspace() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    store.renderTask?.cancel()
    store.workspace.togglePanels(includingTools: true)
    store.workspace.collapsedDock = true
    store.reveal(LayersTab.paths)
    XCTAssertEqual(store.layersTab, .paths)
    XCTAssertTrue(store.workspace.layers)
    XCTAssertFalse(store.workspace.color)
    XCTAssertFalse(store.workspace.properties)
    XCTAssertFalse(store.workspace.tools)
    XCTAssertFalse(store.workspace.options)
    XCTAssertFalse(store.workspace.rail)
    XCTAssertFalse(store.workspace.collapsedDock)
    store.reveal(ColorPanelTab.gradients)
    XCTAssertTrue(store.workspace.color)
    XCTAssertEqual(store.colorTab, .gradients)
    XCTAssertFalse(store.workspace.properties)
    store.reveal(PropertiesTab.adjustments)
    XCTAssertTrue(store.workspace.properties)
    XCTAssertEqual(store.propertiesTab, .adjustments)
  }

  @MainActor func testTemporaryHidingRetainsCollapseAndSelectedTabs() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    store.renderTask?.cancel()
    store.workspace.collapsedDock = true
    store.colorTab = .patterns
    store.propertiesTab = .adjustments
    store.layersTab = .channels
    let initial = store.workspace
    for modifiers: NSEvent.ModifierFlags in [[], .shift] {
      XCTAssertTrue(store.handleWorkspaceKey(try workspaceEvent(modifiers)))
      XCTAssertTrue(store.handleWorkspaceKey(try workspaceEvent(modifiers)))
      XCTAssertEqual(store.workspace, initial)
    }
    XCTAssertEqual(store.colorTab, .patterns)
    XCTAssertEqual(store.propertiesTab, .adjustments)
    XCTAssertEqual(store.layersTab, .channels)
  }

  @MainActor func testWorkspaceShortcutDoesNotConsumeModifiedTabsOrRepeatToggle() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    store.renderTask?.cancel()
    for modifiers: NSEvent.ModifierFlags in [
      .command, .option, .control, .function, [.command, .shift],
    ] {
      XCTAssertFalse(store.handleWorkspaceKey(try workspaceEvent(modifiers)))
      XCTAssertEqual(store.workspace, WorkspaceVisibility())
    }
    XCTAssertTrue(store.handleWorkspaceKey(try workspaceEvent()))
    let hidden = store.workspace
    XCTAssertTrue(store.handleWorkspaceKey(try workspaceEvent(repeatKey: true)))
    XCTAssertEqual(store.workspace, hidden)
    XCTAssertTrue(store.handleWorkspaceKey(try workspaceEvent(.capsLock)))
    XCTAssertEqual(store.workspace, WorkspaceVisibility())
  }

  @MainActor func testHidingPanelsHidesRetainedUtilitiesWithoutSharingDocumentState() throws {
    let first = EditorStore(document: try CraftDocument(width: 2, height: 2))
    let second = EditorStore(document: try CraftDocument(width: 2, height: 2))
    first.renderTask?.cancel()
    second.renderTask?.cancel()
    first.workspaceLibrary.selectPanel(.history, reveal: true)
    first.workspaceLibrary.selectPanel(.cloneSource, reveal: true)
    first.handleWorkspaceKey(try workspaceEvent(.shift))
    XCTAssertFalse(WorkspacePanel.history.isVisible(in: first.workspace))
    XCTAssertFalse(WorkspacePanel.cloneSource.isVisible(in: first.workspace))
    XCTAssertEqual(second.workspace, WorkspaceVisibility())
  }

  @MainActor func testNewDocumentsHaveDistinctNames() throws {
    let controller = CraftDocumentController()
    let first = try XCTUnwrap(
      controller.makeUntitledDocument(ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
    first.store.renderTask?.cancel()
    controller.addDocument(first)
    defer { controller.removeDocument(first) }
    let second = try XCTUnwrap(
      controller.makeUntitledDocument(ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
    second.store.renderTask?.cancel()
    XCTAssertEqual(first.store.document.name, "Untitled-1")
    XCTAssertEqual(second.store.document.name, "Untitled-2")
  }

  @MainActor func testUnavailableToolDoesNotPaintWithPreviouslySelectedBrush() throws {
    let store = EditorStore(document: try CraftNSDocument.blankModel(width: 12, height: 12))
    store.renderTask?.cancel()
    store.chooseTool(WorkspaceCatalog.tool("brush"))
    store.chooseTool(WorkspaceCatalog.tool("remove"))
    let before = store.document
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
    let down = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: CGPoint(x: 150, y: 150), modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    canvas.mouseDown(with: down)
    canvas.mouseUp(with: down)
    XCTAssertEqual(store.selectedTool.id, "remove")
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.chooseTool(WorkspaceCatalog.tool("brush"))
    XCTAssertNil(store.unavailableToolID)
  }
  @MainActor func testGroupedShortcutsCycleAndRememberSelection() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    store.renderTask?.cancel()
    XCTAssertTrue(store.chooseShortcut("u", cycle: false))
    XCTAssertEqual(store.tool, .rectangle)
    XCTAssertTrue(store.chooseShortcut("u", cycle: true))
    XCTAssertEqual(store.tool, .ellipse)
    _ = store.chooseShortcut("b", cycle: false)
    _ = store.chooseShortcut("u", cycle: false)
    XCTAssertEqual(store.tool, .ellipse)
    _ = store.chooseShortcut("u", cycle: true)
    XCTAssertNil(store.unavailableToolID)
    XCTAssertEqual(store.tool,.triangle)
    XCTAssertFalse(store.chooseShortcut("?", cycle: false))
    XCTAssertEqual(Set(WorkspaceCatalog.tools.map(\.id)).count, WorkspaceCatalog.tools.count)
    for tool in EditorTool.allCases {
      XCTAssertEqual(WorkspaceCatalog.tools.filter { $0.native == tool }.count, 1)
    }
  }
  @MainActor func testMarqueeModifiersAndCanvasClipping() {
    let square = CraftCanvas.dragRect(
      from: CGPoint(x: 20, y: 20), to: CGPoint(x: 25, y: 30), flags: [.shift], width: 100,
      height: 100)
    XCTAssertEqual(square, IntRect(x: 20, y: 20, width: 10, height: 10))
    let centered = CraftCanvas.dragRect(
      from: CGPoint(x: 20, y: 20), to: CGPoint(x: 25, y: 30), flags: [.shift, .option], width: 100,
      height: 100)
    XCTAssertEqual(centered, IntRect(x: 10, y: 10, width: 20, height: 20))
    let clipped = CraftCanvas.dragRect(
      from: CGPoint(x: 2, y: 2), to: CGPoint(x: 7, y: 5), flags: [.option], width: 6, height: 6)
    XCTAssertEqual(clipped, IntRect(x: 0, y: 0, width: 6, height: 5))
    XCTAssertNil(CraftCanvas.dragRect(from: .zero, to: .zero, flags: [], width: 6, height: 6))
  }
  @MainActor func testAutoSelectUsesPixelsVisibilityAndMasks() throws {
    var doc = try CraftDocument(width: 8, height: 8)
    let baseID = doc.layers[0].id
    var upper = Layer(
      name: "Upper", content: .raster(try Surface(width: 3, height: 3, fill: Pixel(1, 0, 0))))
    upper.x = 2
    upper.y = 2
    doc.layers.append(upper)
    let store = EditorStore(document: doc)
    store.renderTask?.cancel()
    store.autoSelectLayer(at: CGPoint(x: 2.5, y: 2.5))
    XCTAssertEqual(store.document.activeLayerID, upper.id)
    store.autoSelectLayer(at: CGPoint(x: 0.5, y: 0.5))
    XCTAssertEqual(store.document.activeLayerID, baseID)
    store.perform(.mask(upper.id, try Surface(width: 3, height: 3, fill: .black)))
    store.renderTask?.cancel()
    store.autoSelectLayer(at: CGPoint(x: 2.5, y: 2.5))
    XCTAssertEqual(store.document.activeLayerID, baseID)
  }
  @MainActor func testChannelPreviewPreservesEditableRGBDocument() async throws {
    let document = try CraftNSDocument.blankModel(
      width: 3, height: 3, background: Pixel(0.2, 0.6, 0.9))
    let store = EditorStore(document: document)
    store.displayChannel = 0
    await store.renderTask?.value
    XCTAssertEqual(store.document, document)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    let preview = try RasterIO.surface(XCTUnwrap(store.image))
    let p = preview.pixel(x: 1, y: 1)
    XCTAssertEqual(p.r, p.g, accuracy: 0.01)
    XCTAssertEqual(p.g, p.b, accuracy: 0.01)
    XCTAssertEqual(p.r, 0.2, accuracy: 0.01)
    store.displayChannel = nil
    await store.renderTask?.value
    let restored = try RasterIO.surface(XCTUnwrap(store.image)).pixel(x: 1, y: 1)
    XCTAssertEqual(restored.b, 0.9, accuracy: 0.01)
  }
  @MainActor func testTransparentNewDocumentAndCropRoundTrip() async throws {
    let document = try CraftNSDocument.blankModel(width: 12, height: 10, background: .clear)
    guard case .raster(let raster) = document.layers[0].content else {
      return XCTFail("Expected pixel layer")
    }
    XCTAssertEqual(raster.pixel(x: 5, y: 5).a, 0)
    let store = EditorStore(document: document)
    store.renderTask?.cancel()
    store.perform(.selection(IntRect(x: 2, y: 3, width: 4, height: 5)))
    store.cropToSelection()
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.width, 4)
    XCTAssertEqual(store.document.height, 5)
    await store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.width, 12)
    XCTAssertEqual(store.document.height, 10)
  }
}
