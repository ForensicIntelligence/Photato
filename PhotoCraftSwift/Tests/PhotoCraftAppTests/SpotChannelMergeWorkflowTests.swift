import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SpotChannelMergeWorkflowTests: XCTestCase {
  private func fixture() throws -> (CraftDocument, UUID) {
    var source = try CraftDocument(width: 4, height: 3)
    source.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0.7, 0.4, 0.3)))
    source.layers[0].background = true
    var hidden = Layer(name: "Hidden", content: .raster(try Surface(width: 4, height: 3, fill: .white)))
    hidden.visible = false
    source.layers.append(hidden)
    let spot = try source.newSpotChannel(name: "Sage", ink: .init(color: Pixel(0.4, 0.8, 0.4), solidity: 0.6), density: 0.5)
    source.alphaChannels = [spot]
    return (source, spot.id)
  }

  @MainActor func testNativeConfirmationCancelUndoAndPortableActionsReplay() async throws {
    let (source, id) = try fixture()
    let store = EditorStore(document: source)
    defer { store.geometryTask?.cancel(); store.renderTask?.cancel() }
    try store.selectAlphaChannel(id, overlay: true)
    XCTAssertTrue(store.canMergeSpotChannel(store.alphaEditingID))
    store.flattenImageConfirmation = { request in
      XCTAssertEqual(request.hiddenLayerIDs, [source.layers[1].id])
      return false
    }
    store.requestSpotChannelMerge(id)
    XCTAssertEqual(store.document, source)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    let alert = FlattenImageAlert.make(operation: "Merge Spot Channel")
    XCTAssertTrue(alert.informativeText.contains("Merge Spot Channel"))

    try store.session.startActionRecording(name: "Proof spot", set: "Prepress")
    store.flattenImageConfirmation = { _ in true }
    store.requestSpotChannelMerge(id)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.alphaEditingID)
    XCTAssertTrue(store.document.layers[0].isBackground)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(store.session.undoStack.last?.label, "Merge Spot Channel")

    let recording = try XCTUnwrap(store.session.actionRecording?.snapshot)
    let archive = try ActionLibraryFile.decode(ActionLibraryFile(actions: [recording]).encoded())
    XCTAssertEqual(archive.version, 74)
    var target = source
    target.id = UUID()
    target.alphaChannels?[0].id = UUID()
    let replay = try RecordedActionRenderer.prepare(archive.actions[0], in: target)
    try replay.command.apply(to: &target)
    XCTAssertEqual(target.layers, store.document.layers)
    XCTAssertNil(target.alphaChannels)
    await store.undo()
    XCTAssertEqual(store.document, source)
  }

  @MainActor func testHTTPExplicitHiddenConsentTargetRevisionAndUndoMatchNative() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let (source, id) = try self.fixture()
      document.store.session = EditorSession(document: source)
      try service.share(document)
      try document.store.selectAlphaChannel(id, overlay: true)
      let hidden = document.store.spotChannelMergeState
      XCTAssertEqual(hidden["requiresHiddenLayerConfirmation"] as? Bool, true)
      XCTAssertEqual(hidden["eligibleChannelIDs"] as? [String], [id.uuidString])
      let params: [String: Any] = ["channelID": id.uuidString, "discardHiddenLayers": true]
      let wrong = try await helper.edit(service, document, SpotChannelMergeAPI.name, ["channelID": UUID().uuidString])
      XCTAssertEqual(wrong, 422)
      let stale = try await helper.edit(service, document, SpotChannelMergeAPI.name, params, revision: "stale")
      XCTAssertEqual(stale, 409)
      let missingConsent = try await helper.edit(service, document, SpotChannelMergeAPI.name, ["channelID": id.uuidString])
      XCTAssertEqual(missingConsent, 422)
      XCTAssertEqual(document.store.document, source)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      var manual = source
      try SpotChannelMerge.command(source, channelID: id, discardHiddenLayers: true).apply(to: &manual)
      let accepted = try await helper.edit(service, document, SpotChannelMergeAPI.name, params)
      XCTAssertEqual(accepted, 200)
      XCTAssertEqual(document.store.document, manual)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      XCTAssertNil(document.store.alphaEditingID)
      let undone = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200)
      XCTAssertEqual(document.store.document, source)
    }
  }
}
