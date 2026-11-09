import AppKit
import Foundation
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LensDefaultWorkflowTests: XCTestCase {
  func identity(_ focal: Double = 24, make: String = "Owned", model: String = "Camera", lens: String = "Lens", aperture: Double = 2.8) throws -> CameraLensIdentity {
    try .init(cameraMake: make, cameraModel: model, lensModel: lens, focalLength: focal, fNumber: aperture)
  }
  func settings(_ amount: Double = 20) -> LensCorrectionSettings {
    var s = LensCorrectionSettings(); s.distortion = amount; s.redCyan = 10; return s
  }
  func fixture(_ depth: PixelDepth = .u8, smart: Bool = false, camera: CameraLensIdentity? = nil) throws -> CraftDocument {
    var d = try LensCorrectionWorkflowTests().fixture(depth, smart: smart)
    do {
      let c = try camera ?? identity()
      let tags: [String: Any] = ["{TIFF}": ["Make": c.cameraMake, "Model": c.cameraModel], "{Exif}": ["LensModel": c.lensModel, "FocalLength": c.focalLength, "FNumber": c.fNumber]]
      d.sourceMetadata = ["imageIOProperties": try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)]
    }; return d
  }
  @MainActor func stop(_ store: EditorStore) { store.cancelFilter(); store.geometryTask?.cancel(); store.renderTask?.cancel() }
  func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("owned-lens452-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
  }
  @MainActor func testActualStartupFactoryUsesPersistentLibrariesAndKeepsOwnedSessionsIsolated() {
    _ = NSApplication.shared
    let isolated = PhotatoApp.makeDelegate(isolatedSession: true)
    XCTAssertNil(isolated.controller.filterRecall.lensDefaults.directory)
    XCTAssertNil(isolated.controller.filterRecall.liquifyMeshes.persistenceURL)
    let production = PhotatoApp.makeDelegate(isolatedSession: false)
    XCTAssertTrue(production.controller.filterRecall.lensDefaults === LensDefaultLibrary.shared)
    XCTAssertTrue(production.controller.filterRecall.liquifyMeshes === LiquifyMeshLibrary.shared)
    XCTAssertNotNil(production.controller.filterRecall.lensDefaults.directory)
    XCTAssertNotNil(production.controller.filterRecall.liquifyMeshes.persistenceURL)
    let nextOwned = PhotatoApp.makeDelegate(isolatedSession: true)
    XCTAssertFalse(nextOwned.controller.filterRecall.lensDefaults === LensDefaultLibrary.shared)
    XCTAssertNil(nextOwned.controller.filterRecall.lensDefaults.directory)
    XCTAssertNil(nextOwned.controller.filterRecall.liquifyMeshes.persistenceURL)
  }
  @MainActor func testPersistentExactMatchingEveryIdentityFieldAndNoEntryCountLimit() throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let library = LensDefaultLibrary(directory: root), c = try identity(), s = settings()
    try library.set(s, for: c); XCTAssertEqual(LensDefaultLibrary(directory: root).lookup(c).settings, s)
    for other in [try identity(25), try identity(make: "Other"), try identity(model: "Other"), try identity(lens: "Other"), try identity(aperture: 4)] {
      XCTAssertNil(library.lookup(other).settings)
    }
    for i in 1...80 { try library.set(settings(Double(i)), for: identity(Double(i))) }
    let restored = LensDefaultLibrary(directory: root)
    for i in 1...80 { XCTAssertEqual(restored.lookup(try identity(Double(i))).settings, settings(Double(i))) }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.count, 80)
    try restored.remove(c); XCTAssertNil(LensDefaultLibrary(directory: root).lookup(c).settings)
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Retired").path).isEmpty)
  }
  @MainActor func testCorruptOversizeMismatchedRecordPreservationAndAtomicWriteFailure() throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let c = try identity(), path = try XCTUnwrap(LensDefaultLibrary(directory: root).fileURL(for: c))
    for data in [Data("broken".utf8), Data(repeating: 0, count: 32769)] {
      try data.write(to: path); let library = LensDefaultLibrary(directory: root), before = try Data(contentsOf: path)
      XCTAssertNotNil(library.lookup(c).error); XCTAssertThrowsError(try library.set(settings(), for: c)); XCTAssertEqual(try Data(contentsOf: path), before)
      try library.remove(c); try library.set(settings(), for: c); XCTAssertEqual(library.lookup(c).settings, settings())
    }
    let other = try identity(35), lib = LensDefaultLibrary(directory: root)
    try lib.set(settings(30), for: other)
    try Data(contentsOf: XCTUnwrap(lib.fileURL(for: other))).write(to: path)
    XCTAssertNotNil(LensDefaultLibrary(directory: root).lookup(c).error)
    let blocked = root.appendingPathComponent("blocked"); try Data([1,2,3]).write(to: blocked)
    let failure = LensDefaultLibrary(directory: blocked), rev = failure.revision
    XCTAssertThrowsError(try failure.set(settings(), for: c)); XCTAssertNil(failure.lookup(c).settings); XCTAssertEqual(failure.revision, rev)
    XCTAssertEqual(try Data(contentsOf: blocked), Data([1,2,3]))
  }
  @MainActor func testPreviousConversionOnlySuccessfulPublicationPersistsAndRetries() async throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let library = LensDefaultLibrary(directory: root), store = EditorStore(document: try fixture())
    defer { stop(store) }; store.filterRecall = FilterRecall(lensDefaults: library)
    store.beginFilter(.lensCorrection); store.filterDraft?.filter.lens = settings(); store.cancelFilter(); XCTAssertNil(library.previous)
    var filter = RasterFilter(.lensCorrection); filter.lens = settings()
    try store.executeEditorCommand(.applyFilter(store.document.layers[0].id, filter))
    XCTAssertEqual(library.previous, settings()); XCTAssertEqual(LensDefaultLibrary(directory: root).previous, settings())
    try store.executeEditorCommand(.applyFilter(store.document.layers[0].id, RasterFilter(.blur))); XCTAssertEqual(library.previous, settings())
    var bad = filter; bad.lens?.scale = .nan
    XCTAssertThrowsError(try store.executeEditorCommand(.applyFilter(store.document.layers[0].id, bad))); XCTAssertEqual(library.previous, settings())
    await store.undo(); await store.redo(); XCTAssertEqual(library.previous, settings())
    let blocked = root.appendingPathComponent("blocked"); try Data([9]).write(to: blocked)
    let retry = LensDefaultLibrary(directory: blocked); retry.remember(settings()); XCTAssertNotNil(retry.previousError)
    let rev = retry.revision; try FileManager.default.removeItem(at: blocked); retry.remember(settings())
    XCTAssertNil(retry.previousError); XCTAssertNotEqual(retry.revision, rev); XCTAssertEqual(LensDefaultLibrary(directory: blocked).previous, settings())
  }
  @MainActor func testUnreadablePreviousIsPreservedAndNativePreferenceFailureDoesNotBlockEditing() throws {
    let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("PreviousConversion.json"), data = Data("owned invalid previous".utf8)
    try data.write(to: file); let library = LensDefaultLibrary(directory: root); library.remember(settings())
    XCTAssertEqual(library.previous, settings()); XCTAssertNotNil(library.previousError); XCTAssertEqual(try Data(contentsOf: file), data)
    let store = EditorStore(document: try fixture()), model = LensCorrectionWorkspace(); defer { stop(store) }
    var d = store.document; d.sourceMetadata = nil; store.session = EditorSession(document: d)
    model.saveLensDefault(in: store); XCTAssertNotNil(model.preferenceError); XCTAssertNil(model.error)
    XCTAssertTrue(store.session.undoStack.isEmpty); XCTAssertEqual(store.document, d)
  }
  @MainActor func testNativeDefaultsLocalHistoryCancelAndDocumentUndoAllDepths() async throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth), store = EditorStore(document: d), model = LensCorrectionWorkspace(), c = try identity()
      defer { model.close(); stop(store) }
      try store.setLensDefault(settings()); XCTAssertEqual(store.document, d); XCTAssertTrue(store.session.undoStack.isEmpty)
      store.beginFilter(.lensCorrection); XCTAssertEqual(store.filterDraft?.filter.lens, settings())
      await model.prepare(document: d, draft: try XCTUnwrap(store.filterDraft)); XCTAssertTrue(model.ready, model.error ?? "not ready")
      model.change(settings(40)); await model.task?.value
      model.loadLensDefault(from: store); await model.task?.value; XCTAssertEqual(model.settings, settings())
      model.undo(); await model.task?.value; XCTAssertEqual(model.settings, settings(40))
      model.redo(); await model.task?.value; XCTAssertEqual(model.settings, settings())
      model.saveLensDefault(in: store); store.cancelFilter(); XCTAssertEqual(store.filterRecall.lensDefaults.lookup(c).settings, settings()); XCTAssertEqual(store.document, d)
      store.beginFilter(.lensCorrection); store.commitFilter(); await store.geometryTask?.value
      XCTAssertNil(store.error); var expected = d, f = RasterFilter(.lensCorrection); f.lens = settings()
      try Command.applyFilter(d.layers[0].id, f).apply(to: &expected); XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
      await store.undo(); XCTAssertEqual(store.document, d); await store.redo(); XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.filterRecall.lensDefaults.previous, settings())
      await store.undo(); store.beginFilter(.lensCorrection)
      await model.prepare(document: d, draft: try XCTUnwrap(store.filterDraft)); model.change(.init()); await model.task?.value
      model.loadPreviousConversion(from: store); await model.task?.value; XCTAssertEqual(model.settings, settings())
      try store.removeLensDefault(); XCTAssertEqual(store.document, d); store.cancelFilter()
    }
  }
  @MainActor func testControllerSharingDetachmentMetadataCacheAndExplicitSmartRecallPayload() throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let first = CraftNSDocument(model: try fixture()), second = CraftNSDocument(model: try fixture(.u16))
    controller.addDocument(first); controller.addDocument(second)
    defer { stop(first.store); stop(second.store); if controller.documents.contains(where: { $0 === first }) { controller.removeDocument(first) }; controller.removeDocument(second) }
    try first.store.setLensDefault(settings()); second.store.beginFilter(.lensCorrection); XCTAssertEqual(second.store.filterDraft?.filter.lens, settings()); second.store.cancelFilter()
    controller.removeDocument(first); try first.store.setLensDefault(settings(40))
    XCTAssertEqual(second.store.filterRecall.lensDefaults.lookup(try identity()).settings, settings())
    var changed = try fixture(camera: identity(35)); first.store.session = EditorSession(document: changed); XCTAssertEqual(first.store.cameraLensIdentity, try identity(35))
    changed.sourceMetadata = ["imageIOProperties": Data([1])]; first.store.session = EditorSession(document: changed); XCTAssertNil(first.store.cameraLensIdentity); XCTAssertNotNil(first.store.cameraLensMetadataCache.error)
    let smart = try fixture(smart: true), store = EditorStore(document: smart); defer { stop(store) }
    try store.setLensDefault(settings(40)); var f = RasterFilter(.lensCorrection); f.lens = settings()
    try store.executeEditorCommand(.applyFilter(smart.layers[0].id, f))
    XCTAssertEqual(store.document.layers[0].smartFilters?.filters.first?.filter.lens, settings())
    store.repeatLastFilter(showDialog: true); XCTAssertEqual(store.filterDraft?.filter.lens, settings()); store.cancelFilter()
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(store.document)), store.document)
  }
  @MainActor func testHTTPAuthorizationStateReplayStaleBusyRevokedAndInvalidRequests() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, document in
      let d = try self.fixture(), store = document.store; store.session = EditorSession(document: d); try service.share(document)
      @MainActor func expect(_ expected: Int, _ name: String, _ parameters: [String: Any] = [:], revision: String? = nil) async throws {
        let code = try await AutomationTests().edit(service, document, name, parameters, revision: revision)
        XCTAssertEqual(code, expected)
      }
      let params: [String: Any] = ["operation": "set", "settings": ["distortion": 20, "redCyan": 10]]
      try await expect(403, LensDefaultsAPI.name, params)
      service.setPreferenceChangesEnabled(true); let oldRevision = service.revision(store)
      try await expect(200, LensDefaultsAPI.name, params)
      XCTAssertNotEqual(service.revision(store), oldRevision); XCTAssertEqual(store.document, d); XCTAssertTrue(store.session.undoStack.isEmpty)
      let share = try XCTUnwrap(service.shares.first?.id)
      let response = try await h.request(service, path: "/v1/documents/\(share)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let lens = try XCTUnwrap(state["lensCorrection"] as? [String: Any]), defaults = try XCTUnwrap(lens["defaults"] as? [String: Any])
      let settings = try XCTUnwrap(defaults["settings"] as? [String: Any])
      XCTAssertEqual(settings["distortion"] as? Double, 20)
      let decoded = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: defaults))
      XCTAssertNoThrow(try BrushAPI.merge(decoded, schema: LensDefaultsAPI.stateSchema))
      try await expect(409, LensDefaultsAPI.name, ["operation": "remove"], revision: oldRevision)
      store.beginFilter(.lensCorrection); try await expect(409, LensDefaultsAPI.name, params); store.cancelFilter()
      for bad: [String: Any] in [["operation": "set"], ["operation": "remove", "settings": [:]], ["operation": "set", "settings": ["scale": true]], ["operation": "bogus"], ["operation": "set", "settings": ["unknown": 1]]] {
        try await expect(400, LensDefaultsAPI.name, bad)
      }
      var expected = d, f = RasterFilter(.lensCorrection); f.lens = self.settings(); try Command.applyFilter(d.layers[0].id, f).apply(to: &expected)
      try await expect(200, "filter.apply", ["layerID": d.layers[0].id.uuidString, "filter": ["kind": "lensCorrection", "lens": settings]])
      XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.filterRecall.lensDefaults.previous, self.settings())
      try await expect(200, "history.undo"); XCTAssertEqual(store.document, d)
      try await expect(200, LensDefaultsAPI.name, ["operation": "remove"])
      XCTAssertNil(store.filterRecall.lensDefaults.lookup(try self.identity()).settings)
      service.setPreferenceChangesEnabled(false); try await expect(403, LensDefaultsAPI.name, params)
      service.revoke(share)
      let revoked = try await h.request(service, path: "/v1/documents/\(share)/commands", body: ["command": LensDefaultsAPI.name, "revision": service.revision(store), "parameters": params])
      XCTAssertEqual(revoked.0.statusCode, 404)
    }
  }
  @MainActor func testSettingsMenuOffscreenAndMachineDiscovery() async throws {
    let store = EditorStore(document: try fixture()), model = LensCorrectionWorkspace(); defer { model.close(); stop(store) }
    try store.setLensDefault(settings()); store.beginFilter(.lensCorrection)
    await model.prepare(document: store.document, draft: try XCTUnwrap(store.filterDraft))
    for scheme in [ColorScheme.light, .dark] {
      let view = NSHostingView(rootView: LensCorrectionSheet(store: store, model: model).environment(\.colorScheme, scheme))
      view.frame = NSRect(x: 0, y: 0, width: 940, height: 720); view.layoutSubtreeIfNeeded()
      XCTAssertGreaterThan(view.fittingSize.width, 800)
      if let raw = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: raw).appendingPathComponent("lens-defaults-\(scheme).png")) }
      }
    }
    XCTAssertEqual(AutomationCommand.definitions.count, 267); XCTAssertEqual(ActionLibraryFile.maximumVersion, 61)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: LensDefaultsAPI.capabilities))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: LensDefaultsAPI.commandSchema))

  }
}
