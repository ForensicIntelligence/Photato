import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFLayerWorkflowTests: XCTestCase {
  func fixture(_ name: String = "8-little-marker.tiff") throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-layers/" + name))
  }
  func content(_ a: CraftDocument, _ b: CraftDocument) throws {
    XCTAssertEqual(a.layers.count, b.layers.count)
    XCTAssertEqual(a.depth, b.depth); XCTAssertEqual(a.width, b.width); XCTAssertEqual(a.height, b.height)
    for (left, right) in zip(a.layers, b.layers) {
      XCTAssertEqual(left.name, right.name); XCTAssertEqual(left.content, right.content)
      XCTAssertEqual(left.mask, right.mask); XCTAssertEqual(left.maskProperties, right.maskProperties)
      XCTAssertEqual(left.x, right.x); XCTAssertEqual(left.y, right.y)
      XCTAssertEqual(left.blendMode, right.blendMode); XCTAssertEqual(left.opacity, right.opacity)
      XCTAssertEqual(left.visible, right.visible); XCTAssertEqual(left.locked, right.locked)
      XCTAssertEqual(a.layers.firstIndex { $0.id == left.parentID }, b.layers.firstIndex { $0.id == right.parentID })
    }
  }
  @MainActor func testNativeOpenEditUndoAndEditableSavePreserveLayersAndOriginalTIFF() async throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let bytes = try fixture("32-little-marker.tiff"), source = folder.appendingPathComponent("layers.tiff")
    try bytes.write(to: source)
    let document = try XCTUnwrap(controller.makeDocument(withContentsOf: source,
      ofType: DocumentIO.Format.tiff.typeIdentifier) as? CraftNSDocument)
    controller.addDocument(document); defer { document.close() }
    let before = document.store.document
    XCTAssertEqual(before.layers.count, 3); XCTAssertEqual(document.persistenceFormat, .tiff)
    XCTAssertTrue(document.saveFormats.contains(.tiff))
    XCTAssertNil(DocumentIO.persistenceIssue(before, format: .tiff))
    try document.store.executeEditorCommand(.renameLayer(before.layers[0].id, "Edited Base"))
    XCTAssertTrue(document.isDocumentEdited)
    await document.store.undo(); XCTAssertEqual(document.store.document, before)
    await document.store.redo(); XCTAssertEqual(document.store.document.layers[0].name, "Edited Base")
    let edited = document.store.document
    do {
      try await document.persistDocument(to: source, format: .tiff, operation: .saveOperation, options: .init(tiffLayers: false))
      XCTFail("Layered TIFF ordinary Save must not flatten")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    XCTAssertEqual(document.store.document, edited)
    let native = folder.appendingPathComponent("layers.photato")
    try await document.persistDocument(to: native, format: .native, operation: .saveAsOperation)
    XCTAssertEqual(try DocumentIO.read(native), edited); XCTAssertFalse(document.isDocumentEdited)
    let psd = folder.appendingPathComponent("layers.psd")
    try await document.copyDocument(to: psd, format: .psd)
    try content(DocumentIO.read(psd), edited)
    XCTAssertEqual(document.fileURL, native); XCTAssertEqual(try Data(contentsOf: source), bytes)
  }
  @MainActor func testHTTPImportRetainsEditableStateAndRejectsCorruptLayerDataAtomically() async throws {
    let helper = AutomationTests(), upload = AutomationOpeningTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for d in service.controller.documents where d !== original { d.close() } }
      let bytes = try fixture(), expected = try RasterIO.read(bytes)
      let denied = try await upload.upload(service, bytes: bytes, type: "image/tiff")
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let accepted = try await upload.upload(service, bytes: bytes, type: "image/tiff")
      XCTAssertEqual(accepted.0.statusCode, 201, String(decoding: accepted.1, as: UTF8.self))
      let document = try XCTUnwrap(service.shares.last?.document)
      try content(document.store.document, expected)
      XCTAssertTrue(document.isDocumentEdited); XCTAssertNil(document.fileURL)
      let id = try XCTUnwrap(service.shares.last?.id)
      XCTAssertEqual(document.store.document.profileIsUntagged, true)
      let legacy = try await helper.request(service, path: "/v1/documents/\(id)/file.photato",
        headers: ["X-Photato-Archive-Version": "12"])
      XCTAssertEqual(legacy.0.statusCode, 422)
      let native = try await helper.request(service, path: "/v1/documents/\(id)/file.photato",
        headers: ["X-Photato-Archive-Version": "49"])
      XCTAssertEqual(native.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(native.1), document.store.document)
      var bad = bytes
      let marker = Data("Adobe Photoshop Document Data Block\0".utf8)
      let range = try XCTUnwrap(bad.range(of: marker))
      bad[range.lowerBound] = 0
      let count = service.shares.count, snapshot = document.store.document
      let rejected = try await upload.upload(service, bytes: bad, type: "image/tiff")
      XCTAssertEqual(rejected.0.statusCode, 422)
      XCTAssertEqual(service.shares.count, count); XCTAssertEqual(document.store.document, snapshot)
      let caps = try XCTUnwrap(AutomationService.documentTransferCapabilities["layeredTIFF"] as? [String: Any])
      XCTAssertEqual(caps["input"] as? Bool, true); XCTAssertEqual(caps["output"] as? Bool, true)
    }
  }
  @MainActor func testNativeLayeredTIFFSaveControlsOrdinarySaveAndCopyPreserveOwnership() async throws {
    for depth in [8, 16, 32] {
      let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let model = try RasterIO.read(fixture("\(depth)-little-marker.tiff"))
      let document = CraftNSDocument(model: model)
      controller.addDocument(document); defer { document.close() }
      let panel = NSSavePanel(); XCTAssertTrue(document.prepareSavePanel(panel))
      let accessory = try XCTUnwrap(document.saveAccessory)
      accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: .tiff)))
      accessory.updateFormat()
      XCTAssertFalse(accessory.tiffLayersRow.isHidden)
      XCTAssertEqual(accessory.tiffLayers.state, .on); XCTAssertTrue(accessory.tiffLayerCompression.isEnabled)
      accessory.tiffLayerCompression.selectItem(at: 1)
      accessory.tiffByteOrder.selectItem(at: 2)
      let target = folder.appendingPathComponent("editable.tiff")
      try await DocumentSaveWorkflowTests().save(document, to: target, format: .tiff)
      try content(DocumentIO.read(target), model)
      XCTAssertEqual(document.rememberedEncodingOptions[.tiff]?.tiffLayerCompression, .rle)
      XCTAssertFalse(document.isDocumentEdited)
      try document.store.executeEditorCommand(.renameLayer(model.layers[0].id, "Saved again"))
      let edited = document.store.document
      try await document.persistDocument(to: target, format: .tiff, operation: .saveOperation)
      try content(DocumentIO.read(target), edited)
      let saved = try Data(contentsOf: target), remembered = document.rememberedEncodingOptions
      do {
        try await document.persistDocument(to: target, format: .tiff, operation: .saveOperation,
          options: .init(tiffLayers: false))
        XCTFail("Ordinary Save flattened layers")
      } catch {}
      XCTAssertEqual(try Data(contentsOf: target), saved)
      XCTAssertEqual(document.rememberedEncodingOptions, remembered)
      let copy = folder.appendingPathComponent("copy.tiff")
      try await document.copyDocument(to: copy, format: .tiff, options: .init(tiffLayers: true))
      try content(DocumentIO.read(copy), edited)
      try await document.copyDocument(to: copy, format: .tiff)
      XCTAssertEqual(try DocumentIO.read(copy).layers.count, 1)
      XCTAssertEqual(document.fileURL, target)
      XCTAssertEqual(document.rememberedEncodingOptions, remembered)
      XCTAssertEqual(document.store.document, edited)
    }
  }
  @MainActor func testHTTPPreservingDownloadAndDefaultSaveShareSerializerAndExposeDefaults() async throws {
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try RasterIO.read(fixture("32-little-marker.tiff")))
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder); try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id), before = document.store.document
      let options = RasterEncodingOptions(tiffByteOrder: .littleEndian, tiffLayers: true, tiffLayerCompression: .zip)
      let fields = DocumentEncodingOptions.json(options)
      let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
      let download = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200)
      XCTAssertEqual(download.1, try DocumentIO.encode(before, format: .tiff, options: options))
      try content(RasterIO.read(download.1), before)
      let saved = try await helper.edit(service, document, "document.saveAs",
        ["name": "layers", "format": "tiff", "replace": false])
      XCTAssertEqual(saved, 200)
      let target = folder.appendingPathComponent("layers.tiff"), bytes = try Data(contentsOf: target)
      XCTAssertEqual(bytes, try DocumentIO.encodeForPersistence(before, format: .tiff))
      try content(DocumentIO.read(target), before)
      for invalid in ["{\"tiffLayers\":1}", "{\"tiffLayerCompression\":\"raw\",\"tiffLayers\":true}",
        "{\"tiffLayerCompression\":\"zip\"}", "{\"tiffLayers\":false,\"tiffLayerCompression\":\"rle\"}"] {
        let response = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
          headers: ["X-Photato-Export-Options": invalid])
        XCTAssertEqual(response.0.statusCode, 400)
      }
      let state = try await helper.request(service, path: "/v1/documents/\(id)")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      let effective = try XCTUnwrap(json["effectiveSaveEncodingOptions"] as? [String: [String: Any]])
      XCTAssertEqual(effective["tiff"]?["tiffLayers"] as? Bool, true)
      XCTAssertEqual(try Data(contentsOf: target), bytes)
      XCTAssertEqual(document.store.document, before)
    }
  }
  @MainActor func testLayeredJobOptionsStayDistinctAndAdobeTIFFContractRemainsUnchanged() async throws {
    let bytes = try fixture("16-little-marker.tiff"), expected = try RasterIO.read(bytes)
    let api = AutomationTests(), helper = AutomationEncodingOptionsTests()
    try await api.withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(bytes: bytes)) { service, shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      let variants: [RasterEncodingOptions] = [.init(), .init(tiffLayers: true, tiffLayerCompression: .rle),
        .init(tiffLayers: true, tiffLayerCompression: .zip)]
      let payload = helper.body(outputs: variants.map {
        helper.output("image/tiff", extra: ["encodingOptions": DocumentEncodingOptions.json($0)])
      })
      let outputs = try await helper.outputs(service, route: "/v1/action-jobs", payload: payload)
      XCTAssertEqual(outputs, try variants.map { try DocumentIO.encode(expected, format: .tiff, options: $0) })
      XCTAssertEqual(Set(outputs).count, 3)
      for output in outputs.dropFirst() { try content(RasterIO.read(output), expected) }
      let rejected = try await api.request(service, path: "/v2/execute-actions", body: payload)
      XCTAssertEqual(rejected.0.statusCode, 422)
      let adobe = try await helper.outputs(service, route: "/v2/execute-actions",
        payload: helper.body(outputs: [helper.output("image/tiff")]))
      XCTAssertEqual(adobe, [outputs[0]]); XCTAssertEqual(try RasterIO.read(adobe[0]).layers.count, 1)
      XCTAssertEqual(shared.store.document, before)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let bytes: Data
    func fetch(_ url: URL) async throws -> Data { bytes }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw CraftError.invalid("No external upload in this test.")
    }
  }
  @MainActor func testBothActionJobInterfacesImportTIFFAndPreserveLayersInPSDOutput() async throws {
    for depth in [8, 16, 32] {
      let bytes = try fixture("\(depth)-little-marker.tiff"), expected = try AdobeActionAssets.decode(bytes)
      let api = AutomationTests(), helper = AutomationEncodingOptionsTests()
      try await api.withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(bytes: bytes)) { service, shared in
        service.setResourceJobsEnabled(true)
        let before = shared.store.document
        let payload = helper.body(outputs: [helper.output("image/vnd.adobe.photoshop")])
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let outputs = try await helper.outputs(service, route: route, payload: payload)
          let psd = try XCTUnwrap(outputs.first)
          try content(PSDCodec.read(psd), expected)
          XCTAssertEqual(outputs.count, 1); XCTAssertEqual(shared.store.document, before)
        }
      }
    }
  }
}
