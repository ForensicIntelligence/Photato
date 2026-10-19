import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDMergedSampleTests: XCTestCase {
  func testRGB16PhotoshopAlphaMatrixMergedBytesAndStraightLayerPreservation() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-rgb16-matte-matrix", withExtension: "psd",
        subdirectory: "Fixtures"))
    let bytes = try Data(contentsOf: url)
    let document = try PSDCodec.read(bytes)
    XCTAssertEqual(document.depth, .u16)
    XCTAssertEqual(document.width, 256)
    XCTAssertEqual(document.height, 256)
    XCTAssertEqual(document.layers.count, 1)
    let before = try NativeArchive.encode(document)
    let exported = try PSDCodec.writeRasterLayers(document)
    func merged(_ data: Data) throws -> [UInt8] {
      var reader = PSDReader(data: data, offset: 26)
      for _ in 0..<3 { _ = try reader.section() }
      return try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: 256, height: 256, depth: 16, channels: 4)
    }
    let reference = try merged(bytes)
    let actual = try merged(exported)
    XCTAssertEqual(actual.count, reference.count)
    let changed = zip(actual, reference).filter { $0 != $1 }.count
    print("RGB16 Photoshop alpha matrix: \(changed) changed stored bytes in 65,536 pixels")
    XCTAssertEqual(changed, 0)
    let reopened = try PSDCodec.read(exported)
    XCTAssertEqual(reopened.layers[0].content, document.layers[0].content)
    XCTAssertEqual(try NativeArchive.encode(document), before)
  }

  func testRGB16MatteHalfTiesRoundTheDistanceFromWhite() throws {
    // Explicit stored codes from the Photoshop matrix; direct round-to-nearest
    // after adding white gets these half ties wrong by two full-range codes.
    let samples: [(UInt16, UInt16, UInt16)] = [
      (14080, 256, 65333), (42239, 768, 65261), (32768, 10, 65529),
    ]
    for (color, alpha, expected) in samples {
      let p = PSDMergedSample.encode(
        Pixel(Float(color) / 65535, 0, 1, Float(alpha) / 65535), depth: 16)
      var encoded: [UInt8] = []
      try PSDChannelCodec.append(p.r, depth: 16, to: &encoded)
      XCTAssertEqual(UInt16(encoded[0]) << 8 | UInt16(encoded[1]), expected)
    }
    XCTAssertEqual(PSDMergedSample.encode(Pixel(0.2, 0.7, 0.3, 0), depth: 16), Pixel(1, 1, 1, 0))
    XCTAssertEqual(PSDMergedSample.encode(.white, depth: 16), .white)
    XCTAssertEqual(PSDMergedSample.encode(.black, depth: 16), .black)
  }

  func testWhiteMatteAndHDRSamplesInStoredSpace() throws {
    let half = Pixel(0.2, 0.4, 0.8, 0.5)
    XCTAssertEqual(
      PSDMergedSample.encode(half, depth: 8).quantized(.u8),
      Pixel(Float(153) / 255, Float(178) / 255, Float(229) / 255, Float(128) / 255))
    let sixteen = PSDMergedSample.encode(half, depth: 16)
    XCTAssertEqual(sixteen, Pixel(Float(39321) / 65535, Float(45873) / 65535,
                                 Float(58981) / 65535, Float(32768) / 65535))
    let hdr = SRGBTransfer.encoded(Pixel(2, -0.25, 0.5, 0.5))
    let stored = PSDMergedSample.encode(hdr, depth: 32)
    XCTAssertEqual(stored.r, 1.5, accuracy: 0.000001)
    XCTAssertEqual(stored.g, 0.375, accuracy: 0.000001)
    XCTAssertEqual(stored.b, 0.75, accuracy: 0.000001)
    XCTAssertEqual(PSDMergedSample.encode(.clear, depth: 8), Pixel(1, 1, 1, 0))
    XCTAssertEqual(PSDMergedSample.decode(Pixel(1, 1, 1, 0)), Pixel(1, 1, 1, 0))
    XCTAssertEqual(PSDMergedSample.decode(Pixel(1.5, 0.375, 0.75, 0.5)), Pixel(2, -0.25, 0.5, 0.5))
  }
  func testLayerExportKeepsStraightPixelsButStoresWhiteMatteInMergedPlanes() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 1, height: 1, depth: depth)
      doc.layers = [
        Layer(
          name: "Transparent",
          content: .raster(
            try Surface(width: 1, height: 1, depth: depth, fill: Pixel(0.2, 0.4, 0.8, 0.5))))
      ]
      doc.activeLayerID = doc.layers[0].id
      let data = try PSDCodec.writeRasterLayers(doc)
      let reopened = try PSDCodec.read(data)
      let a = try Renderer.composite(doc)
      let b = try Renderer.composite(reopened)
      XCTAssertEqual(a.pixel(x: 0, y: 0).a, b.pixel(x: 0, y: 0).a, accuracy: 0.000001)
      XCTAssertEqual(a.pixel(x: 0, y: 0).r, b.pixel(x: 0, y: 0).r, accuracy: 0.000001)
      var reader = PSDReader(data: data)
      _ = try reader.bytes(26)
      for _ in 0..<3 { _ = try reader.section() }
      let bits = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      let bytes = try PSDChannelCodec.decode(
        reader.bytes(reader.remaining), width: 1, height: 1, depth: bits, channels: 4)
      let expected = PSDMergedSample.encode(a.pixel(x: 0, y: 0), depth: bits).quantized(depth)
      for (index, value) in [expected.r, expected.g, expected.b, expected.a].enumerated() {
        XCTAssertEqual(try PSDChannelCodec.sample(bytes, index, depth: bits), value)
      }
    }
  }
  func testFlattenedPSDWhiteMatteIsRemovedBeforeColorConversion() throws {
    for depth in [8, 16, 32] {
      var file = PSDWriter()
      file.text("8BPS")
      file.n(1, 2)
      file.n(0, 6)
      file.n(4, 2)
      file.n(1, 4)
      file.n(1, 4)
      file.n(depth, 2)
      file.n(3, 2)
      file.n(0, 4)
      file.n(0, 4)
      var layer = PSDWriter()
      layer.n(0, 4)
      layer.n(0, 4)
      layer.text("8BIM")
      layer.text(depth == 32 ? "Mt32" : depth == 16 ? "Mt16" : "Mtrn")
      layer.n(0, 4)
      file.section(layer.data)
      file.n(0, 2)
      var bytes: [UInt8] = []
      for value: Float in [0.6, 0.7, 0.9, 0.5] {
        try PSDChannelCodec.append(value, depth: depth, to: &bytes)
      }
      file.data.append(contentsOf: bytes)
      let doc = try PSDCodec.read(file.data)
      let pixel = try Renderer.layerSurface(doc.layers[0], in: doc).pixel(x: 0, y: 0)
      let expected =
        depth == 32 ? SRGBTransfer.encoded(Pixel(0.2, 0.4, 0.8, 0.5)) : Pixel(0.2, 0.4, 0.8, 0.5)
      XCTAssertEqual(pixel.r, expected.r, accuracy: depth == 8 ? 0.01 : 0.00005)
      XCTAssertEqual(pixel.g, expected.g, accuracy: depth == 8 ? 0.01 : 0.00005)
      XCTAssertEqual(pixel.b, expected.b, accuracy: depth == 8 ? 0.01 : 0.00005)
    }
  }
}
