import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDCurvesTests: XCTestCase {
  let curves = CurvesAdjustment(
    rgb: .init([.init(0, 0), .init(55, 20), .init(200, 240), .init(255, 255)]),
    red: .init([.init(33, 255), .init(119, 127), .init(185, 0)]),
    green: .init([.init(0, 0), .init(64, 240), .init(128, 5), .init(190, 200), .init(255, 0)]))
  func fixture(_ name: String, _ ext: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
  }
  func testIndependentPresetAndPSDRecordsAndExtensions() throws {
    let acv = try fixture("curves-record", "acv")
    let psd = try fixture("curves-record", "curv")
    let extended = try fixture("curves-extended", "curv")
    XCTAssertEqual(try CurvesPresetCodec.read(acv), curves)
    XCTAssertEqual(try CurvesPresetCodec.write(curves), acv)
    XCTAssertEqual(try PSDCurves.read(psd), curves)
    XCTAssertEqual(try PSDCurves.write(curves), psd)
    XCTAssertEqual(try PSDCurves.read(extended), curves)
    XCTAssertEqual(try PSDCurves.write(curves, original: extended), extended)
    XCTAssertEqual(
      try CurvesPresetCodec.read(fixture("curves-bitmap", "acv")), .init(red: curves.red))
    var acvExtended = Data([0, 1, 0, 15])
    acvExtended.append(extended.dropFirst(7))
    XCTAssertEqual(try CurvesPresetCodec.read(acvExtended), curves)
    XCTAssertEqual(try CurvesPresetCodec.write(curves, original: acvExtended), acvExtended)
    for count in 0..<acv.count {
      XCTAssertThrowsError(try CurvesPresetCodec.read(acv.prefix(count)))
    }
    for count in 0..<extended.count where count != psd.count {
      XCTAssertThrowsError(try PSDCurves.read(extended.prefix(count)))
    }
  }
  func testMalformedUnsupportedAndConflictingRecordsReject() throws {
    let psd = try fixture("curves-record", "curv")
    for (offset, byte) in [(0, UInt8(1)), (2, 2), (8, 20), (11, 1), (13, 0)] {
      var bad = psd
      bad[offset] = byte
      // Last mutation makes the second point input equal to zero.
      if offset == 13 { bad[16] = 0 }
      XCTAssertThrowsError(try PSDCurves.read(bad), "offset \(offset)")
    }
    var extra = psd
    extra[6] = 31
    var record = PSDWriter()
    PSDCurves.writeCurve(.init([.init(0, 255), .init(255, 0)]), to: &record)
    extra.append(record.data)
    XCTAssertThrowsError(try PSDCurves.read(extra))
    var conflict = try fixture("curves-extended", "curv")
    conflict[psd.count + 15] = 1
    XCTAssertThrowsError(try PSDCurves.read(conflict))
    XCTAssertThrowsError(try PSDCurves.read(psd + Data([0])))
    XCTAssertThrowsError(try CurvesPresetCodec.read(Data(repeating: 0, count: 32769)))
    XCTAssertThrowsError(try CurvesPresetCodec.read(Data([0, 4, 255, 255])))
    XCTAssertThrowsError(try CurvesPresetCodec.write(.init(rgb: .init([]))))
  }
  func testInstalledPhotoshop2026PresetsMatchNativeDefinitions() throws {
    let root = URL(
      fileURLWithPath: "/Applications/Adobe Photoshop 2026/Presets/Curves", isDirectory: true)
    guard FileManager.default.fileExists(atPath: root.path) else {
      throw XCTSkip("Installed Photoshop 2026 is required for direct preset qualification.")
    }
    for preset in BuiltInCurvesPreset.allCases where preset != .standard {
      let data = try Data(contentsOf: root.appendingPathComponent(preset.rawValue + ".acv"))
      let actual = try CurvesPresetCodec.read(data)
      XCTAssertEqual(actual, preset.curves, preset.rawValue)
      XCTAssertEqual(try CurvesPresetCodec.write(actual, original: data), data)
    }
  }
  func testEditablePSDAtEveryDepthIncludingMasksAndGroups() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 16, height: 8, depth: depth)
      var raster = try Surface(width: d.width, height: d.height, depth: depth)
      raster.mapPixels { x, y, _ in Pixel(Float(x) / 15, Float(y) / 7, 0.5) }
      d.layers[0].content = .raster(raster)
      let group = Layer(name: "Group", content: .group(.init(passThrough: false)))
      d.layers[0].parentID = group.id
      var layer = Layer(name: "Editable Curves", content: .adjustment(.curves(curves)))
      layer.parentID = group.id
      layer.clipped = true
      layer.opacity = 128.0 / 255
      layer.mask = try Surface(width: 8, height: 8, depth: depth, fill: .white)
      layer.maskProperties = .init()
      layer.maskProperties?.transform = .translation(4, 0)
      d.layers.append(contentsOf: [layer, group])
      let data = try PSDCodec.writeRasterLayers(d)
      let reopened = try PSDCodec.read(data)
      XCTAssertEqual(reopened.layers.count, 3)
      XCTAssertEqual(reopened.layers[1].content, layer.content)
      XCTAssertTrue(reopened.layers[1].isClipped)
      XCTAssertEqual(reopened.layers[1].parentID, reopened.layers[2].id)
      XCTAssertEqual(reopened.layers[1].maskCoordinateTransform, .translation(4, 0))
      let expected = try Renderer.composite(d)
      let actual = try Renderer.composite(reopened)
      for y in 0..<8 {
        for x in 0..<16 {
          let a = expected.pixel(x: x, y: y)
          let b = actual.pixel(x: x, y: y)
          XCTAssertEqual(a.r, b.r, accuracy: 0.000003)
          XCTAssertEqual(a.g, b.g, accuracy: 0.000003)
          XCTAssertEqual(a.b, b.b, accuracy: 0.000003)
          XCTAssertEqual(a.a, b.a)
        }
      }
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      XCTAssertEqual(try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).width, 16)
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      try data.write(
        to: root.appendingPathComponent("artifacts/native-curves-\(depth.rawValue).psd"))
    }
  }
  func testEditsReplaceCurveTagsAndRasterizationRemovesThem() throws {
    var d = try CraftDocument(width: 4, height: 2)
    d.layers.append(Layer(name: "Curves", content: .adjustment(.curves(curves))))
    d = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(d.layers[1].sourceTags?["curv"], try PSDCurves.write(curves))
    d.layers[1].content = .adjustment(.curves(.init()))
    let changed = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(changed.layers[1].content, .adjustment(.curves(.init())))
    XCTAssertEqual(changed.layers[1].sourceTags?["curv"], try PSDCurves.write(.init()))
    d.layers[1].content = .adjustment(.levels(.init()))
    let levels = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertNil(levels.layers[1].sourceTags?["curv"])
    XCTAssertNotNil(levels.layers[1].sourceTags?["levl"])
    d.layers[1].content = .raster(try Surface(width: 4, height: 2, fill: .white))
    XCTAssertNil(try PSDCodec.read(PSDCodec.writeRasterLayers(d)).layers[1].sourceTags?["curv"])
  }
  func testCurvesMaskOpacityAndHistogramInput() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 2, height: 1, depth: depth)
      d.layers[0].content = .raster(
        try Surface(width: 2, height: 1, depth: depth, fill: Pixel(0.4, 0.5, 0.6, 0.5)))
      let before = try Renderer.composite(d)
      var layer = Layer(name: "Curves", content: .adjustment(.curves(curves)))
      layer.opacity = 0.5
      var mask = try Surface(width: 2, height: 1, depth: depth)
      mask.setPixel(x: 1, y: 0, .white)
      layer.mask = mask
      d.layers.append(layer)
      let actual = try Renderer.composite(d)
      let base = before.pixel(x: 1, y: 0)
      let edited = CurvesTransfer(curves, depth: depth).apply(base)
      XCTAssertEqual(actual.pixel(x: 0, y: 0), before.pixel(x: 0, y: 0))
      XCTAssertEqual(
        actual.pixel(x: 1, y: 0),
        LevelsTransfer.mix(base, with: edited, coverage: 0.5, depth: depth))
      XCTAssertEqual(try Renderer.adjustmentInput(layer.id, in: d), before)
    }
  }
}
