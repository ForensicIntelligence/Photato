import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct DocumentedStackTransport: AdobeResourceTransport {
  let data: Data
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("Use hosted fixture output.") }
}

final class DocumentedStackWorkflowTests: XCTestCase {
  let modes: [ImageStackMode] = [.variance, .standardDeviation, .skewness, .kurtosis, .entropy]
  func source() throws -> CraftDocument {
    var d = try CraftDocument(width: 1, height: 1, depth: .f32)
    d.layers = []
    for pixel in [Pixel(0, 0, 0), Pixel(0.5, 0, 0.75), Pixel(1, 1, 1)] {
      var surface = try Surface(width: 1, height: 1, depth: .f32, colorEncoding: .linearRGB)
      surface.setLinearPixel(x: 0, y: 0, pixel)
      d.layers.append(Layer(name: "Owned sample", content: .raster(surface)))
    }
    d.activeLayerID = d.layers.last?.id
    try SmartObjectIO.convert(in: d, selected: Set(d.layers.map(\.id))).apply(to: &d)
    return d
  }
  func expected() throws -> [String: [String: UInt32]] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("PhotoCraftCoreTests/Fixtures/ImageStack/documented-statistics.json")
    let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let rows = try XCTUnwrap(raw["cases"] as? [[String: Any]])
    return Dictionary(uniqueKeysWithValues: try rows.map { row in
      (try XCTUnwrap(row["name"] as? String), try XCTUnwrap(row["expectedWords"] as? [String: UInt32]))
    })
  }
  func assertWords(_ document: CraftDocument, mode: ImageStackMode, expected: [String: [String: UInt32]]) throws {
    guard case .raster(let surface) = document.layers[0].content else { return XCTFail("Missing stack raster") }
    let pixel = surface.linearPixel(x: 0, y: 0)
    for (name, value) in [("channelRed", pixel.r), ("channelGreen", pixel.g), ("channelBlue", pixel.b)] {
      XCTAssertEqual(value.bitPattern, try XCTUnwrap(expected[name]?[mode.rawValue]), name + ":" + mode.rawValue)
    }
    XCTAssertEqual(pixel.a, 1)
  }
  @MainActor func testNativeAndPhotatoAPIUseDocumentedNumbersWithHistoryAndPersistence() async throws {
    let helper = AutomationTests(), expected = try expected()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let original = try source(), id = original.layers[0].id
      try service.share(shared)
      for mode in modes {
        shared.store.session = EditorSession(document: original); shared.store.selectedLayerIDs = [id]
        let native = EditorStore(document: original)
        defer { native.renderTask?.cancel() }
        native.setImageStackMode(mode); await native.geometryTask?.value
        XCTAssertNil(native.error); try assertWords(native.document, mode: mode, expected: expected)
        XCTAssertEqual(native.document.layers[0].smartObject?.data, original.layers[0].smartObject?.data)
        var status = try await helper.edit(service, shared, "smartObject.stackMode", ["layerID": id.uuidString, "mode": mode.rawValue])
        XCTAssertEqual(status, 200); XCTAssertEqual(shared.store.document, native.document)
        XCTAssertEqual(try NativeArchive.encodeChunked(shared.store.document), try NativeArchive.encodeChunked(native.document))
        let saved = native.document
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(saved)), saved)
        XCTAssertEqual(native.session.undoStack.count, 1)
        await native.undo(); status = try await helper.edit(service, shared, "history.undo")
        XCTAssertEqual(status, 200); XCTAssertEqual(native.document, original); XCTAssertEqual(shared.store.document, original)
        await native.redo(); status = try await helper.edit(service, shared, "history.redo")
        XCTAssertEqual(status, 200); XCTAssertEqual(native.document, saved); XCTAssertEqual(shared.store.document, saved)
      }
    }
  }
  @MainActor func testBothAdobeJobRoutesShareCorrectedStackMath() async throws {
    let input = try PSDCodec.writeRasterLayers(source()), decoded = try PSDCodec.read(input)
    let codes: [(String, ImageStackMode)] = [("$vari", .variance), ("$stdv", .standardDeviation), ("$skew", .skewness), ("$kurt", .kurtosis), ("$entr", .entropy)]
    try await AutomationTests().withService(pressedMouseButtons: { 0 }, resourceTransport: DocumentedStackTransport(data: input)) { service, shared in
      service.setResourceJobsEnabled(true); let untouched = shared.store.document
      for (code, mode) in codes {
        let action = "[{\"_obj\":\"applyImageStackPluginRenderer\",\"imageStackPlugin\":{\"_class\":\"\(code)\"},\"name\":\"Documented statistic\"}]"
        var expected = decoded
        try ImageStack.command(in: decoded, layerID: decoded.layers[0].id, mode: mode).apply(to: &expected)
        let body: [String: Any] = ["image": ["source": ["url": "https://example.test/owned-stack.psd"]],
          "options": ["actions": [["source": ["content": action, "contentType": "application/json"]]]],
          "outputs": [["mediaType": "image/tiff", "destination": ["validityPeriod": 60]]]]
        for route in ["/v1/action-jobs", "/v2/execute-actions"] {
          let result = try await AutomationActionJobsTests().output(service, submit: route, payload: body, expectedMediaType: "image/tiff")
          XCTAssertEqual(result.2, try DocumentIO.encode(expected, format: .tiff))
        }
      }
      XCTAssertEqual(shared.store.document, untouched)
    }
  }
}
