import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class AdobeActionJobsTests: XCTestCase {
  private func request(outputs: [[String: Any]]? = nil) throws -> AdobeActionsRequest {
    let actions = """
      [{"_obj":"select","_target":[{"_ref":"channel","_enum":"channel","_value":"red"}]},
      {"_obj":"fill","using":{"_enum":"fillContents","_value":"white"},"mode":{"_enum":"blendMode","_value":"normal"},"opacity":{"_unit":"percentUnit","_value":50}}]
      """
    return try AdobeActionsRequest(
      data: JSONSerialization.data(withJSONObject: [
        "image": ["source": ["url": "https://example.test/input.psd?secret=private"]],
        "options": [
          "actions": [["source": ["content": actions, "contentType": "application/json"]]]
        ],
        "outputs": outputs ?? [
          ["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]],
          ["mediaType": "image/png", "destination": ["validityPeriod": 120]],
        ],
      ]))
  }
  private func input() throws -> Data {
    var document = try CraftDocument(width: 3, height: 2)
    var pixels = try Surface(width: 3, height: 2)
    for y in 0..<2 {
      for x in 0..<3 {
        pixels.setPixel(
          x: x, y: y,
          Pixel(
            Float(32 + x) / 255, 96.0 / 255, 192.0 / 255,
            y == 0 ? 1 : (x == 2 ? 1 : Float(x) / 2)))
      }
    }
    document.layers[0].content = .raster(pixels)
    document.resolution = 144
    return try PSDCodec.writeRasterLayers(document)
  }
  @MainActor private func completed(_ jobs: AdobeActionJobs, _ id: UUID) async throws
    -> AdobeActionJobs.Snapshot
  {
    for _ in 0..<200 {
      if let snapshot = jobs.snapshot(id), [.succeeded, .failed].contains(snapshot.status) {
        return snapshot
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Job did not finish")
    return try XCTUnwrap(jobs.snapshot(id))
  }
  private var base: URL { URL(string: "http://127.0.0.1:43210")! }

  @MainActor func testJobsEncodeNativeOutputsAndPreserveOrderExpiryAndStatusShape() async throws {
    let data = try input()
    let request = try request()
    let transport = StubTransport(data: data)
    let clock = TestClock()
    let jobs = AdobeActionJobs(transport: transport, now: { clock.now() })
    defer { jobs.revoke() }
    let submitted = try jobs.submit(request, baseURL: base)
    XCTAssertEqual(submitted.status, .notStarted)
    let result = try await completed(jobs, submitted.id)
    XCTAssertEqual(result.status, .succeeded, result.error?.message ?? "")
    XCTAssertEqual(result.outputs.map(\.mediaType), [.psd, .png])
    let expected = try request.applying(to: AdobeActionAssets.decode(data)).session.document
    let firstID = try XCTUnwrap(UUID(uuidString: result.outputs[0].url.lastPathComponent))
    let secondID = try XCTUnwrap(UUID(uuidString: result.outputs[1].url.lastPathComponent))
    let psd = try XCTUnwrap(jobs.asset(firstID))
    let png = try XCTUnwrap(jobs.asset(secondID))
    XCTAssertEqual(psd.data, try PSDCodec.writeRasterLayers(expected))
    XCTAssertEqual(png.data, try RasterIO.encoded(expected))
    XCTAssertEqual(try RasterIO.read(png.data).depth, .u8)
    let decoded = try PSDCodec.read(psd.data)
    guard case .raster(let actual) = decoded.layers[0].content,
      case .raster(let wanted) = expected.layers[0].content
    else { return XCTFail("Missing raster") }
    XCTAssertEqual(try actual.rgbaData(depth: .u8), try wanted.rgbaData(depth: .u8))
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: result.response.body) as? [String: Any])
    XCTAssertEqual(json["status"] as? String, "succeeded")
    XCTAssertNotNil(
      ISO8601DateFormatter.withFractional.date(from: try XCTUnwrap(json["createdTime"] as? String)))
    XCTAssertNotNil(json["result"])
    XCTAssertNil(json["errorDetails"])
    clock.advance(60)
    XCTAssertNil(jobs.asset(firstID))
    XCTAssertNotNil(jobs.asset(secondID))
    clock.advance(60)
    XCTAssertNil(jobs.asset(secondID))
    XCTAssertNotNil(jobs.snapshot(submitted.id))
    clock.advance(86_400)
    XCTAssertNil(jobs.snapshot(submitted.id))
  }

  @MainActor func testFIFOQueueCapacityAndRevocationCannotPublishLateResults() async throws {
    let transport = StubTransport(data: try input(), paused: true)
    let jobs = AdobeActionJobs(transport: transport, maximumJobs: 2)
    let a = try jobs.submit(request(), baseURL: base)
    let b = try jobs.submit(request(), baseURL: base)
    XCTAssertThrowsError(try jobs.submit(request(), baseURL: base)) {
      XCTAssertEqual(($0 as? AdobeAPIError)?.status, 429)
    }
    try await transport.waitUntilStarted()
    XCTAssertEqual(jobs.snapshot(a.id)?.status, .running)
    XCTAssertEqual(jobs.snapshot(b.id)?.status, .notStarted)
    jobs.revoke()
    XCTAssertNil(jobs.snapshot(a.id))
    XCTAssertNil(jobs.snapshot(b.id))
    await transport.release()
    let fresh = try jobs.submit(request(), baseURL: base)
    let result = try await completed(jobs, fresh.id)
    XCTAssertEqual(result.status, .succeeded)
    XCTAssertNil(jobs.snapshot(a.id))
    XCTAssertNil(jobs.snapshot(b.id))
    let count = await transport.fetchCount
    XCTAssertEqual(count, 2)
    jobs.revoke()
    XCTAssertNil(
      jobs.asset(try XCTUnwrap(UUID(uuidString: result.outputs[0].url.lastPathComponent))))
  }

  @MainActor func testFailuresAndStorageBudgetPublishNoOutputsAndDoNotLeakSignedURLs() async throws
  {
    let invalid = StubTransport(data: Data("not an image".utf8))
    let jobs = AdobeActionJobs(transport: invalid)
    let first = try jobs.submit(request(), baseURL: base)
    let failed = try await completed(jobs, first.id)
    XCTAssertEqual(failed.status, .failed)
    XCTAssertTrue(failed.outputs.isEmpty)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: failed.response.body) as? [String: Any])
    XCTAssertNotNil(json["errorDetails"])
    XCTAssertNil(json["result"])
    jobs.revoke()

    let budget = AdobeActionJobs(transport: StubTransport(data: try input()), maximumStoredBytes: 1)
    let b = try budget.submit(request(), baseURL: base)
    let limited = try await completed(budget, b.id)
    XCTAssertEqual(limited.error?.code, "rate_limit_exceeded")
    XCTAssertTrue(limited.outputs.isEmpty)
    budget.revoke()

    let failing = StubTransport(data: Data(), failFetch: true)
    let privateJobs = AdobeActionJobs(transport: failing)
    let p = try privateJobs.submit(request(), baseURL: base)
    let privateResult = try await completed(privateJobs, p.id)
    XCTAssertEqual(privateResult.error?.code, "resource_error")
    XCTAssertFalse(String(decoding: privateResult.response.body, as: UTF8.self).contains("private"))
    privateJobs.revoke()
  }

  @MainActor func testExternalFailureDoesNotPublishHostedOutputsAndQueueContinues() async throws {
    let transport = StubTransport(data: try input(), failUpload: true)
    let jobs = AdobeActionJobs(transport: transport)
    defer { jobs.revoke() }
    let mixed = try request(outputs: [
      ["mediaType": "image/png", "destination": ["validityPeriod": 60]],
      [
        "mediaType": "image/vnd.adobe.photoshop",
        "destination": ["url": "https://example.test/out.psd"],
      ],
    ])
    let a = try jobs.submit(mixed, baseURL: base)
    let b = try jobs.submit(request(), baseURL: base)
    let failure = try await completed(jobs, a.id)
    let success = try await completed(jobs, b.id)
    XCTAssertEqual(failure.status, .failed)
    XCTAssertTrue(failure.outputs.isEmpty)
    XCTAssertEqual(success.status, .succeeded)
    let uploaded = await transport.uploads
    XCTAssertEqual(uploaded.count, 1)
    XCTAssertTrue(uploaded[0].starts(with: Data("8BPS".utf8)))
  }

  func testImageResourcesUseNativeFilePathAndRejectUnsupportedAndOversizedHeaders() throws {
    let data = try input()
    let decoded = try AdobeActionAssets.decode(data)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("source.png")
    try RasterIO.write(decoded, to: url)
    let png = try Data(contentsOf: url)
    XCTAssertEqual(png, try RasterIO.encoded(decoded))
    let fileDocument = try RasterIO.read(url)
    let memoryDocument = try RasterIO.read(png, name: "source")
    XCTAssertEqual(fileDocument.resolution, memoryDocument.resolution)
    XCTAssertEqual(fileDocument.sourceICC, memoryDocument.sourceICC)
    XCTAssertEqual(fileDocument.layers[0].content, memoryDocument.layers[0].content)
    XCTAssertEqual(try AdobeActionAssets.decode(png).depth, .u8)
    for raw in [Data(), Data("8BPS".utf8), Data("JPEG not accepted".utf8)] {
      XCTAssertThrowsError(try AdobeActionAssets.decode(raw))
    }
    var huge = data
    huge.replaceSubrange(18..<22, with: [0x7f, 0xff, 0xff, 0xff])
    XCTAssertThrowsError(try AdobeActionAssets.decode(huge))
    var highDepth = data
    highDepth.replaceSubrange(22..<24, with: [0, 16])
    XCTAssertThrowsError(try AdobeActionAssets.decode(highDepth))
  }

  func testPSDResourcePipelineMatchesAllIndependentPhotoshopComponentBytes() throws {
    struct Reference: Decodable {
      struct Item: Decodable {
        let width: Int, height: Int, offset: Int
        let value: Float, opacity: Float
      }
      let cases: [Item]
    }
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("PhotoCraftCoreTests/Fixtures")
    let bytes = try Data(
      contentsOf: directory.appendingPathComponent("photoshop-component-fill-rgb8.bin"))
    let references = try JSONDecoder().decode(
      Reference.self,
      from:
        Data(contentsOf: directory.appendingPathComponent("photoshop-component-fill-rgb8.json")))
    var compared = 0
    for item in references.cases {
      var pixels = try Surface(width: item.width, height: item.height)
      for y in 0..<item.height {
        for x in 0..<item.width {
          let offset = item.offset + (y * item.width + x) * 4
          pixels.setPixel(
            x: x, y: y,
            Pixel(
              Float(bytes[offset]) / 255,
              Float(bytes[offset + 1]) / 255, Float(bytes[offset + 2]) / 255,
              Float(bytes[offset + 3]) / 255))
        }
      }
      var document = try CraftDocument(width: item.width, height: item.height)
      document.layers[0].content = .raster(pixels)
      let json = """
        [{"_obj":"select","_target":[{"_ref":"channel","_enum":"channel","_value":"red"}]},
        {"_obj":"fill","using":{"_enum":"fillContents","_value":"\(item.value == 0 ? "black" : "white")"},"mode":{"_enum":"blendMode","_value":"normal"},"opacity":{"_unit":"percentUnit","_value":\(Double(item.opacity) * 100)}}]
        """
      let request = try AdobeActionsRequest(
        data: JSONSerialization.data(withJSONObject: [
          "image": ["source": ["url": "https://example.test/input"]],
          "options": [
            "actions": [["source": ["content": json, "contentType": "application/json"]]]
          ],
          "outputs": [
            ["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]
          ],
        ]))
      let output = try AdobeActionAssets.execute(
        request, input: PSDCodec.writeRasterLayers(document))
      let result = try PSDCodec.read(XCTUnwrap(output.first).data)
      guard case .raster(let actual) = result.layers[0].content else {
        return XCTFail("Missing raster")
      }
      let count = item.width * item.height * 4
      XCTAssertEqual(
        try actual.rgbaData(depth: .u8),
        bytes.subdata(in: item.offset + count..<item.offset + count * 2))
      compared += count
    }
    XCTAssertEqual(compared, 122_880)
  }

  func testDocumentExportRetainsIntegerDepthAndResolution() throws {
    for depth in [PixelDepth.u8, .u16] {
      var document = try CraftDocument(width: 2, height: 2, depth: depth)
      document.layers[0].content = .raster(
        try Surface(width: 2, height: 2, depth: depth, fill: .white))
      document.resolution = 300
      let imported = try RasterIO.read(RasterIO.encoded(document))
      XCTAssertEqual(imported.depth, depth)
      XCTAssertEqual(imported.pixelsPerInch, 300, accuracy: 0.02)
      if depth == .u16 {
        XCTAssertThrowsError(try AdobeActionAssets.decode(RasterIO.encoded(document)))
      }
    }
  }
}

private actor StubTransport: AdobeResourceTransport {
  let data: Data
  var paused: Bool
  let failFetch: Bool
  let failUpload: Bool
  var fetchCount = 0
  var uploads: [Data] = []
  var continuation: CheckedContinuation<Void, Never>?
  init(data: Data, paused: Bool = false, failFetch: Bool = false, failUpload: Bool = false) {
    self.data = data
    self.paused = paused
    self.failFetch = failFetch
    self.failUpload = failUpload
  }
  func fetch(_ url: URL) async throws -> Data {
    fetchCount += 1
    if paused { await withCheckedContinuation { continuation = $0 } }
    if failFetch {
      throw URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLErrorKey: url])
    }
    return data
  }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
    uploads.append(data)
    if failUpload { throw URLError(.cannotWriteToFile) }
  }
  func release() {
    paused = false
    continuation?.resume()
    continuation = nil
  }
  func waitUntilStarted() async throws {
    for _ in 0..<100 {
      if continuation != nil { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw URLError(.timedOut)
  }
}
private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_700_000_000)
  func now() -> Date { lock.withLock { value } }
  func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}
extension ISO8601DateFormatter {
  fileprivate static var withFractional: ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }
}
