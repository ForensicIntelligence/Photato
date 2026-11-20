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

final class AdobeSmartObjectTransformWorkflowTests: XCTestCase {
  private let input = URL(string: "https://example.test/template.psd")!
  private let asset = URL(string: "https://example.test/logo.png?signature=fixture")!

  private func edit(_ name: String, transform: [String: Any]) -> [String: Any] {
    ["name": name, "type": "smart_object_layer", "operation": ["type": "edit"],
     "transformMode": "custom", "transform": transform]
  }

  private func add(_ name: String, placement: [String: Any] = ["type": "top"],
                   linked: Bool = false, transform: [String: Any] = [:]) -> [String: Any] {
    var fields = edit(name, transform: transform)
    fields["operation"] = ["type": "add", "placement": placement]
    fields["smartObject"] = ["isLinked": linked, "smartObjectFile": ["source": ["url": asset.absoluteString]]]
    return fields
  }

  private func payload(_ layers: [[String: Any]]) -> [String: Any] {
    ["image": ["source": ["url": input.absoluteString]], "edits": ["layers": layers],
     "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
  }

  @MainActor func testHTTPRotatedEmbeddedTemplateMatchesEveryExpectedPixel() async throws {
    var pixels = try Surface(width: 4, height: 2, fill: Pixel(1, 0, 0))
    for x in 0..<4 { pixels.setPixel(x: x, y: 1, Pixel(0, 0, 1)) }
    let source = try RasterIO.encoded(pixels)
    let parent = try CraftDocument(width: 10, height: 8)
    let transport = SmartObjectTransport()
    await transport.set(source, at: asset)
    await transport.set(try PSDCodec.writeRasterLayers(parent), at: input)
    let geometry: [String: Any] = ["offset": ["horizontal": 7, "vertical": 2], "angle": 90,
                                  "anchor": ["horizontal": 0, "vertical": 0]]
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      let result = try await AutomationActionJobsTests().output(service, submit: "/v2/create-composite",
        payload: payload([add("Logo", transform: geometry)]))
      let document = try PSDCodec.read(result.2)
      let logo = try XCTUnwrap(document.layers.last)
      XCTAssertEqual(logo.coordinateTransform, Transform2D(a: 0, b: 1, c: -1, d: 0, tx: 7, ty: 2))
      XCTAssertEqual(logo.smartObject?.data, source)

      var expected = Data()
      for y in 0..<8 {
        for x in 0..<10 {
          switch (x, y) {
          case (5, 2..<6): expected.append(contentsOf: [0, 0, 255, 255])
          case (6, 2..<6): expected.append(contentsOf: [255, 0, 0, 255])
          default: expected.append(contentsOf: [255, 255, 255, 255])
          }
        }
      }
      XCTAssertEqual(try Renderer.composite(document).rgbaData(depth: .u8), expected)
      XCTAssertEqual(shared.store.document, untouched)
    }
  }

  @MainActor func testHTTPLinkedTransformOnlyEditRetainsSourceAtItsNewPosition() async throws {
    var template = try CraftDocument(width: 20, height: 16)
    template.resolution = 144
    let transport = SmartObjectTransport()
    await transport.set(try PSDCodec.writeRasterLayers(template), at: input)
    await transport.set(try RasterIO.encoded(Surface(width: 4, height: 2, fill: Pixel(0, 1, 0))), at: asset)
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      let helper = AutomationActionJobsTests()
      let geometry: [String: Any] = ["dimension": ["width": 4, "height": 2, "unit": "points_unit"],
                                    "horizontalAlign": "right", "verticalAlign": "center"]
      let added = try await helper.output(service, submit: "/v2/create-composite",
        payload: payload([add("Linked Logo", linked: true, transform: geometry)]))
      let addedLayer = try XCTUnwrap(PSDCodec.read(added.2).layers.last)
      XCTAssertEqual(try addedLayer.smartObjectSourceTransform(), Transform2D(a: 2, d: 2, tx: 12, ty: 6))
      let storedSource = try XCTUnwrap(addedLayer.smartObject)
      XCTAssertEqual(storedSource.linkedSource?.reference, "https://example.test/logo.png")
      XCTAssertTrue(storedSource.data.isEmpty)

      await transport.set(added.2, at: input)
      let edited = try await helper.output(service, submit: "/v2/create-composite",
        payload: payload([edit("Linked Logo", transform: ["angle": 90])]))
      let editedLogo = try XCTUnwrap(PSDCodec.read(edited.2).layers.last)
      XCTAssertEqual(try editedLogo.smartObjectSourceTransform(), Transform2D(a: 0, b: 2, c: -2, d: 0, tx: 18, ty: 4))
      XCTAssertEqual(editedLogo.smartObject, storedSource)

      await transport.set(edited.2, at: input)
      let fit: [String: Any] = ["name": "Linked Logo", "type": "smart_object_layer",
                               "operation": ["type": "edit"], "transformMode": "fit"]
      let fitted = try await helper.output(service, submit: "/v2/create-composite", payload: payload([fit]))
      let fittedLogo = try XCTUnwrap(PSDCodec.read(fitted.2).layers.last)
      XCTAssertEqual(try fittedLogo.smartObjectSourceTransform(), Transform2D(a: 5, d: 5, tx: 0, ty: 3))
      XCTAssertEqual(fittedLogo.smartObject, storedSource)
      XCTAssertEqual(shared.store.document, untouched)
    }
  }

  func testSkewRotationAndAnchorComposeInSourceSpace() throws {
    let source = try RasterIO.encoded(Surface(width: 4, height: 2, fill: .white))
    var session = EditorSession(document: try CraftDocument(width: 20, height: 16))
    let geometry: [String: Any] = ["offset": ["horizontal": 5, "vertical": 4],
                                  "anchor": ["horizontal": 0.25, "vertical": 0.5],
                                  "skew": ["horizontal": 45, "vertical": -45], "angle": -90]
    try AdobeSmartObjectEdit(add("Artwork", transform: geometry), path: "layer")
      .apply(to: &session, resources: [asset: source])
    let layer = try XCTUnwrap(session.document.layers.last)
    let value = layer.coordinateTransform
    XCTAssertEqual(value.a, -1, accuracy: 1e-10)
    XCTAssertEqual(value.b, -1, accuracy: 1e-10)
    XCTAssertEqual(value.c, 1, accuracy: 1e-10)
    XCTAssertEqual(value.d, -1, accuracy: 1e-10)
    XCTAssertEqual(value.tx, 6, accuracy: 1e-10)
    XCTAssertEqual(value.ty, 7, accuracy: 1e-10)
    XCTAssertEqual(layer.smartObject?.data, source)

    let changed = try AdobeCompositeEdit(edit("Artwork", transform: ["offset": ["horizontal": 10]]), path: "layer")
    try changed.apply(to: &session, resources: [:])
    let moved = try XCTUnwrap(session.document.layers.last).coordinateTransform
    XCTAssertEqual(moved.tx, 10, accuracy: 1e-10)
    XCTAssertEqual(moved.ty, value.ty, accuracy: 1e-10)
    XCTAssertEqual(moved.c, value.c, accuracy: 1e-10)
    XCTAssertEqual(moved.b, value.b, accuracy: 1e-10)
  }

  func testTemplateInsertionsResolveNamedGroupsAndPSDLayerIDsInRequestOrder() throws {
    var source = try AdobeLayerMoveTests().fixture()
    let group = Layer(name: "Artwork Group", content: .group(.init()))
    source.layers[2].parentID = group.id
    source.layers.insert(group, at: 3)
    let bytes = try RasterIO.encoded(Surface(width: 4, height: 2, fill: .white))
    let edits = [
      add("Under All", placement: ["type": "bottom"]),
      add("Logo", placement: ["type": "into", "referenceLayer": ["name": group.name]]),
      add("Over Logo", placement: ["type": "above", "referenceLayer": ["name": "Logo"]]),
      add("Under A", placement: ["type": "below", "referenceLayer": ["id": 1]]),
      add("On Top"),
    ]
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: payload(edits)),
                                          createComposite: true)
    let result = try request.applying(to: source, resources: [asset: bytes]).session.document
    XCTAssertEqual(result.children(of: nil).map(\.name), ["Under All", "Under A", "A", "B", group.name, "D", "E", "On Top"])
    XCTAssertEqual(result.children(of: group.id).map(\.name), ["C", "Logo", "Over Logo"])
    XCTAssertEqual(result.layers.filter { $0.smartObject?.data == bytes }.count, 5)
  }

  @MainActor func testHTTPRejectsMalformedCustomTransformBeforePublishingOutput() async throws {
    let invalid: [[String: Any]] = [
      ["angle": true],
      ["dimension": ["width": 0]],
      ["dimension": ["width": 3, "unit": "inches"]],
      ["anchor": ["horizontal": 0.5]],
      ["skew": ["horizontal": 45, "vertical": 45]],
      ["skew": ["horizontal": 90, "vertical": 0]],
      ["horizontalAlign": "bottom"],
      ["offset": ["horizontal": 1.5]],
    ]
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: SmartObjectTransport()) { service, shared in
      let before = shared.store.document
      service.setResourceJobsEnabled(true)
      for transform in invalid {
        let result = try await AutomationTests().request(service, path: "/v2/create-composite",
          body: payload([add("Logo"), edit("Logo", transform: transform)]))
        XCTAssertEqual(result.0.statusCode, 400, String(decoding: result.1, as: UTF8.self))
      }
      XCTAssertEqual(shared.store.document, before)
    }
  }
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
