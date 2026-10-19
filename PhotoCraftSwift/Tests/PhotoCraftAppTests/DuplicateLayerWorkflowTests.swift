import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class DuplicateLayerWorkflowTests: XCTestCase {
  @MainActor func testCancelInvalidNameAndOneChangeWithUndo() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let original = store.document
    var changes = 0
    store.onChange = { _ in changes += 1 }
    store.beginDuplicate()
    var draft = try XCTUnwrap(store.duplicateLayerDraft)
    XCTAssertEqual(draft.name, "Shape 0 copy")
    XCTAssertEqual(draft.title, "Duplicate Layer")
    store.cancelDuplicate()
    store.commitDuplicate(draft)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(changes, 0)
    store.beginDuplicate()
    draft = try XCTUnwrap(store.duplicateLayerDraft)
    draft.name = " "
    XCTAssertFalse(draft.valid)
    store.commitDuplicate(draft)
    XCTAssertNil(store.duplicateTask)
    draft.name = "Renamed copy"
    store.commitDuplicate(draft)
    await store.duplicateTask?.value
    XCTAssertNil(store.duplicateLayerDraft)
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(store.activeLayer?.name, "Renamed copy")
    XCTAssertEqual(store.session.undoStack.count, 1)
    let result = store.document
    store.undo()
    XCTAssertEqual(store.document, original)
    store.redo()
    XCTAssertEqual(store.document, result)
  }
  @MainActor func testMultipleSelectedLayersAndContextSelection() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.selectedLayerIDs = [ids[0], ids[2]]
    store.beginDuplicate(contextLayer: ids[2])
    let draft = try XCTUnwrap(store.duplicateLayerDraft)
    XCTAssertEqual(draft.roots.count, 2)
    XCTAssertEqual(draft.title, "Duplicate Layers")
    store.commitDuplicate(draft)
    await store.duplicateTask?.value
    XCTAssertEqual(store.selectedLayerIDs.count, 2)
    XCTAssertEqual(
      store.document.layers.map(\.name),
      ["Shape 0", "Shape 0 copy", "Shape 1", "Shape 2", "Shape 2 copy"])
    store.beginDuplicate(contextLayer: ids[1])
    XCTAssertEqual(store.duplicateLayerDraft?.roots.map(\.id), [ids[1]])
    store.cancelDuplicate()
  }
  @MainActor func testDraftBlocksEditsAndStaleSourceSelectionFails() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.beginDuplicate()
    let draft = try XCTUnwrap(store.duplicateLayerDraft)
    let original = store.document
    store.select(original.layers[2].id)
    store.addPixelLayer()
    store.newGroup()
    store.undo()
    XCTAssertEqual(store.document, original)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.canBeginDuplicate)
    XCTAssertNil(store.newLayerDraft)
    store.selectedLayerIDs = [original.layers[1].id]
    store.commitDuplicate(draft)
    XCTAssertNotNil(draft.error)
    XCTAssertNil(store.duplicateTask)
    store.cancelDuplicate()
    store.showGaps = true
    store.beginDuplicate()
    XCTAssertNil(store.duplicateLayerDraft)
  }
  @MainActor func testTransferHasDestinationUndoAndPreservesSource() async throws {
    let controller = CraftDocumentController()
    let source = CraftNSDocument(model: try CraftDocument(width: 8, height: 6))
    let target = CraftNSDocument(model: try CraftDocument(width: 4, height: 3))
    for d in [source, target] { controller.addDocument(d) }
    defer {
      source.close()
      target.close()
    }
    let originalSource = source.store.document
    let originalTarget = target.store.document
    source.store.beginDuplicate()
    let draft = try XCTUnwrap(source.store.duplicateLayerDraft)
    let previous = draft.destination
    draft.destination = .document(target.store.identity)
    draft.changedDestination(from: previous)
    XCTAssertEqual(draft.name, "Background")
    source.store.commitDuplicate(draft)
    await source.store.duplicateTask?.value
    XCTAssertNil(draft.error)
    XCTAssertNil(source.store.duplicateLayerDraft)
    XCTAssertEqual(source.store.document, originalSource)
    XCTAssertTrue(source.store.session.undoStack.isEmpty)
    XCTAssertEqual(target.store.document.layers.count, 2)
    XCTAssertEqual(target.store.session.undoStack.count, 1)
    XCTAssertEqual(target.store.activeLayer?.content, originalSource.layers[0].content)
    target.store.undo()
    XCTAssertEqual(target.store.document, originalTarget)
  }
  @MainActor func testStaleClosedAndBusyDestinationsAreRejected() async throws {
    let controller = CraftDocumentController()
    let source = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
    let target = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
    for d in [source, target] { controller.addDocument(d) }
    defer {
      source.close()
      target.close()
    }
    source.store.beginDuplicate()
    var draft = try XCTUnwrap(source.store.duplicateLayerDraft)
    draft.destination = .document(target.store.identity)
    target.store.beginNewLayer()
    source.store.commitDuplicate(draft)
    XCTAssertNotNil(draft.error)
    target.store.cancelNewLayer()
    target.store.addPixelLayer()
    source.store.commitDuplicate(draft)
    XCTAssertNotNil(draft.error)
    XCTAssertNil(source.store.duplicateTask)
    source.store.cancelDuplicate()
    source.store.beginDuplicate()
    draft = try XCTUnwrap(source.store.duplicateLayerDraft)
    draft.destination = .document(target.store.identity)
    controller.removeDocument(target)
    source.store.commitDuplicate(draft)
    XCTAssertNotNil(draft.error)
    XCTAssertNil(source.store.duplicateTask)
  }
  @MainActor func testNewDocumentAndCancellationDuringPreparation() async throws {
    let controller = CraftDocumentController()
    let source = CraftNSDocument(model: try CraftDocument(width: 8, height: 6, depth: .u16))
    controller.addDocument(source)
    var created: CraftNSDocument?
    defer {
      created?.close()
      source.close()
    }
    source.store.beginDuplicate()
    var draft = try XCTUnwrap(source.store.duplicateLayerDraft)
    draft.destination = .newDocument
    draft.documentName = "Separate"
    draft.name = "Artwork"
    source.store.commitDuplicate(draft)
    source.store.cancelDuplicate()
    await source.store.duplicateTask?.value
    XCTAssertNil(source.store.duplicateLayerDraft)
    XCTAssertFalse(source.store.geometryBusy)
    XCTAssertFalse(
      controller.documents.contains { ($0 as? CraftNSDocument)?.store.document.name == "Separate" })
    source.store.beginDuplicate()
    draft = try XCTUnwrap(source.store.duplicateLayerDraft)
    draft.destination = .newDocument
    draft.documentName = "Separate"
    draft.name = "Artwork"
    source.store.commitDuplicate(draft)
    await source.store.duplicateTask?.value
    created = controller.documents.compactMap { $0 as? CraftNSDocument }.first {
      $0.store.document.name == "Separate"
    }
    let doc = try XCTUnwrap(created)
    XCTAssertTrue(doc.isDocumentEdited)
    XCTAssertNil(doc.fileURL)
    XCTAssertEqual(doc.store.document.width, 8)
    XCTAssertEqual(doc.store.document.height, 6)
    XCTAssertEqual(doc.store.document.depth, .u16)
    XCTAssertEqual(doc.store.activeLayer?.name, "Artwork")
    XCTAssertTrue(source.store.session.undoStack.isEmpty)
    XCTAssertNil(source.store.duplicateLayerDraft)
  }
  @MainActor func testMenuOpensDialogAndPreservesFactoryShortcut() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let doc = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      defer { doc.close() }
      app.controller.addDocument(doc)
      doc.makeWindowControllers()
      XCTAssertTrue(app.controller.documentWindows.activate(doc))
      let layer = try XCTUnwrap(menu.item(withTitle: "Layer")?.submenu)
      let item = try XCTUnwrap(layer.item(withTitle: "Duplicate Layer…"))
      XCTAssertTrue(item.keyEquivalent.isEmpty)
      XCTAssertTrue(app.validateMenuItem(item))
      layer.performActionForItem(at: layer.index(of: item))
      XCTAssertNotNil(doc.store.duplicateLayerDraft)
      XCTAssertEqual(doc.store.document.layers.count, 1)
      XCTAssertFalse(app.validateMenuItem(item))
      doc.store.cancelDuplicate()
      doc.store.newGroup()
      XCTAssertTrue(app.validateMenuItem(item))
      XCTAssertEqual(item.title, "Duplicate Group…")
    }
  }
  @MainActor func testConcurrentDestinationChangeRejectsPreparedEdit() async throws {
    let controller = CraftDocumentController()
    let source = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
    let target = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
    for document in [source, target] { controller.addDocument(document) }
    defer {
      source.close()
      target.close()
    }
    source.store.beginDuplicate()
    let draft = try XCTUnwrap(source.store.duplicateLayerDraft)
    draft.destination = .document(target.store.identity)
    source.store.commitDuplicate(draft)
    // Simulates a concurrent external model update after the destination snapshot.
    try target.store.session.execute(.renameLayer(target.store.document.layers[0].id, "Changed"))
    let changed = target.store.document
    await source.store.duplicateTask?.value
    XCTAssertEqual(target.store.document, changed)
    XCTAssertEqual(target.store.session.undoStack.count, 1)
    XCTAssertNotNil(draft.error)
    XCTAssertTrue(source.store.duplicateLayerDraft === draft)
    XCTAssertFalse(source.store.geometryBusy)
    XCTAssertFalse(target.store.geometryBusy)
  }

  @MainActor func testNativeDialogFieldsFitAndSameDepthCopyPreservesSamples() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.beginDuplicate()
    let draft = try XCTUnwrap(store.duplicateLayerDraft)
    let host = NSHostingView(rootView: DuplicateLayerSheet(store: store, draft: draft))
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 560, height: 260), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let inputs = fields(host).filter(\.isEditable)
    XCTAssertEqual(inputs.count, 1)
    for field in inputs {
      let bounds = field.convert(field.bounds, to: host)
      XCTAssertTrue(host.bounds.contains(bounds))
      XCTAssertEqual(field.stringValue, "Shape 0 copy")
    }
    for depth in PixelDepth.allCases {
      var source = try CraftDocument(width: 3, height: 2, depth: depth)
      source.layers[0].content = .raster(
        try Surface(width: 3, height: 2, depth: depth, fill: Pixel(0.2, 0.4, 0.7, 0.8)))
      let copied = try LayerDuplication.newDocument(
        from: source, selected: [source.layers[0].id], documentName: "Copy")
      XCTAssertEqual(try Renderer.composite(copied), try Renderer.composite(source))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(copied)), copied)
      if depth != .f32 {
        let a = try PSDCodec.read(PSDCodec.writeRasterLayers(source))
        let b = try PSDCodec.read(PSDCodec.writeRasterLayers(copied))
        XCTAssertEqual(a.layers[0].content, b.layers[0].content)
      }
    }
  }
}
