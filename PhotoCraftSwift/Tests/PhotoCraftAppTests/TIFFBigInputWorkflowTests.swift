import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class TIFFBigInputWorkflowTests: XCTestCase {
  @MainActor func testBigTIFFKeepsNumericGrayscaleAcrossOpenAndBothAPIInputs() async throws {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/bigtiff/gray8-stripped-le.tif")
    let bytes = try Data(contentsOf: source)
    let local = try DocumentIO.read(source)
    let control = try XCTUnwrap(local.layers.first?.nativeMode)
    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.colorMode, .grayscale)
      XCTAssertEqual(document.depth, .u8)
      XCTAssertEqual(document.width, 179)
      XCTAssertEqual(document.height, 129)
      XCTAssertEqual(document.resolution, 225)
      let imported = try XCTUnwrap(document.layers.first?.nativeMode)
      for channel in 0..<2 {
        let range = 0..<(179 * 129)
        XCTAssertEqual(range.map { imported.rawWord(component: channel, index: $0) },
          range.map { control.rawWord(component: channel, index: $0) })
      }
    }
    try check(AdobeActionAssets.decode(bytes))
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      let upload = try await AutomationOpeningTests().upload(service, bytes: bytes,
        type: "image/tiff", format: "tiff")
      XCTAssertEqual(upload.0.statusCode, 201, String(decoding: upload.1, as: UTF8.self))
      try check(XCTUnwrap(service.shares.last?.document?.store.document))
    }
  }
}
