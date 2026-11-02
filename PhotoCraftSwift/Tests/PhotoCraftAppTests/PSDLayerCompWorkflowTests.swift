import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PSDLayerCompWorkflowTests: XCTestCase {
  func source() throws -> CraftDocument {
    var d = try CraftDocument(width: 6, height: 4)
    d.layers[0].content = .raster(try Surface(width: 6, height: 4, fill: Pixel(1, 0, 0)))
    var top = Layer(name: "Blue", content: .raster(try Surface(width: 2, height: 2, fill: Pixel(0, 0, 1)))); top.x = 1; d.layers.append(top)
    let options = LayerCompOptions(visibility: true, position: true, appearance: false)
    try Command.layerComp(.capture(id: UUID(), name: "Left", comment: "", options: options)).apply(to: &d)
    d.layers[1].x = 4
    try Command.layerComp(.capture(id: UUID(), name: "Right", comment: "", options: options)).apply(to: &d)
    return d
  }
  @MainActor func testHTTPPSBImportNativeAPIApplyHistoryAndPSDDownloadsShareTheSerializer() async throws {
    let helper = AutomationTests(), files = DocumentIOWorkflowTests(), input = try PSDCodec.writeRasterLayers(source(), format: .psb)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { for case let doc as CraftNSDocument in service.controller.documents { doc.updateChangeCount(.changeCleared); doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let upload = try await files.request(service, path: "/v1/documents/import", data: input, type: "application/x-photoshop")
      XCTAssertEqual(upload.0.statusCode, 201, String(decoding: upload.1.prefix(500), as: UTF8.self))
      let state = try JSONSerialization.jsonObject(with: upload.1) as! [String: Any], id = state["id"] as! String
      let document = try XCTUnwrap(service.shares.first(where: { $0.id.uuidString == id })?.document), before = document.store.document
      let native = EditorStore(document: before); defer { native.renderTask?.cancel() }
      let first = before.layerComps!.comps[0].id
      try native.editLayerComp(.apply(first)); await native.geometryTask?.value
      let apply = try await helper.edit(service, document, "layerComps.edit", ["operation": "apply", "id": first.uuidString]); XCTAssertEqual(apply, 200)
      XCTAssertEqual(document.store.document, native.document)
      for format in ["psd", "psb"] {
        let reply = try await files.request(service, path: "/v1/documents/\(id)/file.\(format)")
        XCTAssertEqual(reply.0.statusCode, 200, String(decoding: reply.1.prefix(300), as: UTF8.self))
        XCTAssertEqual(reply.1, try DocumentIO.encode(document.store.document, format: DocumentIO.Format(rawValue: format)!))
        XCTAssertEqual(try PSDCodec.read(reply.1).layerComps?.comps.map(\.name), ["Left", "Right"])
      }
      let count = document.store.session.undoStack.count
      let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".psd"); defer { try? FileManager.default.removeItem(at: copy) }
      try await document.copyDocument(to: copy, format: .psd)
      XCTAssertEqual(try Data(contentsOf: copy), try DocumentIO.encode(document.store.document, format: .psd)); XCTAssertEqual(document.store.session.undoStack.count, count)
      let undo = try await helper.edit(service, document, "history.undo", [:]); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, before)
      let clear = try await helper.edit(service, document, "layerComps.edit", ["operation": "clear"]); XCTAssertEqual(clear, 200)
      XCTAssertEqual(LayerCompsAPI.state(document.store.document)["sourceCompsCleared"] as? Bool, true)
      let old = try await files.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "81"]); XCTAssertEqual(old.0.statusCode, 422)
      let clearedFile = try await files.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "82"]); XCTAssertEqual(clearedFile.0.statusCode, 200)
      let cleared = try await files.request(service, path: "/v1/documents/\(id)/file.psd"); XCTAssertEqual(cleared.0.statusCode, 200); XCTAssertNil(try PSDCodec.read(cleared.1).layerComps)
    }
  }
  @MainActor func testNoPropertyCaptureUsesNative82NegotiationAndUnsupportedExportKeepsSourceHistory() async throws {
    let helper = AutomationTests(), files = DocumentIOWorkflowTests(), original = try source()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: original); try service.share(document); service.setDocumentTransfersEnabled(true)
      let id = service.shares.first!.id.uuidString
      let capture = try await helper.edit(service, document, "layerComps.edit", ["operation": "capture", "name": "No properties", "visibility": false, "position": false, "appearance": false, "smartObjects": false]); XCTAssertEqual(capture, 200)
      XCTAssertEqual(document.store.document.minimumArchiveVersion, 82)
      let old = try await files.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "81"]); XCTAssertEqual(old.0.statusCode, 422)
      let file = try await files.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "82"]); XCTAssertEqual(file.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(file.1), document.store.document)
      var changed = document.store.document; changed.layerComps?.comps[0].options.smartObjects = true
      document.store.session = EditorSession(document: changed)
      let fail = try await files.request(service, path: "/v1/documents/\(id)/file.psd"); XCTAssertEqual(fail.0.statusCode, 422)
      XCTAssertEqual(document.store.document, changed); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(LayerCompsAPI.capabilities["nativeArchiveVersion"] as? Int, 82)
      XCTAssertEqual(Set(AutomationCommand.definitions.map(\.name)).count, AutomationTests.expectedCommandCount)
    }
  }
  func testPublishedAdobeOutputEncodingRetainsSupportedCompsThroughTheSharedSwiftSerializer() throws {
    let d = try source()
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: [
      "image": ["width": 6, "height": 4, "mode": "rgb", "depth": 8], "edits": ["layers": []],
      "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]
    ]), createComposite: true)
    let output = try AdobeActionAssets.encode(request, document: d)
    XCTAssertEqual(output.count, 1); XCTAssertEqual(output[0].data, try PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(try PSDCodec.read(output[0].data).layerComps?.comps.map(\.name), ["Left", "Right"])
  }
}
