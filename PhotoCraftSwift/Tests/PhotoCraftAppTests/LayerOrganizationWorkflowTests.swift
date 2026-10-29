import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class LayerOrganizationWorkflowTests: XCTestCase {
  @MainActor func testContextColorTargetsSelectionOrClickedRowAndNoOpIsClean() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.selectedLayerIDs = [ids[0], ids[1]]
    var changes = 0
    store.onChange = { _ in changes += 1 }
    store.setLayerColor(.orange, context: ids[1])
    XCTAssertEqual(store.selectedLayerColor(context: ids[1]), .orange)
    XCTAssertEqual(store.selectedLayerIDs, [ids[0], ids[1]])
    XCTAssertEqual(
      store.document.layers.map(\.colorLabel), [.orange, .orange, LayerColorLabel.none])
    XCTAssertEqual(changes, 1)
    store.setLayerColor(.orange, context: ids[0])
    XCTAssertEqual(changes, 1)
    store.setLayerColor(.blue, context: ids[2])
    XCTAssertEqual(store.selectedLayerIDs, [ids[2]])
    XCTAssertEqual(store.document.activeLayerID, ids[2])
    XCTAssertEqual(store.document.layers.map(\.colorLabel), [.orange, .orange, .blue])
    store.selectedLayerIDs = [ids[0], ids[2]]
    XCTAssertNil(store.selectedLayerColor())
    await store.undo()
    XCTAssertEqual(store.document.layers[2].colorLabel, LayerColorLabel.none)
  }

  @MainActor func testSelectedShowHidePreservesSelectionAndUpdatesMenuTitle() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let original = store.document
    let ids = original.layers.map(\.id)
    store.selectedLayerIDs = [ids[0], ids[2]]
    XCTAssertEqual(store.layerVisibilityMenuTitle(), "Hide Layers")
    store.toggleSelectedLayerVisibility()
    XCTAssertEqual(store.document.layers.map(\.visible), [false, true, false])
    XCTAssertEqual(store.selectedLayerIDs, [ids[0], ids[2]])
    XCTAssertEqual(store.layerVisibilityMenuTitle(), "Show Layers")
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.toggleSelectedLayerVisibility()
    XCTAssertEqual(store.document, original)
    await store.undo()
    XCTAssertEqual(store.document.layers.map(\.visible), [false, true, false])
    await store.redo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testOptionEyeRestoresOriginalMixedStatesWithoutSelectingLayer() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.perform(.visibility(ids[1], false))
    let before = store.document
    let selected = store.groupSelectionIDs
    store.toggleLayerVisibility(ids[2], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [false, false, true])
    XCTAssertEqual(store.groupSelectionIDs, selected)
    XCTAssertNotNil(store.layerVisibilityIsolation)
    store.setLayerColor(.green)
    XCTAssertNotNil(
      store.layerVisibilityIsolation, "Unrelated label edits keep restoration available")
    store.toggleLayerVisibility(ids[2], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), before.layers.map(\.visible))
    XCTAssertEqual(store.document.layers[0].colorLabel, .green)
    XCTAssertNil(store.layerVisibilityIsolation)
  }

  @MainActor func testSwitchingSoloTargetRetainsBaselineAndManualVisibilityInvalidates() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    store.toggleLayerVisibility(ids[1], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [false, true, false])
    store.toggleLayerVisibility(ids[1], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, true, true])
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    store.toggleLayerVisibility(ids[2])
    XCTAssertNil(store.layerVisibilityIsolation)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, false, true])
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, false, true])
  }

  @MainActor func testUndoTopologyAndDocumentReadRetireIsolation() async throws {
    let document = CraftNSDocument(model: try GroupWorkflowTests().store().document)
    let store = document.store
    defer { document.close() }
    let id = store.document.layers[0].id
    store.toggleLayerVisibility(id, modifiers: .option)
    let data = try document.data(ofType: CraftNSDocument.nativeType)
    try document.read(from: data, ofType: CraftNSDocument.nativeType)
    XCTAssertNil(store.layerVisibilityIsolation)
    store.toggleLayerVisibility(id, modifiers: .option)
    store.perform(.addLayer(Layer(name: "New", content: .fill(.white))))
    XCTAssertNil(store.layerVisibilityIsolation)
    store.toggleLayerVisibility(id, modifiers: .option)
    await store.undo()
    XCTAssertNil(store.layerVisibilityIsolation)
    await store.redo()
    XCTAssertNil(store.layerVisibilityIsolation)
  }

  @MainActor func testBlockedAndStaleTargetsCannotEditOrRetireValidIsolation() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let id = store.document.layers[0].id
    store.toggleLayerVisibility(id, modifiers: .option)
    let before = store.document
    let undoCount = store.session.undoStack.count
    store.geometryBusy = true
    store.setLayerColor(.red)
    store.toggleSelectedLayerVisibility()
    store.toggleLayerVisibility(id, modifiers: .option)
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.session.undoStack.count, undoCount)
    XCTAssertNotNil(store.layerVisibilityIsolation)
    store.geometryBusy = false
    store.selectedLayerIDs = [id, UUID()]
    XCTAssertFalse(store.canOrganizeLayers())
    store.setLayerColor(.red)
    store.toggleSelectedLayerVisibility()
    store.toggleLayerVisibility(UUID(), modifiers: .option)
    XCTAssertEqual(store.document, before)
    XCTAssertNotNil(store.layerVisibilityIsolation)
  }

  @MainActor func testNonVisibilityUndoKeepsOriginalSoloSnapshot() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.perform(.visibility(ids[1], false))
    let original = LayerOrganization.visibility(in: store.document)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    store.setLayerColor(.red)
    await store.undo()
    XCTAssertNotNil(store.layerVisibilityIsolation)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    XCTAssertEqual(LayerOrganization.visibility(in: store.document), original)
  }

  @MainActor func testExternalVisibilityEditCannotBeOverwrittenByStaleRestore() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    try store.session.execute(.visibility(ids[2], true))
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, false, false])
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, false, true])
  }

  @MainActor func testIsolationOwnershipStaysWithEachDocument() throws {
    let first = try GroupWorkflowTests().store()
    let second = try GroupWorkflowTests().store()
    defer {
      first.renderTask?.cancel()
      second.renderTask?.cancel()
    }
    let firstID = first.document.layers[0].id
    let secondID = second.document.layers[2].id
    first.toggleLayerVisibility(firstID, modifiers: .option)
    second.toggleLayerVisibility(secondID, modifiers: .option)
    first.toggleLayerVisibility(firstID, modifiers: .option)
    XCTAssertEqual(first.document.layers.map(\.visible), [true, true, true])
    XCTAssertEqual(second.document.layers.map(\.visible), [false, false, true])
    XCTAssertNotNil(second.layerVisibilityIsolation)
  }

  @MainActor func testAlreadySoloWithoutSnapshotRevealsAllAsSourceDoes() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.perform(.layerVisibility([ids[0]: false, ids[1]: true, ids[2]: false]))
    let before = store.document
    XCTAssertNil(store.layerVisibilityIsolation)
    store.toggleLayerVisibility(ids[1], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, true, true])
    XCTAssertNil(store.layerVisibilityIsolation)
    await store.undo()
    XCTAssertEqual(store.document, before)
  }

  @MainActor func testSoloAncestorClickRestoresSnapshotWithoutRevealingHiddenChildren() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.selectedLayerIDs = [ids[0], ids[1]]
    store.groupSelection()
    let group = try XCTUnwrap(store.activeLayer?.id)
    store.perform(.visibility(ids[1], false))
    let original = LayerOrganization.visibility(in: store.document)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    store.toggleLayerVisibility(group, modifiers: .option)
    XCTAssertEqual(LayerOrganization.visibility(in: store.document), original)
    XCTAssertNil(store.layerVisibilityIsolation)
  }

  @MainActor func testFactoryCommandCommaRoutesSelectedVisibilityAndDynamicTitle() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let document = CraftNSDocument(model: try GroupWorkflowTests().store().document)
      app.controller.addDocument(document)
      document.makeWindowControllers()
      XCTAssertTrue(app.controller.documentWindows.activate(document))
      defer { document.close() }
      let item = try XCTUnwrap(
        PhotoshopMenuTests().allItems(menu).first {
          $0.identifier?.rawValue == "Layer > Hide Layers"
        })
      XCTAssertEqual(item.action, #selector(AppDelegate.toggleLayerVisibility))
      XCTAssertEqual(item.keyEquivalent, ",")
      XCTAssertEqual(item.keyEquivalentModifierMask, .command)
      XCTAssertTrue(app.validateMenuItem(item))
      XCTAssertEqual(item.title, "Hide Layers")
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
          windowNumber: 0, context: nil, characters: ",", charactersIgnoringModifiers: ",",
          isARepeat: false, keyCode: 43))
      XCTAssertTrue(menu.performKeyEquivalent(with: event))
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
      XCTAssertTrue(app.validateMenuItem(item))
      XCTAssertEqual(item.title, "Show Layers")
      app.toggleLayerVisibility()
      XCTAssertTrue(document.store.activeLayer!.visible)
      document.store.confirmingLayerDeletion = true
      XCTAssertFalse(app.validateMenuItem(item))
    }
  }

  func testChangedLabelsPreserveExactRenderedSamplesAndPSDAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 3, height: 2, depth: depth)
      document.layers[0].content = .raster(
        try Surface(width: 3, height: 2, depth: depth, fill: Pixel(0.25, 0.5, 0.75, 0.8)))
      let original = try Renderer.composite(document)
      for color in LayerColorLabel.allCases {
        try Command.layerColor([document.layers[0].id], color).apply(to: &document)
        XCTAssertEqual(try Renderer.composite(document), original)
        let read = try PSDCodec.read(PSDCodec.writeRasterLayers(document))
        XCTAssertEqual(read.layers[0].colorLabel, color)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
      }
    }
  }
}
