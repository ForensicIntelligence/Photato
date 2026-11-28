import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class TIFFJPEGImportWorkflowTests: XCTestCase {
  @MainActor func testJPEGCompressedGrayscaleTIFFSharesDesktopAndBothAPIDecoders() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-jpeg/gray-tile.tif")
    let bytes = try Data(contentsOf: fixture)
    let opened = try DocumentIO.read(fixture)
    let expected = try XCTUnwrap(opened.layers.first?.nativeMode)

    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.colorMode, .grayscale)
      XCTAssertEqual(document.depth, .u8)
      XCTAssertEqual(document.resolution, 225)
      XCTAssertEqual(document.width, 179)
      XCTAssertEqual(document.height, 129)
      let actual = try XCTUnwrap(document.layers.first?.nativeMode)
      for plane in 0..<2 {
        let indices = 0..<(179 * 129)
        XCTAssertEqual(indices.map { actual.rawWord(component: plane, index: $0) },
          indices.map { expected.rawWord(component: plane, index: $0) })
      }
    }

    try check(AdobeActionAssets.decode(bytes))
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      let reply = try await AutomationOpeningTests().upload(service, bytes: bytes, type: "image/tiff", format: "tiff")
      XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
      try check(XCTUnwrap(service.shares.last?.document?.store.document))
    }
  }
}
