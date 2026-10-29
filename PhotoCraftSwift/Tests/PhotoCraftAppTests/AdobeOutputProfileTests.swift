import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class AdobeOutputProfileTests: XCTestCase {
  func request(_ profiles: [[String: Any]]) throws -> AdobeActionsRequest {
    try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: [
      "image": ["width": 3, "height": 1, "mode": "rgb", "depth": 16],
      "edits": ["layers": []], "outputs": profiles.map { ["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60], "iccProfile": $0] }
    ]), createComposite: true)
  }
  func testOutputProfilesUseSharedConversionAndDoNotShareWrongCachedEncoding() throws {
    let helper = ColorProfileWorkflowTests(), source = try helper.fixture()
    let url = URL(string: "https://example.test/output-profile.icc")!, p3 = try helper.profile(CGColorSpace.displayP3)
    let request = try request([["type": "custom", "name": "Display P3", "imageMode": "rgb", "source": ["url": url.absoluteString]], ["type": "standard", "name": "sRGB IEC61966-2.1"]])
    let encoded = try AdobeActionAssets.execute(request, document: source, resources: [url: p3])
    XCTAssertEqual(encoded.count, 2); XCTAssertNotEqual(encoded[0].data, encoded[1].data)
    let p3Read = try PSDCodec.read(encoded[0].data), expected = try helper.apply(.init(.convert, profile: p3), source)
    XCTAssertEqual(p3Read.workingICC, p3)
    guard case .raster(let a) = p3Read.layers[0].content, case .raster(let b) = expected.layers[0].content else { return XCTFail("raster") }
    for x in 0..<3 { XCTAssertEqual(a.pixel(x:x,y:0),b.pixel(x:x,y:0)) }
    XCTAssertEqual(try PSDCodec.read(encoded[1].data).workingICC, try NativeModeProfile.standard(.rgb,depth:.u16))
    XCTAssertThrowsError(try AdobeActionAssets.execute(request, document: source))
  }
  @MainActor func testAsyncJobFetchesCustomICCAndPublishesConvertedOutput() async throws {
    let helper = ColorProfileWorkflowTests(), profile = try helper.profile(CGColorSpace.displayP3)
    let url = URL(string: "https://example.test/job-profile.icc")!
    let request = try request([["type": "custom", "name": "Display P3", "source": ["url": url.absoluteString]]])
    let transport = ProfileJobTransport(resources: [url: profile])
    let jobs = AdobeActionJobs(transport: transport); defer { jobs.revoke() }
    let start = try jobs.submit(request, baseURL: URL(string: "http://127.0.0.1:43210")!)
    for _ in 0..<200 {
      if let state = jobs.snapshot(start.id), [.succeeded, .failed].contains(state.status) { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    let state = try XCTUnwrap(jobs.snapshot(start.id))
    XCTAssertEqual(state.status, .succeeded, state.error?.message ?? "")
    let fetched = await transport.fetched; XCTAssertEqual(fetched, [url])
    let output = try XCTUnwrap(state.outputs.first), id = try XCTUnwrap(UUID(uuidString: output.url.lastPathComponent))
    let data = try XCTUnwrap(jobs.asset(id)).data
    XCTAssertEqual(try PSDCodec.read(data).workingICC, profile)
  }
  func testDefaultsModeValidationAndProfileLimits() throws {
    let defaults = try AdobeOutputProfile([:] as [String: Any])
    XCTAssertEqual(defaults.name,"sRGB IEC61966-2.1")
    XCTAssertEqual(try ProofSettings.mode(of: defaults.data(resources:[:],depth:.u8)),.rgb)
    let bad:[Any] = [NSNull(),["type":NSNull()],["type":"standard","name":NSNull()],["type":"custom","name":"X"],["type":"standard","name":"Unknown"],["type":"standard","name":"Apple RGB"],["type":"custom","name":"X","imageMode":"lab","source":["url":"https://example.test/p.icc"]]]
    for raw in bad { XCTAssertThrowsError(try AdobeOutputProfile(raw)) }
    let mismatch = try AdobeOutputProfile(["type":"standard","name":"Adobe RGB (1998)","imageMode":"grayscale"])
    XCTAssertThrowsError(try mismatch.data(resources:[:],depth:.u8))
    let url=URL(string:"https://example.test/p.icc")!
    let custom=try AdobeOutputProfile(["type":"custom","name":"X","source":["url":url.absoluteString]])
    XCTAssertThrowsError(try custom.data(resources:[url:Data(count:ICCProfile.maximumBytes+1)],depth:.u8))
    XCTAssertThrowsError(try custom.data(resources:[url:NativeModeProfile.standard(.rgb,depth:.u8)],depth:.f32))
  }
}

private actor ProfileJobTransport: AdobeResourceTransport {
  let resources: [URL: Data]
  var fetched: [URL] = []
  init(resources: [URL: Data]) { self.resources = resources }
  func fetch(_ url: URL) async throws -> Data { fetched.append(url); return try XCTUnwrap(resources[url]) }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { XCTFail("Unexpected remote upload") }
}
