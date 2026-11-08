import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class ScriptEventsTests: XCTestCase {
  @MainActor private func fixture() throws -> (CraftDocumentController, ScriptEventsStore, ActionLibrary, RecordedAction) {
    _ = NSApplication.shared
    let actions = ActionLibrary()
    let action = RecordedAction(name: "Owned black half-opacity", set: "Event tests", steps: [
      .init(name: "Black", operation: .fill(.active, .black)),
      .init(name: "Half", operation: .opacity(.active, 0.5))])
    try actions.save(action)
    let store = ScriptEventsStore(actions: actions)
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary(), scriptEvents: store)
    return (controller, store, actions, action)
  }
  private func folder() throws -> URL {
    let base = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.temporaryDirectory
    let url = base.appendingPathComponent("script-events-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor private func document(_ actions: ActionLibrary) throws -> CraftNSDocument {
    CraftNSDocument(model: try CraftNSDocument.blankModel(width: 4, height: 3, background: .clear), actions: actions)
  }
  @MainActor private func cleanup(_ controller: CraftDocumentController, _ documents: [CraftNSDocument]) {
    controller.scriptEventsDispatcher.cancel()
    for document in documents {
      document.store.geometryTask?.cancel(); document.store.renderTask?.cancel()
      controller.removeDocument(document)
    }
  }
  func testConfigurationRoundTripDefaultsLimitsAndMalformedVersions() throws {
    let empty = ScriptEventsConfiguration()
    XCTAssertFalse(empty.enabled); XCTAssertTrue(empty.bindings.isEmpty)
    XCTAssertEqual(try ScriptEventsConfiguration.decode(empty.encoded()), empty)
    var value = empty; value.version = 2; XCTAssertThrowsError(try value.encoded())
    value = empty; let binding = ScriptEventBinding(event: .newDocument, actionID: UUID())
    value.bindings = [binding, binding]; XCTAssertThrowsError(try value.encoded())
    value.bindings = (0...ScriptEventsConfiguration.maximumBindings).map { _ in .init(event: .newDocument, actionID: UUID()) }
    XCTAssertThrowsError(try value.encoded())
    XCTAssertThrowsError(try ScriptEventsConfiguration.decode(Data(repeating: 32, count: ScriptEventsConfiguration.maximumBytes + 1)))
    XCTAssertThrowsError(try ScriptEventsConfiguration.decode(Data("{\"version\":1,\"enabled\":true,\"bindings\":[{\"id\":\"bad\",\"event\":\"saveDocument\",\"actionID\":\"bad\"}]}".utf8)))
  }
  @MainActor func testPersistentEnableRegistrationsOrderRemoveAndReload() throws {
    let (_, _, actions, action) = try fixture()
    let url = try folder().appendingPathComponent("events.json")
    let store = ScriptEventsStore(persistenceURL: url, actions: actions)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    try store.add(event: .newDocument, actionID: action.id)
    try store.add(event: .openDocument, actionID: action.id)
    try store.setEnabled(true)
    let restored = ScriptEventsStore(persistenceURL: url, actions: actions)
    XCTAssertNil(restored.loadError); XCTAssertEqual(restored.configuration, store.configuration)
    XCTAssertEqual(restored.configuration.bindings.map(\.event), [.newDocument, .openDocument])
    try restored.remove(restored.configuration.bindings[0].id)
    XCTAssertEqual(restored.configuration.bindings.map(\.event), [.openDocument])
    try restored.setEnabled(false); XCTAssertEqual(restored.configuration.bindings.count, 1)
    try restored.remove(nil); XCTAssertTrue(restored.configuration.bindings.isEmpty)
    XCTAssertFalse(ScriptEventsStore(persistenceURL: url, actions: actions).configuration.enabled)
  }
  @MainActor func testFailedPersistenceCorruptFileAndStaleRevisionPreserveState() throws {
    let (_, _, actions, action) = try fixture(), url = try folder().appendingPathComponent("events.json")
    let broken = Data("owned corrupt event file".utf8); try broken.write(to: url)
    let corrupt = ScriptEventsStore(persistenceURL: url, actions: actions)
    XCTAssertNotNil(corrupt.loadError); XCTAssertThrowsError(try corrupt.setEnabled(true))
    XCTAssertEqual(try Data(contentsOf: url), broken)
    let blocked = ScriptEventsStore(persistenceURL: url.appendingPathComponent("blocked"), actions: actions,
      writer: { _, _ in throw CocoaError(.fileWriteNoPermission) })
    let original = blocked.configuration, revision = blocked.revision
    XCTAssertThrowsError(try blocked.add(event: .newDocument, actionID: action.id))
    XCTAssertEqual(blocked.configuration, original); XCTAssertEqual(blocked.revision, revision)
    let store = ScriptEventsStore(actions: actions), stale = store.revision
    try store.setEnabled(true)
    XCTAssertThrowsError(try store.replace(original, expectedRevision: stale))
    XCTAssertTrue(store.configuration.enabled)
  }
  @MainActor func testMissingActionsRejectedAndSavedOrphansCanBeRemoved() throws {
    let (_, store, actions, action) = try fixture()
    XCTAssertThrowsError(try store.add(event: .newDocument, actionID: UUID()))
    XCTAssertTrue(store.configuration.bindings.isEmpty)
    try store.add(event: .newDocument, actionID: action.id); try actions.remove(action.id)
    try store.setEnabled(true); XCTAssertEqual(store.configuration.bindings.count, 1)
    try store.remove(nil); XCTAssertTrue(store.configuration.bindings.isEmpty)
  }
  @MainActor func testNewDocumentRunsNativeActionWithExactOwnedPixelsAndOneUndo() async throws {
    let (controller, events, actions, action) = try fixture(), document = try document(actions)
    defer { cleanup(controller, [document]) }
    try events.add(event: .newDocument, actionID: action.id); try events.setEnabled(true)
    let before = document.store.document
    controller.addDocument(document); await controller.scriptEventsDispatcher.task?.value
    XCTAssertNil(controller.scriptEventsDispatcher.lastResult?.error)
    XCTAssertEqual(controller.scriptEventsDispatcher.lastResult?.completedActions, 1)
    XCTAssertEqual(document.store.session.undoStack.count, 1)
    XCTAssertEqual(document.store.document.layers[0].opacity, 0.5)
    if case .raster(let surface) = document.store.document.layers[0].content {
      for y in 0..<3 { for x in 0..<4 { XCTAssertEqual(surface.pixel(x: x, y: y), .black) } }
    } else { XCTFail("Expected the original raster layer") }
    XCTAssertNil(document.fileURL); XCTAssertTrue(document.isDocumentEdited)
    _ = await document.store.requestHistory(redo: false).value; XCTAssertEqual(document.store.document, before)
    _ = await document.store.requestHistory(redo: true).value
    XCTAssertEqual(document.store.document.layers[0].opacity, 0.5)
  }
  @MainActor func testOpenEventUsesNativeOpeningAndDoesNotFireWhenFocusingExistingFile() async throws {
    let (controller, events, _, action) = try fixture()
    let source = try CraftNSDocument.blankModel(width: 4, height: 3, background: .clear)
    let url = try folder().appendingPathComponent("owned.photato")
    try DocumentIO.encode(source, format: .native).write(to: url)
    try events.add(event: .openDocument, actionID: action.id); try events.setEnabled(true)
    try controller.documentOpening.begin([url], display: false)
    await controller.documentOpening.task?.value; await controller.scriptEventsDispatcher.task?.value
    let document = try XCTUnwrap(controller.document(for: url) as? CraftNSDocument)
    defer { cleanup(controller, [document]) }
    let bytes = try Data(contentsOf: url)
    XCTAssertEqual(controller.scriptEventsDispatcher.lastResult?.event, .openDocument)
    XCTAssertEqual(document.store.document.layers[0].opacity, 0.5)
    document.store.perform(.opacity(document.store.document.layers[0].id, 0.75))
    let count = document.store.session.undoStack.count
    try controller.documentOpening.begin([url], display: false)
    await controller.documentOpening.task?.value; await controller.scriptEventsDispatcher.task?.value
    XCTAssertEqual(controller.documentOpening.state?.alreadyOpen, 1)
    XCTAssertEqual(document.store.document.layers[0].opacity, 0.75)
    XCTAssertEqual(document.store.session.undoStack.count, count); XCTAssertEqual(try Data(contentsOf: url), bytes)
  }
  @MainActor func testEventActionsKeepRegistrationOrderAndSeparateUndoTransactions() async throws {
    let (controller, events, actions, _) = try fixture(), document = try document(actions)
    defer { cleanup(controller, [document]) }
    for opacity in [Float(0.25), Float(0.75)] {
      let action = RecordedAction(name: "Opacity \(opacity)", steps: [.init(name: "Opacity", operation: .opacity(.active, opacity))])
      try actions.save(action); try events.add(event: .newDocument, actionID: action.id)
    }
    try events.setEnabled(true); let before = document.store.document
    controller.addDocument(document); await controller.scriptEventsDispatcher.task?.value
    XCTAssertEqual(controller.scriptEventsDispatcher.lastResult?.completedActions, 2)
    XCTAssertEqual(document.store.document.layers[0].opacity, 0.75)
    XCTAssertEqual(document.store.session.undoStack.count, 2)
    _ = await document.store.requestHistory(redo: false).value; XCTAssertEqual(document.store.document.layers[0].opacity, 0.25)
    _ = await document.store.requestHistory(redo: false).value; XCTAssertEqual(document.store.document, before)
  }
  @MainActor func testDisabledAndRecoveredDocumentsDoNotScheduleActions() async throws {
    let (controller, events, actions, action) = try fixture(), document = try document(actions)
    defer { cleanup(controller, [document]) }
    try events.add(event: .newDocument, actionID: action.id)
    let before = document.store.document; controller.addDocument(document)
    XCTAssertNil(controller.scriptEventsDispatcher.task); XCTAssertEqual(document.store.document, before)
    controller.removeDocument(document); try events.setEnabled(true); document.isRecoveredSource = true
    controller.addDocument(document); XCTAssertNil(controller.scriptEventsDispatcher.task)
    XCTAssertEqual(document.store.document, before)
  }
  @MainActor func testClosedChangedAndBusyDocumentsCannotReceivePendingEdits() async throws {
    for mode in ["closed", "changed", "busy"] {
      let (controller, events, actions, action) = try fixture(), document = try document(actions)
      defer { cleanup(controller, [document]) }
      try events.add(event: .newDocument, actionID: action.id); try events.setEnabled(true)
      controller.addDocument(document)
      if mode == "closed" { controller.removeDocument(document) }
      if mode == "changed" { document.store.perform(.opacity(document.store.document.layers[0].id, 0.25)) }
      if mode == "busy" { document.store.geometryBusy = true }
      let before = document.store.document
      let history = document.store.session.undoStack.count
      await controller.scriptEventsDispatcher.task?.value
      document.store.geometryBusy = false
      XCTAssertNotNil(controller.scriptEventsDispatcher.lastResult?.error, mode)
      XCTAssertEqual(document.store.document, before, mode); XCTAssertEqual(document.store.session.undoStack.count, history, mode)
    }
  }
  @MainActor func testChangedConfigurationAndActionLibraryRejectCapturedRequests() async throws {
    for mode in ["disabled", "configuration", "library"] {
      let (controller, events, actions, action) = try fixture(), document = try document(actions)
      defer { cleanup(controller, [document]) }
      try events.add(event: .newDocument, actionID: action.id); try events.setEnabled(true)
      controller.addDocument(document); let before = document.store.document
      if mode == "disabled" { try events.setEnabled(false) }
      if mode == "configuration" { try events.remove(nil) }
      if mode == "library" { var changed = action; changed.name = "Changed after publication"; try actions.save(changed) }
      await controller.scriptEventsDispatcher.task?.value
      XCTAssertNotNil(controller.scriptEventsDispatcher.lastResult?.error, mode)
      XCTAssertEqual(document.store.document, before, mode); XCTAssertTrue(document.store.session.undoStack.isEmpty, mode)
    }
  }
  @MainActor func testPreparationCommitValidatorPreventsLateMutationWithoutAffectingManualPlayback() async throws {
    let (_, _, actions, action) = try fixture(), document = try document(actions), store = document.store
    defer { store.renderTask?.cancel() }
    let before = store.document; var checks = 0
    do {
      try await store.playEventAction(action) {
        checks += 1
        if checks == 2 { throw CraftError.invalid("Owned stale event at commit") }
      }
      XCTFail("Expected commit validation rejection")
    } catch { XCTAssertTrue(error.localizedDescription.contains("Owned stale event")) }
    XCTAssertEqual(checks, 2); XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(store.geometryBusy)
    store.error = nil; store.playAction(action); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.session.undoStack.count, 1); XCTAssertEqual(store.document.layers[0].opacity, 0.5)
  }
  @MainActor func testCancellationDuringPlaybackAdmissionCannotCommitOrCancelTheNextEdit() async throws {
    let (_, _, actions, action) = try fixture(), document = try document(actions), store = document.store
    defer { store.renderTask?.cancel() }
    let before = store.document
    var running: Task<Void, Error>?
    running = Task { @MainActor in
      try await store.playEventAction(action) { running?.cancel() }
    }
    do { try await running?.value; XCTFail("Expected cancellation") } catch { }
    XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(store.geometryBusy)
    store.error = nil; store.playAction(action); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document.layers[0].opacity, 0.5)
    XCTAssertEqual(store.session.undoStack.count, 1)
  }
  @MainActor func testEventAndManualPlaybackRetainExactNativePSDAndPNGBytesAcrossDepths() async throws {
    let output = try folder()
    for depth in [PixelDepth.u8, .u16, .f32] {
      let (controller, events, actions, action) = try fixture()
      var original = try CraftNSDocument.blankModel(width: 4, height: 3, depth: depth, background: .clear)
      // Fixed owned identities make the captured inputs comparable on ARM and
      // translated Intel, including metadata in the native/PSD byte streams.
      original.id = UUID(uuidString: "4F5B6565-7C57-4A40-B03C-9326C6BD0001")!
      original.layers[0].id = UUID(uuidString: "4F5B6565-7C57-4A40-B03C-9326C6BD0002")!
      original.activeLayerID = original.layers[0].id
      let document = CraftNSDocument(model: original, actions: actions)
      let manual = EditorStore(document: original, actions: actions)
      defer { manual.renderTask?.cancel(); cleanup(controller, [document]) }
      try events.add(event: .newDocument, actionID: action.id); try events.setEnabled(true)
      controller.addDocument(document); await controller.scriptEventsDispatcher.task?.value
      manual.playAction(action); await manual.geometryTask?.value
      XCTAssertNil(controller.scriptEventsDispatcher.lastResult?.error); XCTAssertNil(manual.error)
      XCTAssertEqual(document.store.document, manual.document)
      for format in [DocumentIO.Format.native, .psd, .png] {
        let actual = try DocumentIO.encode(document.store.document, format: format)
        let expected = try DocumentIO.encode(manual.document, format: format)
        XCTAssertEqual(actual, expected, "\(depth) \(format)")
        try actual.write(to: output.appendingPathComponent("event-\(depth.rawValue).\(format.rawValue)"))
        try expected.write(to: output.appendingPathComponent("manual-\(depth.rawValue).\(format.rawValue)"))
      }
    }
  }
  @MainActor func testUnsupportedActionFailsAtomicallyAndStopsLaterRegistrations() async throws {
    let (controller, events, actions, tail) = try fixture(), document = try document(actions)
    defer { cleanup(controller, [document]) }
    let unsupported = RecordedAction(name: "Owned unavailable", steps: [
      .init(name: "Black", operation: .fill(.active, .black)),
      .init(name: "Unavailable", operation: .unsupported("Owned unsupported operation"))])
    try actions.save(unsupported); try events.add(event: .newDocument, actionID: unsupported.id)
    try events.add(event: .newDocument, actionID: tail.id); try events.setEnabled(true)
    let before = document.store.document; controller.addDocument(document); await controller.scriptEventsDispatcher.task?.value
    XCTAssertNotNil(controller.scriptEventsDispatcher.lastResult?.error)
    XCTAssertEqual(controller.scriptEventsDispatcher.lastResult?.completedActions, 0)
    XCTAssertEqual(document.store.document, before); XCTAssertTrue(document.store.session.undoStack.isEmpty)
  }
  @MainActor func testAPIRequiresSeparatePermissionAndSharesExactPersistentConfiguration() async throws {
    let (controller, events, actions, action) = try fixture()
    let service = AutomationService(controller: controller), helper = AutomationTests()
    defer { service.stop(); controller.scriptEventsDispatcher.cancel() }
    service.start(); for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertTrue(service.isRunning)
    let denied = try await helper.request(service, path: ScriptEventsAPI.path); XCTAssertEqual(denied.0.statusCode, 403)
    service.setScriptEventChangesEnabled(true)
    let initial = try await helper.request(service, path: ScriptEventsAPI.path); XCTAssertEqual(initial.0.statusCode, 200)
    let stale = events.revision.uuidString
    let registration = ScriptEventBinding(event: .newDocument, actionID: action.id)
    let config = ScriptEventsConfiguration(enabled: true, bindings: [registration])
    let object = try JSONSerialization.jsonObject(with: config.encoded())
    let body: [String: Any] = ["revision": stale, "configuration": object]
    let response = try await helper.request(service, path: ScriptEventsAPI.path, body: body)
    XCTAssertEqual(response.0.statusCode, 200); XCTAssertEqual(events.configuration, config)
    let rejected = try await helper.request(service, path: ScriptEventsAPI.path, body: body); XCTAssertEqual(rejected.0.statusCode, 409)
    let document = try document(actions); defer { cleanup(controller, [document]) }
    controller.addDocument(document); await controller.scriptEventsDispatcher.task?.value
    XCTAssertTrue(service.shares.isEmpty); XCTAssertEqual(document.store.document.layers[0].opacity, 0.5)
    service.setScriptEventChangesEnabled(false)
    let revoked = try await helper.request(service, path: ScriptEventsAPI.path); XCTAssertEqual(revoked.0.statusCode, 403)
    XCTAssertTrue(events.configuration.enabled)
    service.stop(); XCTAssertFalse(service.scriptEventChangesEnabled); XCTAssertTrue(events.configuration.enabled)
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: ScriptEventsAPI.capabilities))
  }
  @MainActor func testAPIRejectsUnknownFieldsInvalidEventsAndUnavailableActionsWithoutMutation() async throws {
    let (controller, events, _, _) = try fixture(), service = AutomationService(controller: controller), helper = AutomationTests()
    defer { service.stop() }
    service.start(); for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    service.setScriptEventChangesEnabled(true)
    let before = events.configuration, revision = events.revision
    for mode in ["field", "event", "action", "bool", "version"] {
      var config: [String: Any] = ["version": 1, "enabled": true, "bindings": [["id": UUID().uuidString,
        "event": "newDocument", "actionID": UUID().uuidString]]]
      if mode == "field" { config["script"] = "unavailable.jsx" }
      if mode == "event" { config["bindings"] = [["id": UUID().uuidString, "event": "saveDocument", "actionID": UUID().uuidString]] }
      if mode == "bool" { config["enabled"] = "true" }
      if mode == "version" { config["version"] = 2 }
      let response = try await helper.request(service, path: ScriptEventsAPI.path,
        body: ["revision": revision.uuidString, "configuration": config])
      XCTAssertEqual(response.0.statusCode, mode == "action" ? 422 : 400, mode)
      XCTAssertEqual(events.configuration, before, mode); XCTAssertEqual(events.revision, revision, mode)
    }
  }
  @MainActor func testNativeManagerAndAPIViewUseNativeControlsWithoutChangingDocuments() throws {
    let (controller, events, _, _) = try fixture()
    let window = ScriptEventsWindow(controller: controller)
    defer { window.close() }
    window.window?.setContentSize(.init(width: 660, height: 450))
    window.window?.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(window.window?.title, "Script Events Manager")
    XCTAssertNil(window.window?.appearance)
    XCTAssertFalse(events.configuration.enabled); XCTAssertTrue(controller.documents.isEmpty)
    XCTAssertGreaterThan(window.window?.contentView?.fittingSize.width ?? 0, 500)
    let capabilities = ScriptEventsAPI.capabilities
    XCTAssertEqual(capabilities["events"] as? [String], ["newDocument", "openDocument"])
    XCTAssertEqual(capabilities["scripts"] as? Bool, false)
  }
  @MainActor func testStartupFactoryUsesPersistentEventsOnlyForNormalLaunch() {
    _ = NSApplication.shared
    let normal = PhotatoApp.makeDelegate(isolatedSession: false)
    XCTAssertTrue(normal.controller.scriptEvents === ScriptEventsStore.shared)
    let isolated = PhotatoApp.makeDelegate(isolatedSession: true)
    XCTAssertFalse(isolated.controller.scriptEvents === ScriptEventsStore.shared)
    XCTAssertNil(isolated.controller.scriptEvents.persistenceURL)
    XCTAssertFalse(isolated.controller.scriptEvents.configuration.enabled)
  }
  @MainActor func testAPICannotMutateRegisteredActionsWithoutEventPermissionEvenWhenDisabled() async throws {
    for enabled in [false, true] {
      let (controller, events, actions, action) = try fixture(), document = try document(actions)
      controller.addDocument(document)
      defer { cleanup(controller, [document]) }
      try events.add(event: .newDocument, actionID: action.id); try events.setEnabled(enabled)
      let service = AutomationService(controller: controller), helper = AutomationTests()
      defer { service.stop() }
      service.start(); for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
      try service.share(document)
      let original = try actions.exportFile(), revision = actions.revision, originalDocument = document.store.document
      let requests: [[String: Any]] = [
        ["operation": "rename", "actionID": action.id.uuidString, "name": "Changed", "set": "Changed"],
        ["operation": "delete", "actionID": action.id.uuidString],
        ["operation": "step.enable", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString, "enabled": false],
        ["operation": "step.delete", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString],
        ["operation": "step.move", "actionID": action.id.uuidString, "stepID": action.steps[0].id.uuidString, "index": 1]]
      for request in requests {
        let status = try await helper.edit(service, document, "actions.manage", request)
        XCTAssertEqual(status, 403); XCTAssertEqual(try actions.exportFile(), original); XCTAssertEqual(actions.revision, revision)
        XCTAssertEqual(document.store.document, originalDocument); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      }
      let listed = try await helper.edit(service, document, "actions.manage", ["operation": "list"])
      XCTAssertEqual(listed, 200)
      let unbound = RecordedAction(name: "Owned unbound", steps: [.init(name: "Fill", operation: .fill(.active, .white))])
      try actions.save(unbound)
      let unboundStatus = try await helper.edit(service, document, "actions.manage", ["operation": "step.enable",
        "actionID": unbound.id.uuidString, "stepID": unbound.steps[0].id.uuidString, "enabled": false])
      XCTAssertEqual(unboundStatus, 200); XCTAssertFalse(try actions.action(unbound.id).steps[0].enabled)
      service.setScriptEventChangesEnabled(true)
      let allowed = try await helper.edit(service, document, "actions.manage", requests[2])
      XCTAssertEqual(allowed, 200); XCTAssertFalse(try actions.action(action.id).steps[0].enabled)
      service.setScriptEventChangesEnabled(false)
      let revoked = try await helper.edit(service, document, "actions.manage", requests[1]); XCTAssertEqual(revoked, 403)
      XCTAssertEqual(events.configuration.enabled, enabled)
    }
  }
  @MainActor func testCompleteResultSchemaMatchesEmptyConfiguredAndCompletedHTTPState() async throws {
    let (controller, events, actions, action) = try fixture(), service = AutomationService(controller: controller), helper = AutomationTests()
    defer { service.stop(); controller.scriptEventsDispatcher.cancel() }
    service.start(); for _ in 0..<100 where !service.isRunning { try await Task.sleep(for: .milliseconds(20)) }
    service.setScriptEventChangesEnabled(true)
    let schema = ScriptEventsAPI.stateSchema
    let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
    let required = try XCTUnwrap(schema["required"] as? [String])
    XCTAssertEqual(Set(required), Set(properties.keys))
    for phase in 0..<3 {
      if phase == 1 { try events.add(event: .newDocument, actionID: action.id); try events.setEnabled(true) }
      var created: CraftNSDocument?
      if phase == 2 { created = try document(actions); controller.addDocument(created!); await controller.scriptEventsDispatcher.task?.value }
      defer { if let created { cleanup(controller, [created]) } }
      let response = try await helper.request(service, path: ScriptEventsAPI.path)
      XCTAssertEqual(response.0.statusCode, 200)
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual(Set(body.keys), Set(properties.keys)); XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(body["revision"] as? String)))
      XCTAssertEqual(body["isPersistent"] as? Bool, false); XCTAssertEqual(body["isRunning"] as? Bool, false)
      XCTAssertEqual(body["pendingEvents"] as? Int, 0); XCTAssertTrue(body["loadError"] is NSNull); XCTAssertTrue(body["actionsLoadError"] is NSNull)
      let config = try XCTUnwrap(body["configuration"] as? [String: Any])
      XCTAssertEqual(Set(config.keys), ["version", "enabled", "bindings"])
      if phase == 2 {
        let result = try XCTUnwrap(body["lastResult"] as? [String: Any])
        XCTAssertEqual(Set(result.keys), ["event", "documentID", "completedActions", "error"])
        XCTAssertEqual(result["event"] as? String, "newDocument"); XCTAssertEqual(result["completedActions"] as? Int, 1)
        XCTAssertTrue(result["error"] is NSNull)
      } else { XCTAssertTrue(body["lastResult"] is NSNull) }
    }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: ScriptEventsAPI.capabilities))
  }
}
