import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class FileInfoWorkflowTests: XCTestCase {
  @MainActor func testNativeDraftCancelCommitNoOpHistoryAndStaleGuards() async throws {
    let original = try CraftDocument(width: 5, height: 3), store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    store.beginFileInfo(); let cancelled = try XCTUnwrap(store.fileInfoDraft); cancelled.info.title = "Discarded"
    XCTAssertTrue(store.hasToneDraft); XCTAssertFalse(store.canEditFileInfo); XCTAssertEqual(store.document, original)
    store.fileInfoDraft = nil; XCTAssertEqual(store.document, original)
    store.beginFileInfo(); let draft = try XCTUnwrap(store.fileInfoDraft); draft.info.title = "Native title"; draft.keywords = "one; two"; store.commitFileInfo(draft)
    XCTAssertNil(store.fileInfoDraft); XCTAssertNil(store.error); XCTAssertEqual(try FileInfoMetadata.read(store.document).title, "Native title")
    let edited = store.document; XCTAssertEqual(edited.layers, original.layers)
    try await store.navigateHistory(redo: false); XCTAssertEqual(store.document, original)
    try await store.navigateHistory(redo: true); XCTAssertEqual(store.document, edited)
    store.beginFileInfo(); store.commitFileInfo(try XCTUnwrap(store.fileInfoDraft)); XCTAssertEqual(store.document, edited)
    store.beginFileInfo(); let stale = try XCTUnwrap(store.fileInfoDraft); stale.info.title = "Stale"
    var changed = edited; changed.name = "Other revision"; store.session = EditorSession(document: changed)
    store.commitFileInfo(stale); XCTAssertNotNil(stale.error); XCTAssertEqual(store.document, changed); store.fileInfoDraft = nil
    store.geometryBusy = true; store.beginFileInfo(); XCTAssertNil(store.fileInfoDraft); store.geometryBusy = false
  }
  @MainActor func testAPIReadPatchNoOpUndoAndInvalidBusyStaleRequests() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); let id = try XCTUnwrap(service.shares.first?.id), original = document.store.document
      @MainActor func command(_ parameters: [String: Any], revision: String? = nil) async throws -> (HTTPURLResponse, Data) {
        try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "file.info", "revision": revision ?? service.revision(document.store), "parameters": parameters])
      }
      let read = try await command([:]); XCTAssertEqual(read.0.statusCode, 200); XCTAssertEqual(document.store.document, original)
      var info = FileInformation(); info.title = "API <title>"; info.author = "One; Two"; info.keywords = ["one", "two"]
      let expected = try FileInfoMetadata.applying(info, fields: ["title", "author", "keywords"], to: original)
      let patch = try await command(["title": info.title, "author": info.author, "keywords": info.keywords]); XCTAssertEqual(patch.0.statusCode, 200, String(decoding: patch.1, as: UTF8.self)); XCTAssertEqual(document.store.document, expected)
      let revision = service.revision(document.store), same = try await command(["title": info.title]); XCTAssertEqual(same.0.statusCode, 200); XCTAssertEqual(service.revision(document.store), revision)
      for parameters: [String: Any] in [["copyrightStatus": "bad"], ["title": 12], ["keywords": [12]], ["unexpected": "x"], ["title": "bad\0title"]] {
        let invalid = try await command(parameters); XCTAssertEqual(invalid.0.statusCode, 400); XCTAssertEqual(document.store.document, expected)
      }
      let stale = try await command(["title": "stale"], revision: "stale"); XCTAssertEqual(stale.0.statusCode, 409)
      document.store.beginFileInfo(); let busy = try await command(["title": "busy"]); XCTAssertEqual(busy.0.statusCode, 409); document.store.fileInfoDraft = nil
      let undo = try await helper.request(service, path: "/v1/documents/\(id)/commands", body: ["command": "history.undo", "revision": service.revision(document.store), "parameters": [:]])
      XCTAssertEqual(undo.0.statusCode, 200); XCTAssertEqual(document.store.document, original)
      XCTAssertNotNil(AutomationService.capabilities["fileInfo"])
    }
  }
  @MainActor func testFileInfoIgnoresActiveAlphaAndComponentEditingTargets() throws {
    var document = try CraftDocument(width: 5, height: 3)
    let alpha = try AlphaChannel(name: "Owned alpha", pixels: Surface(width: 5, height: 3, fill: .white))
    document.alphaChannels = [alpha]
    let store = EditorStore(document: document); defer { store.renderTask?.cancel() }; try store.selectAlphaChannel(alpha.id)
    store.beginFileInfo(); let draft = try XCTUnwrap(store.fileInfoDraft); draft.info.title = "Channel-independent"; store.commitFileInfo(draft)
    XCTAssertNil(store.error); XCTAssertNil(store.fileInfoDraft); XCTAssertEqual(store.document.alphaChannels, document.alphaChannels)
    XCTAssertEqual(try FileInfoMetadata.read(store.document).title, "Channel-independent")
  }
  @MainActor func testSourceMetadataImportAndNativePSDDownloadsShareDesktopCode() async throws {
    let helper = AutomationTests(), io = DocumentIOWorkflowTests()
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/FileInfo")
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      defer { PSDAuxiliaryWorkflowTests().cleanup(service.controller) }
      service.setDocumentTransfersEnabled(true)
      let response = try await io.request(service, path: "/v1/documents/import", data: Data(contentsOf: folder.appendingPathComponent("info-u16.pcraft")), type: PcraftImport.mediaType)
      XCTAssertEqual(response.0.statusCode, 201, String(decoding: response.1, as: UTF8.self))
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any]), id = try XCTUnwrap(state["id"] as? String)
      let document = try XCTUnwrap(service.shares.first?.document), original = document.store.document
      XCTAssertEqual(try FileInfoMetadata.read(original).title, "Night <Sky>")
      XCTAssertNotNil(state["fileInfo"])
      let native = try await helper.request(service, path: "/v1/documents/\(id)/file.photato", headers: ["X-Photato-Archive-Version": "78"])
      XCTAssertEqual(native.0.statusCode, 200); XCTAssertEqual(try NativeArchive.decode(native.1), original)
      let psd = try await helper.request(service, path: "/v1/documents/\(id)/file.psd")
      XCTAssertEqual(psd.0.statusCode, 200); XCTAssertEqual(psd.1, try DocumentIO.encode(original, format: .psd))
      XCTAssertEqual(try FileInfoMetadata.read(PSDCodec.read(psd.1)), try FileInfoMetadata.read(original))
      XCTAssertEqual(document.store.document, original)
    }
  }
  @MainActor func testFactoryMenuAndShortcutBindTheNativeDialog() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.title == "File Info…" })
      XCTAssertEqual(item.action, #selector(AppDelegate.fileInfoDialog)); XCTAssertEqual(item.keyEquivalent, "i")
      XCTAssertEqual(item.keyEquivalentModifierMask, [.option, .shift, .command])
    }
  }
}
