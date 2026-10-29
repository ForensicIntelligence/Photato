import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class NewLayerWorkflowTests: XCTestCase {
  @MainActor func testCancelIsUntouchedAndCommitNotifiesDocumentOnce() async throws {
    let store = EditorStore(document: try CraftDocument(width: 3, height: 2))
    defer { store.renderTask?.cancel() }
    var changes = 0
    store.onChange = { _ in changes += 1 }
    let original = store.document
    store.beginNewLayer()
    var draft = try XCTUnwrap(store.newLayerDraft)
    XCTAssertEqual(draft.options.name, "Layer 1")
    XCTAssertEqual(draft.opacityText, "100")
    XCTAssertTrue(draft.canClip)
    draft.options.name = "Cancelled"
    store.cancelNewLayer()
    store.commitNewLayer(draft)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(changes, 0)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginNewLayer()
    draft = try XCTUnwrap(store.newLayerDraft)
    draft.options.name = "Retouch"
    draft.options.color = .magenta
    draft.options.mode = .multiply
    draft.options.clipped = true
    draft.options.neutralFill = true
    draft.opacityText = "42.5"
    store.commitNewLayer(draft)
    XCTAssertNil(store.newLayerDraft)
    XCTAssertNil(store.error)
    XCTAssertEqual(store.activeLayer?.name, "Retouch")
    XCTAssertEqual(store.activeLayer?.colorLabel, .magenta)
    XCTAssertEqual(store.activeLayer?.opacity, 0.425)
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.selectedLayerIDs, [try XCTUnwrap(store.activeLayer?.id)])
    let result = store.document
    await store.undo()
    XCTAssertEqual(store.document, original)
    await store.redo()
    XCTAssertEqual(store.document, result)
  }

  @MainActor func testDraftGuardsEditsSelectionHistoryAndOtherDrafts() async throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    defer { store.renderTask?.cancel() }
    store.addPixelLayer()
    let original = store.document
    store.beginNewLayer()
    let draft = try XCTUnwrap(store.newLayerDraft)
    XCTAssertTrue(store.hasToneDraft)
    XCTAssertFalse(store.canCreatePixelLayer())
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.canNavigateHistory)
    store.beginNewLayer()
    XCTAssertTrue(store.newLayerDraft === draft)
    store.select(original.layers[0].id)
    store.perform(.renameLayer(original.layers[0].id, "Wrong"))
    await store.undo()
    store.addPixelLayer()
    XCTAssertEqual(store.document, original)
    store.cancelNewLayer()
    store.geometryBusy = true
    store.beginNewLayer()
    XCTAssertNil(store.newLayerDraft)
    store.geometryBusy = false
    store.beginLevels()
    store.beginNewLayer()
    XCTAssertNil(store.newLayerDraft)
  }

  @MainActor func testInvalidInputAndStaleDocumentKeepDraftWithoutEditing() throws {
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    defer { store.renderTask?.cancel() }
    store.beginNewLayer()
    let draft = try XCTUnwrap(store.newLayerDraft)
    let original = store.document
    for text in ["", "abc", "nan", "inf", "-1", "100.1"] {
      draft.opacityText = text
      XCTAssertNil(draft.validatedOptions)
      store.commitNewLayer(draft)
      XCTAssertTrue(store.newLayerDraft === draft)
      XCTAssertEqual(store.document, original)
    }
    draft.opacityText = "0"
    XCTAssertNotNil(draft.validatedOptions)
    draft.options.name = "  "
    XCTAssertNil(draft.validatedOptions)
    draft.options.name = "Valid"
    try store.session.execute(.renameLayer(original.layers[0].id, "Changed externally"))
    let changed = store.document
    store.commitNewLayer(draft)
    XCTAssertNotNil(draft.error)
    XCTAssertTrue(store.newLayerDraft === draft)
    XCTAssertEqual(store.document, changed)
    XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testFooterPlainOptionCommandAndCombinedModifiers() throws {
    for modifiers: NSEvent.ModifierFlags in [[], .option, .command, [.command, .option]] {
      let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
      defer { store.renderTask?.cancel() }
      let base = try XCTUnwrap(store.activeLayer?.id)
      store.createPixelLayerFromFooter(modifiers: modifiers)
      if modifiers.contains(.option) {
        XCTAssertEqual(store.document.layers.count, 1)
        let draft = try XCTUnwrap(store.newLayerDraft)
        XCTAssertEqual(draft.below, modifiers.contains(.command))
        XCTAssertEqual(draft.canClip, !modifiers.contains(.command))
        store.commitNewLayer(draft)
      } else {
        XCTAssertNil(store.newLayerDraft)
      }
      XCTAssertEqual(store.document.layers.count, 2)
      XCTAssertEqual(store.document.layers[modifiers.contains(.command) ? 1 : 0].id, base)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testLockedGroupCanInsertBelowButCannotOpenInside() throws {
    var document = try CraftDocument(width: 2, height: 2)
    var folder = Layer(name: "Folder", content: .group(.init()))
    folder.locked = true
    document.layers.append(folder)
    document.activeLayerID = folder.id
    let store = EditorStore(document: document)
    defer { store.renderTask?.cancel() }
    XCTAssertFalse(store.canCreatePixelLayer())
    XCTAssertTrue(store.canCreatePixelLayer(below: true))
    store.beginNewLayer()
    XCTAssertNil(store.newLayerDraft)
    store.createPixelLayerFromFooter(modifiers: .command)
    XCTAssertEqual(store.document.layers.map(\.name), ["Background", "Layer 1", "Folder"])
  }

  @MainActor func testNativeMenuCommandUsesDialogAndBlocksDocumentSwitch() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let controller = app.controller
      let a = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      let b = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      defer {
        a.close()
        b.close()
        a.store.renderTask?.cancel()
        b.store.renderTask?.cancel()
      }
      for doc in [a, b] {
        controller.addDocument(doc)
        doc.makeWindowControllers()
      }
      XCTAssertTrue(controller.documentWindows.activate(a))
      let newMenu = try XCTUnwrap(
        menu.item(withTitle: "Layer")?.submenu?.item(withTitle: "New")?.submenu)
      let item = try XCTUnwrap(newMenu.item(withTitle: "Layer…"))
      XCTAssertEqual(item.keyEquivalent, "n")
      XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
      XCTAssertTrue(app.validateMenuItem(item))
      let before = a.store.document
      newMenu.performActionForItem(at: newMenu.index(of: item))
      XCTAssertNotNil(a.store.newLayerDraft)
      XCTAssertEqual(a.store.document, before)
      XCTAssertFalse(app.validateMenuItem(item))
      XCTAssertFalse(controller.documentWindows.activate(b))
      a.store.cancelNewLayer()
      XCTAssertTrue(controller.documentWindows.activate(b))
      XCTAssertNil(b.store.newLayerDraft)
    }
  }

  @MainActor func testNativeFieldsFitDialog() throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2))
    defer { store.renderTask?.cancel() }
    store.beginNewLayer()
    let draft = try XCTUnwrap(store.newLayerDraft)
    draft.options.mode = .linearLight
    let host = NSHostingView(rootView: NewLayerSheet(store: store, draft: draft))
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 560, height: 260),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let controls = descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    XCTAssertEqual(controls.count, 2)
    for field in controls {
      let rect = field.convert(field.bounds, to: host)
      XCTAssertGreaterThanOrEqual(rect.minX, 0)
      XCTAssertLessThanOrEqual(rect.maxX, host.bounds.width)
      XCTAssertGreaterThanOrEqual(rect.minY, 0)
      XCTAssertLessThanOrEqual(rect.maxY, host.bounds.height)
    }
    XCTAssertEqual(Set(controls.map(\.stringValue)), ["Layer 1", "100"])
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  func testPSDLabelsSurviveAllCodesAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 2, height: 2, depth: depth)
      for color in LayerColorLabel.allCases {
        var options = NewPixelLayerOptions(name: "Label \(color.rawValue)")
        options.color = color
        var layer = try options.layer(in: document)
        // Nonempty raster also exercises channel storage; label must not affect pixels.
        layer.content = .raster(try Surface(width: 2, height: 2, depth: depth, fill: .white))
        document.layers.append(layer)
      }
      let read = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
      XCTAssertEqual(read.layers.map(\.colorLabel), document.layers.map(\.colorLabel))
      XCTAssertEqual(read.layers.map(\.name), document.layers.map(\.name))
    }
  }
}
