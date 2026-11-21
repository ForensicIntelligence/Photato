import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RemoveWiresWorkflowTests: XCTestCase {
  @MainActor func testClickAndAuthenticatedCommandProduceTheSameEditableResult() async throws {
    let fixture = try source()
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let store = doc.store
      store.session = EditorSession(document: fixture); store.tool = .remove
      store.removeSettings.createNewLayer = false
      try service.share(doc)
      XCTAssertTrue(store.canRemoveWires)
      store.removeWiresAndCables()
      XCTAssertNotNil(store.removeWiresID)
      await store.geometryTask?.value
      await store.removeCompletionTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1)
      let native = store.document
      XCTAssertNotEqual(native, fixture)
      await store.undo(); XCTAssertEqual(store.document, fixture)
      let stale = try await h.edit(service, doc, RemoveToolAPI.name, ["operation":"removeWires"], revision:"old")
      XCTAssertEqual(stale, 409)
      let irrelevant = try await h.edit(service, doc, RemoveToolAPI.name, ["operation":"removeWires","strokes":[]])
      XCTAssertEqual(irrelevant, 400)
      let share = try XCTUnwrap(service.shares.first?.id)
      let response = try await h.request(service, path: "/v1/documents/\(share)/commands", body: [
        "command": RemoveToolAPI.name, "revision": service.revision(store), "parameters": ["operation":"removeWires"]])
      XCTAssertEqual(response.0.statusCode, 200)
      let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String:Any])
      let result = try XCTUnwrap(payload["removeWiresResult"] as? [String:Any])
      XCTAssertEqual(result["candidateTracks"] as? Int, 1)
      XCTAssertEqual(result["applied"] as? Bool, true)
      XCTAssertEqual((payload["removeTool"] as? [String:Any])?["removingWires"] as? Bool, false)
      XCTAssertEqual(store.document, native); XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertEqual(store.document, fixture)
    }
  }

  @MainActor func testToolSwitchCancelsPendingNativeRemovalAndKeepsTheDocument() async throws {
    let doc = try source()
    let store = EditorStore(document: doc); store.tool = .remove
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    store.removeWiresPreparation = { _, _, _ in
      while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
      throw CancellationError()
    }
    store.removeWiresAndCables()
    let job = try XCTUnwrap(store.geometryTask)
    XCTAssertNotNil(store.removeWiresID); XCTAssertFalse(store.canRemoveWires)
    store.tool = .move
    await job.value
    XCTAssertNil(store.removeWiresID); XCTAssertFalse(store.geometryBusy)
    XCTAssertEqual(store.document, doc); XCTAssertTrue(store.session.undoStack.isEmpty)
  }

  private func source() throws -> CraftDocument {
    var doc = try CraftDocument(width: 144, height: 96)
    var pixels = try Surface(width: doc.width, height: doc.height, fill: Pixel(0.53, 0.7, 0.93))
    for x in 0..<doc.width { pixels.setPixel(x: x, y: 32, Pixel(0.12, 0.14, 0.13)) }
    doc.layers[0].content = .raster(pixels); doc.layers[0].locked = false
    return doc
  }
}
