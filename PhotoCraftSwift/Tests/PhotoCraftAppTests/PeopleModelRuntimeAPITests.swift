import Foundation
import XCTest
@testable import PhotoCraft

final class PeopleModelRuntimeAPITests: XCTestCase {
  @MainActor func testCapabilitiesDescribeSharedWeakRuntimeWithoutNewCommands() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let response = try await helper.request(service, path: "/v1/capabilities")
      XCTAssertEqual(response.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let people = try XCTUnwrap(json["peopleSelection"] as? [String: Any])
      let runtime = try XCTUnwrap(people["modelRuntime"] as? [String: Any])
      XCTAssertEqual(runtime["lazyLoad"] as? Bool, true)
      XCTAssertEqual(runtime["serializedInference"] as? Bool, true)
      XCTAssertEqual(runtime["poolRetainsProvider"] as? Bool, false)
      XCTAssertEqual(people["commands"] as? [String], PeopleAPI.commands)
      XCTAssertEqual(people["minimumMacOS"] as? String, "14.0")
      XCTAssertEqual(people["onDevice"] as? Bool, true)
      XCTAssertFalse((runtime["remaining"] as? String ?? "").isEmpty)
    }
  }
}
