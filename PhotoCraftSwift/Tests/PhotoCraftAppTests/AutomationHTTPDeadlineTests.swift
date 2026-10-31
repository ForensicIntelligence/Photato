import Foundation
import XCTest
@testable import PhotoCraft

final class AutomationHTTPDeadlineTests: XCTestCase {
  @MainActor func testNativeWorkOutlivesFramingDeadlineAndStillDeliversResponse() async throws {
    let server = AutomationHTTPServer(connectionTimeout: .milliseconds(150))
    defer { server.stop() }
    var port: UInt16?
    var invoked = 0
    var delivery: Bool?
    try server.start(onState: { value, error in
      XCTAssertNil(error); port = value
    }, handler: { _ in
      invoked += 1
      do {
        try await Task.sleep(for: .milliseconds(450))
        return AutomationResponse(status: 200, contentType: "application/octet-stream",
          body: Data("Completed".utf8), didSend: { delivery = $0 })
      } catch {
        XCTFail("Native work was cancelled by the framing deadline: \(error)")
        return .json(["error": "cancelled"], status: 409)
      }
    })
    for _ in 0..<100 where port == nil { try await Task.sleep(for: .milliseconds(20)) }
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(try XCTUnwrap(port))/slow")!)
    request.timeoutInterval = 5
    let (data, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertEqual(data, Data("Completed".utf8))
    for _ in 0..<100 where delivery == nil { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(delivery, true)
    XCTAssertEqual(invoked, 1, "The client must not need to retry a completed native operation.")
  }
}
