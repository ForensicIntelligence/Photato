import AppKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class ActionDuplicationTests: XCTestCase {
  func action(name: String = "Owned action") -> RecordedAction {
    RecordedAction(name: name, set: "Owned tests", steps: [
      .init(name: "Fill", operation: .fill(.active, .black)),
      .init(name: "Opacity", operation: .opacity(.active, 0.5)),
      .init(name: "Unavailable", operation: .unsupported("Owned unsupported command"), enabled: false)])
  }
  func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return try encoder.encode(value)
  }
  @MainActor func testCopiesIDsPayloadOrderAndIndependentEditsWithoutChangingSource() throws {
    let library = ActionLibrary(), source = action(), tail = action(name: "Tail")
    try library.save(source); try library.save(tail)
    let original = try library.exportFile(source.id), revision = library.revision
    let copy = try library.duplicate(source.id)
    XCTAssertEqual(library.file.actions.map(\.id), [source.id,copy.id,tail.id])
    XCTAssertNotEqual(copy.id, source.id); XCTAssertEqual(copy.name, "Owned action copy")
    XCTAssertEqual(copy.set, source.set); XCTAssertEqual(copy.steps.map(\.name), source.steps.map(\.name))
    XCTAssertEqual(copy.steps.map(\.enabled), source.steps.map(\.enabled))
    XCTAssertTrue(Set(copy.steps.map(\.id)).isDisjoint(with: source.steps.map(\.id)))
    for (a,b) in zip(copy.steps,source.steps) { XCTAssertEqual(try encoded(a.operation), try encoded(b.operation)) }
    XCTAssertEqual(try library.exportFile(source.id), original); XCTAssertEqual(library.revision, revision + 1)
    var edited = copy; edited.steps[0].enabled = false; edited.steps.swapAt(0,1); edited.name = "Edited copy"
    try library.save(edited)
    XCTAssertEqual(try library.exportFile(source.id), original)
    try library.remove(copy.id); XCTAssertEqual(try library.exportFile(source.id), original)
  }
  @MainActor func testDefaultNamingCollisionsUnicodeAndExplicitOverridesAreBounded() throws {
    let library = ActionLibrary(), source = action(); try library.save(source)
    let first = try library.duplicate(source.id), second = try library.duplicate(source.id)
    XCTAssertEqual(first.name, "Owned action copy"); XCTAssertEqual(second.name, "Owned action copy 2")
    let named = try library.duplicate(source.id, name: "Explicit", set: "Another set")
    XCTAssertEqual(named.name, "Explicit"); XCTAssertEqual(named.set, "Another set")
    let unicode = action(name: String(repeating: "🥔", count: 64)); try library.save(unicode)
    let unicodeCopy = try library.duplicate(unicode.id)
    XCTAssertLessThanOrEqual(unicodeCopy.name.utf8.count, 256); XCTAssertTrue(unicodeCopy.name.hasSuffix(" copy"))
    XCTAssertFalse(unicodeCopy.name.contains("�")); XCTAssertNoThrow(try unicodeCopy.validate())
    let before = try library.exportFile(), revision = library.revision
    for invalid in ["", "   ", String(repeating: "x", count: 257)] {
      XCTAssertThrowsError(try library.duplicate(source.id, name: invalid))
      XCTAssertEqual(try library.exportFile(), before); XCTAssertEqual(library.revision, revision)
    }
  }
  @MainActor func testCurrentVersionPersistenceReopenExportImportPreserveBothActions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Actions.photatoactions"), library = ActionLibrary(persistenceURL: url)
    let source = action(); try library.save(source)
    try library.update { $0.version = ActionLibraryFile.maximumVersion }
    let copy = try library.duplicate(source.id)
    let restored = ActionLibrary(persistenceURL: url)
    XCTAssertNil(restored.loadError); XCTAssertEqual(restored.file.version, 46)
    XCTAssertEqual(try encoded(restored.action(source.id)), try encoded(source))
    XCTAssertEqual(try encoded(restored.action(copy.id)), try encoded(copy))
    let exported = try restored.exportFile(copy.id), decoded = try ActionLibraryFile.decode(exported)
    XCTAssertEqual(decoded.version, 46); XCTAssertEqual(decoded.actions.count, 1)
    XCTAssertEqual(try encoded(decoded.actions[0]), try encoded(copy))
    let imported = ActionLibrary(); try imported.importFile(exported)
    XCTAssertEqual(imported.file.actions.count, 1); XCTAssertNotEqual(imported.file.actions[0].id, copy.id)
    XCTAssertEqual(try encoded(imported.file.actions[0].steps), try encoded(copy.steps))
  }
  @MainActor func testFullCorruptAndFailedWriteKeepPriorMemoryRevisionAndDisk() throws {
    let full = ActionLibrary(), source = action()
    try full.update { $0.actions = [source] + (1..<128).map { action(name: "Owned \($0)") } }
    let before = try full.exportFile(), revision = full.revision
    XCTAssertThrowsError(try full.duplicate(source.id)); XCTAssertEqual(try full.exportFile(), before)
    XCTAssertEqual(full.revision, revision)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("live"), url = folder.appendingPathComponent("Actions.photatoactions")
    let saved = ActionLibrary(persistenceURL: url); try saved.save(source)
    let disk = try Data(contentsOf: url), memory = try saved.exportFile(), savedRevision = saved.revision
    let retained = root.appendingPathComponent("retained"); try FileManager.default.moveItem(at: folder, to: retained)
    let sentinel = Data("owned write blocker".utf8); try sentinel.write(to: folder)
    XCTAssertThrowsError(try saved.duplicate(source.id))
    XCTAssertEqual(try saved.exportFile(), memory); XCTAssertEqual(saved.revision, savedRevision)
    XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("Actions.photatoactions")), disk)
    XCTAssertEqual(try Data(contentsOf: folder), sentinel)
    let brokenURL = root.appendingPathComponent("broken"), corrupt = Data("owned invalid library".utf8)
    try corrupt.write(to: brokenURL); let broken = ActionLibrary(persistenceURL: brokenURL)
    XCTAssertNotNil(broken.loadError); XCTAssertThrowsError(try broken.duplicate(source.id))
    XCTAssertEqual(try Data(contentsOf: brokenURL), corrupt)
  }
  @MainActor func testDesktopGuardsAndComponentContextDoNotEditPixelsDirtyHistoryOrRecording() throws {
    let library = ActionLibrary(), source = action(); try library.save(source)
    let original = try CraftDocument(width: 7, height: 5), s = EditorStore(document: original, actions: library)
    defer { s.renderTask?.cancel() }
    try s.selectEditingChannel(.red); XCTAssertTrue(s.canDuplicateAction)
    _ = try s.duplicateAction(source.id); XCTAssertEqual(s.componentTarget, .red)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    try s.selectEditingChannel(.composite); try s.startRecordingAction(name: "Owned recording", set: "Owned tests")
    let before = try library.exportFile(), revision = library.revision
    XCTAssertFalse(s.canDuplicateAction); XCTAssertThrowsError(try s.duplicateAction(source.id))
    XCTAssertEqual(try library.exportFile(), before); XCTAssertEqual(library.revision, revision)
    XCTAssertNotNil(s.session.actionRecording); _ = try s.stopRecordingAction(save: false)
    s.geometryBusy = true; XCTAssertFalse(s.canDuplicateAction); XCTAssertThrowsError(try s.duplicateAction(source.id))
    s.geometryBusy = false; XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testDuplicateAndSourcePlaybackProduceIdenticalNativeBytesAndOneUndo() async throws {
    let library = ActionLibrary(), source = action(); try library.save(source)
    let original = try CraftDocument(width: 8, height: 6), s = EditorStore(document: original, actions: library)
    defer { s.geometryTask?.cancel(); s.renderTask?.cancel() }
    let copy = try s.duplicateAction(source.id)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.playAction(source); await s.geometryTask?.value; XCTAssertNil(s.error)
    let expected = s.document, native = try NativeArchive.encode(expected)
    XCTAssertEqual(s.session.undoStack.count, 1); await s.undo(); XCTAssertEqual(s.document, original)
    s.playAction(copy); await s.geometryTask?.value; XCTAssertNil(s.error)
    XCTAssertEqual(s.document, expected); XCTAssertEqual(try NativeArchive.encode(s.document), native)
    XCTAssertEqual(s.session.undoStack.count, 1); await s.undo(); XCTAssertEqual(s.document, original)
  }
  @MainActor func testHTTPDuplicateResultSchemaIndependentEditsAndNativeEquivalentPayloads() async throws {
    let library = ActionLibrary(), source = action(), helper = AutomationTests(); try library.save(source)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let share = try XCTUnwrap(service.shares.first)
      let original = document.store.document, originalAction = try library.exportFile(source.id)
      let revision = service.revision(document.store)
      let response = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: [
        "command":"actions.manage", "revision":revision,
        "parameters":["operation":"duplicate", "actionID":source.id.uuidString, "name":"API copy", "set":"Copied"]])
      XCTAssertEqual(response.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual(Set(body.keys), ["state","revision","sourceActionID","action"])
      XCTAssertEqual(body["sourceActionID"] as? String, source.id.uuidString)
      let info = try XCTUnwrap(body["action"] as? [String: Any]), id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(info["id"] as? String)))
      let copy = try library.action(id); XCTAssertNotEqual(id, source.id)
      XCTAssertEqual(copy.name, "API copy"); XCTAssertEqual(copy.set, "Copied")
      XCTAssertEqual(info["name"] as? String, copy.name); XCTAssertNotEqual(service.revision(document.store), revision)
      let native = try document.store.duplicateAction(source.id, name: "Native copy", set: "Copied")
      for (a,b) in zip(copy.steps,native.steps) { XCTAssertEqual(try self.encoded(a.operation), try self.encoded(b.operation)); XCTAssertNotEqual(a.id,b.id) }
      let disabled = try await helper.edit(service, document, "actions.manage", ["operation":"step.enable", "actionID":id.uuidString, "stepID":copy.steps[0].id.uuidString, "enabled":false])
      XCTAssertEqual(disabled, 200); XCTAssertFalse(try library.action(id).steps[0].enabled)
      let moved = try await helper.edit(service, document, "actions.manage", ["operation":"step.move", "actionID":id.uuidString, "stepID":copy.steps[0].id.uuidString, "index":1])
      XCTAssertEqual(moved, 200); XCTAssertEqual(try library.action(id).steps[1].id, copy.steps[0].id)
      XCTAssertEqual(try library.exportFile(source.id), originalAction)
      XCTAssertEqual(document.store.document, original); XCTAssertFalse(document.isDocumentEdited)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let state = service.state(share, document: document), actions = try XCTUnwrap(state["actions"] as? [String: Any])
      XCTAssertEqual(actions["canDuplicate"] as? Bool, true)
      XCTAssertTrue(JSONSerialization.isValidJSONObject(ActionDuplicationAPI.capabilities))
      XCTAssertTrue(JSONSerialization.isValidJSONObject(ActionDuplicationAPI.resultSchema))
      XCTAssertTrue(AutomationCommand.actionOperations.contains("duplicate"))
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testHTTPInvalidMissingBusyStaleAndRecordingRequestsAreAtomic() async throws {
    let library = ActionLibrary(), source = action(), helper = AutomationTests(); try library.save(source)
    try await helper.withService(actions: library, pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let before = try library.exportFile(), revision = library.revision, original = document.store.document
      for parameters: [String: Any] in [
        ["operation":"duplicate"], ["operation":"duplicate", "actionID":"invalid"],
        ["operation":"duplicate", "actionID":source.id.uuidString, "stepID":source.steps[0].id.uuidString],
        ["operation":"duplicate", "actionID":source.id.uuidString, "name":17]] {
        let result = try await helper.edit(service, document, "actions.manage", parameters); XCTAssertEqual(result, 400)
      }
      let missing = try await helper.edit(service, document, "actions.manage", ["operation":"duplicate", "actionID":UUID().uuidString])
      XCTAssertEqual(missing, 422)
      let stale = try await helper.edit(service, document, "actions.manage", ["operation":"duplicate", "actionID":source.id.uuidString], revision:"stale")
      XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "actions.manage", ["operation":"duplicate", "actionID":source.id.uuidString])
      XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      try document.store.startRecordingAction(name:"Owned", set:"Tests")
      let recording = try await helper.edit(service, document, "actions.manage", ["operation":"duplicate", "actionID":source.id.uuidString])
      XCTAssertEqual(recording, 409); XCTAssertNotNil(document.store.session.actionRecording)
      _ = try document.store.stopRecordingAction(save:false)
      XCTAssertEqual(try library.exportFile(), before); XCTAssertEqual(library.revision, revision)
      XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
