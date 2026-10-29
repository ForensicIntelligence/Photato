import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
import zlib
@testable import PhotoCraftImaging

final class RasterEncodingOptionsTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var model = try CraftDocument(width: 129, height: 73, depth: depth)
    var pixels = try Surface(width: 129, height: 73, depth: depth)
    for y in 0..<73 {
      for x in 0..<129 {
        pixels.setPixel(x: x, y: y, Pixel(Float(x % 23) / 22, Float(y % 17) / 16,
          Float((x * y) % 31) / 30, x % 4 == 0 ? 0.5 : 1))
      }
    }
    model.layers[0].content = .raster(pixels)
    model.resolution = 144
    return model
  }
  func image(_ data: Data) throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }
  func properties(_ data: Data) throws -> [CFString: Any] {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }
  func samples(_ data: Data) throws -> Data {
    let image = try image(data)
    return try XCTUnwrap(image.dataProvider?.data) as Data
  }
  func testPNGAllCompressionLevelsAndAdam7RetainDecoded8And16BitSamples() throws {
    for depth in [PixelDepth.u8, .u16] {
      let model = try fixture(depth), baseline = try RasterIO.encoded(model)
      for interlaced in [false, true] {
        for level in 0...9 {
          let bytes = try RasterIO.encoded(model,
            options: .init(pngCompression: level, pngInterlaced: interlaced))
          XCTAssertEqual(try samples(bytes), try samples(baseline))
          XCTAssertEqual(try image(bytes).bitsPerComponent, depth == .u8 ? 8 : 16)
          let props = try properties(bytes)
          XCTAssertEqual((props[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGInterlaceType] as? Int, interlaced ? 1 : 0)
          XCTAssertEqual(props[kCGImagePropertyDPIWidth] as? Double,
            try properties(baseline)[kCGImagePropertyDPIWidth] as? Double)
        }
      }
      XCTAssertEqual(try RasterIO.encoded(model, options: .init()), baseline)
    }
  }
  func testTIFFCompressionTagsDepthAndSamplesMatchUnmodifiedEncoder() throws {
    for depth in [PixelDepth.u8, .u16] {
      let model = try fixture(depth), baseline = try RasterIO.encoded(model, type: .tiff)
      for compression in RasterEncodingOptions.TIFFCompression.allCases {
        let bytes = try RasterIO.encoded(model, type: .tiff, options: .init(tiffCompression: compression))
        XCTAssertEqual(try samples(bytes), try samples(baseline))
        XCTAssertEqual(try image(bytes).bitsPerComponent, depth == .u8 ? 8 : 16)
        XCTAssertEqual((try properties(bytes)[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int, compression.tag)
      }
      XCTAssertEqual(try RasterIO.encoded(model, type: .tiff, options: .init()), baseline)
    }
  }
  func chunks(_ data: Data) throws -> [(String, Data)] {
    var offset = 8, result: [(String, Data)] = []
    while offset < data.count {
      let count = data[offset..<(offset+4)].reduce(0) { ($0 << 8) | Int($1) }
      let type = String(decoding: data[(offset+4)..<(offset+8)], as: UTF8.self)
      result.append((type, Data(data[(offset+8)..<(offset+8+count)])))
      offset += count + 12
    }
    return result
  }
  func chunk(_ type: String, _ data: Data) -> Data {
    func be(_ x: UInt32) -> Data { var v = x.bigEndian; return withUnsafeBytes(of: &v) { Data($0) } }
    let body = Data(type.utf8) + data
    let crc = body.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
    return be(UInt32(data.count)) + body + be(UInt32(crc))
  }
  func testFragmentedIDATAndAncillaryChunksArePreserved() throws {
    let baseline = try RasterIO.encoded(fixture(.u16), options: .init(pngInterlaced: true))
    let pieces = try chunks(baseline)
    var fragmented = Data(baseline.prefix(8))
    let note = Data("Photato test\0independent original fixture".utf8)
    for (type, bytes) in pieces {
      if type == "IDAT" {
        fragmented.append(chunk(type, Data()))
        for i in stride(from: 0, to: bytes.count, by: 2) {
          fragmented.append(chunk(type, Data(bytes[i..<min(bytes.count, i+2)])))
        }
      } else {
        if type == "IEND" { fragmented.append(chunk("tEXt", note)) }
        fragmented.append(chunk(type, bytes))
      }
    }
    let output = try PNGCompression.rewrite(fragmented, level: 9)
    XCTAssertEqual(try samples(output), try samples(baseline))
    let before = try chunks(fragmented).filter { $0.0 != "IDAT" }.map { chunk($0.0, $0.1) }
    let after = try chunks(output).filter { $0.0 != "IDAT" }.map { chunk($0.0, $0.1) }
    XCTAssertEqual(before, after)
  }
  func testInvalidOptionsDamagedStreamsAndWrongGeometryReject() throws {
    let original = try RasterIO.encoded(fixture())
    for level in [-1, 10] { XCTAssertThrowsError(try PNGCompression.rewrite(original, level: level)) }
    var damaged = original; damaged[20] ^= 1
    XCTAssertThrowsError(try PNGCompression.rewrite(damaged, level: 5))
    XCTAssertThrowsError(try PNGCompression.rewrite(Data(original.dropLast()), level: 5))
    var rebuilt = Data(original.prefix(8))
    for (type, value) in try chunks(original) {
      var bytes = value
      if type == "IHDR" { bytes[3] += 1 }
      rebuilt.append(chunk(type, bytes))
    }
    XCTAssertThrowsError(try PNGCompression.rewrite(rebuilt, level: 5))
    XCTAssertThrowsError(try RasterIO.encoded(fixture(), type: .jpeg, options: .init(pngCompression: 4)))
    XCTAssertThrowsError(try RasterIO.encoded(fixture(), options: .init(tiffCompression: .zip)))
    XCTAssertThrowsError(try RasterIO.encoded(fixture(), options: .init(pngCompression: 10)))
  }
  func testCancelledRecompressionReturnsNoOutput() async throws {
    let bytes = try RasterIO.encoded(fixture())
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try PNGCompression.rewrite(bytes, level: 9)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled compression returned data") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
