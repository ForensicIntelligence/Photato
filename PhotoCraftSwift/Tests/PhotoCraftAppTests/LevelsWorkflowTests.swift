import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class LevelsWorkflowTests: XCTestCase {
  @MainActor func testPreviewCancelCommitAndUndo() async throws {
    var d = try CraftDocument(width: 8, height: 4)
    d.layers[0].content = .raster(try Surface(width: 8, height: 4, fill: Pixel(0.4, 0.5, 0.6)))
    let store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    store.beginLevels()
    XCTAssertNotNil(store.levelsDraft)
    store.levelsDraft?.levels.red.gamma = 0.5
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertLessThan(try XCTUnwrap(store.surface).pixel(x: 0, y: 0).r, 0.4)
    store.levelsDraft?.preview = false
    store.render()
    await store.renderTask?.value
    XCTAssertEqual(store.surface, try Renderer.composite(d))
    store.cancelLevels()
    XCTAssertNil(store.levelsDraft)
    XCTAssertEqual(store.document, d)
    store.beginLevels()
    store.levelsDraft?.levels.red.gamma = 0.5
    store.commitLevels()
    await store.geometryTask?.value
    XCTAssertNotEqual(store.document, d)
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.undo()
    XCTAssertEqual(store.document, d)
    store.beginLevels()
    store.levelsDraft?.levels.red.gamma = 0.5
    store.commitLevels()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    XCTAssertEqual(store.document, d)
    XCTAssertFalse(store.geometryBusy)
  }
  @MainActor func testSelectionMaskLayerEditUndoAndLocks() throws {
    let store = EditorStore(document: try CraftDocument(width: 8, height: 4))
    defer { store.renderTask?.cancel() }
    store.perform(.selection(IntRect(x: 2, y: 1, width: 3, height: 2)))
    let before = store.document
    store.addLevelsLayer()
    let layer = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(layer.content, .adjustment(.levels(.init())))
    XCTAssertEqual(layer.mask?.pixel(x: 2, y: 1).r, 1)
    XCTAssertEqual(layer.mask?.pixel(x: 0, y: 0).r, 0)
    XCTAssertFalse(store.canBeginLevels)
    store.setLevels(layer.id, .init(blue: .init(gamma: 1.4)))
    XCTAssertEqual(store.activeLayer?.content, .adjustment(.levels(.init(blue: .init(gamma: 1.4)))))
    store.undo()
    XCTAssertEqual(store.activeLayer?.content, layer.content)
    store.undo()
    XCTAssertEqual(store.document, before)
    store.perform(.lock(store.document.layers[0].id, true))
    XCTAssertFalse(store.canBeginLevels)
    store.beginLevels()
    XCTAssertNil(store.levelsDraft)
  }
  @MainActor func testLevelsMenusAndShortcut() {
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
    let image = NSApp.mainMenu?.item(withTitle: "Image")?.submenu?.item(withTitle: "Adjustments")?
      .submenu
    XCTAssertEqual(image?.item(withTitle: "Levels…")?.keyEquivalent, "l")
    XCTAssertEqual(image?.item(withTitle: "Levels…")?.keyEquivalentModifierMask, .command)
    let imageMenu = NSApp.mainMenu?.item(withTitle: "Image")?.submenu
    for (title, key, flags) in [
      ("Auto Tone", "l", NSEvent.ModifierFlags([.command, .shift])),
      ("Auto Contrast", "l", [.command, .option, .shift]), ("Auto Color", "b", [.command, .shift]),
    ] {
      XCTAssertEqual(imageMenu?.item(withTitle: title)?.keyEquivalent, key)
      XCTAssertEqual(imageMenu?.item(withTitle: title)?.keyEquivalentModifierMask, flags)
    }
    let layer = NSApp.mainMenu?.item(withTitle: "Layer")?.submenu?.item(
      withTitle: "New Adjustment Layer")?.submenu
    XCTAssertEqual(layer?.item(withTitle: "Levels…")?.action, #selector(AppDelegate.newLevels))
  }
}
