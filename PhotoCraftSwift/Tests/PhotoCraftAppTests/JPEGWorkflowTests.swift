import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class JPEGWorkflowTests: XCTestCase {
  @MainActor func testNativeControlsSaveRememberingCopyAndFailurePreserveState() async throws {
    let (controller, doc, folder) = try DocumentEncodingOptionsTests().fixture()
    defer { doc.close(); _ = controller }
    let panel = NSSavePanel()
    XCTAssertTrue(doc.prepareSavePanel(panel))
    let accessory = try XCTUnwrap(doc.saveAccessory)
    accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: .jpeg)))
    accessory.updateFormat()
    XCTAssertFalse(accessory.jpegControls.view.isHidden)
    XCTAssertTrue(accessory.pngRow.isHidden)
    let controls = accessory.jpegControls
    controls.quality.selectItem(at: 9); controls.format.selectItem(at: 2)
    controls.profile.selectItem(at: 2); controls.matteChoice.selectItem(at: 1)
    controls.matte.color = NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 1)
    controls.updateMatte(); XCTAssertTrue(controls.matte.isEnabled)
    let options = controls.options
    XCTAssertEqual(options, .init(jpegQuality: 8, jpegFormat: .optimized,
      jpegMatte: [0.25,0.5,0.75], jpegEmbedProfile: false))
    let before = doc.store.document, target = folder.appendingPathComponent("native.jpeg")
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .jpeg)
    let expected = try DocumentIO.encode(before, format: .jpeg, options: options)
    XCTAssertEqual(try Data(contentsOf: target), expected)
    XCTAssertEqual(doc.rememberedEncodingOptions[.jpeg], options)
    XCTAssertFalse(doc.isDocumentEdited)
    let next = DocumentCopyAccessory(panel: panel, initial: .jpeg,
      initialOptions: doc.rememberedEncodingOptions)
    XCTAssertEqual(next.encodingOptions, options)
    let history = doc.store.session.undoStack.count
    let copy = folder.appendingPathComponent("copy.jpeg")
    let progressive = RasterEncodingOptions(jpegQuality: 2, jpegFormat: .progressive)
    try await doc.copyDocument(to: copy, format: .jpeg, options: progressive)
    XCTAssertEqual(try Data(contentsOf: copy), try DocumentIO.encode(before, format: .jpeg, options: progressive))
    XCTAssertEqual(doc.fileURL, target); XCTAssertEqual(doc.rememberedEncodingOptions[.jpeg], options)
    XCTAssertEqual(doc.store.session.undoStack.count, history); XCTAssertEqual(doc.store.document, before)
    do {
      try await doc.persistDocument(to: target, format: .jpeg, operation: .saveOperation,
        options: .init(jpegQuality: 13))
      XCTFail("Invalid quality saved")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: target), expected)
    XCTAssertEqual(doc.rememberedEncodingOptions[.jpeg], options)
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw AdobeAPIError.unsupported("Owned hosted-output test.")
    }
  }
  @MainActor func testHTTPDownloadSaveAndBothJPEGJobInterfaces() async throws {
    let helper = AutomationTests(), jobs = AutomationEncodingOptionsTests()
    let input = try PSDCodec.writeRasterLayers(DocumentSaveWorkflowTests().fixture(depth: .f32))
    let decoded = try AdobeActionAssets.decode(input)
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 },
      resourceTransport: Transport(data: input)) { service, doc in
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder); service.setResourceJobsEnabled(true); try service.share(doc)
      let rejectedTransparency = try await helper.edit(service, doc, "document.saveAs",
        ["name": "transparent", "format": "jpeg", "replace": false])
      XCTAssertEqual(rejectedTransparency, 422)
      try doc.store.executeEditorCommand(.fill(try XCTUnwrap(doc.store.document.activeLayerID), Pixel(0.2,0.4,0.6)))
      let id = try XCTUnwrap(service.shares.first?.id), before = doc.store.document
      let options = RasterEncodingOptions(jpegQuality: 10, jpegFormat: .optimized,
        jpegMatte: [0.2,0.3,0.4], jpegEmbedProfile: false)
      let fields = DocumentEncodingOptions.json(options)
      let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
      let expected = try DocumentIO.encode(before, format: .jpeg, options: options)
      let download = try await helper.request(service, path: "/v1/documents/\(id)/file.jpeg",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200); XCTAssertEqual(download.1, expected)
      XCTAssertTrue(doc.rememberedEncodingOptions.isEmpty)
      let saved = try await helper.edit(service, doc, "document.saveAs",
        ["name": "jpeg", "format": "jpeg", "replace": false, "options": fields])
      XCTAssertEqual(saved, 200); XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("jpeg.jpeg")), expected)
      XCTAssertEqual(doc.rememberedEncodingOptions[.jpeg], options)
      let bad = try await helper.request(service, path: "/v1/documents/\(id)/file.jpeg",
        headers: ["X-Photato-Export-Options": "{\"jpegQuality\":true}"])
      XCTAssertEqual(bad.0.statusCode, 400)
      doc.fileOperationBusy = true
      let busy = try await helper.request(service, path: "/v1/documents/\(id)/file.jpeg")
      doc.fileOperationBusy = false
      XCTAssertEqual(busy.0.statusCode, 409)
      let payload = jobs.body(outputs: DocumentEncodingOptions.jpegQualities.map {
        jobs.output("image/jpeg", extra: ["quality": $0])
      })
      let wanted = try (0..<7).map {
        try DocumentIO.encode(decoded, format: .jpeg, options: .init(jpegQuality: $0 * 2))
      }
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let actual = try await jobs.outputs(service, route: route, payload: payload)
        XCTAssertEqual(actual, wanted)
        let rejected = try await helper.request(service, path: route,
          body: jobs.body(outputs: [jobs.output("image/jpeg", extra: ["scan": ["type": "progressive"]])]))
        XCTAssertEqual(rejected.0.statusCode, 400)
      }
      let extended = jobs.body(outputs: [jobs.output("image/jpeg", extra: ["encodingOptions": fields])])
      let native = try await jobs.outputs(service, route: "/v1/action-jobs", payload: extended)
      XCTAssertEqual(native, [try DocumentIO.encode(decoded, format: .jpeg, options: options)])
      let rejected = try await helper.request(service, path: "/v2/execute-actions", body: extended)
      XCTAssertEqual(rejected.0.statusCode, 422)
      XCTAssertEqual(doc.store.document, before)
    }
  }
  func testPinnedQualityContractAndStrictValidation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let spec = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
      root.appendingPathComponent("docs/contracts/adobe-photoshop-v2.json"))) as? [String: Any])
    let schemas = try XCTUnwrap((spec["components"] as? [String: Any])?["schemas"] as? [String: Any])
    let jpeg = try XCTUnwrap(schemas["JpegOutput"] as? [String: Any])
    let variants = try XCTUnwrap(jpeg["allOf"] as? [[String: Any]])
    let fields = try XCTUnwrap(variants[1]["properties"] as? [String: Any])
    XCTAssertEqual((fields["quality"] as? [String: Any])?["enum"] as? [String], DocumentEncodingOptions.jpegQualities)
    XCTAssertNil(fields["scan"])
    let options = RasterEncodingOptions(jpegQuality: 0, jpegFormat: .progressive,
      jpegMatte: [0,0.5,1], jpegEmbedProfile: true)
    let json = String(decoding: try JSONSerialization.data(withJSONObject: DocumentEncodingOptions.json(options)), as: UTF8.self)
    XCTAssertEqual(try DocumentEncodingOptions.header(json, format: .jpeg), options)
    XCTAssertThrowsError(try DocumentEncodingOptions.header(json, format: .png))
    for raw in ["{\"jpegQuality\":true}", "{\"jpegQuality\":1.5}", "{\"jpegQuality\":13}",
      "{\"jpegMatte\":[0,0]}", "{\"jpegMatte\":[0,true,1]}", "{\"jpegMatte\":[0,0,2]}",
      "{\"jpegFormat\":\"unknown\"}", "{\"jpegEmbedProfile\":1}", "{\"jpegScans\":3}"] {
      XCTAssertThrowsError(try DocumentEncodingOptions.header(raw, format: .jpeg))
    }
    let helper = AutomationEncodingOptionsTests()
    for extra: [String: Any] in [["quality": "unknown"], ["quality": 12], ["quality": NSNull()],
      ["quality": "low", "encodingOptions": ["jpegQuality": 4]]] {
      XCTAssertThrowsError(try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
        helper.body(outputs: [helper.output("image/jpeg", extra: extra)])), allowPhotatoOptions: true))
    }
    XCTAssertThrowsError(try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
      helper.body(outputs: [helper.output("image/png", extra: ["quality": "high"])]))))
  }
}
