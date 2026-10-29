import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDStreamingTests: XCTestCase {
  struct Manifest: Decodable {
    struct Case: Decodable {
      var file: String
      var raw: String
      var width: Int
      var height: Int
      var depth: Int
    }
    var cases: [Case]
  }

  private func fixture(_ name: String, directory: String = "psd-stream") throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: name, withExtension: nil, subdirectory: "Fixtures/" + directory))
    return try Data(contentsOf: url)
  }

  func testNestedViewsPreserveRelativeOffsetsAndOriginalDataSlices() throws {
    var data = Data((0..<255).map(UInt8.init))
    var parent = PSDReader(data: data[5..<250])
    XCTAssertEqual(try parent.number(2), 0x0506)
    var child = try parent.view(100)
    var nested = try child.view(4)
    XCTAssertEqual(try nested.u32(), 0x0708_090A)
    XCTAssertThrowsError(try nested.u8())
    XCTAssertEqual(child.remaining, 96)
    XCTAssertEqual(parent.remaining, 143)
    data[11] = 255
    XCTAssertEqual(try child.u8(), 11, "Views retain the original immutable bytes.")
    XCTAssertEqual(try parent.u8(), 107)
    let before = parent.remaining
    for length in [-1, Int.max, before + 1] {
      XCTAssertThrowsError(try parent.view(length))
      XCTAssertEqual(parent.remaining, before)
    }
    XCTAssertThrowsError(try parent.number(9))
    XCTAssertEqual(parent.remaining, before)
    XCTAssertEqual(try child.data.startIndex, 0)
    XCTAssertEqual(try child.data.first, 7)
    for invalidOffset in [Int.min, -1, 256, Int.max] {
      var invalid = PSDReader(data: data, offset: invalidOffset)
      XCTAssertEqual(invalid.remaining, 0)
      XCTAssertThrowsError(try invalid.bytes(0))
      XCTAssertThrowsError(try invalid.view(0))
      XCTAssertThrowsError(try invalid.u8())
    }
  }

  func testRowsMatchIndependentPythonVectorsForEveryCompressionAndDepth() throws {
    for vector in try PSDDepthTests().vectors() {
      for format in PSDFileFormat.allCases {
        // The independent older RLE vectors carry PSD's 16-bit lengths.
        if format == .psb && vector.compression == 1 { continue }
        let reader = try PSDChannelReader(
          PSDReader(data: vector.encoded), width: vector.width, height: vector.height,
          depth: vector.depth, channels: vector.channels, format: format)
        let rowBytes = vector.width * vector.depth / 8
        for row in 0..<vector.height * vector.channels {
          XCTAssertEqual(
            Data(try reader.nextRow()),
            vector.raw.subdata(in: row * rowBytes..<(row + 1) * rowBytes))
        }
        XCTAssertEqual(reader.remainingRows, 0)
        try reader.discardRemaining()
        XCTAssertThrowsError(try reader.nextRow())
      }
    }
  }

  func testWideRowsAndCompressedInputCrossChunkBoundariesExactly() throws {
    let manifest = try JSONDecoder().decode(Manifest.self, from: fixture("provenance.json"))
    for vector in manifest.cases {
      let data = try fixture(vector.file)
      let raw = try fixture(vector.raw)
      XCTAssertGreaterThan(data.count, 65536)
      let rowBytes = vector.width * vector.depth / 8
      let reader = try PSDChannelReader(
        PSDReader(data: data), width: vector.width, height: vector.height, depth: vector.depth)
      for row in 0..<vector.height {
        XCTAssertEqual(
          Data(try reader.nextRow()), raw.subdata(in: row * rowBytes..<(row + 1) * rowBytes),
          "\(vector.file), row \(row)")
      }
      let discarded = try PSDChannelReader(
        PSDReader(data: data), width: vector.width, height: vector.height, depth: vector.depth)
      _ = try discarded.nextRow()
      try discarded.discardRemaining()
      XCTAssertEqual(discarded.remainingRows, 0)
    }
  }

  func testDiscardedZIPRejectsTruncationChecksumTrailingConcatenationAndSizeMismatch() throws {
    let manifest = try JSONDecoder().decode(Manifest.self, from: fixture("provenance.json"))
    for vector in manifest.cases {
      let data = try fixture(vector.file)
      func discard(_ bytes: Data, height: Int? = nil) throws {
        try PSDChannelReader(
          PSDReader(data: bytes), width: vector.width, height: height ?? vector.height,
          depth: vector.depth
        ).discardRemaining()
      }
      for size in [0, 1, 2, 3, 65535, 65536, 65537, data.count - 4, data.count - 1] {
        XCTAssertThrowsError(try discard(data.prefix(size)), "\(vector.file): \(size)")
      }
      var corrupt = data
      corrupt[corrupt.count - 1] ^= 1
      XCTAssertThrowsError(try discard(corrupt))
      XCTAssertThrowsError(try discard(data + Data([0])))
      XCTAssertThrowsError(try discard(data + data.dropFirst(2)))
      XCTAssertThrowsError(try discard(data, height: vector.height - 1))
      XCTAssertThrowsError(try discard(data, height: vector.height + 1))
      // A declared one-byte output cannot expand the entire compressed payload.
      let bomb = try PSDZIPReader(PSDReader(data: data.dropFirst(2)), expected: 1)
      _ = try bomb.read(1)
      XCTAssertThrowsError(try bomb.finish())
    }
  }

  func testPackBitsPaddingSpansLargeDeclaredRowWithoutChangingOutput() throws {
    var bytes = Data([0, 42]) + Data(repeating: 128, count: 200000)
    XCTAssertEqual(try PSDCodec.decodePackBits(bytes, expected: 1), [42])
    bytes[bytes.count - 1] = 0
    XCTAssertThrowsError(try PSDCodec.decodePackBits(bytes, expected: 1))
    var reader = PSDReader(data: Data([9, 0, 0, 0, 9])[1..<4])
    XCTAssertTrue(try reader.consumePadding(0))
    XCTAssertEqual(reader.remaining, 0)
  }

  func testLayeredDocumentsStillRejectCorruptUnusedMergedPreview() throws {
    for depth in [8, 16, 32] {
      for compression in [2, 3] {
        let data = try fixture("rgb\(depth)-compression\(compression).psb", directory: "psb")
        XCTAssertEqual(try PSDCodec.read(data).layers.count, 2)
        var corrupt = data
        corrupt[corrupt.count - 1] ^= 1
        XCTAssertThrowsError(try PSDCodec.read(corrupt))
        XCTAssertThrowsError(try PSDCodec.read(data + Data([0])))
        XCTAssertThrowsError(try PSDCodec.read(data.dropLast()))
      }
    }
  }
}
