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
    let fixedGamma: Int?
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
    for reference in try references() where reference.fixedGamma == nil && !reference.profile.hasSuffix("gamma128")
      && (reference.profile.contains("gamma") || reference.profile.contains("parametric")) {
      try assertReference(reference)
    }
  }

  func testHalfGammaPrecisionPromotionMatchesRGBAndGrayAtBothSourceDepths() throws {
    let cases = try references().filter { $0.profile.hasSuffix("gamma128") }
    XCTAssertEqual(Set(cases.map(\.caseName)), Set(["owned-gray-gamma128-8", "owned-gray-gamma128-16",
      "owned-rgb-gamma128-8", "owned-rgb-gamma128-16"]))
    for reference in cases { try assertReference(reference) }
  }

  func testPowerPromotionMatchesPhotoshopAcrossTheDirectAndInterpolatedBoundaries() throws {
    let cases = try references().filter { $0.fixedGamma != nil }
    let gray = [1, 102, 103, 127, 640, 641].flatMap { gamma in
      [8, 16].map { "gamma-gray-\(gamma)-\($0)" }
    } + ["gamma-gray-4096-16", "gamma-gray-65535-16"]
    let rgb = [102, 103, 127].flatMap { gamma in
      [8, 16].map { "gamma-rgb-\(gamma)-\($0)" }
    }
    XCTAssertEqual(Set(cases.map(\.caseName)), Set(gray + rgb))
    for reference in cases { try assertReference(reference) }
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

  func testMergeKeepsTheGrayWorkingProfileBeforePrecisionPromotion() throws {
    let row = try XCTUnwrap(references().first { $0.caseName == "owned-gray-gamma18-16" })
    var source = try fixture(row)
    XCTAssertEqual(source.colorMode, .grayscale)
    var hidden = source.layers[0]
    hidden.id = UUID()
    hidden.visible = false
    hidden.background = nil
    source.layers.append(hidden)
    source.activeLayerID = hidden.id
    let conversion = DocumentModeConversion(mode: .grayscale, depth: .f32)
    let expected = try source.convertingMode(conversion)
    let command = try DocumentModeInput.command(.init(conversion, mergeVisible: true), in: source)
    var merged = source
    try command.apply(to: &merged)
    XCTAssertEqual(merged.layers.count, 1)
    XCTAssertEqual(merged.activeLayerID, hidden.id)
    XCTAssertEqual(merged.modeDescriptor, expected.modeDescriptor)
    XCTAssertEqual(try merged.layers[0].nativeMode?.planes, try expected.layers[0].nativeMode?.planes)
  }

  func testTranslucentRGB16MergeUsesTheWorkingGridBeforePrecisionPromotion() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "owned-rgb-gamma128", withExtension: "icc",
      subdirectory: "Fixtures/sdr-hdr"))
    let profile = try Data(contentsOf: url)
    var source = try CraftDocument(width: 3, height: 1, depth: .u16)
    source.modeDescriptor = try .init(mode: .rgb, depth: .u16, profile: profile)
    func layer(_ name: String, colors: [[Int]], alpha: [Int]) throws -> Layer {
      var native = try NativeModeRaster(width: 3, height: 1, mode: .rgb, depth: .u16, profile: profile)
      for (index, components) in colors.enumerated() {
        for (channel, value) in (components + [alpha[index]]).enumerated() {
          try native.set(Float(value) / 32_768, component: channel, index: index)
        }
      }
      var layer = Layer(name: name, content: .raster(try native.surface()))
      layer.nativeMode = native
      return layer
    }
    let base = try layer("Background", colors: [[9276, 27363, 19824], [18473, 31732, 26267],
      [158, 13219, 26762]], alpha: [32768, 32768, 32768])
    let overlay = try layer("Overlay", colors: [[209, 22777, 14101], [10494, 2061, 20340],
      [231, 24861, 23268]], alpha: [53 * 512, 26 * 512, 53 * 512])
    source.layers = [base, overlay]
    source.activeLayerID = overlay.id
    let operation = DocumentModeRequest(.init(mode: .rgb, depth: .f32), mergeVisible: true)
    let command = try DocumentModeInput.command(operation, in: source)
    var merged = source
    try command.apply(to: &merged)
    let converted = try XCTUnwrap(merged.layers.first?.nativeMode)
    // Three observed rounding cases from an independently saved Photoshop merge.
    #if arch(x86_64)
    let expected: [[UInt32]] = [[0x3e6dca32, 0x3f2e8a16, 0x3da70b7f],
      [0x3f59182e, 0x3f46622b, 0x3f55d286], [0x3f2db1f4, 0x3f5a71cb, 0x3f5a7d83]]
    #else
    let expected: [[UInt32]] = [[0x3e6d0000, 0x3f2e8000, 0x3da70000],
      [0x3f588000, 0x3f458000, 0x3f550000], [0x3f2d8000, 0x3f5a0000, 0x3f5a0000]]
    #endif
    for channel in expected.indices {
      XCTAssertEqual((0..<3).map { converted.rawWord(component: channel, index: $0) }, expected[channel])
    }
  }
}
