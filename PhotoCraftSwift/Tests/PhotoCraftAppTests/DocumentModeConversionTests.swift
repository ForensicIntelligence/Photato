import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class DocumentModeConversionTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8, rich: Bool = false) throws -> CraftDocument {
    var document = try CraftDocument(width: 4, height: 3, depth: depth, name: "Mode workflow")
    var pixels = try Surface(width: 4, height: 3, depth: depth)
    pixels.setPixel(x: 1, y: 1, Pixel(0.2, 0.6, 0.8, 0.7))
    let layer = Layer(name: "Pixels", content: .raster(pixels))
    document.layers = [layer]; document.activeLayerID = layer.id
    if rich {
      document.layers.append(Layer(name: "Fill", content: .fill(Pixel(0.7, 0.2, 0.3, 0.3))))
      var hidden = Layer(name: "Hidden", content: .raster(pixels)); hidden.visible = false; document.layers.append(hidden)
    }
    try document.validate(); return document
  }
  func testPreparedModeConversionKeepsLayersAndHasAtomicUndoAndStaleGuard() throws {
    for mode in DocumentColorMode.componentModes {
      let original = try fixture(), request = DocumentModeRequest(.init(mode: mode, depth: .u16))
      let command = try DocumentModeInput.command(request, in: original)
      var session = EditorSession(document: original); try session.execute(command)
      let result = session.document
      XCTAssertEqual(result.colorMode, mode); XCTAssertEqual(result.depth, .u16)
      XCTAssertEqual(result.layers.map(\.id), original.layers.map(\.id))
      XCTAssertNotNil(result.layers[0].nativeMode)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)
      XCTAssertThrowsError(try session.execute(command)); XCTAssertEqual(session.document, result)
      try session.undo(); XCTAssertEqual(session.document, original)
      try session.redo(); XCTAssertEqual(session.document, result)
    }
  }
  func testRichConversionRequiresExplicitMergeAndRetainsCompositeAndUndo() throws {
    let original = try fixture(rich: true)
    var request = DocumentModeRequest(.init(mode: .lab, depth: .u16))
    XCTAssertTrue(DocumentModeInput.needsMerge(original))
    XCTAssertThrowsError(try DocumentModeInput.command(request, in: original))
    request.mergeVisible = true
    let expected = try NativeModeRaster.converting(Renderer.composite(original), to: .lab, depth: .u16)
    var session = EditorSession(document: original)
    try session.execute(DocumentModeInput.command(request, in: original))
    XCTAssertEqual(session.document.layers.count, 1)
    XCTAssertEqual(session.document.layers[0].nativeMode, expected)
    XCTAssertEqual(session.document.layers[0].id, original.activeLayerID)
    try session.undo(); XCTAssertEqual(session.document, original)
  }
  func testHDRReductionRequiresExplicitClippingAndCustomProfileIsValidated() throws {
    let source = try fixture(.f32)
    var request = DocumentModeRequest(.init(mode: .grayscale, depth: .u16))
    XCTAssertThrowsError(try DocumentModeInput.command(request, in: source))
    request.clipHDR = true
    var changed = source; try DocumentModeInput.command(request, in: source).apply(to: &changed)
    XCTAssertEqual(changed.depth, .u16); XCTAssertEqual(changed.colorMode, .grayscale)
    request.conversion.profile = try NativeModeProfile.standard(.cmyk, depth: .u16)
    XCTAssertThrowsError(try DocumentModeInput.command(request, in: source))
  }
  func testExistingHDRToningKeepsModeStorageValidAndFloatChannelsRetainHDR() throws {
    var document = try fixture(.f32).convertingMode(.init(mode: .grayscale, depth: .f32))
    let id = try XCTUnwrap(document.activeLayerID)
    let request = try AutomationCommand(data: JSONSerialization.data(withJSONObject: [
      "command": "mode.channel.write", "revision": "test", "parameters": [
        "layerID": id.uuidString, "component": 0, "offset": 0, "values": [2.5, -0.25]]]))
    try request.modeChannelWrite(in: document).apply(to: &document)
    XCTAssertEqual(document.layers[0].nativeMode?.value(component: 0, index: 0), 2.5)
    XCTAssertEqual(document.layers[0].nativeMode?.value(component: 0, index: 1), -0.25)
    let source = document
    try ClassicToneInput.command(.init(.init(.hdrToning)), in: document).apply(to: &document)
    XCTAssertEqual(document.colorMode, .grayscale); XCTAssertEqual(document.depth, .f32)
    XCTAssertNotNil(document.layers[0].nativeMode); XCTAssertNoThrow(try document.validate())
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)), document)
    XCTAssertNotEqual(document, source)
  }
  @MainActor func testPreviewLocalUndoCancelCommitAndDocumentUndo() async throws {
    let source = try fixture(), store = EditorStore(document: source)
    defer { store.cancelDocumentMode(); store.renderTask?.cancel() }
    store.beginDocumentMode(.cmyk)
    let draft = try XCTUnwrap(store.documentModeWorkspace); await draft.task?.value
    XCTAssertTrue(draft.ready, draft.error ?? "No preview"); XCTAssertTrue(store.hasToneDraft)
    XCTAssertEqual(store.document, source); XCTAssertFalse(store.canBeginDocumentMode)
    let first = draft.request
    draft.update { $0.conversion.intent = .perceptual }; let next = draft.request
    draft.undo(); XCTAssertEqual(draft.request, first)
    draft.redo(); XCTAssertEqual(draft.request, next)
    await draft.task?.value; XCTAssertTrue(draft.ready, draft.error ?? "No preview")
    store.cancelDocumentMode(); XCTAssertEqual(store.document, source); XCTAssertNil(store.documentModeWorkspace)
    store.beginDocumentMode(.lab, depth: .u16)
    let commit = try XCTUnwrap(store.documentModeWorkspace); await commit.task?.value
    var expected = source; try DocumentModeInput.command(commit.request, in: source).apply(to: &expected)
    store.commitDocumentMode(); await commit.commitTask?.value
    XCTAssertNil(commit.error); XCTAssertNil(store.documentModeWorkspace); XCTAssertEqual(store.document, expected)
    await store.undo(); XCTAssertEqual(store.document, source)
  }
  @MainActor func testCloseCancelsPreviewAndRejectsStaleCommit() async throws {
    let source = try fixture(), model = try DocumentModeWorkspace(document: source, mode: .cmyk, depth: .u8)
    model.refresh(); let task = model.task; model.close(); await task?.value
    XCTAssertFalse(model.ready); XCTAssertNil(model.image)
    let store = EditorStore(document: source); defer { store.cancelDocumentMode(); store.renderTask?.cancel() }
    store.beginDocumentMode(.lab); let draft = try XCTUnwrap(store.documentModeWorkspace); await draft.task?.value
    try store.session.execute(.renameLayer(source.layers[0].id, "Changed source"))
    let changed = store.document
    store.commitDocumentMode(); await draft.commitTask?.value
    XCTAssertNotNil(draft.error); XCTAssertEqual(store.document, changed)
  }
  @MainActor func testMenusHostedSheetAndJSONDiscovery() async throws {
    let helper = PhotoshopMenuTests()
    try helper.withMenus { _, menu in
      let items = helper.allItems(menu)
      for path in Array(AppDelegate.documentModeMenus.keys) + Array(AppDelegate.documentDepthMenus.keys) {
        let item = try XCTUnwrap(items.first { $0.identifier?.rawValue == path })
        XCTAssertEqual(item.action, #selector(AppDelegate.documentModeDialog(_:)))
        XCTAssertEqual(item.keyEquivalent, "")
      }
    }
    let source = try fixture(), store = EditorStore(document: source)
    let model = try DocumentModeWorkspace(document: source, mode: .cmyk, depth: .u16)
    defer { model.close(); store.renderTask?.cancel() }
    model.refresh(); await model.task?.value; XCTAssertTrue(model.ready, model.error ?? "No preview")
    let view = NSHostingView(rootView: DocumentModeSheet(store: store, model: model))
    view.frame = NSRect(x: 0, y: 0, width: 850, height: 560); view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width, 0)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: DocumentModeAPI.capabilities))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: store.documentModeState))
    XCTAssertEqual(Set(DocumentModeAPI.commands), Set(AutomationCommand.definitions.filter { DocumentModeAPI.commands.contains($0.name) }.map(\.name)))
  }
  @MainActor func testHTTPConversionAndChannelAccessEqualNativeHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let original = try self.fixture(); document.store.session = EditorSession(document: original)
      let profile = try NativeModeProfile.standard(.cmyk, depth: .u16)
      var expected = original
      try DocumentModeInput.command(.init(.init(mode: .cmyk, depth: .u16, profile: profile)), in: original).apply(to: &expected)
      let converted = try await helper.edit(service, document, "document.convertMode", ["mode": "cmyk", "depth": 16, "profileBase64": profile.base64EncodedString()])
      XCTAssertEqual(converted, 200); XCTAssertEqual(document.store.document, expected)
      let id = expected.layers[0].id
      var plane = try expected.modeChannel(layerID: id, component: 3)
      plane.setPixel(x: 1, y: 1, Pixel(0.8, 0.8, 0.8))
      try Command.modeChannel(.init(layerID: id, component: 3, pixels: plane)).apply(to: &expected)
      let written = try await helper.edit(service, document, "mode.channel.write", ["layerID": id.uuidString, "component": 3, "offset": 5, "values": [0.8]])
      XCTAssertEqual(written, 200); XCTAssertEqual(document.store.document, expected)
      let share = try XCTUnwrap(service.shares.first)
      let read = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": "mode.channel.read", "revision": service.revision(document.store), "parameters": ["layerID": id.uuidString, "component": 3, "offset": 5, "count": 1]])
      XCTAssertEqual(read.0.statusCode, 200)
      let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: read.1) as? [String: Any])
      XCTAssertEqual((object["values"] as? [Float])?.first, PixelDepth.u16.quantize(0.8))
      XCTAssertEqual(document.store.document, expected)
      let undoChannel = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undoChannel, 200)
      let undoMode = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undoMode, 200)
      XCTAssertEqual(document.store.document, original)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndProtectedRequestsDoNotMutate() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document)
      let original = document.store.document
      for params in [["mode": "cmyk", "depth": 32], ["mode": "gray", "depth": 8], ["mode": "lab", "depth": 12], ["mode": "rgb", "depth": 8, "profileBase64": "broken"]] as [[String: Any]] {
        let status = try await helper.edit(service, document, "document.convertMode", params)
        XCTAssertEqual(status, 400); XCTAssertEqual(document.store.document, original)
      }
      let stale = try await helper.edit(service, document, "document.convertMode", ["mode": "lab", "depth": 8], revision: "old")
      XCTAssertEqual(stale, 409)
      document.store.beginDocumentMode(.cmyk)
      let busy = try await helper.edit(service, document, "document.convertMode", ["mode": "lab", "depth": 8])
      XCTAssertEqual(busy, 409); document.store.cancelDocumentMode()
      let status = try await helper.edit(service, document, "document.convertMode", ["mode": "cmyk", "depth": 8]); XCTAssertEqual(status, 200)
      let converted = document.store.document, id = try XCTUnwrap(converted.activeLayerID)
      for params in [["layerID": id.uuidString, "component": 4, "values": [0.1]], ["layerID": id.uuidString, "component": 3, "values": [2]], ["layerID": id.uuidString, "component": 3, "offset": 11, "values": [0.1, 0.2]]] as [[String: Any]] {
        let rejected = try await helper.edit(service, document, "mode.channel.write", params)
        XCTAssertEqual(rejected, 400); XCTAssertEqual(document.store.document, converted)
      }
      try document.store.executeEditorCommand(.lock(id, true)); let locked = document.store.document
      let rejected = try await helper.edit(service, document, "mode.channel.write", ["layerID": id.uuidString, "component": 3, "values": [0.1]])
      XCTAssertEqual(rejected, 422); XCTAssertEqual(document.store.document, locked)
    }
  }
}
