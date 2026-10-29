import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ColorSettingsTests: XCTestCase {
  func settings() throws -> ColorSettings {
    var result = ColorSettings()
    try result.setProfile(ColorProfileWorkflowTests().profile(CGColorSpace.displayP3), for: .rgb)
    try result.setProfile(NativeModeProfile.standard(.cmyk, depth: .u16), for: .cmyk)
    try result.setProfile(XCTUnwrap(CGColorSpace(name: CGColorSpace.linearGray)?.copyICCData() as Data?), for: .grayscale)
    result.intent = .perceptual; result.blackPointCompensation = false
    return result
  }
  @MainActor func testPersistenceAllProfilesReloadAndNoOpRevision() throws {
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("nested/ColorSettings.json"), next = try settings()
    let store = ColorSettingsStore(url: url)
    XCTAssertNil(store.loadError); let original = store.revision
    try store.commit(next, revision: original)
    XCTAssertNotEqual(store.revision, original)
    let bytes = try Data(contentsOf: url), revision = store.revision
    try store.commit(next, revision: revision)
    XCTAssertEqual(store.revision, revision); XCTAssertEqual(try Data(contentsOf: url), bytes)
    let loaded = ColorSettingsStore(url: url)
    XCTAssertNil(loaded.loadError); XCTAssertEqual(loaded.value, next)
    for mode in ColorSettings.workingModes {
      for depth in mode.depths { try NativeModeProfile.validate(loaded.value.profile(mode, depth: depth), mode: mode, depth: depth) }
    }
  }
  @MainActor func testInvalidProfilesStaleExternalAndFailedWritePreserveBytes() throws {
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("ColorSettings.json"), next = try settings()
    let store = ColorSettingsStore(url: url), stale = store.revision
    try store.commit(next, revision: stale)
    let bytes = try Data(contentsOf: url)
    XCTAssertThrowsError(try store.commit(.init(), revision: stale))
    var invalid = next; invalid.workingRGB = next.workingCMYK
    XCTAssertThrowsError(try store.commit(invalid, revision: store.revision))
    XCTAssertThrowsError(try invalid.setProfile(Data([1,2,3]), for: .rgb))
    XCTAssertThrowsError(try invalid.setProfile(nil, for: .lab))
    let failing = ColorSettingsStore(url: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    XCTAssertThrowsError(try failing.commit(.init(), revision: failing.revision))
    XCTAssertEqual(failing.value, next); XCTAssertEqual(try Data(contentsOf: url), bytes)
    let external = ColorSettingsStore(url: url)
    try external.commit(.init(), revision: external.revision)
    let changed = try Data(contentsOf: url)
    XCTAssertThrowsError(try store.commit(.init(), revision: store.revision))
    XCTAssertEqual(try Data(contentsOf: url), changed); XCTAssertEqual(store.value, next)
    try Data("broken".utf8).write(to: url)
    let unreadable = ColorSettingsStore(url: url)
    XCTAssertNotNil(unreadable.loadError)
    XCTAssertThrowsError(try unreadable.commit(next, revision: unreadable.revision))
    XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
  }
  @MainActor func testDraftCancelAndStaleDialogCannotOverwriteAPI() throws {
    let store = ColorSettingsStore(), before = store.revision
    var draft: ColorSettingsDraft? = .init(store: store)
    draft?.value = try settings(); draft = nil
    XCTAssertEqual(store.value, ColorSettings()); XCTAssertEqual(store.revision, before)
    let stale = ColorSettingsDraft(store: store), winner = ColorSettingsDraft(store: store)
    winner.value = try settings(); XCTAssertTrue(winner.apply(), winner.error ?? "")
    stale.value.intent = .saturation
    XCTAssertFalse(stale.apply()); XCTAssertEqual(store.value, winner.value)
  }
  @MainActor func testNewDocumentWorkingSpacesCustomOverrideAndSnapshot() throws {
    let settings = try settings()
    for mode in DocumentColorMode.componentModes {
      let options = NewDocumentOptions(settings: settings)
      options.widthField.stringValue = "3"; options.heightField.stringValue = "2"
      options.modeMenu.selectItem(at: try XCTUnwrap(DocumentColorMode.componentModes.firstIndex(of: mode)))
      options.modeChanged()
      for depth in mode.depths {
        options.depthMenu.selectItem(at: try XCTUnwrap(PixelDepth.allCases.firstIndex(of: depth))); options.depthChanged()
        let doc = try options.document(name: "Working profile")
        XCTAssertEqual(try ColorProfileInput.effectiveProfile(doc), try settings.profile(mode, depth: depth))
      }
    }
    let store = ColorSettingsStore(); try store.commit(settings, revision: store.revision)
    let options = NewDocumentOptions(settings: store.value)
    options.widthField.stringValue = "3"; options.heightField.stringValue = "2"
    try store.commit(.init(), revision: store.revision)
    XCTAssertEqual(try ColorProfileInput.effectiveProfile(options.document(name: "Captured")), settings.workingRGB)
    let custom = try NativeModeProfile.standard(.rgb, depth: .u8)
    try options.setProfile(custom, name: "sRGB override")
    XCTAssertEqual(try ColorProfileInput.effectiveProfile(options.document(name: "Custom")), custom)
    options.resetProfile()
    XCTAssertEqual(try ColorProfileInput.effectiveProfile(options.document(name: "Reset")), settings.workingRGB)
  }
  @MainActor func testWorkspacesCaptureDefaultsAndDepthChangeRetainsDocumentProfile() async throws {
    let settings = try settings(), source = try ColorProfileWorkflowTests().fixture()
    let mode = try DocumentModeWorkspace(document: source, mode: .grayscale, depth: .u16, settings: settings)
    XCTAssertEqual(mode.request.conversion.profile, settings.workingGray)
    XCTAssertEqual(mode.request.conversion.intent, .perceptual)
    var p3 = source; p3.workingICC = settings.workingRGB
    let depth = try DocumentModeWorkspace(document: p3, mode: .rgb, depth: .f32, settings: .init())
    XCTAssertEqual(depth.request.conversion.profile, try settings.profile(.rgb, depth: .f32))
    let profile = try ColorProfileWorkspace(document: source, operation: .convert, settings: settings)
    XCTAssertEqual(profile.request.profile, settings.workingRGB)
    XCTAssertEqual(profile.request.intent, .perceptual); XCTAssertFalse(profile.request.blackPointCompensation)
    profile.refresh(); await profile.task?.value
    XCTAssertTrue(profile.ready, profile.error ?? "no preview")
    profile.close(); mode.close(); depth.close()
  }
  @MainActor func testHTTPPermissionsSchemaPersistenceAndStaleRevision() async throws {
    let helper = AutomationTests(), next = try settings(), route = ColorSettingsAPI.path
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = doc.store.document, preferences = service.controller.colorSettings
      let state = try await helper.request(service, path: route)
      XCTAssertEqual(state.0.statusCode, 200)
      let unauthorized = try await helper.request(service, path: route, authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      let body: [String: Any] = ["revision": preferences.revision.uuidString, "settings": ColorSettingsAPI.json(next)]
      service.setPhotoshopPreferenceChangesEnabled(true); service.setPreferenceChangesEnabled(true)
      let denied = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setColorSettingsChangesEnabled(true)
      for key in ["intent", "blackPointCompensation", "workingRGB", "extra"] {
        var bad = ColorSettingsAPI.json(next); bad[key] = 1
        let result = try await helper.request(service, path: route, body: ["revision": preferences.revision.uuidString, "settings": bad])
        XCTAssertEqual(result.0.statusCode, 400, key)
      }
      let updated = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(updated.0.statusCode, 200, String(decoding: updated.1, as: UTF8.self))
      XCTAssertEqual(preferences.value, next); XCTAssertEqual(doc.store.document, source)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let stale = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(stale.0.statusCode, 409)
      let caps = try await helper.request(service, path: "/v1/capabilities")
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any])
      XCTAssertEqual(json["colorSettingsChangesEnabled"] as? Bool, true)
      XCTAssertNotNil(json["colorSettings"])
      service.stop(); XCTAssertFalse(service.colorSettingsChangesEnabled)
    }
  }
  @MainActor func testModeDialogControlsRetainWorkingAndExplicitProfiles() async throws {
    let settings = try settings(), source = try ColorProfileWorkflowTests().fixture()
    let draft = try DocumentModeWorkspace(document: source, mode: .cmyk, depth: .u16, settings: settings)
    defer { draft.close() }
    draft.chooseMode(.grayscale); await draft.task?.value
    XCTAssertEqual(draft.request.conversion.profile, settings.workingGray)
    draft.chooseDepth(.f32); await draft.task?.value
    XCTAssertTrue(draft.ready, draft.error ?? "")
    XCTAssertEqual(draft.request.conversion.profile, try settings.profile(.grayscale, depth: .f32))
    draft.chooseMode(.rgb); await draft.task?.value
    // Returning to the source mode preserves the original document's profile.
    XCTAssertEqual(draft.request.conversion.profile, try NativeModeProfile.atDepth(ColorProfileInput.effectiveProfile(source), mode: .rgb, depth: .f32))
    draft.useWorkingProfile(); await draft.task?.value
    XCTAssertEqual(draft.request.conversion.profile, try settings.profile(.rgb, depth: .f32))
    draft.chooseDepth(.u16); await draft.task?.value
    XCTAssertEqual(draft.request.conversion.profile, try settings.profile(.rgb, depth: .f32))
    draft.useWorkingProfile(); await draft.task?.value
    XCTAssertEqual(draft.request.conversion.profile, settings.workingRGB)
  }
  @MainActor func testHTTPAndNativeConversionsShareSnapshotDefaultsAndUndo() async throws {
    let helper = AutomationTests(), settings = try settings()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let source = try ColorProfileWorkflowTests().fixture()
      document.store.session = EditorSession(document: source)
      try service.share(document)
      try service.controller.colorSettings.commit(settings, revision: service.controller.colorSettings.revision)
      document.store.beginColorProfile(.convert)
      let draft = try XCTUnwrap(document.store.colorProfileWorkspace), request = draft.request
      await draft.task?.value; XCTAssertTrue(draft.ready, draft.error ?? "")
      document.store.cancelColorProfile()
      let expected = try ColorProfileWorkflowTests().apply(request, source)
      let status = try await helper.edit(service, document, "document.convertProfile", ["profileBase64": request.profile.base64EncodedString()])
      XCTAssertEqual(status, 200); XCTAssertEqual(document.store.document, expected)
      let undone = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undone, 200); XCTAssertEqual(document.store.document, source)
      let untagged = try await helper.edit(service, document, "document.assignProfile", ["removeProfile": true])
      XCTAssertEqual(untagged, 200); XCTAssertEqual(document.store.document.layers, source.layers)
      XCTAssertEqual(document.store.document.workingICC, settings.workingRGB)
      XCTAssertEqual(document.store.document.profileIsUntagged, true)
      let gray = try await helper.edit(service, document, "document.convertMode", ["mode": "grayscale", "depth": 16])
      XCTAssertEqual(gray, 200); XCTAssertEqual(document.store.document.modeDescriptor?.profile, settings.workingGray)
      let custom = try NativeModeProfile.standard(.rgb, depth: .u16)
      let override = try await helper.edit(service, document, "document.convertMode", ["mode": "rgb", "depth": 16, "profileBase64": custom.base64EncodedString(), "intent": "saturation"])
      XCTAssertEqual(override, 200); XCTAssertEqual(document.store.document.modeDescriptor?.profile, custom)
    }
  }
  @MainActor func testFactoryShortcutAndGlobalAvailability() throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { app, menu in
      let item = try XCTUnwrap(helper.allItems(menu).first { $0.identifier?.rawValue == "Edit > Color Settings…" })
      XCTAssertEqual(item.action, #selector(AppDelegate.colorSettingsDialog))
      XCTAssertEqual(item.keyEquivalent, "k"); XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
      XCTAssertTrue(app.validateMenuItem(item))
    }
  }
  func testSettingsBodyLimitIsScopedAndStatelessCommandDefaultsRemainStable() throws {
    let limit = ColorSettings.maximumArchiveBytes
    let header = "POST \(ColorSettingsAPI.path) HTTP/1.1\r\nContent-Length: \(limit)\r\n\r\n"
    XCTAssertNil(try AutomationRequest.parse(Data(header.utf8)))
    XCTAssertThrowsError(try AutomationRequest.parse(Data(header.replacingOccurrences(of: "\(limit)", with: "\(limit + 1)").utf8)))
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method: "POST", path: "/v1/preferences/photoshop-file-handling"), 65_536)
    let command = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": "document.convertMode", "revision": "test", "parameters": ["mode": "grayscale", "depth": 16]]))
    let request = try command.documentModeRequest()
    XCTAssertNil(request.conversion.profile); XCTAssertEqual(request.conversion.intent, .relativeColorimetric)
  }
}
