import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RestrictedModeWorkflowTests: XCTestCase {
  func source() throws -> CraftDocument { try DocumentModeConversionTests().fixture() }
  func indexed() throws -> CraftDocument {
    var document = try source()
    let raster = try IndexedRaster(width: 4, height: 3, palette: [.init(20, 30, 40), .init(20, 30, 40), .init(255, 255, 255)], indices: Data([0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]), transparentIndex: 2)
    document = try document.replacingRestrictedMode(.indexed(raster)); return document
  }
  func command(_ name: String, _ parameters: [String: Any]) throws -> AutomationCommand {
    try .init(data: JSONSerialization.data(withJSONObject: ["command": name, "revision": "test", "parameters": parameters]))
  }
  func testACTIndependentBytesAndValidation() throws {
    var data = Data(repeating: 0, count: 772)
    data.replaceSubrange(0..<9, with: [1, 2, 3, 1, 2, 3, 250, 251, 252])
    data.replaceSubrange(768..<772, with: [0, 3, 0, 1])
    let table = try ColorTableFile(data: data)
    XCTAssertEqual(table.colors, [.init(1, 2, 3), .init(1, 2, 3), .init(250, 251, 252)])
    XCTAssertEqual(table.transparentIndex, 1); XCTAssertEqual(try table.encoded(), data)
    XCTAssertEqual(try ColorTableFile(data: data.prefix(768)).colors.count, 256)
    XCTAssertThrowsError(try ColorTableFile(data: data + Data([0])))
    data[769] = 1; XCTAssertThrowsError(try ColorTableFile(data: data))
  }
  func testStrictSettingsAndIndexedIdentityAcrossHistoryAndFormats() throws {
    let original = try indexed()
    let edit = try command("indexed.colorTable.write", ["colors": [["red": 200, "green": 5, "blue": 6], ["red": 20, "green": 30, "blue": 40], ["red": 255, "green": 255, "blue": 255]]])
    var session = EditorSession(document: original)
    try session.execute(try XCTUnwrap(edit.nativeCommand(document: original)))
    guard case .indexed(let before) = original.restrictedMode, case .indexed(let after) = session.document.restrictedMode else { return XCTFail("No index storage") }
    XCTAssertEqual(after.indices, before.indices); XCTAssertEqual(after.transparentIndex, 2); XCTAssertNotEqual(after.palette, before.palette)
    for format in [DocumentIO.Format.native, .psd, .psb, .png, .tiff] {
      let data = try DocumentIO.encodeForPersistence(session.document, format: format)
      let reopened = format == .native ? try NativeArchive.decode(data) : [.psd, .psb].contains(format) ? try PSDCodec.read(data) : try RasterIO.read(data)
      XCTAssertEqual(reopened.restrictedMode, session.document.restrictedMode)
    }
    let changed = session.document; try session.undo(); XCTAssertEqual(session.document, original); try session.redo(); XCTAssertEqual(session.document, changed)
    for settings: [String: Any] in [["colors": 257], ["amount": -0.1], ["bogus": true], ["customPalette": [["red": 256, "green": 0, "blue": 0]]]] {
      XCTAssertThrowsError(try command("document.convertIndexed", ["settings": settings]).restrictedModeRequest(in: source()))
    }
    XCTAssertThrowsError(try command("document.convertBitmap", ["settings": ["pattern": ["width": 2, "height": 2, "samples": "AA=="]]]).restrictedModeRequest(in: source()))
  }
  @MainActor func testIndexedPreviewLocalHistoryCancelCommitAndStaleSource() async throws {
    let original = try source(), store = EditorStore(document: original)
    defer { store.cancelRestrictedMode(); store.renderTask?.cancel() }
    store.beginRestrictedMode(.indexed); let draft = try XCTUnwrap(store.restrictedModeWorkspace)
    await draft.task?.value; XCTAssertTrue(draft.ready, draft.error ?? "preview missing"); XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.hasToneDraft); XCTAssertFalse(store.canBeginDocumentMode)
    let first = draft.request; draft.update { $0.indexed.dither = .none; $0.indexed.colors = 16 }
    let next = draft.request; draft.undo(); XCTAssertEqual(draft.request, first); draft.redo(); XCTAssertEqual(draft.request, next)
    await draft.task?.value
    store.cancelRestrictedMode(); XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginRestrictedMode(.indexed); let commit = try XCTUnwrap(store.restrictedModeWorkspace); await commit.task?.value
    var expected = original; try commit.request.command(in: original).apply(to: &expected)
    store.commitRestrictedMode(); await commit.commitTask?.value
    XCTAssertNil(commit.error); XCTAssertNil(store.restrictedModeWorkspace); XCTAssertEqual(store.document, expected)
    XCTAssertNotNil(store.previousIndexedPalette); await store.undo(); XCTAssertEqual(store.document, original)
    store.beginRestrictedMode(.indexed); let stale = try XCTUnwrap(store.restrictedModeWorkspace); await stale.task?.value
    try store.session.execute(.renameLayer(original.layers[0].id, "Changed")); let changed = store.document
    store.commitRestrictedMode(); await stale.commitTask?.value
    XCTAssertNotNil(stale.error); XCTAssertEqual(store.document, changed)
  }
  @MainActor func testBitmapAndColorTablePreviewAndMergeConsent() async throws {
    let gray = try source().convertingMode(.init(mode: .grayscale, depth: .u8)), store = EditorStore(document: gray)
    defer { store.cancelRestrictedMode(); store.renderTask?.cancel() }
    XCTAssertTrue(store.canBeginRestrictedMode(.bitmap))
    store.beginRestrictedMode(.bitmap); let draft = try XCTUnwrap(store.restrictedModeWorkspace)
    draft.update { $0.bitmap.method = .halftone; $0.bitmap.outputResolution = gray.pixelsPerInch * 2 }
    await draft.task?.value; XCTAssertTrue(draft.ready, draft.error ?? "missing")
    store.commitRestrictedMode(); await draft.commitTask?.value
    XCTAssertEqual(store.document.bitsPerChannel, 1); XCTAssertEqual(store.document.width, 8)
    XCTAssertFalse(store.canEditChannels); XCTAssertFalse(store.canBeginRestrictedMode(.indexed))
    await store.undo(); XCTAssertEqual(store.document, gray)
    store.session = EditorSession(document: try indexed())
    store.beginRestrictedMode(.colorTable); let table = try XCTUnwrap(store.restrictedModeWorkspace)
    table.update { $0.colors[1] = .init(255, 0, 0) }; await table.task?.value
    XCTAssertTrue(table.ready, table.error ?? "missing")
    store.commitRestrictedMode(); await table.commitTask?.value; XCTAssertNil(table.error)
    guard case .indexed(let updated) = store.document.restrictedMode else { return XCTFail() }
    XCTAssertEqual(updated.indices, Data([0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2])); XCTAssertEqual(updated.palette[1], .init(255, 0, 0))
    var rich = try source(); rich.layers.append(Layer(name: "Fill", content: .fill(.white)))
    let merged = RestrictedModeWorkspace(document: rich, kind: .indexed); defer { merged.close() }
    merged.refresh(); await merged.task?.value; XCTAssertNotNil(merged.error)
    merged.update { $0.mergeVisible = true }; await merged.task?.value; XCTAssertTrue(merged.ready, merged.error ?? "missing")
  }
  @MainActor func testMenuBindingsHostedDialogsAndCloseCancellation() async throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { _, menu in
      for path in AppDelegate.restrictedModeMenus.keys {
        let item = try XCTUnwrap(helper.allItems(menu).first { $0.identifier?.rawValue == path })
        XCTAssertEqual(item.action, #selector(AppDelegate.restrictedModeDialog(_:))); XCTAssertEqual(item.keyEquivalent, "")
      }
    }
    let store = EditorStore(document: try source()); defer { store.renderTask?.cancel() }
    for kind in [RestrictedModeRequest.Kind.indexed, .bitmap, .colorTable] {
      let document = kind == .colorTable ? try indexed() : kind == .bitmap ? try source().convertingMode(.init(mode: .grayscale, depth: .u8)) : try source()
      let model = RestrictedModeWorkspace(document: document, kind: kind); model.refresh(); await model.task?.value
      XCTAssertTrue(model.ready, model.error ?? "missing preview")
      let view = NSHostingView(rootView: RestrictedModeSheet(store: store, model: model))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua); window.contentView = view
      view.frame = NSRect(x: 0, y: 0, width: 880, height: 620); view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
      defer { window.close() }
      XCTAssertLessThanOrEqual(view.fittingSize.width, 880); XCTAssertLessThanOrEqual(view.fittingSize.height, 620)
      let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/runs/20261028T101734Z-221-indexed-bitmap")
      if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: path.appendingPathComponent("controls-\(kind.rawValue)-\(UUID()).png")) } }
      model.close()
    }
    let doc = CraftNSDocument(model: try source()); doc.store.beginRestrictedMode(.indexed)
    let draft = try XCTUnwrap(doc.store.restrictedModeWorkspace); let task = draft.task; doc.close(); await task?.value
    XCTAssertNil(doc.store.restrictedModeWorkspace); XCTAssertFalse(draft.ready)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: RestrictedModeAPI.capabilities))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: store.documentModeState))
    XCTAssertEqual(RestrictedModeAPI.commands.count, 6)
  }
  @MainActor func testHTTPMatchesNativeAndReadsWritesPreserveIndices() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); document.store.session = EditorSession(document: try self.source())
      let original = document.store.document
      var expected = original; try RestrictedModeRequest(.indexed).command(in: original).apply(to: &expected)
      let converted = try await helper.edit(service, document, "document.convertIndexed")
      XCTAssertEqual(converted, 200); XCTAssertEqual(document.store.document, expected); XCTAssertNotNil(document.store.previousIndexedPalette)
      let share = try XCTUnwrap(service.shares.first)
      let table = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "indexed.colorTable.read", "revision": service.revision(document.store), "parameters": [:]])
      XCTAssertEqual(table.0.statusCode, 200)
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: table.1) as? [String: Any]); XCTAssertNotNil(object["actBase64"])
      let before = document.store.document
      let unchanged = try await helper.edit(service, document, "indexed.colorTable.write", ["actBase64": try XCTUnwrap(object["actBase64"] as? String)])
      XCTAssertEqual(unchanged, 200); XCTAssertEqual(document.store.document, before)
      let written = try await helper.edit(service, document, "indexed.indices.write", ["offset": 0, "values": [0, 0, 0]])
      XCTAssertEqual(written, 200)
      let read = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "indexed.indices.read", "revision": service.revision(document.store), "parameters": ["offset": 0, "count": 3]])
      XCTAssertEqual(read.0.statusCode, 200)
      XCTAssertEqual((try JSONSerialization.jsonObject(with: read.1) as? [String: Any])?["values"] as? [Int], [0, 0, 0])
      let invalid = try await helper.edit(service, document, "indexed.indices.write", ["values": [255]])
      XCTAssertEqual(invalid, 400)
      let stale = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "indexed.indices.write", "revision": "old", "parameters": ["values": [0]]])
      XCTAssertEqual(stale.0.statusCode, 409)
      document.store.beginRestrictedMode(.colorTable); await document.store.restrictedModeWorkspace?.task?.value
      let busy = try await helper.edit(service, document, "indexed.indices.write", ["values": [0]])
      XCTAssertEqual(busy, 409); document.store.cancelRestrictedMode()
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document, before)
      let gray = try await helper.edit(service, document, "document.convertMode", ["mode": "grayscale", "depth": 8]); XCTAssertEqual(gray, 200)
      let bitmap = try await helper.edit(service, document, "document.convertBitmap", ["settings": ["method": "threshold"]]); XCTAssertEqual(bitmap, 200)
      XCTAssertEqual(document.store.document.bitsPerChannel, 1)
    }
  }
  @MainActor func testRememberedOptionsAdaptButExplicitOptionsStillReject() throws {
    let doc = CraftNSDocument(model: try indexed()); defer { doc.close() }
    let options = RasterEncodingOptions(tiffPredictor: true, tiffLayers: true)
    doc.rememberedEncodingOptions[.tiff] = options
    let adapted = doc.compatibleRememberedEncodingOptions[.tiff]!
    XCTAssertEqual(adapted.tiffLayers, false); XCTAssertEqual(adapted.tiffPredictor, false)
    XCTAssertEqual(doc.rememberedEncodingOptions[.tiff], options)
    XCTAssertNoThrow(try DocumentIO.encodeForPersistence(doc.store.document, format: .tiff, options: adapted))
    XCTAssertThrowsError(try DocumentIO.encodeForPersistence(doc.store.document, format: .tiff, options: options))
  }
  @MainActor func testSharedMasterPaletteMatchesNativeAndRejectsStaleOrChangingSources() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: try self.source()); try service.share(document)
      let other = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 100, height: 100, background: Pixel(0.8, 0.2, 0.4)))
      other.ownerController = service.controller; service.controller.addDocument(other); try service.share(other)
      defer { other.updateChangeCount(.changeCleared); other.close() }
      let share = try XCTUnwrap(service.shares.first { $0.document === other })
      let original = document.store.document
      var settings = IndexedColorSettings(); settings.palette = .masterSelective; settings.colors = 16
      var expected = original; try RestrictedModeInput.indexed(settings, in: original, masterDocuments: [other.store.document]).apply(to: &expected)
      func parameters(_ revision: String) -> [String: Any] { ["settings": ["palette": "masterSelective", "colors": 16], "sources": [["id": share.id.uuidString, "revision": revision]]] }
      let stale = try await helper.edit(service, document, "document.convertIndexed", parameters("old")); XCTAssertEqual(stale, 409); XCTAssertEqual(document.store.document, original)
      let success = try await helper.edit(service, document, "document.convertIndexed", parameters(service.revision(other.store)))
      XCTAssertEqual(success, 200); XCTAssertEqual(document.store.document, expected)
      await document.store.undo(); XCTAssertEqual(document.store.document, original)
      let revision = service.revision(other.store)
      let mutation = Task { @MainActor in
        for _ in 0..<10000 {
          if document.store.geometryBusy {
            try other.store.session.execute(.renameLayer(other.store.document.layers[0].id, "Changed master")); return
          }
          await Task.yield()
        }
        XCTFail("Conversion did not enter prepared worker")
      }
      let changed = try await helper.edit(service, document, "document.convertIndexed", parameters(revision))
      try await mutation.value
      XCTAssertEqual(changed, 409); XCTAssertEqual(document.store.document, original)
    }
  }
  func testIndexWritesRejectMissingEntriesAndLocksWithoutMutation() throws {
    let original = try indexed()
    for parameters: [String: Any] in [["offset": 12, "values": [0]], ["values": [3]], ["values": [0.5]], ["values": []]] {
      XCTAssertThrowsError(try command("indexed.indices.write", parameters).indexedWrite(in: original))
    }
    var locked = original; locked.layers[0].locked = true
    XCTAssertThrowsError(try command("indexed.indices.write", ["values": [0]]).indexedWrite(in: locked))
    XCTAssertEqual(locked.restrictedMode, original.restrictedMode)
    let remove = try command("indexed.colorTable.write", ["colors": [["red": 0, "green": 0, "blue": 0]]])
    XCTAssertThrowsError(try remove.nativeCommand(document: original))
  }

}
