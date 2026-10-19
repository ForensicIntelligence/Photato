import PhotoCraftCore
import XCTest

final class BlendOracleTests: XCTestCase {
  struct Vector: Decodable {
    var mode: Int
    var backdrop: [Float]
    var source: [Float]
    var expected: [Float]
  }
  func testAllModesAgainstOriginalRust() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "blend-oracle", withExtension: "json", subdirectory: "Fixtures"))
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertEqual(vectors.count, 972)
    for v in vectors {
      let b = SIMD3(v.backdrop[0], v.backdrop[1], v.backdrop[2])
      let s = SIMD3(v.source[0], v.source[1], v.source[2])
      let actual = BlendMode.allCases[v.mode].rgb(b, s)
      for c in 0..<3 {
        XCTAssertEqual(
          actual[c], v.expected[c], accuracy: 0.00001,
          "Mode \(BlendMode.allCases[v.mode]), channel \(c), backdrop \(b), source \(s)")
      }
    }
  }
}
