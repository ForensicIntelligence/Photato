import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class GradientStripesRenderTests: XCTestCase {
  private var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }
  func fixture(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: name, withExtension: "psd", subdirectory: "Fixtures")))
  }
  func writeProbe(_ data: Data, name: String) throws {
    let folder = root.appendingPathComponent("artifacts/gradient-method-reference")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try data.write(to: folder.appendingPathComponent(name))
  }
  func testPhotoshopTwoAndThreeStopStripesPixels() throws {
    var reports: [[String: Any]] = []
    for name in [
      "photoshop-gradient-map-stripes-rgb8", "photoshop-stripes-three-stop-rgb8",
      "photoshop-stripes-fill-three-stop-rgb8",
    ] {
      let bytes = try fixture(name)
      let document = try PSDCodec.read(bytes)
      let surface = try Renderer.composite(document)
      var reader = PSDReader(data: bytes, offset: 26)
      for _ in 0..<3 { _ = try reader.section() }
      let planes = try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: 256, height: 64, depth: 8, channels: 4)
      var changed = 0
      var maximum: Float = 0
      for y in 0..<64 {
        for x in 0..<256 {
          let p = PSDMergedSample.encode(surface.pixel(x: x, y: y), depth: 8).quantized(.u8)
          var differs = false
          for (c, value) in [p.r, p.g, p.b, p.a].enumerated() {
            let expected = try PSDChannelCodec.sample(planes, c * 16384 + y * 256 + x, depth: 8)
            differs = differs || value != expected
            maximum = max(maximum, abs(value - expected))
          }
          if differs { changed += 1 }
        }
      }
      print("Stripes Photoshop \(name): \(changed)/16384 changed; max \(maximum * 255) levels")
      reports.append([
        "name": name, "changed_pixels": changed,
        "maximum_channel_steps": maximum * 255, "byte_identical": changed == 0,
      ])
      XCTAssertEqual(changed, 0)
    }
    try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
      .write(
        to: root.appendingPathComponent("artifacts/gradient-stripes-photoshop-comparison.json"))
  }

  func testCoincidentMapStopsPersistAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 256, height: 8, depth: depth)
      var surface = try Surface(width: 256, height: 8, depth: depth)
      for y in 0..<8 {
        for x in 0..<256 {
          var p = Pixel(Float(x) / 255, Float(x) / 255, Float(x) / 255, y < 4 ? 1 : 0.5)
          if y == 1 || y == 5 { p = Pixel(0, 179.0 / 255, 199.0 / 255, p.a) }
          if depth == .f32 { p = SRGBTransfer.encoded(p) }
          surface.setPixel(x: x, y: y, p)
        }
      }
      let gradient = GradientDefinition(
        name: "Original coincident probe",
        colors: [
          .init(0.125, .rgb(Pixel(1, 0, 0))), .init(0.5, .rgb(Pixel(0, 1, 0))),
          .init(0.5, .rgb(Pixel(0, 0, 1))), .init(0.875, .rgb(.white)),
        ], method: .stripes)
      doc.layers[0].content = .raster(surface)
      doc.layers.append(
        Layer(
          name: "Coincident Stripes", content: .adjustment(.gradientMap(.init(gradient: gradient))))
      )
      doc.activeLayerID = doc.layers[1].id
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(doc)), doc)
      if depth == .f32 {
        XCTAssertThrowsError(try PSDCodec.writeRasterLayers(doc)) { error in
          XCTAssertTrue(error.localizedDescription.contains("32-bit"))
        }
        continue
      }
      let bytes = try PSDCodec.writeRasterLayers(doc)
      XCTAssertEqual(try PSDCodec.read(bytes).layers[1].content, doc.layers[1].content)
      let bits = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      try writeProbe(bytes, name: "native-stripes-coincident-rgb\(bits).psd")
    }
  }

  func testPhotoshopCoincidentBoundariesAndLegacyRGB32Retention() throws {
    var reports: [[String: Any]] = []
    for depth in [8, 16] {
      let bytes = try fixture("photoshop-stripes-coincident-rgb\(depth)")
      let doc = try PSDCodec.read(bytes)
      let surface = try Renderer.composite(doc)
      var reader = PSDReader(data: bytes, offset: 26)
      for _ in 0..<3 { _ = try reader.section() }
      let reference = try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: 256, height: 8, depth: depth, channels: 4)
      var actual: [UInt8] = []
      for c in 0..<4 {
        for y in 0..<8 {
          for x in 0..<256 {
            let p = PSDMergedSample.encode(surface.pixel(x: x, y: y), depth: depth)
            try PSDChannelCodec.append([p.r, p.g, p.b, p.a][c], depth: depth, to: &actual)
          }
        }
      }
      let changed = zip(actual, reference).filter { $0 != $1 }.count
      var changedPixels = 0
      var changedOpaque = 0
      var changedAlpha = 0
      var maximum: Float = 0
      for i in 0..<2048 {
        var differs = false
        let alpha = try PSDChannelCodec.sample(reference, 3 * 2048 + i, depth: depth)
        for c in 0..<4 {
          let a = try PSDChannelCodec.sample(actual, c * 2048 + i, depth: depth)
          let b = try PSDChannelCodec.sample(reference, c * 2048 + i, depth: depth)
          maximum = max(maximum, abs(a - b))
          differs = differs || a != b
          if c == 3 && a != b { changedAlpha += 1 }
        }
        if differs {
          changedPixels += 1
          if alpha == 1 { changedOpaque += 1 }
        }
      }
      reports.append([
        "depth": depth, "changed_bytes": changed, "byte_identical": actual == reference,
        "changed_pixels": changedPixels, "changed_opaque_pixels": changedOpaque,
        "changed_alpha_samples": changedAlpha,
        "maximum_channel_steps": maximum * (depth == 8 ? 255 : 65535),
      ])
      print("Stripes Photoshop coincident RGB\(depth): \(changed) changed stored bytes")
      XCTAssertEqual(actual.count, reference.count)
      XCTAssertEqual(changedOpaque, 0)
      XCTAssertEqual(changedAlpha, 0)
      XCTAssertEqual(changedPixels, 0)
      XCTAssertEqual(maximum, 0)
      XCTAssertEqual(changed, 0)
    }
    try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/gradient-stripes-depth-comparison.json"))
    let legacy = try PSDCodec.read(fixture("native-stripes-legacy-rgb32"))
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(legacy)), legacy)
    XCTAssertNoThrow(try Renderer.composite(legacy))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(legacy))
  }

  func testStripesFillTransportAndNativeArchive() throws {
    let doc = try PSDCodec.read(fixture("photoshop-stripes-three-stop-rgb8"))
    let map = try XCTUnwrap(
      doc.layers.compactMap { layer -> GradientMapAdjustment? in
        if case .adjustment(.gradientMap(let value)) = layer.content { return value }
        return nil
      }.first)
    XCTAssertEqual(map.gradient.method, .stripes)
    XCTAssertEqual(map.gradient.colors.count, 3)
    XCTAssertEqual(map.gradient.opacity.count, 3)
    var fillDoc = try CraftDocument(width: 256, height: 64)
    var fill = GradientFill(gradient: map.gradient, aligned: false, dither: false)
    fill.placement.angle = 0
    fillDoc.layers = [Layer(name: "Original Stripes Fill", content: .gradientFill(fill))]
    fillDoc.activeLayerID = fillDoc.layers[0].id
    let bytes = try PSDCodec.writeRasterLayers(fillDoc)
    let restored = try PSDCodec.read(bytes)
    XCTAssertEqual(restored.layers[0].content, fillDoc.layers[0].content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(fillDoc)), fillDoc)
    try writeProbe(bytes, name: "native-stripes-fill-input-rgb8.psd")
  }

  func testPhotoshopOmittedAngleAndInactiveSeedSurviveEdits() throws {
    let file = try fixture("photoshop-stripes-fill-three-stop-rgb8")
    let at = try XCTUnwrap(file.range(of: Data("8BIMGdFl".utf8))).upperBound
    var r = PSDReader(data: file, offset: at)
    let bytes = try r.bytes(r.u32())
    var descriptor = try PSDDescriptor.read(bytes, padding: true)
    XCTAssertNil(descriptor["Angl"])
    XCTAssertEqual(descriptor["noisePreSeed"], .integer(10000))
    var fill = try PSDGradientFill.read(bytes)
    XCTAssertEqual(fill.placement.angle, 0)
    XCTAssertEqual(try PSDGradientFill.write(fill, original: bytes), bytes)
    fill.placement.angle = 35
    let edited = try PSDGradientFill.write(fill, original: bytes)
    XCTAssertEqual(try PSDGradientFill.read(edited), fill)
    XCTAssertEqual(try PSDDescriptor.read(edited)["noisePreSeed"], .integer(10000))
    PSDGradient.set(&descriptor, "Dthr", .boolean(true))
    XCTAssertThrowsError(try PSDGradientFill.read(descriptor.encoded()))
    PSDGradient.set(&descriptor, "Dthr", .boolean(false))
    PSDGradient.set(&descriptor, "noisePreSeed", .boolean(true))
    XCTAssertThrowsError(try PSDGradientFill.read(descriptor.encoded()))
  }

  func testEmptyGeneratedMaskIsIdentityButUnsupportedMasksStillReject() throws {
    let bytes = try fixture("photoshop-stripes-coincident-rgb8")
    let doc = try PSDCodec.read(bytes)
    XCTAssertTrue(doc.layers.allSatisfy { $0.mask == nil && $0.vectorMask == nil })
    let needle = Data(repeating: 0, count: 16) + Data([255, 8, 0, 0])
    let range = try XCTUnwrap(bytes.range(of: needle))
    XCTAssertNil(bytes.range(of: needle, in: range.upperBound..<bytes.count))
    for (offset, value): (Int, UInt8) in [(16, 0), (17, 12)] {
      var changed = bytes
      changed[range.lowerBound + offset] = value
      XCTAssertThrowsError(try PSDCodec.read(changed))
    }
  }
}
