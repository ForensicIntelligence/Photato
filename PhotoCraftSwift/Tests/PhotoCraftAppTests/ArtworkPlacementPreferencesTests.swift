import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ArtworkPlacementPreferencesTests: XCTestCase {
  @MainActor func testGeneralMenuAndPersistentDefaults() throws {
    let domain = "Photato.PlacementTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = ArtworkPlacementPreferences(defaults: defaults)
    XCTAssertEqual(preferences.settings, ArtworkPlacementSettings())
    let initialRevision = preferences.revision
    let unchanged = preferences.settings
    preferences.settings = unchanged
    XCTAssertEqual(preferences.revision, initialRevision)
    preferences.settings = ArtworkPlacementSettings(resizeImageDuringPlace: false,
      skipTransformWhenPlacing: true, alwaysCreateSmartObjectsWhenPlacing: false)
    XCTAssertNotEqual(preferences.revision, initialRevision)
    XCTAssertEqual(ArtworkPlacementPreferences(defaults: defaults).settings, preferences.settings)

    let app = NSApplication.shared
    let originalMenu = app.mainMenu
    let delegate = AppDelegate(workspaces: WorkspaceLibrary(), artworkPlacementPreferences: preferences)
    defer {
      delegate.generalPlacementPreferencesWindow?.close()
      app.mainMenu = originalMenu
    }
    delegate.buildMenus()
    let item = try XCTUnwrap(app.mainMenu?.item(withTitle: "Photato")?.submenu?
      .item(withTitle: "Settings…")?.submenu?.item(withTitle: "General…"))
    XCTAssertEqual(item.action, #selector(AppDelegate.generalPlacementPreferences))
    XCTAssertEqual(item.keyEquivalent, "k")
    XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    XCTAssertTrue(delegate.validateMenuItem(item))
    delegate.generalPlacementPreferences()
    XCTAssertEqual(delegate.generalPlacementPreferencesWindow?.window?.title, "Settings — General")
    XCTAssertTrue(delegate.controller.artworkPlacementPreferences === preferences)
  }

  @MainActor func testSkipTransformAndResizeFitSwitchInOneUndo() async throws {
    let helper = EmbeddedPlacementWorkflowTests()
    let root = try helper.folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("Artwork.png")
    let bytes = try DocumentIO.encode(helper.fixture(), format: .png)
    try bytes.write(to: url)
    let original = try CraftDocument(width: 4, height: 3)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    var changes = 0
    store.onChange = { _ in changes += 1 }

    store.artworkPlacementPreferences.settings.skipTransformWhenPlacing = true
    store.placeEmbeddedSource(url)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.transformDraft)
    XCTAssertNil(store.embeddedPlacement)
    let fitted = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(fitted.smartObject?.data, bytes)
    XCTAssertEqual(try fitted.coordinateTransform.bounds(width: 8, height: 6), IntRect(x: 0, y: 0, width: 4, height: 3))
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(changes, 1)
    await store.undo()
    XCTAssertEqual(store.document, original)

    store.artworkPlacementPreferences.settings.resizeImageDuringPlace = false
    store.placeEmbeddedSource(url)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.transformDraft)
    let unscaled = try XCTUnwrap(store.activeLayer)
    XCTAssertEqual(try unscaled.coordinateTransform.bounds(width: 8, height: 6), IntRect(x: -2, y: -1, width: 8, height: 6))
    XCTAssertEqual(unscaled.smartObject?.data, bytes)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    let placed = store.document
    await store.undo()
    XCTAssertEqual(store.document, original)
    await store.redo()
    XCTAssertEqual(store.document, placed)
  }

  @MainActor func testRasterPlacementCapturesSettingsAndMatchesExplicitHTTPGeometry() async throws {
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, parent in
      let helper = EmbeddedPlacementWorkflowTests()
      let root = try helper.folder()
      defer { try? FileManager.default.removeItem(at: root) }
      let url = root.appendingPathComponent("Artwork.png")
      let bytes = try DocumentIO.encode(helper.fixture(), format: .png)
      try bytes.write(to: url)
      let store = parent.store
      let original = store.document
      try service.share(parent)
      service.setDocumentTransfersEnabled(true)
      store.artworkPlacementPreferences.settings.alwaysCreateSmartObjectsWhenPlacing = false
      store.placeEmbeddedSource(url)
      await store.geometryTask?.value
      var draft = try XCTUnwrap(store.transformDraft)
      XCTAssertNotNil(store.activeLayer?.smartObject)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.session.undoStack.count, 0)
      draft.centerX += 1
      store.updateTransform(draft)
      let delta = BrushAPI.json(draft.delta)
      store.artworkPlacementPreferences.settings.alwaysCreateSmartObjectsWhenPlacing = true
      store.commitTransform()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      let native = try XCTUnwrap(store.activeLayer)
      XCTAssertNil(native.smartObject)
      XCTAssertNil(native.affine)
      XCTAssertEqual(store.session.undoStack.count, 1)
      let nativePixels = try Renderer.composite(store.document).rgbaData(depth: .u8)
      await store.undo()
      XCTAssertEqual(store.document, original)
      let response = try await helper.upload(service, parent, bytes, options: ["rasterize": true, "transform": delta])
      XCTAssertEqual(response.0.statusCode, 200, String(decoding: response.1, as: UTF8.self))
      let automation = try XCTUnwrap(store.activeLayer)
      XCTAssertNil(automation.smartObject)
      XCTAssertEqual(automation.content, native.content)
      XCTAssertEqual(automation.coordinateTransform, native.coordinateTransform)
      XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8), nativePixels)
      XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo()

      store.artworkPlacementPreferences.settings = ArtworkPlacementSettings(resizeImageDuringPlace: false,
        skipTransformWhenPlacing: true, alwaysCreateSmartObjectsWhenPlacing: false)
      let legacy = try await helper.upload(service, parent, bytes)
      XCTAssertEqual(legacy.0.statusCode, 200)
      XCTAssertEqual(store.activeLayer?.smartObject?.data, bytes)
      XCTAssertEqual(store.activeLayer?.coordinateTransform.a, 0.5)
    }
  }

  @MainActor func testPDFSkipTransformStillHonorsChooserAndCanCommitPixels() async throws {
    let helper = PDFPlacementWorkflowTests()
    let original = try CraftDocument(width: 120, height: 90)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    store.artworkPlacementPreferences.settings = ArtworkPlacementSettings(
      skipTransformWhenPlacing: true, alwaysCreateSmartObjectsWhenPlacing: false)

    helper.select(store, cancel: true)
    store.placePDF(helper.fixture())
    await store.geometryTask?.value
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)

    helper.select(store)
    store.placePDF(helper.fixture())
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.transformDraft)
    XCTAssertNil(store.activeLayer?.smartObject)
    XCTAssertEqual(store.session.undoStack.count, 1)

    var expected = original
    let options = try PDFSmartObjectAPI.options(#"{"crop":"media","antialias":false,"rasterize":true}"#)
    try PDFSmartObjectAPI.prepare(Data(contentsOf: helper.fixture()), helper.fixture().lastPathComponent,
      original, options).apply(to: &expected)
    XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth: .u8),
      try Renderer.composite(expected).rgbaData(depth: .u8))
    XCTAssertThrowsError(try PDFSmartObjectAPI.options(#"{"rasterize":1}"#))
    let uuid = UUID()
    XCTAssertThrowsError(try PDFSmartObjectAPI.options("{\"layerID\":\"\(uuid)\",\"rasterize\":true}"))
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("{\"layerID\":\"\(uuid)\",\"rasterize\":true}"))
    XCTAssertThrowsError(try EmbeddedSourceAPI.options("{\"frameID\":\"\(uuid)\",\"rasterize\":false}"))
    XCTAssertThrowsError(try LinkedArtworkPlacementTests().parsed(["pdf": ["rasterize": true]]))
    await store.undo()
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testImmediateLinkedPlacementRetainsOriginalAndRevokedDraftCannotCommit() async throws {
    let helper = LinkedArtworkWorkflowTests()
    let root = try helper.folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("Linked.png")
    let bytes = try helper.artwork()
    try bytes.write(to: url)
    let original = try CraftDocument(width: 4, height: 3)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel(); store.linkedSourceController?.stop() }
    store.linkedSourceRegistry = LinkedSourceRegistry(persistent: false)
    let grant = try store.linkedSourceRegistry.authorize(url)
    store.artworkPlacementPreferences.settings = ArtworkPlacementSettings(
      skipTransformWhenPlacing: true, alwaysCreateSmartObjectsWhenPlacing: false)
    store.placeEmbeddedSource(url, linkedGrant: grant)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertNil(store.embeddedPlacement)
    XCTAssertNil(store.transformDraft)
    XCTAssertEqual(store.activeLayer?.smartObject?.data, bytes)
    XCTAssertNotNil(store.activeLayer?.smartObject?.linkedSource)
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo()
    XCTAssertEqual(store.document, original)

    store.artworkPlacementPreferences.settings.skipTransformWhenPlacing = false
    store.placeEmbeddedSource(url, linkedGrant: grant)
    await store.geometryTask?.value
    XCTAssertNotNil(store.transformDraft)
    XCTAssertTrue(store.status.hasPrefix("Place Linked"))
    try store.linkedSourceRegistry.revoke(grant.id)
    store.commitTransform()
    await store.geometryTask?.value
    XCTAssertNotNil(store.error)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.cancelTransform()
  }

  @MainActor func testPreferencesHTTPRequiresPermissionAndCurrentRevision() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let path = AutomationService.placementPreferencesPath
      let initial = try await helper.request(service, path: path)
      XCTAssertEqual(initial.0.statusCode, 200)
      let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: initial.1) as? [String: Any])
      let revision = try XCTUnwrap(fields["revision"] as? String)
      XCTAssertEqual(fields["resizeImageDuringPlace"] as? Bool, true)
      XCTAssertEqual(fields["skipTransformWhenPlacing"] as? Bool, false)
      XCTAssertEqual(fields["alwaysCreateSmartObjectsWhenPlacing"] as? Bool, true)
      XCTAssertEqual(fields["canUpdate"] as? Bool, false)
      let unauthenticated = try await helper.request(service, path: path, authenticate: false)
      XCTAssertEqual(unauthenticated.0.statusCode, 401)
      let blocked = try await helper.request(service, path: path, body: [
        "revision": revision, "skipTransformWhenPlacing": true])
      XCTAssertEqual(blocked.0.statusCode, 403)
      service.setPhotoshopPreferenceChangesEnabled(true)
      let stillBlocked = try await helper.request(service, path: path, body: [
        "revision": revision, "skipTransformWhenPlacing": true])
      XCTAssertEqual(stillBlocked.0.statusCode, 403)
      service.setPlacementPreferenceChangesEnabled(true)
      let invalid = try await helper.request(service, path: path, body: [
        "revision": revision, "resizeImageDuringPlace": false, "alwaysCreateSmartObjectsWhenPlacing": 1])
      XCTAssertEqual(invalid.0.statusCode, 400)
      XCTAssertEqual(document.store.artworkPlacementPreferences.settings, ArtworkPlacementSettings())
      let edited = try await helper.request(service, path: path, body: [
        "revision": revision, "resizeImageDuringPlace": false, "skipTransformWhenPlacing": true])
      XCTAssertEqual(edited.0.statusCode, 200)
      XCTAssertFalse(document.store.artworkPlacementPreferences.settings.resizeImageDuringPlace)
      XCTAssertTrue(document.store.artworkPlacementPreferences.settings.skipTransformWhenPlacing)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let stale = try await helper.request(service, path: path, body: [
        "revision": revision, "skipTransformWhenPlacing": false])
      XCTAssertEqual(stale.0.statusCode, 409)
      let capabilities = try await helper.request(service, path: "/v1/capabilities")
      let contract = try XCTUnwrap(JSONSerialization.jsonObject(with: capabilities.1) as? [String: Any])
      XCTAssertNotNil(contract["placementPreferences"])
      XCTAssertEqual(contract["placementPreferenceChangesEnabled"] as? Bool, true)
      service.stop()
      XCTAssertFalse(service.placementPreferenceChangesEnabled)
      XCTAssertTrue(document.store.artworkPlacementPreferences.settings.skipTransformWhenPlacing)
    }
  }
}
