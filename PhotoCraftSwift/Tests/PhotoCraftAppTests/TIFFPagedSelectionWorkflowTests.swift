import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFPagedSelectionWorkflowTests: XCTestCase {
  @MainActor func testLargeLayeredTIFFDownloadAndActionInputKeepSavedSelection() async throws {
    let width = 7200, height = 5400
    var source = try CraftDocument(width: width, height: height, depth: .u8)
    var selection = try Surface(width: width, height: height, depth: .u8, fill: .black)
    selection.setPixel(x: 18, y: 11, Pixel(0.5, 0.5, 0.5))
    source.alphaChannels = [AlphaChannel(name: "Subject", pixels: selection)]
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .bigEndian,
      tiffLayers: true, tiffTransparency: true)
    let header = String(decoding: try JSONSerialization.data(withJSONObject: DocumentEncodingOptions.json(options)), as: UTF8.self)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      shared.store.session = EditorSession(document: source)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let reply = try await helper.request(service, path: "/v1/documents/\(id)/file.tiff",
        headers: ["X-Photato-Export-Options": header], timeout: 180)
      XCTAssertEqual(reply.0.statusCode, 200, String(decoding: reply.1, as: UTF8.self))
      let loaded = try AdobeActionAssets.decode(reply.1)
      XCTAssertEqual(loaded.alphaChannels?.first?.name, "Subject")
      XCTAssertEqual(loaded.alphaChannels?.first?.pixels, selection)
      XCTAssertEqual(shared.store.document.alphaChannels?.first?.pixels, selection)
    }
  }
}
