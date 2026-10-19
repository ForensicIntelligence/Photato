import XCTest

@testable import PhotoCraftAI

final class AITests: XCTestCase {
  func testImageGenerationSupportsLocalAndPrivateCloudCompute() {
    for major in [14, 25] {
      XCTAssertFalse(
        LocalAI.imagePlatformCapability(majorVersion: major, isAppleSilicon: true).available)
    }
    for major in [26, 27, 28] {
      XCTAssertFalse(
        LocalAI.imagePlatformCapability(majorVersion: major, isAppleSilicon: false).available)
      let capability = LocalAI.imagePlatformCapability(majorVersion: major, isAppleSilicon: true)
      XCTAssertTrue(capability.available)
      XCTAssertTrue(
        capability.message.contains(major == 26 ? "on-device" : "Private Cloud Compute"))
    }
    // Text remains local even when the system image service moves to cloud processing.
    XCTAssertTrue(LocalAI.platformCapability(majorVersion: 27, isAppleSilicon: true).available)
  }
  func testCapabilityMatrix() {
    XCTAssertFalse(LocalAI.platformCapability(majorVersion: 14, isAppleSilicon: true).available)
    XCTAssertFalse(LocalAI.platformCapability(majorVersion: 26, isAppleSilicon: false).available)
    XCTAssertTrue(LocalAI.platformCapability(majorVersion: 26, isAppleSilicon: true).available)
    XCTAssertTrue(LocalAI.platformCapability(majorVersion: 27, isAppleSilicon: true).available)
  }
  func testPromptValidation() throws {
    XCTAssertThrowsError(try LocalAI.validatePrompt("  \n"))
    XCTAssertThrowsError(try LocalAI.validatePrompt(String(repeating: "a", count: 1001)))
    XCTAssertEqual(try LocalAI.validatePrompt("  blue mountains "), "blue mountains")
  }
  func testInvalidPromptsFailBeforeInvokingModel() async {
    XCTAssertFalse(LocalAI.imageCapability.message.isEmpty)
    do {
      _ = try await LocalAI.refinePrompt("")
      XCTFail("Expected failure")
    } catch { XCTAssertTrue(error is LocalAIError) }
  }
}
