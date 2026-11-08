import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class DocumentModeWorkflowTests: XCTestCase {
  @MainActor func testNative46HTTPNegotiationPreservesModePlanesAndEditingHistory() async throws {
    let storage = try XCTUnwrap(DocumentModeAPI.capabilities["storage"] as? [String: Any])
    XCTAssertEqual(storage["maximumPixels"] as? Int, 90_000_000_000)
    XCTAssertEqual(storage["sampleBlockSize"] as? Int, 4096)
    XCTAssertEqual(storage["rawSampleBits"] as? Bool, true)

    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); service.setDocumentTransfersEnabled(true)
      try document.store.executeEditorCommand(.documentMode(.init(mode: .cmyk, depth: .u16)))
      let id = try XCTUnwrap(document.store.document.activeLayerID)
      var channel = try document.store.document.modeChannel(layerID: id, component: 3)
      channel.setPixel(x: 1, y: 1, Pixel(0.75, 0.75, 0.75))
      try document.store.executeEditorCommand(.modeChannel(.init(layerID: id, component: 3, pixels: channel)))
      let before = document.store.document, share = try XCTUnwrap(service.shares.first)
      for version in [nil, "45"] as [String?] {
        let rejected = try await files.request(service, path: "/v1/documents/\(share.id)/file.photato",
          headers: version.map { ["X-Photato-Archive-Version": $0] } ?? [:])
        XCTAssertEqual(rejected.0.statusCode, 422)
      }
      let saved = try await files.request(service, path: "/v1/documents/\(share.id)/file.photato",
        headers: ["X-Photato-Archive-Version": "46"])
      XCTAssertEqual(saved.0.statusCode, 200, String(decoding: saved.1, as: UTF8.self))
      let read = try NativeArchive.decode(saved.1)
      XCTAssertEqual(read, before)
      XCTAssertEqual(read.layers[0].nativeMode?.value(component: 3, index: 5), PixelDepth.u16.quantize(0.75))
      let imported = try await files.request(service, path: "/v1/documents/import", data: saved.1,
        type: "application/vnd.photato.document")
      XCTAssertEqual(imported.0.statusCode, 201)
      let reopened = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== document })
      XCTAssertEqual(reopened.store.document, before)
      reopened.updateChangeCount(.changeCleared); reopened.close()
      let status = try await helper.edit(service, document, "layer.rename", ["layerID": id.uuidString, "name": "Retained inks"])
      XCTAssertEqual(status, 200)
      XCTAssertEqual(document.store.document.layers[0].nativeMode, before.layers[0].nativeMode)
      let undone = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200)
      XCTAssertEqual(document.store.document, before)
      let formats = try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"] as? [String: Any])
      XCTAssertEqual(formats["readVersions"] as? [Int], Array(1...89))
      XCTAssertEqual(formats["documentModeVersion"] as? Int, 46)
      let psd = try DocumentIO.encode(before, format: .psd)
      XCTAssertEqual(try PSDCodec.read(psd).layers[0].nativeMode, before.layers[0].nativeMode)
      let psdDownload = try await files.request(service, path: "/v1/documents/\(share.id)/file.psd")
      XCTAssertEqual(psdDownload.0.statusCode, 200)
      XCTAssertEqual(try PSDCodec.read(psdDownload.1).layers[0].nativeMode, before.layers[0].nativeMode)
      let tiff = try DocumentIO.encode(before, format: .tiff)
      XCTAssertEqual(try RasterIO.read(tiff).layers[0].nativeMode, before.layers[0].nativeMode)
      let tiffDownload = try await files.request(service, path: "/v1/documents/\(share.id)/file.tiff")
      XCTAssertEqual(tiffDownload.0.statusCode, 200)
      XCTAssertEqual(try RasterIO.read(tiffDownload.1).layers[0].nativeMode, before.layers[0].nativeMode)
      XCTAssertFalse(try DocumentIO.encode(before, format: .png).isEmpty)
    }
  }
}
