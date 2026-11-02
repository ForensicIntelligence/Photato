import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private actor SmartObjectTransport: AdobeResourceTransport {
  var files: [URL: Data] = [:]
  func set(_ data: Data, at url: URL) { files[url] = data }
  func fetch(_ url: URL) async throws -> Data {
    guard let data = files[url] else { throw AdobeAPIError.invalid("Missing test resource.") }; return data
  }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("No uploads.") }
}
final class SmartObjectWorkflowTests: XCTestCase {
  @MainActor func testDesktopConversionChildSaveHistoryAndStaleParent() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let parent = CraftNSDocument(model: try CraftDocument(width: 6, height: 4))
    controller.addDocument(parent)
    defer { parent.store.renderTask?.cancel(); controller.removeDocument(parent) }
    let before = parent.store.document
    parent.store.convertSmartObject(); await parent.store.geometryTask?.value
    XCTAssertNil(parent.store.error)
    let layer = try XCTUnwrap(parent.store.activeLayer), source = try XCTUnwrap(layer.smartObject)
    XCTAssertTrue(parent.store.canEditSmartObject); XCTAssertFalse(parent.store.canBeginLevels)
    XCTAssertTrue(parent.store.canPerformLayerPanel(.rasterize))
    let child = CraftNSDocument(model: try SmartObjectIO.sourceDocument(source))
    controller.addDocument(child)
    defer { child.store.renderTask?.cancel(); controller.removeDocument(child) }
    child.smartObjectEditLink = .init(parent: parent, layerID: layer.id, source: source)
    child.store.perform(.fill(child.store.document.layers[0].id, Pixel(1,0,0)))
    try await child.commitSmartObjectContents()
    XCTAssertFalse(child.isDocumentEdited); XCTAssertTrue(parent.isDocumentEdited)
    XCTAssertEqual(try Renderer.composite(parent.store.document).pixel(x: 2,y: 2), Pixel(1,0,0))
    await parent.store.undo()
    do { try await child.commitSmartObjectContents(); XCTFail("Stale source must reject") } catch {}
    await parent.store.undo(); XCTAssertEqual(parent.store.document, before)
    await parent.store.redo(); XCTAssertNotNil(parent.store.activeLayer?.smartObject)
  }
  @MainActor func testPhotatoConvertCopyResetRasterizeSourceAndNative14() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared); service.setDocumentTransfersEnabled(true)
      let original = shared.store.document
      let converted = try await helper.edit(service, shared, "smartObject.convert", ["layerIDs": [original.layers[0].id.uuidString]])
      XCTAssertEqual(converted, 200)
      let layer = try XCTUnwrap(shared.store.activeLayer), share = try XCTUnwrap(service.shares.first?.id)
      let bytes = try await helper.request(service, path: "/v1/documents/\(share)/smart-objects/\(layer.id)/source")
      XCTAssertEqual(bytes.0.statusCode, 200); XCTAssertEqual(bytes.1, layer.smartObject?.data)
      let old = try await helper.request(service, path: "/v1/documents/\(share)/file.photato", headers: ["X-Photato-Archive-Version": "13"])
      XCTAssertEqual(old.0.statusCode, 422)
      let native = try await helper.request(service, path: "/v1/documents/\(share)/file.photato", headers: ["X-Photato-Archive-Version": "14"])
      XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), shared.store.document)
      let params: [String: Any] = ["layerID": layer.id.uuidString]
      let stale = try await helper.edit(service, shared, "smartObject.copy", params, revision: "stale"); XCTAssertEqual(stale, 409)
      shared.store.geometryBusy = true
      let busy = try await helper.edit(service, shared, "smartObject.copy", params); XCTAssertEqual(busy, 409)
      shared.store.geometryBusy = false
      let copy = try await helper.edit(service, shared, "smartObject.copy", params); XCTAssertEqual(copy, 200)
      XCTAssertNotEqual(shared.store.activeLayer?.smartObject?.sourceID, layer.smartObject?.sourceID)
      let transform: [String: Any] = ["layerID": layer.id.uuidString, "a": 0.5, "b": 0, "c": 0, "d": 0.5, "tx": 1, "ty": 2]
      let moved = try await helper.edit(service, shared, "layer.transform", transform); XCTAssertEqual(moved, 200)
      XCTAssertEqual(shared.store.document.layers.first { $0.id == layer.id }?.content, layer.content)
      XCTAssertEqual(shared.store.document.layers.first { $0.id == layer.id }?.coordinateTransform.a, 0.5)
      let reset = try await helper.edit(service, shared, "smartObject.resetTransform", params); XCTAssertEqual(reset, 200)
      let raster = try await helper.edit(service, shared, "layer.rasterize", params); XCTAssertEqual(raster, 200)
      XCTAssertNil(shared.store.document.layers.first { $0.id == layer.id }?.smartObject)
      let bad = try await helper.edit(service, shared, "layer.rasterize", ["layerID": UUID().uuidString]); XCTAssertEqual(bad, 404)
      let undo = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertNotNil(shared.store.document.layers.first { $0.id == layer.id }?.smartObject)
    }
  }
  @MainActor func testPhotatoPlaceReplaceSnapshotValidationAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let source = CraftNSDocument(model: try CraftDocument(width: 2, height: 2))
      service.controller.addDocument(source)
      defer { source.store.renderTask?.cancel(); service.controller.removeDocument(source) }
      try service.share(shared); try service.share(source)
      let sourceID = try XCTUnwrap(service.shares.first { $0.document === source }?.id)
      var params: [String: Any] = ["sourceDocumentID": sourceID.uuidString, "sourceRevision": service.revision(source.store)]
      let before = shared.store.document
      let placed = try await helper.edit(service, shared, "smartObject.place", params); XCTAssertEqual(placed, 200)
      let layer = try XCTUnwrap(shared.store.activeLayer)
      XCTAssertEqual(layer.smartObject?.width, 2)
      source.store.perform(.fill(source.store.document.layers[0].id, Pixel(0,1,0)))
      params["layerID"] = layer.id.uuidString
      let stale = try await helper.edit(service, shared, "smartObject.replace", params); XCTAssertEqual(stale, 409)
      params["sourceRevision"] = service.revision(source.store)
      let replaced = try await helper.edit(service, shared, "smartObject.replace", params); XCTAssertEqual(replaced, 200)
      XCTAssertEqual(try Renderer.layerSurface(XCTUnwrap(shared.store.activeLayer), in: shared.store.document).pixel(x: 0,y: 0), Pixel(0,1,0))
      for _ in 0..<2 { let status = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(status, 200) }
      XCTAssertEqual(shared.store.document, before)
    }
  }
  @MainActor func testPreparedSmartObjectCancellationAndCommitValidationAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let original = shared.store.document, id = try XCTUnwrap(service.shares.first?.id)
      let expected = service.revision(shared.store)
      let pending = Task {
        try await service.executePreparedOperation(document: shared, shareID: id, revision: expected) { original in
          try await Task.sleep(for: .seconds(5))
          return try SmartObjectIO.convert(in: original, selected: [original.layers[0].id])
        }
      }
      for _ in 0..<100 where !shared.store.geometryBusy { try await Task.sleep(for: .milliseconds(5)) }
      shared.store.cancelActiveOperation()
      do { try await pending.value; XCTFail("Cancelled conversion committed") } catch {}
      XCTAssertEqual(shared.store.document, original)
      do {
        try await service.executePreparedOperation(document: shared, shareID: id, revision: expected,
          validateCommit: { throw AutomationFailure(status: 409, message: "Source sharing revoked") },
          prepare: { original in try SmartObjectIO.convert(in: original, selected: [original.layers[0].id]) })
        XCTFail("Revoked source committed")
      } catch {}
      XCTAssertEqual(shared.store.document, original); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  func addPayload(source: String = "https://example.test/source.png") -> [String: Any] {
    ["image": ["source": ["url": "https://example.test/input.psd"]],
      "edits": ["layers": [["name": "Embedded", "type": "smart_object_layer", "operation": ["type": "add", "placement": ["type": "top"]],
        "smartObject": ["smartObjectFile": ["source": ["url": source]]], "transformMode": "fit"]]],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
  }
  @MainActor func testPublishedCreateCompositeAddsAndReplacesEmbeddedResources() async throws {
    let transport = SmartObjectTransport(), helper = AutomationActionJobsTests()
    let original = try CraftDocument(width: 8, height: 8), source = try CraftDocument(width: 2, height: 4)
    let sourceURL = URL(string: "https://example.test/source.png")!, inputURL = URL(string: "https://example.test/input.psd")!
    let sourceBytes = try RasterIO.encoded(source)
    await transport.set(try PSDCodec.writeRasterLayers(original), at: inputURL)
    await transport.set(sourceBytes, at: sourceURL)
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      let output = try await helper.output(service, submit: "/v2/create-composite", payload: addPayload())
      let added = try PSDCodec.read(output.2), object = try XCTUnwrap(added.layers.last?.smartObject)
      XCTAssertEqual(object.data, sourceBytes); XCTAssertEqual(added.layers.count, 2)
      XCTAssertEqual(added.layers.last?.affine?.a, 2)
      await transport.set(output.2, at: inputURL)
      var replacement = try CraftDocument(width: 3, height: 3)
      try Command.fill(replacement.layers[0].id, Pixel(1,0,0)).apply(to: &replacement)
      await transport.set(try RasterIO.encoded(replacement), at: sourceURL)
      var payload = addPayload()
      payload["edits"] = ["layers": [["name": "Embedded", "type": "smart_object_layer", "operation": ["type": "edit"],
        "smartObject": ["autoResize": true, "smartObjectFile": ["source": ["url": sourceURL.absoluteString]]]]]]
      let edited = try await helper.output(service, submit: "/v2/create-composite", payload: payload)
      let result = try PSDCodec.read(edited.2)
      XCTAssertEqual(result.layers.last?.smartObject?.width, 2); XCTAssertEqual(result.layers.last?.smartObject?.height, 4)
      XCTAssertEqual(result.layers.last?.coordinateTransform, added.layers.last?.coordinateTransform)
      XCTAssertEqual(shared.store.document, untouched)
    }
  }
  func testPublishedContractRejectsUnsupportedLinkedAndTransforms() throws {
    let base: [String: Any] = ["name": "Object", "type": "smart_object_layer", "operation": ["type": "edit"], "smartObject": [:]]
    for extra: [String: Any] in [["smartObject": ["isLinked": "invalid"]], ["transform": ["angle": 30]], ["transformMode": "custom"], ["smartObject": ["autoResize": 1]], ["pixelMask": [:]]] {
      var fields = base; fields.merge(extra) { _, new in new }
      XCTAssertThrowsError(try AdobeSmartObjectEdit(fields, path: "edit"))
    }
    XCTAssertNoThrow(try AdobeSmartObjectEdit(base, path: "edit"))
  }
  @MainActor func testFactorySmartObjectMenuBindings() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      func find(_ menu: NSMenu, _ path: String) -> NSMenuItem? {
        for item in menu.items { if item.identifier?.rawValue == path { return item }; if let sub = item.submenu, let found = find(sub, path) { return found } }; return nil
      }
      for path in ["File > Place Embedded…", "Layer > Smart Objects > Convert to Smart Object", "Layer > Smart Objects > New Smart Object via Copy", "Layer > Smart Objects > Edit Contents", "Layer > Smart Objects > Replace Contents…", "Layer > Smart Objects > Export Contents…", "Layer > Smart Objects > Reset Transform", "Layer > Rasterize > Smart Object"] {
        XCTAssertNotNil(try XCTUnwrap(find(menu, path)).action, path)
      }
    }
  }
}
