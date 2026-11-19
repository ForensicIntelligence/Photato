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
          // Photoshop applies ZIP prediction to Float32 layer data.
          let expected = depth == 32 && method == .zip ? PSDCompression.zipPrediction : method
          XCTAssertEqual(Array(output.data.prefix(2)),[0,UInt8(expected.rawValue)])
          if method == .rle {
            let countBytes = format == .psd ? 2 : 4
            let first = output.data[2..<(2+countBytes)].reduce(0) { ($0<<8)|Int($1) }
            XCTAssertEqual(first,try PSDPackBits.encode(Array(samples.prefix(size))).count)
          }
        }
      }
    }
  }
  func testRepeatedRowsKeepExactPlanarBytesAndCompression() throws {
    let width = 257, height = 29, channels = 2
    for depth in [8, 16, 32] {
      let bytes = width * (depth / 8)
      let defaults = [[UInt8](repeating: 17, count: bytes), pattern(bytes)]
      let patch = pattern(bytes).map { $0 ^ 0x6a }
      func row(_ index: Int) -> [UInt8] {
        index % height == 4 ? patch : defaults[index / height]
      }
      for format in PSDFileFormat.allCases {
        for compression in PSDCompression.allCases {
          let plain = PSDOutput(), batched = PSDOutput()
          try PSDChannelWriter.write(width: width, height: height, depth: depth, compression: compression,
            channels: channels, format: format, to: plain, row: row)
          var requested: [Int] = []
          try PSDChannelWriter.write(width: width, height: height, depth: depth, compression: compression,
            channels: channels, format: format, to: batched, repeatedRows: { index in
              switch index % height { case 0: return 4; case 4: return 1; default: return height - 5 }
            }) { index in
              requested.append(index)
              return row(index)
            }
          XCTAssertEqual(requested, [0, 4, 5, height, height + 4, height + 5])
          XCTAssertEqual(batched.data, plain.data)
        }
      }
    }
    XCTAssertThrowsError(try PSDChannelWriter.write(width: 1, height: 3, depth: 8,
      compression: .rle, channels: 2, to: PSDOutput(), repeatedRows: { _ in 4 }) { _ in [0] })
  }

  func testRepeatedRLECacheValidationKeepsAuxiliaryRowsAndRejectsMalformedRows() throws {
    let width = 253, height = 5, data = PSDOutput()
    let process = [UInt8](repeating: 12, count: width), auxiliary = pattern(width)
    try PSDChannelWriter.write(width: width, height: height, depth: 8, compression: .rle,
      channels: 2, format: .psb, to: data, repeatedRows: { _ in height }) { index in
        index == 0 ? process : auxiliary
      }
    func reader(_ bytes: Data) throws -> PSDChannelReader {
      try PSDChannelReader(PSDReader(data: bytes), width: width, height: height,
        depth: 8, channels: 2, format: .psb)
    }
    let valid = try reader(data.data)
    try valid.discardRows(height)
    for _ in 0..<height { XCTAssertEqual(try valid.nextRow(), auxiliary) }

    var damaged = data.data
    let payload = 2 + height * 2 * 4, firstLength = try PSDPackBits.encode(process).count
    // The second row has the same declared length, but a changed run header.
    damaged[payload + firstLength] = 0x7f
    XCTAssertThrowsError(try reader(damaged).discardRows(height))
    XCTAssertThrowsError(try reader(Data(data.data.dropLast())).discardRemaining())
    XCTAssertThrowsError(try reader(data.data + Data([128])).discardRemaining())
  }

  func testSparsePagedMergedRowsMatchOrdinaryBandsAtEveryDepth() throws {
    let width = 1_203, height = 30_001
    for depth in PixelDepth.allCases {
      var model = try CraftDocument(width: width, height: height, depth: depth)
      let encoding: SurfaceColorEncoding = depth == .f32 ? .linearRGB : .sRGB
      var bottom = try Surface(width: width, height: height, depth: depth,
        fill: Pixel(0.1875, 0.625, 0.25, 0.5), colorEncoding: encoding)
      var top = try Surface(width: width, height: height, depth: depth,
        fill: Pixel(0.875, 0.125, 0.125, 0.75), colorEncoding: encoding)
      bottom.setPixel(x: 0, y: 0, Pixel(0.125, 0.25, 0.375, 1))
      top.setPixel(x: width - 1, y: height - 1, Pixel(0.875, 0.5, 0.625, 0.5))
      if depth == .f32 {
        top.setLinearPixel(x: 64, y: 65, Pixel(1.5, -0.0, 0.625, 0.25))
      }
      var foreground = Layer(name: "Foreground", content: .raster(top))
      foreground.opacity = 0.625
      var mask = try Surface(width: width, height: height, depth: depth, fill: Pixel(0.75, 0.75, 0.75))
      mask.setPixel(x: 1_201, y: 127, .black)
      foreground.mask = mask
      model.layers = [Layer(name: "Base", content: .raster(bottom)), foreground]
      model.activeLayerID = foreground.id
      let ordinary = PSDCompositeRows(model), sparse = try XCTUnwrap(ordinary.sparseRows())
      let bits = model.bitsPerChannel
      XCTAssertEqual(sparse.repeatedRows(from: 128), 29_952 - 128)
      XCTAssertEqual(sparse.repeatedRows(from: height - 1), 1)
      for y in [0, 64, 65, 127, 128, height - 1] {
        for channel in 0..<4 {
          XCTAssertEqual(try sparse.row(y, channel: channel, depth: bits), try ordinary.row(y, channel: channel, depth: bits),
            "RGB/\(bits), row \(y), plane \(channel)")
        }
      }
    }
  }

  func testPackBitsLayerRetainsImplicitColorAndEveryEditedBit() throws {
    let width = 131, height = 129
    let changes = [IntRect(x: 0, y: 0, width: 1, height: 1),
      IntRect(x: 64, y: 65, width: 1, height: 1), IntRect(x: width - 1, y: height - 1, width: 1, height: 1)]
    for depth in PixelDepth.allCases {
      let bits = depth == .u8 ? 8 : depth == .u16 ? 16 : 32
      let quiet: [Float] = [0.37, -0.0, depth == .f32 ? 2.5 : 0.61, 0.75]
      let changed: [Float] = [0.78, depth == .f32 ? -0.25 : 0.25, 0.15, -0.0]
      for components in [3, 4] {
        let bytes = try (0..<components).map { c -> Data in
          let output = PSDOutput()
          try PSDChannelWriter.write(width: width, height: height, depth: bits,
            compression: .rle, format: .psb, to: output) { y in
              var row: [UInt8] = []
              for x in 0..<width {
                try PSDChannelCodec.append(changes.contains { $0.contains(x, y) } ? changed[c] : quiet[c],
                  depth: bits, to: &row)
              }
              return row
            }
          return output.data
        }
        func input() throws -> [PSDChannelReader] {
          try bytes.map { try PSDChannelReader(PSDReader(data: $0), width: width, height: height, depth: bits, format: .psb) }
        }
        let slow = try input()
        let expected = try PSDRasterPaging.layer(width: width, height: height, depth: depth,
          components: components, context: PSDRasterPaging.Context()) { _ in try slow.map { try $0.nextRow() } }
        let actual = try PSDRasterPaging.sparseLayer(width: width, height: height, depth: depth,
          channels: input(), context: PSDRasterPaging.Context(scratchByteLimit: 3 * 65_536))
        XCTAssertEqual(actual, expected, "RGB/\(bits) with \(components) stored components")
        XCTAssertEqual(actual.tileCount, 3)
        if depth == .f32 {
          XCTAssertEqual(actual.linearPixel(x: 130, y: 127).g.bitPattern, Float(-0.0).bitPattern)
          XCTAssertEqual(actual.linearPixel(x: 130, y: 128).g.bitPattern, Float(-0.25).bitPattern)
        }
      }
    }
  }

  func testPackBitsLayerRejectsChangedNonfiniteAndTruncatedRows() throws {
    let width = 67, height = 2
    func plane(_ corrupt: Bool) throws -> Data {
      let output = PSDOutput()
      try PSDChannelWriter.write(width: width, height: height, depth: 32, compression: .rle,
        format: .psb, to: output) { y in
          var bytes = [UInt8](repeating: 0, count: width * 4)
          if y == 1 && corrupt { bytes[260] = 0x7f; bytes[261] = 0xc0 }
          return bytes
        }
      return output.data
    }
    let good = try plane(false), bad = try plane(true)
    for wrong in [bad, Data(good.dropLast()), good + Data([128])] {
      let channels = try [good, wrong, good].map {
        try PSDChannelReader(PSDReader(data: $0), width: width, height: height, depth: 32, format: .psb)
      }
      XCTAssertThrowsError(try PSDRasterPaging.sparseLayer(width: width, height: height, depth: .f32,
        channels: channels, context: PSDRasterPaging.Context()))
    }
  }

  func testLayerWithPaintAcrossFirstRowFitsItsSparseBudget() throws {
    let width = 131, height = 129
    let base: [UInt8] = [51, 102, 153], paint: [UInt8] = [179, 51, 102]
    for compression: [PSDCompression] in [[.rle, .rle, .rle], [.raw, .raw, .raw], [.raw, .rle, .raw]] {
      let data = try compression.enumerated().map { component, method -> Data in
        let output = PSDOutput()
        try PSDChannelWriter.write(width: width, height: height, depth: 8,
          compression: method, format: .psb, to: output) { y in
            var row = [UInt8](repeating: y == 0 ? paint[component] : base[component], count: width)
            if y == 65 { row[64] = paint[component] }
            if y == height - 1 { row[width - 1] = paint[component] }
            return row
          }
        return output.data
      }
      func input() throws -> [PSDChannelReader] {
        try data.map { try PSDChannelReader(PSDReader(data: $0), width: width, height: height, depth: 8, format: .psb) }
      }
      let original = try input()
      let direct = try PSDRasterPaging.layer(width: width, height: height, depth: .u8, components: 3,
        context: PSDRasterPaging.Context()) { _ in try original.map { try $0.nextRow() } }
      let sparse = try PSDRasterPaging.sparseLayer(width: width, height: height, depth: .u8,
        channels: input(), context: PSDRasterPaging.Context(scratchByteLimit: 5 * 65_536))
      XCTAssertEqual(sparse, direct)
      XCTAssertEqual(sparse.tileCount, 5)
      XCTAssertEqual(sparse.mappedBytes, 5 * 65_536)
    }
  }

  func testSparseLayerRowInspectionPreservesTheLiveCursor() throws {
    let width = 19, height = 7
    for format in PSDFileFormat.allCases {
      for compression in [PSDCompression.raw, .rle] {
        let output = PSDOutput()
        try PSDChannelWriter.write(width: width, height: height, depth: 8, compression: compression,
          format: format, to: output) { row in [UInt8](repeating: UInt8(row), count: width) }
        let reader = try PSDChannelReader(PSDReader(data: output.data), width: width, height: height, depth: 8, format: format)
        var values: [UInt8] = []
        try reader.inspectLayerRows(at: [0, 2, 6]) { values.append($0[0]) }
        XCTAssertEqual(values, [0, 2, 6])
        XCTAssertEqual(reader.remainingRows, height)
        XCTAssertThrowsError(try reader.inspectLayerRows(at: [2, 1]) { _ in })
        for y in 0..<height {
          XCTAssertEqual(try reader.nextRow(), [UInt8](repeating: UInt8(y), count: width))
        }
        let truncated = try PSDChannelReader(PSDReader(data: output.data.dropLast()), width: width, height: height, depth: 8, format: format)
        XCTAssertThrowsError(try truncated.inspectLayerRows(at: [height - 1]) { _ in })
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
