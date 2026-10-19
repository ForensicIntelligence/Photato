import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class MaskWorkflowTests: XCTestCase {
  @MainActor func testApplyAndFromTransparencyRunInBackgroundWithUndoAndPaintTargetReset()
    async throws
  {
    var doc = try CraftDocument(width: 4, height: 2)
    doc.selection = IntRect(x: 0, y: 0, width: 2, height: 2)
    let store = EditorStore(document: doc)
    store.renderTask?.cancel()
    store.createMask(.hideSelection)
    store.renderTask?.cancel()
    XCTAssertTrue(store.editingMask)
    XCTAssertFalse(store.canCreateMask(.revealAll))
    let masked = store.document
    store.applyMask()
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertNil(store.error)
    XCTAssertFalse(store.geometryBusy)
    XCTAssertFalse(store.editingMask)
    XCTAssertNil(store.maskEditingLayerID)
    XCTAssertNil(store.activeLayer?.mask)
    XCTAssertEqual(store.session.undoStack.last?.label, "Apply Layer Mask")
    XCTAssertEqual(try Renderer.composite(store.document).pixel(x: 0, y: 0).a, 0)
    XCTAssertEqual(try Renderer.composite(store.document).pixel(x: 3, y: 0).a, 1)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, masked)
    store.redo()
    store.renderTask?.cancel()
    let applied = store.document
    store.createMask(.fromTransparency)
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertTrue(store.editingMask)
    XCTAssertEqual(try Renderer.composite(store.document), try Renderer.composite(applied))
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, applied)
  }

  @MainActor func testMaskCapabilitiesRejectWrongTargetsAndCancelledApplyDoesNotEdit() async throws
  {
    let store = EditorStore(document: try CraftDocument(width: 64, height: 64))
    store.renderTask?.cancel()
    XCTAssertFalse(store.canCreateMask(.hideSelection))
    XCTAssertTrue(store.canCreateMask(.fromTransparency))
    store.addMask(hiding: true)
    store.renderTask?.cancel()
    let original = store.document
    let history = store.session.undoStack.count
    store.applyMask()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(store.session.undoStack.count, history)
    XCTAssertTrue(store.editingMask)
    XCTAssertFalse(store.geometryBusy)
    store.deleteMask()
    store.renderTask?.cancel()
    store.perform(.lock(store.document.layers[0].id, true))
    store.renderTask?.cancel()
    XCTAssertFalse(store.canCreateMask(.revealAll))
    XCTAssertFalse(store.canEditActiveMask)
    var group = Layer(name: "Group", content: .group(GroupContent()))
    group.mask = try Surface(width: 2, height: 2, fill: .white)
    XCTAssertFalse(store.canApplyMask(group))
  }

  @MainActor func testNativeLayerMaskMenuHasSeparateCreationApplyAndDeleteCommands() {
    _ = NSApplication.shared
    let oldMenu = NSApp.mainMenu
    let oldWindowsMenu = NSApp.windowsMenu
    let oldHelpMenu = NSApp.helpMenu
    defer {
      NSApp.mainMenu = oldMenu
      NSApp.windowsMenu = oldWindowsMenu
      NSApp.helpMenu = oldHelpMenu
    }
    let app = AppDelegate()
    app.buildMenus()
    let layer = NSApp.mainMenu?.item(withTitle: "Layer")?.submenu
    let mask = layer?.item(withTitle: "Layer Mask")?.submenu
    XCTAssertEqual(
      mask?.items.filter { !$0.isSeparatorItem }.map(\.title),
      [
        "Reveal All", "Hide All", "Reveal Selection", "Hide Selection", "From Transparency",
        "Delete", "Apply", "Enable", "Unlink",
      ])
    XCTAssertEqual(mask?.item(withTitle: "Apply")?.action, #selector(AppDelegate.maskApply))
    XCTAssertEqual(mask?.item(withTitle: "Delete")?.action, #selector(AppDelegate.maskDelete))
    XCTAssertTrue(mask?.items.allSatisfy { $0.keyEquivalent.isEmpty } == true)
  }

  @MainActor func testPropertiesAndUnlinkedMaskMoveLeaveContentInPlace() throws {
    var doc = try CraftDocument(width: 20, height: 20)
    var layer = Layer(
      name: "Mask", content: .raster(try Surface(width: 20, height: 20, fill: .white)))
    layer.mask = try Surface(width: 4, height: 4, fill: .white)
    doc.layers = [layer]
    doc.activeLayerID = layer.id
    let store = EditorStore(document: doc)
    store.renderTask?.cancel()
    store.selectMask(layer.id)
    store.updateMask(layer.id) {
      $0.linked = false
      $0.density = 0.7
    }
    store.renderTask?.cancel()
    store.chooseTool(WorkspaceCatalog.tool("move"))
    store.selectMask(layer.id)
    store.zoom = 1
    let canvas = CraftCanvas(store: store)
    canvas.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
    func event(_ kind: NSEvent.EventType, _ p: CGPoint) throws -> NSEvent {
      try XCTUnwrap(
        NSEvent.mouseEvent(
          with: kind, location: p, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    let origin = canvas.imageRect.origin
    canvas.mouseDown(with: try event(.leftMouseDown, CGPoint(x: origin.x + 1, y: origin.y + 1)))
    canvas.mouseUp(with: try event(.leftMouseUp, CGPoint(x: origin.x + 6, y: origin.y + 3)))
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.layers[0].x, 0)
    XCTAssertEqual(store.document.layers[0].maskCoordinateTransform.tx, 5, accuracy: 0.01)
    // AppKit event coordinates convert through the flipped canvas; vertical direction is checked as magnitude.
    XCTAssertEqual(abs(store.document.layers[0].maskCoordinateTransform.ty), 2, accuracy: 0.01)
    XCTAssertEqual(store.session.undoStack.count, 2)
    store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document.layers[0].maskCoordinateTransform, .identity)
  }
  @MainActor func testHitTestingAndTransformPreviewRespectDisabledAndUnlinkedMasks() throws {
    var d = try CraftDocument(width: 12, height: 12)
    let base = Layer(
      name: "Base", content: .raster(try Surface(width: 12, height: 12, fill: .white)))
    var l = Layer(name: "Top", content: .raster(try Surface(width: 8, height: 8, fill: .white)))
    l.mask = try Surface(width: 2, height: 2, fill: .white)
    var p = MaskProperties()
    p.transform = .translation(4, 4)
    p.linked = false
    l.maskProperties = p
    d.layers = [base, l]
    d.activeLayerID = l.id
    let s = EditorStore(document: d)
    s.renderTask?.cancel()
    s.autoSelectLayer(at: CGPoint(x: 0.5, y: 0.5))
    XCTAssertEqual(s.activeLayer?.id, base.id)
    s.autoSelectLayer(at: CGPoint(x: 4.5, y: 4.5))
    XCTAssertEqual(s.activeLayer?.id, l.id)
    s.updateMask(l.id) { $0.enabled = false }
    s.renderTask?.cancel()
    s.autoSelectLayer(at: CGPoint(x: 0.5, y: 0.5))
    XCTAssertEqual(s.activeLayer?.id, l.id)
    s.beginTransform()
    s.transformDraft?.centerX += 2
    s.transformDraft?.centerY += 3
    XCTAssertEqual(s.previewDocument.layers[1].maskCoordinateTransform, .translation(4, 4))
    s.cancelTransform()
    s.renderTask?.cancel()
  }
}
