import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDHueSaturationTests: XCTestCase {
  var settings: HueSaturationAdjustment {
    var a = HueSaturationAdjustment(
      master: .init(hue: 30, saturation: -20, lightness: 5),
      colorization: .init(hue: -145, saturation: 25, lightness: 7))
    a.ranges[0].values = .init(hue: 120, saturation: -60, lightness: 20)
    a.ranges[3].values = .init(hue: -20, saturation: 40, lightness: -10)
    return a
  }
  func fixture() throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "hue-saturation-record", withExtension: "ahu", subdirectory: "Fixtures")))
  }
  func testIndependentBinaryRecordAndBothParameterSets() throws {
    let data = try fixture()
    XCTAssertEqual(data.count, 100)
    XCTAssertEqual(try PSDHueSaturation.read(data), settings)
    XCTAssertEqual(try PSDHueSaturation.write(settings), data)
    var padded = data
    padded[3] = 251
    XCTAssertEqual(try HueSaturationPresetCodec.read(padded), settings)
    XCTAssertEqual(try HueSaturationPresetCodec.write(settings, original: padded), padded)
    var enabled = settings
    enabled.colorize = true
    let edited = try HueSaturationPresetCodec.write(enabled, original: padded)
    XCTAssertEqual(try HueSaturationPresetCodec.read(edited), enabled)
    XCTAssertEqual(edited[2], 1)
    XCTAssertEqual(edited.dropFirst(4), data.dropFirst(4))
    enabled.colorization.hue = 215
    XCTAssertEqual(try PSDHueSaturation.read(PSDHueSaturation.write(enabled)), enabled)
  }
  func testTruncatedExcessInvalidFlagsValuesAndRangeOrderingReject() throws {
    let data = try fixture()
    for length in 0..<100 { XCTAssertThrowsError(try PSDHueSaturation.read(data.prefix(length))) }
    XCTAssertThrowsError(try PSDHueSaturation.read(data + Data([0])))
    for (index, value) in [
      (1, UInt8(1)), (2, 2), (7, 101), (11, 181), (13, 101), (15, 101), (16, 255),
    ] {
      var bad = data
      bad[index] = value
      XCTAssertThrowsError(try PSDHueSaturation.read(bad), "Byte \(index)")
    }
    var loop = data
    for (i, bound) in [0, 120, 240, 0].enumerated() {
      loop[16 + i * 2] = UInt8(bound >> 8)
      loop[17 + i * 2] = UInt8(bound & 255)
    }
    XCTAssertThrowsError(try PSDHueSaturation.read(loop))
    XCTAssertThrowsError(try PSDHueSaturation.write(.init(ranges: [])))
  }
  func testInstalledPhotoshop2026PresetsIncludingInactiveSettings() throws {
    let root = URL(
      fileURLWithPath: "/Applications/Adobe Photoshop 2026/Presets/Hue and Saturation",
      isDirectory: true)
    guard FileManager.default.fileExists(atPath: root.path) else {
      throw XCTSkip("Installed Photoshop 2026 is required for direct preset qualification.")
    }
    for preset in BuiltInHueSaturationPreset.allCases where preset != .standard {
      let data = try Data(contentsOf: root.appendingPathComponent(preset.rawValue + ".ahu"))
      let actual = try HueSaturationPresetCodec.read(data)
      XCTAssertEqual(actual, preset.adjustment, preset.rawValue)
      XCTAssertEqual(try HueSaturationPresetCodec.write(actual, original: data), data)
      XCTAssertEqual(try HueSaturationPresetCodec.write(actual), data)
    }
  }
  func testEditablePSDAtAllDepthsMasksGroupsClippingAndIndependentImageIO() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 16, height: 8, depth: depth)
      var pixels = try Surface(width: d.width, height: d.height, depth: depth)
      pixels.mapPixels { x, y, _ in Pixel(Float(x) / 15, Float(y) / 7, 0.5) }
      d.layers[0].content = .raster(pixels)
      let group = Layer(name: "Group", content: .group(.init(passThrough: false)))
      d.layers[0].parentID = group.id
      var adjustment = Layer(name: "Hue/Saturation", content: .adjustment(.hueSaturation(settings)))
      adjustment.parentID = group.id
      adjustment.clipped = true
      adjustment.opacity = 128.0 / 255
      adjustment.mask = try Surface(width: 8, height: 8, depth: depth, fill: .white)
      adjustment.maskProperties = .init()
      adjustment.maskProperties?.transform = .translation(4, 0)
      d.layers.append(contentsOf: [adjustment, group])
      let bytes = try PSDCodec.writeRasterLayers(d)
      let reopened = try PSDCodec.read(bytes)
      XCTAssertEqual(reopened.layers.count, 3)
      XCTAssertEqual(reopened.layers[1].content, adjustment.content)
      let tag = try XCTUnwrap(reopened.layers[1].sourceTags?["hue2"])
      XCTAssertEqual(tag.count, 136)
      XCTAssertEqual(tag.prefix(100), try fixture())
      let expectedColors: [UInt8] = [
        0, 0, 0, 100, 0, 50, 0, 60, 0, 100, 0, 50, 0, 120, 0, 100, 0, 50, 0, 180, 0, 100, 0, 50, 0,
        240, 0, 100, 0, 50, 1, 44, 0, 100, 0, 50,
      ]
      XCTAssertEqual(tag.suffix(36), Data(expectedColors))
      XCTAssertTrue(reopened.layers[1].isClipped)
      XCTAssertEqual(reopened.layers[1].parentID, reopened.layers[2].id)
      XCTAssertEqual(reopened.layers[1].maskCoordinateTransform, .translation(4, 0))
      let expected = try Renderer.composite(d)
      let actual = try Renderer.composite(reopened)
      for y in 0..<8 {
        for x in 0..<16 {
          let a = actual.pixel(x: x, y: y)
          let b = expected.pixel(x: x, y: y)
          XCTAssertEqual(a.r, b.r, accuracy: 0.000003)
          XCTAssertEqual(a.g, b.g, accuracy: 0.000003)
          XCTAssertEqual(a.b, b.b, accuracy: 0.000003)
          XCTAssertEqual(a.a, b.a)
        }
      }
      let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
      XCTAssertEqual(try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil)).width, 16)
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      try bytes.write(
        to: root.appendingPathComponent("artifacts/native-hue-saturation-\(depth.rawValue).psd"))
    }
  }
  func testMaskOpacityFloatMixingAndStaleMetadataRemoval() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 2, height: 1, depth: depth)
      d.layers[0].content = .raster(
        try Surface(width: 2, height: 1, depth: depth, fill: Pixel(0.4, 0.5, 0.6, 0.5)))
      let before = try Renderer.composite(d)
      var layer = Layer(name: "Hue/Saturation", content: .adjustment(.hueSaturation(settings)))
      layer.opacity = 0.5
      var mask = try Surface(width: 2, height: 1, depth: depth)
      mask.setPixel(x: 1, y: 0, .white)
      layer.mask = mask
      d.layers.append(layer)
      let result = try Renderer.composite(d)
      let p = before.pixel(x: 1, y: 0)
      let edited = HueSaturationTransfer(settings, depth: depth).apply(before.pixel(x: 1, y: 0))
      XCTAssertEqual(result.pixel(x: 0, y: 0), before.pixel(x: 0, y: 0))
      XCTAssertEqual(
        result.pixel(x: 1, y: 0), LevelsTransfer.mix(p, with: edited, coverage: 0.5, depth: depth))
      d = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      d.layers[1].content = .adjustment(.hueSaturation(.init(colorize: true)))
      let changed = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      XCTAssertEqual(changed.layers[1].content, d.layers[1].content)
      d.layers[1].content = .adjustment(.curves(.init()))
      let curves = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      XCTAssertNil(curves.layers[1].sourceTags?["hue2"])
      XCTAssertNotNil(curves.layers[1].sourceTags?["curv"])
      d.layers[1].content = .raster(try Surface(width: 2, height: 1, depth: depth, fill: .white))
      XCTAssertNil(try PSDCodec.read(PSDCodec.writeRasterLayers(d)).layers[1].sourceTags?["hue2"])
    }
  }
}
