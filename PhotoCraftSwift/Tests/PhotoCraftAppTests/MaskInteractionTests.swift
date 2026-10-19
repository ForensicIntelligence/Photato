import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class MaskInteractionTests: XCTestCase {
  @MainActor func testVectorTargetChangeWhileMaskRenderIsPendingSettlesCanvas() async throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    store.toggleMaskView(id, mode: .gray)
    XCTAssertTrue(store.rendering)
    store.useMaskThumbnail(id, kind: .vector)
    await store.renderTask?.value
    XCTAssertFalse(store.rendering)
    XCTAssertNil(store.displayedMaskImage)
    XCTAssertNotNil(store.image)
    XCTAssertEqual(store.pathTarget, .vectorMask(id))
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  @MainActor func testVectorClickKeepsLayersPanelAndCommandLoadsWithoutRetargeting() async throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    store.toggleMaskView(id, mode: .gray)
    store.useMaskThumbnail(id, kind: .vector)
    XCTAssertEqual(store.pathTarget, .vectorMask(id))
    XCTAssertEqual(store.tool, .directSelection)
    XCTAssertEqual(store.layersTab, .layers)
    XCTAssertNil(store.currentMaskView)
    store.select(id)
    store.useMaskThumbnail(id, kind: .vector, modifiers: .command)
    await store.geometryTask?.value
    XCTAssertNil(store.pathTarget)
    XCTAssertNil(store.maskEditingLayerID)
    XCTAssertEqual(try store.document.coverageSelection()?.bytes, [255, 255, 255, 255])
    XCTAssertEqual(store.session.undoStack.count, 1)
  }
  @MainActor func testNativeThumbnailRetainsModifiersAndRejectsDragAndStaleGeneration() throws {
    _ = NSApplication.shared
    let store = try fixture()
    let id = store.document.layers[0].id
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer {
      window.close()
      store.renderTask?.cancel()
    }
    let button = MaskThumbnailButton()
    button.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
    button.store = store
    button.layerID = id
    window.contentView?.addSubview(button)
    func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = [], x: CGFloat = 10)
      throws -> NSEvent
    {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: type, location: NSPoint(x: x, y: 10), modifierFlags: flags,
          timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1))
    }
    button.mouseDown(with: try event(.leftMouseDown, .shift))
    button.mouseUp(with: try event(.leftMouseUp))
    XCTAssertFalse(store.activeLayer!.effectiveMaskProperties.enabled)
    XCTAssertEqual(store.session.undoStack.count, 1)
    button.mouseDown(with: try event(.leftMouseDown, .shift))
    button.mouseDragged(with: try event(.leftMouseDragged, x: 20))
    button.mouseUp(with: try event(.leftMouseUp))
    XCTAssertEqual(store.session.undoStack.count, 1)
    button.mouseDown(with: try event(.leftMouseDown, .option))
    store.layerPanelGeneration = UUID()
    button.mouseUp(with: try event(.leftMouseUp))
    XCTAssertNil(store.currentMaskView)
    button.performClick(nil)
    XCTAssertTrue(store.editingMask)
    XCTAssertNil(store.currentMaskView)
    button.mouseDown(with: try event(.leftMouseDown, .option))
    button.cancelOperation(nil)
    button.mouseUp(with: try event(.leftMouseUp))
    XCTAssertNil(store.currentMaskView)
  }

  @MainActor func testReloadAndCloseDiscardViewAndPendingSelectionEvenWithIdenticalDocument()
    async throws
  {
    _ = NSApplication.shared
    _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    let initial = try fixture()
    defer { initial.renderTask?.cancel() }
    let doc = CraftNSDocument(model: initial.document)
    let store = doc.store
    let id = store.document.layers[0].id
    defer { doc.close() }
    let bytes = try NativeArchive.encode(store.document)
    store.toggleMaskView(id, mode: .gray)
    store.useMaskThumbnail(id, kind: .pixel, modifiers: .command)
    let pending = store.geometryTask
    try doc.read(from: bytes, ofType: CraftNSDocument.nativeType)
    await pending?.value
    await store.renderTask?.value
    XCTAssertFalse(store.geometryBusy)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertNil(store.currentMaskView)
    XCTAssertNil(store.displayedMaskImage)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(try NativeArchive.encode(store.document), bytes)
    store.toggleMaskView(id, mode: .overlay)
    let render = store.renderTask
    doc.close()
    await render?.value
    XCTAssertNil(store.displayedMaskImage)
  }

  @MainActor func fixture() throws -> EditorStore {
    var doc = try CraftDocument(width: 4, height: 1)
    doc.layers[0].mask = try Surface(width: 4, height: 1, fill: .black)
    doc.layers[0].mask?.setPixel(x: 1, y: 0, .white)
    doc.layers[0].mask?.setPixel(x: 2, y: 0, .white)
    doc.layers[0].vectorMask = VectorMask(path: VectorPath())
    let store = EditorStore(document: doc)
    store.renderTask?.cancel()
    return store
  }

  @MainActor func testGrayAndOverlayTogglesAreCleanAndLeaveCompositeAndArchiveUnchanged()
    async throws
  {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    let archive = try NativeArchive.encode(store.document)
    let composite = try Renderer.composite(store.document)
    var changes = 0
    store.onChange = { _ in changes += 1 }
    for flags: NSEvent.ModifierFlags in [.option, [.option, .shift], [.option, .shift], .option] {
      store.useMaskThumbnail(id, kind: .pixel, modifiers: flags)
      await store.renderTask?.value
      XCTAssertTrue(store.editingMask)
      XCTAssertEqual(try NativeArchive.encode(store.document), archive)
      XCTAssertEqual(store.surface, composite)
      XCTAssertNotNil(store.image)
      XCTAssertEqual(
        store.image?.dataProvider?.data as Data?,
        try RasterIO.displayImage(composite).dataProvider?.data as Data?)
    }
    XCTAssertEqual(store.currentMaskView?.mode, .gray)
    XCTAssertNotNil(store.displayedMaskImage)
    store.useMaskThumbnail(id, kind: .pixel, modifiers: .option)
    XCTAssertNil(store.currentMaskView)
    XCTAssertNil(store.displayedMaskImage)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(changes, 0)
  }

  @MainActor func testDisablePixelAndVectorMasksHaveOneUndoAndDoNotRetarget() throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    let original = store.document
    for kind: MaskThumbnailKind in [.pixel, .vector] {
      store.useMaskThumbnail(id, kind: kind, modifiers: .shift)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertNil(store.maskEditingLayerID)
      if kind == .pixel {
        XCTAssertFalse(store.activeLayer!.effectiveMaskProperties.enabled)
      } else {
        XCTAssertFalse(store.activeLayer!.vectorMask!.enabled)
      }
      store.undo()
      XCTAssertEqual(store.document, original)
    }
  }

  @MainActor func testCommandModifierPrecedenceAndAllSelectionCombinations() async throws {
    let cases: [(NSEvent.ModifierFlags, [UInt8])] = [
      ([.command], [0, 255, 255, 0]), ([.command, .shift], [255, 255, 255, 0]),
      ([.command, .option], [255, 0, 0, 0]), ([.command, .shift, .option], [0, 255, 0, 0]),
    ]
    for (flags, expected) in cases {
      let store = try fixture()
      let id = store.document.layers[0].id
      defer { store.renderTask?.cancel() }
      var selected = store.document
      selected.selection = IntRect(x: 0, y: 0, width: 2, height: 1)
      store.session = EditorSession(document: selected)
      store.selectionMode = .subtract  // Thumbnail defaults must ignore tool mode.
      let before = store.document
      store.useMaskThumbnail(id, kind: .pixel, modifiers: flags)
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      XCTAssertEqual(try store.document.coverageSelection()?.bytes, expected)
      XCTAssertEqual(store.activeLayer?.mask, before.layers[0].mask)
      XCTAssertNil(store.currentMaskView)
      XCTAssertNil(store.maskEditingLayerID)
      XCTAssertEqual(store.session.undoStack.count, 1)
      store.undo()
      XCTAssertEqual(store.document, before)
    }
  }

  @MainActor func testViewPaintingUpdatesMaskAndUndoWithoutChangingContent() async throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    let content = store.activeLayer!.content
    let old = store.activeLayer!.mask
    store.useMaskThumbnail(id, kind: .pixel, modifiers: .option)
    store.fill(color: .white)
    await store.renderTask?.value
    XCTAssertEqual(store.activeLayer?.content, content)
    XCTAssertNotEqual(store.activeLayer?.mask, old)
    XCTAssertEqual(store.currentMaskView?.mode, .gray)
    XCTAssertNotNil(store.displayedMaskImage)
    store.undo()
    await store.renderTask?.value
    XCTAssertEqual(store.activeLayer?.mask, old)
    XCTAssertEqual(store.currentMaskView?.mode, .gray)
  }

  @MainActor func testContentOtherLayerAndDeletedMaskExitViewWithoutResurrectingIt() async throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    store.toggleMaskView(id, mode: .gray)
    store.select(id)
    await store.renderTask?.value
    XCTAssertNil(store.displayedMaskImage)
    store.toggleMaskView(id, mode: .overlay)
    store.deleteMask(id)
    await store.renderTask?.value
    XCTAssertNil(store.currentMaskView)
    store.undo()
    XCTAssertNil(store.currentMaskView)
    store.toggleMaskView(id, mode: .gray)
    store.addPixelLayer()
    await store.renderTask?.value
    XCTAssertNil(store.currentMaskView)
  }

  @MainActor func testLockedMasksCanBeViewedAndLoadedButCannotBeDisabled() async throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    var locked = store.document
    locked.layers[0].locked = true
    store.session = EditorSession(document: locked)
    store.useMaskThumbnail(id, kind: .pixel, modifiers: .shift)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.useMaskThumbnail(id, kind: .pixel, modifiers: .option)
    XCTAssertEqual(store.currentMaskView?.mode, .gray)
    store.useMaskThumbnail(id, kind: .pixel, modifiers: .command)
    await store.geometryTask?.value
    XCTAssertEqual(try store.document.coverageSelection()?.bytes, [0, 255, 255, 0])
  }

  @MainActor func testModalAndMissingTargetsAreRejectedAndGenerationInvalidatesView() throws {
    let store = try fixture()
    let id = store.document.layers[0].id
    defer { store.renderTask?.cancel() }
    let before = store.document
    for change: (Bool) -> Void in [
      { store.geometryBusy = $0 }, { store.showAI = $0 }, { store.confirmingLayerDeletion = $0 },
    ] {
      change(true)
      for flags: NSEvent.ModifierFlags in [.option, .shift, .command] {
        store.useMaskThumbnail(id, kind: .pixel, modifiers: flags)
      }
      change(false)
      XCTAssertEqual(store.document, before)
      XCTAssertNil(store.currentMaskView)
    }
    store.useMaskThumbnail(UUID(), kind: .pixel, modifiers: .option)
    XCTAssertNil(store.maskEditingLayerID)
    store.toggleMaskView(id, mode: .gray)
    store.layerPanelGeneration = UUID()
    XCTAssertNil(store.currentMaskView)
    store.render()
    XCTAssertNil(store.layerMaskView)
  }
}
