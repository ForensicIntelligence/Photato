import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RestrictedFormatWorkflowTests: XCTestCase {
  func fixtures() throws -> [CraftDocument] {
    let indexed = try IndexedRaster(width: 9, height: 2, palette: [.init(250,0,10),.init(250,0,10),.init(0,255,0)],
      indices: Data((0..<18).map { UInt8($0 % 3) }), transparentIndex: 2)
    let bitmap = try BitmapRaster(width: 9, height: 2, bits: Data([0x80,0x80,0x40,0]))
    return try [RestrictedModeRaster.indexed(indexed), .bitmap(bitmap)].map {
      try CraftDocument(width: 9, height: 2, name: $0.mode.rawValue).replacingRestrictedMode($0)
    }
  }
  @MainActor func testHTTPNative47AndEveryLosslessFormatPreserveRestrictedSamples() async throws {
    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    for source in try fixtures() {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: source)
        try service.share(document); service.setDocumentTransfersEnabled(true)
        let share = try XCTUnwrap(service.shares.first), before = document.store.document
        let route = "/v1/documents/\(share.id)/file.photato"
        for version in [nil, "46"] as [String?] {
          let response = try await files.request(service, path: route,
            headers: version.map { ["X-Photato-Archive-Version": $0] } ?? [:])
          XCTAssertEqual(response.0.statusCode, 422)
          XCTAssertTrue(String(decoding: response.1, as: UTF8.self).contains("47"))
        }
        let native = try await files.request(service, path: route, headers: ["X-Photato-Archive-Version": "47"])
        XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), before)
        for format in [DocumentIO.Format.psd, .psb, .png, .tiff] {
          let path = "/v1/documents/\(share.id)/file.\(format.rawValue)"
          let stale = try await files.request(service, path: path, headers: ["X-Photato-Revision": "stale"])
          XCTAssertEqual(stale.0.statusCode, 409)
          let response = try await files.request(service, path: path)
          XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1, as: UTF8.self))
          let read = try RasterIO.read(response.1)
          XCTAssertEqual(read.restrictedMode, before.restrictedMode, format.rawValue)
          XCTAssertEqual(try RasterIO.read(DocumentIO.encode(before, format: format)).restrictedMode, read.restrictedMode)
          let uploaded = try await files.request(service, path: "/v1/documents/import", data: response.1, type: format.mediaType)
          XCTAssertEqual(uploaded.0.statusCode, 201)
          let importResponse = try XCTUnwrap(JSONSerialization.jsonObject(with: uploaded.1) as? [String: Any])
          let importedID = try XCTUnwrap((importResponse["id"] as? String).flatMap(UUID.init(uuidString:)))
          let reopened = try XCTUnwrap(service.shares.first { $0.id == importedID }?.document)
          XCTAssertEqual(reopened.store.document.restrictedMode, before.restrictedMode)
          reopened.updateChangeCount(.changeCleared); reopened.close()
        }
        XCTAssertEqual(document.store.document, before); XCTAssertTrue(document.store.session.undoStack.isEmpty)
        let caps = try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"] as? [String: Any])
        XCTAssertEqual(caps["readVersions"] as? [Int], Array(1...85)); XCTAssertEqual(caps["restrictedModeVersion"] as? Int, 47)
      }
    }
  }
  @MainActor func testNativeSaveAccessoryAndPersistenceKeepActualMode() async throws {
    for source in try fixtures() {
      let (controller, document, folder) = try DocumentEncodingOptionsTests().fixture()
      defer { document.updateChangeCount(.changeCleared); document.close(); _ = controller }
      document.store.session = EditorSession(document: source)
      XCTAssertFalse(document.saveFormats.contains(.jpeg))
      let panel = NSSavePanel(); XCTAssertTrue(document.prepareSavePanel(panel))
      let accessory = try XCTUnwrap(document.saveAccessory)
      accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: .tiff))); accessory.updateFormat()
      XCTAssertFalse(accessory.tiffLayers.isEnabled); XCTAssertEqual(accessory.tiffLayers.state, .off)
      XCTAssertEqual(accessory.encodingOptions.tiffLayers, false)
      XCTAssertFalse(accessory.tiffLayerCompression.isEnabled)
      accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: .psd))); accessory.updateFormat()
      XCTAssertTrue(accessory.psdLayerRow.isHidden)
      XCTAssertEqual(accessory.psdCompositeCompression.item(at: 4)?.isEnabled, source.colorMode != .bitmap)
      for format in [DocumentIO.Format.psd, .psb, .png, .tiff, .native] {
        let url = folder.appendingPathComponent("\(source.name).\(format.rawValue)")
        try await DocumentSaveWorkflowTests().save(document, to: url, format: format)
        XCTAssertEqual(try DocumentIO.read(url).restrictedMode, source.restrictedMode)
        XCTAssertEqual(document.fileURL, url); XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(document.store.document, source)
      }
      XCTAssertNotNil(DocumentIO.persistenceIssue(source, format: .tiff, options: .init(tiffLayers: true)))
      XCTAssertNotNil(DocumentIO.persistenceIssue(source, format: .jpeg))
    }
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw CraftError.invalid("Expected hosted output") }
  }
  @MainActor func testBothExistingActionJobRoutesPreserveRestrictedFileSamples() async throws {
    let helper = AutomationEncodingOptionsTests()
    for source in try fixtures() { for format in [DocumentIO.Format.psd, .png, .tiff] {
      let input = try DocumentIO.encode(source, format: format)
      try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(data: input)) { service, shared in
        service.setResourceJobsEnabled(true); let before = shared.store.document
        var body = helper.body(outputs: [helper.output("image/png"), helper.output("image/tiff"), helper.output("image/vnd.adobe.photoshop")])
        body["options"] = ["actions": [["source": ["content": "[{\"_obj\":\"selectAllLayers\",\"_target\":[{\"_ref\":\"layer\",\"_enum\":\"ordinal\",\"_value\":\"targetEnum\"}]}]", "contentType": "application/json"]]]]
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let outputs = try await helper.outputs(service, route: route, payload: body)
          XCTAssertEqual(outputs.count, 3)
          for output in outputs { XCTAssertEqual(try RasterIO.read(output).restrictedMode, source.restrictedMode, "\(route) \(format)") }
        }
        XCTAssertEqual(shared.store.document, before)
      }
    } }
  }
}
