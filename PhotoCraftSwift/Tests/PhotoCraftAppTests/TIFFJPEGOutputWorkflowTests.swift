import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFJPEGOutputWorkflowTests: XCTestCase {
  @MainActor func testJPEGSaveControlsAndAuthenticatedDownloadsShareCodec() async throws {
    let accessory = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff,
      initialOptions: [.tiff: .init(tiffCompression: .jpeg, tiffJPEGQuality: 8)])
    XCTAssertEqual(accessory.tiffCompression.titleOfSelectedItem, "JPEG")
    XCTAssertEqual(accessory.encodingOptions.tiffJPEGQuality, 8)
    XCTAssertFalse(try XCTUnwrap(accessory.tiffJPEGQuality.superview).isHidden)
    accessory.tiffJPEGQuality.selectItem(withTitle: "10")
    XCTAssertEqual(accessory.encodingOptions.tiffJPEGQuality, 10)
    accessory.tiffCompression.selectItem(withTitle: "LZW")
    accessory.updateTIFFCompression()
    XCTAssertNil(accessory.encodingOptions.tiffJPEGQuality)
    XCTAssertTrue(try XCTUnwrap(accessory.tiffJPEGQuality.superview).isHidden)
    let deep = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff, depth: .u16)
    XCTAssertFalse(try XCTUnwrap(deep.tiffCompression.item(withTitle: "JPEG")).isEnabled)
    let wide = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff, width: 30_001)
    XCTAssertFalse(try XCTUnwrap(wide.tiffCompression.item(withTitle: "JPEG")).isEnabled)

    var model = try CraftDocument(width: 113, height: 83, depth: .u8)
    model.layers[0].content = .raster(try Surface(width: 113, height: 83, depth: .u8, fill: .white))
    let options = RasterEncodingOptions(tiffCompression: .jpeg, tiffImagePyramid: true, tiffJPEGQuality: 8)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: model)
      service.setDocumentTransfersEnabled(true)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let route = "/v1/documents/\(id)/file.tiff"
      let reply = try await helper.request(service, path: route, headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(reply.0.statusCode, 200, String(decoding: reply.1, as: UTF8.self))
      XCTAssertEqual(reply.1, try RasterIO.encoded(model, type: .tiff, options: options))
      let invalid = try await helper.request(service, path: route, headers: [
        "X-Photato-Export-Options": #"{"tiffCompression":"zip","tiffJPEGQuality":8}"#,
      ])
      XCTAssertEqual(invalid.0.statusCode, 400)

      let result = try await helper.edit(service, shared, "document.saveAs",
        ["name": "compressed", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(result, 200)
      XCTAssertEqual(shared.rememberedEncodingOptions[.tiff], options)
      var layered = options; layered.tiffLayers = true
      let saved = try Data(contentsOf: folder.appendingPathComponent("compressed.tiff"))
      XCTAssertEqual(saved, try RasterIO.encoded(model, type: .tiff, options: layered))
    }
  }
}
