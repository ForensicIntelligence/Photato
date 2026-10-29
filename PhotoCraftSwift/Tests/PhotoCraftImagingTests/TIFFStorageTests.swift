import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers
import XCTest
@testable import PhotoCraftImaging

final class TIFFStorageTests: XCTestCase {
  func fixture(_ depth: PixelDepth) throws -> CraftDocument {
    var d = try CraftDocument(width: 257, height: 73, depth: depth)
    var s = try Surface(width: d.width, height: d.height, depth: depth,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
    var random: UInt32 = 0x12345678
    func next() -> Float {
      random = random &* 1664525 &+ 1013904223
      return Float(random >> 8) / 16777216
    }
    for y in 0..<d.height {
      for x in 0..<d.width {
        var p = Pixel(next(), next(), next(), [Float(0), 0.25, 0.7, 1][(x + y) % 4])
        if depth == .f32 {
          p.r = p.r * 32 - 2; p.b *= 0.00001
          s.setLinearPixel(x: x, y: y, p)
        } else { s.setPixel(x: x, y: y, p) }
      }
    }
    d.layers[0].content = .raster(s); d.resolution = 144
    d.sourceMetadata = try RasterIO.read(MetadataPreservationTests().source()).sourceMetadata
    return d
  }
  func raw(_ d: CraftDocument) throws -> Data {
    guard case .raster(let s) = d.layers[0].content else { throw CraftError.invalid("Expected raster") }
    return try s.rgbaData(depth: d.depth, colorEncoding: d.depth == .f32 ? .linearRGB : .sRGB)
  }
  func testStorageMatrixPreservesBaseSamplesProfileExifXMPAndStripGeometry() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth), before = d
      let base = try RasterIO.encoded(d, type: .tiff, options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
      let baseDocument = try RasterIO.read(base)
      let expected = try raw(baseDocument)
      let folder = ProcessInfo.processInfo.environment["PHOTATO_TIFF_STORAGE_OUTPUT_DIR"]
        .map { URL(fileURLWithPath: $0) }
      if let folder {
        try base.write(to: folder.appendingPathComponent("\(depth.rawValue)-base.tiff"))
        try expected.write(to: folder.appendingPathComponent("\(depth.rawValue)-expected.rgba"))
      }
      for order in RasterEncodingOptions.TIFFByteOrder.allCases {
        for layout in RasterEncodingOptions.TIFFPixelOrder.allCases {
          for compression in RasterEncodingOptions.TIFFCompression.allCases {
            for prediction in depth == .f32 && compression != .none ? [false, true] : [false] {
              let options = RasterEncodingOptions(tiffCompression: compression,
                tiffByteOrder: order, tiffPixelOrder: layout, tiffPredictor: prediction)
              let bytes = try RasterIO.encoded(d, type: .tiff, options: options)
              let file = try TIFFContainer(bytes, metadata: true)
              XCTAssertEqual(file.order, order == .bigEndian ? .big : .little)
              XCTAssertEqual(try file.scalar(284), layout == .perChannel ? 2 : 1)
              XCTAssertEqual(try file.scalar(259), compression.tag)
              XCTAssertEqual(try file.scalar(317), prediction ? 3 : 1)
              if depth == .f32 && compression != .none {
                XCTAssertLessThan(try file.scalar(278), d.height)
              }
              let reopened = try RasterIO.read(bytes)
              XCTAssertEqual(try raw(reopened), expected, "\(depth) \(options)")
              XCTAssertEqual(reopened.workingICC, baseDocument.workingICC)
              XCTAssertEqual(reopened.pixelsPerInch, 144)
              let properties = try MetadataPreservationTests().properties(bytes)
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
              XCTAssertEqual(exif?[kCGImagePropertyExifFNumber] as? Double, 2.8)
              XCTAssertTrue(String(decoding: try XCTUnwrap(RasterMetadata.xmpData(reopened.sourceMetadata)),
                as: UTF8.self).contains("original-value"))
              if let folder {
                let stem = "\(depth.rawValue)-\(order.rawValue)-\(layout.rawValue)-\(compression.rawValue)-\(prediction)"
                try bytes.write(to: folder.appendingPathComponent(stem + ".tiff"))
              }
            }
          }
        }
      }
      XCTAssertEqual(d, before)
    }
  }
  func testLZWBoundaryStreamsDecodeInImageIOAndImageIOStreamsDecodeNatively() throws {
    let d = try fixture(.u16)
    let baseline = try RasterIO.encoded(d, type: .tiff, options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
    let apple = try RasterIO.encoded(d, type: .tiff, options: .init(tiffCompression: .lzw))
    let swift = try RasterIO.encoded(d, type: .tiff,
      options: .init(tiffCompression: .lzw, tiffByteOrder: .littleEndian))
    let a = try XCTUnwrap(CGImageSourceCreateWithData(baseline as CFData, nil))
    let b = try XCTUnwrap(CGImageSourceCreateWithData(swift as CFData, nil))
    let ai = try XCTUnwrap(CGImageSourceCreateImageAtIndex(a, 0, nil))
    let bi = try XCTUnwrap(CGImageSourceCreateImageAtIndex(b, 0, nil))
    XCTAssertEqual(ai.dataProvider?.data as Data?, bi.dataProvider?.data as Data?)
    XCTAssertEqual(try raw(RasterIO.read(apple)), try raw(RasterIO.read(baseline)))
    for count in [0, 1, 253, 254, 255, 256, 765, 766, 1790, 8192, 100_000] {
      var state: UInt32 = 19
      let bytes = (0..<count).map { _ -> UInt8 in
        state = state &* 1664525 &+ 1013904223; return UInt8(truncatingIfNeeded: state >> 16)
      }
      let encoded = try TIFFLZW.encode(bytes)
      XCTAssertEqual(try TIFFLZW.decode(encoded, expected: count), bytes)
      if let folder = ProcessInfo.processInfo.environment["PHOTATO_TIFF_STORAGE_OUTPUT_DIR"] {
        try encoded.write(to: URL(fileURLWithPath: folder).appendingPathComponent("lzw-\(count).bin"))
        try Data(bytes).write(to: URL(fileURLWithPath: folder).appendingPathComponent("lzw-\(count).raw"))
      }
    }
  }
  func testIndependentFloatFixturesRetainPlanarAlphaAndPredictionAcrossByteOrders() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tiff-storage")
    let expected = try Data(contentsOf: root.appendingPathComponent("expected.rgba32le"))
    for little in 0...1 {
      for planar in 0...1 {
        for predictor in 0...1 {
          let data = try Data(contentsOf: root.appendingPathComponent("little\(little)-planar\(planar)-predict\(predictor).tiff"))
          XCTAssertEqual(try raw(RasterIO.read(data)), expected)
        }
      }
    }
  }
  func testIntegerHorizontalPredictionUsesSamplesNotIndividualBytes() {
    XCTAssertEqual(TIFFStorage.restore([250, 1, 3, 10, 2, 255], bits: 8,
      components: 3, order: .big, predictor: 2), [250, 1, 3, 4, 3, 2])
    for order in [TIFFContainer.Order.big, .little] {
      let encoded = [65530, 255, 32767, 10, 2, 65535].reduce(into: Data()) {
        $0.append(order.bytes($1, 2))
      }
      let expected = [65530, 255, 32767, 4, 257, 32766].reduce(into: Data()) {
        $0.append(order.bytes($1, 2))
      }
      XCTAssertEqual(TIFFStorage.restore([UInt8](encoded), bits: 16, components: 3,
        order: order, predictor: 2), [UInt8](expected))
    }
  }
  func testMalformedStorageAndInvalidDepthDoNotReturnPixelsOrOutput() throws {
    let d = try TIFFFloatTests().fixture()
    let data = try RasterIO.encoded(d, type: .tiff, options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none))
    for end in [0, 7, data.count / 2, data.count - 1] {
      XCTAssertThrowsError(try TIFFContainer(Data(data.prefix(end)), metadata: true))
    }
    var cyclic = data
    let file = try TIFFContainer(data, metadata: true)
    let offset = file.order.number(data, 4, 4), count = file.order.number(data, offset, 2)
    cyclic.replaceSubrange(offset + 2 + count * 12..<offset + 6 + count * 12, with: file.order.bytes(offset, 4))
    XCTAssertThrowsError(try TIFFContainer(cyclic, metadata: true))
    var tiled = data
    for i in 0..<count {
      let at = offset + 2 + i * 12, tag = file.order.number(data, at, 2)
      if tag == 273 || tag == 279 {
        tiled.replaceSubrange(at..<at + 2, with: file.order.bytes(tag == 273 ? 324 : 325, 2))
      }
    }
    XCTAssertNil(try TIFFStorage.surface(tiled, depth: .f32, encoding: .linearRGB),
      "Tile layouts must defer to ImageIO instead of failing strip admission")
    let wrapped = Data([0]) + data
    XCTAssertEqual(try TIFFContainer(wrapped.dropFirst(), metadata: true).order, file.order)
    let packed = try TIFFLZW.encode([1, 2, 3, 4])
    for bytes in [Data(), Data([0, 0]), Data(packed.dropLast())] {
      XCTAssertThrowsError(try TIFFLZW.decode(bytes, expected: 4))
    }
    XCTAssertThrowsError(try TIFFLZW.decode(packed, expected: 3))
    XCTAssertThrowsError(try TIFFLZW.decode(packed, expected: TIFFContainer.byteLimit + 1))
    for compression in [nil, RasterEncodingOptions.TIFFCompression.none] {
      XCTAssertThrowsError(try RasterIO.encoded(d, type: .tiff,
        options: .init(tiffCompression: compression, tiffPredictor: true)))
    }
    XCTAssertThrowsError(try RasterIO.encoded(fixture(.u8), type: .tiff,
      options: .init(tiffCompression: .zip, tiffPredictor: true)))
    XCTAssertThrowsError(try RasterIO.encoded(d, type: .png,
      options: .init(tiffByteOrder: .bigEndian)))
  }
  func testCancelledNativeCodecRejectsBeforePublishing() async throws {
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try TIFFLZW.encode([1, 2, 3])
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancellation returned data") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
