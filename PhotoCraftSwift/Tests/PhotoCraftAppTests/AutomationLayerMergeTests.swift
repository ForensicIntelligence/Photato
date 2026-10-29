import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class AutomationLayerMergeTests: XCTestCase {
  func fixture(_ name: String) throws -> CraftDocument {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    return try PSDCodec.read(
      Data(
        contentsOf: root.appendingPathComponent(
          "PhotoCraftImagingTests/Fixtures/layer-merge/" + name + ".psd")))
  }
  func samePixels(_ actual: CraftDocument, _ expected: CraftDocument) throws {
    XCTAssertEqual(actual.layers.count, expected.layers.count)
    XCTAssertEqual(try ColorManagement.space(for: actual), try ColorManagement.space(for: expected))
    if let embedded = expected.workingICC { XCTAssertEqual(actual.workingICC, embedded) }
    for (a, b) in zip(actual.layers, expected.layers) {
      XCTAssertEqual(a.name, b.name)
      XCTAssertEqual(a.x, b.x)
      XCTAssertEqual(a.y, b.y)
      guard case .raster(let x) = a.content, case .raster(let y) = b.content else {
        return XCTFail()
      }
      let encoding: SurfaceColorEncoding = actual.depth == .f32 ? .linearRGB : .sRGB
      if actual.depth == .f32, x.width == 256, x.height == 7, a.name == "Source", a.x == 0, a.y == 1
      {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
          .deletingLastPathComponent()
        let raw = try Data(
          contentsOf: root.appendingPathComponent(
            "PhotoCraftImagingTests/Fixtures/layer-merge/original-profile-down-rgb32.rgba"))
        let output = try x.rgbaData(depth: .f32, colorEncoding: .linearRGB)
        XCTAssertEqual(output.count, raw.count)
        XCTAssertEqual(zip(output, raw).filter { $0 != $1 }.count, 0)
      }
      XCTAssertEqual(
        try x.rgbaData(depth: actual.depth, colorEncoding: encoding),
        try y.rgbaData(depth: expected.depth, colorEncoding: encoding))
    }
  }
  @MainActor func testEveryMergeDepthDesktopHTTPPhotoshopAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      for bits in [8, 16, 32] {
        for (name, operation) in [
          ("down", LayerMergeOperation.down), ("selected", .selected), ("visible", .visible),
        ] {
          let original = try fixture("photoshop-source-rgb\(bits)")
          let expected = try fixture("photoshop-\(name)-rgb\(bits)")
          let desktop = EditorStore(document: original)
          defer { desktop.renderTask?.cancel() }
          if operation == .selected { desktop.selectedLayerIDs = Set(original.layers.map(\.id)) }
          desktop.merge(operation)
          await desktop.geometryTask?.value
          XCTAssertNil(desktop.error)
          try samePixels(desktop.document, expected)
          let store = shared.store
          store.session = EditorSession(document: original)
          store.selectedLayerIDs = Set(original.activeLayerID.map { [$0] } ?? [])
          let ids =
            operation == .visible
            ? []
            : operation == .down
              ? [try XCTUnwrap(original.activeLayerID).uuidString]
              : original.layers.map { $0.id.uuidString }
          let status = try await helper.edit(
            service, shared, "layer.merge", ["operation": name, "layerIDs": ids])
          XCTAssertEqual(status, 200)
          let share = try XCTUnwrap(service.shares.first)
          let response = try await helper.request(service, path: "/v1/documents/\(share.id)")
          XCTAssertEqual(response.0.statusCode, 200)
          let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: response.1) as? [String: Any])
          let profile = try XCTUnwrap(state["workingProfile"] as? [String: Any])
          XCTAssertEqual(profile["embedded"] as? Bool, original.workingICC != nil)
          XCTAssertEqual(
            profile["sampleEncoding"] as? String, bits == 32 ? "linearRGB" : "profileRGB")
          XCTAssertEqual(
            (profile["iccSHA256"] as? String)?.count, original.workingICC == nil ? nil : 64)
          XCTAssertEqual(store.document, desktop.document)
          try samePixels(PSDCodec.read(PSDCodec.writeRasterLayers(store.document)), expected)
          XCTAssertEqual(
            store.selectedLayerIDs, Set(store.document.activeLayerID.map { [$0] } ?? []))
          XCTAssertEqual(store.session.undoStack.map(\.label), [operation.rawValue])
          XCTAssertTrue(shared.isDocumentEdited)
          let undo = try await helper.edit(service, shared, "history.undo")
          XCTAssertEqual(undo, 200)
          XCTAssertEqual(store.document, original)
          let redo = try await helper.edit(service, shared, "history.redo")
          XCTAssertEqual(redo, 200)
          XCTAssertEqual(store.document, desktop.document)
          await store.undo()
          store.renderTask?.cancel()
          XCTAssertEqual(store.document, original)
          shared.updateChangeCount(.changeCleared)
        }
      }
    }
  }
  @MainActor func testMergeRejectsInvalidStaleBusyContextAndOversizedRequestsAtomically()
    async throws
  {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let original = try fixture("photoshop-source-rgb8")
      let store = shared.store
      store.session = EditorSession(document: original)
      let id = try XCTUnwrap(original.activeLayerID).uuidString
      let valid: [String: Any] = ["operation": "down", "layerIDs": [id]]
      for bad: [String: Any] in [
        ["operation": "unknown", "layerIDs": [id]], ["operation": "down", "layerIDs": id],
        ["operation": "down", "layerIDs": [true]], ["operation": "down", "layerIDs": [id, id]],
        ["operation": "selected", "layerIDs": [id]], ["operation": "visible", "layerIDs": [id]],
      ] {
        let result = try await helper.edit(service, shared, "layer.merge", bad)
        XCTAssertEqual(result, 400)
      }
      let missing = try await helper.edit(
        service, shared, "layer.merge", ["operation": "down", "layerIDs": [UUID().uuidString]])
      XCTAssertEqual(missing, 404)
      let stale = try await helper.edit(service, shared, "layer.merge", valid, revision: "stale")
      XCTAssertEqual(stale, 409)
      store.geometryBusy = true
      let busy = try await helper.edit(service, shared, "layer.merge", valid)
      XCTAssertEqual(busy, 409)
      store.geometryBusy = false
      try store.selectEditingChannel(.red)
      let component = try await helper.edit(service, shared, "layer.merge", valid)
      XCTAssertEqual(component, 422)
      try store.selectEditingChannel(.composite)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      for variant in 0..<3 {
        var changed = original
        if variant == 0 { changed.layers[1].locked = true }
        if variant == 1 { changed.layers[1].mask = try Surface(width: 1, height: 1, fill: .white) }
        if variant == 2 {
          changed.layers[1].x = 10_000
          changed.layers[1].y = 1_000
        }
        store.session = EditorSession(document: changed)
        let result = try await helper.edit(service, shared, "layer.merge", valid)
        XCTAssertEqual(result, variant == 2 ? 413 : 422)
        XCTAssertEqual(store.document, changed)
        XCTAssertTrue(store.session.undoStack.isEmpty)
      }
    }
  }
}
