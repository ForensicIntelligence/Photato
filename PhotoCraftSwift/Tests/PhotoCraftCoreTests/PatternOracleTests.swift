import Foundation
import XCTest

@testable import PhotoCraftCore

final class PatternOracleTests: XCTestCase {
  struct Reader {
    let data: Data
    var offset = 0
    init(_ name: String) throws {
      data = try Data(
        contentsOf: XCTUnwrap(
          Bundle.module.url(
            forResource: name,
            withExtension: "bin", subdirectory: "Fixtures")))
    }
    mutating func u() -> UInt32 {
      defer { offset += 4 }
      return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }
    mutating func f() -> Float { Float(bitPattern: u()) }
    mutating func string() -> String {
      let length = Int(u())
      defer { offset += length }
      return String(decoding: data[offset..<offset + length], as: UTF8.self)
    }
  }
  func testOriginalRustProceduralPresetsAndIdentifiers() throws {
    var reader = try Reader("pattern-presets-oracle")
    var count = 0
    let patterns = try PatternPresets.make()
    for pattern in patterns {
      XCTAssertEqual(pattern.surface.width, Int(reader.u()))
      XCTAssertEqual(pattern.surface.height, Int(reader.u()))
      XCTAssertEqual(pattern.name, reader.string())
      XCTAssertEqual(pattern.id, reader.string())
      for y in 0..<pattern.surface.height {
        for x in 0..<pattern.surface.width {
          let p = pattern.surface.pixel(x: x, y: y)
          for actual in [p.r, p.g, p.b] {
            XCTAssertEqual(actual.bitPattern, reader.f().bitPattern)
            count += 1
          }
          XCTAssertEqual(p.a, 1)
        }
      }
    }
    XCTAssertEqual(reader.offset, reader.data.count)
    XCTAssertEqual(count, 16_752)
    print("Pattern preset Rust oracle: 7 identifiers and \(count) exact Float32 samples")
  }
  func testOriginalRustWrappedSamplingScaleAngleAndPhase() throws {
    var reader = try Reader("pattern-sampling-oracle")
    var count = 0
    var exact = 0
    var worst: Float = 0
    for _ in 0..<4 {
      let w = Int(reader.u())
      let h = Int(reader.u())
      var surface = try Surface(width: w, height: h, depth: .f32)
      for y in 0..<h {
        for x in 0..<w {
          surface.setPixel(x: x, y: y, Pixel(reader.f(), reader.f(), reader.f(), reader.f()))
        }
      }
      let pattern = try RasterPattern(name: "Oracle", surface: surface)
      for _ in 0..<4 {
        var placement = PatternPlacement()
        placement.scale = reader.f()
        placement.angle = reader.f()
        placement.phaseX = reader.f()
        placement.phaseY = reader.f()
        let sampler = try PatternSampler(pattern, placement: placement)
        for y in -7..<12 {
          for x in -5..<18 {
            let p = sampler.sample(x: Double(x) + 0.5, y: Double(y) + 0.5)
            for actual in [p.r, p.g, p.b, p.a] {
              let expected = reader.f()
              XCTAssertEqual(actual, expected, accuracy: 0.000002)
              if actual.bitPattern == expected.bitPattern { exact += 1 }
              worst = max(worst, abs(actual - expected))
              count += 1
            }
          }
        }
      }
    }
    XCTAssertEqual(reader.offset, reader.data.count)
    XCTAssertEqual(count, 27_968)
    XCTAssertEqual(exact, count, "Pattern sampling must retain every original Rust Float32 bit")
    print(
      "Pattern sampler Rust oracle: \(exact)/\(count) exact Float32 values; maximum error \(worst)")
  }
}
