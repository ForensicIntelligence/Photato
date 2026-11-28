import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLargeComponentTests: XCTestCase {
  private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/tiff-large-components/\(name).tif")
  }

  func testLargeGray16ZIPRetainsExactComponentSamplesThroughFileAndDataImports() throws {
    let url = fixture("gray16-36mp-zip")
    try assertGray16(RasterIO.read(url))
    try assertGray16(RasterIO.read(Data(contentsOf: url)))
  }

  func testLargeGray16LZWReversesTheHorizontalPredictorAcrossStrips() throws {
    try assertGray16(RasterIO.read(fixture("gray16-36mp-lzw-predicted")))
  }

  private func assertGray16(_ document: CraftDocument) throws {
    XCTAssertEqual(document.depth, .u16)
    XCTAssertEqual(document.width, 6000)
    XCTAssertEqual(document.height, 6000)
    let raster = try XCTUnwrap(document.layers.first?.nativeMode)
    XCTAssertEqual(raster.mode, .grayscale)
    XCTAssertTrue(raster.requiresPagedArchive)
    XCTAssertTrue(raster.isOpaque)
    XCTAssertGreaterThan(raster.mappedComponentSampleBytes, 0)
    XCTAssertEqual(raster.residentComponentEditBytes, 0)
    for (x, y, word) in [(0, 0, 4970), (5999, 0, 3727), (23, 3000, 2982), (5999, 5999, 2130), (4, 8, 14911)] {
      let index = y * document.width + x
      XCTAssertEqual(raster.rawWord(component: 0, index: index), UInt32(word))
      XCTAssertEqual(raster.rawWord(component: 1, index: index), 65535)
    }
  }

  func testLargePlanarCMYKPreservesIndependentInkAndOpacity() throws {
    let document = try RasterIO.read(fixture("cmyk16-9mp-zip-planar"))
    XCTAssertEqual(document.colorMode, .cmyk)
    XCTAssertEqual(document.width, 3001)
    XCTAssertEqual(document.height, 2800)
    let raster = try XCTUnwrap(document.layers.first?.nativeMode)
    XCTAssertEqual(raster.depth, .u16)
    XCTAssertTrue(raster.requiresPagedArchive)
    XCTAssertEqual(raster.residentComponentEditBytes, 0)
    let samples: [(Int, Int, [UInt32])] = [
      (0, 0, [666, 18333, 10922, 4115, 65535]),
      (3000, 0, [500, 13750, 8192, 3086, 65535]),
      (23, 1400, [400, 11000, 6553, 2469, 65535]),
      (3000, 2799, [285, 7857, 4681, 1763, 65535]),
      (4, 8, [2000, 55000, 32768, 12345, 65535]),
    ]
    for (x, y, words) in samples {
      XCTAssertEqual((0..<5).map { raster.rawWord(component: $0, index: y * document.width + x) }, words)
    }
  }

  func testLargeWhiteIsZeroGrayscaleReorientsAndRecoversAssociatedAlpha() throws {
    let document = try RasterIO.read(fixture("gray8-9mp-associated-planar"))
    XCTAssertEqual(document.colorMode, .grayscale)
    XCTAssertEqual(document.width, 2800)
    XCTAssertEqual(document.height, 3001)
    let raster = try XCTUnwrap(document.layers.first?.nativeMode)
    XCTAssertEqual(raster.depth, .u8)
    XCTAssertTrue(raster.requiresPagedArchive)
    XCTAssertEqual(raster.residentComponentEditBytes, 0)
    let samples = [(2799, 0, 124, 64), (2799, 3000, 0, 0), (1399, 23, 83, 110),
      (0, 3000, 128, 22), (4, 8, 80, 128)]
    for (x, y, gray, alpha) in samples {
      let index = y * document.width + x
      XCTAssertEqual(raster.rawWord(component: 0, index: index), UInt32(gray))
      XCTAssertEqual(raster.rawWord(component: 1, index: index), UInt32(alpha))
    }
  }

  func testPagedComponentImportMatchesDenseForEverySmallAssociatedAlphaSample() throws {
    let data = try Data(contentsOf: fixture("gray8-small-associated-planar"))
    let dense = try RasterIO.read(data)
    let paged = try XCTUnwrap(TIFFModeStorage.read(data, name: "Gray", forcePaged: true))
    let original = try XCTUnwrap(dense.layers.first?.nativeMode)
    let compared = try XCTUnwrap(paged.layers.first?.nativeMode)
    XCTAssertEqual(try original.planes, try compared.planes)
    guard case .raster(let originalPreview) = try XCTUnwrap(dense.layers.first).content,
      case .raster(let pagedPreview) = try XCTUnwrap(paged.layers.first).content else {
      return XCTFail("Expected editable raster previews.")
    }
    for y in 0..<dense.height { for x in 0..<dense.width {
      XCTAssertEqual(originalPreview.pixel(x: x, y: y), pagedPreview.pixel(x: x, y: y))
    } }
  }
}
