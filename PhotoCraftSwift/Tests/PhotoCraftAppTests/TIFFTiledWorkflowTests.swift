import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class TIFFTiledWorkflowTests: XCTestCase {
  @MainActor func testRectangularTIFFTilesKeepNativeCMYKThroughBothAPIInputs() async throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/tiff-tiled-components")
    let location = fixtures.appendingPathComponent("planar-cmyk16-lzw-tiled.tiff")
    let authoringInput = try Data(contentsOf: location)
    let expected = try DocumentIO.read(location)
    XCTAssertEqual(expected.colorMode, .cmyk)
    XCTAssertEqual(expected.resolution, 225)
    let local = try XCTUnwrap(expected.layers.first?.nativeMode)

    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.colorMode, .cmyk)
      XCTAssertEqual(document.depth, .u16)
      XCTAssertEqual(document.width, 259)
      XCTAssertEqual(document.height, 137)
      XCTAssertEqual(document.resolution, 225)
      let raster = try XCTUnwrap(document.layers.first?.nativeMode)
      for channel in 0..<5 {
        let indices = 0..<(259 * 137)
        XCTAssertEqual(indices.map { raster.rawWord(component: channel, index: $0) },
          indices.map { local.rawWord(component: channel, index: $0) })
      }
    }

    try check(AdobeActionAssets.decode(authoringInput))
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for document in service.controller.documents where document !== original { document.close() } }
      service.setDocumentTransfersEnabled(true)
      let reply = try await AutomationOpeningTests().upload(service, bytes: authoringInput,
        type: "image/tiff", format: "tiff")
      XCTAssertEqual(reply.0.statusCode, 201, String(decoding: reply.1, as: UTF8.self))
      try check(XCTUnwrap(service.shares.last?.document?.store.document))
    }
  }
}
