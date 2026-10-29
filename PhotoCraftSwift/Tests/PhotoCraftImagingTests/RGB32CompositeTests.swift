import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class RGB32CompositeTests: XCTestCase {
  let names = [
    "01-opaque-samples", "02-alpha-samples", "03-opaque-base",
    "04-translucent-base", "05-mask-opacity", "06-cartesian-alpha",
    "07-random-mask", "08-three-layers", "09-offset-hdr", "10-opaque-base-random-mask",
  ]

  func fixture(_ name: String, extension ext: String = "psd") throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: name, withExtension: ext, subdirectory: "Fixtures/rgb32-composite")))
  }

  func merged(_ data: Data, width: Int, height: Int) throws -> Data {
    var reader = PSDReader(data: data)
    _ = try reader.bytes(12)
    let channels = try reader.u16()
    XCTAssertEqual(channels, 4)
    _ = try reader.bytes(12)
    for _ in 0..<3 { _ = try reader.section() }
    return Data(
      try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: width, height: height, depth: 32, channels: channels)
    )
  }

  func testPhotoshopMergedSamplesAndStraightLayersForEveryProbe() throws {
    for name in names {
      let document = try PSDCodec.read(fixture(name))
      let before = try NativeArchive.encode(document)
      let expected = try fixture(name, extension: "merged")
      for compression in PSDCompression.allCases {
        let encoded = try PSDCodec.writeRasterLayers(document, compression: compression)
        let actual = try merged(encoded, width: document.width, height: document.height)
        XCTAssertEqual(actual.count, expected.count, name)
        XCTAssertEqual(zip(actual, expected).filter { $0 != $1 }.count, 0, name)
        let reopened = try PSDCodec.read(encoded)
        for (a, b) in zip(document.layers, reopened.layers) {
          XCTAssertEqual(a.content, b.content, name)
          XCTAssertEqual(a.mask, b.mask, name)
          XCTAssertEqual(a.opacity.bitPattern, b.opacity.bitPattern, name)
        }
      }
      XCTAssertEqual(try NativeArchive.encode(document), before, name)
    }
  }

  func testRegionsAndIncrementalRenderMatchWholeNormalStack() throws {
    var document = try PSDCodec.read(fixture("08-three-layers"))
    let baseline = try Renderer.render(document)
    var hidden = Layer(name: "Hidden fill", content: .fill(.white))
    hidden.visible = false
    var hiddenDocument = document
    hiddenDocument.layers.append(hidden)
    XCTAssertEqual(
      try Renderer.composite(hiddenDocument).rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try baseline.surface.rgbaData(depth: .f32, colorEncoding: .linearRGB))
    let region = IntRect(x: 7, y: 9, width: 31, height: 27)
    let partial = try Renderer.composite(document, region: region)
    for y in 9..<36 {
      for x in 7..<38 {
        XCTAssertTrue(
          partial.linearPixel(x: x, y: y).hasSameBits(
            as:
              baseline.surface.linearPixel(x: x, y: y)))
      }
    }
    XCTAssertEqual(partial.linearPixel(x: 0, y: 0), .clear)
    guard case .raster(var source) = document.layers[1].content else { return XCTFail() }
    source.setLinearPixel(x: 15, y: 15, Pixel(2, -0.5, 0.01, 0.3))
    document.layers[1].content = .raster(source)
    let incremental = try Renderer.render(document, reusing: baseline)
    guard case .region = incremental.update else { return XCTFail("Expected regional update") }
    XCTAssertEqual(
      try incremental.surface.rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try Renderer.composite(document).rgbaData(depth: .f32, colorEncoding: .linearRGB))
  }

  func testPSD32OpacityKeepsCanonicalStoredByteValue() throws {
    let document = try PSDCodec.read(fixture("08-three-layers"))
    XCTAssertEqual(document.layers[1].opacity.bitPattern, UInt32(0x3f55_d5d6))
  }
  func testFiniteRangeOverflowIsReportedInsteadOfSilentlyReplacingPixels() throws {
    var document = try CraftDocument(width: 1, height: 1, depth: .f32)
    let layers = try [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude].map { value in
      var pixels = try Surface(width: 1, height: 1, depth: .f32, colorEncoding: .linearRGB)
      pixels.setLinearPixel(x: 0, y: 0, Pixel(value, 0, 0, 1))
      return Layer(name: "HDR", content: .raster(pixels))
    }
    document.layers = layers
    document.activeLayerID = layers.last?.id
    XCTAssertThrowsError(try Renderer.composite(document))
  }

}
