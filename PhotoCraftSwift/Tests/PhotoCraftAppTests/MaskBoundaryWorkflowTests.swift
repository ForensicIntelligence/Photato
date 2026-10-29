import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MaskBoundaryWorkflowTests: XCTestCase {
  func fixture() throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("PhotoCraftImagingTests/Fixtures/MaskBoundary/offcanvas-photoshop.psd"))
  }
  @MainActor func testNativeAndHTTPImportPreviewAndPersistenceUseCorrectBoundary() async throws {
    let input = try fixture(), helper = AutomationTests(), opening = AutomationOpeningTests()
    let model = try DocumentIO.decodeUpload(input, native: false, name: "Owned mask")
    XCTAssertLessThan(try Renderer.composite(model).pixel(x: 0, y: 0).r, 0.6)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.updateChangeCount(.changeCleared); doc.close() } }
      let denied = try await opening.upload(service, bytes: input, type: "image/vnd.adobe.photoshop")
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let accepted = try await opening.upload(service, bytes: input, type: "image/vnd.adobe.photoshop", format: "psd")
      XCTAssertEqual(accepted.0.statusCode, 201)
      let share = try XCTUnwrap(service.shares.first), document = try XCTUnwrap(share.document)
      let native = try Renderer.composite(model)
      XCTAssertEqual(try Renderer.composite(document.store.document), native)
      let preview = try await helper.request(service, path: "/v1/documents/\(share.id)/preview.png")
      XCTAssertEqual(preview.0.statusCode, 200)
      XCTAssertEqual(preview.1, try AutomationService.png(model))
      let saved = try await helper.request(service, path: "/v1/documents/\(share.id)/file.photato")
      XCTAssertEqual(saved.0.statusCode, 200)
      XCTAssertEqual(try Renderer.composite(NativeArchive.decode(saved.1)), native)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  private actor Transport: AdobeResourceTransport {
    let data: Data
    init(_ data: Data) { self.data = data }
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw AdobeAPIError.unsupported("This test uses hosted outputs only.")
    }
  }
  @MainActor func testBothActionInterfacesRenderOffCanvasMasksLikeDesktop() async throws {
    let input = try fixture(), helper = AutomationTests()
    let payload: [String: Any] = [
      "image": ["source": ["url": "https://example.test/mask.psd"]],
      "options": ["actions": [["source": ["contentType": "application/json",
        "content": "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(input)) { service, original in
      let before = original.store.document
      service.setResourceJobsEnabled(true)
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let submitted = try await helper.request(service, path: route, body: payload)
        XCTAssertEqual(submitted.0.statusCode, 202)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: submitted.1) as? [String: Any])
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(body["statusUrl"] as? String)))
        var terminal: [String: Any]?
        for _ in 0..<1000 {
          let response = try await helper.request(service, path: url.path)
          let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
          if ["succeeded", "failed"].contains(snapshot["status"] as? String ?? "") { terminal = snapshot; break }
          try await Task.sleep(for: .milliseconds(10))
        }
        let result = try XCTUnwrap(terminal)
        XCTAssertEqual(result["status"] as? String, "succeeded", "\(result)")
        if result["status"] as? String == "succeeded" {
          let output = try XCTUnwrap((result["result"] as? [String: Any])?["outputs"] as? [[String: Any]])
          let destination = try XCTUnwrap(output.first?["destination"] as? [String: Any])
          let assetURL = try XCTUnwrap(URL(string: try XCTUnwrap(destination["url"] as? String)))
          let asset = try await helper.request(service, path: assetURL.path)
          XCTAssertEqual(asset.0.statusCode, 200)
          XCTAssertEqual(asset.1, try DocumentIO.encode(PSDCodec.read(input), format: .psd))
        }
      }
      XCTAssertEqual(original.store.document, before)
      XCTAssertTrue(original.store.session.undoStack.isEmpty)
    }
  }
}
