import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GradientMapRenderTests: XCTestCase {
  func fixture(_ method: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "photoshop-gradient-map-\(method)-rgb8", withExtension: "psd",
          subdirectory: "Fixtures")))
  }
  func record(_ bytes: Data) throws -> Data {
    let at = try XCTUnwrap(bytes.range(of: Data("8BIMgrdm".utf8))).upperBound
    var r = PSDReader(data: bytes, offset: at)
    return try r.bytes(r.u32())
  }
  func testPhotoshopSavedRGB8ControlsAndMeasuredPixelDeltas() throws {
    var reports: [[String: Any]] = []
    for method: GradientMethod in [.classic, .linear, .perceptual] {
      let bytes = try fixture(method.rawValue.lowercased())
      let source = try record(bytes)
      let settings = try PSDGradientMap.read(source)
      XCTAssertEqual(settings.gradient.method, method)
      XCTAssertEqual(settings.gradient.smoothness, 1)
      XCTAssertFalse(settings.reverse)
      XCTAssertFalse(settings.dither)
      XCTAssertEqual(try PSDGradientMap.write(settings, original: source), source)
      let document = try PSDCodec.read(bytes)
      let result = try Renderer.composite(document)
      var reader = PSDReader(data: bytes, offset: 26)
      for _ in 0..<3 { _ = try reader.section() }
      let planes = try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: 256, height: 64, depth: 8, channels: 4)
      var changed = 0
      var maximum: Float = 0
      var grayChanged = 0
      var alphaChanged = 0
      for y in 0..<64 {
        for x in 0..<256 {
          let actual = PSDMergedSample.encode(result.pixel(x: x, y: y), depth: 8).quantized(.u8)
          var differs = false
          for (c, value) in [actual.r, actual.g, actual.b, actual.a].enumerated() {
            let expected = try PSDChannelCodec.sample(planes, c * 16384 + y * 256 + x, depth: 8)
            if value != expected {
              differs = true
              if c == 3 { alphaChanged += 1 }
            }
            maximum = max(maximum, abs(value - expected))
          }
          if differs {
            changed += 1
            if y < 8 { grayChanged += 1 }
          }
        }
      }
      reports.append([
        "byte_identical": changed == 0, "method": method.rawValue, "changed_pixels": changed,
        "gray_changed_pixels": grayChanged,
        "maximum_channel_steps": maximum * 255, "alpha_changed_samples": alphaChanged,
      ])
      print(
        "Gradient Map Photoshop \(method.rawValue): changed \(changed)/16384; gray \(grayChanged)/2048; max \(maximum * 255) levels; alpha \(alphaChanged)"
      )
      XCTAssertEqual(alphaChanged, 0)
      if method == .classic { XCTAssertEqual(grayChanged, 0) }
      // These fixtures expose remaining one-level differences; this is a bounded
      // regression check, not a claim of full Photoshop pixel equivalence.
      XCTAssertLessThanOrEqual(changed, method == .classic ? 38 : method == .linear ? 285 : 270)
      XCTAssertLessThanOrEqual(maximum, 1.01 / 255)
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/gradient-map-photoshop-comparison.json"))
  }
  func testUnsupportedNewMethodsAndMalformedRecordsDoNotFallBack() throws {
    for method in ["smooth"] {
      let bytes = try fixture(method)
      XCTAssertThrowsError(try PSDGradientMap.read(record(bytes))) { error in
        guard case CraftError.unsupported(let message) = error else { return XCTFail("\(error)") }
        XCTAssertTrue(message.contains("method"))
      }
    }
    let source = try record(fixture("classic"))
    for size in 0..<source.count - 3 {
      XCTAssertThrowsError(try PSDGradientMap.read(source.prefix(size)), "\(size)")
    }
    var bad = source
    bad[2] = 255
    XCTAssertThrowsError(try PSDGradientMap.read(bad))
  }
  func testLegacyVersionAndColorModelsRetainControls() throws {
    var legacy = try record(fixture("classic"))
    legacy[1] = 1
    legacy.removeSubrange(4..<8)
    let old = try PSDGradientMap.read(legacy)
    XCTAssertEqual(old.gradient.method, .classic)
    XCTAssertEqual(try PSDGradientMap.write(old, original: legacy), legacy)
    var value = GradientMapAdjustment(
      gradient: .init(
        name: "Map ✓",
        colors: [
          .init(0, .gray(ink: 0.25)),
          .init(1, .hsb(hue: 120, saturation: 1, brightness: 1), midpoint: 0.3),
        ], opacity: [.init(0, 0.2), .init(1, 1)], smoothness: 0.5, method: .linear), reverse: true)
    let record = try PSDGradientMap.write(value)
    let restored = try PSDGradientMap.read(record)
    XCTAssertEqual(restored, value)
    XCTAssertEqual(try PSDGradientMap.write(restored), record)
    value.gradient.colors[0].color = .foreground
    XCTAssertThrowsError(try PSDGradientMap.write(value))
  }
  func testEditablePSDAndArchiveAtAllDepthsAndRegionalDither() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 9, height: 7, depth: depth)
      doc.layers[0].content = .raster(
        try Surface(width: 9, height: 7, depth: depth, fill: Pixel(0.24, 0.57, 0.81, 0.75)))
      var gradient = GradientDefinition.blackToWhite
      gradient.method = .classic
      gradient.smoothness = 0.75
      gradient.opacity = [.init(0, 0), .init(1, 0)]
      let map = GradientMapAdjustment(gradient: gradient, reverse: true, dither: true)
      var layer = Layer(name: "Gradient Map", content: .adjustment(.gradientMap(map)))
      layer.opacity = 128.0 / 255
      layer.mask = try Surface(width: 9, height: 7, depth: depth, fill: .white)
      doc.layers.append(layer)
      doc.activeLayerID = layer.id
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(doc)), doc)
      if depth == .f32 {
        XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc))
      } else {
        let bytes = try PSDCodec.writeRasterLayers(doc)
        if depth == .u8 {
          let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
          try bytes.write(to: root.appendingPathComponent("artifacts/native-gradient-map-rgb8.psd"))
        }
        let restored = try PSDCodec.read(bytes)
        XCTAssertEqual(restored.layers[1].content, layer.content)
      }
      let full = try Renderer.render(doc)
      doc.layers[1].mask?.setPixel(x: 4, y: 3, .black)
      let partial = try Renderer.render(doc, reusing: full)
      XCTAssertEqual(
        try partial.surface.rgbaData(depth: .f32), try Renderer.composite(doc).rgbaData(depth: .f32)
      )
      let pixel = partial.surface.pixel(x: 4, y: 3)
      XCTAssertEqual(pixel.a, full.surface.pixel(x: 4, y: 3).a)
    }
  }
}
