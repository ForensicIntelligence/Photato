import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class JPEGEncodingTests: XCTestCase {
  func export(_ data: Data, _ name: String) throws {
    if let path = ProcessInfo.processInfo.environment["PHOTATO_JPEG_OUTPUT_DIR"] {
      try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(name + ".jpg"))
    }
  }
  func testAllQualitiesAndFormatsPreserveOptimizedSamplesAndMetadata() throws {
    let helper = RasterEncodingOptionsTests(), model = try helper.fixture()
    for quality in 0...12 {
      let baseline = try RasterIO.encoded(model, type: .jpeg,
        options: .init(jpegQuality: quality, jpegFormat: .baseline))
      try export(baseline, "q\(quality)-baseline")
      for format in [RasterEncodingOptions.JPEGFormat.optimized, .progressive] {
        let encoded = try RasterIO.encoded(model, type: .jpeg,
          options: .init(jpegQuality: quality, jpegFormat: format))
        try export(encoded, "q\(quality)-\(format.rawValue)")
        XCTAssertEqual(try helper.image(encoded).width, model.width)
        XCTAssertEqual(try helper.image(encoded).height, model.height)
        let records = try JPEGContainer.segments([UInt8](encoded))
        XCTAssertTrue(records.contains { $0.marker == (format == .progressive ? 194 : 192) })
        if format == .optimized {
          XCTAssertEqual(try helper.samples(encoded), try helper.samples(baseline))
          XCTAssertLessThan(encoded.count, baseline.count)
          let original = [UInt8](baseline), optimized = [UInt8](encoded)
          let before = try JPEGContainer.segments(original).filter { $0.marker != 196 }
            .map { Array(original[$0.range]) }
          let after = records.filter { $0.marker != 196 }.map { Array(optimized[$0.range]) }
          XCTAssertEqual(after, before)
        }
      }
    }
    let original = try RasterIO.encoded(model, type: .jpeg)
    XCTAssertEqual(try RasterIO.encoded(model, type: .jpeg, options: .init()), original)
    try export(original, "default")
  }
  func testTinyConstantAndOddDimensionsOptimize() throws {
    for (w, h) in [(1,1), (7,9), (16,16), (31,33)] {
      for color in [Pixel.black, .white, Pixel(0.4,0.2,0.6)] {
        let surface = try Surface(width: w, height: h, fill: color)
        let original = try RasterIO.encoded(surface, type: .jpeg)
        let output = try JPEGEntropyOptimizer.optimize(original)
        XCTAssertEqual(try RasterEncodingOptionsTests().samples(output),
          try RasterEncodingOptionsTests().samples(original))
      }
    }
  }
  func testMatteAndProfileRemovalAcrossDepthsAndProgressiveScans() throws {
    let helper = RasterEncodingOptionsTests()
    for depth in [PixelDepth.u8, .u16, .f32] {
      var model = try CraftDocument(width: 17, height: 11, depth: depth)
      model.layers[0].content = .raster(try Surface(width: 17, height: 11, depth: depth, fill: .clear))
      for format in RasterEncodingOptions.JPEGFormat.allCases {
        let options = RasterEncodingOptions(jpegQuality: 12, jpegFormat: format, jpegMatte: [1,0,0], jpegEmbedProfile: true)
        let bytes = try RasterIO.encoded(model, type: .jpeg, options: options)
        var untagged = options; untagged.jpegEmbedProfile = false
        let stripped = try RasterIO.encoded(model, type: .jpeg, options: untagged)
        try export(bytes, "\(depth.rawValue)-\(format.rawValue)-red")
        try export(stripped, "\(depth.rawValue)-\(format.rawValue)-untagged")
        let image = try helper.image(stripped)
        XCTAssertEqual(image.bitsPerComponent, 8)
        let decoded = try RasterIO.read(bytes, name: "matte")
        let composite = try Renderer.composite(decoded)
        let color = composite.pixel(x: 8, y: 5)
        XCTAssertGreaterThan(color.r, 0.98); XCTAssertLessThan(color.g, 0.02); XCTAssertLessThan(color.b, 0.02)
        let original = [UInt8](bytes), after = [UInt8](stripped)
        let records = try JPEGContainer.segments(original)
        let icc = records.filter { $0.marker == 226 && original[$0.payload].starts(with: Array("ICC_PROFILE\0".utf8)) }
        XCTAssertFalse(icc.isEmpty)
        XCTAssertEqual(bytes.count - stripped.count, icc.reduce(0) { $0 + $1.range.count })
        XCTAssertFalse(try JPEGContainer.segments(after).contains {
          $0.marker == 226 && after[$0.payload].starts(with: Array("ICC_PROFILE\0".utf8))
        })
        XCTAssertEqual(try JPEGContainer.withoutICC(stripped), stripped)
        XCTAssertEqual(try helper.samples(stripped), try helper.samples(bytes))
      }
    }
  }
  func testMalformedEntropyRestartProgressiveAndInvalidOptionsReject() throws {
    let baseline = try RasterIO.encoded(RasterEncodingOptionsTests().fixture(), type: .jpeg,
      options: .init(jpegFormat: .baseline))
    let records = try JPEGContainer.segments([UInt8](baseline))
    let scan = try XCTUnwrap(records.first { $0.marker == 218 })
    var cases = [Data(), Data(baseline.dropLast()), baseline + Data([0]),
      try RasterIO.encoded(RasterEncodingOptionsTests().fixture(), type: .jpeg,
        options: .init(jpegFormat: .progressive))]
    var restart = baseline
    restart.insert(contentsOf: [255,221,0,4,0,1], at: scan.range.lowerBound); cases.append(restart)
    var wrongHeader = baseline; wrongHeader[scan.payload.upperBound - 2] = 62; cases.append(wrongHeader)
    var truncated = baseline
    let entropy = try XCTUnwrap(scan.entropy)
    truncated.removeSubrange(entropy.lowerBound..<(entropy.upperBound - 1)); cases.append(truncated)
    for data in cases { XCTAssertThrowsError(try JPEGEntropyOptimizer.optimize(data)) }
    for option in [RasterEncodingOptions(jpegQuality: -1), .init(jpegQuality: 13),
      .init(jpegMatte: [0,0]), .init(jpegMatte: [0,0,1.1]), .init(jpegMatte: [0,.nan,0])] {
      XCTAssertThrowsError(try RasterIO.encoded(RasterEncodingOptionsTests().fixture(), type: .jpeg, options: option))
    }
    XCTAssertThrowsError(try RasterEncodingOptions(jpegFormat: .optimized).validate(for: .png))
  }
  func testCancellationPreventsEntropyAndProfileOutput() async throws {
    let data = try RasterIO.encoded(RasterEncodingOptionsTests().fixture(), type: .jpeg)
    for strip in [false, true] {
      let worker = Task {
        while !Task.isCancelled { await Task.yield() }
        return try strip ? JPEGContainer.withoutICC(data) : JPEGEntropyOptimizer.optimize(data)
      }
      worker.cancel()
      do { _ = try await worker.value; XCTFail("Cancelled output returned") }
      catch { XCTAssertTrue(error is CancellationError) }
    }
  }
}
