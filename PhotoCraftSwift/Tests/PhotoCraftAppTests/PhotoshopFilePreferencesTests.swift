import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PhotoshopFilePreferencesTests: XCTestCase {
  let route = "/v1/preferences/photoshop-file-handling"
  @MainActor func fixture(_ depth: PixelDepth = .u16) throws
    -> (URL, RecoveryPreferencesStore, CraftDocumentController, CraftNSDocument) {
    let (folder, preferences, controller) = try RecentDocumentsTests().fixture()
    // This test owns cleanup; the helper instance's teardown is not run by XCTest.
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let document = CraftNSDocument(model: try DocumentSaveWorkflowTests().fixture(depth: depth))
    controller.addDocument(document)
    return (folder, preferences, controller, document)
  }
  @MainActor func set(_ disabled: Bool, _ controller: CraftDocumentController) throws {
    let draft = RecoveryPreferencesDraft(controller: controller)
    draft.value.disablePSDCompression = disabled
    XCTAssertTrue(draft.apply(), draft.error ?? "")
  }
  @MainActor func testLegacyMigrationReloadAndRecentUpdatesPreserveAllSettings() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for version in [1, 2] {
      let url = folder.appendingPathComponent("v\(version).json")
      let bytes = Data("""
        {"version":\(version),"recovery":{"enabled":false,"intervalMinutes":30,"recentFileLimit":7},"recentDocuments":[]}
        """.utf8)
      try bytes.write(to: url)
      let preferences = RecoveryPreferencesStore(url: url)
      XCTAssertNil(preferences.loadError)
      XCTAssertFalse(preferences.value.disablePSDCompression)
      XCTAssertEqual(try Data(contentsOf: url), bytes)
      var next = preferences.value; next.disablePSDCompression = true
      try preferences.commit(next, revision: preferences.revision)
      let model = try DocumentSaveWorkflowTests().fixture()
      let file = folder.appendingPathComponent("recent\(version).photato")
      try NativeArchive.write(model, to: file)
      preferences.remember(file)
      let loaded = RecoveryPreferencesStore(url: url)
      XCTAssertNil(loaded.loadError)
      XCTAssertEqual(loaded.value, next)
      XCTAssertEqual(loaded.recentDocuments, preferences.recentDocuments)
      XCTAssertEqual(loaded.recentDocuments.count, 1)
      let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      XCTAssertEqual(raw["version"] as? Int, 4)
      XCTAssertEqual(try NativeArchive.read(file), model)
    }
  }
  @MainActor func testNativeDefaultsFollowPreferenceWithoutStickySaveChoicesAtAllDepths() async throws {
    for depth in PixelDepth.allCases {
      let (folder, preferences, controller, doc) = try fixture(depth)
      defer { doc.close() }
      let model = doc.store.document
      for disabled in [true, false, true] {
        try set(disabled, controller)
        for format in [DocumentIO.Format.psd, .psb] {
          let target = folder.appendingPathComponent("default." + format.rawValue)
          let expected: RasterEncodingOptions = disabled && depth != .u8
            ? .init(psdLayerCompression: .raw, psdCompositeCompression: .raw) : .init()
          let panel = NSSavePanel()
          XCTAssertTrue(doc.prepareSavePanel(panel))
          let accessory = try XCTUnwrap(doc.saveAccessory)
          accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of: format)))
          accessory.updateFormat()
          XCTAssertTrue(accessory.encodingOptions.isEmpty)
          XCTAssertEqual(accessory.psdLayerCompression.itemTitle(at: 0),
            disabled && depth != .u8 ? "Default (None — File Handling)" : "Default (ZIP with Prediction)")
          try await DocumentSaveWorkflowTests().save(doc, to: target, format: format)
          XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(model, format: format, options: expected))
          XCTAssertEqual(doc.rememberedEncodingOptions[format], .init())
          XCTAssertEqual(try doc.data(ofType: format.typeIdentifier),
            try DocumentIO.encode(model, format: format, options: expected))
          XCTAssertEqual(doc.store.document, model)
          XCTAssertTrue(doc.store.session.undoStack.isEmpty)
          XCTAssertFalse(doc.isDocumentEdited)
        }
        XCTAssertEqual(RecoveryPreferencesStore(url: folder.appendingPathComponent("FileHandling.json")).value,
          preferences.value)
      }
    }
  }
  @MainActor func testOrdinarySaveReevaluatesDefaultAndExplicitOptionsStayAuthoritative() async throws {
    let (folder, _, controller, doc) = try fixture(.f32); defer { doc.close() }
    let target = folder.appendingPathComponent("ordinary.psb")
    try await doc.persistDocument(to: target, format: .psb, operation: .saveAsOperation)
    let compressed = try Data(contentsOf: target)
    try set(true, controller)
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .psb, operation: .saveOperation)
    let raw = try Data(contentsOf: target)
    XCTAssertNotEqual(raw, compressed)
    XCTAssertEqual(raw, try DocumentIO.encode(doc.store.document, format: .psb,
      options: .init(psdLayerCompression: .raw, psdCompositeCompression: .raw)))
    try set(false, controller)
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .psb, operation: .saveOperation)
    XCTAssertEqual(try Data(contentsOf: target), compressed)
    let explicit = RasterEncodingOptions(psdLayerCompression: .rle, psdCompositeCompression: .zip)
    try await doc.persistDocument(to: target, format: .psb, operation: .saveAsOperation, options: explicit)
    try set(true, controller)
    try await DocumentSaveWorkflowTests().save(doc, to: target, format: .psb, operation: .saveOperation)
    XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(doc.store.document, format: .psb, options: explicit))
    XCTAssertEqual(doc.rememberedEncodingOptions[.psb], explicit)
  }
  @MainActor func testCopyPartialOverrideAndOtherFormatsDoNotMutateSaveSettingsOrHistory() async throws {
    let (folder, _, controller, doc) = try fixture()
    defer { doc.close() }
    try set(true, controller)
    let model = doc.store.document
    for format in DocumentIO.Format.allCases where format != .jpeg {
      let target = folder.appendingPathComponent("copy." + format.rawValue)
      let options: RasterEncodingOptions = format == .psd || format == .psb
        ? .init(psdLayerCompression: .zip) : .init()
      let expected: RasterEncodingOptions = format == .psd || format == .psb
        ? .init(psdLayerCompression: .zip, psdCompositeCompression: .raw) : .init()
      try await doc.copyDocument(to: target, format: format, options: options)
      XCTAssertEqual(try Data(contentsOf: target), try DocumentIO.encode(model, format: format, options: expected))
    }
    XCTAssertNil(doc.fileURL)
    XCTAssertTrue(doc.rememberedEncodingOptions.isEmpty)
    XCTAssertEqual(doc.store.document, model)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }
  @MainActor func testCancelStaleBusyAndPersistenceFailureKeepArchiveAndDocumentState() throws {
    let (folder, preferences, controller, doc) = try fixture()
    defer { doc.close() }
    let cancelled = RecoveryPreferencesDraft(controller: controller)
    cancelled.value.disablePSDCompression = true
    XCTAssertFalse(preferences.value.disablePSDCompression)
    try set(true, controller)
    XCTAssertFalse(cancelled.apply())
    let url = folder.appendingPathComponent("FileHandling.json")
    let bytes = try Data(contentsOf: url), revision = preferences.revision
    for copyPanel in [false, true] {
      doc.fileOperationBusy = !copyPanel
      if copyPanel { doc.copyPanel = NSSavePanel() }
      let blocked = RecoveryPreferencesDraft(controller: controller)
      blocked.value.disablePSDCompression = false
      XCTAssertFalse(blocked.apply())
      XCTAssertEqual(preferences.revision, revision)
      doc.fileOperationBusy = false; doc.copyPanel = nil
    }
    let failing = RecoveryPreferencesStore(url: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
    var next = failing.value; next.disablePSDCompression = false
    XCTAssertThrowsError(try failing.commit(next, revision: failing.revision))
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertTrue(failing.value.disablePSDCompression)
    let external = RecoveryPreferencesStore(url: url)
    try external.commit(next, revision: external.revision)
    let changed = try Data(contentsOf: url)
    XCTAssertThrowsError(try preferences.commit(next, revision: revision))
    XCTAssertEqual(try Data(contentsOf: url), changed)
    XCTAssertTrue(preferences.value.disablePSDCompression)
    XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPSeparatePermissionStrictSchemaStaleAndRecoveryIsolation() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      let preferences = service.controller.recoveryPreferences
      let original = doc.store.document
      let state = try await helper.request(service, path: route)
      XCTAssertEqual(state.0.statusCode, 200)
      let unauthorized = try await helper.request(service, path: route, authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      service.setPreferenceChangesEnabled(true)
      var body: [String: Any] = ["revision": preferences.revision.uuidString, "disablePSDCompression": true]
      let denied = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setPhotoshopPreferenceChangesEnabled(true)
      for (key, value) in [("disablePSDCompression", 1 as Any), ("revision", "bad" as Any), ("unknown", false as Any)] {
        var bad = body; bad[key] = value
        let invalid = try await helper.request(service, path: route, body: bad)
        XCTAssertEqual(invalid.0.statusCode, 400)
      }
      let media = try await helper.request(service, path: route, body: body, headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      doc.fileOperationBusy = true
      let busy = try await helper.request(service, path: route, body: body)
      doc.fileOperationBusy = false
      XCTAssertEqual(busy.0.statusCode, 409)
      let accepted = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(accepted.0.statusCode, 200)
      let stale = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(stale.0.statusCode, 409)
      let recovery = try await helper.request(service, path: "/v1/preferences/recovery",
        body: ["revision": preferences.revision.uuidString, "enabled": false, "intervalMinutes": 15])
      XCTAssertEqual(recovery.0.statusCode, 200)
      XCTAssertTrue(preferences.value.disablePSDCompression)
      service.setRecentFilesEnabled(true)
      let recent = try await helper.request(service, path: "/v1/recent-documents/limit",
        body: ["revision": preferences.recentRevision.uuidString, "limit": 7])
      XCTAssertEqual(recent.0.statusCode, 200)
      XCTAssertTrue(preferences.value.disablePSDCompression)
      body["revision"] = preferences.revision.uuidString; body["disablePSDCompression"] = false
      let reset = try await helper.request(service, path: route, body: body)
      XCTAssertEqual(reset.0.statusCode, 200)
      XCTAssertEqual(preferences.value, .init(enabled: false, intervalMinutes: 15, recentFileLimit: 7))
      XCTAssertEqual(doc.store.document, original)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let schema = try XCTUnwrap(AutomationService.photoshopFilePreferencesCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(service.photoshopFilePreferencesState.keys))
      service.stop()
      XCTAssertFalse(service.photoshopPreferenceChangesEnabled)
      service.setPhotoshopPreferenceChangesEnabled(true)
      XCTAssertFalse(service.photoshopPreferenceChangesEnabled)
    }
  }
  @MainActor func testHTTPSharedDownloadsAndSaveUseNativePreference() async throws {
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let doc = CraftNSDocument(model: try DocumentSaveWorkflowTests().fixture(depth: .f32))
      service.controller.addDocument(doc); defer { doc.close() }
      try set(true, service.controller)
      service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder); try service.share(doc)
      let id = try XCTUnwrap(service.shares.first?.id)
      for format in [DocumentIO.Format.psd, .psb] {
        let result = try await helper.request(service, path: "/v1/documents/\(id)/file.\(format.rawValue)")
        XCTAssertEqual(result.0.statusCode, 200)
        XCTAssertEqual(result.1, try DocumentIO.encode(doc.store.document, format: format,
          options: .init(psdLayerCompression: .raw, psdCompositeCompression: .raw)))
        let explicit = try await helper.request(service, path: "/v1/documents/\(id)/file.\(format.rawValue)",
          headers: ["X-Photato-Export-Options": #"{"psdLayerCompression":"rle","psdCompositeCompression":"zip"}"#])
        XCTAssertEqual(explicit.0.statusCode, 200)
        XCTAssertEqual(explicit.1, try DocumentIO.encode(doc.store.document, format: format,
          options: .init(psdLayerCompression: .rle, psdCompositeCompression: .zip)))
      }
      let saved = try await helper.edit(service, doc, "document.saveAs",
        ["name": "default", "format": "psb", "replace": false])
      XCTAssertEqual(saved, 200)
      XCTAssertEqual(doc.rememberedEncodingOptions[.psb], .init())
      XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("default.psb")),
        try DocumentIO.encode(doc.store.document, format: .psb,
          options: .init(psdLayerCompression: .raw, psdCompositeCompression: .raw)))
      let state = service.state(try XCTUnwrap(service.shares.first), document: doc)
      let effective = try XCTUnwrap(state["effectiveSaveEncodingOptions"] as? [String: [String: Any]])
      XCTAssertEqual(effective["psb"]?["psdLayerCompression"] as? String, "raw")
      XCTAssertFalse(DocumentEncodingOptions.json(doc.rememberedEncodingOptions[.psb]!).keys.contains("psdLayerCompression"))
    }
  }
  private struct Transport: AdobeResourceTransport {
    let bytes: Data
    func fetch(_ url: URL) async throws -> Data { bytes }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {
      throw CraftError.invalid("No external upload in this owned preference test.")
    }
  }
  @MainActor func testBothHTTPJobInterfacesKeepOutputContractWithPreferenceEnabled() async throws {
    let bytes = try PSDCodec.writeRasterLayers(DocumentSaveWorkflowTests().fixture(depth: .u16))
    let model = try AdobeActionAssets.decode(bytes)
    let helper = AutomationEncodingOptionsTests()
    try await AutomationTests().withService(pressedMouseButtons: { 0 },
      resourceTransport: Transport(bytes: bytes)) { service, _ in
      try set(true, service.controller)
      service.setResourceJobsEnabled(true)
      let request = helper.body(outputs: [helper.output("image/vnd.adobe.photoshop")])
      for route in ["/v1/action-jobs", "/v2/execute-actions"] {
        let data = try await helper.outputs(service, route: route, payload: request)
        XCTAssertEqual(data, [try PSDCodec.writeRasterLayers(model)])
        XCTAssertNotEqual(data[0], try DocumentIO.encode(model, format: .psd,
          options: .init(psdLayerCompression: .raw, psdCompositeCompression: .raw)))
      }
    }
  }
  @MainActor func testHTTPUnreadableAndWriteFailureDoNotPublishPreference() async throws {
    for unreadable in [false, true] {
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let url = folder.appendingPathComponent("settings.json")
      if unreadable { try Data("invalid".utf8).write(to: url) }
      let preferences = RecoveryPreferencesStore(url: url) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
      try await AutomationTests().withService(recoveryPreferences: preferences) { service, _ in
        service.setPhotoshopPreferenceChangesEnabled(true)
        let response = try await AutomationTests().request(service, path: route,
          body: ["revision": preferences.revision.uuidString, "disablePSDCompression": true])
        XCTAssertEqual(response.0.statusCode, 422)
        XCTAssertFalse(preferences.value.disablePSDCompression)
        if unreadable { XCTAssertEqual(try Data(contentsOf: url), Data("invalid".utf8)) }
        else { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
      }
    }
  }
}
