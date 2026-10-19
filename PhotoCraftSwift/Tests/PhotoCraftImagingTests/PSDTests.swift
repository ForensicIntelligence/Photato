import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6)
    let base = Layer(
      name: "Base", content: .raster(try Surface(width: 8, height: 6, fill: Pixel(0.2, 0.3, 0.4))))
    var top = Layer(
      name: "日本語 Ink",
      content: .raster(try Surface(width: 3, height: 2, fill: Pixel(0.9, 0.1, 0.3, 0.7))))
    top.x = 2
    top.y = 1
    top.opacity = 0.6
    top.blendMode = .multiply
    d.layers = [base, top]
    d.activeLayerID = top.id
    return d
  }
  func testLayeredPSDRoundTrip() throws {
    let original = try fixture()
    let data = try PSDCodec.writeRasterLayers(original)
    let decoded = try PSDCodec.read(data)
    XCTAssertEqual(decoded.layers.map(\.name), original.layers.map(\.name))
    XCTAssertEqual(decoded.layers[1].x, 2)
    XCTAssertEqual(decoded.layers[1].blendMode, .multiply)
    let a = try Renderer.composite(original)
    let b = try Renderer.composite(decoded)
    for y in 0..<6 {
      for x in 0..<8 {
        let p = a.pixel(x: x, y: y)
        let q = b.pixel(x: x, y: y)
        XCTAssertEqual(p.r, q.r, accuracy: 0.006)
        XCTAssertEqual(p.g, q.g, accuracy: 0.006)
        XCTAssertEqual(p.b, q.b, accuracy: 0.006)
      }
    }
  }
  func testExportOpensInIndependentApplePSDDecoder() throws {
    let original = try fixture()
    let data = try PSDCodec.writeRasterLayers(original)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, 8)
    XCTAssertEqual(image.height, 6)
    let actual = try RasterIO.surface(image)
    let expected = try Renderer.composite(original)
    XCTAssertEqual(actual.pixel(x: 3, y: 2).r, expected.pixel(x: 3, y: 2).r, accuracy: 0.008)
  }
  func testPackBitsAndMalformedRuns() throws {
    XCTAssertEqual(
      try PSDCodec.decodePackBits(Data([2, 10, 20, 30, 254, 7]), expected: 6),
      [10, 20, 30, 7, 7, 7])
    XCTAssertEqual(try PSDCodec.decodePackBits(Data([128, 0, 9]), expected: 1), [9])
    for bytes: [UInt8] in [[], [3, 1, 2], [250, 1], [0], [0, 1, 99]] {
      XCTAssertThrowsError(try PSDCodec.decodePackBits(Data(bytes), expected: 1))
    }
  }
  func testTruncatedPSDAndUnsupportedLayersReject() throws {
    let data = try PSDCodec.writeRasterLayers(fixture())
    for n in [0, 4, 26, 60, data.count / 2, data.count - 1] {
      XCTAssertThrowsError(try PSDCodec.read(data.prefix(n)))
    }
    var bad = data
    bad[5] = 2
    XCTAssertThrowsError(try PSDCodec.read(bad))
    bad = data
    bad[23] = 16
    XCTAssertThrowsError(try PSDCodec.read(bad))
    var rich = try CraftDocument(width: 8, height: 6)
    rich.layers.append(Layer(name: "Type", content: .text(TextContent(text: "Rich"))))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(rich))
  }
}
extension PSDTests {
  func testDeterministicMutationCorpusDoesNotTrap() throws {
    let valid = try PSDCodec.writeRasterLayers(fixture())
    var seed: UInt64 = 0x504344
    for _ in 0..<200 {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      var data = valid
      let position = Int(seed % UInt64(data.count))
      data[position] ^= UInt8(truncatingIfNeeded: seed >> 32)
      do {
        let doc = try PSDCodec.read(data)
        try doc.validate()
      } catch { /* Rejection is expected for corrupt fields. */  }
    }
  }
}

extension PSDTests {
  func testPhotoshop2026AuthoredMaskFixtureMatchesItsMergedImage() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-mask-raster", withExtension: "psd", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let d = try PSDCodec.read(data)
    XCTAssertEqual(d.layers.map(\.name), ["Background", "Background copy", "Shape 1"])
    let mask = try XCTUnwrap(d.layers[1].mask)
    XCTAssertEqual(mask.width, 71)
    XCTAssertEqual(mask.height, 57)
    XCTAssertEqual(d.layers[1].maskCoordinateTransform, .translation(23, 10))
    let composite = try Renderer.composite(d)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let expected = try RasterIO.surface(image)
    var maxError: Float = 0
    for y in 0..<d.height {
      for x in 0..<d.width {
        let p = composite.pixel(x: x, y: y)
        let q = expected.pixel(x: x, y: y)
        maxError = max(maxError, abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
      }
    }
    XCTAssertLessThanOrEqual(maxError, 2.0 / 255)
  }
  func testMaskExportRoundTripKeepsPropertiesAndEditableChannel() throws {
    var d = try fixture()
    d.layers[1].mask = try Surface(width: 2, height: 1, fill: .black)
    d.layers[1].mask?.setPixel(x: 0, y: 0, .white)
    var p = MaskProperties()
    p.transform = .translation(1, -1)
    p.density = 128.0 / 255
    p.feather = 1.5
    p.linked = false
    p.enabled = false
    p.outside = 1
    d.layers[1].maskProperties = p
    d.layers[1].sourceTags = ["lclr": Data(repeating: 0, count: 8)]
    let result = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(result.layers[1].maskProperties, p)
    XCTAssertEqual(result.layers[1].mask?.pixel(x: 0, y: 0), .white)
    XCTAssertEqual(result.layers[1].mask?.pixel(x: 1, y: 0), .black)
    XCTAssertEqual(result.layers[1].sourceTags?["lclr"], d.layers[1].sourceTags?["lclr"])
    d.layers[1].maskProperties?.enabled = true
    let data = try PSDCodec.writeRasterLayers(d)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let actual = try RasterIO.surface(image)
    let expected = try Renderer.composite(d)
    XCTAssertEqual(actual.pixel(x: 3, y: 1).r, expected.pixel(x: 3, y: 1).r, accuracy: 0.008)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    try data.write(to: root.appendingPathComponent("artifacts/native-mask-export.psd"))
  }
  func testMaskMetadataFromIndependentFilesBothParameterOrders() throws {
    func data(_ hex: String) -> Data {
      Data(
        stride(from: 0, to: hex.count, by: 2).map { i in
          UInt8(
            hex[
              hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 2)],
            radix: 16)!
        })
    }
    // Exact sections from pinned psd-tools mask-density-layermask and layer_mask_data.
    let density = try XCTUnwrap(
      PSDMaskRecord.read(data("0000001900000001000000210000001800100140")))
    XCTAssertEqual(density.density, 64)
    XCTAssertEqual(density.bounds.x, 1)
    XCTAssertEqual(density.bounds.height, 8)
    let complex = try XCTUnwrap(
      PSDMaskRecord.read(
        data(
          "0000008d0000000c000000bf000000bc001800ff0000009200000024000000ba000000aa0bbf400800000000000040000000000000000000"
        )))
    XCTAssertEqual(complex.density, 191)
    XCTAssertEqual(complex.feather, 3)
    XCTAssertEqual(complex.vectorFeather, 2)
    XCTAssertEqual(complex.real?.bounds.x, 36)
    // The published format puts parameters before the real-mask fields.
    let realFirst = data(
      "0000008d0000000c000000bf000000bc001800ff0000009200000024000000ba000000aa0bbf400800000000000040000000000000000000"
    )
    let reordered =
      Data(realFirst.prefix(18)) + realFirst.subdata(in: 36..<realFirst.count - 2)
      + realFirst.subdata(in: 18..<36) + realFirst.suffix(2)
    let parameterFirst = try XCTUnwrap(PSDMaskRecord.read(reordered))
    XCTAssertEqual(parameterFirst.feather, complex.feather)
    XCTAssertEqual(parameterFirst.density, complex.density)
    XCTAssertEqual(parameterFirst.real?.bounds.x, complex.real?.bounds.x)
    let noReal = try XCTUnwrap(
      PSDMaskRecord.read(
        data("00000000000000000000010000000100ff100e4008000000000000bf4018000000000000")))
    XCTAssertNil(noReal.real)
    XCTAssertEqual(noReal.feather, 3)
    XCTAssertEqual(noReal.vectorDensity, 191)
    XCTAssertEqual(noReal.vectorFeather, 6)
    XCTAssertThrowsError(try PSDMaskRecord.read(data("00000000000000000000010000000100ff100e4008")))
  }
}

extension PSDTests {
  func testPhotoshopResavedFeatherAndDensityComposite() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-mask-feather", withExtension: "psd", subdirectory: "Fixtures"))
    let data = try Data(contentsOf: url)
    let d = try PSDCodec.read(data)
    XCTAssertEqual(d.layers.map(\.name), ["Base", "日本語 Ink"])
    XCTAssertEqual(d.layers[1].effectiveMaskProperties.feather, 1.5)
    XCTAssertEqual(d.layers[1].effectiveMaskProperties.density, 128.0 / 255, accuracy: 1.0 / 255)
    XCTAssertFalse(d.layers[1].effectiveMaskProperties.linked)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let expected = try RasterIO.surface(image)
    let actual = try Renderer.composite(d)
    var maximum: Float = 0
    for y in 0..<d.height {
      for x in 0..<d.width {
        let p = actual.pixel(x: x, y: y)
        let q = expected.pixel(x: x, y: y)
        maximum = max(maximum, abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
      }
    }
    XCTAssertLessThanOrEqual(maximum, 2.0 / 255)
  }
}
