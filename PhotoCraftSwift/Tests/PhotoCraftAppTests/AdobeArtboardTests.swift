import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AdobeArtboardTests: XCTestCase {
  func body() -> [String: Any] {
    ["artboardSpacing": 3, "images": [["name": "First", "source": ["url": "https://example.test/a.png"]], ["source": ["url": "https://example.test/b.png"]]], "outputs": [["mediaType": "image/png", "destination": ["validityPeriod": 60]], ["mediaType": "application/json", "destination": ["validityPeriod": 60]]]]
  }
  func image(_ width: Int, _ height: Int, _ color: Pixel) throws -> Data {
    var d = try CraftDocument(width: width, height: height); d.layers[0].content = .raster(try Surface(width: width, height: height, fill: color))
    return try DocumentIO.encode(d, format: .png)
  }
  func resources() throws -> [URL: Data] { try [URL(string: "https://example.test/a.png")!: image(4, 3, Pixel(1, 0, 0)), URL(string: "https://example.test/b.png")!: image(2, 5, Pixel(0, 0, 1))] }
  func testContractBoundsNamesHorizontalAssemblyAndManifest() throws {
    let request = try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: body()))
    let d = try request.document(resources: resources())
    XCTAssertEqual(d.width, 9); XCTAssertEqual(d.height, 5); XCTAssertEqual(d.layers.count, 4)
    XCTAssertEqual(d.artboards.map(\.name), ["First", "2 x 5"])
    XCTAssertEqual(d.artboards[1].artboardBounds, .init(x: 7, y: 0, width: 2, height: 5))
    let outputs = try request.execute(resources: resources())
    let pixels = try Renderer.composite(RasterIO.read(outputs[0].data, name: "Boards"))
    XCTAssertEqual(pixels.pixel(x: 1, y: 1), Pixel(1, 0, 0)); XCTAssertEqual(pixels.pixel(x: 5, y: 1), .clear); XCTAssertEqual(pixels.pixel(x: 8, y: 4), Pixel(0, 0, 1))
    let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: outputs[1].data) as? [String: Any])
    let boards = try XCTUnwrap(manifest["artboards"] as? [[String: Any]])
    XCTAssertEqual(boards.count, 2); XCTAssertEqual((boards[1]["bounds"] as? [String: Int])?["left"], 7)
    let rootLayers = try XCTUnwrap(manifest["layers"] as? [[String: Any]]); XCTAssertEqual((rootLayers[0]["children"] as? [Any])?.count, 1)
    var defaultBody = body(); defaultBody.removeValue(forKey: "artboardSpacing")
    XCTAssertEqual(try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: defaultBody)).spacing, 50)
  }
  func testInvalidAndUnsupportedContractFieldsFailExplicitly() throws {
    var value = body(); value["images"] = []; XCTAssertThrowsError(try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: value)))
    value = body(); value["artboardSpacing"] = true; XCTAssertThrowsError(try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: value)))
    value = body(); value["outputs"] = [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]
    XCTAssertThrowsError(try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: value)))
    value = body(); value["images"] = [["source": ["creativeCloudPath": "/input.psd"]]]
    XCTAssertThrowsError(try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: value)))
    value = body(); value["outputs"] = [["mediaType": "application/json", "quality": "high", "destination": ["validityPeriod": 60]]]
    XCTAssertThrowsError(try AdobeArtboardRequest(data: JSONSerialization.data(withJSONObject: value)))
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method: "POST", path: "/v2/create-artboard"), AdobeActionsRequest.maximumBodyBytes)
  }
  @MainActor func testPublishedRouteJobStatusAndHostedOutputs() async throws {
    let transport = ArtboardTransport(resources: try resources()), helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, _ in
      service.setResourceJobsEnabled(true)
      let submitted = try await helper.request(service, path: "/v2/create-artboard", body: body())
      XCTAssertEqual(submitted.0.statusCode, 202)
      let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: submitted.1) as? [String: Any])
      let id = try XCTUnwrap(envelope["jobId"] as? String)
      var completed: [String: Any] = [:]
      for _ in 0..<100 {
        let response = try await helper.request(service, path: "/v2/status/\(id)")
        completed = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
        if ["succeeded", "failed"].contains(completed["status"] as? String ?? "") { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertEqual(completed["status"] as? String, "succeeded", "\(completed["errorDetails"] ?? "")")
      let result = try XCTUnwrap(completed["result"] as? [String: Any]), outputs = try XCTUnwrap(result["outputs"] as? [[String: Any]])
      XCTAssertEqual(outputs.count, 2)
      let destination = try XCTUnwrap(outputs[1]["destination"] as? [String: Any]), url = try XCTUnwrap(URL(string: destination["url"] as? String ?? ""))
      let asset = try await helper.request(service, path: url.path); XCTAssertEqual(asset.0.statusCode, 200); XCTAssertEqual(asset.0.mimeType, "application/json")
      service.setResourceJobsEnabled(false)
      let revoked = try await helper.request(service, path: url.path); XCTAssertEqual(revoked.0.statusCode, 403)
    }
  }
}
private struct ArtboardTransport: AdobeResourceTransport {
  let resources: [URL: Data]
  func fetch(_ url: URL) async throws -> Data { guard let data = resources[url] else { throw URLError(.fileDoesNotExist) }; return data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {}
}
