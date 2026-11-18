import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class ToolRecordingPreferenceTests: XCTestCase {
  private func source() throws -> CraftDocument {
    var document = try CraftDocument(width: 16, height: 12)
    document.layers[0].content = .raster(try Surface(width: 16, height: 12, fill: .white))
    return document
  }

  @MainActor func testPreferencePersistsAndOpenRecordingsKeepTheirStartSetting() throws {
    let suite = "Photato.ToolRecording.Tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let library = ActionLibrary(defaults: defaults)
    let first = EditorStore(document: try source(), actions: library)
    let second = EditorStore(document: try source(), actions: library)
    XCTAssertFalse(library.allowToolRecording)
    XCTAssertEqual(first.actionState["allowToolRecording"] as? Bool, false)
    try first.startRecordingAction(name: "First", set: "Tests")
    XCTAssertEqual(first.actionState["recordingAllowsTools"] as? Bool, false)
    XCTAssertThrowsError(try first.setAllowToolRecording(true))

    let revision = library.revision
    try second.setAllowToolRecording(true)
    XCTAssertEqual(library.revision, revision + 1)
    try second.setAllowToolRecording(true)
    XCTAssertEqual(library.revision, revision + 1)
    XCTAssertEqual(first.actionState["allowToolRecording"] as? Bool, true)
    XCTAssertEqual(first.actionState["recordingAllowsTools"] as? Bool, false)
    XCTAssertTrue(ActionLibrary(defaults: defaults).allowToolRecording)
    XCTAssertTrue(library.file.actions.isEmpty)
    XCTAssertTrue(first.session.undoStack.isEmpty)
    _ = try first.stopRecordingAction(save: false)
    try first.startRecordingAction(name: "Next", set: "Tests")
    XCTAssertEqual(first.actionState["recordingAllowsTools"] as? Bool, true)
    _ = try first.stopRecordingAction(save: false)
    try second.setAllowToolRecording(false)
    XCTAssertFalse(ActionLibrary(defaults: defaults).allowToolRecording)
  }

  @MainActor func testDesktopBrushEditsAndUndoesWhenOffAndSavedStrokePlaysWhenOff() async throws {
    let original = try source(), library = ActionLibrary()
    let store = EditorStore(document: original, actions: library)
    defer { store.renderTask?.cancel() }
    let id = try XCTUnwrap(original.activeLayerID)
    store.tool = .brush
    store.brush.size = 5
    store.brush.color = .black
    func paint() async {
      store.beginBrush(.init(x: 6.5, y: 5.5), zoom: 1)
      store.extendBrush(.init(x: 10.5, y: 5.5))
      store.finishBrush()
      await store.geometryTask?.value
    }

    try store.startRecordingAction(name: "Skip brush", set: "Tests")
    await paint()
    let painted = store.document
    XCTAssertNotEqual(painted, original)
    XCTAssertTrue(try XCTUnwrap(store.session.actionRecording?.snapshot).steps.isEmpty)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo()
    XCTAssertEqual(store.document, original)
    await store.redo()
    XCTAssertEqual(store.document, painted)
    try store.session.execute(.opacity(id, 0.5))
    let structural = try store.stopRecordingAction()
    XCTAssertEqual(structural.steps.count, 1)
    guard case .opacity = structural.steps.first?.operation else { return XCTFail("Expected the layer opacity step") }

    store.session = EditorSession(document: original)
    try store.setAllowToolRecording(true)
    try store.startRecordingAction(name: "Capture brush", set: "Tests")
    await paint()
    let captured = try store.stopRecordingAction()
    let expected = store.document
    XCTAssertEqual(expected, painted)
    XCTAssertEqual(captured.steps.count, 1)
    guard case .stroke = captured.steps.first?.operation else { return XCTFail("Expected the captured Brush step") }
    let saved = try XCTUnwrap(ActionLibraryFile.decode(library.exportFile(captured.id)).actions.first)
    store.session = EditorSession(document: original)
    try store.setAllowToolRecording(false)
    store.playAction(saved)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document, expected)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testHTTPPreferenceValidationAndProcessStrokeRecording() async throws {
    let helper = AutomationTests(), library = ActionLibrary()
    let original = try ModePaintingWorkflowTests().document(.rgb, depth: .u16)
    let id = try XCTUnwrap(original.activeLayerID)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, file in
      let store = file.store
      store.session = EditorSession(document: original)
      try service.share(file)
      let selected = try await helper.edit(service, file, "mode.channel.select", ["components": [0, 2]])
      XCTAssertEqual(selected, 200)
      let preference: [String: Any] = ["operation": "toolRecording", "enabled": true]
      let stroke: [String: Any] = ["action": "stroke", "layerID": id.uuidString, "components": [0, 2],
        "points": [["x": 6.5, "y": 4.5]], "brush": ["size": 3]]
      let malformed = try await helper.edit(service, file, "actions.manage", ["operation": "toolRecording", "enabled": "true"])
      XCTAssertEqual(malformed, 400)

      let start = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "Off"])
      let changeDuringRecord = try await helper.edit(service, file, "actions.manage", preference)
      let paint = try await helper.edit(service, file, "mode.channel.edit", stroke)
      let stop = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
      XCTAssertEqual([start, changeDuringRecord, paint, stop], [200, 409, 200, 200])
      XCTAssertEqual(library.file.actions.first?.steps.count, 0)
      let painted = store.document
      XCTAssertNotEqual(painted, original)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()
      XCTAssertEqual(store.document, original)

      let previous = service.revision(store)
      let configured = try await helper.edit(service, file, "actions.manage", preference)
      let stale = try await helper.edit(service, file, "actions.manage", ["operation": "toolRecording", "enabled": false], revision: previous)
      XCTAssertEqual([configured, stale], [200, 409])
      XCTAssertTrue(library.allowToolRecording)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      let record = try await helper.edit(service, file, "actions.manage", ["operation": "record", "name": "On"])
      let captured = try await helper.edit(service, file, "mode.channel.edit", stroke)
      let end = try await helper.edit(service, file, "actions.manage", ["operation": "stop"])
      XCTAssertEqual([record, captured, end], [200, 200, 200])
      XCTAssertEqual(store.document, painted)
      let action = try XCTUnwrap(library.file.actions.last)
      guard case .colorChannelBrushStroke = action.steps.first?.operation else { return XCTFail("Expected a process stroke") }
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "actions.manage" })
      let schema = try JSONSerialization.data(withJSONObject: definition.schema)
      XCTAssertTrue(String(decoding: schema, as: UTF8.self).contains("toolRecording"))
    }
  }
}
