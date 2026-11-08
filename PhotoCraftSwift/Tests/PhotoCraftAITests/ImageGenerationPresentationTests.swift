import XCTest
@testable import PhotoCraftAI

final class ImageGenerationPresentationTests: XCTestCase {
  func testEarlierSystemsExposeNoGenerationConfiguration() {
    for major in [-1, 0, 14, 15, 25] {
      let policy = ImageGenerationPresentation(majorVersion: major)
      XCTAssertTrue(policy.styles.isEmpty)
      XCTAssertNil(policy.defaultStyle)
      XCTAssertFalse(policy.usesCanvasSizeHint)
    }
  }
  func testMacOS26RetainsThreeStylesAndIllustrationDefault() {
    let policy = ImageGenerationPresentation(majorVersion: 26)
    XCTAssertEqual(policy.styles.map(\.rawValue), ["illustration", "animation", "sketch"])
    XCTAssertEqual(policy.defaultStyle, .illustration)
    XCTAssertFalse(policy.usesCanvasSizeHint)
  }
  func testModernConfigurationOffersAnyStyleAndCanvasHint() {
    for major in [27, 28] {
      let policy = ImageGenerationPresentation(majorVersion: major)
      XCTAssertEqual(policy.styles.map(\.rawValue), ["any", "illustration", "animation", "sketch"])
      XCTAssertEqual(policy.defaultStyle, .any)
      XCTAssertTrue(policy.usesCanvasSizeHint)
      XCTAssertFalse(policy.styles.map(\.rawValue).contains("externalProvider"))
    }
  }
}
