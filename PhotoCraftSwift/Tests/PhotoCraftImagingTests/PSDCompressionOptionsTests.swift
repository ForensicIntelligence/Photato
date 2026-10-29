import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDCompressionOptionsTests: XCTestCase {
  struct Oracle: Decodable {
    struct Row: Decodable { let name: String; let raw: Data; let encoded: Data }
    let cases: [Row]
  }
  func testPackBitsMatchesOriginalRustBoundaryAndRandomRows() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource:"psd-packbits-rust-oracle",withExtension:"json",subdirectory:"Fixtures"))
    let rows = try JSONDecoder().decode(Oracle.self,from:Data(contentsOf:url)).cases
    XCTAssertEqual(rows.count,44)
    for row in rows {
      XCTAssertEqual(try PSDPackBits.encode(Array(row.raw)),row.encoded,row.name)
    }
  }
  func pattern(_ count: Int) -> [UInt8] {
    var seed: UInt32 = 141
    return (0..<count).map { _ in seed = 1_664_525 &* seed &+ 1_013_904_223;return UInt8(truncatingIfNeeded:seed >> 24) }
  }
  func testFourPlanarMethodsAndBothRowTableWidthsRoundTripExactly() throws {
    for depth in [8,16,32] {
      let width = 257, height = 3, channels = 4, size = width * depth / 8
      let samples = pattern(size * height * channels)
      for format in PSDFileFormat.allCases {
        for method in PSDCompression.allCases {
          let output = PSDOutput()
          try PSDChannelWriter.write(width:width,height:height,depth:depth,compression:method,channels:channels,format:format,to:output) { y in
            Array(samples[(y*size)..<((y+1)*size)])
          }
          XCTAssertEqual(try PSDChannelCodec.decode(output.data,width:width,height:height,depth:depth,channels:channels,format:format),samples)
          XCTAssertEqual(Array(output.data.prefix(2)),[0,UInt8(method.rawValue)])
          if method == .rle {
            let countBytes = format == .psd ? 2 : 4
            let first = output.data[2..<(2+countBytes)].reduce(0) { ($0<<8)|Int($1) }
            XCTAssertEqual(first,try PSDPackBits.encode(Array(samples.prefix(size))).count)
          }
        }
      }
    }
  }
  func merged(_ data: Data, _ format: PSDFileFormat) throws -> Data {
    var reader = PSDReader(data:data)
    _ = try reader.bytes(26)
    _ = try reader.section();_ = try reader.section()
    let length = try reader.length(format == .psd ? 4 : 8)
    _ = try reader.view(length)
    return try reader.bytes(reader.remaining)
  }
  func testAllLayerAndMergedCompressionsRetainSamplesMasksAndMetadata() throws {
    let folder = try PSDFileOutputTests().directory();defer { try? FileManager.default.removeItem(at:folder) }
    for depth in PixelDepth.allCases {
      let model = try PSDDepthTests().document(depth)
      let bits = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      for format in PSDFileFormat.allCases {
        let baselineBytes = try PSDCodec.writeRasterLayers(model,format:format)
        let baseline = try PSDCodec.read(baselineBytes)
        let rawMerged = try PSDChannelCodec.decode(merged(baselineBytes,format),width:model.width,height:model.height,depth:bits,channels:4,format:format)
        for layer in PSDCompression.allCases {
          for composite in PSDCompression.allCases {
            let bytes = try PSDCodec.writeRasterLayers(model,compression:layer,format:format,compositeCompression:composite)
            let name = "rgb\(bits)-format\(format.rawValue)-layer\(layer.rawValue)-merged\(composite.rawValue).\(format == .psd ? "psd" : "psb")"
            let target = folder.appendingPathComponent(name)
            try PSDCodec.writeRasterLayers(model,to:target,compression:layer,format:format,compositeCompression:composite)
            XCTAssertEqual(try Data(contentsOf:target),bytes)
            XCTAssertEqual(try PSDChannelCodec.decode(merged(bytes,format),width:model.width,height:model.height,depth:bits,channels:4,format:format),rawMerged)
            let decoded = try PSDCodec.read(bytes)
            XCTAssertEqual(decoded.depth,baseline.depth);XCTAssertEqual(decoded.workingICC,baseline.workingICC)
            XCTAssertEqual(decoded.pixelsPerInch,baseline.pixelsPerInch);XCTAssertEqual(decoded.layers.map(\.name),baseline.layers.map(\.name))
            for (a,b) in zip(decoded.layers,baseline.layers) {
              XCTAssertEqual(a.opacity,b.opacity);XCTAssertEqual(a.blendMode,b.blendMode)
              XCTAssertEqual(a.mask,b.mask);XCTAssertEqual(a.maskProperties,b.maskProperties)
              if case .raster(let left) = a.content, case .raster(let right) = b.content {
                let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
                XCTAssertEqual(try left.rgbaData(depth:.f32,colorEncoding:encoding),try right.rgbaData(depth:.f32,colorEncoding:encoding))
              } else { XCTFail("Missing raster content") }
            }
            if layer == .zipPrediction && composite == .raw { XCTAssertEqual(bytes,baselineBytes) }
            if let destination = ProcessInfo.processInfo.environment["PHOTATO_PSD_COMPRESSION_OUTPUT_DIR"] {
              try bytes.write(to:URL(fileURLWithPath:destination).appendingPathComponent(name))
            }
          }
        }
      }
    }
  }
  func testOversizedPSDRowRejectsAtomicallyWhilePSBRetainsAllBytes() throws {
    let bytes = pattern(80_000), folder = try PSDFileOutputTests().directory()
    defer { try? FileManager.default.removeItem(at:folder) }
    let url = folder.appendingPathComponent("preserved.psd"), original = Data("Original document".utf8)
    try original.write(to:url)
    do {
      let file = try AtomicFileWriter(to:url), output = PSDOutput(file:file)
      try PSDChannelWriter.write(width:20_000,height:1,depth:32,compression:.rle,format:.psd,to:output) { _ in bytes }
      try file.commit();XCTFail("Oversized PSD row was written")
    } catch { XCTAssertTrue(error.localizedDescription.contains("Use PSB")) }
    XCTAssertEqual(try Data(contentsOf:url),original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path),[url.lastPathComponent])
    let output = PSDOutput()
    try PSDChannelWriter.write(width:20_000,height:1,depth:32,compression:.rle,format:.psb,to:output) { _ in bytes }
    XCTAssertEqual(try PSDChannelCodec.decode(output.data,width:20_000,height:1,depth:32,format:.psb),bytes)
    XCTAssertGreaterThan(output.data[2..<6].reduce(0) { ($0<<8)|Int($1) },65_535)
    let short = PSDOutput();try short.n(0,2);try short.patchLength(65_535,at:0,width:2)
    XCTAssertEqual(short.data,Data([255,255]));XCTAssertThrowsError(try short.patchLength(65_536,at:0,width:2))
  }
  func testCancellationStopsRLEBeforePublishingAFile() async throws {
    let folder = try PSDFileOutputTests().directory();defer { try? FileManager.default.removeItem(at:folder) }
    let url = folder.appendingPathComponent("preserved.psb"), original = Data([4,5,6])
    try original.write(to:url)
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      let model = try CraftDocument(width:17,height:11)
      try PSDCodec.writeRasterLayers(model,to:url,compression:.rle,format:.psb,compositeCompression:.rle)
    }
    task.cancel()
    do { try await task.value;XCTFail("Cancelled output succeeded") } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(try Data(contentsOf:url),original)
  }
}
