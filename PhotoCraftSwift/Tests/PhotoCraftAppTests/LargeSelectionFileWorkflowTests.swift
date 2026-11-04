import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging
@testable import PhotoCraft

final class LargeSelectionFileWorkflowTests: XCTestCase {
  func input(_ name: String = "large-8-v2-c1.psb") throws -> Data {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/large-selection-files")
    let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])
    let cases = try XCTUnwrap(manifest["cases"] as? [[String: Any]])
    let item = try XCTUnwrap(cases.first { ($0["name"] as? String) == name })
    let data = Data(try PSDChannelCodec.inflate(Data(contentsOf: folder.appendingPathComponent(try XCTUnwrap(item["file"] as? String))), expected: try XCTUnwrap(item["decodedFileBytes"] as? Int)))
    XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), item["fileSHA256"] as? String)
    return data
  }
  func capture(_ data: Data, _ name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else { return }
    let folder = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try data.write(to: folder.appendingPathComponent(name))
  }
  @MainActor func request(_ service: AutomationService, _ path: String, data: Data? = nil, headers: [String: String] = [:]) async throws -> (HTTPURLResponse, Data) {
    var request = URLRequest(url: try XCTUnwrap(URL(string: try XCTUnwrap(service.endpoint) + path)))
    request.timeoutInterval = 60
    request.setValue("Bearer " + (service.token ?? ""), forHTTPHeaderField: "Authorization")
    if let data { request.httpMethod = "POST"; request.httpBody = data; request.setValue("image/vnd.adobe.photoshop", forHTTPHeaderField: "Content-Type") }
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let (body, response) = try await URLSession.shared.data(for: request)
    return (try XCTUnwrap(response as? HTTPURLResponse), body)
  }

  @MainActor func testNativeReadPaintUndoAndReopenPreserveLargeMaskWithoutLayers() async throws {
    let file = CraftNSDocument(model: try CraftDocument(width: 4, height: 3))
    defer { file.close() }
    try file.read(from: input(), ofType: DocumentIO.Format.psd.contentType.identifier)
    let store = file.store, original = store.document
    XCTAssertEqual(original.width, 4096); XCTAssertEqual(original.height, 2049)
    XCTAssertTrue(original.isChannelOnly); XCTAssertTrue(original.layers.isEmpty)
    let alpha = try XCTUnwrap(original.alphaChannels?.first)
    XCTAssertEqual(store.editingChannel, .alpha(alpha.id))
    XCTAssertEqual(alpha.name, "Owned large selection")
    XCTAssertEqual(alpha.psdIdentifier, 2)
    let archive = try file.data(ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(try NativeArchive.decodePaged(archive), original)
    store.tool = .brush
    var brush = store.brush; brush.size = 4; brush.hardness = 1; brush.color = .white
    store.stroke([.init(x: 512, y: 512)], brush: brush)
    XCTAssertNil(store.error); XCTAssertEqual(store.document.alphaChannels?.first?.pixels.pixel(x: 512, y: 512).r, 1)
    XCTAssertTrue(store.document.layers.isEmpty)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo(); XCTAssertEqual(store.document, original)
    try file.read(from: archive, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testHTTPImportNative85AndPSBDownloadKeepEveryMaskSample() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      service.setDocumentTransfersEnabled(true)
      let response = try await self.request(service, "/v1/documents/import", data: self.input())
      XCTAssertEqual(response.0.statusCode, 201, String(decoding: response.1, as: UTF8.self))
      guard response.0.statusCode == 201 else { return }
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any]), id = try XCTUnwrap(state["id"] as? String)
      let file = try XCTUnwrap(service.shares.first { $0.id.uuidString == id }?.document)
      defer { file.store.renderTask?.cancel(); service.controller.removeDocument(file); file.close() }
      let original = file.store.document
      XCTAssertTrue(original.isChannelOnly); XCTAssertEqual(original.width * original.height, 8_392_704)
      let legacy = try await self.request(service, "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version":"84"])
      XCTAssertEqual(legacy.0.statusCode, 422)
      let native = try await self.request(service, "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version":"85"])
      XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decodePaged(native.1), original)
      let psb = try await self.request(service, "/v1/documents/\(id)/file.psb")
      XCTAssertEqual(psb.0.statusCode, 200)
      let reopened = try PSDCodec.readPaged(psb.1)
      XCTAssertEqual(reopened.alphaChannels?.first?.pixels, original.alphaChannels?.first?.pixels)
      XCTAssertEqual(reopened.alphaChannels?.first?.name, "Owned large selection")
      XCTAssertEqual(reopened.alphaChannels?.first?.psdIdentifier, 2)
      XCTAssertEqual(file.store.document, original); XCTAssertTrue(file.store.session.undoStack.isEmpty)
      try self.capture(psb.1, "large-selection-api.psb")
      let capabilities = try XCTUnwrap(ChannelAPI.photoshopCapabilities["standaloneSelections"] as? [String: Any])
      XCTAssertEqual(capabilities["maximumPSBside"] as? Int, 300000)
      XCTAssertEqual(capabilities["printingPlateMaximumPixels"] as? Int, 8_388_608)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }

  @MainActor func testMalformedLargeUploadDoesNotPublishAnotherDocument() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, file in
      service.setDocumentTransfersEnabled(true)
      let original = file.store.document, count = service.controller.documents.count
      let data = try self.input("large-8-v2-c2.psb")
      let response = try await self.request(service, "/v1/documents/import", data: Data(data.dropLast()))
      XCTAssertEqual(response.0.statusCode, 422)
      XCTAssertEqual(service.controller.documents.count, count)
      XCTAssertEqual(file.store.document, original)
      XCTAssertTrue(service.shares.isEmpty)
    }
  }

  func testPublishedCompositeExecutorPreservesLargeAuxiliaryInputWithoutInventedChannelActions() throws {
    let data = try input()
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: [
      "image":["source":["url":"https://example.test/owned-large-selection.psb"]],
      "outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]
    ]), createComposite: true)
    let source = try AdobeActionAssets.decode(data)
    let result = try XCTUnwrap(AdobeActionAssets.execute(request, input: data).first)
    let reopened = try PSDCodec.readPaged(result.data)
    XCTAssertTrue(reopened.isChannelOnly)
    XCTAssertEqual(reopened.alphaChannels?.first?.pixels, source.alphaChannels?.first?.pixels)
    XCTAssertEqual(reopened.alphaChannels?.first?.psdIdentifier, 2)
    try capture(result.data, "large-selection-adobe-composite.psd")
  }
}
