import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDFileOutputTests: XCTestCase {
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  func testRowCompressionMatchesPreviousWholePlaneEncoderAcrossDepthsAndBoundaries() throws {
    for depth in [8, 16, 32] {
      for width in [1, 193, 20_000] {
        let height = 7
        var seed: UInt32 = 4321
        let bytes: [UInt8] = (0..<(width * height * (depth / 8))).map { _ in
          seed = 1_664_525 &* seed &+ 1_013_904_223
          return UInt8(truncatingIfNeeded: seed >> 24)
        }
        for compression in PSDCompression.allCases {
          let output = PSDOutput()
          let size = width * (depth / 8)
          let format: PSDFileFormat = compression == .rle && size > 65_000 ? .psb : .psd
          try PSDChannelWriter.write(
            width: width, height: height, depth: depth, compression: compression, format: format, to: output
          ) { y in Array(bytes[y * size..<(y + 1) * size]) }
          XCTAssertEqual(
            output.data,
            try PSDChannelCodec.encode(
              bytes, width: width, height: height, depth: depth, compression: compression, format: format))
          XCTAssertEqual(
            try PSDChannelCodec.decode(
              output.data, width: width, height: height, depth: depth, format: format), bytes)
        }
      }
    }
  }
  func testFileAndDataSerializationMatchForIndependentPSBCorpora() throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    var inputs: [URL] = []
    for depth in [8, 16, 32] {
      inputs.append(
        try XCTUnwrap(
          Bundle.module.url(
            forResource: "rgb\(depth)-compression0", withExtension: "psb",
            subdirectory: "Fixtures/psb")))
    }
    for name in [
      "0layers", "1layer", "2layers", "group", "16bit5x5", "32bit5x5", "hidden-layer", "300dpi",
      "transparentbg",
    ] {
      inputs.append(
        try XCTUnwrap(
          Bundle.module.url(
            forResource: name, withExtension: "psb", subdirectory: "Fixtures/psb-corpus")))
    }
    for input in inputs {
      let document = try PSDCodec.read(input)
      for format in PSDFileFormat.allCases {
        let target = folder.appendingPathComponent("output")
        try PSDCodec.writeRasterLayers(document, to: target, format: format)
        let expected = try PSDCodec.writeRasterLayers(document, format: format)
        XCTAssertEqual(try Data(contentsOf: target), expected, input.lastPathComponent)
        let reopened = try PSDCodec.read(target)
        XCTAssertEqual(reopened.profileIsUntagged, document.profileIsUntagged, input.lastPathComponent)
        if document.profileIsUntagged == true {
          // Independent 1layer/2layers PSB fixtures carry1041=1 and no1039.
          // Saving must retain that explicit untagged state, not insert an ICC.
          XCTAssertNil(reopened.workingICC, input.lastPathComponent)
          XCTAssertNil(reopened.sourceICC, input.lastPathComponent)
        } else {
          XCTAssertEqual(reopened.workingICC,
            try document.workingICC ?? (ColorManagement.space(for: document).copyICCData() as Data?))
        }
        XCTAssertEqual(reopened.layers.map(\.name), document.layers.map(\.name))
        for (a, b) in zip(reopened.layers, document.layers) {
          if case .raster(let x) = a.content, case .raster(let y) = b.content {
            let encoding: SurfaceColorEncoding = document.depth == .f32 ? .linearRGB : .sRGB
            XCTAssertEqual(
              try x.rgbaData(depth: .f32, colorEncoding: encoding),
              try y.rgbaData(depth: .f32, colorEncoding: encoding))
          }
          XCTAssertEqual(try a.mask?.rgbaData(depth: .f32), try b.mask?.rgbaData(depth: .f32))
        }
      }
    }
  }
  func testLengthChecksAndMidOutputBudgetFailureKeepExistingFile() throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let target = folder.appendingPathComponent("existing.psb")
    let original = Data("preserve existing file".utf8)
    try original.write(to: target)
    do {
      let file = try AtomicFileWriter(to: target, maximumBytes: 100)
      let output = PSDOutput(file: file)
      let model = try CraftDocument(width: 2, height: 2)
      XCTAssertThrowsError(
        try PSDCodec.writeRasterLayers(
          model, compression: .raw, format: .psb, output: output))
    }
    XCTAssertEqual(try Data(contentsOf: target), original)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: folder.path), ["existing.psb"])
    let output = PSDOutput()
    let offset = try output.reserveLength(8)
    try output.patchLength(Int(UInt32.max) + 123, at: offset, width: 8)
    var reader = PSDReader(data: output.data)
    XCTAssertEqual(try reader.length(8), Int(UInt32.max) + 123)
    XCTAssertThrowsError(try output.patchLength(Int(UInt32.max) + 1, at: offset, width: 4))
    XCTAssertThrowsError(try output.patchLength(-1, at: offset, width: 8))
    XCTAssertThrowsError(try output.patchLength(1, at: Int.max, width: 8))
    XCTAssertThrowsError(try output.finishLength(Int.max, width: 8))
    XCTAssertThrowsError(try output.reserveLength(3))
    XCTAssertThrowsError(
      try PSDChannelWriter.write(
        width: 1, height: 1, depth: 8, compression: .zip, to: PSDOutput()
      ) { _ in [] })
  }
}
