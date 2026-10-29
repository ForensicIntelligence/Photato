import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class HistoryScratchWorkflowTests: XCTestCase {
  @MainActor func testDesktopAndHTTPHistoryShareScratchAndTransactionalFailures() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
        "HistoryHTTP-" + UUID().uuidString)
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: parent) }
      let store = document.store
      let original = store.document
      let layerID = try XCTUnwrap(original.activeLayerID)
      store.session = EditorSession(document: original, historyByteLimit: 0, scratchParent: parent)
      try service.share(document)
      let renamed = try await api.edit(
        service, document, "layer.rename", ["layerID": layerID.uuidString, "name": "On disk"])
      XCTAssertEqual(renamed, 200)
      XCTAssertEqual(store.session.historySpilledStates, 1)
      XCTAssertTrue(document.isDocumentEdited)
      let edited = store.document
      let oldRevision = service.revision(store)
      let navigationResult1 = await store.undo()
      XCTAssertTrue(navigationResult1)
      XCTAssertEqual(store.document, original)
      XCTAssertFalse(document.isDocumentEdited)
      let redone = try await api.edit(service, document, "history.redo")
      XCTAssertEqual(redone, 200)
      XCTAssertEqual(store.document, edited)
      XCTAssertTrue(document.isDocumentEdited)
      let stale = try await api.edit(service, document, "history.undo", revision: oldRevision)
      XCTAssertEqual(stale, 409)
      store.geometryBusy = true
      let busy = try await api.edit(service, document, "history.undo")
      store.geometryBusy = false
      XCTAssertEqual(busy, 409)
      let share = try XCTUnwrap(service.shares.first)
      let state = service.state(share, document: document)
      let storage = try XCTUnwrap(state["historyStorage"] as? [String: Int])
      XCTAssertEqual(storage["undoStates"], 1)
      XCTAssertEqual(storage["spilledStates"], 1)
      XCTAssertEqual(storage["residentPayloadBytes"], 0)
      XCTAssertEqual(storage["sharedScratchBytes"], store.session.historyDiskBytes)
      let capabilities = try await api.request(service, path: "/v1/capabilities")
      XCTAssertEqual(capabilities.0.statusCode, 200)
      let discovery = try XCTUnwrap(
        JSONSerialization.jsonObject(with: capabilities.1) as? [String: Any])
      let schemas = try XCTUnwrap(discovery["stateSchemas"] as? [String: Any])
      let schema = try XCTUnwrap(schemas["historyStorage"] as? [String: Any])
      XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), Set(storage.keys))
      let revision = service.revision(store)
      let directory = try XCTUnwrap(
        FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first)
      for file in try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      {
        try Data([0]).write(to: file)
      }
      let failed = try await api.edit(service, document, "history.undo")
      XCTAssertEqual(failed, 422)
      XCTAssertEqual(store.document, edited)
      XCTAssertEqual(service.revision(store), revision)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertTrue(store.session.redoStack.isEmpty)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertNil(store.error, "HTTP failures must not present native error alerts")
      let navigationResult2 = await store.undo()
      XCTAssertFalse(navigationResult2)
      XCTAssertNotNil(store.error)
      XCTAssertEqual(service.revision(store), revision)
      XCTAssertEqual(store.document, edited)
      store.error = nil
    }
  }
  @MainActor func testHTTPStorageFailureDoesNotDirtyDocumentOrAdvanceRevision() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      let original = store.document
      store.session = EditorSession(
        document: original, historyByteLimit: 0, historyDiskByteLimit: 0)
      try service.share(document)
      let revision = service.revision(store)
      let status = try await api.edit(
        service, document, "layer.rename",
        ["layerID": original.layers[0].id.uuidString, "name": "Rejected"])
      XCTAssertEqual(status, 422)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(service.revision(store), revision)
      XCTAssertFalse(document.isDocumentEdited)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.error)
    }
  }

  @MainActor func testDesktopAndHTTPExposeCurrentRasterReuseAndClearItOnEditing() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      var source = try CraftDocument(width: 64, height: 64)
      var pixels = try Surface(width: 64, height: 64)
      pixels.setPixel(x: 0, y: 0, .white)
      source.layers[0].content = .raster(pixels)
      let store = document.store
      store.session = EditorSession(document: source, historyByteLimit: 0)
      try service.share(document)
      let id = source.layers[0].id.uuidString
      for name in ["First", "Second"] {
        let status = try await api.edit(
          service, document, "layer.rename", ["layerID": id, "name": name])
        XCTAssertEqual(status, 200)
      }
      let undone = try await api.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200)
      XCTAssertEqual(store.session.historyReusableCurrentRasterBytes, 65_536)
      let share = try XCTUnwrap(service.shares.first)
      let state = service.state(share, document: document)
      let storage = try XCTUnwrap(state["historyStorage"] as? [String: Int])
      XCTAssertEqual(storage["reusableCurrentRasterBytes"], 65_536)
      XCTAssertEqual(storage["residentPayloadBytes"], 0)
      let navigationResult3 = await store.redo()
      XCTAssertTrue(navigationResult3)
      XCTAssertEqual(store.document.layers[0].name, "Second")
      XCTAssertEqual(store.session.historyReusableCurrentRasterBytes, 65_536)
      let changed = try await api.edit(
        service, document, "layer.rename", ["layerID": id, "name": "Edited"])
      XCTAssertEqual(changed, 200)
      XCTAssertEqual(store.session.historyReusableCurrentRasterBytes, 0)
      let capabilities = try await api.request(service, path: "/v1/capabilities")
      let discovery = try XCTUnwrap(
        JSONSerialization.jsonObject(with: capabilities.1) as? [String: Any])
      let history = try XCTUnwrap(discovery["historyStorage"] as? [String: Any])
      XCTAssertEqual(history["currentRasterReuse"] as? Bool, true)
    }
  }
}
