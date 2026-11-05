import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SkyRenameTests: XCTestCase {
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("photato-sky-rename-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor func prepared(_ document: CraftDocument, library: SkyLibrary) async -> SkyWorkspace {
    let model = SkyWorkspace(document: document, library: library)
    await model.prepare(); await model.task?.value; await model.task?.value
    return model
  }
  @MainActor func testNativeRenameMatchesHTTPAndPersistenceWithoutChangingPixelsOrHistory() async throws {
    for depth in PixelDepth.allCases {
      let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
      let nativeURL = folder.appendingPathComponent("native/skies.plist"), apiURL = folder.appendingPathComponent("api/skies.plist")
      let preset = SkyPreset(name: "Sunset", data: try RasterIO.encoded(SkyWorkflowTests().sky()))
      let nativeLibrary = SkyLibrary(persistenceURL: nativeURL), apiLibrary = SkyLibrary(persistenceURL: apiURL)
      try nativeLibrary.add(preset); try apiLibrary.add(preset)
      let original = try SkyWorkflowTests().photo(depth: depth)
      let native = EditorStore(document: original, actions: ActionLibrary(), skies: nativeLibrary)
      defer { native.cancelSkyReplacement(); native.renderTask?.cancel() }
      native.beginSkyReplacement(); let model = try XCTUnwrap(native.skyWorkspace)
      await model.task?.value; await model.task?.value
      let before = try Renderer.composite(XCTUnwrap(model.edit).result), localHistory = model.undoStates
      XCTAssertTrue(model.canRenameSky); model.beginSkyRename(); let draft = try XCTUnwrap(model.renameDraft)
      XCTAssertEqual(draft.name, preset.name); XCTAssertFalse(model.canCommit)
      XCTAssertEqual(native.skyState["libraryRenameOpen"] as? Bool, true)
      let unchanged = try Data(contentsOf: nativeURL)
      draft.name = "Cancelled"; model.cancelSkyRename(draft)
      XCTAssertEqual(try Data(contentsOf: nativeURL), unchanged); XCTAssertEqual(nativeLibrary.skies, [preset])
      model.beginSkyRename(); let edit = try XCTUnwrap(model.renameDraft); edit.name = "夕焼け — Sunset 2026"
      XCTAssertTrue(model.confirmSkyRename(edit)); await model.task?.value
      XCTAssertNil(model.renameDraft); XCTAssertEqual(nativeLibrary.skies[0].id, preset.id)
      XCTAssertEqual(nativeLibrary.skies[0].data, preset.data); XCTAssertEqual(nativeLibrary.skies[0].name, edit.name)
      XCTAssertEqual(SkyLibrary(persistenceURL: nativeURL).skies, nativeLibrary.skies)
      XCTAssertEqual(try Renderer.composite(XCTUnwrap(model.edit).result), before)
      XCTAssertTrue(try XCTUnwrap(model.edit).result.layers.contains { $0.name == edit.name })
      XCTAssertEqual(model.undoStates, localHistory); XCTAssertEqual(native.document, original); XCTAssertTrue(native.session.undoStack.isEmpty)
      let helper = AutomationTests()
      try await helper.withService(skies: apiLibrary, pressedMouseButtons: { 0 }) { service, document in
        document.store.session = EditorSession(document: original); try service.share(document)
        let renamed = try await helper.edit(service, document, "sky.library", ["operation": "rename", "skyID": preset.id.uuidString, "name": edit.name])
        XCTAssertEqual(renamed, 200); XCTAssertEqual(apiLibrary.skies, nativeLibrary.skies)
        XCTAssertEqual(try Data(contentsOf: apiURL), try Data(contentsOf: nativeURL))
        XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
        let stale = try await helper.edit(service, document, "sky.library", ["operation": "rename", "skyID": preset.id.uuidString, "name": "stale"], revision: "stale")
        XCTAssertEqual(stale, 409)
      }
      native.cancelSkyReplacement(); XCTAssertEqual(native.document, original)
      XCTAssertEqual(SkyLibrary(persistenceURL: nativeURL).skies[0].name, edit.name)
      XCTAssertEqual(native.skyState["libraryRenameOpen"] as? Bool, false)
    }
  }
  @MainActor func testInvalidNamesAndFailedStoragePreserveLibraryAndAllowRetry() async throws {
    let folder = try directory(); defer { try? FileManager.default.removeItem(at: folder) }
    let parent = folder.appendingPathComponent("library"), url = parent.appendingPathComponent("skies.plist")
    let library = SkyLibrary(persistenceURL: url), preset = SkyPreset(name: "Original", data: try RasterIO.encoded(SkyWorkflowTests().sky()))
    try library.add(preset)
    let model = try await prepared(SkyWorkflowTests().photo(), library: library); defer { model.close() }
    model.beginSkyRename(); let draft = try XCTUnwrap(model.renameDraft), data = try Data(contentsOf: url)
    let revision = library.revision
    for invalid in ["", "   ", String(repeating: "🙂", count: 128)] {
      draft.name = invalid; XCTAssertFalse(model.confirmSkyRename(draft)); XCTAssertNotNil(draft.error)
      XCTAssertTrue(model.renameDraft === draft); XCTAssertEqual(library.skies, [preset]); XCTAssertEqual(library.revision, revision)
      XCTAssertEqual(try Data(contentsOf: url), data)
    }
    let saved = folder.appendingPathComponent("preserved")
    try FileManager.default.moveItem(at: parent, to: saved)
    try Data("blocked parent".utf8).write(to: parent)
    draft.name = "Renamed"; XCTAssertFalse(model.confirmSkyRename(draft)); XCTAssertNotNil(draft.error)
    XCTAssertEqual(library.skies, [preset]); XCTAssertEqual(library.revision, revision)
    XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("skies.plist")), data)
    try FileManager.default.removeItem(at: parent); try FileManager.default.moveItem(at: saved, to: parent)
    XCTAssertTrue(model.confirmSkyRename(draft)); XCTAssertEqual(library.skies[0].name, "Renamed")
    XCTAssertEqual(library.skies[0].data, preset.data)
  }
  @MainActor func testStaleSelectionLibraryClosureAndDialogStateCannotRenameAnotherSky() async throws {
    let original = try SkyWorkflowTests().photo(), bytes = try RasterIO.encoded(SkyWorkflowTests().sky())
    for mode in ["selection", "settings", "revision", "remove", "closed", "superseded"] {
      let library = SkyLibrary(), first = SkyPreset(name: "One", data: bytes), second = SkyPreset(name: "Two", data: bytes)
      try library.add(first); try library.add(second)
      let model = await prepared(original, library: library); defer { model.close() }
      model.beginSkyRename(); let draft = try XCTUnwrap(model.renameDraft); draft.name = "Must not commit"
      switch mode {
      case "selection": model.chooseSky(second.id)
      case "settings": var state = model.state; state.settings.flip.toggle(); model.change(state)
      case "revision": try library.rename(second.id, "Concurrent")
      case "remove": try library.remove(first.id)
      case "closed": model.close()
      default: model.cancelSkyRename(draft); model.beginSkyRename()
      }
      let before = library.skies, revision = library.revision
      XCTAssertFalse(model.confirmSkyRename(draft), mode); XCTAssertEqual(library.skies, before, mode); XCTAssertEqual(library.revision, revision, mode)
    }
    let library = SkyLibrary(); try library.add(.init(name: "One", data: bytes))
    let model = await prepared(original, library: library); defer { model.close() }
    model.beginSkyRename(); let draft = try XCTUnwrap(model.renameDraft)
    let host = NSHostingView(rootView: SkyRenameSheet(model: model, draft: draft))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 180); host.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(host.fittingSize.width, 420); XCTAssertLessThanOrEqual(host.fittingSize.height, 220)
    let properties = try XCTUnwrap(SkyAPI.stateSchema["properties"] as? [String: Any])
    XCTAssertNotNil(properties["libraryRenameOpen"]); XCTAssertNotNil(properties["canRenameSelectedSky"])
    XCTAssertNotNil(SkyAPI.capabilities["nativeLibraryManagement"])
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: SkyAPI.capabilities))
    XCTAssertEqual(AutomationCommand.definitions.count, 249)
  }
}
