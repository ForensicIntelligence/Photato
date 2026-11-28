import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TIFFLargeRGBWorkflowTests: XCTestCase {
  @MainActor func testLargeRGBTIFFSharesEditableImportWithBothResourcePaths() async throws {
    let location = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/large-rgb-tiff/rgba16-lzw-strips.tif")
    let data = try Data(contentsOf: location)
    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.width, 9000)
      XCTAssertEqual(document.height, 8000)
      XCTAssertEqual(document.depth, .u16)
      XCTAssertNil(document.modeDescriptor)
      XCTAssertTrue(document.profileIsUntagged == true)
      guard case .raster(let pixels) = try XCTUnwrap(document.layers.first).content else {
        return XCTFail("Expected an editable RGB raster.")
      }
      let p = pixels.pixel(x: 8999, y: 0)
      let values = [p.r, p.g, p.b, p.a].map { UInt16(($0 * 65535).rounded()) }
      XCTAssertEqual(values, [777, 12345, 65535, 0])
    }
    try check(AdobeActionAssets.decode(data))
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let url = try XCTUnwrap(URL(string: try XCTUnwrap(service.endpoint) + "/v1/documents/import"))
      var request = URLRequest(url: url, timeoutInterval: 180)
      request.httpMethod = "POST"
      request.httpBody = data
      request.setValue("Bearer \(try XCTUnwrap(service.token))", forHTTPHeaderField: "Authorization")
      request.setValue("image/tiff", forHTTPHeaderField: "Content-Type")
      request.setValue("tiff", forHTTPHeaderField: "X-Photato-Open-Format")
      let (bytes, response) = try await URLSession.shared.data(for: request)
      XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201, String(decoding: bytes, as: UTF8.self))
      try check(XCTUnwrap(service.shares.last?.document?.store.document))
    }
  }
}
