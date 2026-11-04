import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class EmptyLayerDeletionWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 8, depth: depth)
    let base = Layer(name: "Keep", content: .raster(try Surface(width: 8, height: 8, depth: depth, fill: .white)))
    let empty = Layer(name: "Empty", content: .raster(try Surface(width: 8, height: 8, depth: depth, fill: Pixel(1, 0.4, 0.8, 0))))
    var hidden = Layer(name: "Hidden", content: .raster(try Surface(width: 2, height: 2, depth: depth, fill: .black))); hidden.visible = false
    d.layers = [base, empty, hidden]; d.activeLayerID = base.id
    return d
  }
  @MainActor func testFactoryScriptMenuUsesNativeActionAndBusyValidation() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let document = CraftNSDocument(model: try fixture())
      app.controller.addDocument(document); document.makeWindowControllers()
      XCTAssertTrue(app.controller.documentWindows.activate(document)); defer { document.close() }
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.title == EmptyLayerDeletion.title })
      XCTAssertEqual(item.action, #selector(AppDelegate.deleteEmptyLayers)); XCTAssertEqual(item.keyEquivalent, "")
      XCTAssertTrue(app.validateMenuItem(item))
      document.store.geometryBusy = true; XCTAssertFalse(app.validateMenuItem(item))
      document.store.geometryBusy = false
    }
  }
  @MainActor func testDesktopPreservesSurvivingMultiselectionAndOneHistoryEntry() async throws {
    let original = try fixture(), store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    let selected = Set(original.layers.map(\.id)); store.selectedLayerIDs = selected
    store.deleteEmptyLayers(); await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document.layers, [original.layers[0],original.layers[2]])
    XCTAssertEqual(store.selectedLayerIDs, [original.layers[0].id,original.layers[2].id])
    XCTAssertEqual(store.document.activeLayerID, original.activeLayerID)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo(); XCTAssertEqual(store.document, original)
  }
  @MainActor func testEveryDepthRealHTTPMatchesDesktopAndUndo() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      for depth in PixelDepth.allCases {
        let original = try fixture(depth), native = EditorStore(document: original)
        defer { native.renderTask?.cancel() }
        let selected = Set(original.layers.map(\.id)); native.selectedLayerIDs = selected
        native.deleteEmptyLayers(); await native.geometryTask?.value; XCTAssertNil(native.error)
        shared.store.session = EditorSession(document: original); shared.store.selectedLayerIDs = selected
        let status = try await helper.edit(service, shared, EmptyLayerDeletionAPI.name)
        XCTAssertEqual(status, 200); XCTAssertEqual(shared.store.document, native.document)
        XCTAssertEqual(shared.store.selectedLayerIDs, native.selectedLayerIDs)
        XCTAssertEqual(shared.store.session.undoStack.count, 1)
        XCTAssertEqual(shared.store.session.undoStack.last?.label, EmptyLayerDeletion.title)
        let undoStatus = try await helper.edit(service, shared, "history.undo")
        XCTAssertEqual(undoStatus, 200); XCTAssertEqual(shared.store.document, original)
      }
    }
  }
  @MainActor func testInvalidBusyStaleRequestsAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared); let original = try fixture()
      shared.store.session = EditorSession(document: original)
      let invalid = try await helper.edit(service, shared, EmptyLayerDeletionAPI.name, ["deleteHidden":true])
      XCTAssertEqual(invalid, 400)
      let stale = try await helper.edit(service, shared, EmptyLayerDeletionAPI.name, revision: "stale")
      XCTAssertEqual(stale, 409)
      shared.store.geometryBusy = true
      let busy = try await helper.edit(service, shared, EmptyLayerDeletionAPI.name)
      XCTAssertEqual(busy, 409); shared.store.geometryBusy = false
      XCTAssertEqual(shared.store.document, original); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPNoOpPreservesDocumentHistoryAndDirtyState() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared); var d = try fixture(); d.layers.remove(at: 1)
      shared.store.session = EditorSession(document: d)
      let dirty = shared.isDocumentEdited
      let status = try await helper.edit(service, shared, EmptyLayerDeletionAPI.name)
      XCTAssertEqual(status, 200); XCTAssertEqual(shared.store.document, d)
      // Existing API revisions include redraw/view state, not only content.
      XCTAssertEqual(shared.isDocumentEdited, dirty); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testDiscoveryIncludesCommandSchemaCapabilitiesAndObservableAvailability() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == EmptyLayerDeletionAPI.name })
      XCTAssertTrue(definition.parameters.isEmpty)
      XCTAssertNotNil(EmptyLayerDeletionAPI.capabilities["adobe"])
      let share = try XCTUnwrap(service.shares.first)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String:Any])
      XCTAssertEqual((object["emptyLayerDeletion"] as? [String:Any])?["canRun"] as? Bool, shared.store.canDeleteEmptyLayers)
    }
  }
  @MainActor func testNativeClippingStackKeepsExactCompositeAndOneUndo() async throws {
    var d = try CraftDocument(width: 8, height: 8)
    let bottom = Layer(name: "White", content: .raster(try Surface(width: 8, height: 8, fill: .white)))
    let base = Layer(name: "Empty clipping base", content: .raster(try Surface(width: 8, height: 8)))
    var clipped = Layer(name: "Black clipped", content: .raster(try Surface(width: 8, height: 8, fill: .black))); clipped.clipped = true
    let empty = Layer(name: "Delete this", content: .raster(try Surface(width: 8, height: 8)))
    d.layers = [bottom, base, clipped, empty]; d.activeLayerID = clipped.id
    let pixels = try Renderer.composite(d).rgbaData(depth: .u8)
    var unsafe = d; try Command.deleteLayers([base.id, empty.id]).apply(to: &unsafe)
    XCTAssertNotEqual(try Renderer.composite(unsafe).rgbaData(depth: .u8), pixels,
      "The counterexample must reveal clipped artwork when its empty base is deleted.")
    let store = EditorStore(document: d); defer { store.renderTask?.cancel() }
    store.deleteEmptyLayers(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document.layers, [bottom, base, clipped])
    XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), pixels)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo(); XCTAssertEqual(store.document, d)
  }
}
