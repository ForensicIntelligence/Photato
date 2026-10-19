import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class ClassicGradientMapRenderTests: XCTestCase {
  private let cases = [
    "new-random33-partial", "coincident", "holdout-random17-linear", "color-matrix",
  ]
  private var root: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }
  private func fixture(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(
          forResource: "photoshop-classic-\(name)-rgb16", withExtension: "psd",
          subdirectory: "Fixtures")))
  }
  private func merged(_ data: Data) throws -> [UInt16] {
    let channels = Int(data[12]) << 8 | Int(data[13])
    XCTAssertTrue(channels == 3 || channels == 4)
    let height = Int(data[14]) << 24 | Int(data[15]) << 16 | Int(data[16]) << 8 | Int(data[17])
    let width = Int(data[18]) << 24 | Int(data[19]) << 16 | Int(data[20]) << 8 | Int(data[21])
    let pixels = width * height
    var reader = PSDReader(data: data, offset: 26)
    for _ in 0..<3 { _ = try reader.section() }
    let decoded = try PSDChannelCodec.decode(
      reader.bytes(reader.remaining), width: width, height: height,
      depth: 16, channels: channels)
    var result: [UInt16] = []
    result.reserveCapacity(pixels * 4)
    for i in 0..<pixels {
      for c in 0..<4 {
        let at = (c * pixels + i) * 2
        result.append(c < channels ? UInt16(decoded[at]) << 8 | UInt16(decoded[at + 1]) : 65535)
      }
    }
    return result
  }
  private func compare(_ actual: [UInt16], _ expected: [UInt16], name: String) -> [String: Any] {
    XCTAssertEqual(actual.count, expected.count)
    var changed = 0
    var maximum = 0
    var alphaChanged = 0
    for i in stride(from: 0, to: expected.count, by: 4) {
      var differs = false
      for c in 0..<4 {
        let difference = abs(Int(actual[i + c]) - Int(expected[i + c]))
        maximum = max(maximum, difference)
        if difference > 0 { differs = true }
        if c == 3 && difference > 0 { alphaChanged += 1 }
      }
      if differs { changed += 1 }
    }
    XCTAssertEqual(changed, 0, "\(name): maximum \(maximum) stored levels; alpha \(alphaChanged)")
    return [
      "name": name, "pixels": expected.count / 4, "changed_pixels": changed,
      "maximum_stored_error": maximum, "alpha_changed_pixels": alphaChanged,
      "byte_identical": changed == 0,
    ]
  }
  func testIndependentPhotoshopClassicCompositionAndAlpha() throws {
    var results: [[String: Any]] = []
    for name in cases {
      let bytes = try fixture(name)
      let document = try PSDCodec.read(bytes)
      let surface = try Renderer.composite(document)
      var actual: [UInt16] = []
      for y in 0..<document.height {
        for x in 0..<document.width {
          let p = PSDMergedSample.encode(surface.pixel(x: x, y: y), depth: 16)
          actual += [p.r, p.g, p.b, p.a].map { UInt16(($0 * 65535).rounded()) }
        }
      }
      results.append(compare(actual, try merged(bytes), name: name))
    }
    try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
      .write(to: root.appendingPathComponent("artifacts/classic-gradient-map-reference.json"))
  }
  func testNativeArchiveAndPSDExportPreserveQualifiedPixelsAndControls() throws {
    for name in cases {
      let bytes = try fixture(name)
      let document = try PSDCodec.read(bytes)
      let archived = try NativeArchive.decode(NativeArchive.encode(document))
      XCTAssertEqual(archived, document)
      let exported = try PSDCodec.writeRasterLayers(archived)
      _ = compare(try merged(exported), try merged(bytes), name: "export-\(name)")
      let restored = try PSDCodec.read(exported)
      XCTAssertEqual(restored.layers.last?.content, document.layers.last?.content)
      try exported.write(
        to: root.appendingPathComponent("artifacts/classic-gradient-map-\(name)-native.psd"))
    }
  }
}
