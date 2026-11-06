import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class SaveDialogFormatsTests: XCTestCase {
  let route = "/v1/preferences/photoshop-file-handling"
  @MainActor func fixture(_ depth: PixelDepth = .u8) throws -> (URL, RecoveryPreferencesStore, CraftDocumentController, CraftNSDocument) {
    let folder = try DocumentPersistenceTests().directory()
    let settings = RecoveryPreferencesStore(url: folder.appendingPathComponent("settings.json"))
    let controller = RecoveryPreferencesTests().controller(settings)
    let model = try CraftNSDocument.blankModel(width: 4, height: 3, depth: depth)
    let document = CraftNSDocument(model: model); controller.addDocument(document)
    return (folder, settings, controller, document)
  }
  @MainActor func testLegacyVersionsAndStrictV4PreserveSettingsAndRecentFiles() throws {
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: folder) }
    for version in [1, 2, 3] {
      let url = folder.appendingPathComponent("legacy-\(version).json")
      let original = Data("{\"version\":\(version),\"recovery\":{\"enabled\":false,\"intervalMinutes\":30,\"recentFileLimit\":7,\"disablePSDCompression\":true},\"recentDocuments\":[]}".utf8)
      try original.write(to: url)
      let store = RecoveryPreferencesStore(url: url)
      XCTAssertNil(store.loadError); XCTAssertEqual(store.value.saveDialogFormats, SaveDialogFormats.defaults)
      XCTAssertEqual(try Data(contentsOf: url), original, "Reading a legacy archive must not write it.")
      var next = store.value; next.saveDialogFormats = [.jpeg, .png]
      try store.commit(next, revision: store.revision)
      let recent = folder.appendingPathComponent("owned.photato")
      try NativeArchive.write(CraftDocument(width: 1, height: 1), to: recent)
      store.remember(recent)
      let loaded = RecoveryPreferencesStore(url: url)
      XCTAssertNil(loaded.loadError); XCTAssertEqual(loaded.value, next)
      XCTAssertEqual(loaded.recentDocuments, store.recentDocuments); XCTAssertEqual(loaded.recentDocuments.count, 1)
      let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      XCTAssertEqual(raw["version"] as? Int, 4)
      let recovery = try XCTUnwrap(raw["recovery"] as? [String: Any])
      XCTAssertEqual(recovery["saveDialogFormats"] as? [String], ["png", "jpeg"])
      try loaded.clearRecent(revision: loaded.recentRevision)
      XCTAssertEqual(RecoveryPreferencesStore(url: url).value, next)
    }
    let bad: [String] = [
      #"{"version":5,"recovery":{"enabled":true,"intervalMinutes":10,"saveDialogFormats":[]}}"#,
      #"{"version":4,"recovery":{"enabled":true,"intervalMinutes":10}}"#,
      #"{"version":4,"recovery":{"enabled":true,"intervalMinutes":10,"saveDialogFormats":null}}"#,
      #"{"version":4,"recovery":{"enabled":true,"intervalMinutes":10,"saveDialogFormats":["png","png"]}}"#,
      #"{"version":4,"recovery":{"enabled":true,"intervalMinutes":10,"saveDialogFormats":["unsupported"]}}"#,
      #"{"version":4,"recovery":{"enabled":true,"intervalMinutes":10,"saveDialogFormats":[42]}}"#,
    ]
    for (index, text) in bad.enumerated() {
      let url = folder.appendingPathComponent("bad-\(index).json"), bytes = Data(text.utf8); try bytes.write(to: url)
      let store = RecoveryPreferencesStore(url: url)
      XCTAssertNotNil(store.loadError)
      XCTAssertThrowsError(try store.commit(.init(enabled: false), revision: store.revision))
      XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
  }
  @MainActor func testAll64ListsPreserveContentHistoryAndEncoderAvailabilityAtEveryRGBDepth() throws {
    for depth in PixelDepth.allCases {
      let settings = RecoveryPreferencesStore(), controller = RecoveryPreferencesTests().controller(settings)
      let model = try CraftNSDocument.blankModel(width: 4, height: 3, depth: depth)
      let document = CraftNSDocument(model: model); controller.addDocument(document); defer { document.close() }
      let writable = document.saveFormats, before = try NativeArchive.encodeChunked(model), revision = document.store.revision
      for bits in 0..<64 {
        let selected = Set(DocumentIO.Format.allCases.enumerated().compactMap { bits & (1 << $0.offset) == 0 ? nil : $0.element })
        var value = settings.value; value.saveDialogFormats = selected
        try controller.setRecoveryPreferences(value, revision: settings.revision)
        XCTAssertEqual(document.dialogCopyFormats, DocumentIO.Format.allCases.filter { selected.contains($0) })
        XCTAssertEqual(document.dialogSaveFormats, writable.filter { selected.contains($0) })
        XCTAssertEqual(document.saveFormats, writable)
        XCTAssertEqual(document.writableTypes(for: .saveOperation), writable.map(\.typeIdentifier))
        XCTAssertEqual(document.store.document, model); XCTAssertEqual(document.store.revision, revision)
        XCTAssertEqual(try NativeArchive.encodeChunked(document.store.document), before)
        XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertTrue(document.store.session.redoStack.isEmpty)
        XCTAssertFalse(document.isDocumentEdited); XCTAssertEqual(controller.autosavingDelay, 600)
      }
      let huge = CraftNSDocument(model: try CraftDocument(width: 300000, height: 300000))
      controller.addDocument(huge); defer { huge.close() }
      XCTAssertTrue(huge.dialogSaveFormats.contains(.native))
      XCTAssertEqual(huge.store.document.width, 300000)
    }
  }
  @MainActor func testNativePanelsNeverRestoreHiddenFormatsAndExplicitSavesKeepExactBytes() async throws {
    for depth in PixelDepth.allCases {
      let (folder, settings, controller, document) = try fixture(depth)
      defer { document.close(); try? FileManager.default.removeItem(at: folder) }
      let before = document.store.document, target = folder.appendingPathComponent("owned.photato")
      try await document.persistDocument(to: target, format: .native, operation: .saveAsOperation)
      let saved = try Data(contentsOf: target)
      let selected = SaveDialogFormatsDraft(controller: controller); selected.selected = [.png]
      XCTAssertTrue(selected.apply(), selected.error ?? "")
      XCTAssertEqual(document.prepareSavePanel(NSSavePanel()), depth != .f32)
      if depth == .f32 {
        XCTAssertTrue(document.dialogSaveFormats.isEmpty); XCTAssertNil(document.saveAccessory)
      } else { XCTAssertEqual(document.saveAccessory?.availableFormats, [.png]) }
      document.store.error = nil
      let clear = SaveDialogFormatsDraft(controller: controller); clear.clearFormats(); XCTAssertTrue(clear.apply())
      XCTAssertTrue(settings.value.saveDialogFormats.isEmpty)
      XCTAssertFalse(document.prepareSavePanel(NSSavePanel())); XCTAssertNil(document.saveAccessory)
      XCTAssertNotNil(document.store.error); document.store.error = nil
      document.showSaveCopy(); XCTAssertNil(document.copyPanel); XCTAssertNotNil(document.store.error)
      document.store.error = nil
      try await document.persistDocument(to: target, format: .native, operation: .saveOperation)
      XCTAssertEqual(try Data(contentsOf: target), saved)
      let copy = folder.appendingPathComponent("explicit.png")
      try await document.copyDocument(to: copy, format: .png)
      XCTAssertEqual(try Data(contentsOf: copy), try DocumentIO.encode(before, format: .png))
      XCTAssertEqual(document.store.document, before); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertFalse(document.isDocumentEdited)
      let restore = SaveDialogFormatsDraft(controller: controller); restore.restoreDefaults(); XCTAssertTrue(restore.apply())
      XCTAssertEqual(document.dialogSaveFormats, document.saveFormats)
    }
  }
  @MainActor func testDraftCancelRestoreStaleBusyExternalAndFailedWritesAreAtomic() throws {
    let (folder, settings, controller, document) = try fixture()
    defer { document.close(); try? FileManager.default.removeItem(at: folder) }
    let cancelled = SaveDialogFormatsDraft(controller: controller); cancelled.clearFormats()
    XCTAssertEqual(settings.value.saveDialogFormats, SaveDialogFormats.defaults)
    cancelled.restoreDefaults(); XCTAssertEqual(cancelled.selected, SaveDialogFormats.defaults)
    let accepted = SaveDialogFormatsDraft(controller: controller); accepted.selected = [.png]
    XCTAssertTrue(accepted.apply()); XCTAssertFalse(cancelled.apply())
    let url = folder.appendingPathComponent("settings.json"), bytes = try Data(contentsOf: url), revision = settings.revision
    document.fileOperationBusy = true
    let busy = SaveDialogFormatsDraft(controller: controller); busy.clearFormats(); XCTAssertFalse(busy.apply())
    document.fileOperationBusy = false
    XCTAssertEqual(settings.revision, revision); XCTAssertEqual(try Data(contentsOf: url), bytes)
    let failing = RecoveryPreferencesStore(url: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    let failingController = RecoveryPreferencesTests().controller(failing)
    let failure = SaveDialogFormatsDraft(controller: failingController); failure.clearFormats(); XCTAssertFalse(failure.apply())
    XCTAssertEqual(failing.value.saveDialogFormats, [.png]); XCTAssertEqual(try Data(contentsOf: url), bytes)
    let external = RecoveryPreferencesStore(url: url); var changed = external.value; changed.saveDialogFormats = [.jpeg]
    try external.commit(changed, revision: external.revision)
    let externalBytes = try Data(contentsOf: url)
    let stale = SaveDialogFormatsDraft(controller: controller); stale.clearFormats(); XCTAssertFalse(stale.apply())
    XCTAssertEqual(try Data(contentsOf: url), externalBytes); XCTAssertEqual(settings.value.saveDialogFormats, [.png])
  }
  @MainActor func testHTTPNativeEquivalenceSchemasAndExistingRecoveryIsolation() async throws {
    let nativeSettings = RecoveryPreferencesStore(), nativeController = RecoveryPreferencesTests().controller(nativeSettings)
    let draft = SaveDialogFormatsDraft(controller: nativeController); draft.selected = [.jpeg, .png]; XCTAssertTrue(draft.apply())
    let nativeExpected = nativeSettings.value
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let settings = service.controller.recoveryPreferences, before = document.store.document
      await document.store.renderTask?.value
      let revision = service.revision(document.store); try service.share(document)
      let denied = try await helper.request(service, path: self.route,
        body: ["revision": settings.revision.uuidString, "saveDialogFormats": ["jpeg", "png"]])
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setPhotoshopPreferenceChangesEnabled(true)
      let accepted = try await helper.request(service, path: self.route,
        body: ["revision": settings.revision.uuidString, "saveDialogFormats": ["jpeg", "png"]])
      XCTAssertEqual(accepted.0.statusCode, 200)
      XCTAssertEqual(settings.value, nativeExpected)
      let state = service.state(try XCTUnwrap(service.shares.first), document: document)
      XCTAssertEqual(state["saveFormats"] as? [String], document.saveFormats.map(\.rawValue))
      XCTAssertEqual(state["saveDialogFormats"] as? [String], document.dialogSaveFormats.map(\.rawValue))
      XCTAssertEqual(state["copyDialogFormats"] as? [String], ["png", "jpeg"])
      XCTAssertEqual(state["fileHandlingPreferencesRevision"] as? String, settings.revision.uuidString)
      let value = try JSONDecoder().decode(AutomationValue.self, from: accepted.1)
      let schema = try XCTUnwrap(AutomationService.photoshopFilePreferencesCapabilities["stateSchema"] as? [String: Any])
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: schema))
      XCTAssertEqual(service.revision(document.store), revision)
      service.setDocumentTransfersEnabled(true)
      let sharedID = try XCTUnwrap(service.shares.first?.id).uuidString
      let download = try await helper.request(service, path: "/v1/documents/\(sharedID)/file.photato",
        headers: ["X-Photato-Archive-Version": "86"])
      XCTAssertEqual(download.0.statusCode, 200)
      XCTAssertEqual(download.1, try NativeArchive.encodeChunked(before, minimumVersion: 86), "Hidden native format remains available to explicit API output.")
      service.setPreferenceChangesEnabled(true)
      let recovery = try await helper.request(service, path: "/v1/preferences/recovery",
        body: ["revision": settings.revision.uuidString, "enabled": false, "intervalMinutes": 15])
      XCTAssertEqual(recovery.0.statusCode, 200); XCTAssertEqual(settings.value.saveDialogFormats, [.png, .jpeg])
      XCTAssertEqual(document.store.document, before); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleNoopPermissionAndFailedWriteDoNotPublish() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let settings = service.controller.recoveryPreferences; service.setPhotoshopPreferenceChangesEnabled(true)
      let revision = settings.revision
      let invalid: [[String: Any]] = [
        ["revision": revision.uuidString],
        ["revision": revision.uuidString, "saveDialogFormats": "png"],
        ["revision": revision.uuidString, "saveDialogFormats": NSNull()],
        ["revision": revision.uuidString, "saveDialogFormats": [42]],
        ["revision": revision.uuidString, "saveDialogFormats": ["png", "png"]],
        ["revision": revision.uuidString, "saveDialogFormats": ["unknown"]],
        ["revision": revision.uuidString, "saveDialogFormats": ["png"], "unknown": true],
        ["revision": "invalid", "saveDialogFormats": []],
        ["revision": revision.uuidString, "saveDialogFormats": ["png"], "disablePSDCompression": "true"],
      ]
      for body in invalid {
        let result = try await helper.request(service, path: self.route, body: body)
        XCTAssertEqual(result.0.statusCode, 400); XCTAssertEqual(settings.revision, revision)
      }
      let body: [String: Any] = ["revision": revision.uuidString, "saveDialogFormats": []]
      document.fileOperationBusy = true
      let busy = try await helper.request(service, path: self.route, body: body)
      document.fileOperationBusy = false; XCTAssertEqual(busy.0.statusCode, 409)
      let accepted = try await helper.request(service, path: self.route, body: body)
      XCTAssertEqual(accepted.0.statusCode, 200); XCTAssertTrue(settings.value.saveDialogFormats.isEmpty)
      let latest = settings.revision
      let noop = try await helper.request(service, path: self.route,
        body: ["revision": latest.uuidString, "saveDialogFormats": []])
      XCTAssertEqual(noop.0.statusCode, 200); XCTAssertEqual(settings.revision, latest)
      let stale = try await helper.request(service, path: self.route, body: body)
      XCTAssertEqual(stale.0.statusCode, 409)
      service.setPhotoshopPreferenceChangesEnabled(false)
      let revoked = try await helper.request(service, path: self.route,
        body: ["revision": latest.uuidString, "saveDialogFormats": ["png"]])
      XCTAssertEqual(revoked.0.statusCode, 403); XCTAssertTrue(settings.value.saveDialogFormats.isEmpty)
    }
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("failed.json")
    let failing = RecoveryPreferencesStore(url: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    try await helper.withService(recoveryPreferences: failing) { service, _ in
      service.setPhotoshopPreferenceChangesEnabled(true)
      let response = try await helper.request(service, path: self.route,
        body: ["revision": failing.revision.uuidString, "saveDialogFormats": []])
      XCTAssertEqual(response.0.statusCode, 422); XCTAssertEqual(failing.value.saveDialogFormats, SaveDialogFormats.defaults)
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }
  @MainActor func testSupplementalMenuAndOwnedWindowLayoutRetainHistoricalMenus() throws {
    let fixture = try XCTUnwrap(Bundle.module.url(forResource: "photoshop-save-dialog-formats", withExtension: "json", subdirectory: "Fixtures"))
    let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
    let path = try XCTUnwrap(reference["path"] as? [String]).joined(separator: " > ")
    try PhotoshopMenuTests().withMenus { app, menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == path })
      XCTAssertEqual(item.action, #selector(AppDelegate.customizeSaveDialogFileFormats))
      XCTAssertTrue(item.keyEquivalent.isEmpty); XCTAssertTrue(app.validateMenuItem(item))
    }
    let settings = RecoveryPreferencesStore(), controller = RecoveryPreferencesTests().controller(settings)
    let window = SaveDialogFormatsWindowController(controller: controller); defer { window.close() }
    XCTAssertEqual(window.window?.title, "Customize Save Dialog File Formats")
    let host = try XCTUnwrap(window.window?.contentView)
    host.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(host.fittingSize.width, 620); XCTAssertLessThanOrEqual(host.fittingSize.height, 400)
    XCTAssertEqual(window.draft.selected, SaveDialogFormats.defaults)
    if let dir = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
      let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: image)
      try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("save-dialog-formats.png"))
    }
  }
}
