import Foundation
import XCTest
@testable import PhotoCraftCore

final class ImageStackStatisticsTests: XCTestCase {
  struct Fixture: Decodable {
    struct Row: Decodable { let name: String; let inputs: [Float]; let expectedWords: [String: UInt32] }
    let cases: [Row]
  }
  func testDocumentedMomentsAndEntropyMatchIndependentFloatWords() throws {
    let url = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/ImageStack/documented-statistics.json")
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    var captured: [String: [String: UInt32]] = [:]
    for row in fixture.cases {
      var words: [String: UInt32] = [:]
      for (name, expected) in row.expectedWords {
        let mode = try XCTUnwrap(ImageStackMode(rawValue: name))
        let result = mode.statistic(row.inputs)
        XCTAssertTrue(result.isFinite, row.name + ":" + name)
        XCTAssertEqual(result.bitPattern, expected, row.name + ":" + name)
        words[name] = result.bitPattern
      }
      captured[row.name] = words
    }
    XCTAssertEqual(fixture.cases.count, 14)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let folder = URL(fileURLWithPath: path)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: ["cases": captured], options: [.prettyPrinted, .sortedKeys])
        .write(to: folder.appendingPathComponent("documented-stack-statistics.json"))
    }
  }
  func testUnchangedOrderStatisticsAndFiniteDegeneratePolicy() {
    let values: [Float] = [0, 0.5, 1]
    for (mode, expected): (ImageStackMode, Float) in [(.minimum, 0), (.maximum, 1), (.range, 1), (.mean, 0.5), (.median, 0.5), (.summation, 1.5)] {
      XCTAssertEqual(mode.statistic(values), expected)
    }
    XCTAssertEqual(ImageStackMode.variance.statistic([0, 1]), 0.5)
    XCTAssertEqual(ImageStackMode.kurtosis.statistic([0, 1]), 0.5)
    XCTAssertLessThan(ImageStackMode.skewness.statistic([0, 0.75, 1, 1]), 0)
    XCTAssertGreaterThan(ImageStackMode.entropy.statistic([0, 0.5, 1]), 1)
    XCTAssertEqual(ImageStackMode.entropy.statistic([2, 4, 8]), ImageStackMode.entropy.statistic([0, 0.5, 1]))
    for mode in ImageStackMode.allCases { XCTAssertEqual(mode.statistic([]), 0) }
    for mode: ImageStackMode in [.variance, .standardDeviation, .skewness, .kurtosis] {
      XCTAssertEqual(mode.statistic([0.25]), 0)
      XCTAssertEqual(mode.statistic([0.5, 0.5, 0.5]), 0)
    }
  }
}
