import XCTest
@testable import PhotoCraftCore

final class SkyMaskGaussianTests: XCTestCase {
  private func expected(_ source: Surface, sigma: Float) throws -> [UInt8] {
    let values = (0..<source.width * source.height).map { source.pixel(x: $0 % source.width, y: $0 / source.width).r }
    return try MattingFilters.gaussian(values, source.width, source.height, sigma)
      .map { UInt8(min(255, max(0, ($0 * 255).rounded()))) }
  }
  private func bytes(_ source: Surface) -> [UInt8] {
    (0..<source.width * source.height).map { UInt8((source.pixel(x: $0 % source.width, y: $0 / source.width).r * 255).rounded()) }
  }

  func testFullAxisGaussianMatchesDenseAcross2048AndCanvasEdges() throws {
    for (width, height) in [(2113, 129), (129, 2113)] {
      var source = try Surface(width: width, height: height, depth: .u8, fill: Pixel(0.4, 0.4, 0.4))
      for y in max(0, height - 97)..<height { for x in max(0, width - 97)..<width {
        let v = Float((x * 173 + y * 71) % 256) / 255
        source.setPixel(x: x, y: y, Pixel(v, v, v))
      } }
      let copy = source
      for sigma in [Float(0.1), 2.5, 5] {
        XCTAssertEqual(bytes(try SkyMaskGaussian.apply(source, sigma: sigma)), try expected(source, sigma: sigma), "\(width)x\(height), sigma=\(sigma)")
      }
      XCTAssertEqual(source, copy)
    }
  }

  func testImplicitAndExplicitBackgroundStorageRetainIdenticalGaussianBytes() throws {
    let width = 333, height = 139
    for background in [Float(1), Float(128) / 255] {
      var sparse = try Surface(width: width, height: height, depth: .u8, fill: Pixel(background, background, background))
      for y in 125..<height { for x in 70..<88 { sparse.setPixel(x: x, y: y, .black) } }
      var explicit = try Surface(width: width, height: height, depth: .u8, fill: .black)
      for y in 0..<height { for x in 0..<width { explicit.setPixel(x: x, y: y, sparse.pixel(x: x, y: y)) } }
      XCTAssertEqual(sparse, explicit)
      for sigma in [Float(0.5), 2.5, 5] {
        let reference = try expected(sparse, sigma: sigma)
        XCTAssertEqual(bytes(try SkyMaskGaussian.apply(sparse, sigma: sigma)), reference)
        XCTAssertEqual(bytes(try SkyMaskGaussian.apply(explicit, sigma: sigma)), reference)
      }
    }
  }

  func testEveryUniformCoverageByteIsPreservedByDenseAndImplicitGaussian() throws {
    for value in 0...255 {
      let v = Float(value) / 255
      let source = try Surface(width: 77, height: 69, depth: .u8, fill: Pixel(v, v, v))
      for sigma in [Float(0.5), 2.5, 5] {
        let reference = try expected(source, sigma: sigma)
        XCTAssertTrue(reference.allSatisfy { $0 == UInt8(value) })
        let output = try SkyMaskGaussian.apply(source, sigma: sigma)
        XCTAssertEqual(output.tileCount, 0)
        XCTAssertEqual(output.defaultPixel, source.defaultPixel)
      }
    }
  }
}
