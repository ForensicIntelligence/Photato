import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PcraftWorkflowTests: XCTestCase {
  func fixture(_ bits: String = "u8", rich: Bool = false) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures")
    return try Data(contentsOf: root.appendingPathComponent(rich ? "PcraftProjects/rich-\(bits).pcraft" : "Pcraft/source-\(bits).pcraft"))
  }
  @MainActor func testNativeOpenEditUndoSaveAsRetainsSourceAndExactModel() async throws {
    _ = NSApplication.shared
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for bits in ["u8", "u16", "f32"] {
      let bytes = try fixture(bits), url = folder.appendingPathComponent("original-\(bits).pcraft")
      try bytes.write(to: url)
      XCTAssertEqual(DocumentOpenFormat.detect(bytes), .pcraft)
      XCTAssertEqual(DocumentOpenFormat.detect(url), .pcraft)
      XCTAssertNil(DocumentIO.sourceFormat(url))
      XCTAssertFalse(DocumentIO.isNativeFile(url))
      let prepared = try PreparedLocalDocument.read(url, format: .pcraft)
      XCTAssertNil(prepared.format)
      let doc = prepared.makeDocument(url: url)
      defer { doc.updateChangeCount(.changeCleared); doc.close() }
      XCTAssertNil(doc.fileURL); XCTAssertEqual(doc.importedSourceURL, url)
      let original = doc.store.document
      XCTAssertEqual(original, try DocumentIO.decodeUpload(bytes, native: false, name: "Ignored filename"))
      try doc.store.executeEditorCommand(.renameLayer(original.layers[1].id, "Migrated layer"))
      let edited = doc.store.document
      try doc.store.session.undo(); XCTAssertEqual(doc.store.document, original)
      try doc.store.session.redo(); XCTAssertEqual(doc.store.document, edited)
      let target = folder.appendingPathComponent("saved-\(bits).photato")
      try await DocumentSaveWorkflowTests().save(doc, to: target, format: .native)
      XCTAssertEqual(doc.fileURL, target)
      XCTAssertEqual(try DocumentIO.read(target), edited)
      XCTAssertEqual(try Data(contentsOf: url), bytes)
      XCTAssertThrowsError(try PreparedLocalDocument.read(url, format: .psd))
    }
  }
  @MainActor func testOpenPanelAndCapabilitiesDistinguishSourceImportFromWritableFormats() throws {
    _ = NSApplication.shared
    let panel = NSOpenPanel(); DocumentIO.configureOpenPanel(panel)
    let accessory = DocumentOpenAccessory(panel: panel)
    XCTAssertFalse(panel.canChooseDirectories)
    accessory.formats.selectItem(at: DocumentOpenFormat.allCases.firstIndex(of: .pcraft)!)
    accessory.changed()
    XCTAssertTrue(panel.canChooseDirectories)
    XCTAssertEqual(panel.allowedContentTypes.map(\.preferredFilenameExtension), ["pcraft"])
    XCTAssertNil(DocumentOpenFormat.pcraft.persistenceFormat)
    XCTAssertTrue(DocumentIO.uploadTypes.contains(PcraftImport.mediaType))
    XCTAssertNotNil(AutomationService.documentOpeningCapabilities["pcraft"])
  }
  @MainActor func testHTTPUploadEditDownloadAndRejectedImportAreAtomic() async throws {
    let helper = AutomationTests(), opening = AutomationOpeningTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.updateChangeCount(.changeCleared); doc.close() } }
      let input = try fixture("f32")
      let denied = try await opening.upload(service, bytes: input, type: PcraftImport.mediaType)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let mismatch = try await opening.upload(service, bytes: input, type: "application/octet-stream", format: "psd")
      XCTAssertEqual(mismatch.0.statusCode, 422); XCTAssertTrue(service.shares.isEmpty)
      let accepted = try await opening.upload(service, bytes: input, type: PcraftImport.mediaType, format: "pcraft")
      XCTAssertEqual(accepted.0.statusCode, 201, String(decoding: accepted.1, as: UTF8.self))
      let share = try XCTUnwrap(service.shares.first), doc = try XCTUnwrap(share.document)
      let model = try PcraftImport.read(input)
      XCTAssertEqual(doc.store.document, model); XCTAssertNil(doc.fileURL)
      let desktop = EditorStore(document: model)
      defer { desktop.renderTask?.cancel() }
      let layer = model.layers[1].id
      try desktop.executeEditorCommand(.renameLayer(layer, "API and desktop"))
      let status = try await helper.edit(service, doc, "layer.rename", ["layerID": layer.uuidString, "name": "API and desktop"])
      XCTAssertEqual(status, 200); XCTAssertEqual(doc.store.document, desktop.document)
      let reply = try await helper.request(service, path: "/v1/documents/\(share.id)/file.photato",
        headers: ["X-Photato-Archive-Version": "12"])
      XCTAssertEqual(reply.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decode(reply.1), desktop.document)
      let before = doc.store.document
      let rejected = try await opening.upload(service, bytes: fixture("u8", rich: true), type: PcraftImport.mediaType)
      XCTAssertEqual(rejected.0.statusCode, 422)
      XCTAssertEqual(service.shares.count, 1); XCTAssertEqual(doc.store.document, before)
      try doc.store.session.undo(); XCTAssertEqual(doc.store.document, model)
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
  @MainActor func testPhotatoResourceJobAcceptsSourceWhileAdobeJobRejectsIt() async throws {
    let input = try fixture(), helper = AutomationTests()
    let payload: [String: Any] = [
      "image": ["source": ["url": "https://example.test/source.pcraft"]],
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
        XCTAssertEqual(result["status"] as? String, route.hasPrefix("/v1") ? "succeeded" : "failed", "\(result)")
        if route.hasPrefix("/v1") {
          let output = try XCTUnwrap((result["result"] as? [String: Any])?["outputs"] as? [[String: Any]])
          let destination = try XCTUnwrap(output.first?["destination"] as? [String: Any])
          let assetURL = try XCTUnwrap(URL(string: try XCTUnwrap(destination["url"] as? String)))
          let asset = try await helper.request(service, path: assetURL.path)
          XCTAssertEqual(asset.0.statusCode, 200)
          XCTAssertEqual(asset.1, try DocumentIO.encode(PcraftImport.read(input), format: .psd))
        }
      }
      XCTAssertEqual(original.store.document, before)
      XCTAssertTrue(original.store.session.undoStack.isEmpty)
    }
  }
}
