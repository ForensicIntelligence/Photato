import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFBigOutputWorkflowTests: XCTestCase {
  @MainActor func testBigTIFFNativeControlsAndHTTPDownloadAndSave() async throws {
    let accessory = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff)
    XCTAssertFalse(accessory.tiffBigTIFF.isHidden)
    XCTAssertEqual(accessory.tiffBigTIFF.state, .off)
    XCTAssertNil(accessory.encodingOptions.tiffBigTIFF)
    accessory.tiffBigTIFF.performClick(nil)
    XCTAssertEqual(accessory.encodingOptions.tiffBigTIFF, true)
    accessory.formats.selectItem(withTitle: DocumentIO.Format.png.title)
    accessory.updateFormat()
    XCTAssertTrue(accessory.tiffBigTIFF.isHidden)
    XCTAssertNil(accessory.encodingOptions.tiffBigTIFF)
    accessory.formats.selectItem(withTitle: DocumentIO.Format.tiff.title)
    accessory.updateFormat()
    XCTAssertEqual(accessory.encodingOptions.tiffBigTIFF, true)
    accessory.tiffBigTIFF.performClick(nil)
    XCTAssertEqual(accessory.encodingOptions.tiffBigTIFF, false)
    let restored = DocumentCopyAccessory(panel: NSSavePanel(), initial: .tiff,
      initialOptions: [.tiff: .init(tiffBigTIFF: true)])
    XCTAssertEqual(restored.encodingOptions.tiffBigTIFF, true)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    var model = try CraftDocument(width: 27, height: 19, depth: .u8)
    model.layers[0].content = .raster(try Surface(width: 27, height: 19, depth: .u8, fill: .white))
    let options = RasterEncodingOptions(tiffCompression: .lzw, tiffImagePyramid: true, tiffBigTIFF: true)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: model)
      service.setDocumentTransfersEnabled(true)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let route = "/v1/documents/\(id)/file.tiff"
      let download = try await helper.request(service, path: route, headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(download.0.statusCode, 200, String(decoding: download.1, as: UTF8.self))
      XCTAssertEqual(download.1, try RasterIO.encoded(model, type: .tiff, options: options))
      let response = try await helper.edit(service, shared, "document.saveAs",
        ["name": "bigtiff-verification", "format": "tiff", "replace": false, "options": fields])
      XCTAssertEqual(response, 200)
      XCTAssertEqual(shared.rememberedEncodingOptions[.tiff], options)
      let saved = try Data(contentsOf: folder.appendingPathComponent("bigtiff-verification.tiff"))
      XCTAssertEqual(saved.prefix(4), Data([77, 77, 0, 43]))
      let bad = try await helper.request(service, path: route,
        headers: ["X-Photato-Export-Options": #"{"tiffBigTIFF":"true"}"#])
      XCTAssertEqual(bad.0.statusCode, 400)
    }
  }
}
