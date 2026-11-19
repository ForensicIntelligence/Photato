import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AutomationEncodingOptionsTests: XCTestCase {
  @MainActor func testHTTPDownloadsAndSaveAsUseIdenticalOptionsAndExposeRememberedState() async throws {
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder); try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let snapshot = document.store.document
      let options = RasterEncodingOptions(pngCompression: 9, pngInterlaced: true)
      let fields = DocumentEncodingOptions.json(options)
      let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
      let expected = try DocumentIO.encode(snapshot, format: .png, options: options)
      let downloaded = try await helper.request(service, path: "/v1/documents/\(id)/file.png",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(downloaded.0.statusCode, 200); XCTAssertEqual(downloaded.1, expected)
      XCTAssertTrue(document.rememberedEncodingOptions.isEmpty)
      let saved = try await helper.edit(service, document, "document.saveAs",
        ["name": "owned", "format": "png", "replace": false, "options": fields])
      XCTAssertEqual(saved, 200)
      XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("owned.png")), expected)
      XCTAssertEqual(document.rememberedEncodingOptions[.png], options)
      let state = try await helper.request(service, path: "/v1/documents/\(id)")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      let remembered = try XCTUnwrap(json["saveEncodingOptions"] as? [String: [String: Any]])
      XCTAssertEqual(remembered["png"]?["pngCompression"] as? Int, 9)
      XCTAssertEqual(remembered["png"]?["pngInterlaced"] as? Bool, true)
      let invalid = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(invalid.0.statusCode, 400)
      XCTAssertEqual(document.store.document, snapshot)
      XCTAssertEqual(document.rememberedEncodingOptions[.png], options)
      let denied = try await helper.edit(service, document, "document.save", ["options": ["pngCompression": true]])
      XCTAssertEqual(denied, 400)
      XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("owned.png")), expected)
      service.setDocumentSavesEnabled(false)
      let forbidden = try await helper.edit(service, document, "document.save", ["options": fields])
      XCTAssertEqual(forbidden, 403)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw AdobeAPIError.unsupported("No external upload in this owned test.")
    }
  }
  func body(outputs: [[String: Any]]) -> [String: Any] {
    ["image": ["source": ["url": "https://example.invalid/owned.psd"]],
     "options": ["actions": [["source": [
       "content": "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]",
       "contentType": "application/json"]]]], "outputs": outputs]
  }
  func output(_ media: String, extra: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = ["mediaType": media, "destination": ["validityPeriod": 60]]
    result.merge(extra) { _, new in new }; return result
  }
  @MainActor func outputs(_ service: AutomationService, route: String,
    payload: [String: Any]) async throws -> [Data] {
    let helper = AutomationTests(), accepted = try await helper.request(service, path: route, body: payload)
    XCTAssertEqual(accepted.0.statusCode, 202, String(decoding: accepted.1, as: UTF8.self))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: accepted.1) as? [String: Any])
    let status = try XCTUnwrap(URL(string: try XCTUnwrap(object["statusUrl"] as? String)))
    for _ in 0..<200 {
      let response = try await helper.request(service, path: status.path)
      let row = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      if row["status"] as? String == "failed" { XCTFail("\(row)"); break }
      if row["status"] as? String == "succeeded" {
        let result = try XCTUnwrap(row["result"] as? [String: Any])
        let outputs = try XCTUnwrap(result["outputs"] as? [[String: Any]])
        var bytes: [Data] = []
        for item in outputs {
          let destination = try XCTUnwrap(item["destination"] as? [String: Any])
          let url = try XCTUnwrap(URL(string: try XCTUnwrap(destination["url"] as? String)))
          let asset = try await helper.request(service, path: url.path)
          XCTAssertEqual(asset.0.statusCode, 200)
          XCTAssertEqual(asset.0.value(forHTTPHeaderField: "Content-Type"), item["mediaType"] as? String)
          bytes.append(asset.1)
        }
        return bytes
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw CraftError.invalid("Owned encoding job did not finish.")
  }
  @MainActor func testBothActualJobRoutesKeepDistinctPNGOptionsAndTIFFOutput() async throws {
    let input = try PSDCodec.writeRasterLayers(DocumentSaveWorkflowTests().fixture())
    let decoded = try AdobeActionAssets.decode(input)
    let expected = try [
      DocumentIO.encode(decoded, format: .png, options: .init(pngCompression: 0)),
      DocumentIO.encode(decoded, format: .png, options: .init(pngCompression: 9)),
      DocumentIO.encode(decoded, format: .tiff),
    ]
    XCTAssertNotEqual(expected[0], expected[1], "Different compression outputs must not share the same cache entry")
    let payload = body(outputs: [
      output("image/png", extra: ["compression": "none"]),
      output("image/png", extra: ["compression": "maximum"]),
      output("image/tiff"),
    ])
    try await AutomationTests().withService(pressedMouseButtons: { 0 },
      resourceTransport: Transport(data: input)) { service, shared in
      service.setResourceJobsEnabled(true)
      let before = shared.store.document
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let bytes = try await outputs(service, route: route, payload: payload)
        XCTAssertEqual(bytes, expected)
      }
      XCTAssertEqual(shared.store.document, before); XCTAssertTrue(service.shares.isEmpty)
    }
  }
  @MainActor func testImportAndBothJobsRetainSavedChannelsWithoutMergedPreview() async throws {
    var model = try DocumentSaveWorkflowTests().fixture(depth: .u16)
    var plane = try Surface(width: model.width, height: model.height, depth: .u16, fill: .black)
    plane.setPixel(x: 2, y: 1, Pixel(0.25, 0.25, 0.25))
    model.alphaChannels = [AlphaChannel(name: "Owned saved selection", pixels: plane)]
    let original = try PSDCodec.writeRasterLayers(model, format: .psb)
    let colorBytes = original[26..<30].reduce(0) { ($0 << 8) | Int($1) }
    let resourceSize = 30 + colorBytes
    let length = original[resourceSize..<resourceSize + 4].reduce(0) { ($0 << 8) | Int($1) }
    let resourcesEnd = resourceSize + 4 + length
    let flag = Data([0x38, 0x42, 0x49, 0x4D, 0x04, 0x21, 0, 0, 0, 0, 0, 21,
      0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 84, 0, 0, 0, 1, 0, 84, 0, 0, 0, 1, 0])
    var input = Data(original.prefix(resourceSize))
    var nextLength = UInt32(length + flag.count).bigEndian
    withUnsafeBytes(of: &nextLength) { input.append(contentsOf: $0) }
    input.append(original[(resourceSize + 4)..<resourcesEnd])
    input.append(flag)
    input.append(original[resourcesEnd...])
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(data: input)) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      service.setResourceJobsEnabled(true)
      let uploads = AutomationOpeningTests()
      let truncated = try await uploads.upload(service, bytes: input.dropLast(), type: "application/x-photoshop")
      XCTAssertEqual(truncated.0.statusCode, 422)
      XCTAssertTrue(service.shares.isEmpty)
      let opened = try await uploads.upload(service, bytes: input, type: "application/x-photoshop")
      XCTAssertEqual(opened.0.statusCode, 201)
      let document = try XCTUnwrap(service.shares.last?.document?.store.document)
      XCTAssertEqual(document.alphaChannels?.map(\.name), ["Owned saved selection"])
      XCTAssertEqual(document.alphaChannels?.first?.pixels, plane)
      let payload = body(outputs: [output("image/vnd.adobe.photoshop")])
      let expected = try PSDCodec.writeRasterLayers(AdobeActionAssets.decode(input))
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let files = try await outputs(service, route: route, payload: payload)
        XCTAssertEqual(files, [expected])
        XCTAssertEqual(try PSDCodec.read(XCTUnwrap(files.first)).alphaChannels?.first?.pixels, plane)
      }
    }
  }

  @MainActor func testPhotatoOnlyJobOptionsAreRejectedByAdobeRouteAndAppliedByNativeRoute() async throws {
    let input = try PSDCodec.writeRasterLayers(DocumentSaveWorkflowTests().fixture())
    let decoded = try AdobeActionAssets.decode(input)
    let options = RasterEncodingOptions(tiffCompression: .zip)
    let payload = body(outputs: [output("image/tiff",
      extra: ["encodingOptions": DocumentEncodingOptions.json(options)])])
    try await AutomationTests().withService(pressedMouseButtons: { 0 },
      resourceTransport: Transport(data: input)) { service, _ in
      service.setResourceJobsEnabled(true)
      let rejected = try await AutomationTests().request(service, path: "/v2/execute-actions", body: payload)
      XCTAssertEqual(rejected.0.statusCode, 422)
      let bytes = try await outputs(service, route: "/v1/action-jobs", payload: payload)
      XCTAssertEqual(bytes, [try DocumentIO.encode(decoded, format: .tiff, options: options)])
    }
  }
  func testPinnedPNGContractAndInvalidOptionVariants() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let spec = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
      root.appendingPathComponent("docs/contracts/adobe-photoshop-v2.json"))) as? [String: Any])
    let components = try XCTUnwrap(spec["components"] as? [String: Any])
    let schemas = try XCTUnwrap(components["schemas"] as? [String: Any])
    let png = try XCTUnwrap(schemas["PngOutput"] as? [String: Any])
    let variants = try XCTUnwrap(png["allOf"] as? [[String: Any]])
    let fields = try XCTUnwrap(variants[1]["properties"] as? [String: Any])
    let compression = try XCTUnwrap(fields["compression"] as? [String: Any])
    XCTAssertEqual(compression["enum"] as? [String], DocumentEncodingOptions.pngLevels)
    for (index, name) in DocumentEncodingOptions.pngLevels.enumerated() {
      let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
        body(outputs: [output("image/png", extra: ["compression": name])])))
      XCTAssertEqual(request.outputs[0].encodingOptions.pngCompression, index)
    }
    let invalidVariants: [[String: Any]] = [
      ["compression": "unknown"], ["compression": 1], ["compression": NSNull()],
      ["scan": ["type": "progressive"]], ["encodingOptions": ["pngCompression": 2]],
    ]
    for extra in invalidVariants {
      XCTAssertThrowsError(try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
        body(outputs: [output("image/png", extra: extra)]))))
    }
    XCTAssertThrowsError(try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
      body(outputs: [output("image/tiff", extra: ["compression": "none"])]))))
    XCTAssertThrowsError(try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject:
      body(outputs: [output("image/png", extra: ["compression": "none",
        "encodingOptions": ["pngCompression": 4]])])), allowPhotatoOptions: true))
  }
}
