import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RetouchAutomationTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 64, height: 48)
    var pixels = try Surface(width: 64, height: 48)
    pixels.mapPixels { x, y, _ in Pixel(Float(x % 11) / 12 + 0.05, Float(y % 9) / 10 + 0.1, Float((x + y) % 7) / 8 + 0.1) }
    d.layers[0].content = .raster(pixels); return d
  }
  @MainActor func testNativeNineToolRecordingSerializationPlaybackAndHistory() async throws {
    let tools: [EditorTool] = [.cloneStamp, .healingBrush, .spotHealing, .dodge, .burn, .sponge, .blur, .sharpen, .smudge]
    for tool in tools {
      let original = try fixture(), library = ActionLibrary(), state = CloneSources()
      let store = EditorStore(document: original, cloneState: state, actions: library)
      defer { store.cancelClone(); store.renderTask?.cancel() }
      store.tool = tool; store.retouchSettings.brush.size = 6; store.retouchSettings.focus.protectDetail = false
      store.setCloneSource(at: .init(8, 9))
      try store.startRecordingAction(name: "Retouch", set: "Tests")
      store.beginClone(.init(x: 24, y: 20)); await store.clonePrepareTask?.value
      store.extendClone(.init(x: 34, y: 24)); store.finishClone(); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertNotEqual(store.document, original)
      let action = try store.stopRecordingAction(); XCTAssertEqual(action.steps.count, 1)
      guard case .retouch = action.steps.first?.operation else { return XCTFail("\(tool) is not semantic") }
      let bytes = try library.exportFile(action.id), decoded = try ActionLibraryFile.decode(bytes)
      XCTAssertEqual(decoded.version, 21); XCTAssertLessThan(bytes.count, 6500)
      var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); raw["version"] = 20
      XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: raw)))
      let result = store.document
      await store.undo(); XCTAssertTrue(store.document == original)
      store.playAction(decoded.actions[0]); await store.geometryTask?.value
      XCTAssertNil(store.error); XCTAssertTrue(store.document == result); XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertTrue(store.document == original)
      await store.redo(); XCTAssertTrue(store.document == result)
    }
  }
  @MainActor func testHTTPNineToolsMatchNativeAndRecordSemanticActions() async throws {
    let helper = AutomationTests(), library = ActionLibrary()
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      let store = document.store
      try service.share(document)
      for tool in RecordedRetouchTool.allCases {
        let original = try self.fixture(); store.session = EditorSession(document: original)
        var parameters: [String: Any] = ["tool": tool.rawValue, "points": [["x": 24, "y": 20], ["x": 34, "y": 24]],
          "brush": ["size": 6, "hardness": 0.8, "opacity": 1, "flow": 1, "spacing": 0.25, "pressureSize": true, "pressureOpacity": false, "mode": BlendMode.normal.rawValue]]
        if tool == .cloneStamp || tool == .healingBrush { parameters["mapping"] = ["source": ["x": 8, "y": 9]]; parameters["sampling"] = CloneSampling.current.rawValue; parameters["ignoreAdjustments"] = false }
        if tool == .spotHealing { parameters["sampling"] = CloneSampling.current.rawValue; parameters["spotType"] = SpotHealingType.proximityMatch.rawValue }
        if tool.focus != nil { parameters["focus"] = ["strength": 0.5, "protectDetail": false, "sampleAllLayers": false, "fingerPainting": false] }
        if tool.toning != nil { parameters["toning"] = ["exposure": 0.5, "range": RetouchToneRange.midtones.rawValue, "protectTones": true, "spongeMode": SpongeMode.desaturate.rawValue, "vibrance": true] }
        var request = RecordedRetouchStroke(tool: tool, target: .active,
          points: [.init(x: 24, y: 20), .init(x: 34, y: 24)])
        request.brush.size = 6; request.focus.protectDetail = false; request.spotType = .proximityMatch
        request.mapping = .init(source: .init(8, 9), anchor: .init(24, 20))
        if tool.toning == nil { request.source = .init(layer: .active, convertToTarget: tool == .cloneStamp || tool == .healingBrush) }
        var expected = original; try RetouchPreparation.command(request, in: original).apply(to: &expected)
        try store.startRecordingAction(name: tool.rawValue, set: "Tests")
        let status = try await helper.edit(service, document, "retouch.stroke", parameters); XCTAssertEqual(status, 200, "\(tool)")
        XCTAssertTrue(store.document == expected); XCTAssertEqual(store.session.undoStack.count, 1)
        let action = try store.stopRecordingAction(); XCTAssertEqual(action.steps.count, 1); XCTAssertNil(action.steps[0].operation.unsupportedReason)
        let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertTrue(store.document == original)
        let play = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString]); XCTAssertEqual(play, 200); XCTAssertTrue(store.document == expected)
      }
    }
  }
  @MainActor func testHTTPExternalSourcesAreExplicitAndRevisionCheckedForStrokeAndAction() async throws {
    let helper = AutomationTests(), library = ActionLibrary()
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      let original = try self.fixture(); document.store.session = EditorSession(document: original)
      var inputModel = try self.fixture(); inputModel.name = "External retouch source"
      let input = CraftNSDocument(model: inputModel)
      service.controller.addDocument(input)
      defer { input.store.renderTask?.cancel(); service.controller.removeDocument(input) }
      try service.share(document); try service.share(input)
      let sourceShare = try XCTUnwrap(service.shares.first { $0.document === input })
      var parameters: [String: Any] = ["tool": "cloneStamp", "points": [["x": 24, "y": 20], ["x": 34, "y": 24]],
        "brush": ["size": 6], "mapping": ["source": ["x": 8, "y": 9]],
        "source": ["id": sourceShare.id.uuidString, "revision": "stale"]]
      let stale = try await helper.edit(service, document, "retouch.stroke", parameters); XCTAssertEqual(stale, 409)
      XCTAssertTrue(document.store.document == original)
      parameters["source"] = ["id": sourceShare.id.uuidString, "revision": service.revision(input.store)]
      try document.store.startRecordingAction(name: "External", set: "Tests")
      let accepted = try await helper.edit(service, document, "retouch.stroke", parameters); XCTAssertEqual(accepted, 200)
      let result = document.store.document, action = try document.store.stopRecordingAction()
      XCTAssertTrue(action.usesExternalRetouchSources)
      await document.store.undo(); XCTAssertTrue(document.store.document == original)
      let missing = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString]); XCTAssertEqual(missing, 422)
      XCTAssertTrue(document.store.document == original)
      let play = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString,
        "sources": [["id": sourceShare.id.uuidString, "revision": service.revision(input.store)]]])
      XCTAssertEqual(play, 200); XCTAssertTrue(document.store.document == result)
      await document.store.undo()
      service.revoke(sourceShare.id)
      let revoked = try await helper.edit(service, document, "retouch.stroke", parameters); XCTAssertEqual(revoked, 400)
      XCTAssertTrue(document.store.document == original)
    }
  }
  @MainActor func testHTTPInvalidStaleBusyAndMaskInputsAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store; var original = try self.fixture()
      original.layers[0].mask = try Surface(width: 64, height: 48, fill: Pixel(0.4, 0.4, 0.4))
      store.session = EditorSession(document: original); try service.share(document)
      let valid: [String: Any] = ["tool": "dodge", "points": [["x": 24, "y": 20]], "brush": ["size": 6]]
      for patch: [String: Any] in [["points": []], ["brush": ["size": 0]], ["tool": "invented"], ["focus": ["strength": 0.2]], ["source": ["id": UUID().uuidString, "revision": "0"]], ["points": [["x": 2, "y": 3, "invented": true]]]] {
        var p = valid; p.merge(patch) { _, b in b }
        let status = try await helper.edit(service, document, "retouch.stroke", p); XCTAssertEqual(status, 400)
        XCTAssertTrue(store.document == original); XCTAssertTrue(store.session.undoStack.isEmpty)
      }
      let stale = try await helper.edit(service, document, "retouch.stroke", valid, revision: "stale"); XCTAssertEqual(stale, 409)
      let missingCoordinates = try await helper.edit(service, document, "retouch.stroke",
        ["tool": "cloneStamp", "points": [["x": 24, "y": 20]], "mapping": ["source": [:]]])
      XCTAssertEqual(missingCoordinates, 400); XCTAssertTrue(store.document == original)
      store.tool = .dodge; store.beginClone(.init(x: 20, y: 20))
      let busy = try await helper.edit(service, document, "retouch.stroke", valid); XCTAssertEqual(busy, 409); store.cancelClone()
      var mask = valid; mask["target"] = "layerMask"
      let status = try await helper.edit(service, document, "retouch.stroke", mask); XCTAssertEqual(status, 200)
      XCTAssertEqual(store.document.layers[0].content, original.layers[0].content); XCTAssertNotEqual(store.document.layers[0].mask, original.layers[0].mask)
    }
  }
  @MainActor func testHTTPInFlightSourceChangeRevocationAndCancellationRejectCommit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var original = try CraftDocument(width: 256, height: 256)
      var pixels = try Surface(width: 256, height: 256)
      pixels.mapPixels { x, y, _ in Pixel(Float(x % 19) / 20, Float(y % 17) / 18, Float((x + y) % 13) / 14) }
      original.layers[0].content = .raster(pixels)
      var sourceModel = original; sourceModel.id = UUID(); sourceModel.name = "In-flight source"
      let input = CraftNSDocument(model: sourceModel); service.controller.addDocument(input)
      defer { input.store.renderTask?.cancel(); service.controller.removeDocument(input) }
      for interruption in ["sourceChange", "sourceRevoke", "cancel"] {
        document.store.session = EditorSession(document: original)
        input.store.session = EditorSession(document: sourceModel)
        try service.share(document); try service.share(input)
        let source = try XCTUnwrap(service.shares.first { $0.document === input })
        let parameters: [String: Any] = ["tool": "healingBrush", "points": [["x": 100, "y": 100], ["x": 160, "y": 160]],
          "brush": ["size": 96], "mapping": ["source": ["x": 40, "y": 40]],
          "source": ["id": source.id.uuidString, "revision": service.revision(input.store)]]
        let task = Task { @MainActor in try await helper.edit(service, document, "retouch.stroke", parameters) }
        for _ in 0..<1000 where !document.store.geometryBusy { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(document.store.geometryBusy, "The owned healing workload must still be preparing")
        if interruption == "sourceChange" { input.store.perform(.opacity(sourceModel.layers[0].id, 0.7)) }
        else if interruption == "sourceRevoke" { service.revoke(source.id) }
        else { document.store.geometryTask?.cancel() }
        let status = try await task.value; XCTAssertNotEqual(status, 200, interruption)
        XCTAssertTrue(document.store.document == original, interruption)
        XCTAssertTrue(document.store.session.undoStack.isEmpty)
        XCTAssertFalse(document.store.geometryBusy)
      }
    }
  }
}
