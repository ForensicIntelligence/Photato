import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private actor FilterTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("No uploads.") }
}

final class SmartFilterWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try FilterWorkflowTests().fixture()
    try SmartObjectIO.convert(in: d, selected: [d.layers[0].id]).apply(to: &d)
    return d
  }
  @MainActor func testDraftCancelEditBlendMaskAndUndo() async throws {
    let d = try fixture(), id = d.layers[0].id, store = EditorStore(document: d)
    defer { store.renderTask?.cancel() }
    XCTAssertTrue(store.canBeginFilter); XCTAssertFalse(store.canBeginLevels)
    store.beginFilter(.mosaic); await store.renderTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document, d)
    store.cancelFilter(); XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginFilter(.mosaic); store.commitFilter(); await store.geometryTask?.value
    XCTAssertNil(store.error)
    let first = store.document, filterID = try XCTUnwrap(first.layers[0].smartFilters?.filters.first?.id)
    store.beginSmartFilter(id, filterID: filterID)
    store.filterDraft?.filter.cellSize = 3; store.filterDraft?.opacity = 0.5; store.filterDraft?.blendMode = .screen
    await store.renderTask?.value; XCTAssertEqual(store.document, first)
    store.commitFilter(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document.layers[0].smartFilters?.filters.count, 1)
    XCTAssertEqual(store.document.layers[0].smartFilters?.filters[0].opacity, 0.5)
    let edited = store.document
    store.selectSmartFilterMask(id); XCTAssertTrue(store.editingMask)
    var brush = Brush(); brush.size = 4; brush.color = .black
    store.stroke([.init(x: 4, y: 4)], brush: brush)
    XCTAssertNil(store.error); XCTAssertNil(store.document.layers[0].mask)
    XCTAssertNotEqual(store.document.layers[0].smartFilters?.mask, edited.layers[0].smartFilters?.mask)
    await store.undo(); XCTAssertEqual(store.document, edited)
    await store.undo(); XCTAssertEqual(store.document, first)
    await store.undo(); XCTAssertEqual(store.document, d)
    store.select(id); XCTAssertFalse(store.smartFilterMaskEditing)
  }
  @MainActor func testHTTPStackMaskStateUndoAndInvalidBusyStale() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let d = try fixture(), id = d.layers[0].id
      shared.store.session = EditorSession(document: d); try service.share(shared)
      let apply = try await helper.edit(service, shared, "filter.apply", ["layerID": id.uuidString, "filter": ["kind": "mosaic"]])
      XCTAssertEqual(apply, 200)
      let first = shared.store.document
      service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first?.id)
      let old = try await helper.request(service, path: "/v1/documents/\(share)/file.photato", headers: ["X-Photato-Archive-Version": "14"])
      XCTAssertEqual(old.0.statusCode, 422)
      let native = try await helper.request(service, path: "/v1/documents/\(share)/file.photato", headers: ["X-Photato-Archive-Version": "15"])
      XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), first)
      var stack = try XCTUnwrap(first.layers[0].smartFilters)
      stack.filters[0].opacity = 0.25; stack.filters[0].blendMode = .multiply
      var payload = stack.apiState; payload.removeValue(forKey: "hasMask"); payload.removeValue(forKey: "maskTransform")
      let edited = try await helper.edit(service, shared, "smartFilter.set", ["layerID": id.uuidString, "stack": payload])
      XCTAssertEqual(edited, 200); XCTAssertEqual(shared.store.document.layers[0].smartFilters, stack)
      let before = shared.store.document
      let stroke: [String: Any] = ["layerID": id.uuidString, "size": 4, "hardness": 0.8, "opacity": 1,
        "value": 0, "points": [["x": 4, "y": 4]]]
      let painted = try await helper.edit(service, shared, "smartFilter.maskStroke", stroke)
      XCTAssertEqual(painted, 200)
      var expected = before; var brush = Brush(); brush.size = 4; brush.color = .black
      try Command.smartFilterMask(id, .maskStroke(id, [.init(x: 4, y: 4)], brush)).apply(to: &expected)
      XCTAssertEqual(shared.store.document, expected)
      let undo = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertEqual(shared.store.document, before)
      let stale = try await helper.edit(service, shared, "smartFilter.set", ["layerID": id.uuidString, "stack": payload], revision: "stale")
      XCTAssertEqual(stale, 409)
      shared.store.beginFilter(.boxBlur)
      let busy = try await helper.edit(service, shared, "smartFilter.maskFill", ["layerID": id.uuidString, "value": 0])
      XCTAssertEqual(busy, 409); shared.store.cancelFilter()
      let bad = try await helper.edit(service, shared, "smartFilter.set", ["layerID": id.uuidString, "stack": ["enabled": 1, "filters": []]])
      XCTAssertEqual(bad, 400); XCTAssertEqual(shared.store.document, before)
      let filled = try await helper.edit(service, shared, "smartFilter.maskFill", ["layerID": id.uuidString, "value": 0])
      XCTAssertEqual(filled, 200)
      XCTAssertEqual(try Renderer.composite(shared.store.document).rgbaData(depth: .u8), try Renderer.composite(d).rgbaData(depth: .u8))
    }
  }
  @MainActor func testPublishedExecuteActionsRetainsEditablePSDStack() async throws {
    var d = try fixture(); d.layers[0].name = "Artwork"
    let transport = FilterTransport(try PSDCodec.writeRasterLayers(d))
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let unchanged = shared.store.document; service.setResourceJobsEnabled(true)
      let action = #"[{"_obj":"select","_target":[{"_ref":"layer","_name":"Artwork"}]},{"_obj":"gaussianBlur","radius":{"_unit":"pixelsUnit","_value":12}}]"#
      let payload: [String: Any] = ["image": ["source": ["url": "https://example.test/smart.psd"]],
        "options": ["actions": [["source": ["content": action, "contentType": "application/json"]]]], "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
      let result = try await AutomationActionJobsTests().output(service, submit: "/v2/execute-actions", payload: payload)
      let reopened = try PSDCodec.read(result.2)
      XCTAssertEqual(reopened.layers[0].smartFilters?.filters.first?.filter.radius, 12)
      XCTAssertNotNil(reopened.layers[0].smartObject)
      XCTAssertEqual(shared.store.document, unchanged)
    }
  }
  @MainActor func testFactoryMenusAndNativeVersionSchema() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      func find(_ menu: NSMenu, _ path: String) -> NSMenuItem? {
        for item in menu.items { if item.identifier?.rawValue == path { return item }; if let sub = item.submenu, let found = find(sub, path) { return found } }; return nil
      }
      for path in ["Filter > Convert for Smart Filters", "Layer > Smart Filter > Disable Smart Filters", "Layer > Smart Filter > Delete Filter Mask", "Layer > Smart Filter > Disable Filter Mask", "Layer > Smart Filter > Clear Smart Filters"] {
        XCTAssertNotNil(try XCTUnwrap(find(menu, path)).action)
      }
    }
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: SmartFilterStack.apiCapabilities))
  }
}
