import AppKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationOpeningTests: XCTestCase {
  @MainActor func upload(_ service: AutomationService, bytes: Data, type: String,
    format: String? = nil) async throws -> (HTTPURLResponse, Data)
  {
    var request = URLRequest(url: URL(string: try XCTUnwrap(service.endpoint) + "/v1/documents/import")!)
    request.httpMethod = "POST"; request.httpBody = bytes
    request.setValue("Bearer \(try XCTUnwrap(service.token))", forHTTPHeaderField: "Authorization")
    request.setValue(type, forHTTPHeaderField: "Content-Type")
    if let format { request.setValue(format, forHTTPHeaderField: "X-Photato-Open-Format") }
    let (data, response) = try await URLSession.shared.data(for: request)
    return (try XCTUnwrap(response as? HTTPURLResponse), data)
  }
  @MainActor func testHTTPSelectedNativeAndRasterFormatsMatchDesktopAndRejectMismatches() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller
      defer { for doc in c.documents where doc !== original { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let model = try CraftDocument(width: 4, height: 3)
      for format in [DocumentIO.Format.native, .psd, .psb, .png] {
        let bytes = try DocumentIO.encode(model, format: format)
        let bad = try await upload(service, bytes: bytes, type: "application/octet-stream", format: "jpeg")
        XCTAssertEqual(bad.0.statusCode, 422)
        XCTAssertEqual(service.shares.count, 0)
        let valid = try await upload(service, bytes: bytes, type: "application/octet-stream", format: format.rawValue)
        XCTAssertEqual(valid.0.statusCode, 201, String(decoding: valid.1, as: UTF8.self))
        let doc = try XCTUnwrap(service.shares.last?.document)
        var expected = try DocumentIO.decodeUpload(bytes, native: format == .native, name: "Imported Image")
        let actual = doc.store.document
        if format != .native {
          // Independent image decodes allocate document/layer identities.
          // This one-layer fixture must otherwise preserve the complete model.
          XCTAssertEqual(expected.layers.count, 1)
          XCTAssertEqual(actual.layers.count, 1)
          expected.id = actual.id
          expected.layers[0].id = actual.layers[0].id
          expected.activeLayerID = actual.activeLayerID
          if let left = actual.sourceMetadata?["imageIOProperties"],
            let right = expected.sourceMetadata?["imageIOProperties"]
          {
            // ImageIO's binary plist dictionary order is not canonical.
            let properties = try PropertyListSerialization.propertyList(from: left, format: nil) as? NSDictionary
            let expectedProperties = try PropertyListSerialization.propertyList(from: right, format: nil) as? NSDictionary
            XCTAssertNotNil(properties)
            XCTAssertEqual(properties, expectedProperties)
            expected.sourceMetadata?["imageIOProperties"] = left
          }
        }
        XCTAssertTrue(actual == expected, "\(format.rawValue) imported model differs after identity normalization")
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertNil(doc.fileURL)
        service.revoke(try XCTUnwrap(service.shares.last?.id)); doc.close()
      }
      let bytes = try NativeArchive.encode(model)
      let auto = try await upload(service, bytes: bytes, type: "image/png", format: "automatic")
      XCTAssertEqual(auto.0.statusCode, 201)
      XCTAssertEqual(service.shares.last?.document?.store.document, model)
      let invalid = try await upload(service, bytes: bytes, type: "application/octet-stream", format: "bad")
      XCTAssertEqual(invalid.0.statusCode, 400)
      let unsupported = try await upload(service, bytes: bytes, type: "application/octet-stream")
      XCTAssertEqual(unsupported.0.statusCode, 415)
      let legacy = try await upload(service, bytes: bytes, type: "image/png")
      XCTAssertEqual(legacy.0.statusCode, 422)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testNativeOpeningStatePrivacyPermissionsAndExactIDCancellation() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder); c.documentOpening.reader = PreparedLocalDocument.read }
      let url = try DocumentOpeningTests().fixture(folder, name: "private-name.photato")
      let gate = OpeningGate(); defer { gate.release() }
      c.documentOpening.reader = { url, format in gate.wait(); try Task.checkCancellation(); return try PreparedLocalDocument.read(url, format: format) }
      let id = try c.documentOpening.begin([url], display: false)
      try await DocumentOpeningTests().wait(gate)
      let stateResponse = try await api.request(service, path: "/v1/document-opening")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateResponse.1) as? [String: Any])
      let schema = try XCTUnwrap(AutomationService.documentOpeningCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertFalse(String(decoding: stateResponse.1, as: UTF8.self).contains("private-name"))
      XCTAssertEqual(state["active"] as? Bool, true)
      let denied = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      for payload in [["operationID": UUID().uuidString], ["operationID": "bad"], ["operationID": id.uuidString, "extra": "bad"]] {
        let response = try await api.request(service, path: "/v1/document-opening/cancel", body: payload)
        XCTAssertEqual(response.0.statusCode, payload.count == 1 && payload["operationID"] != "bad" ? 409 : 400)
      }
      let media = try await api.request(service, path: "/v1/document-opening/cancel",
        body: ["operationID": id.uuidString], headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      let importing = try await upload(service, bytes: try NativeArchive.encode(CraftDocument(width: 1, height: 1)),
        type: DocumentIO.Format.native.mediaType)
      XCTAssertEqual(importing.0.statusCode, 409)
      let cancel = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
      XCTAssertEqual(cancel.0.statusCode, 200)
      gate.release(); await c.documentOpening.task?.value
      XCTAssertEqual(c.documents.count, 1)
      XCTAssertTrue(c.documents[0] === original)
      XCTAssertEqual(c.documentOpening.state?.cancellationRequested, true)
      let stale = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
      XCTAssertEqual(stale.0.statusCode, 409)
    }
  }
  @MainActor func testRevokedSelectedUploadCannotPublishAfterWorkerReturns() async throws {
    let gate = OpeningGate(); defer { gate.release() }
    let api = AutomationTests()
    try await api.withService(documentDecoder: { data, native, name in
      gate.wait(); return try DocumentIO.decodeUpload(data, native: native, name: name)
    }) { service, original in
      service.setDocumentTransfersEnabled(true)
      let bytes = try NativeArchive.encode(CraftDocument(width: 4, height: 3))
      let task = Task { try await self.upload(service, bytes: bytes, type: "application/octet-stream", format: "automatic") }
      try await DocumentOpeningTests().wait(gate)
      service.setDocumentTransfersEnabled(false)
      gate.release()
      let response = try await task.value
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertEqual(service.shares.count, 0)
      XCTAssertEqual(service.controller.documents.count, 1)
      XCTAssertTrue(service.controller.documents[0] === original)
    }
  }
  @MainActor func testFinishedCloseDuringUploadStillPreventsLatePublication() async throws {
    let gate = OpeningGate(); defer { gate.release() }
    let api = AutomationTests()
    try await api.withService(documentDecoder: { data, native, name in
      gate.wait(); return try DocumentIO.decodeUpload(data, native: native, name: name)
    }) { service, original in
      service.setDocumentTransfersEnabled(true)
      let bytes = try NativeArchive.encode(CraftDocument(width: 4, height: 3))
      let task = Task { try await self.upload(service, bytes: bytes, type: "application/octet-stream", format: "automatic") }
      try await DocumentOpeningTests().wait(gate)
      let closing = service.controller.documentClosing
      let id = try closing.prepare([original], scope: .all, mode: .discard)
      closing.start(id); await closing.task?.value
      XCTAssertFalse(closing.isActive)
      gate.release()
      let response = try await task.value
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertTrue(service.controller.documents.isEmpty)
      XCTAssertEqual(service.shares.count, 0)
    }
  }

}
