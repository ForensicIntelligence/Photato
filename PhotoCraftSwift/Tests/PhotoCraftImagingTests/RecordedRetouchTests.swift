import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RecordedRetouchTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8, mask: Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width: 48, height: 40, depth: depth)
    var p = try Surface(width: 64, height: 64, depth: depth)
    p.mapPixels { x, y, _ in Pixel(Float(x % 11) / 12 + 0.05, Float(y % 9) / 10 + 0.1, Float((x + y) % 7) / 8 + 0.1) }
    d.layers[0].name = "Retouch"; d.layers[0].content = .raster(p)
    d.layers[0].x = -6; d.layers[0].y = -5; d.layers[0].affine = .rotation(3)
    if mask { d.layers[0].mask = p }
    d.selection = .init(x: 5, y: 6, width: 34, height: 27)
    return d
  }
  func request(_ tool: RecordedRetouchTool, mask: Bool = false) -> RecordedRetouchStroke {
    var r = RecordedRetouchStroke(tool: tool, target: .active,
      points: [.init(x: 16, y: 19, pressure: 0.6), .init(x: 21, y: 20), .init(x: 29, y: 24)])
    r.brush.size = 6; r.brush.spacing = 0.2; r.mask = mask; r.focus.protectDetail = false
    r.mapping = .init(source: .init(8, 9), anchor: .init(16, 19))
    if tool.toning == nil { r.source = .init(layer: .active, mask: mask, convertToTarget: tool == .cloneStamp || tool == .healingBrush) }
    return r
  }
  func testNineToolsRecordResampleAndReplayExactNativePixelsAcrossDepthsAndMasks() throws {
    for depth in PixelDepth.allCases { for mask in [false, true] { for tool in RecordedRetouchTool.allCases {
      let d = try fixture(depth, mask: mask), r = request(tool, mask: mask)
      let command = try RetouchPreparation.command(r, in: d)
      let operation = ActionOperation(recording: command, in: d)
      XCTAssertNil(operation.unsupportedReason, "\(tool)")
      let action = RecordedAction(name: "Retouch", steps: [.init(name: command.label, operation: operation)])
      let bytes = try JSONEncoder().encode(action)
      XCTAssertLessThan(bytes.count, 5000); XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("surface"))
      let restored = try JSONDecoder().decode(RecordedAction.self, from: bytes)
      var expected = d; try command.apply(to: &expected)
      var session = EditorSession(document: d)
      try session.execute(RecordedActionRenderer.prepare(restored, in: d).command)
      XCTAssertTrue(session.document == expected, "\(tool),\(depth),mask\(mask)")
      if expected != d { XCTAssertEqual(session.undoStack.count, 1); try session.undo(); XCTAssertTrue(session.document == d); try session.redo(); XCTAssertTrue(session.document == expected) }
      var other = d; other.id = UUID(); other.layers[0].id = UUID(); other.activeLayerID = other.layers[0].id
      if case .raster(var p) = other.layers[0].content { p.mapPixels { _, _, c in Pixel(c.b, c.r, c.g, c.a) }; other.layers[0].content = .raster(p) }
      var dynamicExpected = other; try RetouchPreparation.command(r, in: other).apply(to: &dynamicExpected)
      var dynamicResult = other; try RecordedActionRenderer.prepare(restored, in: other).command.apply(to: &dynamicResult)
      XCTAssertTrue(dynamicResult == dynamicExpected, "Replay must sample the playback document")
    } } }
  }
  func testAllLayerSamplingHealingContextAndExternalSourceBindings() throws {
    var d = try fixture(); let id = try XCTUnwrap(d.activeLayerID)
    d.layers.append(Layer(name: "Overlay", content: .raster(try Surface(width: 48, height: 40, fill: Pixel(0.7, 0.2, 0.4, 0.25)))))
    for tool in [RecordedRetouchTool.cloneStamp, .healingBrush, .spotHealing, .blur, .sharpen, .smudge] {
      var r = request(tool); r.source?.sampling = .all
      if tool.focus != nil { r.focus.sampleAllLayers = true }
      if tool == .healingBrush { r.destination = .init(layer: .active, sampling: .all) }
      let c = try RetouchPreparation.command(r, in: d)
      let action = RecordedAction(name: "All", steps: [.init(name: c.label, operation: .init(recording: c, in: d))])
      var a = d; try c.apply(to: &a); var b = d; try RecordedActionRenderer.prepare(action, in: d).command.apply(to: &b)
      XCTAssertTrue(a == b); XCTAssertEqual(b.activeLayerID, id)
    }
    var external = try fixture(.u16); external.name = "Sample source"
    var r = request(.cloneStamp)
    r.source = .init(layer: .named("Retouch", occurrence: 0), convertToTarget: true, documentID: external.id, documentName: external.name)
    let c = try RetouchPreparation.command(r, in: d, sources: [external])
    let action = RecordedAction(name: "External", steps: [.init(name: c.label, operation: .init(recording: c, in: d))])
    XCTAssertTrue(action.usesExternalRetouchSources)
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(action, in: d))
    var reopened = external; reopened.id = UUID()
    var expected = d; try c.apply(to: &expected)
    var result = d; try RecordedActionRenderer.prepare(action, in: d, masters: [reopened]).command.apply(to: &result)
    XCTAssertTrue(result == expected)
    var duplicate = reopened; duplicate.id = UUID()
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(action, in: d, masters: [reopened, duplicate]))
  }
  func testInvalidLockedCancelledAndLateActionFailuresStayAtomic() async throws {
    let d = try fixture(); var r = request(.cloneStamp)
    r.points = []; XCTAssertThrowsError(try r.validate())
    r = request(.burn); r.brush.mode = .multiply; XCTAssertThrowsError(try r.validate())
    r = request(.cloneStamp); r.source?.mask = true; XCTAssertThrowsError(try r.validate())
    let valid = request(.dodge)
    var locked = d; locked.layers[0].locked = true
    let action = RecordedAction(name: "Retouch", steps: [.init(name: "Dodge", operation: .retouch(valid))])
    XCTAssertThrowsError(try RecordedActionRenderer.prepare(action, in: locked))
    var failed = action; failed.steps.append(.init(name: "Missing", operation: .select(.named("Missing", occurrence: 0))))
    var result = d; XCTAssertThrowsError(try RecordedActionRenderer.prepare(failed, in: result)); XCTAssertTrue(result == d)
    let cancelled = Task.detached { withUnsafeCurrentTask { $0?.cancel() }; return try RecordedActionRenderer.prepare(action, in: d) }
    do { _ = try await cancelled.value; XCTFail("Cancelled playback committed") } catch is CancellationError {} catch { XCTFail("\(error)") }
  }
}
