import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AdobeLayerProtectionTests: XCTestCase {
  func testOmittedNullAndEmptyAreContextual() throws {
    for value: Any? in [nil, NSNull(), [String]()] {
      XCTAssertEqual(try AdobeLayerProtection.parse(value, addingLayer: false), .unchanged)
      XCTAssertEqual(try AdobeLayerProtection.parse(value, addingLayer: true), .replace([]))
    }
    for adding in [false, true] {
      XCTAssertEqual(try AdobeLayerProtection.parse(["none"], addingLayer: adding), .replace([]))
      XCTAssertEqual(try AdobeLayerProtection.parse(["all"], addingLayer: adding),
        .replace(.fullyLocked))
    }
  }

  func testAllPartialFlagSubsetsAndRepeatedFlags() throws {
    let pairs: [(String, LayerProtection)] = [
      ("transparency", .transparency), ("composite", .image),
      ("position", .position), ("artboard_autonest", .autoNest),
    ]
    for mask in 1..<16 {
      let chosen = pairs.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
      let expected = chosen.reduce(LayerProtection()) { $0.union($1.1) }
      XCTAssertEqual(try AdobeLayerProtection.parse(chosen.map(\.0), addingLayer: false),
        .replace(expected))
      XCTAssertEqual(try AdobeLayerProtection.parse(chosen.map(\.0) + chosen.map(\.0),
        addingLayer: true), .replace(expected))
    }
  }

  func testInvalidShapeAndExclusiveFlagsUseAdobeErrorEnvelope() {
    let invalid: [Any] = [
      "all", 1, true, ["all", "position"], ["none", "none"], ["all", "all"],
      ["none", "all"], ["image"], ["position", "unknown"], [NSNull()], ["all": true],
    ]
    for value in invalid {
      XCTAssertThrowsError(try AdobeLayerProtection.parse(value, addingLayer: false)) { error in
        guard let error = error as? AdobeAPIError else { return XCTFail("Wrong error type") }
        XCTAssertEqual(error.status, 400)
        XCTAssertEqual(error.code, "validation_error")
      }
    }
  }
}
