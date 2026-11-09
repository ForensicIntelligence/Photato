import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeSkyWorkflowTests: XCTestCase {
  func fixture() throws -> (document: CraftDocument, skyID: UUID) {
    let size = Surface.maxDimension
    var document = try CraftDocument(width: size, height: size)
    document.layers[0].content = .raster(try Surface(width: size, height: size, fill: Pixel(0.3, 0.6, 0.95)))
    var sky = Layer(name: "Owned full-size sky", content: .raster(try Surface(width: size, height: size, fill: Pixel(0.9, 0.4, 0.2))))
    sky.visible = false; document.layers.append(sky)
    return (document, sky.id)
  }
  @MainActor private func settled(_ draft: SkyWorkspace) async { await draft.task?.value; await draft.task?.value }

  @MainActor func testLargeNativeWorkspaceCancelManualRefinementCommitAndHistory() async throws {
    let fixture = try fixture()
    let store = EditorStore(document: fixture.document, actions: ActionLibrary(), brushes: BrushLibrary(), skies: SkyLibrary())
    defer { store.cancelSkyReplacement(); store.renderTask?.cancel() }
    let original = store.document
    XCTAssertTrue(store.canSelectSky); XCTAssertTrue(store.canReplaceSky)
    store.beginSkyReplacement(); let cancelled = try XCTUnwrap(store.skyWorkspace)
    await settled(cancelled); cancelled.useLayer(fixture.skyID); await settled(cancelled)
    XCTAssertTrue(cancelled.canCommit, cancelled.error ?? "Missing output")
    XCTAssertEqual(cancelled.originalImage?.width, 2048); XCTAssertEqual(cancelled.previewImage?.height, 2048)
    store.cancelSkyReplacement(); XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginSkyReplacement(); let draft = try XCTUnwrap(store.skyWorkspace)
    await settled(draft); draft.useLayer(fixture.skyID); await settled(draft)
    draft.add = false; draft.size = 12; draft.hardness = 1
    draft.beginStroke(.init(129, 131), alternate: false); draft.endStroke(); await settled(draft)
    XCTAssertEqual(draft.mask?.coverage(x: 129, y: 131), 0)
    XCTAssertTrue(draft.canCommit, draft.error ?? "No refined output")
    let expected = try XCTUnwrap(draft.edit).result
    store.commitSkyReplacement(); await draft.commitTask?.value
    XCTAssertNil(store.skyWorkspace); XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)) == expected)
    _ = await store.requestHistory(redo: false).value; XCTAssertEqual(store.document, original)
    _ = await store.requestHistory(redo: true).value; XCTAssertEqual(store.document, expected)
  }

  @MainActor func testLargeSharedAPISelectionReplacementNativeEquivalenceAndStaleGuard() async throws {
    let helper = AutomationTests(), fixture = try fixture()
    try await helper.withService(skies: SkyLibrary(), pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      defer { store.cancelSkyReplacement(); store.renderTask?.cancel() }
      store.session = EditorSession(document: fixture.document); try service.share(document)
      let original = store.document
      var selected = original
      try SkyReplacementInput.selection(original, layerID: original.activeLayerID).apply(to: &selected)
      let selectionStatus = try await helper.edit(service, document, "selection.sky")
      XCTAssertEqual(selectionStatus, 200); XCTAssertEqual(store.document, selected)
      _ = await store.requestHistory(redo: false).value
      let revision = service.revision(store)
      var settings = SkyReplacementSettings(); settings.fadeEdge = 0
      let source = try SkyWorkspace.sourceLayer(fixture.skyID, in: original)
      let expected = try SkyReplacementInput.prepare(original).edit(sky: source, name: source.name, settings: settings).edit.result
      let status = try await helper.edit(service, document, "sky.replace",
        ["sourceLayerID": fixture.skyID.uuidString, "settings": BrushAPI.json(settings)])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(try Renderer.composite(store.document), try Renderer.composite(expected))
      XCTAssertEqual(store.document.layers.map(\.mask), expected.layers.map(\.mask))
      XCTAssertEqual(store.document.layers.map(\.affine), expected.layers.map(\.affine))
      XCTAssertEqual(store.session.undoStack.count, 1)
      let committed = store.document
      let stale = try await helper.edit(service, document, "sky.replace", ["sourceLayerID": fixture.skyID.uuidString], revision: revision)
      XCTAssertEqual(stale, 409); XCTAssertEqual(store.document, committed)
      _ = await store.requestHistory(redo: false).value; XCTAssertEqual(store.document, original)
      store.aiBusy = true; XCTAssertFalse(store.canReplaceSky); store.aiBusy = false
      let encoded = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: store.skyState))
      XCTAssertNoThrow(try BrushAPI.merge(encoded, schema: SkyAPI.stateSchema))
    }
  }

  @MainActor func testSkyPresetBeyondOldLimitAndCapacityDiscovery() throws {
    var document = try CraftDocument(width: 3072, height: 3072)
    document.layers[0].content = .raster(try Surface(width: 3072, height: 3072, fill: Pixel(0.3, 0.6, 0.95)))
    let data = try RasterIO.encoded(document)
    let preset = SkyPreset(name: "Owned nine-megapixel sky", data: data)
    let decoded = try preset.document()
    XCTAssertEqual(decoded.width, 3072); XCTAssertEqual(decoded.height, 3072)
    let library = SkyLibrary(); try library.add(preset); XCTAssertEqual(library.skies.count, 1)
    let capacity = try XCTUnwrap(SkyAPI.capabilities["largeCanvas"] as? [String: Any])
    XCTAssertEqual(capacity["maximumDimension"] as? Int, Surface.maxDimension)
    XCTAssertEqual(capacity["maximumPixels"] as? Int, Surface.maxPixels)
    XCTAssertEqual(capacity["maximumOverviewSide"] as? Int, 2048)
    XCTAssertFalse((SkyAPI.capabilities["limits"] as? String ?? "").contains("sharing4,194,304"))
    var fixture = try fixture().document
    fixture.colorSpace = "Owned source profile label"; fixture.profileIsUntagged = true
    let source = try SkyWorkspace.sourceLayer(fixture.layers[0].id, in: fixture)
    XCTAssertEqual(source.colorSpace, fixture.colorSpace); XCTAssertEqual(source.profileIsUntagged, true)
  }
}
