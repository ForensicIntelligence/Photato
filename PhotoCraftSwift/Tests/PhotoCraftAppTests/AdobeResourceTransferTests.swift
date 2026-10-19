import Foundation
import XCTest

@testable import PhotoCraft

final class AdobeResourceTransferTests: XCTestCase {
  private func configured(_ handler: @escaping @Sendable (ResourceURLProtocol) -> Void) -> (
    URLRequest, URLSessionConfiguration
  ) {
    let url = URL(string: "https://resource.example.test/\(UUID().uuidString)")!
    ResourceURLProtocol.handlers.set(url, handler)
    addTeardownBlock { ResourceURLProtocol.handlers.remove(url) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResourceURLProtocol.self]
    return (URLRequest(url: url), configuration)
  }
  private func receive(
    _ handler: @escaping @Sendable (ResourceURLProtocol) -> Void,
    limit: Int = 4
  ) async throws -> Data {
    let (request, configuration) = configured(handler)
    return try await AdobeResourceTransfer.perform(
      request, maximumBytes: limit, configuration: configuration)
  }
  func testStreamingDataIsBoundedWithoutDependingOnContentLength() async throws {
    let data = try await receive { item in
      item.respond(status: 200)
      item.client?.urlProtocol(item, didLoad: Data([1, 2]))
      item.client?.urlProtocol(item, didLoad: Data([3, 4]))
      item.client?.urlProtocolDidFinishLoading(item)
    }
    XCTAssertEqual(data, Data([1, 2, 3, 4]))
    do {
      _ = try await receive { item in
        item.respond(status: 200)
        item.client?.urlProtocol(item, didLoad: Data([1, 2, 3]))
        item.client?.urlProtocol(item, didLoad: Data([4, 5]))
        item.client?.urlProtocolDidFinishLoading(item)
      }
      XCTFail("Unknown-length overflow accepted")
    } catch { XCTAssertEqual((error as? AdobeAPIError)?.code, "validation_error") }
  }
  func testOversizedDeclaredLengthAndUnsuccessfulOrPartialHTTPAreRejected() async throws {
    for (status, headers) in [(200, ["Content-Length": "500"]), (404, [:]), (206, [:]), (500, [:])]
    {
      do {
        _ = try await receive { item in
          item.respond(status: status, headers: headers)
          item.client?.urlProtocolDidFinishLoading(item)
        }
        XCTFail("Accepted HTTP \(status) \(headers)")
      } catch { XCTAssertNotNil(error as? AdobeAPIError) }
    }
  }
  func testRedirectDoesNotForwardRequestToSecondResource() async throws {
    let redirected = URL(string: "https://redirected.example.test/private")!
    do {
      _ = try await receive { item in
        let response = HTTPURLResponse(
          url: item.request.url!, statusCode: 302,
          httpVersion: "HTTP/1.1", headerFields: ["Location": redirected.absoluteString])!
        item.client?.urlProtocol(
          item, wasRedirectedTo: URLRequest(url: redirected), redirectResponse: response)
      }
      XCTFail("Redirect accepted")
    } catch { XCTAssertEqual((error as? AdobeAPIError)?.status, 422) }
  }
  func testCancellationBeforeAndDuringTransferCompletesWithoutWaitingForTimeout() async throws {
    let started = expectation(description: "Transfer started")
    let (request, configuration) = configured { _ in started.fulfill() }
    let task = Task {
      try await AdobeResourceTransfer.perform(
        request, maximumBytes: 4, configuration: configuration)
    }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled transfer returned data")
    } catch { XCTAssertTrue(error is CancellationError) }
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await AdobeResourceTransfer.perform(
        request, maximumBytes: 4, configuration: configuration)
    }
    do {
      _ = try await cancelled.value
      XCTFail("Already-cancelled transfer started")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testNativeRequestsDoNotUseAmbientAuthenticationAndRetainOutputConditions() throws {
    let url = URL(string: "https://example.test/blob?sig=provided")!
    let get = try NativeAdobeResourceTransport.fetchRequest(url)
    XCTAssertEqual(get.httpMethod, "GET")
    XCTAssertNil(get.value(forHTTPHeaderField: "Authorization"))
    for overwrite in [nil, true, false] as [Bool?] {
      let output = AdobeActionsRequest.Output(
        mediaType: .psd,
        destination: .external(url, storageType: "azure"), shouldOverwrite: overwrite)
      let put = try NativeAdobeResourceTransport.uploadRequest(Data([1, 2]), output: output)
      XCTAssertEqual(put.httpMethod, "PUT")
      XCTAssertEqual(put.httpBody, Data([1, 2]))
      XCTAssertEqual(put.value(forHTTPHeaderField: "Content-Type"), "image/vnd.adobe.photoshop")
      XCTAssertEqual(put.value(forHTTPHeaderField: "x-ms-blob-type"), "BlockBlob")
      XCTAssertEqual(put.value(forHTTPHeaderField: "If-None-Match"), overwrite == false ? "*" : nil)
      XCTAssertNil(put.value(forHTTPHeaderField: "Authorization"))
    }
    for url in [
      "file:///tmp/input.psd", "https://user:password@example.test/in",
      "https://example.test/in#secret",
    ] {
      XCTAssertThrowsError(
        try NativeAdobeResourceTransport.fetchRequest(XCTUnwrap(URL(string: url))))
    }
    for destination in [
      AdobeActionsRequest.Destination.hosted(validityPeriod: 60),
      .external(url, storageType: "dropbox"),
      .external(URL(string: "http://example.test/out")!, storageType: nil),
    ] {
      XCTAssertThrowsError(
        try NativeAdobeResourceTransport.uploadRequest(
          Data(),
          output:
            .init(mediaType: .png, destination: destination, shouldOverwrite: nil)))
    }
  }
  @MainActor func testNativeTransportFetchesExactBytesFromRealLoopbackHTTP() async throws {
    let server = AutomationHTTPServer()
    defer { server.stop() }
    var port: UInt16?
    let data = Data((0..<255).map(UInt8.init))
    try server.start(onState: {
      port = $0
      XCTAssertNil($1)
    }) { _ in
      .init(status: 200, contentType: "image/png", body: data)
    }
    for _ in 0..<100 where port == nil { try await Task.sleep(for: .milliseconds(10)) }
    let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(try XCTUnwrap(port))/resource"))
    let fetched = try await NativeAdobeResourceTransport().fetch(url)
    XCTAssertEqual(fetched, data)
  }
}

private final class ResourceURLProtocol: URLProtocol, @unchecked Sendable {
  static let handlers = ResourceHandlers()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let url = request.url, let handler = Self.handlers.get(url) else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    handler(self)
  }
  override func stopLoading() {}
  func respond(status: Int, headers: [String: String] = [:]) {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
  }
}
private final class ResourceHandlers: @unchecked Sendable {
  typealias Handler = @Sendable (ResourceURLProtocol) -> Void
  private let lock = NSLock()
  private var values: [URL: Handler] = [:]
  func set(_ url: URL, _ handler: @escaping Handler) { lock.withLock { values[url] = handler } }
  func get(_ url: URL) -> Handler? { lock.withLock { values[url] } }
  func remove(_ url: URL) { _ = lock.withLock { values.removeValue(forKey: url) } }
}
