import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class ActionsWorkflowTests: XCTestCase {
  @MainActor func testNativeRecordSaveLoadEditReplayUndoAndPanel() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Actions.photatoactions"), library = ActionLibrary(persistenceURL: url)
    let d = try CraftDocument(width: 8, height: 6), store = EditorStore(document: d, actions: library)
    defer { store.renderTask?.cancel() }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    try store.startRecordingAction(name: "Paint", set: "Tests")
    store.perform(.fill(d.activeLayerID!, .black)); store.perform(.opacity(d.activeLayerID!, 0.5))
    let action = try store.stopRecordingAction(); XCTAssertEqual(action.steps.count, 2)
    let restored = ActionLibrary(persistenceURL: url); XCTAssertNil(restored.loadError)
    XCTAssertEqual(restored.file.actions.first?.name, "Paint")
    let replay = EditorStore(document: d, actions: restored); defer { replay.renderTask?.cancel() }
    replay.playAction(action); await replay.geometryTask?.value
    XCTAssertNil(replay.error); XCTAssertEqual(replay.document, store.document); XCTAssertEqual(replay.session.undoStack.count, 1)
    _ = await replay.requestHistory(redo: false).value; XCTAssertEqual(replay.document, d)
    let view = NSHostingView(rootView: ActionsPanel(store: store)); view.frame = NSRect(x: 0, y: 0, width: 420, height: 520); view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 300)
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      if let png = bitmap.representation(using: .png, properties: [:]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try png.write(to: root.appendingPathComponent("artifacts/actions-offscreen.png"))
      }
    }
    try restored.importFile(library.exportFile()); XCTAssertEqual(restored.file.actions.count, 2)
    XCTAssertNotEqual(restored.file.actions[0].id, restored.file.actions[1].id)
    try restored.remove(action.id); XCTAssertEqual(restored.file.actions.count, 1)
  }
  @MainActor func testCorruptLibraryPreservedAndFailedSaveRetainsRecording() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("broken"), invalid = Data("broken".utf8); try invalid.write(to: url)
    let broken = ActionLibrary(persistenceURL: url); XCTAssertNotNil(broken.loadError)
    XCTAssertThrowsError(try broken.save(.init(name: "Replace"))); XCTAssertEqual(try Data(contentsOf: url), invalid)
    let blocked = ActionLibrary(persistenceURL: url.appendingPathComponent("library"))
    let store = EditorStore(document: try CraftDocument(width: 2, height: 2), actions: blocked); defer { store.renderTask?.cancel() }
    try store.startRecordingAction(name: "Retained", set: "Test"); store.perform(.opacity(store.document.activeLayerID!, 0.5))
    XCTAssertThrowsError(try store.stopRecordingAction()); XCTAssertNotNil(store.session.actionRecording)
    _ = try store.stopRecordingAction(save: false); XCTAssertNil(store.session.actionRecording)
  }
  @MainActor func testAPIRecordingPlaybackStateInvalidBusyAndStale() async throws {
    let library = ActionLibrary(), helper = AutomationTests()
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let initial = service.revision(document.store)
      let start = try await helper.edit(service, document, "actions.manage", ["operation": "record", "name": "API", "set": "Tests"]); XCTAssertEqual(start, 200)
      let stale = try await helper.edit(service, document, "actions.manage", ["operation": "list"], revision: initial); XCTAssertEqual(stale, 409)
      let fill = try await helper.edit(service, document, "layer.fill", ["layerID": document.store.document.activeLayerID!.uuidString, "r": 0.2, "g": 0.3, "b": 0.8, "a": 1]); XCTAssertEqual(fill, 200)
      let stop = try await helper.edit(service, document, "actions.manage", ["operation": "stop"]); XCTAssertEqual(stop, 200)
      let action = try XCTUnwrap(library.file.actions.first); XCTAssertEqual(action.steps.count, 1)
      let expected = document.store.document
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
      let play = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString]); XCTAssertEqual(play, 200); XCTAssertEqual(document.store.document, expected)
      let bad = try await helper.edit(service, document, "actions.manage", ["operation": "step.enable", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString, "enabled": "yes"]); XCTAssertEqual(bad, 400)
      let state = document.store.actionState; XCTAssertEqual((state["library"] as? [[String: Any]])?.count, 1)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "actions.play", ["actionID": action.id.uuidString]); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let disable = try await helper.edit(service, document, "actions.manage", ["operation": "step.enable", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString, "enabled": false]); XCTAssertEqual(disable, 200)
      XCTAssertFalse(library.file.actions[0].steps[0].enabled)
      let schema = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "actions.manage" }); XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: schema.schema))
    }
  }
}
