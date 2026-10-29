import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFRichWorkflowTests: XCTestCase {
  func fixture(_ depth: Int = 16) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-rich/\(depth)-little.tiff"))
  }
  func content(_ actual: CraftDocument, _ expected: CraftDocument) throws {
    try TIFFLayerWorkflowTests().content(actual, expected)
    XCTAssertEqual(actual.layers.map(\.vectorMask), expected.layers.map(\.vectorMask))
    XCTAssertEqual(actual.sourceMetadata?["psdGlobal_LMsk"], expected.sourceMetadata?["psdGlobal_LMsk"])
    XCTAssertNotNil(actual.sourceMetadata?["psdGlobal_LMsk"])
  }
  @MainActor func testNativeRichTIFFOpenHistorySaveAndCopyPreserveMetadata() async throws {
    for depth in [8, 16, 32] {
      let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let bytes = try fixture(depth), source = folder.appendingPathComponent("rich.tiff")
      try bytes.write(to: source)
      let document = try XCTUnwrap(controller.makeDocument(withContentsOf: source,
        ofType: DocumentIO.Format.tiff.typeIdentifier) as? CraftNSDocument)
      controller.addDocument(document); defer { document.close() }
      let before = document.store.document
      XCTAssertEqual(before.layers.count, depth == 32 ? 7 : 8)
      try document.store.executeEditorCommand(.renameLayer(before.layers[1].id, "Edited Levels"))
      let edited = document.store.document
      await document.store.undo(); XCTAssertEqual(document.store.document, before)
      await document.store.redo(); XCTAssertEqual(document.store.document, edited)
      let target = folder.appendingPathComponent("saved.tiff")
      let options = RasterEncodingOptions(tiffByteOrder: .littleEndian, tiffLayers: true, tiffLayerCompression: .rle)
      try await document.persistDocument(to: target, format: .tiff, operation: .saveAsOperation, options: options)
      try content(DocumentIO.read(target), edited)
      XCTAssertFalse(document.isDocumentEdited)
      XCTAssertEqual(document.rememberedEncodingOptions[.tiff], options)
      let copy = folder.appendingPathComponent("copy.psb")
      try await document.copyDocument(to: copy, format: .psb)
      try content(DocumentIO.read(copy), edited)
      XCTAssertEqual(document.fileURL, target); XCTAssertEqual(document.store.document, edited)
      XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
  }
  @MainActor func testHTTPRichImportDownloadAndSaveUseSameNativeEncoding() async throws {
    let helper = AutomationTests(), upload = AutomationOpeningTests()
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.close() } }
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true); service.setSaveDirectory(folder)
      let bytes = try fixture(32), expected = try RasterIO.read(bytes)
      let accepted = try await upload.upload(service, bytes: bytes, type: "image/tiff")
      XCTAssertEqual(accepted.0.statusCode, 201)
      let document = try XCTUnwrap(service.shares.last?.document), id = try XCTUnwrap(service.shares.last?.id)
      try content(document.store.document, expected)
      let model = document.store.document
      let options = RasterEncodingOptions(tiffByteOrder: .littleEndian, tiffLayers: true, tiffLayerCompression: .zip)
      let fields = DocumentEncodingOptions.json(options)
      let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
      let downloaded = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(downloaded.0.statusCode, 200)
      XCTAssertEqual(downloaded.1, try DocumentIO.encode(model, format: .tiff, options: options))
      try content(RasterIO.read(downloaded.1), model)
      let status = try await helper.edit(service, document, "document.saveAs",
        ["name": "rich", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(status, 200)
      let target = folder.appendingPathComponent("rich.tiff")
      XCTAssertEqual(try Data(contentsOf: target), downloaded.1)
      try content(DocumentIO.read(target), model)
      XCTAssertEqual(document.store.document, model)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let bytes: Data
    func fetch(_ url: URL) async throws -> Data { bytes }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw CraftError.invalid("No external upload in this test.")
    }
  }
  @MainActor func testBothJobInterfacesPreserveRichInputInPSDAndPhotatoTIFFOutput() async throws {
    let bytes = try fixture(), expected = try RasterIO.read(bytes)
    let api = AutomationTests(), helper = AutomationEncodingOptionsTests()
    try await api.withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(bytes: bytes)) { service, shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let result = try await helper.outputs(service, route: route,
          payload: helper.body(outputs: [helper.output("image/vnd.adobe.photoshop")]))
        try content(PSDCodec.read(XCTUnwrap(result.first)), expected)
      }
      let options = RasterEncodingOptions(tiffByteOrder: .littleEndian, tiffLayers: true)
      let payload = helper.body(outputs: [helper.output("image/tiff",
        extra: ["encodingOptions": DocumentEncodingOptions.json(options)])])
      let result = try await helper.outputs(service, route: "/v1/action-jobs", payload: payload)
      try content(RasterIO.read(XCTUnwrap(result.first)), expected)
      let denied = try await api.request(service, path: "/v2/execute-actions", body: payload)
      XCTAssertEqual(denied.0.statusCode, 422)
      XCTAssertEqual(shared.store.document, before)
    }
  }
}
