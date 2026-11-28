import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFPyramidWorkflowTests: XCTestCase {
  @MainActor func testSaveImagePyramidCheckboxAndDownloadShareEncodingOptions() async throws {
    let panel = NSSavePanel()
    let accessory = DocumentCopyAccessory(panel: panel, initial: .tiff)
    XCTAssertFalse(accessory.tiffImagePyramid.isHidden)
    XCTAssertNil(accessory.encodingOptions.tiffImagePyramid)
    accessory.tiffImagePyramid.performClick(nil)
    XCTAssertEqual(accessory.encodingOptions.tiffImagePyramid, true)
    accessory.formats.selectItem(withTitle: DocumentIO.Format.png.title)
    accessory.updateFormat()
    XCTAssertTrue(accessory.tiffImagePyramid.isHidden)
    XCTAssertNil(accessory.encodingOptions.tiffImagePyramid)
    let restored = DocumentCopyAccessory(panel: panel, initial: .tiff,
      initialOptions: [.tiff: .init(tiffImagePyramid: true)])
    XCTAssertEqual(restored.tiffImagePyramid.state, .on)
    restored.tiffImagePyramid.performClick(nil)
    XCTAssertEqual(restored.encodingOptions.tiffImagePyramid, false)

    let options = RasterEncodingOptions(tiffTransparency: false, tiffImagePyramid: true)
    let encoded = try JSONSerialization.data(withJSONObject: DocumentEncodingOptions.json(options))
    let header = String(decoding: encoded, as: UTF8.self)
    let model = try CraftDocument(width: 17, height: 13, depth: .u8)
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: model)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let reply = try await AutomationTests().request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header])
      XCTAssertEqual(reply.0.statusCode, 200, String(decoding: reply.1, as: UTF8.self))
      XCTAssertEqual(reply.1, try RasterIO.encoded(model, type: .tiff, options: options))
    }
  }
}
