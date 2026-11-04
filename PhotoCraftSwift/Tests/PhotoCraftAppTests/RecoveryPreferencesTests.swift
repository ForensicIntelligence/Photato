import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class RecoveryPreferencesTests: XCTestCase {
  @MainActor func url() throws -> URL {
    let folder = try DocumentPersistenceTests().directory()
    addTeardownBlock { try FileManager.default.removeItem(at: folder) }
    return folder.appendingPathComponent("RecoverySettings.json")
  }
  @MainActor func controller(_ preferences: RecoveryPreferencesStore) -> CraftDocumentController {
    _ = NSApplication.shared
    return CraftDocumentController(workspaces: WorkspaceLibrary(), recoveryPreferences: preferences)
  }
  @MainActor func testDefaultsAllIntervalsAndPersistentReload() throws {
    let url = try url()
    let preferences = RecoveryPreferencesStore(url: url)
    XCTAssertEqual(preferences.value, RecoveryPreferences(enabled: true, intervalMinutes: 10))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    let controller = controller(preferences)
    for minutes in RecoveryPreferences.intervals {
      let value = RecoveryPreferences(enabled: minutes != 15, intervalMinutes: minutes)
      try controller.setRecoveryPreferences(value, revision: preferences.revision)
      XCTAssertEqual(controller.autosavingDelay, value.delay)
      let loaded = RecoveryPreferencesStore(url: url)
      XCTAssertNil(loaded.loadError)
      XCTAssertEqual(loaded.value, value)
    }
  }
  @MainActor func testInvalidStaleAndNoOpKeepRevisionAndBytes() throws {
    let url = try url()
    let preferences = RecoveryPreferencesStore(url: url)
    try preferences.commit(
      .init(enabled: false, intervalMinutes: 30), revision: preferences.revision)
    let revision = preferences.revision
    let bytes = try Data(contentsOf: url)
    try preferences.commit(preferences.value, revision: revision)
    XCTAssertEqual(preferences.revision, revision)
    for minutes in [0, 1, 11, 90, Int.max] {
      XCTAssertThrowsError(
        try preferences.commit(.init(intervalMinutes: minutes), revision: revision))
    }
    XCTAssertThrowsError(try preferences.commit(.init(), revision: UUID()))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertEqual(preferences.revision, revision)
  }
  @MainActor func testPersistenceFailureKeepsTimerValueAndRevision() throws {
    let url = try url()
    let preferences = RecoveryPreferencesStore(url: url) { _, _ in
      throw CocoaError(.fileWriteOutOfSpace)
    }
    let controller = controller(preferences)
    let revision = preferences.revision
    XCTAssertThrowsError(
      try controller.setRecoveryPreferences(.init(enabled: false), revision: revision))
    XCTAssertEqual(preferences.revision, revision)
    XCTAssertEqual(preferences.value, .init())
    XCTAssertEqual(controller.autosavingDelay, 600)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }
  @MainActor func testCorruptUnsupportedAndOversizedFilesArePreserved() throws {
    for bytes in [
      Data("invalid".utf8),
      Data(#"{"version":4,"recovery":{"enabled":false,"intervalMinutes":5}}"#.utf8),
      Data(#"{"version":1,"recovery":{"enabled":true,"intervalMinutes":1}}"#.utf8),
      Data(repeating: 32, count: RecoveryPreferencesStore.maximumBytes + 1),
    ] {
      let url = try url()
      try bytes.write(to: url)
      let preferences = RecoveryPreferencesStore(url: url)
      XCTAssertNotNil(preferences.loadError)
      XCTAssertEqual(preferences.value, .init())
      XCTAssertThrowsError(
        try preferences.commit(.init(enabled: false), revision: preferences.revision))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }
  @MainActor func testExternalChangeRejectsBeforeOverwrite() throws {
    let url = try url()
    let preferences = RecoveryPreferencesStore(url: url)
    try preferences.commit(.init(intervalMinutes: 5), revision: preferences.revision)
    let other = RecoveryPreferencesStore(url: url)
    try other.commit(.init(enabled: false, intervalMinutes: 60), revision: other.revision)
    let external = try Data(contentsOf: url)
    XCTAssertThrowsError(
      try preferences.commit(.init(intervalMinutes: 30), revision: preferences.revision))
    XCTAssertEqual(try Data(contentsOf: url), external)
    XCTAssertEqual(preferences.value.intervalMinutes, 5)
  }
  @MainActor func testDraftCancelApplyAndStaleChange() throws {
    let preferences = RecoveryPreferencesStore()
    let controller = controller(preferences)
    let cancelled = RecoveryPreferencesDraft(controller: controller)
    cancelled.value = .init(enabled: false, intervalMinutes: 60)
    XCTAssertEqual(preferences.value, .init())
    XCTAssertEqual(controller.autosavingDelay, 600)
    let accepted = RecoveryPreferencesDraft(controller: controller)
    accepted.value.intervalMinutes = 5
    XCTAssertTrue(accepted.apply())
    XCTAssertEqual(controller.autosavingDelay, 300)
    XCTAssertFalse(cancelled.apply())
    XCTAssertNotNil(cancelled.error)
    XCTAssertEqual(preferences.value.intervalMinutes, 5)
  }
  @MainActor func testChangingSettingsDoesNotChangeDocumentsHistoryOrExistingBackup() async throws {
    let preferences = RecoveryPreferencesStore()
    let controller = controller(preferences)
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 3, height: 2))
    controller.addDocument(document)
    defer { document.close() }
    try document.store.executeEditorCommand(
      .renameLayer(document.store.document.activeLayerID!, "Edit"))
    try await document.writeRecoverySnapshot()
    let saved = try XCTUnwrap(document.autosavedContentsFileURL)
    let bytes = try Data(contentsOf: saved)
    let model = document.store.document
    let revision = document.store.revision
    let history = document.store.session.undoStack.count
    try controller.setRecoveryPreferences(
      .init(enabled: false, intervalMinutes: 30), revision: preferences.revision)
    XCTAssertEqual(controller.autosavingDelay, 0)
    XCTAssertEqual(document.autosavedContentsFileURL, saved)
    XCTAssertEqual(try Data(contentsOf: saved), bytes)
    XCTAssertEqual(document.store.document, model)
    XCTAssertEqual(document.store.revision, revision)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertTrue(document.isDocumentEdited)
    try document.store.executeEditorCommand(.renameLayer(model.activeLayerID!, "Manual backup"))
    try await document.writeRecoverySnapshot()
    XCTAssertEqual(
      try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)),
      document.store.document)
    XCTAssertEqual(controller.autosavingDelay, 0)
  }
  @MainActor func testBusyControllerRejectsWithoutChangingSettings() throws {
    let preferences = RecoveryPreferencesStore()
    let controller = controller(preferences)
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 2, height: 2))
    controller.addDocument(document)
    defer { document.close() }
    for recovery in [true, false] {
      document.recoveryWriteBusy = recovery
      document.fileOperationBusy = !recovery
      XCTAssertThrowsError(
        try controller.setRecoveryPreferences(.init(enabled: false), revision: preferences.revision)
      )
      XCTAssertEqual(preferences.value, .init())
      XCTAssertEqual(controller.autosavingDelay, 600)
    }
    document.recoveryWriteBusy = false
    document.fileOperationBusy = false
  }
  @MainActor func testQueuedAutomaticBackupRejectsAfterDisabling() async throws {
    let preferences = RecoveryPreferencesStore()
    let controller = controller(preferences)
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 2, height: 2))
    controller.addDocument(document)
    defer { document.close() }
    try document.store.executeEditorCommand(
      .renameLayer(document.store.document.activeLayerID!, "Edit"))
    try controller.setRecoveryPreferences(.init(enabled: false), revision: preferences.revision)
    let target = try url().deletingLastPathComponent().appendingPathComponent("queued.photato")
    let error = await withCheckedContinuation { (c: CheckedContinuation<Error?, Never>) in
      document.save(
        to: target, ofType: CraftNSDocument.nativeType, for: .autosaveElsewhereOperation
      ) {
        c.resume(returning: $0)
      }
    }
    XCTAssertEqual((error as NSError?)?.code, NSUserCancelledError)
    XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertFalse(document.lastRecoveryWriteFailed)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertTrue(document.hasUnautosavedChanges)
    try await document.writeRecoverySnapshot()
    XCTAssertEqual(
      try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)),
      document.store.document)
  }
  @MainActor func testEnablingExistingDirtyDocumentDoesNotInventEdits() throws {
    let preferences = RecoveryPreferencesStore()
    let controller = controller(preferences)
    try controller.setRecoveryPreferences(.init(enabled: false), revision: preferences.revision)
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 2, height: 2))
    controller.addDocument(document)
    defer { document.close() }
    try document.store.executeEditorCommand(
      .renameLayer(document.store.document.activeLayerID!, "Edit"))
    let content = document.store.document
    let revision = document.store.revision
    let history = document.store.session.undoStack.count
    try controller.setRecoveryPreferences(.init(intervalMinutes: 5), revision: preferences.revision)
    XCTAssertEqual(controller.autosavingDelay, 300)
    XCTAssertEqual(document.store.document, content)
    XCTAssertEqual(document.store.revision, revision)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertTrue(document.hasUnautosavedChanges)
    XCTAssertNil(document.autosavedContentsFileURL)
  }
  @MainActor func testFileHandlingMenuIsBoundWithoutRepurposingGeneralShortcut() throws {
    let menus = PhotoshopMenuTests()
    try menus.withMenus { app, menu in
      let items = menus.allItems(menu)
      let file = try XCTUnwrap(
        items.first { $0.identifier?.rawValue == "Photato > Settings… > File Handling…" })
      XCTAssertEqual(file.action, #selector(AppDelegate.fileHandlingPreferences))
      XCTAssertTrue(app.validateMenuItem(file))
      XCTAssertEqual(file.keyEquivalent, "")
      let general = try XCTUnwrap(
        items.first { $0.identifier?.rawValue == "Photato > Settings… > General…" })
      XCTAssertNil(general.action)
      XCTAssertEqual(general.keyEquivalent, "k")
      XCTAssertEqual(general.keyEquivalentModifierMask, [.command])
      let window = RecoveryPreferencesWindowController(controller: app.controller)
      XCTAssertEqual(window.window?.title, "Settings — File Handling")
      XCTAssertNotNil(window.window?.contentView)
      window.close()
    }
  }
  @MainActor func testHTTPPermissionNativeEquivalenceAndStaleRevision() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      let path = "/v1/preferences/recovery"
      let unauthorized = try await api.request(service, path: path, authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      let state = try await api.request(service, path: path)
      XCTAssertEqual(state.0.statusCode, 200)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      XCTAssertEqual(object["intervalMinutes"] as? Int, 10)
      let revision = service.controller.recoveryPreferences.revision.uuidString
      let body: [String: Any] = ["revision": revision, "enabled": false, "intervalMinutes": 15]
      let denied = try await api.request(service, path: path, body: body)
      XCTAssertEqual(denied.0.statusCode, 403)
      let documentRevision = document.store.revision
      service.setPreferenceChangesEnabled(true)
      let changed = try await api.request(service, path: path, body: body)
      XCTAssertEqual(changed.0.statusCode, 200)
      XCTAssertEqual(
        service.controller.recoveryPreferences.value, .init(enabled: false, intervalMinutes: 15))
      XCTAssertEqual(service.controller.autosavingDelay, 0)
      XCTAssertEqual(document.store.revision, documentRevision)
      let stale = try await api.request(service, path: path, body: body)
      XCTAssertEqual(stale.0.statusCode, 409)
      let draft = RecoveryPreferencesDraft(controller: service.controller)
      draft.value = .init(intervalMinutes: 30)
      XCTAssertTrue(draft.apply())
      let latest = try await api.request(service, path: path)
      let latestState = try XCTUnwrap(
        JSONSerialization.jsonObject(with: latest.1) as? [String: Any])
      XCTAssertEqual(latestState["effectiveIntervalSeconds"] as? Double, 1800)
      service.stop()
      XCTAssertFalse(service.preferenceChangesEnabled)
    }
  }
  @MainActor func testHTTPInvalidBusyAndMediaTypeAreAtomic() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      service.setPreferenceChangesEnabled(true)
      let path = "/v1/preferences/recovery"
      let preferences = service.controller.recoveryPreferences
      let body: [String: Any] = [
        "revision": preferences.revision.uuidString, "enabled": true, "intervalMinutes": 5,
      ]
      for (key, value) in [
        ("enabled", 1 as Any), ("intervalMinutes", 5.5 as Any), ("revision", "wrong" as Any),
        ("unknown", true as Any),
      ] {
        var bad = body
        bad[key] = value
        let response = try await api.request(service, path: path, body: bad)
        XCTAssertEqual(response.0.statusCode, 400)
      }
      let media = try await api.request(
        service, path: path, body: body, headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      document.recoveryWriteBusy = true
      let busy = try await api.request(service, path: path, body: body)
      document.recoveryWriteBusy = false
      XCTAssertEqual(busy.0.statusCode, 409)
      XCTAssertEqual(preferences.value, .init())
      XCTAssertEqual(service.controller.autosavingDelay, 600)
      let capabilities = AutomationService.recoveryPreferencesCapabilities
      let schema = try XCTUnwrap(capabilities["updateSchema"] as? [String: Any])
      XCTAssertEqual(
        Set(schema["required"] as? [String] ?? []), ["revision", "enabled", "intervalMinutes"])
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testHTTPPersistenceFailureDoesNotPublishSettings() async throws {
    let api = AutomationTests()
    let preferences = RecoveryPreferencesStore(url: try url()) { _, _ in
      throw CocoaError(.fileWriteOutOfSpace)
    }
    try await api.withService(recoveryPreferences: preferences) { service, _ in
      service.setPreferenceChangesEnabled(true)
      let response = try await api.request(
        service, path: "/v1/preferences/recovery",
        body: [
          "revision": preferences.revision.uuidString, "enabled": false, "intervalMinutes": 60,
        ])
      XCTAssertEqual(response.0.statusCode, 422)
      XCTAssertEqual(preferences.value, .init())
      XCTAssertEqual(service.controller.autosavingDelay, 600)
    }
  }
}
