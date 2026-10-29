import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers
import XCTest
@testable import PhotoCraftImaging

final class TIFFFloatTests: XCTestCase {
  let values: [Float] = [
    -1, 0.1, 2, 0, 16, 0.5, -0.125, 0.25, 0.000001, 100.5, 0.33333334, 0.7,
    2.5, 0.3, 1.2, 1, 0.75, 0.625, 0.125, 0.00001,
    Float(bitPattern: 0x3eaaaaab), Float(bitPattern: 0x40000001), 0.01, 0.5,
  ]
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 3, height: 2, depth: .f32)
    var s = try Surface(width: 3, height: 2, depth: .f32, colorEncoding: .linearRGB)
    for i in 0..<6 {
      s.setLinearPixel(x: i % 3, y: i / 3,
        Pixel(values[i * 4], values[i * 4 + 1], values[i * 4 + 2], values[i * 4 + 3]))
    }
    d.layers[0].content = .raster(s)
    d.resolution = 144
    d.sourceMetadata = [RasterMetadata.xmpKey: MetadataPreservationTests().xmp]
    return d
  }
  func raw(_ d: CraftDocument) throws -> Data {
    guard case .raster(let pixels) = d.layers[0].content else { throw CraftError.invalid("Expected pixels") }
    return try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB)
  }
  func testFloatTIFFAllCompressionChoicesRetainExactSamplesICCAndMetadata() throws {
    let adobe = try PSDCodec.read(WorkingProfileTests().fixture("photoshop-source-rgb32")).workingICC
    let p3 = try ColorManagement.importedProfile(
      CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?, depth: .f32)
    for (index, profile) in [nil, adobe, p3].enumerated() {
      var d = try fixture(); d.workingICC = profile
      let original = d, expected = try raw(d)
      for compression in RasterEncodingOptions.TIFFCompression.allCases {
        let data = try RasterIO.encoded(d, type: .tiff, options: .init(tiffCompression: compression))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.bitsPerComponent, 32)
        let props = try RasterEncodingOptionsTests().properties(data)
        XCTAssertEqual((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int, compression.tag)
        let reopened = try RasterIO.read(data)
        XCTAssertEqual(reopened.depth, .f32)
        XCTAssertEqual(try raw(reopened), expected)
        XCTAssertEqual(reopened.workingICC, try ColorManagement.space(for: d).copyICCData() as Data?)
        XCTAssertEqual(reopened.sourceICC, reopened.workingICC)
        XCTAssertEqual(reopened.pixelsPerInch, 144)
        let xmp = String(decoding: try XCTUnwrap(RasterMetadata.xmpData(reopened.sourceMetadata)), as: UTF8.self)
        XCTAssertTrue(xmp.contains("original-value")); XCTAssertFalse(xmp.contains("Old profile"))
        XCTAssertEqual(d, original)
        if let path = ProcessInfo.processInfo.environment["PHOTATO_TIFF_FLOAT_OUTPUT_DIR"] {
          let folder = URL(fileURLWithPath: path)
          let stem = "profile\(index)-\(compression.rawValue)"
          try data.write(to: folder.appendingPathComponent(stem + ".tiff"))
          try expected.write(to: folder.appendingPathComponent(stem + ".rgba32le"))
          try (try XCTUnwrap(ColorManagement.space(for: d).copyICCData()) as Data)
            .write(to: folder.appendingPathComponent(stem + ".icc"))
        }
      }
    }
  }

  // A separate, uncompressed TIFF fixture builder; does not use ImageIO or the
  // application encoder. Classic TIFF SHORT/LONG/UNDEFINED fields, one RGBA strip.
  func independentTIFF(little: Bool, orientation: Int) throws -> Data {
    func number(_ n: Int, _ count: Int) -> Data {
      Data((0..<count).map { UInt8(truncatingIfNeeded: n >> (8 * (little ? $0 : count - 1 - $0))) })
    }
    var pixels = Data()
    for value in values { pixels.append(number(Int(value.bitPattern), 4)) }
    let icc = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB)?.copyICCData() as Data?)
    var fields: [(Int, Int, Int, Data)] = [
      (256, 4, 1, number(3, 4)), (257, 4, 1, number(2, 4)),
      (258, 3, 4, Data(repeating: 0, count: 0)), (259, 3, 1, number(1, 2)),
      (262, 3, 1, number(2, 2)), (273, 4, 1, Data()),
      (274, 3, 1, number(orientation, 2)), (277, 3, 1, number(4, 2)),
      (278, 4, 1, number(2, 4)), (279, 4, 1, number(pixels.count, 4)),
      (284, 3, 1, number(1, 2)), (338, 3, 1, number(2, 2)),
      (339, 3, 4, Data()), (34675, 7, icc.count, icc),
    ]
    fields[2].3 = (0..<4).reduce(into: Data()) { v, _ in v.append(number(32, 2)) }
    fields[12].3 = (0..<4).reduce(into: Data()) { v, _ in v.append(number(3, 2)) }
    let payloadStart = 8 + 2 + fields.count * 12 + 4
    fields[5].3 = number(payloadStart, 4)
    var payload = pixels
    var result = Data((little ? "II" : "MM").utf8) + number(42, 2) + number(8, 4) + number(fields.count, 2)
    for (tag, type, count, bytes) in fields {
      result.append(number(tag, 2) + number(type, 2) + number(count, 4))
      if bytes.count <= 4 {
        result.append(bytes + Data(repeating: 0, count: 4 - bytes.count))
      } else {
        result.append(number(payloadStart + payload.count, 4)); payload.append(bytes)
      }
    }
    return result + number(0, 4) + payload
  }
  func testIndependentBothEndianTIFFFixturesAndAllOrientationsRetainBits() throws {
    let orders = [
      [0, 1, 2, 3, 4, 5], [2, 1, 0, 5, 4, 3], [5, 4, 3, 2, 1, 0], [3, 4, 5, 0, 1, 2],
      [0, 3, 1, 4, 2, 5], [3, 0, 4, 1, 5, 2], [5, 2, 4, 1, 3, 0], [2, 5, 1, 4, 0, 3],
    ]
    for little in [true, false] {
      for orientation in 1...8 {
        let data = try independentTIFF(little: little, orientation: orientation)
        let d = try RasterIO.read(data)
        XCTAssertEqual(d.width, orientation < 5 ? 3 : 2)
        XCTAssertEqual(d.height, orientation < 5 ? 2 : 3)
        let expected = orders[orientation - 1].flatMap { Array(values[$0 * 4..<$0 * 4 + 4]) }
        XCTAssertEqual(try raw(d), expected.withUnsafeBytes { Data($0) })
      }
    }
  }
  func testDirectFloatProviderHandlesPaddingByteOrderAndOpaqueRGB() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
    for little in [true, false] {
      for channels in [3, 4] {
        var bytes = Data()
        for y in 0..<2 {
          for x in 0..<3 {
            for c in 0..<channels {
              var n = values[(y * 3 + x) * 4 + c].bitPattern
              n = little ? n.littleEndian : n.bigEndian
              bytes.append(withUnsafeBytes(of: &n) { Data($0) })
            }
          }
          bytes.append(Data(repeating: 0xa5, count: 16))
        }
        let image = try XCTUnwrap(CGImage(width: 3, height: 2, bitsPerComponent: 32,
          bitsPerPixel: channels * 32, bytesPerRow: 3 * channels * 4 + 16, space: space,
          bitmapInfo: [.floatComponents, little ? .byteOrder32Little : .byteOrder32Big,
            CGBitmapInfo(rawValue: (channels == 4 ? CGImageAlphaInfo.last : .none).rawValue)],
          provider: CGDataProvider(data: bytes as CFData)!, decode: nil,
          shouldInterpolate: false, intent: .defaultIntent))
        let result = try XCTUnwrap(FloatRasterSamples.surface(image, space: space))
        var expected = values
        if channels == 3 { for i in 0..<6 { expected[i * 4 + 3] = 1 } }
        XCTAssertEqual(try result.rgbaData(depth: .f32, colorEncoding: .linearRGB),
          expected.withUnsafeBytes { Data($0) })
        XCTAssertNil(try FloatRasterSamples.surface(image, space: RasterIO.colorSpace()))
      }
    }
  }
  func testPNGStillConvertsFloatToSDRAndExplicitIntegerTIFFRemainsAvailable() throws {
    let d = try fixture()
    XCTAssertEqual(try RasterEncodingOptionsTests().image(RasterIO.encoded(d)).bitsPerComponent, 16)
    XCTAssertEqual(try RasterEncodingOptionsTests().image(
      RasterIO.encoded(Renderer.composite(d), type: .tiff, outputDepth: .u16, workingDocument: d)
    ).bitsPerComponent, 16)
  }
  func testDirectFloatReaderRejectsNonfiniteSamplesAndDefersPremultipliedImages() throws {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
    for component in 0..<4 {
      var values: [Float] = [0.2, 0.4, 0.8, 1]
      values[component] = component % 2 == 0 ? .nan : .infinity
      let data = values.withUnsafeBytes { Data($0) }
      let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 32,
        bitsPerPixel: 128, bytesPerRow: 16, space: space,
        bitmapInfo: [.floatComponents, .byteOrder32Little,
          CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)],
        provider: CGDataProvider(data: data as CFData)!, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent))
      XCTAssertThrowsError(try FloatRasterSamples.surface(image, space: space))
    }
    let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1,
      bitsPerComponent: 32, bytesPerRow: 16, space: space,
      bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue))
    XCTAssertNil(try FloatRasterSamples.surface(XCTUnwrap(context.makeImage()), space: space))
  }
  func testCancelledFloatEncodingReturnsNoData() async throws {
    let d = try fixture()
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try RasterIO.encoded(d, type: .tiff)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancellation returned TIFF data") }
    catch { XCTAssertTrue(error is CancellationError) }
  }
}
