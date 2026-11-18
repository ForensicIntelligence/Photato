import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class SDRToHDRConversionTests: XCTestCase {
  private struct Reference: Decodable {
    let caseName: String
    let profile: String
    let inputFileSHA256: String
    let sourceICC: String
    let sampleSHA256: String
    let intelSampleSHA256: String
    let width: Int
    let height: Int
    let mode: Int
    let channels: Int
    let depth: Int
    let samples: Int
  }

  private func references() throws -> [Reference] {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "references", withExtension: "json",
      subdirectory: "Fixtures/sdr-hdr"))
    return try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
  }

  private func fixture(_ row: Reference) throws -> CraftDocument {
    let url = try XCTUnwrap(Bundle.module.url(forResource: row.profile, withExtension: "icc",
      subdirectory: "Fixtures/sdr-hdr"))
    let profile = try Data(contentsOf: url)
    XCTAssertEqual(SHA256.hash(data: profile).map { String(format: "%02x", $0) }.joined(), row.sourceICC)
    let maxWord = row.depth == 8 ? 255 : 65_535
    let steps = row.depth == 8 ? 255 : 32_768
    let pixels = row.width * row.height
    var writer = PSDWriter()
    writer.text("8BPS"); writer.n(1, 2); writer.n(0, 6)
    writer.n(row.channels, 2); writer.n(row.height, 4); writer.n(row.width, 4)
    writer.n(row.depth, 2); writer.n(row.mode, 2)
    writer.section(Data())
    writer.section(PSDImageResources.block(1039, data: profile))
    writer.section(Data())
    writer.n(0, 2)
    for c in 0..<row.channels {
      for i in 0..<pixels {
        let level = ((i + c * (pixels / 3)) % pixels) % (steps + 1)
        writer.n((level * maxWord + steps / 2) / steps, row.depth / 8)
      }
    }
    XCTAssertEqual(SHA256.hash(data: writer.data).map { String(format: "%02x", $0) }.joined(),
      row.inputFileSHA256, row.caseName)
    return try PSDCodec.read(writer.data)
  }

  private func assertReference(_ reference: Reference) throws {
    let source = try fixture(reference)
    let profile = try ColorSettings().conversionProfile(from: source, to: source.colorMode, depth: .f32)
    let request = DocumentModeRequest(.init(mode: source.colorMode, depth: .f32, profile: profile))
    let edit = try DocumentModeInput.command(request, in: source)
    var result = source
    try edit.apply(to: &result)
    let native = try XCTUnwrap(result.layers.first?.nativeMode)
    XCTAssertEqual(native.profile, profile, reference.caseName)
    XCTAssertEqual(native.depth, .f32)
    XCTAssertTrue(native.isOpaque)
    var samples = Data()
    samples.reserveCapacity(reference.samples * 4)
    for component in 0..<reference.channels {
      for i in 0..<(reference.width * reference.height) {
        var word = native.rawWord(component: component, index: i).bigEndian
        withUnsafeBytes(of: &word) { samples.append(contentsOf: $0) }
      }
    }
    if let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try samples.write(to: URL(fileURLWithPath: capture).appendingPathComponent(reference.caseName + ".be-f32"))
    }
    #if arch(x86_64)
    let expected = reference.intelSampleSHA256
    #else
    let expected = reference.sampleSHA256
    #endif
    XCTAssertEqual(SHA256.hash(data: samples).map { String(format: "%02x", $0) }.joined(),
      expected, reference.caseName)
  }

  func testSampledAndLinearPrecisionPromotionMatchesEveryPhotoshopSample() throws {
    for reference in try references() where reference.profile.contains("curves") || reference.profile.contains("linear") {
      try assertReference(reference)
    }
  }

  func testPowerAndParametricPrecisionPromotionProducesReferencePlanes() throws {
    for reference in try references() where reference.profile.contains("gamma") || reference.profile.contains("parametric") {
      try assertReference(reference)
    }
  }

  func testDifferentLinearDestinationStillUsesICCAndPreservesSourceAlpha() throws {
    let reference = try XCTUnwrap(references().first { $0.caseName == "owned-rgb-curves-8" })
    var source = try fixture(reference)
    guard case .raster(var samples) = source.layers[0].content else {
      return XCTFail("The source should be an RGB raster.")
    }
    samples.setPixel(x: 1, y: 0, Pixel(0.3, 0.6, 0.9, 0.35))
    source.layers[0].content = .raster(samples)
    let defaultResult = try source.convertingMode(.init(mode: .rgb, depth: .f32))
    let preserved = try XCTUnwrap(defaultResult.layers[0].nativeMode)
    XCTAssertEqual(preserved.value(component: 3, index: 1), samples.pixel(x: 1, y: 0).a)

    let otherProfile = try NativeModeProfile.standard(.rgb, depth: .f32)
    XCTAssertNotEqual(otherProfile, preserved.profile)
    let explicit = try source.convertingMode(.init(mode: .rgb, depth: .f32, profile: otherProfile))
    let baseline = try NativeModeRaster.converting(samples, to: .rgb, depth: .f32, profile: otherProfile,
      sourceProfile: source.workingICC)
    XCTAssertEqual(try explicit.layers[0].nativeMode?.planes, try baseline.planes)
    XCTAssertNotEqual(try preserved.planeBytes(0), try baseline.planeBytes(0))
  }
}
