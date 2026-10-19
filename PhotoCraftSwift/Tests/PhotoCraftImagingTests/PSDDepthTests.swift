import CoreGraphics
import ImageIO
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDDepthTests: XCTestCase {
  struct Vectors: Decodable {
    struct Vector: Decodable {
      var depth: Int
      var width: Int
      var height: Int
      var channels: Int
      var compression: Int
      var raw: Data
      var encoded: Data
    }
    var vectors: [Vector]
  }
  func vectors() throws -> [Vectors.Vector] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "psd-channel-oracles", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url)).vectors
  }
  func testAllDepthsAndCompressionAgainstIndependentPythonVectors() throws {
    for v in try vectors() {
      let decoded = try PSDChannelCodec.decode(
        v.encoded, width: v.width, height: v.height, depth: v.depth, channels: v.channels)
      XCTAssertEqual(Data(decoded), v.raw, "\(v.depth)/\(v.compression)")
      if let compression = PSDCompression(rawValue: v.compression) {
        let plane = Array(v.raw.prefix(v.width * v.height * v.depth / 8))
        let encoded = try PSDChannelCodec.encode(
          plane, width: v.width, height: v.height, depth: v.depth, compression: compression)
        XCTAssertEqual(
          try PSDChannelCodec.decode(encoded, width: v.width, height: v.height, depth: v.depth),
          plane)
      }
    }
  }
  func testZIPRejectsTruncationChecksumTrailingAndInflatedSizeMismatch() throws {
    for v in try vectors() where v.compression >= 2 {
      func read(_ bytes: Data, width: Int? = nil) throws {
        _ = try PSDChannelCodec.decode(
          bytes, width: width ?? v.width, height: v.height, depth: v.depth, channels: v.channels)
      }
      for length in [0, 2, 5, v.encoded.count - 1] {
        XCTAssertThrowsError(try read(v.encoded.prefix(length)))
      }
      var corrupt = v.encoded
      corrupt[corrupt.count - 1] ^= 1
      XCTAssertThrowsError(try read(corrupt))
      XCTAssertThrowsError(try read(v.encoded + Data([0])))
      XCTAssertThrowsError(try read(v.encoded, width: v.width - 1))
      XCTAssertThrowsError(try read(v.encoded, width: v.width + 1))
    }
    XCTAssertThrowsError(
      try PSDChannelCodec.decode(Data([0, 2]), width: Int.max, height: 1, depth: 32))
    XCTAssertThrowsError(try PSDChannelCodec.sample([0x7f, 0x80, 0, 0], 0, depth: 32))
    XCTAssertThrowsError(try PSDChannelCodec.sample([0x7f, 0xc0, 0, 0], 0, depth: 32))
  }
  func testThinLayerMemoryBudgetAccountsForWholeTilesBeforeDecoding() throws {
    // A one-pixel row still allocates 64-pixel-high tiles. Reject the total
    // before touching deliberately absent channel payloads.
    var info = PSDWriter()
    info.n(18, 2)
    for _ in 0..<18 {
      for value in [0, 0, 1, 30000] { info.n(value, 4) }
      info.n(3, 2)
      for id in 0..<3 {
        info.n(id, 2)
        info.n(2, 4)
      }
      info.text("8BIM")
      info.text("norm")
      info.n(255, 1)
      info.n(0, 3)
      var extra = PSDWriter()
      extra.n(0, 4)
      extra.n(0, 4)
      extra.n(0, 4)
      info.section(extra.data)
    }
    var layers = PSDWriter()
    layers.section(info.data)
    layers.n(0, 4)
    var file = PSDWriter()
    file.text("8BPS")
    file.n(1, 2)
    file.n(0, 6)
    file.n(3, 2)
    file.n(1, 4)
    file.n(1, 4)
    file.n(8, 2)
    file.n(3, 2)
    file.n(0, 4)
    file.n(0, 4)
    file.section(layers.data)
    file.n(0, 5)
    XCTAssertThrowsError(try PSDCodec.read(file.data)) { error in
      XCTAssertTrue(error.localizedDescription.contains("memory"), error.localizedDescription)
    }
  }
  func document(_ depth: PixelDepth) throws -> CraftDocument {
    var doc = try CraftDocument(width: 96, height: 64, depth: depth, name: "Depth reference")
    var base = try Surface(width: 96, height: 64, depth: depth)
    for y in 0..<64 {
      for x in 0..<96 {
        base.setPixel(x: x, y: y, Pixel(Float(x) / 95, Float(y) / 63, 0.23456))
      }
    }
    var top = try Surface(width: 48, height: 32, depth: depth)
    for y in 0..<32 {
      for x in 0..<48 {
        top.setPixel(x: x, y: y, Pixel(0.81234, 0.12345, 0.43210, Float(x + 1) / 48))
      }
    }
    var layer = Layer(name: "Precision", content: .raster(top))
    layer.x = 13
    layer.y = 9
    var mask = try Surface(width: 25, height: 20, depth: depth)
    for y in 0..<20 {
      for x in 0..<25 {
        let v = Float(x + 1) / 25
        mask.setPixel(x: x, y: y, Pixel(v, v, v))
      }
    }
    layer.mask = mask
    layer.maskProperties = MaskProperties()
    layer.maskProperties?.transform = .translation(3, 4)
    doc.layers = [Layer(name: "Gradient", content: .raster(base)), layer]
    doc.activeLayerID = layer.id
    return doc
  }
  func testHighDepthLayerMaskPrecisionRoundTrips() throws {
    for depth in PixelDepth.allCases {
      let d = try document(depth)
      for compression in PSDCompression.allCases {
        let bytes = try PSDCodec.writeRasterLayers(d, compression: compression)
        let result = try PSDCodec.read(bytes)
        XCTAssertEqual(result.depth, depth)
        XCTAssertEqual(result.layers.map(\.name), ["Gradient", "Precision"])
        let mask = try XCTUnwrap(result.layers[1].mask)
        let originalMask = try XCTUnwrap(d.layers[1].mask)
        XCTAssertEqual(mask.depth, depth)
        XCTAssertEqual(mask.width, originalMask.width)
        XCTAssertEqual(mask.height, originalMask.height)
        for y in 0..<mask.height {
          for x in 0..<mask.width {
            XCTAssertEqual(mask.pixel(x: x, y: y), originalMask.pixel(x: x, y: y))
          }
        }
        for i in 0..<d.layers.count {
          guard case .raster(let a) = d.layers[i].content,
            case .raster(let b) = result.layers[i].content
          else { return XCTFail("Missing raster") }
          XCTAssertEqual(a.depth, b.depth)
          for y in 0..<a.height {
            for x in 0..<a.width {
              let p = a.pixel(x: x, y: y)
              let q = b.pixel(x: x, y: y)
              XCTAssertEqual(p.r, q.r, accuracy: 0.000002)
              XCTAssertEqual(p.g, q.g, accuracy: 0.000002)
              XCTAssertEqual(p.b, q.b, accuracy: 0.000002)
              XCTAssertEqual(p.a, q.a)
            }
          }
        }
      }
      let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      let n = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      try PSDCodec.writeRasterLayers(d).write(
        to: root.appendingPathComponent("artifacts/native-depth-\(n).psd"))
    }
  }
  func testFloatHDRAndNegativeSamplesAreNotQuantizedOrClamped() throws {
    var d = try CraftDocument(width: 3, height: 1, depth: .f32)
    var pixels = try Surface(width: 3, height: 1, depth: .f32)
    pixels.setPixel(x: 0, y: 0, Pixel(3.25, -0.125, 0.00001, 0.5))
    pixels.setPixel(x: 1, y: 0, Pixel(0.2, 0.3, 0.4, 0))
    d.layers = [Layer(name: "HDR", content: .raster(pixels))]
    d.activeLayerID = d.layers[0].id
    let read = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
    guard case .raster(let p) = read.layers[0].content else { return XCTFail() }
    for x in 0..<3 {
      let a = p.pixel(x: x, y: 0)
      let b = pixels.pixel(x: x, y: 0)
      XCTAssertEqual(a.r, b.r, accuracy: 0.000002)
      XCTAssertEqual(a.g, b.g, accuracy: 0.000002)
      XCTAssertEqual(a.b, b.b, accuracy: 0.000002)
      XCTAssertEqual(a.a, b.a)
    }
    XCTAssertEqual(PSDColorMetadata.defaultHDRToning().count, 110)
    XCTAssertEqual(read.sourceMetadata?["psdColorModeData"], PSDColorMetadata.defaultHDRToning())
  }
  func testFlattenedPSDAtEveryDepthAndCompression() throws {
    for v in try vectors() {
      var w = PSDWriter()
      w.text("8BPS")
      w.n(1, 2)
      w.n(0, 6)
      w.n(3, 2)
      w.n(v.height, 4)
      w.n(v.width, 4)
      w.n(v.depth, 2)
      w.n(3, 2)
      w.n(0, 4)
      w.n(0, 4)
      w.n(0, 4)
      w.data.append(v.encoded)
      let d = try PSDCodec.read(w.data)
      XCTAssertEqual(d.layers.count, 1)
      guard case .raster(let s) = d.layers[0].content else { return XCTFail() }
      for y in 0..<v.height {
        for x in 0..<v.width {
          let i = y * v.width + x
          let sample = try PSDChannelCodec.sample(Array(v.raw), i, depth: v.depth)
          XCTAssertEqual(
            s.pixel(x: x, y: y).r, v.depth == 32 ? SRGBTransfer.encoded(sample) : sample,
            accuracy: 0.000001)
        }
      }
    }
  }
  func testFloatNormalCompositionUsesLinearLight() throws {
    var d = try CraftDocument(width: 1, height: 1, depth: .f32)
    d.layers = [
      Layer(name: "Black", content: .fill(.black)),
      Layer(name: "Half White", content: .fill(Pixel(1, 1, 1, 0.5))),
    ]
    d.activeLayerID = d.layers.last?.id
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).r, 0.73535698, accuracy: 0.000001)
    d.depth = .u16
    XCTAssertEqual(try Renderer.composite(d).pixel(x: 0, y: 0).r, 0.5, accuracy: 0.00002)
  }
  func testHighDepthMergedExportWithAppleDecoder() throws {
    for depth in [PixelDepth.u16, .f32] {
      let d = try document(depth)
      let data = try PSDCodec.writeRasterLayers(d)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.bitsPerComponent, depth == .u16 ? 16 : 32)
      let read = try RasterIO.surface(image, depth: depth)
      let expected = try Renderer.composite(d)
      for (x, y) in [(0, 0), (95, 63), (25, 20), (40, 28)] {
        XCTAssertEqual(read.pixel(x: x, y: y).r, expected.pixel(x: x, y: y).r, accuracy: 0.0001)
        XCTAssertEqual(read.pixel(x: x, y: y).g, expected.pixel(x: x, y: y).g, accuracy: 0.0001)
      }
    }
  }
  func testPhotoshopSavedHighDepthLayersAndComposites() throws {
    for n in [16, 32] {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "photoshop-depth-\(n)", withExtension: "psd", subdirectory: "Fixtures"))
      let data = try Data(contentsOf: url)
      let doc = try PSDCodec.read(data)
      XCTAssertEqual(doc.depth, n == 16 ? .u16 : .f32)
      XCTAssertEqual(doc.layers.map(\.name), ["Gradient", "Precision"])
      XCTAssertEqual(doc.layers[1].x, 13)
      let expectedDoc = try document(doc.depth)
      // Photoshop may expand the stored mask rectangle; document-space coverage
      // must remain identical regardless of that storage normalization.
      let mask = try XCTUnwrap(MaskSampler(layer: doc.layers[1]))
      let expectedMask = try XCTUnwrap(MaskSampler(layer: expectedDoc.layers[1]))
      for y in 0..<doc.height {
        for x in 0..<doc.width {
          XCTAssertEqual(
            mask.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5),
            expectedMask.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5), accuracy: 0.00005)
        }
      }
      for i in 0..<2 {
        guard case .raster(let a) = doc.layers[i].content,
          case .raster(let b) = expectedDoc.layers[i].content
        else { return XCTFail() }
        for y in 0..<a.height {
          for x in 0..<a.width {
            let p = a.pixel(x: x, y: y)
            let q = b.pixel(x: x, y: y)
            XCTAssertEqual(p.r, q.r, accuracy: 0.00005)
            XCTAssertEqual(p.g, q.g, accuracy: 0.00005)
            XCTAssertEqual(p.b, q.b, accuracy: 0.00005)
            XCTAssertEqual(p.a, q.a, accuracy: 0.00005)
          }
        }
      }
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      let expected = try RasterIO.surface(image, depth: doc.depth)
      let actual = try Renderer.composite(doc)
      var error: Float = 0
      for y in 0..<doc.height {
        for x in 0..<doc.width {
          let p = actual.pixel(x: x, y: y)
          let q = expected.pixel(x: x, y: y)
          error = max(error, abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
        }
      }
      XCTAssertLessThanOrEqual(error, 0.0001, "Photoshop \(n)-bit composite")
    }
  }
}
