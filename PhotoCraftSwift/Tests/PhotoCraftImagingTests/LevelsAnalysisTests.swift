import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class LevelsAnalysisTests: XCTestCase {
  func raster(_ name: String, _ color: Pixel) throws -> Layer {
    Layer(name: name, content: .raster(try Surface(width: 4, height: 2, depth: .f32, fill: color)))
  }
  func document(_ layers: [Layer]) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 2, depth: .u8)
    d.layers = layers
    d.activeLayerID = layers.last?.id
    return d
  }
  func testHistogramCapturesInputBeforeOwnParametersMaskAndUpperLayers() throws {
    let base = try raster("Base", Pixel(0.2, 0.4, 0.6))
    let prior = Layer(name: "Earlier invert", content: .adjustment(.invert))
    var target = Layer(name: "Levels", content: .adjustment(.levels(.init(rgb: .init(gamma: 0.5)))))
    target.mask = try Surface(width: 4, height: 2, fill: .black)
    target.opacity = 0
    target.visible = false
    let upper = try raster("Upper", .white)
    let d = try document([base, prior, target, upper])
    let input = try Renderer.adjustmentInput(target.id, in: d)
    let p = input.pixel(x: 0, y: 0)
    XCTAssertEqual(p.r, 0.8, accuracy: 0.000001)
    XCTAssertEqual(p.g, 0.6, accuracy: 0.000001)
    XCTAssertEqual(p.b, 0.4, accuracy: 0.000001)
    let h = try Renderer.levelsHistogram(target.id, in: d)
    XCTAssertEqual(h.samples, 8)
    XCTAssertEqual(h.channels[0][204], 8)
    XCTAssertFalse(d.layers[2].visible)
    XCTAssertEqual(d.layers[2].opacity, 0)
    XCTAssertThrowsError(try Renderer.adjustmentInput(base.id, in: d))
  }
  func testInputFollowsPassThroughIsolatedGroupsAndClipping() throws {
    let outside = try raster("Outside", Pixel(0, 0, 1))
    var group = Layer(name: "Group", content: .group(.init()))
    group.opacity = 0.2
    var inside = try raster("Inside", Pixel(1, 0, 0, 0.5))
    inside.parentID = group.id
    var target = Layer(name: "Levels", content: .adjustment(.levels(.init())))
    target.parentID = group.id
    var d = try document([outside, inside, target, group])
    var p = try Renderer.adjustmentInput(target.id, in: d).pixel(x: 0, y: 0)
    XCTAssertEqual(p, Pixel(0.5, 0, 0.5))
    group.content = .group(.init(passThrough: false))
    group.visible = false
    d.layers[3] = group
    p = try Renderer.adjustmentInput(target.id, in: d).pixel(x: 0, y: 0)
    XCTAssertEqual(p, Pixel(1, 0, 0, 0.5))
    inside.parentID = nil
    target.parentID = nil
    target.clipped = true
    var firstClip = try raster("Blue clip", Pixel(0, 0, 1))
    firstClip.clipped = true
    d = try document([inside, firstClip, target])
    p = try Renderer.adjustmentInput(target.id, in: d).pixel(x: 0, y: 0)
    XCTAssertEqual(p, Pixel(0, 0, 1, 0.5))
    d.layers[0].visible = false
    XCTAssertThrowsError(try Renderer.adjustmentInput(target.id, in: d))
  }
  func testExtendedPresetRecordsAreBoundedAndPreserved() throws {
    let levels = LevelsAdjustment(rgb: .init(inputBlack: 19, inputWhite: 231, gamma: 1.31))
    var data = try LevelsPresetCodec.write(levels)
    var w = PSDWriter()
    w.text("Lvls")
    w.n(3, 2)
    w.n(62, 2)
    for _ in 29..<62 { for v in [0, 255, 0, 255, 100] { w.n(v, 2) } }
    data.append(w.data)
    XCTAssertEqual(data.count, 630)
    XCTAssertEqual(try LevelsPresetCodec.read(data), levels)
    XCTAssertEqual(try LevelsPresetCodec.write(levels, original: data), data)
    for size in 293..<data.count {
      XCTAssertThrowsError(try LevelsPresetCodec.read(data.prefix(size)))
    }
    var malformed = data
    malformed[298] = 255
    XCTAssertThrowsError(try LevelsPresetCodec.read(malformed))
    malformed = data
    malformed[629] = 90
    XCTAssertThrowsError(try LevelsPresetCodec.read(malformed))
    XCTAssertThrowsError(try LevelsPresetCodec.read(Data(repeating: 0, count: 4097)))
  }
  func testInstalledPhotoshop2026PresetsMatchNativeSettings() throws {
    let root = URL(
      fileURLWithPath: "/Applications/Adobe Photoshop 2026/Presets/Levels", isDirectory: true)
    guard FileManager.default.fileExists(atPath: root.path) else {
      throw XCTSkip(
        "Direct preset reference qualification requires the installed Photoshop 2026 app.")
    }
    for preset in BuiltInLevelsPreset.allCases where preset != .standard {
      let data = try Data(contentsOf: root.appendingPathComponent(preset.rawValue + ".alv"))
      XCTAssertEqual(data.count, 630)
      let actual = try LevelsPresetCodec.read(data)
      XCTAssertEqual(actual, preset.levels, preset.rawValue)
      XCTAssertEqual(try LevelsPresetCodec.write(actual, original: data), data)
    }
  }
}
