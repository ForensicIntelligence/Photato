import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLargeRGBTests: XCTestCase {
  func testLargePredictedLZWRGBImportPreservesHiddenColorAndEditableRGB() throws {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/large-rgb-tiff/rgba16-lzw-strips.tif")
    let document = try RasterIO.read(path)
    XCTAssertEqual(document.width, 9000)
    XCTAssertEqual(document.height, 8000)
    XCTAssertEqual(document.depth, .u16)
    XCTAssertEqual(document.colorMode, .rgb)
    XCTAssertNil(document.modeDescriptor)
    XCTAssertTrue(document.profileIsUntagged == true)
    let layer = try XCTUnwrap(document.layers.first)
    XCTAssertNil(layer.nativeMode)
    guard case .raster(var raster) = layer.content else { return XCTFail("Expected an editable RGB layer.") }
    let samples: [(Int, Int, [UInt16])] = [(0, 0, [65535, 32768, 123, 32768]),
      (8999, 0, [777, 12345, 65535, 0]), (120, 3200, [40000, 30000, 20000, 65535]),
      (8999, 7999, [456, 23456, 54321, 50123]), (4500, 4000, [0, 0, 0, 0])]
    for (x, y, expected) in samples {
      let p = raster.pixel(x: x, y: y)
      XCTAssertEqual([p.r, p.g, p.b, p.a].map { UInt16(($0 * 65535).rounded()) }, expected)
    }
    raster.setPixel(x: 90, y: 60, Pixel(0.25, 0.5, 0.75, 1))
    let edited = raster.pixel(x: 90, y: 60)
    XCTAssertEqual([edited.r, edited.g, edited.b, edited.a].map { UInt16(($0 * 65535).rounded()) },
      [16384, 32768, 49151, 65535])
  }

  func testForcedPagedRGB32UsesLinearWorkingSpaceForNonlinearICC() throws {
    var rgb = try Surface(width: 2, height: 1, depth: .f32, fill: Pixel(0, 0, 0, 1))
    rgb.setLinearPixel(x: 0, y: 0, Pixel(0.5, 0.25, 0.125, 1))
    let bytes = try RasterIO.encoded(rgb, type: .tiff, outputDepth: .f32)
    let encodedSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let encodedProfile = try XCTUnwrap(encodedSpace.copyICCData() as Data?)
    let file = try TIFFContainer(bytes, metadata: true)
    file.root.fields[34675] = .init(tag: 34675, type: 7, count: encodedProfile.count, data: encodedProfile)
    var control = bytes
    try file.appendDirectories(to: &control, order: file.order)
    let document = try XCTUnwrap(RasterIO.readPagedComponentTIFF(control, name: "Encoded RGB32"))
    XCTAssertEqual(document.sourceICC, encodedProfile)
    let profile = try XCTUnwrap(document.workingICC)
    XCTAssertTrue(try ICCProfile.isLinear(profile))
    guard case .raster(let result) = try XCTUnwrap(document.layers.first).content else {
      return XCTFail("Expected a raster layer.")
    }
    let observed = result.linearPixel(x: 0, y: 0)
    let expected = try XCTUnwrap(CGColor(colorSpace: encodedSpace, components: [0.5, 0.25, 0.125, 1])?
      .converted(to: ColorManagement.space(for: document), intent: .relativeColorimetric, options: nil)?.components)
    XCTAssertEqual(observed.r, Float(expected[0]), accuracy: 0.00001)
    XCTAssertEqual(observed.g, Float(expected[1]), accuracy: 0.00001)
    XCTAssertEqual(observed.b, Float(expected[2]), accuracy: 0.00001)
    XCTAssertEqual(observed.a, 1)
  }
}
