import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDTonalStepsTests: XCTestCase {
  func testIndependentRecordsPaddingValidationAndStaleMetadata() throws {
    for kind in TonalStepsAdjustment.Kind.allCases {
      let value = TonalStepsAdjustment(kind: kind)
      let bytes = Data([0, UInt8(value.level), 0, 0])
      XCTAssertEqual(try PSDTonalSteps.read(bytes, kind: kind), value)
      XCTAssertEqual(try PSDTonalSteps.write(value), bytes)
      var padded = bytes
      padded[2] = 123
      padded[3] = 231
      XCTAssertEqual(try PSDTonalSteps.write(value, original: padded), padded)
      XCTAssertEqual(
        try PSDTonalSteps.write(.init(kind: kind, level: 7), original: padded), Data([0, 7, 0, 0]))
      for count in 0..<4 {
        XCTAssertThrowsError(try PSDTonalSteps.read(bytes.prefix(count), kind: kind))
      }
      for bad in [Data([0, 0, 0, 0]), Data([1, 0, 0, 0]), bytes + Data([0])] {
        XCTAssertThrowsError(try PSDTonalSteps.read(bad, kind: kind))
      }
    }
    var d = try CraftDocument(width: 2, height: 2)
    var layer = Layer(name: "Threshold", content: .adjustment(.tonalSteps(.init(kind: .threshold))))
    layer.sourceTags = ["thrs": Data([0, 128, 0, 0])]
    d.layers.append(layer)
    d.layers[1].content = .adjustment(.tonalSteps(.init(kind: .posterize, level: 7)))
    let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertNil(reopened.layers[1].sourceTags?["thrs"])
    XCTAssertEqual(reopened.layers[1].sourceTags?["post"], Data([0, 7, 0, 0]))
    d.layers[1].content = .raster(try Surface(width: 2, height: 2, fill: .white))
    XCTAssertNil(try PSDCodec.read(PSDCodec.writeRasterLayers(d)).layers[1].sourceTags?["thrs"])
  }
  func testEditablePSDAllDepthsGroupsMasksClippingAndNativeArchive() throws {
    for depth in PixelDepth.allCases {
      for kind in TonalStepsAdjustment.Kind.allCases {
        var d = try CraftDocument(width: 4, height: 3, depth: depth)
        d.layers[0].content = .raster(
          try Surface(width: 4, height: 3, depth: depth, fill: Pixel(0.334, 0.8, 0.2)))
        let group = Layer(name: "Group", content: .group(.init(passThrough: false)))
        d.layers[0].parentID = group.id
        var layer = Layer(name: kind.rawValue, content: .adjustment(.tonalSteps(.init(kind: kind))))
        layer.parentID = group.id
        layer.clipped = true
        layer.opacity = 128.0 / 255
        layer.mask = try Surface(width: 2, height: 3, depth: depth, fill: Pixel(0.5, 0.5, 0.5))
        layer.maskProperties = .init()
        layer.maskProperties?.transform = .translation(1, 0)
        d.layers.append(contentsOf: [layer, group])
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
        let bytes = try PSDCodec.writeRasterLayers(d)
        let restored = try PSDCodec.read(bytes)
        XCTAssertEqual(restored.layers[1].content, layer.content)
        XCTAssertTrue(restored.layers[1].isClipped)
        XCTAssertEqual(restored.layers[1].parentID, restored.layers[2].id)
        XCTAssertEqual(restored.layers[1].maskCoordinateTransform, layer.maskCoordinateTransform)
        let a = try Renderer.composite(d)
        let b = try Renderer.composite(restored)
        for y in 0..<3 {
          for x in 0..<4 {
            let p = a.pixel(x: x, y: y)
            let q = b.pixel(x: x, y: y)
            XCTAssertEqual(p.r, q.r, accuracy: 0.0001)
            XCTAssertEqual(p.g, q.g, accuracy: 0.0001)
            XCTAssertEqual(p.b, q.b, accuracy: 0.0001)
          }
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 3)
      }
    }
  }
  func testPinnedPhotoshopRGB8AndRGB16CompositesAndSettings() throws {
    let fixtures: [(String, String, Float, Int)] = [
      (
        "posterize_rgb", "7e97af29a928e43e0c16baeb3b60483574774e2d7f23667ab07a3affeb83048a", 0.003,
        1
      ),
      (
        "posterize_16bits_rgb", "f349d0e2e253e1d7b3dcd8645d555a1605b7e2d6bba1b99de164ab7853e4871c",
        0.00002, 4
      ),
      (
        "threshold_rgb", "d61e095b3bf816a39eac075243ca0cadeb1922411b14db13c3fda598b741c5f0", 0.003,
        1
      ),
      (
        "threshold_16bits_rgb", "db8191826e0ca11fdf0961abd9acfa9fbb31b3edca5fc7492f5c0b6766d13559",
        0.00002, 3
      ),
    ]
    var records = 0
    var reports: [[String: Any]] = []
    for (name, hash, maxError, maxChanged) in fixtures {
      let file = try XCTUnwrap(
        Bundle.module.url(
          forResource: "psdtools-" + name, withExtension: "psd", subdirectory: "Fixtures"))
      let data = try Data(contentsOf: file)
      XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), hash)
      let d = try PSDCodec.read(data)
      let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      for (i, l) in d.layers.enumerated() {
        if case .adjustment(.tonalSteps(let a)) = l.content {
          let key = PSDTonalSteps.key(a.kind)
          XCTAssertEqual(saved.layers[i].sourceTags?[key], l.sourceTags?[key])
          XCTAssertEqual(saved.layers[i].content, l.content)
          records += 1
        }
      }
      let image = try XCTUnwrap(
        CGImageSourceCreateImageAtIndex(
          try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil)), 0, nil))
      let expected = try RasterIO.surface(image, depth: d.depth)
      let actual = try Renderer.composite(d)
      var maximum: Float = 0
      var sum: Double = 0
      var changed = 0
      for y in 0..<d.height {
        for x in 0..<d.width {
          let p = actual.pixel(x: x, y: y)
          let q = expected.pixel(x: x, y: y)
          let e = max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
          maximum = max(maximum, e)
          sum += Double(e)
          if p.quantized(d.depth) != q.quantized(d.depth) { changed += 1 }
        }
      }
      // Tight regression ceilings, not a substitute for the zero-difference goal.
      XCTAssertLessThanOrEqual(maximum, maxError, name)
      XCTAssertLessThanOrEqual(changed, maxChanged, name)
      reports.append([
        "file": name + ".psd", "maximum_encoded_error": maximum, "differing_pixels": changed,
        "pixels": d.width * d.height, "mean_pixel_max_error": sum / Double(d.width * d.height),
        "exact_at_document_depth": changed == 0,
      ])
    }
    XCTAssertEqual(records, 16)
    try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
      .write(
        to: PSDSolidColorTests.root.appendingPathComponent("artifacts/tonal-steps-reference.json"))
  }
}
