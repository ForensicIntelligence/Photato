import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LinkedSmartObjectGeometryWorkflowTests: XCTestCase {
  private func reopen(_ format: PSDFileFormat) throws -> CraftDocument {
    let pixels = try Surface(width: 8, height: 4, fill: Pixel(1, 0, 0))
    let bytes = try RasterIO.encoded(pixels)
    let link = try LinkedSmartObjectSource(
      reference: "file:///does-not-exist/Fixture.png",
      contentHash: LinkedSmartObjectSource.fingerprint(bytes), byteLength: UInt64(bytes.count))
    var canvas = try CraftDocument(width: 128, height: 128, name: "Linked geometry reference")
    var layer = try LinkedSmartObjectIO.place(bytes, fileName: "Fixture.png", reference: link, in: canvas, fit: false)
    layer.x = 20
    layer.y = 10
    layer.affine = .translation(0.25, 0.5) * .rotation(30) * .scale(2, 2)
    try Command.addLayer(layer).apply(to: &canvas)
    var result = try PSDCodec.read(PSDCodec.writeRasterLayers(canvas, format: format))
    let linked = try XCTUnwrap(result.layers.last)
    XCTAssertNotNil(try linked.linkedSmartObjectPreview())
    XCTAssertTrue(try XCTUnwrap(linked.smartObject).data.isEmpty)
    result.activeLayerID = linked.id
    return result
  }

  @MainActor func testLinkedPropertiesAndFreeTransformUseArtworkBoundsInPSDAndPSB() async throws {
    let initial = IntRect(x: 16, y: 10, width: 19, height: 16)
    let expected = IntRect(x: 30, y: 40, width: 17, height: 9)
    for format in [PSDFileFormat.psd, .psb] {
      let reopened = try reopen(format)
      let store = EditorStore(document: reopened)
      defer { store.renderTask?.cancel() }
      let layer = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(try XCTUnwrap(store.layerRotation(layer)), 30, accuracy: 1e-8)
      XCTAssertEqual(store.activeLayerBounds, initial)
      let source = try layer.smartObjectSourceTransform()
      let next = Transform2D(a: 2, d: 2, tx: 30.25, ty: 40.5)
      store.perform(.transform(layer.id, next * (try source.inverted()), .bicubic))
      let moved = try XCTUnwrap(store.activeLayer)
      guard case .raster(let cache) = moved.content else { return XCTFail("Missing the linked preview") }
      XCTAssertNotEqual(try moved.coordinateTransform.bounds(width: cache.width, height: cache.height), expected)
      XCTAssertEqual(store.activeLayerBounds, expected)
      XCTAssertEqual(store.activeLayerSize, CGSize(width: 17, height: 9))
      XCTAssertEqual(try XCTUnwrap(store.layerRotation(moved)), 0, accuracy: 1e-8)
      store.beginTransform()
      XCTAssertEqual(store.transformDraft?.bounds, expected)
      store.cancelTransform()
      await store.undo()
      XCTAssertEqual(store.document, reopened)
    }
  }

  @MainActor func testNativePositionFieldUsesArtworkOriginAndCommitsOneUndo() async throws {
    var model = try reopen(.psd)
    let original = try XCTUnwrap(model.activeLayerID.flatMap { id in model.layers.first { $0.id == id } })
    let source = try original.smartObjectSourceTransform()
    let target = Transform2D(a: 2, d: 2, tx: 30.25, ty: 40.5)
    try Command.transform(original.id, target * (try source.inverted()), .bicubic).apply(to: &model)
    let document = CraftNSDocument(model: model)
    let helper = NumericFieldEditingTests()
    try await helper.withPositionFields(document: document) { store, _, x, y in
      XCTAssertEqual(x.stringValue, "30")
      XCTAssertEqual(y.stringValue, "40")
      let editor = try helper.replace(x, with: "37")
      XCTAssertEqual(store.document, model)
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      XCTAssertEqual(store.activeLayerBounds, IntRect(x: 37, y: 40, width: 17, height: 9))
      let active = try XCTUnwrap(store.activeLayer)
      XCTAssertEqual(try active.smartObjectSourceTransform().tx, 37.25, accuracy: 1e-8)
      XCTAssertEqual(active.smartObject, original.smartObject)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertEqual(store.document, model)
    }
  }

  @MainActor func testHTTPExposesOriginalGeometryThroughMoveAndUndo() async throws {
    let input = try reopen(.psb)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      store.session = EditorSession(document: input)
      try service.share(shared)
      let id = try XCTUnwrap(service.shares.first?.id)
      let layerID = try XCTUnwrap(store.activeLayer?.id)
      @MainActor func state() async throws -> (legacy: [String: Double], source: [String: Double], bounds: [String: Int], angle: Double) {
        let reply = try await AutomationTests().request(service, path: "/v1/documents/\(id)")
        XCTAssertEqual(reply.0.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: reply.1) as? [String: Any])
        let layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        let layer = try XCTUnwrap(layers.first { $0["id"] as? String == layerID.uuidString })
        let smart = try XCTUnwrap(layer["smartObject"] as? [String: Any])
        let geometry = try XCTUnwrap(smart["sourceGeometry"] as? [String: Any])
        return (try XCTUnwrap(layer["transform"] as? [String: Double]),
                try XCTUnwrap(geometry["transform"] as? [String: Double]),
                try XCTUnwrap(geometry["bounds"] as? [String: Int]),
                try XCTUnwrap(geometry["rotationDegrees"] as? Double))
      }
      let before = try await state()
      XCTAssertEqual(before.legacy["b"], 0)
      XCTAssertEqual(before.legacy["tx"], 16)
      XCTAssertEqual(try XCTUnwrap(before.source["b"]), 1, accuracy: 1e-8)
      XCTAssertEqual(try XCTUnwrap(before.source["tx"]), 20.25, accuracy: 1e-8)
      XCTAssertEqual(before.bounds, ["x": 16, "y": 10, "width": 19, "height": 16])
      XCTAssertEqual(before.angle, try XCTUnwrap(store.layerRotation(XCTUnwrap(store.activeLayer))), accuracy: 1e-8)
      let capabilities = try await helper.request(service, path: "/v1/capabilities")
      XCTAssertEqual(capabilities.0.statusCode, 200)
      XCTAssertTrue(String(decoding: capabilities.1, as: UTF8.self).contains("\"sourceGeometry\""))
      XCTAssertEqual(store.document, input)
      XCTAssertTrue(store.session.undoStack.isEmpty)

      let parameters: [String: Any] = ["layerID": layerID.uuidString, "a": 1, "b": 0, "c": 0, "d": 1, "tx": 5, "ty": -3]
      let applied = try await helper.edit(service, shared, "layer.transform", parameters)
      XCTAssertEqual(applied, 200)
      let moved = try await state()
      XCTAssertEqual(try XCTUnwrap(moved.source["tx"]), 25.25, accuracy: 1e-8)
      XCTAssertEqual(try XCTUnwrap(moved.source["ty"]), 7.5, accuracy: 1e-8)
      XCTAssertEqual(moved.bounds, ["x": 21, "y": 7, "width": 19, "height": 16])
      let reverted = try await helper.edit(service, shared, "history.undo")
      XCTAssertEqual(reverted, 200)
      let afterUndo = try await state()
      XCTAssertEqual(afterUndo.legacy, before.legacy)
      XCTAssertEqual(afterUndo.source, before.source)
      XCTAssertEqual(store.document, input)
    }
  }

  func testWarpedArtworkOmitsAffineGeometry() throws {
    let input = try reopen(.psd)
    var linked = try XCTUnwrap(input.layers.last)
    var warp = WarpDefinition()
    warp.style = .arc
    warp.bend = 25
    linked.warp = warp
    XCTAssertNil(try linked.smartObjectGeometry())
    XCTAssertTrue(linked.smartObjectAPIState?["sourceGeometry"] is NSNull)
    XCTAssertNil(input.layers.first?.smartObjectAPIState)
  }
}
