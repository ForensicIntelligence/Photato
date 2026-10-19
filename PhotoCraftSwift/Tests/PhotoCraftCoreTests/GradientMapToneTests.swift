import Foundation
import XCTest

@testable import PhotoCraftCore

final class GradientMapToneTests: XCTestCase {
  private struct Tone {
    var r: Int
    var g: Int
    var b: Int
    var index: Int
    func pixel(stored: Bool, alpha: Float = 1) -> Pixel {
      func component(_ value: Int) -> Float {
        stored ? Float((value * 65535 + 16384) / 32768) / 65535 : Float(value) / 32768
      }
      return Pixel(component(r), component(g), component(b), alpha)
    }
  }
  private func tones() throws -> [Tone] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-gradient-map-tone-rgb16", withExtension: "bin",
        subdirectory: "Fixtures"))
    let bytes = [UInt8](try Data(contentsOf: url))
    XCTAssertEqual(Array(bytes.prefix(4)), Array("PTGT".utf8))
    func u32(_ at: Int) -> Int {
      bytes[at..<at + 4].reduce(0) { ($0 << 8) | Int($1) }
    }
    func u16(_ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
    XCTAssertEqual(u32(4), 1)
    let count = u32(8)
    XCTAssertEqual(count, 131072)
    XCTAssertEqual(bytes.count, 12 + count * 8)
    return (0..<count).map { i in
      let at = 12 + i * 8
      return Tone(r: u16(at), g: u16(at + 2), b: u16(at + 4), index: u16(at + 6))
    }
  }
  private func identity() -> GradientDefinition {
    var gradient = GradientDefinition.blackToWhite
    gradient.method = .classic
    gradient.smoothness = 0
    return gradient
  }
  private func identityReference() throws -> [Float] {
    // The separately Photoshop-rendered identity ramp is not numerically equal
    // to its input coordinates after RGB16 Classic output conversion.
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-classic-rgb16", withExtension: "bin", subdirectory: "Fixtures"))
    let bytes = [UInt8](try Data(contentsOf: url))
    XCTAssertEqual(Array(bytes.prefix(4)), Array("PCLS".utf8))
    return (0...4096).map { i in
      let at = 12 + i * 6
      return Float(Int(bytes[at]) << 8 | Int(bytes[at + 1])) / 32768
    }
  }
  func testIndependentPhotoshopRGB16ToneVectors() throws {
    let transfer = try GradientMapTransfer(.init(gradient: identity()), depth: .u16)
    let vectors = try tones()
    let lookup = try identityReference()
    for stored in [false, true] {
      var changed = 0
      var first: Int?
      for (i, tone) in vectors.enumerated() {
        let expected = lookup[tone.index]
        let actual = transfer.apply(tone.pixel(stored: stored))
        if actual != Pixel(expected, expected, expected) {
          changed += 1
          if first == nil { first = i }
        }
      }
      XCTAssertEqual(changed, 0, "stored=\(stored); first difference \(String(describing: first))")
    }
  }
  func testRGB16ReverseAlphaAndInvalidSamples() throws {
    var gradient = identity()
    gradient.opacity = [.init(0, 0), .init(1, 0)]
    let transfer = try GradientMapTransfer(.init(gradient: gradient, reverse: true), depth: .u16)
    let vectors = try tones()
    let lookup = try identityReference()
    var changed = 0
    for i in stride(from: 0, to: vectors.count, by: 257) {
      let tone = vectors[i]
      let expected = lookup[4096 - tone.index]
      let actual = transfer.apply(tone.pixel(stored: true, alpha: 0.37))
      if actual != Pixel(expected, expected, expected, 0.37) { changed += 1 }
    }
    XCTAssertEqual(changed, 0)
    for pixel in [
      Pixel(0.7, 0.2, 0.1, 0), Pixel(.nan, 0, 0), Pixel(.infinity, 0, 0),
      Pixel(0, 0, 0, .nan),
    ] {
      XCTAssertTrue(transfer.apply(pixel).hasSameBits(as: pixel))
    }
    XCTAssertEqual(transfer.apply(Pixel(-1, 2, 0.5)), transfer.apply(Pixel(0, 1, 0.5)))
  }
  private struct LegacyVector: Decodable {
    var settings: GradientMapAdjustment
    var depth: PixelDepth
    var input: [UInt32]
    var output: [UInt32]
    var x: Int
    var y: Int
  }
  func testRGB8AndFloatTransfersKeepPreviousBits() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "gradient-map-other-depths", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([LegacyVector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 224)
    for (i, vector) in vectors.enumerated() {
      let v = vector.input.map { Float(bitPattern: $0) }
      let transfer = try GradientMapTransfer(vector.settings, depth: vector.depth)
      let actual = transfer.apply(Pixel(v[0], v[1], v[2], v[3]), x: vector.x, y: vector.y)
      XCTAssertEqual(
        [actual.r.bitPattern, actual.g.bitPattern, actual.b.bitPattern, actual.a.bitPattern],
        vector.output, "Legacy vector \(i)")
    }
  }
}
