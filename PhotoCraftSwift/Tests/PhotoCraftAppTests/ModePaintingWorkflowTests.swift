import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ModePaintingWorkflowTests: XCTestCase {
  var contexts: [(DocumentColorMode, PixelDepth)] {
    (DocumentColorMode.componentModes + [.indexed, .bitmap]).flatMap { mode in
      (mode == .bitmap ? [PixelDepth.u8] : mode.depths).map { (mode, $0) }
    }
  }
  func document(_ mode: DocumentColorMode, depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 12, height: 8)
    document.layers[0].content = .raster(try Surface(width: 12, height: 8, fill: Pixel(0.3, 0.6, 0.8)))
    if mode == .indexed {
      return try document.replacingRestrictedMode(.indexed(.init(width: 12, height: 8,
        palette: [.init(0, 0, 0), .init(255, 0, 0), .init(255, 0, 0), .init(255, 255, 255)], indices: Data(repeating: 2, count: 96))))
    }
    if mode == .bitmap {
      return try document.replacingRestrictedMode(.bitmap(.init(width: 12, height: 8, bits: Data((0..<8).flatMap { _ in [UInt8(255), 240] }))))
    }
    return try document.convertingMode(.init(mode: mode, depth: depth))
  }
  func request(_ document: CraftDocument, tool: PaintTool = .pencil) -> PaintToolRequest {
    var brush = Brush(); brush.size = 3; brush.hardness = 1; brush.color = .white; brush.backgroundColor = .white
    brush.settings = .init(); brush.settings!.pressureSize = false; brush.settings!.seed = 9
    return .init(tool: tool, target: .pixels(document.activeLayerID!), points: [.init(x: 4, y: 4), .init(x: 7, y: 4)], brush: brush)
  }
  func testPreparedPencilSamplesMatchCommitAndNativeReopenInEveryMode() throws {
    for (mode, depth) in contexts {
      let original = try document(mode, depth: depth), prepared = try PaintingPreparation.prepare(request(original), in: original)
      var session = EditorSession(document: original); try session.execute(.painting(prepared))
      XCTAssertTrue(prepared.result == session.document, "Prepared and committed samples differ: \(mode)")
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(prepared.result)) == prepared.result, "Prepared pixels are lost on reopen: \(mode)")
      XCTAssertFalse(session.document == original, "Fixture did not paint: \(mode)")
      try session.undo(); XCTAssertTrue(session.document == original)
      try session.redo(); XCTAssertTrue(session.document == prepared.result, "Redo differs from preview: \(mode)")
    }
  }

  func testEveryPaintToolPreservesUnselectedSamplesAndCanonicalStorage() throws {
    for (mode, depth) in contexts { for tool in PaintTool.allCases {
      var original = try document(mode, depth: depth)
      original.selection = .init(x: 3, y: 2, width: 6, height: 4)
      var stroke = request(original, tool: tool)
      if tool == .magicEraser { stroke.points = [stroke.points[0]] }
      if tool == .colorReplacement { stroke.options.replacementMode = .luminosity }
      if tool == .mixerBrush { stroke.options.wet = 0; stroke.options.mix = 0; stroke.options.load = 1; stroke.mixer.load(.white) }
      if tool == .patternStamp { stroke.pattern = try RasterPattern(name: "White", surface: Surface(width: 2, height: 2, fill: .white)) }
      let prepared = try PaintingPreparation.prepare(stroke, in: original), result = prepared.result
      let label = "\(mode)/\(depth)/\(tool)"
      XCTAssertFalse(result == original, "Fixture did not paint: \(label)")
      var session = EditorSession(document: original); try session.execute(.painting(prepared))
      XCTAssertTrue(result == session.document, "Commit differs: \(label)")
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result)) == result, "Reopen differs: \(label)")
      if let native = result.layers[0].nativeMode, let before = original.layers[0].nativeMode {
        for component in 0...mode.componentCount {
          for y in 0..<8 { for x in 0..<12 where !original.selection!.contains(x, y) {
            XCTAssertEqual(native.value(component: component, index: y * 12 + x), before.value(component: component, index: y * 12 + x), "Unselected sample changed: \(label)")
          } }
        }
      }
      if case .indexed(let raster) = result.restrictedMode {
        XCTAssertEqual(raster.palette, [.init(0, 0, 0), .init(255, 0, 0), .init(255, 0, 0), .init(255, 255, 255)])
        for y in 0..<8 { for x in 0..<12 where !original.selection!.contains(x, y) {
          XCTAssertEqual(raster.indices[y * 12 + x], 2, "Duplicate palette identity changed: \(label)")
        } }
      }
      if case .bitmap(let raster) = result.restrictedMode {
        for y in 0..<8 { XCTAssertEqual(raster.bits[y * 2 + 1] & 15, 0, "Bitmap row padding changed") }
      }
      var stale = original; stale.name = "Changed during preparation"
      XCTAssertThrowsError(try prepared.applied(to: stale))
    } }
  }

  func testIndexedErasureUsesTransparencyAndRetainsDuplicateIndices() throws {
    for tool in [PaintTool.backgroundEraser, .magicEraser] {
      var original = try document(.indexed)
      original = try original.replacingColorTable([.init(0, 0, 0), .init(255, 0, 0), .init(255, 0, 0), .init(255, 255, 255)], transparentIndex: 0)
      original.selection = .init(x: 3, y: 2, width: 6, height: 4)
      var stroke = request(original, tool: tool); stroke.points = [stroke.points[0]]
      let prepared = try PaintingPreparation.prepare(stroke, in: original)
      guard case .indexed(let raster) = prepared.result.restrictedMode else { return XCTFail("Missing Indexed storage") }
      XCTAssertEqual(raster.indices[4 * 12 + 4], 0)
      XCTAssertEqual(raster.indices[0], 2)
      XCTAssertEqual(try raster.surface().pixel(x: 4, y: 4).a, 0)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(prepared.result)) == prepared.result)
    }
  }

  @MainActor func testNativePreviewCancelCommitAndHistoryAcrossModesAndDepths() async throws {
    for (mode, depth) in contexts {
      let original = try document(mode, depth: depth), store = try PaintingWorkflowTests().store(original)
      defer { store.cancelBrush(); store.renderTask?.cancel() }
      store.tool = .pencil; store.brush.color = .white; store.brush.size = 3
      store.beginBrush(.init(x: 4, y: 4), zoom: 1); store.extendBrush(.init(x: 7, y: 4))
      let preview = try PaintingPreparation.prepare(XCTUnwrap(store.brushGesture?.paintingRequest), in: original)
      await store.brushPreviewTask?.value; await store.renderTask?.value
      XCTAssertTrue(store.surface == (try Renderer.composite(preview.result)), "Preview: \(mode)/\(depth)")
      XCTAssertTrue(store.document == original)
      store.cancelBrush(); await store.renderTask?.value
      XCTAssertTrue(store.document == original); XCTAssertTrue(store.session.undoStack.isEmpty)
      store.beginBrush(.init(x: 4, y: 4), zoom: 1); store.extendBrush(.init(x: 7, y: 4))
      let final = try PaintingPreparation.prepare(XCTUnwrap(store.brushGesture?.paintingRequest), in: original)
      store.finishBrush(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertTrue(store.document == final.result); XCTAssertEqual(store.session.undoStack.count, 1)
      _ = await store.requestHistory(redo: false).value; XCTAssertTrue(store.document == original)
      _ = await store.requestHistory(redo: true).value; XCTAssertTrue(store.document == final.result)
    }
  }

  func testAutomaticLayersAndMasksRetainNativeComponents() throws {
    for (mode, depth) in contexts where !mode.isRestricted {
      var original = try document(mode, depth: depth)
      original.layers[0].content = .fill(.white); original.layers[0].nativeMode = nil
      let created = try PaintingPreparation.prepare(request(original), in: original)
      XCTAssertEqual(created.result.layers.count, 2)
      XCTAssertNotNil(created.result.layers.first(where: { $0.id == created.result.activeLayerID })?.nativeMode)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(created.result)) == created.result)
      var masked = try document(mode, depth: depth)
      masked.layers[0].mask = try Surface(width: 12, height: 8, fill: .white)
      var stroke = request(masked); stroke.target = .layerMask(masked.layers[0].id); stroke.brush.color = .black
      let painted = try PaintingPreparation.prepare(stroke, in: masked)
      XCTAssertTrue(painted.result.layers[0].nativeMode == masked.layers[0].nativeMode)
      XCTAssertTrue(painted.result.layers[0].content == masked.layers[0].content)
      XCTAssertNotEqual(painted.result.layers[0].mask?.pixel(x: 4, y: 4), masked.layers[0].mask?.pixel(x: 4, y: 4))
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(painted.result)) == painted.result)
    }
  }

  @MainActor func testHTTPPaintingMatchesPreparedSamplesAcrossToolsModesAndDepths() async throws {
    let helper = AutomationTests()
    try await helper.withService(brushes: BrushLibrary(), pressedMouseButtons: { 0 }) { service, shared in
      let store = shared.store
      for (mode, depth) in self.contexts { for tool in PaintTool.allCases {
        var original = try self.document(mode, depth: depth)
        original.selection = .init(x: 3, y: 2, width: 6, height: 4)
        original.patterns = [try RasterPattern(name: "White", surface: Surface(width: 2, height: 2, fill: .white))]
        store.session = EditorSession(document: original); try service.share(shared)
        var p: [String: Any] = ["tool": tool.rawValue, "points": [["x": 4, "y": 4], ["x": 7, "y": 4]],
          "brush": ["size": 3, "hardness": 1, "color": ["r": 1, "g": 1, "b": 1, "a": 1], "settings": ["seed": 9, "pressureSize": false]]]
        if tool == .magicEraser { p["points"] = [["x": 4, "y": 4]] }
        if tool == .colorReplacement { p["options"] = ["replacementMode": BlendMode.luminosity.rawValue] }
        if tool == .mixerBrush { p["options"] = ["wet": 0, "mix": 0, "load": 1]; store.mixerPaint.load(.white) }
        if tool == .patternStamp { p["patternID"] = original.patterns![0].id }
        let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "paint.tool", "revision": "preview", "parameters": p]))
        let expected = try PaintingPreparation.prepare(command.paintingRequest(store: store), in: original)
        let status = try await helper.edit(service, shared, "paint.tool", p)
        XCTAssertEqual(status, 200, "\(mode)/\(depth)/\(tool)")
        XCTAssertTrue(store.document == expected.result); XCTAssertEqual(store.session.undoStack.count, 1)
        XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)) == expected.result)
        let stale = try await helper.edit(service, shared, "paint.tool", p, revision: "stale"); XCTAssertEqual(stale, 409)
        let undone = try await helper.edit(service, shared, "history.undo"); XCTAssertEqual(undone, 200); XCTAssertTrue(store.document == original)
        let redone = try await helper.edit(service, shared, "history.redo"); XCTAssertEqual(redone, 200); XCTAssertTrue(store.document == expected.result)
      } }
    }
    XCTAssertNotNil(PaintingAPI.capabilities["modeStorage"])
  }
}
