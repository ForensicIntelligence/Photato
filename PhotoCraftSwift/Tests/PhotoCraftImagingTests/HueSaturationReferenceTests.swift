import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class HueSaturationReferenceTests: XCTestCase {
  let fixtures: [(String, String, Float)] = [
    (
      "huesaturation_colorize_rgb",
      "8e64b22972a81439c97ea2ec94d535e4c947c276c54ab701d7eee042de02efa0", 0.012
    ),
    (
      "huesaturation_lightness_rgb",
      "bacb269f9b1f75e54bc64f10cf33e5acf947389900b7ee6b6576b7cb332e4cdb", 0.018
    ),
    (
      "huesaturation_rgb", "2c81966b5f43f48ea0596ee02b41a18eff3db92e3a9a54c83769e561f018f55d", 0.266
    ),
    (
      "huesaturation_saturation_rgb",
      "389c6fe7d8dd6f73e4ea4039b8ee4b94cc9c20023ace6727aa76799a7897f409", 0.095
    ),
  ]
  func data(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "psdtools-" + name, withExtension: "psd", subdirectory: "Fixtures")))
  }
  func testPinnedPhotoshopRecordsNativeArchiveAndUnchangedPSDData() throws {
    var records = 0
    for (name, hash, _) in fixtures {
      let bytes = try data(name)
      XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), hash)
      let d = try PSDCodec.read(bytes)
      XCTAssertEqual(d.width, 200)
      XCTAssertEqual(d.height, 200)
      XCTAssertEqual(d.depth, .u8)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      XCTAssertEqual(saved.layers.count, d.layers.count)
      for (index, layer) in d.layers.enumerated() {
        guard case .adjustment(.hueSaturation(let adjustment)) = layer.content else { continue }
        let original = try XCTUnwrap(layer.sourceTags?["hue2"])
        XCTAssertEqual(original.count, 136)
        XCTAssertEqual(try PSDHueSaturation.read(original), adjustment)
        XCTAssertEqual(saved.layers[index].sourceTags?["hue2"], original)
        XCTAssertEqual(saved.layers[index].content, layer.content)
        XCTAssertEqual(saved.layers[index].maskCoordinateTransform, layer.maskCoordinateTransform)
        records += 1
      }
    }
    XCTAssertEqual(records, 16)
  }
  func testRangeColorTrailerRegeneratesAfterEditsAndRejectsUnrepresentedData() throws {
    let d = try PSDCodec.read(data("huesaturation_lightness_rgb"))
    let layer = try XCTUnwrap(d.layers.first { $0.sourceTags?["hue2"] != nil })
    let original = try XCTUnwrap(layer.sourceTags?["hue2"])
    var settings = try PSDHueSaturation.read(original)
    XCTAssertEqual(try PSDHueSaturation.write(settings, original: original), original)
    settings.ranges[0].bounds = [-30, -12, 19, 51]
    settings.master.hue = 20
    let edited = try PSDHueSaturation.write(settings, original: original)
    XCTAssertEqual(edited.count, 136)
    XCTAssertEqual(Array(edited[100..<106]), [0, 3, 0, 100, 0, 50])
    XCTAssertEqual(try PSDHueSaturation.read(edited), settings)
    XCTAssertEqual(settings.ranges[0].representativeHue, 3)
    XCTAssertEqual(HueRange(bounds: [-30, -12, 11, 30]).representativeHue, 359)
    XCTAssertEqual(HueRange(bounds: [330, 350, 370, 390]).representativeHue, 0)
    XCTAssertEqual(try HueSaturationPresetCodec.write(settings).count, 100)
    for length in 101..<136 {
      XCTAssertThrowsError(try PSDHueSaturation.read(edited.prefix(length)))
    }
    XCTAssertThrowsError(try PSDHueSaturation.read(edited + Data([0])))
    for offset in 100..<136 {
      var invalid = edited
      invalid[offset] ^= 1
      XCTAssertThrowsError(try PSDHueSaturation.read(invalid))
    }
  }
  func testSavedPhotoshopCompositesMeasureRemainingPixelDifferences() throws {
    var report: [[String: Any]] = []
    for (name, _, regressionBound) in fixtures {
      let bytes = try data(name)
      let d = try PSDCodec.read(bytes)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      let expected = try RasterIO.surface(image, depth: d.depth)
      let actual = try Renderer.composite(d)
      var maximum: Float = 0
      var changed = 0
      var errorSum: Double = 0
      for y in 0..<d.height {
        for x in 0..<d.width {
          let p = actual.pixel(x: x, y: y)
          let q = expected.pixel(x: x, y: y)
          let error = max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
          maximum = max(maximum, error)
          errorSum += Double(error)
          if p.quantized(d.depth) != q.quantized(d.depth) { changed += 1 }
        }
      }
      // These measured ceilings prevent regressions; they explicitly do NOT
      // satisfy the required byte-identical Photoshop acceptance gate.
      XCTAssertLessThanOrEqual(maximum, regressionBound, name)
      let meanBounds = [
        "huesaturation_colorize_rgb": 0.004, "huesaturation_lightness_rgb": 0.0022,
        "huesaturation_rgb": 0.0067, "huesaturation_saturation_rgb": 0.0029,
      ]
      XCTAssertLessThan(
        errorSum / Double(d.width * d.height), try XCTUnwrap(meanBounds[name]), name)
      report.append([
        "file": name + ".psd", "imported": true,
        "maximum_encoded_error": maximum, "differing_pixels": changed,
        "mean_pixel_max_error": errorSum / Double(d.width * d.height),
        "exact_at_document_depth": changed == 0,
      ])
    }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(
        to: PSDSolidColorTests.root.appendingPathComponent("artifacts/hue-reference-corrected.json")
      )
  }
}
