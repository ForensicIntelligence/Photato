import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class AutomationActionJobsTests: XCTestCase {
  @MainActor func testNativeFiltersThroughBothJobInterfaces() async throws {
    let transport = Transport()
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      let original = try FilterWorkflowTests().fixture()
      let encoded = try PSDCodec.writeRasterLayers(original)
      await transport.set(encoded)
      let descriptors = [
        #"{"_obj":"gaussianBlur","radius":{"_unit":"pixelsUnit","_value":5}}"#,
        #"{"_obj":"boxblur","radius":{"_unit":"pixelsUnit","_value":5}}"#,
        #"{"_obj":"motionBlur","angle":{"_unit":"angleUnit","_value":0},"distance":{"_unit":"pixelsUnit","_value":10}}"#,
        #"{"_obj":"unsharpMask","radius":{"_unit":"pixelsUnit","_value":1},"amount":{"_unit":"percentUnit","_value":50},"threshold":0}"#,
        #"{"_obj":"highPass","radius":{"_unit":"pixelsUnit","_value":5}}"#,
        #"{"_obj":"addNoise","amount":{"_unit":"percentUnit","_value":10},"distribution":{"_enum":"distribution","_value":"uniformDistribution"},"monochromatic":true}"#,
        #"{"_obj":"mosaic","cellSize":{"_unit":"pixelsUnit","_value":10}}"#,
        #"{"_obj":"$Avrg"}"#,
      ]
      for descriptor in descriptors {
        service.setResourceJobsEnabled(false); service.setResourceJobsEnabled(true)
        var payload = body()
        let actions = "[" + descriptor + "]"
        payload["options"] = ["actions": [["source": ["content": actions, "contentType": "application/json"]]]]
        let expected = try PhotoshopActionProgram(actionJSON: actions).applying(to: AdobeActionAssets.decode(encoded)).session.document
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let result = try await output(service, submit: route, payload: payload)
          XCTAssertEqual(result.2, try PSDCodec.writeRasterLayers(expected))
        }
      }
      XCTAssertEqual(shared.store.document, untouched)
    }
  }

  @MainActor func testIndependentPSBInputsThroughBothActualJobRoutes() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/psb")
    let transport = Transport()
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 }, resourceTransport: transport
    ) {
      service, shared in
      let before = shared.store.document
      for depth in [8, 16, 32] {
        service.setResourceJobsEnabled(false)
        service.setResourceJobsEnabled(true)
        let inputURL = root.appendingPathComponent("rgb\(depth)-compression1.psb")
        let input = try Data(contentsOf: inputURL)
        await transport.set(input)
        var payload = self.body()
        payload["options"] = [
          "actions": [
            [
              "source": [
                "content":
                  "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]",
                "contentType": "application/json",
              ]
            ]
          ]
        ]
        let expected = try DocumentIO.encode(DocumentIO.read(inputURL), format: .psd)
        XCTAssertEqual(expected, try DocumentIO.encode(PSDCodec.read(input), format: .psd))
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let result = try await self.output(service, submit: route, payload: payload)
          XCTAssertEqual(result.2, expected)
          XCTAssertEqual(Array(result.2[4..<6]), [0, 1], "Published Photoshop output remains PSD")
        }
      }
      XCTAssertEqual(shared.store.document, before)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testMergeActionsAcrossBothJobsDesktopAndIndependentPhotoshopLayers() async throws
  {
    let transport = Transport()
    let comparison = AutomationLayerMergeTests()
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 }, resourceTransport: transport
    ) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      for bits in [8, 16, 32] {
        let source = try comparison.fixture("photoshop-source-rgb\(bits)")
        await transport.set(try PSDCodec.writeRasterLayers(source))
        for key in ["down", "selected", "visible"] {
          service.setResourceJobsEnabled(false)
          service.setResourceJobsEnabled(true)
          let expected = try comparison.fixture("photoshop-\(key)-rgb\(bits)")
          let selectAll =
            "{\"_obj\":\"selectAllLayers\",\"_target\":[{\"_ref\":\"layer\",\"_enum\":\"ordinal\",\"_value\":\"targetEnum\"}]}"
          let event = key == "visible" ? "$MrgV" : "$Mrg2"
          let merge = "{\"_obj\":\"\(event)\",\"_options\":{\"dialogOptions\":\"dontDisplay\"}}"
          // Separate resources prove selected-layer state survives action boundaries.
          let actions = (key == "selected" ? ["[\(selectAll)]"] : []) + ["[\(merge)]"]
          var payload = body()
          payload["options"] = [
            "actions": actions.map {
              ["source": ["content": $0, "contentType": "application/json"]]
            }
          ]
          var outputs: [Data] = []
          for route in ["/v1/action-jobs", "/v2/execute-actions"] {
            let result = try await output(service, submit: route, payload: payload)
            outputs.append(result.2)
            try comparison.samePixels(PSDCodec.read(result.2), expected)
          }
          XCTAssertEqual(outputs[0], outputs[1])
        }
      }
      XCTAssertEqual(shared.store.document, untouched)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testRGB32MergedPhotoshopGoldenThroughDesktopDownloadAndBothJobs() async throws {
    try await assertRGB32Golden(folder: "rgb32-composite", name: "08-three-layers")
  }

  @MainActor func testRGB32GroupGoldensThroughDesktopDownloadAndBothJobs() async throws {
    for name in [
      "02-pass-opacity", "04-isolated-opacity-mask", "05-clipping", "07-nested-pass",
      "08-opaque-pass-opacity",
      "09-pass-opacity-213", "10-nested-masked", "11-isolated-first-transparent",
    ] {
      try await assertRGB32Golden(folder: "rgb32-groups", name: name)
    }
  }

  @MainActor private func assertRGB32Golden(folder: String, name: String) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(
        "PhotoCraftImagingTests/Fixtures/\(folder)")
    let input = try Data(contentsOf: root.appendingPathComponent(name + ".psd"))
    let golden = try Data(contentsOf: root.appendingPathComponent(name + ".merged"))
    let original = try PSDCodec.read(input)
    let transport = Transport()
    await transport.set(input)
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 }, resourceTransport: transport
    ) {
      service, shared in
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel() }
      let expected = try DocumentIO.encode(desktop.document, format: .psd)
      // Exported merged planes are raw. Extract without the production PSD decoder.
      func assertGolden(_ bytes: Data) throws {
        XCTAssertEqual(Array(bytes[12..<14]), [0, 4])
        var offset = 26
        for _ in 0..<3 {
          let count = bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
          offset += 4 + count
          XCTAssertLessThan(offset + 2, bytes.count)
        }
        XCTAssertEqual(Array(bytes[offset..<(offset + 2)]), [0, 0])
        let merged = bytes.dropFirst(offset + 2)
        XCTAssertEqual(merged.count, golden.count)
        XCTAssertEqual(zip(merged, golden).filter { $0 != $1 }.count, 0)
      }
      try assertGolden(expected)
      var payload = self.body()
      payload["options"] = [
        "actions": [
          [
            "source": [
              "content":
                "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]",
              "contentType": "application/json",
            ]
          ]
        ]
      ]
      service.setResourceJobsEnabled(true)
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let result = try await self.output(service, submit: route, payload: payload)
        XCTAssertEqual(result.2, expected, route)
        try assertGolden(result.2)
      }
      shared.store.session = EditorSession(document: original)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await AutomationTests().request(
        service, path: "/v1/documents/\(id)/file.psd")
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(response.1, expected)
      try assertGolden(response.1)
      XCTAssertEqual(shared.store.document, original)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      XCTAssertFalse(shared.isDocumentEdited)
      let storage = try XCTUnwrap(
        AutomationService.documentTransferCapabilities["float32Storage"] as? [String: Any])
      let composition = try XCTUnwrap(storage["normalRasterComposition"] as? [String: Any])
      XCTAssertEqual(composition["exactWholePSDFile"] as? Bool, false)
      let hierarchy = try XCTUnwrap(storage["normalHierarchyComposition"] as? [String: Any])
      XCTAssertEqual(hierarchy["exactWholePSDFile"] as? Bool, false)
    }
  }

  @MainActor func testRGB32PreservationAcrossDesktopDownloadsAndBothJobAPIs() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(
        "PhotoCraftImagingTests/Fixtures/photoshop-depth-32.psd")
    let input = try Data(contentsOf: fixture)
    let original = try PSDCodec.read(input)
    let transport = Transport()
    await transport.set(input)
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 }, resourceTransport: transport
    ) { service, shared in
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel() }
      try desktop.selectEditingChannel(.composite)
      let expected = try DocumentIO.encode(desktop.document, format: .psd)
      var payload = self.body()
      payload["options"] = [
        "actions": [
          [
            "source": [
              "content":
                "[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]",
              "contentType": "application/json",
            ]
          ]
        ]
      ]
      var pngOutput = payload
      pngOutput["outputs"] = [["mediaType": "image/png", "destination": ["validityPeriod": 60]]]
      let unsupportedPNG = try AdobeActionsRequest(
        data: JSONSerialization.data(withJSONObject: pngOutput))
      XCTAssertThrowsError(try AdobeActionAssets.execute(unsupportedPNG, input: input))
      let componentFill = try AdobeActionsRequest(
        data: JSONSerialization.data(withJSONObject: self.body()))
      let fillDesktop = EditorStore(document: original)
      defer { fillDesktop.renderTask?.cancel() }
      try fillDesktop.selectEditingChannel(.red)
      try fillDesktop.executeEditorCommand(fillDesktop.componentFillCommand(value: 1, opacity: 0.5))
      XCTAssertEqual(fillDesktop.document.depth, .f32)
      XCTAssertEqual(fillDesktop.session.undoStack.count, 1)
      let active = try XCTUnwrap(original.activeLayerID)
      for (before, after) in zip(original.layers, fillDesktop.document.layers) {
        if before.id != active { XCTAssertEqual(after, before); continue }
        guard case .raster(let a) = before.content, case .raster(let b) = after.content else {
          return XCTFail("Component Fill must retain raster layers")
        }
        let oldBytes = try a.rgbaData(depth: .f32, colorEncoding: .linearRGB)
        let newBytes = try b.rgbaData(depth: .f32, colorEncoding: .linearRGB)
        for y in 0..<a.height { for x in 0..<a.width {
          let offset = (y * a.width + x) * 16
          XCTAssertEqual(newBytes[offset + 4..<offset + 16], oldBytes[offset + 4..<offset + 16],
            "Green, blue and alpha Float32 bytes must remain untouched")
          let point = before.coordinateTransform.point(Double(x) + 0.5, Double(y) + 0.5)
          let amount = original.selectionCoverage(x: Int(floor(point.x)), y: Int(floor(point.y))) * 0.5
          XCTAssertEqual(b.linearPixel(x: x, y: y).r, a.linearPixel(x: x, y: y).r * (1 - amount) + amount)
        } }
      }
      let filled = fillDesktop.document
      let expectedFill = try DocumentIO.encode(filled, format: .psd)
      XCTAssertEqual(try AdobeActionAssets.execute(componentFill, input: input).map(\.data), [expectedFill])
      try fillDesktop.session.undo(); XCTAssertEqual(fillDesktop.document, original)
      try fillDesktop.session.redo(); XCTAssertEqual(fillDesktop.document, filled)
      service.setResourceJobsEnabled(true)
      for route in ["/v2/execute-actions", "/v1/action-jobs"] {
        let fillResult = try await self.output(service, submit: route, payload: self.body())
        XCTAssertEqual(fillResult.2, expectedFill, route)
        let result = try await self.output(service, submit: route, payload: payload)
        XCTAssertEqual(result.2, expected, route)
        let decoded = try PSDCodec.read(result.2)
        for (before, after) in zip(original.layers, decoded.layers) {
          guard case .raster(let a) = before.content, case .raster(let b) = after.content else {
            return XCTFail()
          }
          XCTAssertEqual(
            try a.rgbaData(depth: .f32, colorEncoding: .linearRGB),
            try b.rgbaData(depth: .f32, colorEncoding: .linearRGB))
        }
      }
      shared.store.session = EditorSession(document: desktop.document)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      for format in [DocumentIO.Format.native, .psd] {
        let response = try await AutomationTests().request(
          service, path: "/v1/documents/\(id)/file.\(format.rawValue)",
          headers: format == .native ? ["X-Photato-Archive-Version": "11"] : [:])
        XCTAssertEqual(response.0.statusCode, 200)
        XCTAssertEqual(response.1, try DocumentIO.encode(desktop.document, format: format))
      }
      XCTAssertEqual(shared.store.document, original)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      XCTAssertFalse(shared.isDocumentEdited)
      let capabilities =
        AutomationService.documentTransferCapabilities["float32Storage"] as? [String: Any]
      XCTAssertEqual(capabilities?["nativeArchiveVersion"] as? Int, 10)
      XCTAssertEqual(capabilities?["encoding"] as? String, "linearRGB")
    }
  }
  @MainActor func testMetadataPreservationAcrossDesktopDownloadsAndBothJobAPIs() async throws {
    let transport = Transport()
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 }, resourceTransport: transport
    ) { service, shared in
      var model = try CraftNSDocument.blankModel(
        width: 3, height: 2, background: Pixel(0.2, 0.4, 0.8))
      let opaqueBlock = Data([0x38, 0x42, 0x49, 0x4d, 0x0f, 0xa0, 1, 65, 0, 0, 0, 3, 1, 2, 3, 0])
      model.sourceMetadata = ["psdResources": opaqueBlock]
      let input = try PSDCodec.writeRasterLayers(model)
      await transport.set(input)
      let original = try PSDCodec.read(input)
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel() }
      try desktop.selectEditingChannel(.red)
      desktop.fill(color: .white, opacity: 0.5)
      XCTAssertNil(desktop.error)
      let expected = try PSDCodec.writeRasterLayers(desktop.document)
      service.setResourceJobsEnabled(true)
      for route in ["/v2/execute-actions", "/v1/action-jobs"] {
        let result = try await output(service, submit: route, payload: body())
        XCTAssertEqual(result.2, expected, route)
        let decoded = try PSDCodec.read(result.2)
        XCTAssertTrue(decoded.sourceMetadata?["psdResources"]?.range(of: opaqueBlock) != nil)
      }
      shared.store.session = EditorSession(document: desktop.document)
      service.setDocumentTransfersEnabled(true)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let response = try await AutomationTests().request(
        service, path: "/v1/documents/\(id)/file.psd")
      XCTAssertEqual(response.0.statusCode, 200)
      XCTAssertEqual(response.1, expected)
      XCTAssertEqual(shared.store.document, desktop.document)
      XCTAssertFalse(shared.isDocumentEdited)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }

  func testFramingErrorEnvelopeDoesNotDecodeOrDependOnBodyBytes() async throws {
    let invalidBody =
      Data("POST /v2/execute-actions HTTP/1.1\r\nContent-Length: 4194305\r\n\r\n".utf8)
      + Data([0xff, 0xfe])
    let response = AutomationResponse.failure(
      .init(status: 413, message: "Body too large."),
      requestData: invalidBody)
    XCTAssertEqual(response.status, 413)
    XCTAssertEqual(try object(response.body)["error_code"] as? String, "validation_error")
    XCTAssertNil(try object(response.body)["error"])
  }

  @MainActor func testLayerProtectionCreateCompositeHTTPJob() async throws {
    let transport = Transport()
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      var document = try CraftDocument(width: 4, height: 4)
      document.layers[0].name = "Owned Pixels"
      let input = try PSDCodec.writeRasterLayers(document)
      await transport.set(input)
      var payload = body()
      payload.removeValue(forKey: "options")
      payload["edits"] = ["layers": [["name": "Owned Pixels", "operation": ["type": "edit"],
        "protection": ["transparency", "position"]]]]
      let disabled = try await helper.request(service, path: "/v2/create-composite", body: payload)
      XCTAssertEqual(disabled.0.statusCode, 403)
      service.setResourceJobsEnabled(true)
      let result = try await output(service, submit: "/v2/create-composite", payload: payload)
      let decoded = try PSDCodec.read(result.2)
      XCTAssertEqual(decoded.layers[0].protection, [.transparency, .position])
      var expected = try PSDCodec.read(input)
      expected.layers[0].protection = [.transparency, .position]
      XCTAssertEqual(result.2, try PSDCodec.writeRasterLayers(expected))
      XCTAssertEqual(shared.store.document, untouched)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      payload["edits"] = ["layers": [["name": "Owned Pixels", "operation": ["type": "move"]]]]
      let unsupported = try await helper.request(service, path: "/v2/create-composite", body: payload)
      XCTAssertEqual(unsupported.0.statusCode, 422)
    }
  }

  @MainActor func testLayerStyleCreateCompositeHTTPJob() async throws {
    let transport = Transport(), helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }, resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      var d = try CraftDocument(width: 24, height: 24)
      d.layers[0].name = "Styled Pixels"
      d.layers[0].content = .shape(.init(kind: .rectangle, width: 8, height: 8, color: .white))
      d.layers[0].content = .raster(try Renderer.layerSurface(d.layers[0], in: d))
      d.layers[0].x = 8; d.layers[0].y = 8
      let input = try PSDCodec.writeRasterLayers(d); await transport.set(input)
      var payload = body(); payload.removeValue(forKey: "options")
      payload["edits"] = ["layers": [["name": "Styled Pixels", "operation": ["type": "edit"],
        "layerEffects": ["dropShadow": [["size": 3, "distance": 4, "useGlobalLight": false, "angle": 90]]]]]]
      service.setResourceJobsEnabled(true)
      let result = try await output(service, submit: "/v2/create-composite", payload: payload)
      let decoded = try PSDCodec.read(result.2)
      var expected = try PSDCodec.read(input), effect = LayerEffect(.dropShadow)
      effect.size = 3; effect.distance = 4; effect.useGlobalLight = false; effect.angle = 90
      try Command.layerStyle([expected.layers[0].id], LayerStyle(effects: [effect])).apply(to: &expected)
      XCTAssertEqual(result.2, try PSDCodec.writeRasterLayers(expected))
      XCTAssertEqual(decoded.layers[0].style?.effects.first?.distance, 4)
      XCTAssertEqual(shared.store.document, untouched)
    }
  }

  actor Transport: AdobeResourceTransport {
    var data = Data()
    var fetches = 0
    func set(_ data: Data) { self.data = data }
    func fetch(_ url: URL) async throws -> Data {
      fetches += 1
      return data
    }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw AdobeAPIError.unsupported("No external uploads in this test.")
    }
  }
  private func body(value: Float = 1, opacity: Float = 0.5) -> [String: Any] {
    let actions = """
      [{"_obj":"select","_target":[{"_ref":"channel","_enum":"channel","_value":"red"}]},
      {"_obj":"fill","using":{"_enum":"fillContents","_value":"\(value == 0 ? "black" : "white")"},"mode":{"_enum":"blendMode","_value":"normal"},"opacity":{"_unit":"percentUnit","_value":\(opacity * 100)}}]
      """
    return [
      "image": ["source": ["url": "https://example.test/original.psd"]],
      "options": [
        "actions": [["source": ["content": actions, "contentType": "application/json"]]]
      ],
      "outputs": [
        ["mediaType": "image/vnd.adobe.photoshop", "destination": ["validityPeriod": 60]]
      ],
    ]
  }
  private func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  @MainActor func output(
    _ service: AutomationService, submit: String,
    payload: [String: Any], expectedMediaType: String = "image/vnd.adobe.photoshop"
  ) async throws -> (String, String, Data) {
    let helper = AutomationTests()
    let accepted = try await helper.request(service, path: submit, body: payload)
    XCTAssertEqual(accepted.0.statusCode, 202, String(decoding: accepted.1, as: UTF8.self))
    let acceptance = try object(accepted.1)
    XCTAssertEqual(Set(acceptance.keys), ["jobId", "statusUrl"])
    let statusURL = try XCTUnwrap(URL(string: XCTUnwrap(acceptance["statusUrl"] as? String)))
    XCTAssertEqual(statusURL.host, "127.0.0.1")
    for _ in 0..<200 {
      let response = try await helper.request(service, path: statusURL.path)
      XCTAssertEqual(response.0.statusCode, 200)
      let snapshot = try object(response.1)
      XCTAssertEqual(snapshot["jobId"] as? String, acceptance["jobId"] as? String)
      if snapshot["status"] as? String == "failed" {
        XCTFail("Native job failed: \(snapshot)")
        break
      }
      if snapshot["status"] as? String == "succeeded" {
        let result = try XCTUnwrap(snapshot["result"] as? [String: Any])
        let outputs = try XCTUnwrap(result["outputs"] as? [[String: Any]])
        let destination = try XCTUnwrap(outputs.first?["destination"] as? [String: Any])
        let url = try XCTUnwrap(URL(string: XCTUnwrap(destination["url"] as? String)))
        let asset = try await helper.request(service, path: url.path)
        XCTAssertEqual(asset.0.statusCode, 200)
        XCTAssertEqual(
          asset.0.value(forHTTPHeaderField: "Content-Type"), expectedMediaType)
        return (statusURL.path, url.path, asset.1)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw NSError(
      domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Job did not succeed"])
  }

  @MainActor func testBothHTTPInterfacesAndDesktopMatchAllIndependentPhotoshopBytes() async throws {
    struct References: Decodable {
      struct Sample: Decodable {
        let width: Int
        let height: Int
        let value: Float
        let opacity: Float
        let offset: Int
      }
      let cases: [Sample]
    }
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftCoreTests/Fixtures/photoshop-component-fill-rgb8")
    let references = try JSONDecoder().decode(
      References.self, from: Data(contentsOf: fixtures.appendingPathExtension("json")))
    let bytes = try Data(contentsOf: fixtures.appendingPathExtension("bin"))
    let transport = Transport()
    let helper = AutomationTests()
    try await helper.withService(resourceTransport: transport) { service, shared in
      let untouched = shared.store.document
      service.setResourceJobsEnabled(true)
      var compared = 0
      for sample in references.cases {
        let count = sample.width * sample.height * 4
        let input = bytes.subdata(in: sample.offset..<sample.offset + count)
        let expected = bytes.subdata(in: sample.offset + count..<sample.offset + count * 2)
        var surface = try Surface(width: sample.width, height: sample.height)
        for y in 0..<sample.height {
          for x in 0..<sample.width {
            let i = (y * sample.width + x) * 4
            surface.setPixel(
              x: x, y: y,
              Pixel(
                Float(input[i]) / 255, Float(input[i + 1]) / 255,
                Float(input[i + 2]) / 255, Float(input[i + 3]) / 255))
          }
        }
        var model = try CraftDocument(width: sample.width, height: sample.height)
        model.layers[0].content = .raster(surface)
        await transport.set(try PSDCodec.writeRasterLayers(model))
        let store = EditorStore(document: model)
        try store.selectEditingChannel(.red)
        store.fill(color: Pixel(sample.value, sample.value, sample.value), opacity: sample.opacity)
        XCTAssertNil(store.error)
        guard case .raster(let desktop) = store.document.layers[0].content else { return XCTFail() }
        XCTAssertEqual(try desktop.rgbaData(depth: .u8), expected)
        await store.undo()
        XCTAssertEqual(store.document, model)
        await store.redo()
        store.renderTask?.cancel()
        for route in ["/v2/execute-actions", "/v1/action-jobs"] {
          let result = try await output(
            service, submit: route, payload: body(value: sample.value, opacity: sample.opacity))
          let decoded = try PSDCodec.read(result.2)
          guard case .raster(let actual) = decoded.layers[0].content else { return XCTFail() }
          XCTAssertEqual(try actual.rgbaData(depth: .u8), expected, route)
          XCTAssertEqual(try actual.rgbaData(depth: .u8), try desktop.rgbaData(depth: .u8))
        }
        compared += count
      }
      XCTAssertEqual(compared, 122_880, "Independent bytes per interface")
      XCTAssertEqual(shared.store.document, untouched, "Resource jobs cannot mutate open documents")
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testEnablementAuthenticationErrorsAndRevocationOverHTTP() async throws {
    let transport = Transport()
    await transport.set(try PSDCodec.writeRasterLayers(CraftDocument(width: 3, height: 2)))
    let helper = AutomationTests()
    try await helper.withService(resourceTransport: transport) { service, _ in
      XCTAssertFalse(service.resourceJobsEnabled)
      let unauthorized = try await helper.request(
        service, path: "/v2/execute-actions", body: body(), authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      XCTAssertEqual(try object(unauthorized.1)["error_code"] as? String, "401013")
      let disabled = try await helper.request(service, path: "/v2/execute-actions", body: body())
      XCTAssertEqual(disabled.0.statusCode, 403)
      let calls = await transport.fetches
      XCTAssertEqual(calls, 0)
      service.setResourceJobsEnabled(true)
      let origin = try await helper.request(
        service, path: "/v2/execute-actions", body: body(),
        headers: ["Origin": "https://example.test"])
      XCTAssertEqual(origin.0.statusCode, 403)
      XCTAssertEqual(try object(origin.1)["error_code"] as? String, "unauthorized_forbidden")
      let invalid = try await helper.request(service, path: "/v2/execute-actions", body: [:])
      XCTAssertEqual(invalid.0.statusCode, 400)
      XCTAssertNotNil(try object(invalid.1)["error_code"])
      let missing = try await helper.request(service, path: "/v2/status/\(UUID())")
      XCTAssertEqual(missing.0.statusCode, 404)
      XCTAssertEqual(try object(missing.1)["error_code"] as? String, "unknown_job_id")
      let result = try await output(service, submit: "/v2/execute-actions", payload: body())
      let assetUnauthorized = try await helper.request(service, path: result.1, authenticate: false)
      XCTAssertEqual(assetUnauthorized.0.statusCode, 401)
      service.setResourceJobsEnabled(false)
      service.setResourceJobsEnabled(true)
      for path in [result.0, result.1] {
        let revoked = try await helper.request(service, path: path)
        XCTAssertEqual(revoked.0.statusCode, 404)
      }
      service.stop()
      XCTAssertFalse(service.resourceJobsEnabled)
      XCTAssertNil(service.token)
    }
  }

  @MainActor func testNativeInputTransferThroughCompleteLoopbackJobWorkflow() async throws {
    let source = AutomationHTTPServer()
    var port: UInt16?
    var requests = 0
    let model = try CraftDocument(width: 4, height: 3)
    let bytes = try PSDCodec.writeRasterLayers(model)
    try source.start(
      onState: { value, _ in port = value },
      handler: { request in
        requests += 1
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/input.psd")
        XCTAssertNil(
          request.headers["authorization"], "Local API token must never go to resource servers")
        return .init(status: 200, contentType: "image/vnd.adobe.photoshop", body: bytes)
      })
    defer { source.stop() }
    for _ in 0..<100 where port == nil { try await Task.sleep(for: .milliseconds(10)) }
    let sourcePort = try XCTUnwrap(port)
    let helper = AutomationTests()
    try await helper.withService { service, _ in
      service.setResourceJobsEnabled(true)
      var payload = body()
      payload["image"] = ["source": ["url": "http://127.0.0.1:\(sourcePort)/input.psd"]]
      let result = try await output(service, submit: "/v2/execute-actions", payload: payload)
      XCTAssertEqual(requests, 1)
      let decoded = try PSDCodec.read(result.2)
      let store = EditorStore(document: model)
      defer { store.renderTask?.cancel() }
      try store.selectEditingChannel(.red)
      store.fill(color: .white, opacity: 0.5)
      guard case .raster(let actual) = decoded.layers[0].content,
        case .raster(let expected) = store.document.layers[0].content
      else { return XCTFail() }
      XCTAssertEqual(try actual.rgbaData(depth: .u8), try expected.rgbaData(depth: .u8))
    }
  }

  func testRouteSpecificFramingBudgetAndAcceptedWireStatus() throws {
    for path in ["/v2/execute-actions", "/v1/action-jobs"] {
      let header = "POST \(path) HTTP/1.1\r\nContent-Length: 65537\r\n\r\n"
      XCTAssertNil(try AutomationRequest.parse(Data(header.utf8)))
      XCTAssertNotNil(
        try AutomationRequest.parse(Data(header.utf8) + Data(repeating: 32, count: 65537)))
      XCTAssertThrowsError(
        try AutomationRequest.parse(
          Data("POST \(path) HTTP/1.1\r\nContent-Length: 4194305\r\n\r\n".utf8)))
    }
    for path in ["/v1/documents/id/commands", "/v2/unsupported", "/"] {
      XCTAssertThrowsError(
        try AutomationRequest.parse(
          Data("POST \(path) HTTP/1.1\r\nContent-Length: 65537\r\n\r\n".utf8)))
    }
    XCTAssertTrue(
      String(decoding: AutomationResponse.json([:], status: 202).wire, as: UTF8.self).hasPrefix(
        "HTTP/1.1 202 Accepted\r\n"))
  }
}
