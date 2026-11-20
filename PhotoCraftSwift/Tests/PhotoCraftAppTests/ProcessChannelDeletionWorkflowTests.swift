import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ProcessChannelDeletionWorkflowTests: XCTestCase {
  private func source(layered: Bool = true) throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3)
    document.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(0.2, 0.4, 0.6)))
    if layered {
      var hidden = Layer(name: "Hidden", content: .raster(try Surface(width: 4, height: 3, fill: .white)))
      hidden.visible = false
      document.layers.append(hidden)
    }
    return document
  }

  @MainActor func testNativeDeleteMenuUsesCurrentComponentsAndConfirmOrImmediateTrash() async throws {
    let document = try source()
    let store = EditorStore(document: document)
    defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
    XCTAssertFalse(store.canDeleteSelectedChannel)
    try store.selectColorComponentRow(1, modifiers: [])
    try store.selectColorComponentRow(2, modifiers: [.shift])
    XCTAssertEqual(store.selectedProcessChannelsForDeletion, [1, 2])
    var prompts = 0
    store.flattenImageConfirmation = { request in
      prompts += 1
      XCTAssertEqual(request.hiddenLayerIDs, [document.layers[1].id])
      return false
    }
    store.deleteSelectedChannel()
    XCTAssertEqual(prompts, 1)
    XCTAssertEqual(store.document, document)
    XCTAssertTrue(store.session.undoStack.isEmpty)

    try store.session.startActionRecording(name: "Keep one channel", set: "Press")
    store.deleteSelectedChannel(fromTrash: true, modifiers: [.option])
    await store.geometryTask?.value
    XCTAssertEqual(prompts, 1)
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document.colorMode, .multichannel)
    XCTAssertTrue(store.document.layers.isEmpty)
    XCTAssertEqual(store.document.colorChannelNames, ["Cyan"])
    XCTAssertEqual(store.session.undoStack.last?.label, "Delete Channels")
    let snapshot = try XCTUnwrap(store.session.actionRecording?.snapshot)
    let library = try ActionLibraryFile.decode(ActionLibraryFile(actions: [snapshot]).encoded())
    XCTAssertEqual(library.version, 75)
    var playback = document
    playback.id = UUID()
    let replayed = try RecordedActionRenderer.prepare(library.actions[0], in: playback)
    try replayed.command.apply(to: &playback)
    XCTAssertEqual(playback.colorChannelNames, store.document.colorChannelNames)
    XCTAssertEqual(try playback.inkChannel(playback.inkChannelTargets[0]), try store.document.inkChannel(store.document.inkChannelTargets[0]))
    await store.undo()
    XCTAssertEqual(store.document, document)
  }

  @MainActor func testHTTPLayeredConsentAndNumberValidationWithActiveProcessSelection() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      let document = try self.source()
      doc.store.session = EditorSession(document: document)
      try service.share(doc)
      try doc.store.selectColorComponentRow(0, modifiers: [])
      let api = ProcessChannelDeletionAPI.name
      let params: [String: Any] = ["components": [0], "mergeVisible": true]
      let state = doc.store.processChannelDeletionState
      XCTAssertEqual(state["selectedComponents"] as? [Int], [0])
      XCTAssertEqual(state["requiresMerge"] as? Bool, true)
      let missingPermission = try await helper.edit(service, doc, api, ["components": [0]])
      XCTAssertEqual(missingPermission, 422)
      let malformed = try await helper.edit(service, doc, api, ["components": [0, 0]])
      XCTAssertEqual(malformed, 400)
      let stale = try await helper.edit(service, doc, api, params, revision: "old")
      XCTAssertEqual(stale, 409)
      XCTAssertEqual(doc.store.document, document)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let okay = try await helper.edit(service, doc, api, params)
      XCTAssertEqual(okay, 200)
      XCTAssertEqual(doc.store.document.colorChannelNames, ["Magenta", "Yellow"])
      XCTAssertTrue(doc.store.selectedProcessChannelsForDeletion.isEmpty)
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      let undo = try await helper.edit(service, doc, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(doc.store.document, document)
    }
  }
}
