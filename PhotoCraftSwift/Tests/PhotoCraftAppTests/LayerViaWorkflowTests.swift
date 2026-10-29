import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class LayerViaWorkflowTests: XCTestCase {
  @MainActor func store(clipboard: MemoryClipboard = MemoryClipboard()) throws -> EditorStore {
    var d = try CraftDocument(width: 5, height: 4)
    d.selection = IntRect(x: 1, y: 1, width: 2, height: 2)
    let s = EditorStore(document: d, clipboard: clipboard)
    s.renderTask?.cancel()
    return s
  }
  @MainActor func testCopyCutUndoAndSelectionDoNotTouchClipboard() async throws {
    for operation in LayerViaOperation.allCases {
      let clipboard = MemoryClipboard()
      clipboard.rejectWrites = true
      clipboard.changeCount = 17
      let s = try store(clipboard: clipboard)
      let original = s.document
      XCTAssertTrue(s.canLayerVia(operation))
      s.layerVia(operation)
      await s.geometryTask?.value
      s.renderTask?.cancel()
      XCTAssertNil(s.error)
      XCTAssertEqual(clipboard.changeCount, 17)
      XCTAssertNil(clipboard.value)
      XCTAssertEqual(s.document.layers.count, 2)
      XCTAssertNil(s.document.selection)
      XCTAssertEqual(s.selectedLayerIDs, Set([try XCTUnwrap(s.document.activeLayerID)]))
      XCTAssertEqual(s.session.undoStack.count, 1)
      XCTAssertEqual(s.session.undoStack.last?.label, operation.rawValue)
      let result = s.document
      await s.undo()
      s.renderTask?.cancel()
      XCTAssertEqual(s.document, original)
      await s.redo()
      s.renderTask?.cancel()
      XCTAssertEqual(s.document, result)
    }
  }
  @MainActor func testContextGuardsAndCancellation() async throws {
    let s = try store()
    s.geometryBusy = true
    XCTAssertFalse(s.canLayerVia(.copy))
    s.geometryBusy = false
    s.selectedLayerIDs = [s.document.layers[0].id, UUID()]
    XCTAssertFalse(s.canLayerVia(.copy))
    s.selectedLayerIDs = [s.document.layers[0].id]
    s.perform(.lock(s.document.layers[0].id, true))
    s.renderTask?.cancel()
    XCTAssertFalse(s.canLayerVia(.copy))
    XCTAssertFalse(s.canLayerVia(.cut))
    await s.undo()
    s.renderTask?.cancel()
    let before = s.document
    s.layerVia(.cut)
    s.geometryTask?.cancel()
    await s.geometryTask?.value
    s.renderTask?.cancel()
    XCTAssertEqual(s.document, before)
    XCTAssertNil(s.error)
    s.perform(.selection(nil))
    s.renderTask?.cancel()
    XCTAssertTrue(s.canLayerVia(.copy))
    XCTAssertFalse(s.canLayerVia(.cut))
  }
  @MainActor func testFactoryShortcutsRouteBothLayerViaCommands() throws {
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
    let menu = try XCTUnwrap(
      NSApp.mainMenu?.item(withTitle: "Layer")?.submenu?.item(withTitle: "New")?.submenu)
    let copy = try XCTUnwrap(menu.item(withTitle: "Layer Via Copy"))
    let cut = try XCTUnwrap(menu.item(withTitle: "Layer Via Cut"))
    XCTAssertEqual(copy.action, #selector(AppDelegate.layerViaCopy))
    XCTAssertEqual(cut.action, #selector(AppDelegate.layerViaCut))
    XCTAssertEqual(copy.keyEquivalent, "j")
    XCTAssertEqual(copy.keyEquivalentModifierMask, [.command])
    XCTAssertEqual(cut.keyEquivalent, "j")
    XCTAssertEqual(cut.keyEquivalentModifierMask, [.command, .shift])
  }
}
