import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
import UniformTypeIdentifiers
@testable import PhotoCraftImaging

final class TIFFRestrictedTests: XCTestCase {
  func testPaletteAndBitmapByteOrderCompressionAndLayout() throws {
    for document in try RestrictedFormatTests().documents() {
      for order in RasterEncodingOptions.TIFFByteOrder.allCases {
        for layout in RasterEncodingOptions.TIFFPixelOrder.allCases {
          for compression in RasterEncodingOptions.TIFFCompression.allCases {
            let data = try RasterIO.encoded(document, type: .tiff,
              options: .init(tiffCompression: compression, tiffByteOrder: order, tiffPixelOrder: layout))
            let file = try TIFFContainer(data, metadata: true), result = try RasterIO.read(data)
            XCTAssertEqual(try file.scalar(262), document.colorMode == .indexed ? 3 : 0)
            XCTAssertEqual(try file.numbers(258).first, document.bitsPerChannel)
            XCTAssertEqual(result.restrictedMode, document.restrictedMode)
            XCTAssertEqual(result.pixelsPerInch, document.pixelsPerInch)
          }
        }
      }
    }
  }
  func literal(width: Int, height: Int, bits: Int, photo: Int, samples: Data,
    compression: Int = 1, orientation: Int = 1, fill: Int = 1,
    channels: Int = 1, tiled: Bool = false, predictor: Int = 1) throws -> Data {
    let file = try TIFFContainer(Data([73,73,42,0,8,0,0,0,0,0,0,0,0,0]), metadata: true)
    file.set(256, [width], type: 4); file.set(257, [height], type: 4)
    file.set(258, Array(repeating: bits, count: channels)); file.set(262, [photo]); file.set(277, [channels])
    file.set(259, [compression]); file.set(274, [orientation]); file.set(266, [fill]); file.set(317, [predictor])
    if channels == 2 { file.set(338, [2]) }
    if tiled { file.set(322, [16]); file.set(323, [16]) } else { file.set(278, [height], type: 4) }
    if photo == 3 {
      let colors = 1 << bits
      // Index0 red,1 green,2 blue,3 white, remaining entries black.
      var table = [Int](repeating: 0, count: colors * 3)
      table[0] = 65535; table[colors + 1] = 65535
      if colors >= 4 { table[2 * colors + 2] = 65535; for c in 0..<3 { table[c * colors + 3] = 65535 } }
      file.set(320, table)
    }
    var data = Data([73,73,42,0,0,0,0,0]); data.append(samples)
    file.set(tiled ? 324 : 273, [8], type: 4); file.set(tiled ? 325 : 279, [samples.count], type: 4)
    try file.appendDirectories(to: &data, order: .little); return data
  }
  func testSubBytePaletteOrientationTileEdgesAndPrediction() throws {
    let expected: [[UInt8]] = [[0,1,2,3,1,0],[2,1,0,0,1,3],[0,1,3,2,1,0],[3,1,0,0,1,2],
      [0,3,1,1,2,0],[3,0,1,1,0,2],[0,2,1,1,3,0],[2,0,1,1,0,3]]
    for orientation in 1...8 {
      let data = try literal(width: 3, height: 2, bits: 2, photo: 3, samples: Data([0x18,0xd0]), orientation: orientation)
      let document = try RasterIO.read(data)
      guard case .indexed(let r) = document.restrictedMode else { return XCTFail() }
      XCTAssertEqual(Array(r.indices), expected[orientation - 1]); XCTAssertEqual(r.width, orientation >= 5 ? 2 : 3)
    }
    var tile = Data(repeating: 0, count: 64); tile[0] = 0x18; tile[4] = 0xd0
    let tiled = try literal(width: 3, height: 2, bits: 2, photo: 3, samples: tile, tiled: true)
    guard case .indexed(let raster) = try RasterIO.read(tiled).restrictedMode else { return XCTFail() }
    XCTAssertEqual(Array(raster.indices), expected[0])
    let compressed = try RestrictedRasterCompression.deflate(Data([0,1,1,3,254,255]))
    let predicted = try literal(width: 3, height: 2, bits: 8, photo: 3, samples: compressed, compression: 8, predictor: 2)
    guard case .indexed(let r) = try RasterIO.read(predicted).restrictedMode else { return XCTFail() }
    XCTAssertEqual(Array(r.indices), expected[0])
  }
  func testBitmapPolarityFillOrderAndPackBits() throws {
    let raw = Data([0x80,0x80,0x40,0]), black = [true,false,false,false,false,false,false,false,true,false,true,false,false,false,false,false,false,false]
    for photo in [0,1] { for fill in [1,2] {
      var samples = photo == 0 ? raw : Data(raw.map { ~$0 })
      if fill == 2 { samples = Data(samples.map { b in (0..<8).reduce(UInt8(0)) { $0 << 1 | (b >> $1 & 1) } }) }
      let data = try literal(width: 9, height: 2, bits: 1, photo: photo, samples: samples, fill: fill)
      guard case .bitmap(let r) = try RasterIO.read(data).restrictedMode else { return XCTFail() }
      XCTAssertEqual((0..<2).flatMap { y in (0..<9).map { r.isBlack(x: $0, y: y) } }, black)
      XCTAssertEqual(r.bits, raw)
    } }
    // Literal PackBits: repeat0x80 twice, then two-byte literal0x40,0.
    let packed = try literal(width: 9, height: 2, bits: 1, photo: 0, samples: Data([255,0x80,1,0x40,0]), compression: 32773)
    guard case .bitmap(let r) = try RasterIO.read(packed).restrictedMode else { return XCTFail() }
    XCTAssertEqual(r.bits, raw)
    XCTAssertEqual(try TIFFRestrictedStorage.unpackBits(Data([253,0]), expected: 4, rowBytes: 2), Data(repeating: 0, count: 4))
    XCTAssertThrowsError(try TIFFRestrictedStorage.unpackBits(Data([252,0]), expected: 4, rowBytes: 2))
  }
  func testInvalidPaletteAlphaAndSegmentExtentsReject() throws {
    let data = try literal(width: 3, height: 1, bits: 8, photo: 3, samples: Data([0,0,1,255,2,255]), channels: 2)
    guard case .indexed(let r) = try RasterIO.read(data).restrictedMode else { return XCTFail() }
    XCTAssertEqual(r.transparentIndex, 0); XCTAssertEqual(r.indices, Data([0,1,2]))
    for samples in [Data([0,128,1,255,2,255]), Data([0,0,0,255,2,255]), Data([0,0,1,0,2,255])] {
      XCTAssertThrowsError(try RasterIO.read(literal(width: 3, height: 1, bits: 8, photo: 3, samples: samples, channels: 2)))
    }
    XCTAssertThrowsError(try RasterIO.read(literal(width: 9, height: 1, bits: 1, photo: 0, samples: Data([0]))))
    XCTAssertThrowsError(try RasterIO.read(literal(width: 2, height: 1, bits: 1, photo: 0, samples: Data([0]), orientation: 9)))
    for tag in [273, 279, 320] {
      let file = try TIFFContainer(data, metadata: true)
      if tag == 320 { file.set(tag, [0,1,2]) } else { file.set(tag, [Int(UInt32.max)], type: 4) }
      var changed = data; try file.appendDirectories(to: &changed, order: file.order)
      XCTAssertThrowsError(try RasterIO.read(changed))
    }
    let document = try RestrictedFormatTests().documents()[0]
    XCTAssertThrowsError(try RasterIO.encoded(document, type: .tiff, options: .init(tiffLayers: true)))
    XCTAssertThrowsError(try RasterIO.encoded(document, type: .tiff, options: .init(tiffCompression: .zip, tiffPredictor: true)))
  }
  func testRestrictedMetadataSurvivesFormatsWithoutStaleColorTags() throws {
    for var document in try RestrictedFormatTests().documents() {
      document.sourceMetadata = try RasterIO.read(MetadataPreservationTests().source()).sourceMetadata
      for type in [UTType.png, .tiff] {
        let data = try RasterIO.encoded(document, type: type), result = try RasterIO.read(data)
        let xmp = String(decoding: try XCTUnwrap(RasterMetadata.xmpData(result.sourceMetadata)), as: UTF8.self)
        XCTAssertTrue(xmp.contains("original-value")); XCTAssertFalse(xmp.contains("Old profile"))
        XCTAssertEqual(result.restrictedMode, document.restrictedMode)
        let properties = try MetadataPreservationTests().properties(data)
        XCTAssertEqual((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifFNumber] as? Double, 2.8)
      }
    }
  }
  func testEmitTIFFForIndependentReaders() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_RESTRICTED_TIFF_OUTPUT_DIR"] else { return }
    let directory = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var files = [[String: Any]]()
    for document in try RestrictedFormatTests().documents() {
      var expected: [String: Any] = ["width": document.width,"height": document.height,"mode": document.colorMode.rawValue]
      switch document.restrictedMode! {
      case .indexed(let r): expected["palette"] = r.palette.map { [Int($0.red),Int($0.green),Int($0.blue)] }; expected["indices"] = Array(r.indices); expected["transparentIndex"] = r.transparentIndex
      case .bitmap(let r): expected["black"] = (0..<document.height).flatMap { y in (0..<document.width).map { r.isBlack(x: $0,y: y) } }
      }
      for order in RasterEncodingOptions.TIFFByteOrder.allCases { for layout in RasterEncodingOptions.TIFFPixelOrder.allCases { for compression in RasterEncodingOptions.TIFFCompression.allCases {
        let filename = "\(document.name)-\(order.rawValue)-\(layout.rawValue)-\(compression.rawValue).tiff"
        let data = try RasterIO.encoded(document, type: .tiff, options: .init(tiffCompression: compression, tiffByteOrder: order, tiffPixelOrder: layout))
        try data.write(to: directory.appendingPathComponent(filename))
        var entry = expected; entry["file"] = filename; files.append(entry)
      } } }
    }
    try JSONSerialization.data(withJSONObject: files, options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("expected.json"))
  }
}
