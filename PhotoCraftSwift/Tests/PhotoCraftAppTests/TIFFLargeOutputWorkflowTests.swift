import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFLargeOutputWorkflowTests: XCTestCase {
  @MainActor func testLargeTIFFDownloadAndSaveAsKeepEditableGrayAndAlpha() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-large-components/gray8-9mp-associated-planar.tif")
    let source = try RasterIO.read(fixture)
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .bigEndian,
      tiffLayers: false, tiffEmbedProfile: false)
    let fields = DocumentEncodingOptions.json(options)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: source)
      service.setDocumentTransfersEnabled(true)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let reply = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header], timeout: 60)
      XCTAssertEqual(reply.0.statusCode, 200, String(decoding: reply.1, as: UTF8.self))
      let saved = try await helper.edit(service, document, "document.saveAs",
        ["name": "large-gray", "format": "tiff", "replace": false, "options": fields], timeout: 60)
      XCTAssertEqual(saved, 200)
      let file = folder.appendingPathComponent("large-gray.tiff")
      XCTAssertEqual(try Data(contentsOf: file), reply.1)
      let reopened = try RasterIO.read(file)
      XCTAssertEqual(reopened.layers.first?.nativeMode, source.layers.first?.nativeMode)
      XCTAssertNil(reopened.sourceICC)
    }
  }
}
