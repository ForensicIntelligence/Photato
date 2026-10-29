import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class InkModeControlsTests: XCTestCase {
  func source(_ mode: DocumentColorMode = .grayscale, depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 24, height: 16)
    var p = try Surface(width: 24, height: 16)
    for y in 0..<16 { for x in 0..<24 { let v = Float(x + y) / 38; p.setPixel(x: x, y: y, Pixel(v, v * 0.8, v * 0.6)) } }
    d.layers[0].content = .raster(p)
    return try d.convertingMode(.init(mode: mode, depth: depth))
  }
  func command(_ name: String, _ fields: [String: Any] = [:]) throws -> AutomationCommand {
    try .init(data: JSONSerialization.data(withJSONObject: ["command": name, "revision": "test", "parameters": fields]))
  }
  func settings() -> DuotoneSettings {
    .init(inks: [.init(name: "Black", color: .black), .init(name: "Rose", color: Pixel(0.8, 0.1, 0.4), curve: [.init(0, 0), .init(0.5, 0.2), .init(1, 0.7)])], overprints: [.init(mask: 3, color: Pixel(0.15, 0.02, 0.1))])
  }
  func testStrictInkSettingsAndStableConversionIdentities() throws {
    let original = try source(.cmyk, depth: .u16), r = InkModeRequest(.multichannel, document: original)
    var first = original, second = original
    try r.command(in: original).apply(to: &first); try r.command(in: original).apply(to: &second)
    XCTAssertTrue(first == second)
    guard case .multichannel(let raster) = first.inkMode else { return XCTFail() }
    XCTAssertEqual(raster.plates.map(\.id), r.plateIDs)
    let c = try command("document.convertMultichannel", ["plateIDs": r.plateIDs.map(\.uuidString)])
    var api = original; try XCTUnwrap(c.nativeCommand(document: original)).apply(to: &api); XCTAssertTrue(api == first)
    var bad = r; bad.plateIDs[1] = bad.plateIDs[0]; XCTAssertThrowsError(try bad.command(in: original))
    bad = r; bad.plateIDs.removeLast(); XCTAssertThrowsError(try bad.command(in: original))
    let ink = BrushAPI.json(DuotoneInk(name: "Black", color: .black)) as! [String: Any]
    for value: [String: Any] in [["bogus": true], ["inks": []], ["inks": [ink, ink]], ["overprints": [["mask": 1, "color": BrushAPI.json(Pixel.black)]]], ["inks": [["name": "", "color": BrushAPI.json(Pixel.black)]]], ["inks": [["name": "Ink", "color": BrushAPI.json(Pixel(0, 0, 0, 0.5))]]]] {
      XCTAssertThrowsError(try command("document.convertDuotone", ["settings": value]).inkModeRequest(in: source()))
    }
    let defaults = try command("document.convertDuotone", ["settings": ["inks": [["name": "Cyan", "color": BrushAPI.json(Pixel(0, 1, 1))]]]]).inkModeRequest(in: source())
    XCTAssertEqual(defaults.settings.inks[0].curve, [.init(0, 0), .init(1, 1)])
    XCTAssertNoThrow(try defaults.command(in: source()))
  }
  @MainActor func testPreviewInkControlsLocalHistoryPresetAndCancellation() async throws {
    let original = try source(), store = EditorStore(document: original)
    defer { store.cancelInkMode(); store.renderTask?.cancel() }
    store.beginInkMode(.duotone); let draft = try XCTUnwrap(store.inkModeWorkspace); await draft.task?.value
    XCTAssertTrue(draft.ready, draft.error ?? "preview missing"); XCTAssertTrue(store.document == original); XCTAssertTrue(store.hasToneDraft)
    draft.update { $0.settings = settings() }; await draft.task?.value
    let two = draft.request; XCTAssertTrue(draft.ready, draft.error ?? "missing")
    let saved = try draft.settingsData(); draft.setInkCount(1); XCTAssertTrue(draft.request.settings.overprints.isEmpty)
    draft.undo(); XCTAssertEqual(draft.request, two); draft.redo(); XCTAssertEqual(draft.request.settings.inks.count, 1)
    try draft.loadSettings(saved); XCTAssertEqual(draft.request, two)
    XCTAssertThrowsError(try draft.loadSettings(Data("{\"inks\":[]}".utf8))); XCTAssertEqual(draft.request, two)
    draft.setInkCount(4); XCTAssertEqual(draft.request.settings.inks.count, 4); await draft.task?.value; XCTAssertTrue(draft.ready, draft.error ?? "missing")
    XCTAssertEqual(store.inkModeState["workspace"] as? String, "duotone")
    store.cancelInkMode(); await draft.task?.value
    XCTAssertFalse(draft.ready); XCTAssertTrue(store.document == original); XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testCommitSettingsPreservesGrayUndoAndStaleSource() async throws {
    let original = try source(), store = EditorStore(document: original)
    defer { store.cancelInkMode(); store.renderTask?.cancel() }
    store.beginInkMode(.duotone); let draft = try XCTUnwrap(store.inkModeWorkspace)
    draft.update { $0.settings = settings() }; await draft.task?.value
    var expected = original; try draft.request.command(in: original).apply(to: &expected)
    store.commitInkMode(); await draft.commitTask?.value
    XCTAssertNil(draft.error); XCTAssertTrue(store.document == expected); XCTAssertNil(store.inkModeWorkspace)
    guard case .duotone(let before) = store.document.inkMode else { return XCTFail() }
    store.beginInkMode(.duotone); let edit = try XCTUnwrap(store.inkModeWorkspace)
    edit.update { $0.settings.inks[1].name = "Pink"; $0.settings.inks[1].curve[1].output = 0.8 }; await edit.task?.value
    store.commitInkMode(); await edit.commitTask?.value
    guard case .duotone(let after) = store.document.inkMode else { return XCTFail() }
    XCTAssertEqual(after.gray, before.gray); XCTAssertNotEqual(after.settings, before.settings)
    let reopened = try NativeArchive.decode(NativeArchive.encodeChunked(store.document)); XCTAssertTrue(reopened == store.document)
    await store.undo(); XCTAssertTrue(store.document == expected); await store.undo(); XCTAssertTrue(store.document == original)
    store.beginInkMode(.duotone); let stale = try XCTUnwrap(store.inkModeWorkspace); await stale.task?.value
    try store.session.execute(.renameLayer(original.layers[0].id, "Changed source")); let changed = store.document
    store.commitInkMode(); await stale.commitTask?.value; XCTAssertNotNil(stale.error); XCTAssertTrue(store.document == changed)
  }
  @MainActor func testMultichannelPreviewCommitMergeAndCloseLifecycle() async throws {
    var original = try source(.rgb, depth: .u16); var hidden = original.layers[0]; hidden.id = UUID(); hidden.visible = false; original.layers.append(hidden)
    let document = CraftNSDocument(model: original); defer { document.updateChangeCount(.changeCleared); document.close() }
    let store = document.store; store.beginInkMode(.multichannel); let draft = try XCTUnwrap(store.inkModeWorkspace)
    await draft.task?.value; XCTAssertNotNil(draft.error); XCTAssertFalse(draft.ready); XCTAssertTrue(store.document == original)
    draft.update { $0.mergeVisible = true }; await draft.task?.value; XCTAssertTrue(draft.ready, draft.error ?? "missing")
    var expected = original; try draft.request.command(in: original).apply(to: &expected)
    store.commitInkMode(); await draft.commitTask?.value; XCTAssertNil(draft.error); XCTAssertTrue(store.document == expected)
    XCTAssertEqual(store.document.layers.count, 0); XCTAssertEqual(store.document.colorChannelNames, ["Cyan", "Magenta", "Yellow"])
    await store.undo(); XCTAssertTrue(store.document == original)
    store.beginInkMode(.multichannel); let closing = try XCTUnwrap(store.inkModeWorkspace), task = closing.task
    document.close(); await task?.value; XCTAssertNil(store.inkModeWorkspace); XCTAssertFalse(closing.ready)
  }
  @MainActor func testMenusHostedControlsAndStateSchemas() async throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { _, menu in
      for path in AppDelegate.inkModeMenus.keys {
        let item = try XCTUnwrap(helper.allItems(menu).first { $0.identifier?.rawValue == path })
        XCTAssertEqual(item.action, #selector(AppDelegate.inkModeDialog(_:))); XCTAssertEqual(item.keyEquivalent, "")
      }
    }
    for kind in InkModeRequest.Kind.allCases {
      let store = EditorStore(document: try source()), model = InkModeWorkspace(document: try source(), kind: kind)
      defer { store.renderTask?.cancel(); model.close() }
      model.update { $0.settings = settings() }; model.refresh(); await model.task?.value
      XCTAssertTrue(model.ready, model.error ?? "missing")
      let view = NSHostingView(rootView: InkModeSheet(store: store, model: model)), frame = NSRect(x: 0, y: 0, width: 900, height: 640)
      let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua); window.contentView = view; view.frame = frame
      defer { window.close() }; view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
      XCTAssertLessThanOrEqual(view.fittingSize.width, 900); XCTAssertLessThanOrEqual(view.fittingSize.height, 640)
      let run = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/runs/20261028T152212Z-222-ink-modes")
      if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: run.appendingPathComponent("controls-\(kind.rawValue)-\(UUID()).png")) } }
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: InkModeAPI.capabilities)); XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: store.inkModeState))
    }
    let gray = EditorStore(document: try source()); defer { gray.renderTask?.cancel() }
    XCTAssertTrue(gray.canBeginInkMode(.duotone)); XCTAssertTrue(gray.canBeginInkMode(.multichannel))
    let rgb = EditorStore(document: try source(.rgb, depth: .f32)); defer { rgb.renderTask?.cancel() }
    XCTAssertFalse(rgb.canBeginInkMode(.duotone)); XCTAssertFalse(rgb.canBeginInkMode(.multichannel))
  }
  func testActions20RetainSettingsAndPlayOnDifferentDocument() throws {
    let first = try source(), second = try source(); var request = InkModeRequest(.duotone, document: first); request.settings = settings()
    var session = EditorSession(document: first); try session.startActionRecording(name: "Two inks"); try session.execute(request.command(in: first))
    let action = try XCTUnwrap(session.actionRecording?.snapshot)
    guard case .inkMode(let retained) = action.steps[0].operation else { return XCTFail("Missing semantic ink operation") }
    XCTAssertEqual(retained, request)
    let bytes = try ActionLibraryFile(actions: [action]).encoded(), decoded = try ActionLibraryFile.decode(bytes); XCTAssertEqual(decoded.version, 20)
    var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); bad["version"] = 19
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: bad)))
    var expected = second, actual = second; try request.command(in: second).apply(to: &expected)
    try RecordedActionRenderer.prepare(decoded.actions[0], in: second).command.apply(to: &actual); XCTAssertTrue(actual == expected)
    let multi = InkModeRequest(.multichannel, document: expected)
    var pair = action; pair.steps.append(.init(name: "Separate", operation: .inkMode(multi)))
    try multi.command(in: expected).apply(to: &expected); actual = second
    try RecordedActionRenderer.prepare(pair, in: second).command.apply(to: &actual); XCTAssertTrue(actual == expected)
    pair.steps.append(.init(name: "Stop", operation: .unsupported("Intentional"))); XCTAssertThrowsError(try RecordedActionRenderer.prepare(pair, in: second))
  }
  @MainActor func testHTTPConversionReadSettingsUndoStaleBusyAndInvalid() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let original = try self.source(); document.store.session = EditorSession(document: original); try service.share(document)
      let settings = self.settings(); var expected = original; try InkModeInput.duotone(settings, in: original).apply(to: &expected)
      let converted = try await helper.edit(service, document, "document.convertDuotone", ["settings": BrushAPI.json(settings)])
      XCTAssertEqual(converted, 200); XCTAssertTrue(document.store.document == expected)
      let share = try XCTUnwrap(service.shares.first), count = document.store.session.undoStack.count
      let read = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "ink.settings.read", "revision": service.revision(document.store), "parameters": [:]])
      XCTAssertEqual(read.0.statusCode, 200)
      let value = try XCTUnwrap(JSONSerialization.jsonObject(with: read.1) as? [String: Any]); XCTAssertEqual(value["mode"] as? String, "duotone")
      let saved = try JSONDecoder().decode(DuotoneSettings.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(value["settings"]))); XCTAssertEqual(saved, settings); XCTAssertEqual(document.store.session.undoStack.count, count)
      let invalid = try await helper.edit(service, document, "document.convertDuotone", ["settings": ["inks": []]])
      XCTAssertEqual(invalid, 400); XCTAssertTrue(document.store.document == expected)
      let stale = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "document.convertMultichannel", "revision": "old", "parameters": [:]])
      XCTAssertEqual(stale.0.statusCode, 409)
      document.store.beginInkMode(.duotone); await document.store.inkModeWorkspace?.task?.value
      let busy = try await helper.edit(service, document, "document.convertMultichannel"); XCTAssertEqual(busy, 409); document.store.cancelInkMode()
      let request = InkModeRequest(.multichannel, document: expected); try request.command(in: expected).apply(to: &expected)
      let multi = try await helper.edit(service, document, "document.convertMultichannel"); XCTAssertEqual(multi, 200); XCTAssertTrue(document.store.document == expected)
      let inkRead = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "ink.settings.read", "revision": service.revision(document.store), "parameters": [:]])
      XCTAssertEqual(inkRead.0.statusCode, 200); XCTAssertEqual((try JSONSerialization.jsonObject(with: inkRead.1) as? [String: Any])?["plates"].map { ($0 as? [Any])?.count ?? 0 }, 2)
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200); XCTAssertEqual(document.store.document.colorMode, .duotone)
      let undo2 = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo2, 200); XCTAssertTrue(document.store.document == original)
      let caps = try await helper.request(service, path: "/v1/capabilities"); let object = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any]); XCTAssertNotNil(object["inkModes"])
    }
  }
  func testMultichannelActionAdaptsToPlaybackComponentsAndExistingInkIDs() throws {
    let recordedSource = try source(.rgb), request = InkModeRequest(.multichannel, document: recordedSource)
    let action = RecordedAction(name: "Separate inks", steps: [.init(name: "Multichannel", operation: .inkMode(request))])
    var duo = try source(); try InkModeInput.duotone(settings(), in: duo).apply(to: &duo)
    for original in [try source(.grayscale), try source(.cmyk, depth: .u16), duo] {
      var expected = original, actual = original
      try InkModeInput.multichannel(in: original).apply(to: &expected)
      try RecordedActionRenderer.prepare(action, in: original).command.apply(to: &actual)
      guard case .multichannel(let a) = actual.inkMode, case .multichannel(let b) = expected.inkMode else { return XCTFail() }
      XCTAssertEqual(a.plates.map(\.name), b.plates.map(\.name)); XCTAssertEqual(a.plates.map(\.color), b.plates.map(\.color))
      XCTAssertTrue(a.plates.map(\.samples) == b.plates.map(\.samples))
      if original.inkMode != nil { XCTAssertEqual(a.plates.map(\.id), b.plates.map(\.id)) }
    }
  }
  @MainActor func testHTTPRevocationDuringInkPreparationLeavesDocumentUntouched() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let original = try CraftNSDocument.blankModel(width: 512, height: 512, background: Pixel(0.1, 0.6, 0.9))
      document.store.session = EditorSession(document: original); try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let revoke = Task { @MainActor in
        for _ in 0..<10000 {
          if document.store.geometryBusy { service.revoke(id); return }
          await Task.yield()
        }
        XCTFail("Conversion did not enter the prepared worker")
      }
      let status = try await helper.edit(service, document, "document.convertMultichannel")
      await revoke.value
      XCTAssertEqual(status, 409); XCTAssertTrue(document.store.document == original)
      XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.store.geometryBusy)
    }
  }

}
