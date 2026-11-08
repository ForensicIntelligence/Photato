import Foundation
import XCTest
@testable import PhotoCraftAI

final class AppleTextRuntimeTests: XCTestCase {
  func testReadyCloudModelStillRequiresSupportedPlatformAndSignedEntitlement() {
    for major in [14, 25, 26, 27, 28] {
      for arm in [false, true] { for entitled in [false, true] {
        let value = LocalAI.cloudTextCapability(majorVersion: major, isAppleSilicon: arm,
          hasEntitlement: entitled, modelReason: .ready)
        XCTAssertEqual(value.available, major >= 27 && arm && entitled)
        XCTAssertEqual(value.reason, !arm ? .deviceNotEligible : major < 27 ? .unsupportedSystem : !entitled ? .missingEntitlement : .ready)
        if arm && major >= 27 && !entitled { XCTAssertTrue(value.message.contains("PCC-enabled")) }
      } }
    }
  }
  func testSignedCloudReadinessKeepsDeviceSystemAndUnknownFailuresDistinct() {
    for reason in [AICapabilityReason.deviceNotEligible, .systemNotReady, .frameworkUnavailable, .unknown] {
      let value = LocalAI.cloudTextCapability(majorVersion: 27, isAppleSilicon: true,
        hasEntitlement: true, modelReason: reason)
      XCTAssertFalse(value.available); XCTAssertEqual(value.reason, reason); XCTAssertFalse(value.message.isEmpty)
    }
    let ready = LocalAI.cloudTextCapability(majorVersion: 27, isAppleSilicon: true,
      hasEntitlement: true, modelReason: .ready)
    XCTAssertTrue(ready.message.contains("Your instruction is sent"))
    XCTAssertTrue(ready.message.contains("No image pixels"))
  }
  func testExistingCapabilityInitializerRetainsCallersAndExplicitReasons() {
    XCTAssertEqual(AICapability(available: true, message: "Owned provider").reason, .ready)
    XCTAssertEqual(AICapability(available: false, message: "Owned unavailable provider").reason, .unknown)
    let disabled = AICapability(available: false, message: "Enable Apple Intelligence", reason: .appleIntelligenceNotEnabled)
    XCTAssertEqual(disabled.reason, .appleIntelligenceNotEnabled)
    XCTAssertFalse(LocalAI.platformCapability(majorVersion: 14, isAppleSilicon: true).available)
    XCTAssertEqual(LocalAI.platformCapability(majorVersion: 14, isAppleSilicon: true).reason, .unsupportedSystem)
    XCTAssertEqual(LocalAI.platformCapability(majorVersion: 27, isAppleSilicon: false).reason, .deviceNotEligible)
  }
  func testCurrentNativeRuntimeReportsAdmissionWithoutInvokingInference() throws {
    let cloud = LocalAI.privateCloudComputeCapability, text = LocalAI.textCapability, image = LocalAI.imageCapability
    XCTAssertEqual(EditPlanProvider.privateCloudCompute.capability, cloud)
    if cloud.available { XCTAssertTrue(LocalAI.privateCloudComputeEntitled); XCTAssertEqual(cloud.reason, .ready) }
    #if arch(arm64)
    if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 && !LocalAI.privateCloudComputeEntitled {
      XCTAssertEqual(cloud.reason, .missingEntitlement); XCTAssertFalse(cloud.available)
    }
    #else
    XCTAssertEqual(cloud.reason, .deviceNotEligible); XCTAssertFalse(cloud.available)
    #endif
    for capability in [cloud, text, image] {
      XCTAssertFalse(capability.message.isEmpty)
      XCTAssertEqual(capability.available, capability.reason == .ready)
    }
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let values: [String: Any] = ["inferenceInvoked": false,
        "PCCSignedEntitlement": LocalAI.privateCloudComputeEntitled,
        "text": ["available": text.available, "reason": text.reason.rawValue, "message": text.message],
        "image": ["available": image.available, "reason": image.reason.rawValue, "message": image.message],
        "cloud": ["available": cloud.available, "reason": cloud.reason.rawValue, "message": cloud.message]]
      try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted])
        .write(to: URL(fileURLWithPath: path).appendingPathComponent("apple-native-runtime.json"))
    }
  }
  func testOptionalManagedTemplatePreservesOrdinarySigningAndAllSandboxPermissions() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let ordinary = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("scripts/Photato-AppStore.entitlements")), format: nil) as? [String: Any])
    let optional = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("scripts/Photato-PCC.entitlements")), format: nil) as? [String: Any])
    let key = "com.apple.developer.private-cloud-compute"
    XCTAssertNil(ordinary[key]); XCTAssertEqual(optional[key] as? Bool, true)
    var expected = ordinary; expected[key] = true
    XCTAssertEqual(optional as NSDictionary, expected as NSDictionary)
    XCTAssertEqual(ordinary["com.apple.security.app-sandbox"] as? Bool, true)
  }
  func testInvalidInstructionsRejectBeforeEitherModelCanStart() async {
    for provider in EditPlanProvider.allCases {
      do { _ = try await NativeEditPlanner.propose(" \n ", provider: provider); XCTFail("Blank instruction accepted") }
      catch LocalAIError.invalidPrompt { }
      catch { XCTFail("Unexpected error: \(error)") }
    }
  }
}
