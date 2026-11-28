import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class CameraRawPreferencesTests: XCTestCase {
  @MainActor func testCameraRawSettingsMenuAndPersistentStorageChoice() throws {
    let domain = "Photato.CameraRawTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = CameraRawPreferences(defaults: defaults)
    XCTAssertEqual(preferences.dngStorage, .embedXMP)
    let revision = preferences.revision
    preferences.dngStorage = .ignoreSidecarXMP
    XCTAssertNotEqual(preferences.revision, revision)
    XCTAssertEqual(CameraRawPreferences(defaults: defaults).dngStorage, .ignoreSidecarXMP)

    let app = NSApplication.shared
    let oldMenu = app.mainMenu
    let delegate = AppDelegate(workspaces: WorkspaceLibrary(), cameraRawPreferences: preferences)
    defer {
      delegate.cameraRawPreferencesWindow?.close()
      app.mainMenu = oldMenu
    }
    delegate.buildMenus()
    let item = try XCTUnwrap(app.mainMenu?.item(withTitle: "Photato")?.submenu?
      .item(withTitle: "Settings…")?.submenu?.item(withTitle: "Camera Raw…"))
    XCTAssertEqual(item.action, #selector(AppDelegate.cameraRawPreferences))
    XCTAssertTrue(delegate.validateMenuItem(item))
    delegate.cameraRawPreferences()
    XCTAssertEqual(delegate.cameraRawPreferencesWindow?.window?.title, "Settings — Camera Raw")
    XCTAssertTrue(delegate.controller.cameraRawPreferences === preferences)
  }

  @MainActor func testAuthorizedCameraRawPreferencesControlFutureNativeAndAPISaves() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let original = try Data(contentsOf: root.appendingPathComponent("Fixtures/Raw/raw-with-embedded-xmp.dng"))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let raw = directory.appendingPathComponent("Local.dng")
    let sidecar = directory.appendingPathComponent("Local.xmp")
    try original.write(to: raw)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let route = AutomationService.cameraRawPreferencesPath
      let state = try await helper.request(service, path: route)
      XCTAssertEqual(state.0.statusCode, 200)
      let values = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      XCTAssertEqual(values["dngStorage"] as? String, "embedXMP")
      XCTAssertEqual(values["canUpdate"] as? Bool, false)
      let revision = try XCTUnwrap(values["revision"] as? String)
      let change = ["revision": revision, "dngStorage": "sidecarXMP"]

      let denied = try await helper.request(service, path: route, body: change)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setPhotoshopPreferenceChangesEnabled(true)
      let accepted = try await helper.request(service, path: route, body: change)
      XCTAssertEqual(accepted.0.statusCode, 200)
      let stale = try await helper.request(service, path: route, body: change)
      XCTAssertEqual(stale.0.statusCode, 409)
      let preferences = service.controller.cameraRawPreferences
      XCTAssertEqual(preferences.dngStorage, .sidecarXMP)

      let document: CraftNSDocument = try await withCheckedThrowingContinuation { continuation in
        do {
          try service.controller.documentOpening.begin([raw], display: false, completion: { opened, _, error in
            if let error { continuation.resume(throwing: error) }
            else if let document = opened as? CraftNSDocument { continuation.resume(returning: document) }
            else { continuation.resume(throwing: CraftError.invalid("Camera Raw document did not open.")) }
          })
        } catch { continuation.resume(throwing: error) }
      }
      defer { document.close() }
      let captured = try XCTUnwrap(document.localRawSource?.original)
      XCTAssertFalse(captured.savesInsideDNG)
      preferences.dngStorage = .ignoreSidecarXMP
      try service.share(document)
      let layer = try XCTUnwrap(document.store.document.activeLayerID)
      service.setDocumentSavesEnabled(true)
      let developed = try await helper.edit(service, document, "raw.develop",
        ["layerID": layer.uuidString, "settings": ["adjustments": ["exposure": 1.75]]], timeout: 30)
      XCTAssertEqual(developed, 200)
      let saved = try await helper.edit(service, document, "raw.saveSourceSettings", ["layerID": layer.uuidString])
      XCTAssertEqual(saved, 200)
      XCTAssertEqual(try Data(contentsOf: raw), original)
      XCTAssertEqual(try RawSourceIO.relatedSettings(for: raw)?.adjustments.exposure, 1.75)
    }
  }
}
