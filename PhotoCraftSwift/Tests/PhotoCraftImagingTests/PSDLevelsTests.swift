import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDLevelsTests: XCTestCase {
  let levels = LevelsAdjustment(
    rgb: .init(inputBlack: 15, inputWhite: 230, gamma: 1.3, outputBlack: 10, outputWhite: 245),
    red: .init(gamma: 0.5), green: .init(inputBlack: 44, inputWhite: 214, gamma: 1.78))
  func testIndependentBinaryRecordAndMalformedInput() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "levels-record", withExtension: "alv", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    XCTAssertEqual(try PSDLevels.read(data), levels)
    XCTAssertEqual(try PSDLevels.write(levels), data)
    for count in 0..<data.count { XCTAssertThrowsError(try PSDLevels.read(data.prefix(count))) }
    var bad = data
    bad[1] = 3
    XCTAssertThrowsError(try PSDLevels.read(bad))
    bad = data
    bad[42 + 9] = 90  // Non-identity, unrepresented fifth channel.
    XCTAssertThrowsError(try PSDLevels.read(bad))
    bad = data
    bad.append(contentsOf: [76, 118, 108, 115, 0, 3, 0, 29])
    XCTAssertEqual(try PSDLevels.read(bad), levels)
    XCTAssertEqual(try PSDLevels.write(levels, original: bad), bad)
    bad.append(0)
    XCTAssertThrowsError(try PSDLevels.read(bad))
    XCTAssertThrowsError(try PSDLevels.write(.init(rgb: .init(gamma: 1.234))))
  }
  func testEditablePSDLevelsMasksAndCompositeAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 16, height: 8, depth: depth)
      var raster = try Surface(width: d.width, height: d.height, depth: depth)
      raster.mapPixels { x, y, _ in Pixel(Float(x) / 15, Float(y) / 7, 0.5) }
      d.layers[0].content = .raster(raster)
      var layer = Layer(name: "Editable Levels", content: .adjustment(.levels(levels)))
      layer.opacity = 128.0 / 255
      layer.mask = try Surface(width: 8, height: 8, depth: depth, fill: .white)
      layer.maskProperties = .init()
      layer.maskProperties?.transform = .translation(4, 0)
      d.layers.append(layer)
      let data = try PSDCodec.writeRasterLayers(d)
      let actual = try PSDCodec.read(data)
      XCTAssertEqual(actual.layers.count, 2)
      XCTAssertEqual(actual.layers[1].content, layer.content)
      let mask = try XCTUnwrap(actual.layers[1].mask)
      XCTAssertEqual(mask.width, 8)
      XCTAssertEqual(mask.height, 8)
      for y in 0..<8 { for x in 0..<8 { XCTAssertEqual(mask.pixel(x: x, y: y), .white) } }
      XCTAssertEqual(actual.layers[1].maskCoordinateTransform, .translation(4, 0))
      let expectedPixels = try Renderer.composite(d)
      let actualPixels = try Renderer.composite(actual)
      for y in 0..<d.height {
        for x in 0..<d.width {
          let a = actualPixels.pixel(x: x, y: y)
          let b = expectedPixels.pixel(x: x, y: y)
          XCTAssertEqual(a.r, b.r, accuracy: 0.000003)
          XCTAssertEqual(a.g, b.g, accuracy: 0.000003)
          XCTAssertEqual(a.b, b.b, accuracy: 0.000003)
        }
      }
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.width, d.width)
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      try data.write(
        to: root.appendingPathComponent("artifacts/native-levels-\(depth.rawValue).psd"))
    }
  }
  func testEditsReplaceLevelsTagAndIncompatibleContentRejects() throws {
    var d = try CraftDocument(width: 4, height: 4)
    d.layers.append(Layer(name: "Levels", content: .adjustment(.levels(levels))))
    d = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    let original = try XCTUnwrap(d.layers[1].sourceTags?["levl"])
    d.layers[1].content = .adjustment(.levels(.init()))
    let changed = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(changed.layers[1].content, .adjustment(.levels(.init())))
    XCTAssertNotEqual(changed.layers[1].sourceTags?["levl"], original)
    d.layers[1].content = .raster(try Surface(width: 4, height: 4, fill: .white))
    let flattened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertNil(flattened.layers[1].sourceTags?["levl"])
    d.layers[1].content = .adjustment(.saturation(0.5))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
  }
  func testAdjustmentOpacityAndMaskPreserveAlpha() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 2, height: 1, depth: depth)
      let pixel = Pixel(0.4, 0.5, 0.6, 0.5).quantized(depth)
      d.layers[0].content = .raster(try Surface(width: 2, height: 1, depth: depth, fill: pixel))
      var layer = Layer(name: "Levels", content: .adjustment(.levels(levels)))
      layer.opacity = 0.5
      var mask = try Surface(width: 2, height: 1, depth: depth)
      mask.setPixel(x: 1, y: 0, .white)
      layer.mask = mask
      d.layers.append(layer)
      let result = try Renderer.composite(d)
      let base = try Renderer.composite(
        {
          var base = d
          base.layers.removeLast()
          return base
        }())
      XCTAssertEqual(result.pixel(x: 0, y: 0), base.pixel(x: 0, y: 0))
      XCTAssertEqual(result.pixel(x: 1, y: 0).a, pixel.a)
      XCTAssertNotEqual(result.pixel(x: 1, y: 0).r, base.pixel(x: 1, y: 0).r)
    }
  }
}
