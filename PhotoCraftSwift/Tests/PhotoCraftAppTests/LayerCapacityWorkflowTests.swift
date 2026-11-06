import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LayerCapacityWorkflowTests: XCTestCase {
  func fixture(_ count: Int = 8000, large: Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width: large ? 300000 : 2, height: large ? 300000 : 1)
    let pixels = try Surface(width: 2, height: 1, fill: Pixel(1, 0, 0))
    d.layers = (0..<count).map { Layer(name: "Layer \($0)", content: .raster(pixels)) }
    d.activeLayerID = d.layers.last?.id
    return d
  }
  @MainActor func testNativePanelLists8000RowsSearchAndCollapsedGroup() throws {
    let d = try fixture(7999); var grouped = d
    try Command.newGroup(.init(name: "Stack"), children: d.layers.map(\.id)).apply(to: &grouped)
    let s = EditorStore(document: grouped); defer { s.renderTask?.cancel() }
    XCTAssertEqual(s.layersInPanel().count, 8000)
    XCTAssertEqual(s.layersInPanel(search: "Layer 7998").map(\.id), [d.layers[7998].id])
    let group = try XCTUnwrap(grouped.layers.last?.id)
    s.toggleGroupDisclosure(group)
    XCTAssertEqual(s.layersInPanel().map(\.id), [group])
    XCTAssertEqual(s.layersInPanel(search: "Layer 7998").map(\.id), [d.layers[7998].id])
    XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertFalse(s.canCreatePixelLayer())
  }
  @MainActor func testHTTP8000LayersStateProtectionHistoryAndNativeDownload() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try self.fixture(); doc.store.session = EditorSession(document: source)
      try service.share(doc); service.setDocumentTransfersEnabled(true)
      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await h.request(service, path: "/v1/documents/\(id)")
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual((state["layers"] as? [[String: Any]])?.count, 8000)
      let params: [String: Any] = ["layerIDs": source.layers.map { $0.id.uuidString }, "protection": ["position"]]
      let status = try await h.edit(service, doc, "layer.protection", params)
      XCTAssertEqual(status, 200); XCTAssertTrue(doc.store.document.layers.allSatisfy { $0.protection.locksPosition })
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      let undo = try await h.edit(service, doc, "history.undo")
      XCTAssertEqual(undo, 200); XCTAssertEqual(doc.store.document, source)
      let file = try await h.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "84"])
      XCTAssertEqual(file.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(file.1), source)
      let overflow = try await h.edit(service, doc, "layer.new", ["name": "Too many"])
      XCTAssertEqual(overflow, 413); XCTAssertEqual(doc.store.document, source)
    }
  }
  @MainActor func testLargeSparseCanvasCanAdd8000thLayerWithoutLogicalAllocationReservation() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try self.fixture(7999, large: true); doc.store.session = EditorSession(document: source)
      try service.share(doc)
      let status = try await h.edit(service, doc, "layer.new", ["name": "Empty maximum canvas"])
      XCTAssertEqual(status, 200); XCTAssertEqual(doc.store.document.layers.count, 8000)
      guard case .raster(let pixels) = doc.store.document.layers.last?.content else { return XCTFail("Pixel layer") }
      XCTAssertEqual(pixels.width, 300000); XCTAssertEqual(pixels.height, 300000); XCTAssertEqual(pixels.tileCount, 0)
      let undo = try await h.edit(service, doc, "history.undo")
      XCTAssertEqual(undo, 200); XCTAssertEqual(doc.store.document, source)
    }
  }
  @MainActor func testCapacityRequestsKeepBusyStaleRevocationAndDuplicateValidation() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try self.fixture(7999); doc.store.session = EditorSession(document: source); try service.share(doc)
      let stale = try await h.edit(service, doc, "layer.new", ["name": "Stale"], revision: "old")
      XCTAssertEqual(stale, 409)
      doc.store.geometryBusy = true
      let busy = try await h.edit(service, doc, "layer.new", ["name": "Busy"])
      XCTAssertEqual(busy, 409); doc.store.geometryBusy = false
      let duplicate = try await h.edit(service, doc, "layer.protection", ["layerIDs": [source.layers[0].id.uuidString, source.layers[0].id.uuidString], "protection": ["position"]])
      XCTAssertEqual(duplicate, 400)
      let id = try XCTUnwrap(service.shares.first?.id); service.revoke(id)
      let revoked = try await h.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "layer.new", "revision": service.revision(doc.store), "parameters": ["name": "Revoked"]])
      XCTAssertEqual(revoked.0.statusCode, 404); XCTAssertEqual(doc.store.document, source); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testDiscoverySchemasAndLargeUUIDBodyAgree() throws {
    let limits = try XCTUnwrap(AutomationService.capabilities["limits"] as? [String: Any])
    XCTAssertEqual(limits["maxLayers"] as? Int, 8000)
    XCTAssertEqual(LayerCollectionTransformAPI.schema("layerIDs")["maxItems"] as? Int, 8000)
    XCTAssertEqual(ClipboardAPI.schema("layerIDs")["maxItems"] as? Int, 8000)
    let d = try fixture(), id = UUID()
    let body = try JSONSerialization.data(withJSONObject: ["command": "layer.protection", "revision": "r", "parameters": ["layerIDs": d.layers.map { $0.id.uuidString }, "protection": ["position"], "includeDescendants": true]])
    XCTAssertGreaterThan(body.count, 65536)
    let head = "POST /v1/documents/\(id)/commands HTTP/1.1\r\nContent-Length: \(body.count)\r\n\r\n"
    let parsed = try XCTUnwrap(AutomationRequest.parse(Data(head.utf8) + body))
    let command = try AutomationCommand(data: parsed.body)
    var changed = d; try command.protectionCommand(document: d).apply(to: &changed)
    XCTAssertTrue(changed.layers.allSatisfy { $0.protection.locksPosition })
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount); XCTAssertEqual(ActionLibraryFile.maximumVersion, 50)
  }
  func testAdobeResourceAdmissionUsesSame8000TargetAndRetainsHeapBudget() throws {
    let d = try fixture(); XCTAssertNoThrow(try AdobeActionAssets.check(d))
    var invalid = d; invalid.layers.append(Layer(name: "Overflow", content: d.layers[0].content))
    XCTAssertThrowsError(try AdobeActionAssets.check(invalid))
    XCTAssertEqual(AdobeActionAssets.maximumDocumentBytes, 128 * 1024 * 1024)
  }
  @MainActor func testStylesAndSmartConversionAcceptMoreThanFormer64LayerSelection() throws {
    let d = try fixture(65), ids = d.layers.map { $0.id.uuidString }
    let style = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "layer.style.patch", "revision": "r", "parameters": ["layerIDs": ids, "patch": ["fillOpacity": 0.5]]]))
    var changed = d; try style.advancedStyleCommand(document: d).apply(to: &changed)
    XCTAssertTrue(changed.layers.allSatisfy { $0.style?.fillOpacity == 0.5 })
    let convert = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "smartObject.convert", "revision": "r", "parameters": ["layerIDs": ids]]))
    let command = try convert.smartObjectCommand(document: d); var smart = d; try command.apply(to: &smart)
    XCTAssertEqual(smart.layers.count, 1); XCTAssertNotNil(smart.layers[0].smartObject)
  }
  func testAdobeOutputSelectionKeepsPublished100ReferenceBudget() throws {
    let fields: [String: Any] = ["layers": (1...100).map { ["id": $0] }]
    XCTAssertNoThrow(try AdobeLayerOutput(fields, createComposite: true, mediaType: .png))
    XCTAssertThrowsError(try AdobeLayerOutput(["layers": (1...101).map { ["id": $0] }], createComposite: true, mediaType: .png))
    XCTAssertThrowsError(try AdobeLayerOutput(fields, createComposite: true, mediaType: .psd))
  }

}
