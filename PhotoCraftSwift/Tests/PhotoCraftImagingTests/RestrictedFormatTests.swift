import CoreGraphics
import Foundation
import ImageIO
import XCTest
import UniformTypeIdentifiers
import CryptoKit
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RestrictedFormatTests: XCTestCase {
  func testIndependentEncoderFixturesPreserveEveryStoredIndexAndBit() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "provenance", withExtension: "json", subdirectory: "Fixtures/RestrictedFormats"))
    let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let cases = try XCTUnwrap(manifest["cases"] as? [[String: Any]])
    XCTAssertEqual(cases.count, 37)
    for entry in cases {
      let name = try XCTUnwrap(entry["file"] as? String), bytes = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(name))
      XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), entry["sha256"] as? String)
      let document = try RasterIO.read(bytes, name: name)
      XCTAssertEqual(document.width, entry["width"] as? Int); XCTAssertEqual(document.height, entry["height"] as? Int)
      XCTAssertEqual(document.pixelsPerInch, try XCTUnwrap(entry["dpi"] as? Double), accuracy: 0.013)
      switch try XCTUnwrap(document.restrictedMode) {
      case .indexed(let r):
        XCTAssertEqual(entry["mode"] as? String, "indexed")
        XCTAssertEqual(r.indices.map(Int.init), entry["indices"] as? [Int], name)
        XCTAssertEqual(r.palette.map { [Int($0.red),Int($0.green),Int($0.blue)] }, entry["palette"] as? [[Int]], name)
        XCTAssertEqual(r.transparentIndex, entry["transparentIndex"] as? Int, name)
      case .bitmap(let r):
        XCTAssertEqual(entry["mode"] as? String, "bitmap")
        XCTAssertEqual((0..<r.height).flatMap { y in (0..<r.width).map { r.isBlack(x: $0,y: y) } }, entry["black"] as? [Bool], name)
      }
    }
  }
  func documents() throws -> [CraftDocument] {
    let palette: [PaletteColor] = [.init(240, 20, 30), .init(240, 20, 30), .init(0, 255, 0), .init(255, 255, 255), .init(0, 0, 255)]
    let indices = Data((0..<221).map { UInt8(($0 * 3 + $0 / 17) % 5) })
    let indexed = try IndexedRaster(width: 17, height: 13, palette: palette, indices: indices, transparentIndex: 3)
    var settings = BitmapConversionSettings(); settings.method = .pattern
    let bitmap = try BitmapRaster.converting((0..<221).map { Float(($0 * 37) % 256) / 255 }, width: 17, settings: settings)
    return try [RestrictedModeRaster.indexed(indexed), .bitmap(bitmap)].map {
      var d = try CraftDocument(width: 17, height: 13, name: $0.mode.rawValue).replacingRestrictedMode($0)
      d.resolution = 300; return d
    }
  }
  func testPSDPSBAllSupportedCompressionPreservesNativeSamplesAndHeader() throws {
    for document in try documents() { for format in PSDFileFormat.allCases { for compression in PSDCompression.allCases {
      if document.colorMode == .bitmap && compression == .zipPrediction {
        XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: compression)); continue
      }
      let data = try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: compression)
      XCTAssertEqual(Int(data[24]) * 256 + Int(data[25]), document.colorMode == .bitmap ? 0 : 2)
      XCTAssertEqual(Int(data[22]) * 256 + Int(data[23]), document.bitsPerChannel)
      let result = try PSDCodec.read(data)
      XCTAssertEqual(result.restrictedMode, document.restrictedMode, "\(format) \(compression)")
      XCTAssertEqual(result.pixelsPerInch, 300); XCTAssertEqual(result.layers.count, 1)
    } } }
  }
  func testPNGCompressionInterlaceAndPaletteIdentity() throws {
    for document in try documents() { for interlaced in [false, true] { for level in [0, 6, 9] {
      let data = try RasterIO.encoded(document, type: .png, options: .init(pngCompression: level, pngInterlaced: interlaced))
      XCTAssertEqual(data[24], UInt8(document.bitsPerChannel)); XCTAssertEqual(data[25], document.colorMode == .bitmap ? 0 : 3)
      XCTAssertEqual(data[28], interlaced ? 1 : 0)
      let result = try RasterIO.read(data)
      XCTAssertEqual(result.restrictedMode, document.restrictedMode)
      XCTAssertEqual(result.pixelsPerInch, 300, accuracy: 0.013)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.width, document.width); XCTAssertEqual(image.height, document.height)
    } } }
  }
  func testSubBytePNGAndAllRowFiltersFromHandSpecifiedRows() throws {
    // Independent expected pixels and precomputed filter residuals. Rows all
    // contain indices0,1,2,3; each uses a different standard filter.
    var header = PNGRestrictedStorage.number(4) + PNGRestrictedStorage.number(5)
    header.append(contentsOf: [8,3,0,0,0])
    let rows = Data([0,0,1,2,3, 1,0,1,1,1, 2,0,0,0,0, 3,0,1,1,1, 4,0,0,0,0])
    let palette = Data([255,0,0, 0,255,0, 0,0,255, 255,255,255])
    let data = PNGRestrictedStorage.signature + PNGRestrictedStorage.chunk("IHDR", header)
      + PNGRestrictedStorage.chunk("PLTE", palette)
      + PNGRestrictedStorage.chunk("IDAT", try RestrictedRasterCompression.deflate(rows)) + PNGRestrictedStorage.chunk("IEND", Data())
    guard case .indexed(let r) = try RasterIO.read(data).restrictedMode else { return XCTFail() }
    XCTAssertEqual(r.indices, Data(Array(repeating: [UInt8](0...3), count: 5).flatMap { $0 }))
    for (bits, packed) in [(2, [UInt8(0x1b), 0x40]), (4, [UInt8(0x01), 0x23, 0x10])] {
      var h = PNGRestrictedStorage.number(5) + PNGRestrictedStorage.number(1); h.append(contentsOf: [UInt8(bits),3,0,0,0])
      let png = PNGRestrictedStorage.signature + PNGRestrictedStorage.chunk("IHDR", h) + PNGRestrictedStorage.chunk("PLTE", palette)
        + PNGRestrictedStorage.chunk("IDAT", try RestrictedRasterCompression.deflate(Data([0] + packed))) + PNGRestrictedStorage.chunk("IEND", Data())
      guard case .indexed(let r) = try RasterIO.read(png).restrictedMode else { return XCTFail() }
      XCTAssertEqual(r.indices, Data([0,1,2,3,1]))
    }
  }
  func testPaletteAlphaPromotesOnlyUnrepresentableTablesToRGB() throws {
    let colors = Data([29, 180, 245, 29, 180, 245, 240, 157, 23, 175, 34, 209])
    let order = [1, 0, 2, 3]
    let tables: [([UInt8], Bool)] = [([0], false), ([255, 0], false), ([0, 255, 0], true), ([0, 1, 127, 255], true)]
    let profile = try NativeModeProfile.standard(.rgb, depth: .u8)
    let compressedProfile = try RestrictedRasterCompression.deflate(profile)
    for (alpha, promotes) in tables {
      for interlaced in [false, true] {
        let header = PNGRestrictedStorage.number(4) + PNGRestrictedStorage.number(1)
          + Data([2, 3, 0, 0, interlaced ? 1 : 0])
        let rows = interlaced ? Data([0, 0x40, 0, 0x80, 0, 0x30]) : Data([0, 0x4b])
        let png = PNGRestrictedStorage.signature + PNGRestrictedStorage.chunk("IHDR", header)
          + PNGRestrictedStorage.chunk("iCCP", Data("Owned RGB".utf8) + Data([0, 0]) + compressedProfile)
          + PNGRestrictedStorage.chunk("PLTE", colors) + PNGRestrictedStorage.chunk("tRNS", Data(alpha))
          + PNGRestrictedStorage.chunk("pHYs", PNGRestrictedStorage.number(11811) + PNGRestrictedStorage.number(11811) + Data([1]))
          + PNGRestrictedStorage.chunk("IDAT", try RestrictedRasterCompression.deflate(rows))
          + PNGRestrictedStorage.chunk("IEND", Data())
        let document = try RasterIO.read(png)
        XCTAssertEqual(document.pixelsPerInch, 300, accuracy: 0.013)
        XCTAssertEqual(document.sourceICC, profile)
        if promotes {
          XCTAssertEqual(document.colorMode, .rgb)
          XCTAssertEqual(document.workingICC, profile)
          let expected = Data(order.flatMap { index in
            Array(colors[(index * 3)..<(index * 3 + 3)]) + [index < alpha.count ? alpha[index] : 255]
          })
          let archive = try NativeArchive.decode(NativeArchive.encodeChunked(document))
          guard case .raster(let raster) = try XCTUnwrap(archive.layers.first).content else { return XCTFail() }
          XCTAssertEqual(try raster.rgbaData(depth: .u8), expected)
        } else {
          guard case .indexed(let raster) = document.restrictedMode else { return XCTFail() }
          XCTAssertEqual(raster.indices, Data(order.map(UInt8.init)))
          XCTAssertEqual(raster.transparentIndex, alpha.firstIndex(of: 0))
        }
      }
    }
  }
  func testLargeComplexPalettePNGOpensAsSparseEditableRGB() throws {
    let metadata = try XCTUnwrap(Bundle.module.url(forResource: "provenance", withExtension: "json",
      subdirectory: "Fixtures/png-paged-palette"))
    let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
    let cases = try XCTUnwrap(manifest["cases"] as? [[String: Any]])
    let palette = [Pixel(29 / 255, 180 / 255, 245 / 255, 0), Pixel(29 / 255, 180 / 255, 245 / 255, 1 / 255),
      Pixel(240 / 255, 157 / 255, 23 / 255, 127 / 255), Pixel(175 / 255, 34 / 255, 209 / 255, 1)]
    for fixture in cases {
      let name = try XCTUnwrap(fixture["file"] as? String)
      let data = try Data(contentsOf: metadata.deletingLastPathComponent().appendingPathComponent(name))
      let bytes = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(bytes, fixture["pngSHA256"] as? String)
      let document = try RasterIO.read(data, name: name)
      XCTAssertEqual(document.colorMode, .rgb)
      XCTAssertEqual(document.depth, .u8)
      XCTAssertEqual(document.width, fixture["width"] as? Int)
      XCTAssertEqual(document.height, fixture["height"] as? Int)
      XCTAssertEqual(document.pixelsPerInch, 300, accuracy: 0.013)
      XCTAssertNil(document.restrictedMode)
      guard case .raster(let surface) = try XCTUnwrap(document.layers.first).content else { return XCTFail() }
      XCTAssertGreaterThan(surface.mappedTileCount, 0)
      XCTAssertLessThanOrEqual(surface.tileCount, 12)
      XCTAssertEqual(surface.pixel(x: 0, y: 0), palette[0])
      XCTAssertEqual(surface.pixel(x: 320, y: 740), palette[0])
      let changes = try XCTUnwrap(fixture["changes"] as? [[Int]])
      for point in changes {
        XCTAssertEqual(surface.pixel(x: point[0], y: point[1]), palette[point[2]], "\(name): \(point)")
      }
      if name == "paged-ordinary.png" {
        let exif = Data([73, 73, 42, 0, 8, 0, 0, 0, 1, 0, 18, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0])
        var rotated = data
        rotated.insert(contentsOf: PNGRestrictedStorage.chunk("eXIf", exif), at: 33)
        let opened = try RasterIO.read(rotated)
        XCTAssertEqual(opened.width, document.height)
        XCTAssertEqual(opened.height, document.width)
        guard case .raster(let transformed) = try XCTUnwrap(opened.layers.first).content else { return XCTFail() }
        XCTAssertGreaterThan(transformed.mappedTileCount, 0)
        XCTAssertLessThanOrEqual(transformed.tileCount, 12)
        for point in changes {
          XCTAssertEqual(transformed.pixel(x: document.height - 1 - point[1], y: point[0]), palette[point[2]])
        }
      }
    }
  }
  func testMalformedContainersAndInvalidAlphaTablesReject() throws {
    let indexed = try documents()[0], good = try RasterIO.encoded(indexed, type: .png)
    var corrupt = good; corrupt[29] ^= 1; XCTAssertThrowsError(try RasterIO.read(corrupt))
    XCTAssertThrowsError(try RasterIO.read(good.dropLast()))
    for alpha in [Data(), Data(repeating: 0, count: 6)] {
      let blocks = try PNGRestrictedStorage.chunks(good)
      let png = blocks.reduce(into: PNGRestrictedStorage.signature) { $0 += PNGRestrictedStorage.chunk($1.type, $1.type == "tRNS" ? alpha : $1.data) }
      XCTAssertThrowsError(try RasterIO.read(png))
    }
    var psd = try PSDCodec.writeRasterLayers(indexed); psd[23] = 16; XCTAssertThrowsError(try PSDCodec.read(psd))
    psd = try PSDCodec.writeRasterLayers(indexed); psd[25] = 0; XCTAssertThrowsError(try PSDCodec.read(psd))
    let zipped = try RestrictedRasterCompression.deflate(Data(repeating: 0, count: 4096))
    XCTAssertThrowsError(try RestrictedRasterCompression.inflate(zipped, limit: 10))
    XCTAssertThrowsError(try RestrictedRasterCompression.inflate(zipped + Data([0]), limit: 4096))
  }
  func testEmitRestrictedFormatsForIndependentReaders() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_RESTRICTED_OUTPUT_DIR"] else { return }
    let directory = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var files = [[String: Any]]()
    for document in try documents() {
      var expected: [String: Any] = ["width": document.width, "height": document.height, "mode": document.colorMode.rawValue]
      switch document.restrictedMode! {
      case .indexed(let r): expected["palette"] = r.palette.map { [Int($0.red), Int($0.green), Int($0.blue)] }; expected["indices"] = Array(r.indices); expected["transparentIndex"] = r.transparentIndex
      case .bitmap(let r): expected["black"] = (0..<document.height).flatMap { y in (0..<document.width).map { x in r.isBlack(x: x, y: y) } }
      }
      for format in PSDFileFormat.allCases { for compression in PSDCompression.allCases where document.colorMode != .bitmap || compression != .zipPrediction {
        let name = "\(document.name)-\(compression.rawValue).\(format == .psd ? "psd" : "psb")"
        try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: compression).write(to: directory.appendingPathComponent(name))
        var entry = expected; entry["file"] = name; files.append(entry)
      } }
      for interlaced in [false,true] {
        let name = "\(document.name)-\(interlaced ? "adam7" : "plain").png"
        try RasterIO.encoded(document, type: .png, options: .init(pngInterlaced: interlaced)).write(to: directory.appendingPathComponent(name))
        var entry = expected; entry["file"] = name; files.append(entry)
      }
    }
    try JSONSerialization.data(withJSONObject: files, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("expected.json"))
  }
}
