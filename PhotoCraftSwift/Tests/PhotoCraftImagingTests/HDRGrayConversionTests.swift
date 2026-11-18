import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class HDRGrayConversionTests: XCTestCase {
  private struct Reference: Decodable {
    let name: String
    let inputICCSHA256: String
    let inputSamplesSHA256: String
    let graySamplesSHA256: String
  }

  private func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func fixtureURL(_ name: String, _ fileExtension: String) throws -> URL {
    try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: fileExtension,
      subdirectory: "Fixtures/hdr-rgb-gray"))
  }

  func testLinearRGBGrayscaleMatchesTheSavedPhotoshopPlanes() throws {
    let rows = try JSONDecoder().decode([Reference].self,
      from: Data(contentsOf: try fixtureURL("references", "json")))
    XCTAssertEqual(Set(rows.map(\.name)), Set(["linear-32", "authored-adobe-32", "authored-p3-32",
      "cycle-primaries-32", "custom-y-32", "near-y-32", "same-y-other-chromaticity-32",
      "srgb-shift-65-32", "srgb-shift-66-32"]))
    let width = 128, height = 40, count = width * height
    let levels: [Float] = [-0.375, -0.125, 0, 0.015625, 0.03125, 0.0625, 0.125, 0.25,
      0.375, 0.5, 0.625, 0.75, 0.875, 1, 1.25, 1.5, 2.5]
    var pixels: [Pixel] = []
    pixels.reserveCapacity(count)
    for r in levels {
      for g in levels {
        for b in levels { pixels.append(Pixel(r, g, b, 1)) }
      }
    }
    let remaining = count - pixels.count
    for i in 0..<remaining {
      let divisor = Double(remaining)
      pixels.append(Pixel(Float(Double(i) / divisor), Float(Double(remaining - 1 - i) / divisor),
        Float(Double((i * 41) % remaining) / divisor), 1))
    }
    func append(_ value: Float, to bytes: inout Data) {
      var word = value.bitPattern.bigEndian
      withUnsafeBytes(of: &word) { bytes.append(contentsOf: $0) }
    }
    var originalSamples = Data()
    let components: [(Pixel) -> Float] = [{ $0.r }, { $0.g }, { $0.b }]
    for component in components {
      for pixel in pixels { append(component(pixel), to: &originalSamples) }
    }

    for row in rows {
      let icc = try Data(contentsOf: fixtureURL(row.name, "icc"))
      XCTAssertEqual(sha(icc), row.inputICCSHA256, row.name)
      XCTAssertEqual(sha(originalSamples), row.inputSamplesSHA256, row.name)
      var source = try CraftDocument(width: width, height: height, depth: .f32)
      source.workingICC = icc
      var input = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
      for (i, pixel) in pixels.enumerated() { input.setLinearPixel(x: i % width, y: i / width, pixel) }
      source.layers[0].content = .raster(input)
      source.layers[0].background = true
      let profile = try ColorSettings().conversionProfile(from: source, to: .grayscale, depth: .f32)
      let command = try DocumentModeInput.command(.init(.init(mode: .grayscale, depth: .f32, profile: profile)), in: source)
      var result = source
      try command.apply(to: &result)
      XCTAssertTrue(result.layers[0].isBackground)
      let gray = try XCTUnwrap(result.layers[0].nativeMode)
      XCTAssertTrue(gray.isOpaque)
      XCTAssertEqual(gray.profile, profile)
      var samples = Data()
      for i in 0..<count { append(gray.value(component: 0, index: i), to: &samples) }
      XCTAssertEqual(sha(samples), row.graySamplesSHA256, row.name)
      if let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try samples.write(to: URL(fileURLWithPath: capture).appendingPathComponent("gray-\(row.name).be-f32"))
      }
    }
  }

  func testRetainedRGBConvertsHiddenColorWithoutTouchingAlphaOrLayerMask() throws {
    let icc = try Data(contentsOf: fixtureURL("linear-32", "icc"))
    var source = try CraftDocument(width: 4, height: 1, depth: .f32)
    source.modeDescriptor = try .init(mode: .rgb, depth: .f32, profile: icc)
    var raster = try NativeModeRaster(width: 4, height: 1, mode: .rgb, depth: .f32, profile: icc)
    let samples: [Pixel] = [Pixel(2.5, 0, 0, 0), Pixel(0, -0.375, 0, 0.125),
      Pixel(0, 0, 1, 0.75), Pixel(1, 1, 1, 1)]
    for (i, p) in samples.enumerated() {
      for (c, x) in [p.r, p.g, p.b, p.a].enumerated() { try raster.set(x, component: c, index: i) }
    }
    source.layers[0].nativeMode = raster
    source.layers[0].content = .raster(try raster.surface())
    let mask = try Surface(width: 4, height: 1, depth: .f32, fill: Pixel(0.5, 0.5, 0.5))
    source.layers[0].mask = mask

    let result = try source.convertingMode(.init(mode: .grayscale, depth: .f32))
    let gray = try XCTUnwrap(result.layers[0].nativeMode)
    let expected: [Float] = [0.5562113523483276, -0.26883941888809204, 0.06061035394668579, 1]
    XCTAssertEqual((0..<4).map { gray.value(component: 0, index: $0) }, expected)
    XCTAssertEqual(try gray.planeBytes(1), try raster.planeBytes(3))
    XCTAssertEqual(result.layers[0].mask, mask)
  }
}

