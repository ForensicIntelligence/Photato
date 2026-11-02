import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PSDGlobalLightWorkflowTests: XCTestCase {
  func source() throws -> CraftDocument {
    var d = try CraftDocument(width: 12, height: 12), pixels = try Surface(width: 12, height: 12)
    for y in 4..<8 { for x in 4..<8 { pixels.setPixel(x: x, y: y, Pixel(0.5, 0.6, 0.8)) } }
    d.layers[0].content = .raster(pixels)
    var effect = LayerEffect(.dropShadow); effect.size = 0; effect.distance = 3; effect.useGlobalLight = true; effect.angle = 25.5
    d.layers[0].style = LayerStyle(effects: [effect]); return d
  }
  @MainActor func testNativeGlobalLightDialogAndAPIHistoryMatchAcrossPhotoshopFileDownloads() async throws {
    let original = try source(), helper = AutomationTests(), native = EditorStore(document: original)
    defer { native.renderTask?.cancel() }
    native.beginGlobalLight(); LayerStyleSheet(store: native).sharedLight(\.angle).wrappedValue = 45; native.cancelLayerStyle(); XCTAssertEqual(native.document, original)
    native.beginGlobalLight(); LayerStyleSheet(store: native).sharedLight(\.angle).wrappedValue = 45; LayerStyleSheet(store: native).sharedLight(\.altitude).wrappedValue = 60
    native.commitLayerStyle(); await native.geometryTask?.value; XCTAssertEqual(native.document.globalLight, GlobalLight(angle: 45, altitude: 60))
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: original); try service.share(document); service.setDocumentTransfersEnabled(true)
      let changed = try await helper.edit(service, document, "document.globalLight", ["angle": 45, "altitude": 60]); XCTAssertEqual(changed, 200); XCTAssertEqual(document.store.document, native.document)
      let id = service.shares.first!.id
      for format in ["psd", "psb"] {
        let file = try await helper.request(service, path: "/v1/documents/\(id)/file.\(format)"); XCTAssertEqual(file.0.statusCode, 200, String(decoding: file.1.prefix(400), as: UTF8.self))
        XCTAssertEqual(file.1, try DocumentIO.encode(native.document, format: DocumentIO.Format(rawValue: format)!))
        let read = try PSDCodec.read(file.1); XCTAssertEqual(read.globalLight, native.document.globalLight); XCTAssertEqual(read.layers[0].style?.effects[0].useGlobalLight, true); XCTAssertEqual(read.layers[0].style?.effects[0].angle, 25.5)
      }
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      let undo = try await helper.edit(service, document, "history.undo", [:]); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, original)
      let redo = try await helper.edit(service, document, "history.redo", [:]); XCTAssertEqual(redo, 200); XCTAssertEqual(document.store.document, native.document)
      document.store.beginLayerStyle(); let busy = try await helper.edit(service, document, "document.globalLight", ["angle": 70, "altitude": 30]); XCTAssertEqual(busy, 409); document.store.cancelLayerStyle()
    }
  }
  @MainActor func testNativeLegacyOpenAndHTTPImportAdoptLightWithoutRewritingOriginalBytes() async throws {
    var legacy = try source(); legacy.layers[0].style?.lightAngle = 90
    let resources = Data([0x38,0x42,0x49,0x4d,0x04,0x0d,0,0,0,0,0,4,0,0,0,90, 0x38,0x42,0x49,0x4d,0x04,0x19,0,0,0,0,0,4,0,0,0,30])
    legacy.sourceMetadata = ["psdResources": resources]
    let data = try NativeArchive.encode(legacy), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".photato")
    try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
    let native = try DocumentIO.readNative(url); XCTAssertEqual(native.globalLight, GlobalLight(angle: 90, altitude: 30)); XCTAssertEqual(native.layers, legacy.layers); XCTAssertEqual(try Data(contentsOf: url), data)
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { for case let document as CraftNSDocument in service.controller.documents { document.updateChangeCount(.changeCleared); document.close() } }
      service.setDocumentTransfersEnabled(true)
      let reply = try await DocumentIOWorkflowTests().request(service, path: "/v1/documents/import", data: data, type: "application/vnd.photato.document")
      XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1.prefix(400), as: UTF8.self))
      let document = try XCTUnwrap(service.shares.first?.document); XCTAssertEqual(document.store.document.globalLight, native.globalLight)
      XCTAssertEqual(document.store.document.layers, native.layers); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  func testAdobeOutputUsesSharedResourcesAndPrecisionErrorsDoNotMutateSource() throws {
    var d = try source(); d.globalLight = GlobalLight(angle: 60, altitude: 45)
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: ["image": ["width": 12, "height": 12, "mode": "rgb", "depth": 8], "edits": ["layers": []], "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]), createComposite: true)
    let encoded = try AdobeActionAssets.encode(request, document: d); XCTAssertEqual(encoded.count, 1); XCTAssertEqual(encoded[0].data, try PSDCodec.writeRasterLayers(d)); XCTAssertEqual(try PSDCodec.read(encoded[0].data).globalLight, d.globalLight)
    d.globalLight?.angle = 60.25; let before = d; XCTAssertThrowsError(try AdobeActionAssets.encode(request, document: d)); XCTAssertEqual(d, before)
    XCTAssertNotNil(LayerStyle.apiCapabilities["globalLightInterchange"])
  }
}
