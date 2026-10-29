import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ColorBalanceWorkflowTests: XCTestCase {
  @MainActor func testPreviewCancelBackgroundCommitUndoAndDraftExclusion() async throws {
    var d = try CraftDocument(width: 8, height: 4)
    d.layers[0].content = .raster(try Surface(width: 8, height: 4, fill: Pixel(0.8, 0.2, 0.4)))
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    store.beginColorBalance()
    XCTAssertNotNil(store.colorBalanceDraft)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.canBeginCurves)
    XCTAssertFalse(store.clipboardTargetAvailable)
    store.beginLevels()
    store.beginCurves()
    store.beginHueSaturation()
    store.beginTransform()
    XCTAssertNil(store.levelsDraft)
    XCTAssertNil(store.curvesDraft)
    XCTAssertNil(store.hueSaturationDraft)
    XCTAssertNil(store.transformDraft)
    store.colorBalanceDraft?.adjustment.midtones.yellowBlue = 100
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertNotEqual(try XCTUnwrap(store.surface), try Renderer.composite(d))
    store.colorBalanceDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.surface, try Renderer.composite(d))
    store.cancelColorBalance()
    XCTAssertEqual(store.document, d)
    store.beginColorBalance()
    store.colorBalanceDraft?.adjustment = ColorBalanceAdjustment(
      midtones: .init(cyanRed: 35, yellowBlue: -20))
    store.commitColorBalance()
    await store.geometryTask?.value
    XCTAssertNotEqual(store.document, d)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Color Balance")
    await store.undo()
    XCTAssertEqual(store.document, d)
    store.beginColorBalance()
    store.colorBalanceDraft?.adjustment.midtones.cyanRed = 90
    store.commitColorBalance()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertFalse(store.geometryBusy)
    store.beginCurves()
    store.beginColorBalance()
    XCTAssertNil(store.colorBalanceDraft)
    store.cancelCurves()
  }
  @MainActor func testSelectionMaskToneEditsCoalescingAndLocks() async throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 2))
    defer { store.renderTask?.cancel() }
    store.perform(.selection(IntRect(x: 1, y: 0, width: 2, height: 2)))
    let before = store.document
    store.addColorBalanceLayer()
    let layer = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(layer.content, .adjustment(.colorBalance(.init())))
    XCTAssertEqual(layer.mask?.pixel(x: 1, y: 0), .white)
    XCTAssertEqual(layer.mask?.pixel(x: 0, y: 0), .black)
    XCTAssertFalse(store.canBeginColorBalance)
    store.coalesce(true)
    for amount in [10, 20, 30] {
      var a = ColorBalanceAdjustment()
      a.shadows.cyanRed = amount
      a.highlights.yellowBlue = -20
      store.setColorBalance(layer.id, a)
    }
    store.coalesce(false)
    await store.undo()
    XCTAssertEqual(store.activeLayer?.content, layer.content)
    store.perform(.lock(layer.id, true))
    let locked = store.document
    store.setColorBalance(
      layer.id, ColorBalanceAdjustment(midtones: .init(cyanRed: 35, yellowBlue: -20)))
    XCTAssertEqual(store.document, locked)
    await store.undo()
    await store.undo()
    XCTAssertEqual(store.document, before)
  }
  @MainActor func testCommandBAndLayerMenus() {
    _ = NSApplication.shared
    let old = NSApp.mainMenu
    let windows = NSApp.windowsMenu
    let help = NSApp.helpMenu
    defer {
      NSApp.mainMenu = old
      NSApp.windowsMenu = windows
      NSApp.helpMenu = help
    }
    let app = AppDelegate()
    app.buildMenus()
    let menu = NSApp.mainMenu?.item(withTitle: "Image")?.submenu?.item(withTitle: "Adjustments")?
      .submenu
    XCTAssertEqual(menu?.item(withTitle: "Color Balance…")?.keyEquivalent, "b")
    XCTAssertEqual(menu?.item(withTitle: "Color Balance…")?.keyEquivalentModifierMask, .command)
    XCTAssertEqual(
      menu?.item(withTitle: "Color Balance…")?.action, #selector(AppDelegate.colorBalance))
    let layer = NSApp.mainMenu?.item(withTitle: "Layer")?.submenu?.item(
      withTitle: "New Adjustment Layer")?.submenu
    XCTAssertEqual(
      layer?.item(withTitle: "Color Balance…")?.action, #selector(AppDelegate.newColorBalance))
  }
}
