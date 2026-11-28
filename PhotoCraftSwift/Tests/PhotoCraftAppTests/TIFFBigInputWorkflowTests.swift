import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers
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

  @MainActor func testOpaqueRGBBigTIFFKeepsPixelsAcrossNativeAndBothAPIInputs() async throws {
    var pixels = try Surface(width: 81, height: 67, fill: Pixel(0.2, 0.4, 0.6))
    pixels.setPixel(x: 80, y: 66, Pixel(1, 0, 0.4))
    var source = try CraftDocument(width: pixels.width, height: pixels.height, name: "Opaque RGB TIFF")
    source.layers = [Layer(name: "Pixels", content: .raster(pixels))]
    source.activeLayerID = source.layers[0].id
    source.profileIsUntagged = true
    let expected = try pixels.rgbaData(depth: .u8)
    let bytes = try RasterIO.encoded(source, type: .tiff, options: .init(tiffCompression: .zip,
      tiffTransparency: false, tiffBigTIFF: true))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: url) }
    try bytes.write(to: url)
    func check(_ document: CraftDocument) throws {
      XCTAssertEqual(document.colorMode, .rgb)
      XCTAssertEqual(document.depth, .u8)
      XCTAssertEqual(document.width, 81)
      XCTAssertEqual(document.height, 67)
      XCTAssertEqual(document.profileIsUntagged, true)
      guard case .raster(let imported) = try XCTUnwrap(document.layers.first).content else {
        return XCTFail("Expected an editable RGB layer.")
      }
      XCTAssertEqual(try imported.rgbaData(depth: .u8), expected)
    }
    try check(DocumentIO.read(url))
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
