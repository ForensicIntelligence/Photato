import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor SmartCompPreparationGate {
  var entered = false
  func mark() { entered = true }
}
final class SmartObjectLayerCompWorkflowTests: XCTestCase {
  func fixture() throws -> (parent: CraftDocument, source: CraftDocument) {
    var source = try CraftDocument(width: 4, height: 3)
    source.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: Pixel(1, 0, 0)))
    var top = Layer(name: "Blue", content: .raster(try Surface(width: 4, height: 3, fill: Pixel(0, 0, 1)))); top.visible = false; source.layers.append(top)
    try Command.layerComp(.capture(id: UUID(), name: "Red", comment: "", options: .init())).apply(to: &source)
    source.layers[1].visible = true
    try Command.layerComp(.capture(id: UUID(), name: "Blue", comment: "", options: .init())).apply(to: &source)
    var parent = try CraftDocument(width: 8, height: 6)
    let layer = try SmartObjectIO.placed(data: NativeArchive.encode(source), fileName: "Owned.photato", in: parent, fit: false)
    parent.layers = [layer]; parent.activeLayerID = layer.id; return (parent, source)
  }
  @MainActor func testNativePropertiesSelectionAndHTTPUseIdenticalDocumentsAndHistory() async throws {
    let fixture = try fixture(), helper = AutomationTests(), red = fixture.source.layerComps!.comps[0].id, layer = fixture.parent.layers[0].id
    let native = EditorStore(document: fixture.parent); defer { native.renderTask?.cancel() }
    XCTAssertTrue(native.canChooseSmartObjectComp); native.chooseSmartObjectComp(red)
    await native.geometryTask?.value; XCTAssertNil(native.error); XCTAssertEqual(native.document.layers[0].smartObject?.layerComps?.selectedID, red)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: fixture.parent); try service.share(document); let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "smartObject.layerComp", "revision": service.revision(document.store), "parameters": ["layerID": layer.uuidString, "compID": red.uuidString]])
      XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1, as: UTF8.self)); XCTAssertEqual(document.store.document, native.document)
      let state = document.store.document.layers[0].smartObject!.apiState
      let choices = try XCTUnwrap(state["layerComps"] as? [String: Any]); XCTAssertEqual(choices["selectedID"] as? String, red.uuidString)
      XCTAssertEqual((choices["entries"] as? [[String: Any]])?.count, 2)
      let changed = document.store.document
      let undo = try await helper.edit(service, document, "history.undo", [:]); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, fixture.parent)
      let redo = try await helper.edit(service, document, "history.redo", [:]); XCTAssertEqual(redo, 200); XCTAssertEqual(document.store.document, changed)
      let reset = try await helper.edit(service, document, "smartObject.layerComp", ["layerID": layer.uuidString, "compID": NSNull()]); XCTAssertEqual(reset, 200)
      XCTAssertNil(document.store.document.layers[0].smartObject?.layerComps?.selectedID)
      XCTAssertEqual(document.store.document.layers[0].smartObject?.data, fixture.parent.layers[0].smartObject?.data)
    }
  }
  @MainActor func testSchemaInvalidBusyStaleAndNative80Negotiation() async throws {
    let fixture = try fixture(), helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: fixture.parent); try service.share(document); let id = try XCTUnwrap(service.shares.first?.id), layer = fixture.parent.layers[0].id
      for (status, parameters): (Int, [String: Any]) in [
        (400, ["layerID": layer.uuidString]), (400, ["layerID": layer.uuidString, "compID": 123]),
        (400, ["layerID": layer.uuidString, "compID": "bad"]), (404, ["layerID": UUID().uuidString, "compID": NSNull()]),
        (422, ["layerID": layer.uuidString, "compID": UUID().uuidString])
      ] {
        let result = try await helper.edit(service, document, "smartObject.layerComp", parameters); XCTAssertEqual(result, status); XCTAssertEqual(document.store.document, fixture.parent)
      }
      let params: [String: Any] = ["layerID": layer.uuidString, "compID": NSNull()]
      let stale = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "smartObject.layerComp", "revision": "stale", "parameters": params]); XCTAssertEqual(stale.0.statusCode, 409)
      document.store.geometryBusy = true; let busy = try await helper.edit(service, document, "smartObject.layerComp", params); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      service.setDocumentTransfersEnabled(true)
      let old = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "79"]); XCTAssertEqual(old.0.statusCode, 422)
      let native = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "80"]); XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), fixture.parent)
      let properties = AutomationCommand.definitions.first { $0.name == "smartObject.layerComp" }!.schema["properties"] as! [String: Any]
      let parameters = try XCTUnwrap(properties["parameters"] as? [String: Any])
      let fields = try XCTUnwrap(parameters["properties"] as? [String: Any])
      let comp = try XCTUnwrap(fields["compID"] as? [String: Any])
      XCTAssertEqual(comp["type"] as? [String], ["string", "null"]); XCTAssertEqual(comp["format"] as? String, "uuid")
      XCTAssertEqual(Set(AutomationCommand.definitions.map(\.name)).count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testReopenedLinkedChoiceRequiresExistingAPIFileAuthorizationAndUnchangedOriginal() async throws {
    let helper = AutomationTests(), fixture = try fixture(), bytes = try NativeArchive.encode(fixture.source)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("Owned.photato"); try bytes.write(to: url)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let registry = LinkedSourceRegistry(persistent: false), grant = try registry.authorize(url), file = try LinkedArtworkRead.read(grant)
      var linked = fixture.parent; linked.layers[0].smartObject?.data = bytes
      linked.layers[0] = try LinkedSmartObjectIO.linked(linked.layers[0], reference: file.reference)
      let reopened = try NativeArchive.decode(NativeArchive.encode(linked)); document.store.session = EditorSession(document: reopened); document.store.linkedSourceRegistry = registry
      try service.share(document)
      let parameters: [String: Any] = ["layerID": reopened.layers[0].id.uuidString, "compID": fixture.source.layerComps!.comps[0].id.uuidString]
      let denied = try await helper.edit(service, document, "smartObject.layerComp", parameters); XCTAssertEqual(denied, 403); XCTAssertEqual(document.store.document, reopened)
      _ = try service.authorizeLinkedArtwork(url, registry: registry)
      let allowed = try await helper.edit(service, document, "smartObject.layerComp", parameters); XCTAssertEqual(allowed, 200); XCTAssertEqual(document.store.document.layers[0].smartObject?.layerComps?.selectedID, fixture.source.layerComps!.comps[0].id)
      document.store.session = EditorSession(document: reopened); try Data([1, 2, 3]).write(to: url)
      let changed = try await helper.edit(service, document, "smartObject.layerComp", parameters); XCTAssertEqual(changed, 422); XCTAssertEqual(document.store.document, reopened)
    }
  }
  @MainActor func testCancellationAndShareRevocationRejectAConfirmedLivePreparedEdit() async throws {
    let helper = AutomationTests(), fixture = try fixture()
    for revoke in [false, true] {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: fixture.parent); try service.share(document); let id = try XCTUnwrap(service.shares.first?.id), gate = SmartCompPreparationGate()
        service.smartObjectCompPreparation = { original, layer, comp, data in
          await gate.mark(); try await Task.sleep(for: .seconds(30)); return try SmartObjectLayerCompIO.selection(in: original, layerID: layer, compID: comp, sourceData: data)
        }
        let operation = Task { try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "smartObject.layerComp", "revision": service.revision(document.store), "parameters": ["layerID": fixture.parent.layers[0].id.uuidString, "compID": fixture.source.layerComps!.comps[0].id.uuidString]]) }
        let deadline = Date().addingTimeInterval(3)
        while !(await gate.entered), Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let entered = await gate.entered; XCTAssertTrue(entered)
        if revoke { service.revoke(id) } else { document.store.geometryTask?.cancel() }
        let result = try await operation.value; XCTAssertEqual(result.0.statusCode, 409)
        XCTAssertEqual(document.store.document, fixture.parent); XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.store.geometryBusy)
      }
    }
  }
}
