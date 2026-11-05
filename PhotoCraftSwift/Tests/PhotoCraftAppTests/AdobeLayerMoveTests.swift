import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class AdobeLayerMoveTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try LayerStackOrderWorkflowTests().fixture()
    for i in d.layers.indices { d.layers[i].sourceTags = ["lyid": Data([0, 0, 0, UInt8(i + 1)])] }
    return d
  }
  func move(_ target: [String: Any], _ placement: String, reference: [String: Any]? = nil,
    children: Bool = true) -> [String: Any] {
    var position: [String: Any] = ["type": placement]; position["referenceLayer"] = reference
    return target.merging(["operation": ["type": "move", "placement": position,
      "shouldIncludeChildren": children]]) { _, new in new }
  }
  func request(_ edits: [[String: Any]]) throws -> AdobeActionsRequest {
    try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: [
      "image": ["source": ["url": "https://example.test/owned.psd"]],
      "edits": ["layers": edits], "outputs": [["mediaType": "image/vnd.adobe.photoshop",
        "destination": ["validityPeriod": 60]]],
    ]), createComposite: true)
  }
  func testAllPublishedPlacementValuesNameIDAndNativePrimitiveEquivalence() throws {
    let source = try fixture(), id = source.layers[1].id
    let cases: [(String, [String: Any]?, [String], Command)] = [
      ("top", nil, ["A", "C", "D", "E", "B"], .stackLayers(.init(layerIDs: [id], operation: .bringToFront))),
      ("bottom", nil, ["B", "A", "C", "D", "E"], .stackLayers(.init(layerIDs: [id], operation: .sendToBack))),
      ("above", ["name": "D"], ["A", "C", "D", "B", "E"], .relocate(id, nil, 3)),
      ("below", ["id": 1], ["B", "A", "C", "D", "E"], .relocate(id, nil, 0)),
    ]
    for (placement, reference, names, command) in cases { for target: [String: Any] in [["name": "B"], ["id": 2, "type": "layer"]] {
      let original = source
      let actual = try request([move(target, placement, reference: reference)]).applying(to: source).session.document
      var native = source; try command.apply(to: &native)
      XCTAssertEqual(actual.layers.map(\.name), names); XCTAssertEqual(actual, native)
      XCTAssertEqual(try NativeArchive.encodeChunked(actual), try NativeArchive.encodeChunked(native))
      XCTAssertEqual(source, original)
    } }
    var grouped = source
    let group = Layer(name: "Group", content: .group(.init()))
    grouped.layers[3].parentID = group.id
    grouped.layers.insert(group, at: 4)
    let actual = try request([move(["id": 2], "into", reference: ["name": "Group"])]).applying(to: grouped).session.document
    XCTAssertEqual(actual.layers.map(\.name), ["A", "C", "D", "B", "Group", "E"])
    XCTAssertEqual(actual.layers.first { $0.id == id }?.parentID, group.id)
    XCTAssertEqual(actual.layers.first { $0.id == id }?.content, source.layers[1].content)
    let movedGroup = try request([move(["name": "Group"], "bottom")]).applying(to: grouped).session.document
    XCTAssertEqual(movedGroup.layers.map(\.name), ["D", "Group", "A", "B", "C", "E"])
    XCTAssertEqual(movedGroup.layers.first, grouped.layers[3])
    var background = grouped
    background.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: .white))
    background.layers[0].mask = nil
    background.layers[0].background = true; background.layers[0].protection = .fullyLocked
    let outOfGroup = try request([move(["name": "D"], "bottom")]).applying(to: background).session.document
    XCTAssertEqual(outOfGroup.layers.map(\.name), ["A", "D", "B", "C", "Group", "E"])
    XCTAssertNil(outOfGroup.layers.first { $0.name == "D" }?.parentID)
  }

  func testInvalidAmbiguousCyclesUnsupportedAndLaterFailurePreserveInput() throws {
    let source = try fixture(), before = source
    let invalid: [[String: Any]] = [
      move(["name": "B", "id": 2], "top"), move(["id": true], "top"), move(["name": ""], "top"),
      move(["name": "B"], "unknown"), move(["name": "B"], "above"),
      move(["name": "B"], "top", reference: ["name": "C"]),
      move(["name": "B"], "into", reference: ["name": "C"]),
      move(["name": "Missing"], "top"), move(["name": "B", "type": "text_layer"], "top"),
    ]
    for edit in invalid {
      XCTAssertThrowsError(try request([move(["name": "A"], "top"), edit]).applying(to: source))
      XCTAssertEqual(source, before)
    }
    var grouped = source
    let group = Layer(name: "Group", content: .group(.init()))
    grouped.layers[1].parentID = group.id; grouped.layers.insert(group, at: 2)
    for edit in [move(["name": "Group"], "into", reference: ["name": "Group"]),
      move(["name": "Group"], "above", reference: ["name": "B"]),
      move(["name": "Group"], "top", children: false)] {
      XCTAssertThrowsError(try request([edit]).applying(to: grouped))
    }
    var ambiguous = source; ambiguous.layers[2].name = "B"
    XCTAssertThrowsError(try request([move(["name": "B"], "top")]).applying(to: ambiguous))
    var locked = source; locked.layers[1].locked = true
    XCTAssertThrowsError(try request([move(["id": 2], "top")]).applying(to: locked))
  }

  @MainActor func testActualCreateCompositeJobsRetainInputBytesAndMatchNativePSDOutput() async throws {
    var original = try fixture()
    // The existing PSD writer emits regular lyid tags when comp resources are active.
    original.layerComps = LayerComps()
    let input = try PSDCodec.writeRasterLayers(original)
    let parsed = try PSDCodec.read(input)
    XCTAssertEqual(parsed.layers.first { $0.name == "B" }?.sourceTags?["lyid"], Data([0, 0, 0, 2]))
    let jobs = AdobeActionJobs(transport: LayerMoveTransport(input)); defer { jobs.revoke() }
    for edit in [move(["name": "B"], "top"), move(["id": 2], "below", reference: ["name": "A"])] {
      let request = try request([edit])
      let expected = try request.applying(to: parsed).session.document
      let expectedBytes = try PSDCodec.writeRasterLayers(expected)
      let submitted = try jobs.submit(request, baseURL: URL(string: "http://127.0.0.1:43210")!)
      let until = Date().addingTimeInterval(20)
      while Date() < until {
        if let state = jobs.snapshot(submitted.id), [.succeeded, .failed].contains(state.status) { break }
        try await Task.sleep(for: .milliseconds(5))
      }
      let state = try XCTUnwrap(jobs.snapshot(submitted.id))
      XCTAssertEqual(state.status, .succeeded, state.error?.message ?? "")
      let output = try XCTUnwrap(state.outputs.first)
      let id = try XCTUnwrap(UUID(uuidString: output.url.lastPathComponent)), asset = try XCTUnwrap(jobs.asset(id))
      let read = try PSDCodec.read(asset.data)
      XCTAssertEqual(read.layers.map(\.name), expected.layers.map(\.name))
      XCTAssertEqual(try Renderer.composite(read), try Renderer.composite(expected))
      XCTAssertEqual(asset.data, expectedBytes)
      XCTAssertEqual(try PSDCodec.writeRasterLayers(original), input)
    }
  }
}

private actor LayerMoveTransport: AdobeResourceTransport {
  let input: Data
  init(_ input: Data) { self.input = input }
  func fetch(_ url: URL) async throws -> Data { input }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {}
}
