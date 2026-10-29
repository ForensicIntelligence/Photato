import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ModeActionWorkflowTests: XCTestCase {
  private func select(_ channel: String) -> [String: Any] {
    ["_obj": "select", "_target": [["_ref": "channel", "_enum": "channel", "_value": channel]]]
  }
  private func body(_ resources: [[[String: Any]]]) throws -> [String: Any] {
    ["image": ["source": ["url": "https://example.test/owned.psd"]],
      "options": ["actions": try resources.map { actions in
        ["source": ["contentType": "application/json", "content": String(decoding: try JSONSerialization.data(withJSONObject: actions), as: UTF8.self)]]
      }], "outputs": [["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]]]
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw CraftError.invalid("Expected hosted output") }
  }
  @MainActor func testBothHTTPJobInterfacesRetainTargetsAcrossResourcesAndMatchChannelsUI() async throws {
    let helper = AutomationEncodingOptionsTests()
    let cases: [(DocumentColorMode, PixelDepth, String, Int)] = [(.rgb, .u16, "red", 0), (.rgb, .f32, "green", 1),
      (.grayscale, .u16, "gray", 0), (.grayscale, .f32, "gray", 0), (.cmyk, .u16, "black", 3), (.lab, .u16, "a", 1)]
    for (mode, depth, name, component) in cases {
      let source = try TIFFModeWorkflowTests().fixture(mode, depth), input = try DocumentIO.encode(source, format: .psd)
      let decoded = try AdobeActionAssets.decode(input), desktop = EditorStore(document: decoded)
      defer { desktop.renderTask?.cancel() }
      let id = try XCTUnwrap(decoded.activeLayerID)
      try desktop.selectModeComponents([component])
      try desktop.executeEditorCommand(.fill(id, Pixel(1, 1, 1, 0.5)))
      try desktop.executeEditorCommand(.applyAdjustment(id, .invert))
      try desktop.executeEditorCommand(.applyFilter(id, .init(.average)))
      let expected = try DocumentIO.encode(desktop.document, format: .psd)
      let payload = try body([[select(name)], [
        ["_obj": "fill", "using": ["_enum": "fillContents", "_value": "white"],
          "mode": ["_enum": "blendMode", "_value": "normal"], "opacity": ["_unit": "percentUnit", "_value": 50]],
        ["_obj": "invert"], ["_obj": "average"],
      ]])
      try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(data: input)) { service, shared in
        service.setResourceJobsEnabled(true); let untouched = shared.store.document
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let outputs = try await helper.outputs(service, route: route, payload: payload)
          XCTAssertEqual(outputs, [expected], "\(mode) \(depth) \(route)")
        }
        XCTAssertEqual(shared.store.document, untouched)
        let caps = try await AutomationTests().request(service, path: "/v1/capabilities")
        XCTAssertTrue(String(decoding: caps.1, as: UTF8.self).contains("colorModeActions"))
      }
      for _ in 0..<3 { try desktop.session.undo() }
      XCTAssertEqual(desktop.document, decoded)
    }
  }
  @MainActor func testBothHTTPModeConversionRoutesMatchDesktopAndClearPriorTargets() async throws {
    let helper = AutomationEncodingOptionsTests()
    let source = try TIFFModeWorkflowTests().fixture(.rgb, .u16), input = try DocumentIO.encode(source, format: .psd)
    let decoded = try AdobeActionAssets.decode(input)
    for mode in [DocumentColorMode.grayscale, .cmyk, .lab] {
      let desktop = EditorStore(document: decoded); defer { desktop.renderTask?.cancel() }
      try desktop.executeEditorCommand(DocumentModeInput.command(.init(.init(mode: mode, depth: .u16)), in: decoded))
      let expected = try DocumentIO.encode(desktop.document, format: .psd)
      let payload = try body([[select("red")], [["_obj": "convertMode", "to": ["_enum": "colorSpaceMode", "_value": mode.rawValue]]]])
      try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: Transport(data: input)) { service, shared in
        service.setResourceJobsEnabled(true); let untouched = shared.store.document
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let outputs = try await helper.outputs(service, route: route, payload: payload)
          XCTAssertEqual(outputs, [expected])
        }
        XCTAssertEqual(shared.store.document, untouched)
      }
      try desktop.session.undo(); XCTAssertEqual(desktop.document, decoded)
    }
  }
  @MainActor func testExplicitMergeUsesSharedCompositorAndLaterFailurePublishesNothing() async throws {
    var source = try TIFFModeWorkflowTests().fixture(.rgb, .u16)
    var hidden = Layer(name: "Hidden", content: .raster(try Surface(width: 4, height: 3, depth: .u16, fill: .black)))
    hidden.visible = false; source.layers.append(hidden)
    // Ordinary added layers must also receive authoritative mode samples.
    source.layers[1].nativeMode = try NativeModeRaster.converting(Surface(width: 4, height: 3, depth: .u16, fill: .black), to: .rgb, depth: .u16)
    let input = try DocumentIO.encode(source, format: .psd), decoded = try AdobeActionAssets.decode(input)
    let action: [String: Any] = ["_obj": "$CnvM", "$T   ": ["_class": "$Grys"], "$Dpth": 8, "$Mrge": true]
    let request = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: body([[action]])))
    let actual = try request.applying(to: decoded).session.document
    var expected = decoded
    try DocumentModeInput.command(.init(.init(mode: .grayscale, depth: .u8), mergeVisible: true), in: decoded).apply(to: &expected)
    XCTAssertEqual(actual, expected); XCTAssertEqual(actual.layers.count, 1)
    let failedRequest = try AdobeActionsRequest(data: JSONSerialization.data(withJSONObject: body([[action], [select("cyan")]])))
    let jobs = AdobeActionJobs(transport: Transport(data: input)); defer { jobs.revoke() }
    let snapshot = try jobs.submit(failedRequest, baseURL: URL(string: "http://127.0.0.1:43210")!)
    for _ in 0..<200 {
      if [.failed, .succeeded].contains(jobs.snapshot(snapshot.id)?.status) { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(jobs.snapshot(snapshot.id)?.status, .failed)
    XCTAssertTrue(jobs.snapshot(snapshot.id)?.outputs.isEmpty == true)
  }
}
