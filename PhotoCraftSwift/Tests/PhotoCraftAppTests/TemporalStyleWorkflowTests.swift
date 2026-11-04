import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class TemporalStyleWorkflowTests: XCTestCase {
  func fixture(video: Bool, depth: PixelDepth = .u8, existingStyle: Bool = false) throws -> CraftDocument {
    var document = try CraftDocument(width: 6, height: 4, depth: depth)
    var layer = Layer(name: "Owned square", content: .raster(try Surface(width: 2, height: 2, depth: depth, fill: Pixel(1, 0, 0))))
    if existingStyle { layer.style = blue }
    document.layers = [layer]; document.activeLayerID = layer.id
    if video {
      try Command.video(.create(frameRate: 4, durationFrames: 9)).apply(to: &document)
      try Command.video(.keyframe(.enable(layer.id, .style))).apply(to: &document)
      try document.selectVideoFrame(8)
      if existingStyle { try Command.video(.keyframe(.set(layer.id, .style, 2))).apply(to: &document) }
    } else {
      try Command.animation(.create).apply(to: &document)
      try Command.animation(.duplicate).apply(to: &document)
    }
    return document
  }
  var blue: LayerStyle {
    var effect = LayerEffect(.colorOverlay); effect.color = Pixel(0, 0, 1)
    return LayerStyle(effects: [effect])
  }
  func assertSquare(_ surface: Surface, fraction: Float, linear: Bool, file: StaticString = #filePath, line: UInt = #line) {
    for y in 0..<4 { for x in 0..<6 {
      let expected = x < 2 && y < 2 ? Pixel(1 - fraction, 0, fraction) : Pixel.clear
      let actual = linear ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
      let accuracy: Float = linear ? 0.000001 : 1.0 / 255
      XCTAssertEqual(actual.r, expected.r, accuracy: accuracy, file: file, line: line)
      XCTAssertEqual(actual.g, expected.g, file: file, line: line)
      XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, file: file, line: line)
      XCTAssertEqual(actual.a, expected.a, file: file, line: line)
    } }
  }
  @MainActor func testNativeStylePreviewCancelCommitHistoryAndAnalyticFramesAtAllDepths() async throws {
    for video in [true, false] { for depth in [PixelDepth.u8, .u16, .f32] {
      let original = try fixture(video: video, depth: depth), store = EditorStore(document: original)
      defer { store.renderTask?.cancel() }
      store.beginLayerStyle(.colorOverlay)
      LayerStyleSheet(store: store).value(\.color, .black).wrappedValue = Pixel(0, 0, 1)
      await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.document, original); XCTAssertEqual(store.session.undoStack.count, 0)
      let preview = try XCTUnwrap(store.renderSnapshot)
      XCTAssertEqual(preview.document.layers[0].style, blue); assertSquare(preview.surface, fraction: 1, linear: depth == .f32)
      try preview.document.validate()
      store.cancelLayerStyle(); await store.renderTask?.value
      XCTAssertEqual(store.document, original); XCTAssertEqual(store.session.undoStack.count, 0)
      assertSquare(try XCTUnwrap(store.surface), fraction: 0, linear: depth == .f32)
      store.beginLayerStyle(.colorOverlay)
      LayerStyleSheet(store: store).value(\.color, .black).wrappedValue = Pixel(0, 0, 1)
      store.commitLayerStyle(); await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1)
      let changed = store.document; XCTAssertEqual(changed.layers[0].style, blue)
      let undone = await store.undo(); XCTAssertTrue(undone); XCTAssertEqual(store.document, original)
      let redone = await store.redo(); XCTAssertTrue(redone); XCTAssertEqual(store.document, changed)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(changed)), changed)
      for frame in [0, 4, 8] {
        let sample: CraftDocument
        if video { sample = try changed.videoDocument(at: frame) }
        else { sample = try changed.animationDocument(at: changed.animation!.frames[frame == 0 ? 0 : 1].id) }
        let fraction: Float = video ? Float(frame) / 8 : (frame == 0 ? 0 : 1)
        assertSquare(try Renderer.composite(sample), fraction: fraction, linear: depth == .f32)
        if let directory = ProcessInfo.processInfo.environment["PHOTATO_TEMPORAL_STYLE_OUTPUT_DIR"] {
          let name = "\(video ? "video" : "frames")-\(depth)-\(frame).png"
          try DocumentIO.encode(sample, format: .png).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
        }
      }
    } }
  }
  @MainActor func testHTTPReplacePatchClearPersistenceHistoryAndInvalidBusyStale() async throws {
    let helper = AutomationTests()
    for video in [true, false] {
      try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
        let original = try fixture(video: video, existingStyle: true), store = shared.store
        store.session = EditorSession(document: original); try service.share(shared); service.setDocumentTransfersEnabled(true)
        let id = original.layers[0].id, share = try XCTUnwrap(service.shares.first?.id)
        let capabilityReply = try await helper.request(service, path: "/v1/capabilities")
        XCTAssertEqual(capabilityReply.0.statusCode, 200)
        let capabilities = try XCTUnwrap(JSONSerialization.jsonObject(with: capabilityReply.1) as? [String: Any])
        let styleCapabilities = try XCTUnwrap(capabilities["layerStyles"] as? [String: Any])
        XCTAssertNotNil(styleCapabilities["temporalEditing"] as? String)
        let parameters: [String: Any] = ["layerIDs": [id.uuidString], "style": ["effects": [["kind": "colorOverlay", "color": ["r": 0, "g": 1, "b": 0, "a": 1]]]], "globalLight": ["angle": 73.375, "altitude": 31.25]]
        let replace = try await helper.edit(service, shared, "layer.style", parameters); XCTAssertEqual(replace, 200)
        var green = blue; green.effects[0].color = Pixel(0, 1, 0)
        var expected = original
        try Command.layerStyles(LayerStyleEdit(layerIDs: [id], style: green, globalLight: GlobalLight(angle: 73.375, altitude: 31.25))).apply(to: &expected)
        XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
        let patch: [String: Any] = ["layerIDs": [id.uuidString], "effectIndex": 0, "effect": ["opacity": 0.25]]
        let patched = try await helper.edit(service, shared, "layer.style.patch", patch); XCTAssertEqual(patched, 200)
        green.effects[0].opacity = 0.25
        try Command.layerStyles(LayerStyleEdit(layerIDs: [id], style: green)).apply(to: &expected)
        XCTAssertEqual(store.document, expected)
        let beforeRejects = store.document, revision = service.revision(store), count = store.session.undoStack.count
        let stale = try await helper.edit(service, shared, "layer.style", parameters, revision: "old"); XCTAssertEqual(stale, 409)
        let invalid = try await helper.edit(service, shared, "layer.style.patch", ["layerIDs": [id.uuidString], "effectIndex": 0, "effect": ["opacity": 2]]); XCTAssertEqual(invalid, 400)
        XCTAssertEqual(service.revision(store), revision)
        store.beginLayerStyle()
        let busyRevision = service.revision(store)
        let busy = try await helper.edit(service, shared, "layer.style", parameters); XCTAssertEqual(busy, 409)
        XCTAssertEqual(service.revision(store), busyRevision)
        store.cancelLayerStyle()
        XCTAssertEqual(store.document, beforeRejects); XCTAssertEqual(store.session.undoStack.count, count)
        let download = try await helper.request(service, path: "/v1/documents/\(share)/file.photato", headers: ["X-Photato-Archive-Version": "85"])
        XCTAssertEqual(download.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(download.1), expected)
        let clear = try await helper.edit(service, shared, "layer.style", ["layerIDs": [id.uuidString], "style": NSNull()]); XCTAssertEqual(clear, 200)
        try Command.layerStyle([id], nil).apply(to: &expected); XCTAssertEqual(store.document, expected)
        let undo = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(store.document, beforeRejects)
        let redo = try await helper.edit(service, shared, "history.redo"); XCTAssertEqual(redo, 200); XCTAssertEqual(store.document, expected)
        XCTAssertEqual(store.session.undoStack.count, count + 1)
      }
    }
  }
}
