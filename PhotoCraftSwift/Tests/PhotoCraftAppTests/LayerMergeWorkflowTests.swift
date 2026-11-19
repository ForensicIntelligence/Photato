import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class LayerMergeWorkflowTests: XCTestCase {
  @MainActor func store() throws -> EditorStore {
    var d = try CraftDocument(width: 5, height: 4)
    d.layers.append(
      Layer(
        name: "Top",
        content: .raster(
          try Surface(width: 3, height: 2, fill: Pixel(0.7, 0.2, 0.1, 0.6)))))
    d.activeLayerID = d.layers[1].id
    return EditorStore(document: d)
  }
  @MainActor func testDefaultMergeRoutingUndoAndCancellation() async throws {
    for operation in [LayerMergeOperation.down, .selected, .visible] {
      let s = try store()
      s.renderTask?.cancel()
      let before = s.document
      XCTAssertEqual(s.menuMergeOperation, .down)
      if operation == .selected { s.selectedLayerIDs = Set(s.document.layers.map(\.id)) }
      XCTAssertTrue(s.canMerge(operation))
      s.merge(operation)
      await s.geometryTask?.value
      s.renderTask?.cancel()
      XCTAssertNil(s.error)
      XCTAssertEqual(s.document.layers.count, 1)
      XCTAssertEqual(s.selectedLayerIDs, Set([try XCTUnwrap(s.document.activeLayerID)]))
      XCTAssertEqual(s.session.undoStack.last?.label, operation.rawValue)
      await s.undo()
      s.renderTask?.cancel()
      XCTAssertEqual(s.document, before)
      s.selectedLayerIDs = Set(s.document.layers.map(\.id))
      s.merge(.selected)
      s.geometryTask?.cancel()
      await s.geometryTask?.value
      s.renderTask?.cancel()
      XCTAssertEqual(s.document, before)
    }
  }
  @MainActor func testUnavailableContextsAndFactoryShortcuts() throws {
    let s = try store()
    s.renderTask?.cancel()
    s.geometryBusy = true
    XCTAssertFalse(s.canMerge(.down))
    s.geometryBusy = false
    s.perform(.visibility(s.document.layers[0].id, false))
    s.renderTask?.cancel()
    XCTAssertEqual(s.menuMergeOperation, .selected)
    XCTAssertFalse(s.canMerge(.down))
    XCTAssertFalse(s.canMerge(.visible))
    try PhotoshopMenuTests().withMenus { _, menu in
      let layer = try XCTUnwrap(menu.item(withTitle: "Layer")?.submenu)
      let merge = try XCTUnwrap(layer.item(withTitle: "Merge Layers"))
      let visible = try XCTUnwrap(layer.item(withTitle: "Merge Visible"))
      XCTAssertEqual(merge.action, #selector(AppDelegate.mergeLayers))
      XCTAssertEqual(merge.keyEquivalent, "e")
      XCTAssertEqual(merge.keyEquivalentModifierMask, .command)
      XCTAssertEqual(visible.action, #selector(AppDelegate.mergeVisible))
      XCTAssertEqual(visible.keyEquivalent, "e")
      XCTAssertEqual(visible.keyEquivalentModifierMask, [.command, .shift])
      let stampSelected = try XCTUnwrap(layer.item(withTitle: "Stamp Layers"))
      let stampVisible = try XCTUnwrap(layer.item(withTitle: "Stamp Visible"))
      XCTAssertEqual(stampSelected.action, #selector(AppDelegate.stampLayers(_:)))
      XCTAssertEqual(stampVisible.action, #selector(AppDelegate.stampLayers(_:)))
      XCTAssertTrue(stampSelected.isAlternate)
      XCTAssertTrue(stampVisible.isAlternate)
      XCTAssertEqual(stampSelected.keyEquivalent, "e")
      XCTAssertEqual(stampVisible.keyEquivalent, "e")
      XCTAssertEqual(stampSelected.keyEquivalentModifierMask, [.command, .option])
      XCTAssertEqual(stampVisible.keyEquivalentModifierMask, [.command, .option, .shift])
      XCTAssertEqual(layer.item(withTitle: "Flatten Image")?.action, #selector(AppDelegate.flattenImage))
    }
  }

  @MainActor func testLayerMenuRoutesClippingBaseAndRecordsPortableMerge() async throws {
    var source = try AutomationLayerMergeTests().fixture("clipping-merge/chain-8-base")
    let base = try XCTUnwrap(source.layers.first { $0.name == "Clipping base" })
    let lower = try XCTUnwrap(source.layers.first { $0.name == "Lower clip" })
    source.activeLayerID = base.id
    let store = EditorStore(document: source)
    defer { store.renderTask?.cancel() }
    XCTAssertEqual(store.menuMergeOperation, .clippingMask)
    XCTAssertEqual(store.menuMergeTitle, "Merge Clipping Mask")
    XCTAssertTrue(store.canMerge(.clippingMask))
    XCTAssertEqual(store.layerPanelTitle(.merge, context: base.id), "Merge Clipping Mask")
    store.select(lower.id)
    XCTAssertEqual(store.menuMergeOperation, .down)
    store.select(base.id)
    let command = try LayerMergeIntent.adobeCommand(source, [base.id], .down)
    guard case .preparedLayerMerge(let edited) = command else { return XCTFail("Expected prepared merge") }
    XCTAssertEqual(edited.operation, .clippingMask)
    let recorded = ActionOperation(recording: command, in: source)
    let action = RecordedAction(name: "Merge clipping chain", steps: [
      RecordedActionStep(name: "Merge Clipping Mask", operation: recorded)
    ])
    XCTAssertEqual(ActionLibraryFile(actions: [action]).requiredVersion, 72)
    let rendered = try RecordedActionRenderer.prepare(action, in: source)
    var replayed = source
    try rendered.command.apply(to: &replayed)
    XCTAssertEqual(replayed, edited.result)
    store.merge(store.menuMergeOperation)
    await store.geometryTask?.value
    XCTAssertEqual(store.document, edited.result)
    XCTAssertEqual(store.session.undoStack.last?.label, "Merge Clipping Mask")
    XCTAssertEqual(store.selectedLayerIDs, [base.id])
    await store.undo()
    XCTAssertEqual(store.document, source)
  }

  @MainActor func testStampFromEditorRecordsPortableActionAndOneUndo() async throws {
    let s = try store()
    defer { s.renderTask?.cancel() }
    let original = s.document
    let prepared = try LayerMergePreparation.prepare(original, layerIDs: [try XCTUnwrap(original.activeLayerID)], operation: .stampVisible)
    let step = RecordedActionStep(name: "Stamp Visible", operation: ActionOperation(recording: .preparedLayerMerge(prepared), in: original))
    guard case .merge(let targets, .stampVisible) = step.operation else { return XCTFail("Missing stamp action") }
    XCTAssertTrue(targets.isEmpty)
    let action = RecordedAction(name: "Stamp test", steps: [step])
    XCTAssertEqual(ActionLibraryFile(actions: [action]).requiredVersion, 71)
    s.merge(.stampVisible)
    await s.geometryTask?.value
    XCTAssertNil(s.error)
    let edited = s.document
    XCTAssertEqual(edited.layers.count, original.layers.count + 1)
    XCTAssertEqual(edited.layers.dropLast(), ArraySlice(original.layers))
    XCTAssertEqual(s.session.undoStack.last?.label, "Stamp Visible")
    await s.undo()
    XCTAssertEqual(s.document, original)
    await s.redo()
    XCTAssertEqual(s.document, edited)
    var second = try store().document
    let bottom = second.layers[0].id
    second.activeLayerID = bottom
    let playback = try RecordedActionRenderer.prepare(action, in: second)
    let initial = second
    try playback.command.apply(to: &second)
    XCTAssertEqual(second.layers[1].id, second.activeLayerID)
    XCTAssertEqual(second.layers.filter { $0.id != second.activeLayerID }, initial.layers)
    XCTAssertNotEqual(second.activeLayerID, edited.activeLayerID)
  }
}
