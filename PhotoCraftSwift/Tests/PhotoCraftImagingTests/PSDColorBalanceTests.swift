import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDColorBalanceTests: XCTestCase {
  var settings: ColorBalanceAdjustment {
    .init(
      shadows: .init(cyanRed: -30, magentaGreen: 20),
      midtones: .init(cyanRed: 10, magentaGreen: -5, yellowBlue: 100),
      highlights: .init(yellowBlue: -100))
  }
  func fixture() throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "color-balance-record", withExtension: "bin", subdirectory: "Fixtures")))
  }
  func testIndependentBinaryRecordShortFormAndOriginalPadding() throws {
    let data = try fixture()
    XCTAssertEqual(data.count, 20)
    XCTAssertEqual(try PSDColorBalance.read(data), settings)
    XCTAssertEqual(try PSDColorBalance.write(settings), data)
    let short = Data(data.prefix(19))
    XCTAssertEqual(try PSDColorBalance.read(short), settings)
    XCTAssertEqual(try PSDColorBalance.write(settings, original: short), short)
    var padded = data
    padded[19] = 237
    XCTAssertEqual(try PSDColorBalance.read(padded), settings)
    XCTAssertEqual(try PSDColorBalance.write(settings, original: padded), padded)
    var changed = settings
    changed.preserveLuminosity = false
    let edited = try PSDColorBalance.write(changed, original: padded)
    XCTAssertEqual(edited[18], 0)
    XCTAssertEqual(edited[19], 0)
    XCTAssertEqual(edited.prefix(18), data.prefix(18))
    XCTAssertEqual(try PSDColorBalance.read(edited), changed)
  }
  func testTruncationExcessInvalidFlagsAndEachToneValueReject() throws {
    let data = try fixture()
    for length in 0..<19 { XCTAssertThrowsError(try PSDColorBalance.read(data.prefix(length))) }
    XCTAssertThrowsError(try PSDColorBalance.read(data + Data([0])))
    var invalid = data
    invalid[18] = 2
    XCTAssertThrowsError(try PSDColorBalance.read(invalid))
    for field in 0..<9 {
      for value: Int16 in [-32768, -101, 101, 32767] {
        var bad = data
        let bits = UInt16(bitPattern: value)
        bad[field * 2] = UInt8(bits >> 8)
        bad[field * 2 + 1] = UInt8(bits & 255)
        XCTAssertThrowsError(try PSDColorBalance.read(bad))
      }
    }
    XCTAssertThrowsError(try PSDColorBalance.write(.init(highlights: .init(cyanRed: -101))))
  }
  func testPSDAtAllDepthsMasksGroupsClippingAndIndependentDecoder() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 16, height: 8, depth: depth)
      var pixels = try Surface(width: d.width, height: d.height, depth: depth)
      pixels.mapPixels { x, y, _ in Pixel(Float(x) / 15, Float(y) / 7, 0.5) }
      d.layers[0].content = .raster(pixels)
      let group = Layer(name: "Group", content: .group(.init(passThrough: false)))
      d.layers[0].parentID = group.id
      var adjustment = Layer(name: "Color Balance", content: .adjustment(.colorBalance(settings)))
      adjustment.parentID = group.id
      adjustment.clipped = true
      adjustment.opacity = 128.0 / 255
      adjustment.mask = try Surface(width: 8, height: 8, depth: depth, fill: .white)
      adjustment.maskProperties = .init()
      adjustment.maskProperties?.transform = .translation(4, 0)
      // Preserve odd-length source records and correctly align the next block.
      adjustment.sourceTags = ["blnc": Data(try fixture().prefix(19))]
      d.layers.append(contentsOf: [adjustment, group])
      let data = try PSDCodec.writeRasterLayers(d)
      let reopened = try PSDCodec.read(data)
      XCTAssertEqual(reopened.layers.count, 3)
      XCTAssertEqual(reopened.layers[1].content, adjustment.content)
      XCTAssertEqual(reopened.layers[1].sourceTags?["blnc"], adjustment.sourceTags?["blnc"])
      XCTAssertTrue(reopened.layers[1].isClipped)
      XCTAssertEqual(reopened.layers[1].parentID, reopened.layers[2].id)
      XCTAssertEqual(reopened.layers[1].maskCoordinateTransform, .translation(4, 0))
      let actual = try Renderer.composite(reopened)
      let expected = try Renderer.composite(d)
      for y in 0..<8 {
        for x in 0..<16 {
          let p = actual.pixel(x: x, y: y)
          let q = expected.pixel(x: x, y: y)
          XCTAssertEqual(p.r, q.r, accuracy: 0.0001)
          XCTAssertEqual(p.g, q.g, accuracy: 0.0001)
          XCTAssertEqual(p.b, q.b, accuracy: 0.0001)
        }
      }
      let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
      XCTAssertEqual(image.width, 16)
      XCTAssertEqual(image.height, 8)
      try data.write(
        to: URL(fileURLWithPath: "artifacts/native-color-balance-\(depth.rawValue).psd"))
    }
  }
  func testMaskOpacityLinearFloatMixAndNoStaleContentTags() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 2, height: 1, depth: depth)
      d.layers[0].content = .raster(
        try Surface(width: 2, height: 1, depth: depth, fill: Pixel(0.2, 0.4, 0.6)))
      let before = try Renderer.composite(d)
      var layer = Layer(name: "Color Balance", content: .adjustment(.colorBalance(settings)))
      layer.opacity = 0.5
      var mask = try Surface(width: 2, height: 1, depth: depth, fill: .black)
      mask.setPixel(x: 1, y: 0, .white)
      layer.mask = mask
      d.layers.append(layer)
      let actual = try Renderer.composite(d)
      let p = before.pixel(x: 1, y: 0)
      let adjusted = ColorBalanceTransfer(settings, depth: depth).apply(p)
      XCTAssertEqual(actual.pixel(x: 0, y: 0), before.pixel(x: 0, y: 0))
      XCTAssertEqual(
        actual.pixel(x: 1, y: 0), LevelsTransfer.mix(p, with: adjusted, coverage: 0.5, depth: depth)
      )
      d = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      d.layers[1].content = .adjustment(
        .colorBalance(.init(midtones: .init(cyanRed: 40), preserveLuminosity: false)))
      XCTAssertEqual(
        try PSDCodec.read(PSDCodec.writeRasterLayers(d)).layers[1].content, d.layers[1].content)
      d.layers[1].content = .adjustment(.hueSaturation(.init()))
      let hue = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      XCTAssertNil(hue.layers[1].sourceTags?["blnc"])
      XCTAssertNotNil(hue.layers[1].sourceTags?["hue2"])
      d.layers[1].content = .raster(try Surface(width: 2, height: 1, depth: depth, fill: .white))
      XCTAssertNil(try PSDCodec.read(PSDCodec.writeRasterLayers(d)).layers[1].sourceTags?["blnc"])
    }
  }
}
