import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

@MainActor final class MemoryClipboard: ClipboardAccess {
  var changeCount = 0
  var value: ClipboardRepresentations?
  var rejectWrites = false
  var hasImage: Bool { value != nil }
  func read() throws -> ClipboardInput {
    guard let value else { throw CraftError.invalid("Empty") }
    return .native(value.native)
  }
  func write(_ value: ClipboardRepresentations) throws {
    if rejectWrites { throw CraftError.unavailable("Rejected clipboard write") }
    self.value = value
    changeCount += 1
  }
}

final class ClipboardWorkflowTests: XCTestCase {
  @MainActor func testCopyIsReadOnlyAndCrossDocumentPasteRetainsLayersWithUndo() async throws {
    let clipboard = MemoryClipboard()
    var source = try CraftDocument(width: 5, height: 3, depth: .f32)
    source.layers[0].content = .raster(
      try Surface(width: 3, height: 2, depth: .f32, fill: Pixel(0.2, 0.7, 0.9, 0.6)))
    source.layers[0].x = -2
    source.layers[0].y = 1
    source.layers[0].opacity = 0.7
    let a = EditorStore(document: source, clipboard: clipboard)
    a.renderTask?.cancel()
    a.copyImage()
    await a.geometryTask?.value
    XCTAssertNil(a.error)
    XCTAssertEqual(a.document, source)
    XCTAssertTrue(a.session.undoStack.isEmpty)
    XCTAssertNotNil(clipboard.value)
    let b = EditorStore(
      document: try CraftDocument(width: 20, height: 10, depth: .u16), clipboard: clipboard)
    b.renderTask?.cancel()
    let before = b.document
    b.pasteImage(.inPlace)
    await b.geometryTask?.value
    b.renderTask?.cancel()
    XCTAssertNil(b.error)
    XCTAssertEqual(b.document.layers.count, 2)
    XCTAssertEqual(b.activeLayer?.x, -2)
    XCTAssertEqual(b.activeLayer?.y, 1)
    XCTAssertEqual(b.activeLayer?.opacity, 0.7)
    XCTAssertNotEqual(b.activeLayer?.id, source.layers[0].id)
    XCTAssertEqual(b.selectedLayerIDs, [b.activeLayer!.id])
    await b.undo()
    b.renderTask?.cancel()
    XCTAssertEqual(b.document, before)
  }
  @MainActor func testFailedOrCancelledCutNeverDeletesPixelsAndStaleClipboardIsNotOverwritten()
    async throws
  {
    let clipboard = MemoryClipboard()
    let store = EditorStore(document: try CraftDocument(width: 4, height: 2), clipboard: clipboard)
    store.renderTask?.cancel()
    let original = store.document
    clipboard.rejectWrites = true
    store.copyImage(cut: true)
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertNotNil(store.error)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    clipboard.rejectWrites = false
    store.error = nil
    store.copyImage(cut: true)
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, original)
    XCTAssertNil(clipboard.value)
    store.copyImage(cut: true)
    clipboard.changeCount += 1
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, original)
    XCTAssertNil(clipboard.value)
    XCTAssertNotNil(store.error)
  }
  @MainActor func testCutWritesClipboardBeforeEditingAndUndoDoesNotRevertClipboard() async throws {
    let clipboard = MemoryClipboard()
    var doc = try CraftDocument(width: 4, height: 2)
    doc.selection = IntRect(x: 1, y: 0, width: 2, height: 1)
    let store = EditorStore(document: doc, clipboard: clipboard)
    store.renderTask?.cancel()
    store.copyImage(cut: true)
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertNil(store.error)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Cut")
    let transferred = try clipboard.read().decoded()
    XCTAssertEqual(transferred.bounds, IntRect(x: 1, y: 0, width: 2, height: 1))
    XCTAssertEqual(try Renderer.composite(store.document).pixel(x: 1, y: 0).a, 0)
    await store.undo()
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, doc)
    XCTAssertEqual(try clipboard.read().decoded(), transferred)
    store.pasteImage(.into)
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertNil(store.error)
    XCTAssertEqual(store.activeLayer?.maskProperties?.linked, false)
    XCTAssertEqual(store.session.undoStack.last?.label, "Paste Into")
  }
  @MainActor func testPasteCancellationAndTargetValidationDoNotChangeDocument() async throws {
    let clipboard = MemoryClipboard()
    try clipboard.write(
      ClipboardRepresentations(.pixels(Surface(width: 2, height: 2, fill: .white))))
    let store = EditorStore(document: try CraftDocument(width: 4, height: 4), clipboard: clipboard)
    store.renderTask?.cancel()
    let before = store.document
    XCTAssertFalse(store.canPaste(.into))
    store.pasteImage()
    store.geometryTask?.cancel()
    await store.geometryTask?.value
    store.renderTask?.cancel()
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.createMask(.revealAll)
    store.renderTask?.cancel()
    XCTAssertTrue(store.canPaste(.centered))
    XCTAssertTrue(store.canCopy())
    XCTAssertFalse(store.canPaste(.into))
    XCTAssertFalse(store.canCopy(merged:true))
  }
  @MainActor func testNamedSystemPasteboardUsesNativeTIFFAndPNGWithoutTouchingGeneralClipboard()
    throws
  {
    let pasteboard = NSPasteboard(name: .init("PhotatoTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let access = SystemClipboard(pasteboard: pasteboard)
    let value = try ClipboardContent.pixels(
      Surface(width: 2, height: 3, depth: .f32, fill: Pixel(0.7, 0.2, 0.1, 0.4)))
    let representations = try ClipboardRepresentations(value)
    try access.write(representations)
    XCTAssertTrue(access.hasImage)
    XCTAssertEqual(try access.read().decoded(), value)
    XCTAssertEqual(pasteboard.data(forType: .tiff), representations.tiff)
    XCTAssertEqual(pasteboard.data(forType: .png), representations.png)
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setData(try XCTUnwrap(representations.png), forType: .png))
    XCTAssertEqual(try access.read().decoded().bounds.width, 2)
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString("Text", forType: .string))
    XCTAssertFalse(access.hasImage)
    XCTAssertThrowsError(try access.read())
  }
  @MainActor func testMenusKeepTextResponderActionsAndPhotoshopClipboardShortcuts() {
    _ = NSApplication.shared
    let previous = (NSApp.mainMenu, NSApp.windowsMenu, NSApp.helpMenu)
    defer {
      NSApp.mainMenu = previous.0
      NSApp.windowsMenu = previous.1
      NSApp.helpMenu = previous.2
    }
    let delegate = AppDelegate()
    delegate.buildMenus()
    let edit = NSApp.mainMenu!.item(withTitle: "Edit")!.submenu!
    for (title, key, selector) in [
      ("Cut", "x", #selector(NSText.cut(_:))),
      ("Copy", "c", #selector(NSText.copy(_:))), ("Paste", "v", #selector(NSText.paste(_:))),
    ] {
      let item = edit.item(withTitle: title)!
      XCTAssertNil(item.target)
      XCTAssertEqual(item.action, selector)
      XCTAssertEqual(item.keyEquivalent, key)
      XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    }
    let merged = edit.item(withTitle: "Copy Merged")!
    XCTAssertEqual(merged.keyEquivalent, "c")
    XCTAssertEqual(merged.keyEquivalentModifierMask, [.command, .shift])
    let special = edit.item(withTitle: "Paste Special")!.submenu!
    XCTAssertEqual(
      special.item(withTitle: "Paste in Place")!.keyEquivalentModifierMask, [.command, .shift])
    XCTAssertEqual(
      special.item(withTitle: "Paste Into")!.keyEquivalentModifierMask, [.command, .option, .shift])
    XCTAssertEqual(special.item(withTitle: "Paste Outside")!.keyEquivalent, "")
  }
}
