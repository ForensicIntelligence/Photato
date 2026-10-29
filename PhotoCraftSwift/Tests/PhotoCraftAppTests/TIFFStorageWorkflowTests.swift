import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFStorageWorkflowTests: XCTestCase {
  let options = RasterEncodingOptions(tiffCompression: .lzw, tiffByteOrder: .bigEndian,
    tiffPixelOrder: .perChannel, tiffPredictor: true, tiffLayers: true)

  @MainActor func testNativeControlsRememberSuccessfulSaveAndCopyPreservesOwnership() async throws {
    let (controller, doc, folder) = try DocumentEncodingOptionsTests().fixture()
    defer { doc.close(); _ = controller }
    doc.store.session = EditorSession(document: try TIFFFloatWorkflowTests().fixture())
    let panel = NSSavePanel(); XCTAssertTrue(doc.prepareSavePanel(panel))
    let a = try XCTUnwrap(doc.saveAccessory)
    a.formats.selectItem(at: try XCTUnwrap(a.availableFormats.firstIndex(of: .tiff))); a.updateFormat()
    XCTAssertFalse(a.tiffByteOrderRow.isHidden); XCTAssertFalse(a.tiffPixelOrderRow.isHidden)
    XCTAssertFalse(a.tiffPredictor.isHidden); XCTAssertFalse(a.tiffPredictor.isEnabled)
    a.tiffCompression.selectItem(at: 2); a.updateTIFFCompression()
    XCTAssertTrue(a.tiffPredictor.isEnabled)
    a.tiffByteOrder.selectItem(at: 1); a.tiffPixelOrder.selectItem(at: 2)
    a.tiffPredictor.state = .on; a.updateTIFFPredictor()
    XCTAssertEqual(a.encodingOptions, options)
    a.formats.selectItem(at: try XCTUnwrap(a.availableFormats.firstIndex(of: .psd))); a.updateFormat()
    XCTAssertTrue(a.tiffByteOrderRow.isHidden); XCTAssertTrue(a.tiffPixelOrderRow.isHidden)
    a.formats.selectItem(at: try XCTUnwrap(a.availableFormats.firstIndex(of: .tiff))); a.updateFormat()
    XCTAssertEqual(a.encodingOptions, options)
    let before = doc.store.document, target = folder.appendingPathComponent("planar.tiff")
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .tiff)
    XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(before, format: .tiff, options: options))
    XCTAssertEqual(doc.rememberedEncodingOptions[.tiff], options)
    XCTAssertEqual(try TIFFFloatWorkflowTests().raw(DocumentIO.read(target)), try TIFFFloatWorkflowTests().raw(before))
    let reload = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff,
      initialOptions: doc.rememberedEncodingOptions, depth: .f32)
    XCTAssertEqual(reload.encodingOptions, options)
    reload.tiffCompression.selectItem(at: 1); reload.updateTIFFCompression()
    XCTAssertFalse(reload.tiffPredictor.isEnabled)
    XCTAssertEqual(reload.encodingOptions.tiffPredictor, false)
    let copy = folder.appendingPathComponent("copy.tiff")
    let copyOptions = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .littleEndian,
      tiffPixelOrder: .interleaved, tiffPredictor: true)
    try await doc.copyDocument(to: copy, format: .tiff, options: copyOptions)
    XCTAssertEqual(try Data(contentsOf: copy), try DocumentIO.encode(before, format: .tiff, options: copyOptions))
    XCTAssertEqual(doc.rememberedEncodingOptions[.tiff], options)
    XCTAssertEqual(doc.fileURL, target); XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertEqual(doc.store.document, before)
  }
  @MainActor func testIntegerControlsAndFailedPredictorSavePreserveExistingFileAndSettings() async throws {
    let (controller, doc, folder) = try DocumentEncodingOptionsTests().fixture()
    defer { doc.close(); _ = controller }
    let a = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff)
    XCTAssertTrue(a.encodingOptions.isEmpty); XCTAssertTrue(a.tiffPredictor.isHidden)
    a.tiffCompression.selectItem(at: 2); a.updateTIFFCompression()
    XCTAssertFalse(a.tiffPredictor.isEnabled)
    let target = folder.appendingPathComponent("preserve.tiff"), original = Data("Existing output".utf8)
    try original.write(to: target)
    doc.rememberedEncodingOptions[.tiff] = .init(tiffCompression: .zip)
    let before = doc.store.document
    do {
      try await doc.persistDocument(to: target, format: .tiff, operation: .saveAsOperation, options: options)
      XCTFail("Integer floating predictor was accepted")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: target), original)
    XCTAssertEqual(doc.rememberedEncodingOptions[.tiff], .init(tiffCompression: .zip))
    XCTAssertEqual(doc.store.document, before); XCTAssertNil(doc.fileURL)
    XCTAssertFalse(doc.fileOperationBusy)
  }
  @MainActor func testHTTPDownloadSaveAndInvalidStorageOptionsUseSharedSerializer() async throws {
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      doc.store.session = EditorSession(document: try TIFFFloatWorkflowTests().fixture())
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder); try service.share(doc)
      let id = try XCTUnwrap(service.shares.first?.id), before = doc.store.document
      let fields = DocumentEncodingOptions.json(options)
      let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
      let response = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(response.1, try DocumentIO.encode(before, format: .tiff, options: options))
      XCTAssertEqual(try TIFFFloatWorkflowTests().raw(RasterIO.read(response.1)), try TIFFFloatWorkflowTests().raw(before))
      let status = try await helper.edit(service, doc, "document.saveAs",
        ["name": "storage", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(status, 200); XCTAssertEqual(doc.rememberedEncodingOptions[.tiff], options)
      let target = folder.appendingPathComponent("storage.tiff"), saved = try Data(contentsOf: target)
      for invalid in [
        "{\"tiffByteOrder\":\"middle\"}", "{\"tiffPixelOrder\":true}",
        "{\"tiffPredictor\":1}", "{\"tiffPredictor\":true}", "{\"tiffCompression\":\"none\",\"tiffPredictor\":true}",
      ] {
        let denied = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
          headers: ["X-Photato-Export-Options": invalid])
        XCTAssertEqual(denied.0.statusCode, 400)
      }
      let mismatch = try await helper.request(service, path: "/v1/documents/\(id)/file.png",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(mismatch.0.statusCode, 400)
      let state = try await helper.request(service, path: "/v1/documents/\(id)")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      let remembered = try XCTUnwrap(json["saveEncodingOptions"] as? [String: [String: Any]])
      XCTAssertEqual(remembered["tiff"]?["tiffPixelOrder"] as? String, "perChannel")
      XCTAssertEqual(remembered["tiff"]?["tiffPredictor"] as? Bool, true)
      XCTAssertEqual(try Data(contentsOf: target), saved)
      XCTAssertEqual(doc.store.document, before)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw CraftError.invalid("Owned hosted-output test")
    }
  }
  @MainActor func testActionJobsSeparateTIFFStorageCacheKeysAndKeepAdobeContract() async throws {
    let input = try PSDCodec.writeRasterLayers(TIFFFloatWorkflowTests().fixture())
    let model = try AdobeActionAssets.decode(input), helper = AutomationEncodingOptionsTests()
    let variants = [
      options,
      .init(tiffCompression: .lzw, tiffByteOrder: .littleEndian, tiffPixelOrder: .perChannel, tiffPredictor: true),
      .init(tiffCompression: .lzw, tiffByteOrder: .bigEndian, tiffPixelOrder: .interleaved, tiffPredictor: true),
      .init(tiffCompression: .lzw, tiffByteOrder: .bigEndian, tiffPixelOrder: .perChannel, tiffPredictor: false),
    ]
    try await AutomationTests().withService(pressedMouseButtons: { 0 },
      resourceTransport: Transport(data: input)) { service, shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      let payload = helper.body(outputs: variants.map {
        helper.output("image/tiff", extra: ["encodingOptions": DocumentEncodingOptions.json($0)])
      })
      let bytes = try await helper.outputs(service, route: "/v1/action-jobs", payload: payload)
      XCTAssertEqual(bytes, try variants.map { try DocumentIO.encode(model, format: .tiff, options: $0) })
      XCTAssertEqual(Set(bytes).count, 4)
      let rejected = try await AutomationTests().request(service, path: "/v2/execute-actions", body: payload)
      XCTAssertEqual(rejected.0.statusCode, 422)
      let adobe = try await helper.outputs(service, route: "/v2/execute-actions",
        payload: helper.body(outputs: [helper.output("image/tiff")]))
      XCTAssertEqual(adobe, [try DocumentIO.encode(model, format: .tiff)])
      XCTAssertEqual(shared.store.document, before)
    }
  }
}
