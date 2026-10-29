import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RestrictedClipboardWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument { try RestrictedModeWorkflowTests().indexed() }
  func indices(_ document: CraftDocument) throws -> Data {
    guard case .indexed(let raster) = document.restrictedMode else { throw CraftError.invalid("No indices") }; return raster.indices
  }
  func testSelectedCopyMergedAndNewDocumentKeepIndexIdentity() throws {
    var document = try fixture(); document.selection = .init(x: 1, y: 0, width: 3, height: 3)
    for merged in [false, true] {
      let content = try ClipboardRenderer.copy(document, layerIDs: [document.layers[0].id], merged: merged)
      XCTAssertEqual(content.bounds, .init(x: 1, y: 0, width: 3, height: 3))
      let restored = try ClipboardContent.decode(content.encoded()), created = try restored.newDocument(name: "Copied indices")
      XCTAssertEqual(try indices(created), Data([1, 2, 0, 2, 0, 1, 0, 1, 2]))
      XCTAssertEqual(created.workingICC, document.workingICC); XCTAssertEqual(created.colorMode, .indexed)
    }
    document.setCoverageSelection(try SelectionMask(width: 4, height: 3, bytes: [0, 128, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255]))
    let partial = try ClipboardRenderer.copy(document, layerIDs: [document.layers[0].id])
    XCTAssertNotNil(partial.restrictedSamples); XCTAssertEqual(try partial.newDocument(name: "Coverage").colorMode, .rgb)
  }
  func testProfileConversionDropsObsoleteIdentityAndImageReadKeepsNativePalette() throws {
    let document = try fixture(), clip = try ClipboardRenderer.copy(document, layerIDs: [document.layers[0].id])
    var target = try CraftDocument(width: 4, height: 3)
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)), profile = try XCTUnwrap(p3.copyICCData()) as Data
    target.workingICC = profile
    let converted = try ColorManagement.converted(clip, to: target)
    XCTAssertNil(converted.restrictedSamples); XCTAssertEqual(converted.document.workingICC, profile); try converted.validate()
    let png = try RasterIO.encoded(document, type: .png), image = try ClipboardRenderer.readImage(png)
    XCTAssertEqual(image.restrictedSamples, document.restrictedMode)
    XCTAssertEqual(try image.newDocument(name: "PNG").restrictedMode, document.restrictedMode)
  }
  @MainActor func testDesktopCopyCutPasteSelectionAndFailedClipboardWrite() async throws {
    let clipboard = MemoryClipboard(), original = try fixture(), store = EditorStore(document: original, clipboard: clipboard)
    defer { store.renderTask?.cancel() }
    store.copyImage(); await store.geometryTask?.value; XCTAssertNil(store.error)
    let copy = try clipboard.read().decoded(); XCTAssertEqual(copy.restrictedSamples, original.restrictedMode)
    XCTAssertTrue(store.document == original); XCTAssertTrue(store.session.undoStack.isEmpty)
    clipboard.rejectWrites = true; store.copyImage(cut: true); await store.geometryTask?.value
    XCTAssertNotNil(store.error); XCTAssertTrue(store.document == original); store.error = nil; clipboard.rejectWrites = false
    store.copyImage(cut: true); await store.geometryTask?.value; XCTAssertNil(store.error); XCTAssertEqual(store.document.layers.count, 1)
    await store.undo(); XCTAssertTrue(store.document == original)
    store.pasteImage(.inPlace); await store.geometryTask?.value; XCTAssertNil(store.error)
    XCTAssertEqual(try indices(store.document), try indices(original)); XCTAssertEqual(store.document.layers.count, 1)
    XCTAssertEqual(store.selectedLayerIDs, [original.layers[0].id])
    var locked = store.document; locked.layers[0].protection = .image; store.session = EditorSession(document: locked)
    XCTAssertFalse(store.canCopy(cut: true)); XCTAssertFalse(store.canPaste(.centered)); XCTAssertTrue(store.canCopy())
  }
  @MainActor func testHTTPExplicitPayloadCutUndoPasteAndNewDocument() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); document.store.session = EditorSession(document: try fixture())
      let original = document.store.document, systemRevision = document.store.clipboard.changeCount, share = try XCTUnwrap(service.shares.first)
      @MainActor func request(_ name: String, _ parameters: [String: Any] = [:]) async throws -> (Int, [String: Any]) {
        let response = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: ["command": name, "revision": service.revision(document.store), "parameters": parameters])
        return (response.0.statusCode, try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any]))
      }
      let copied = try await request("clipboard.copy"); XCTAssertEqual(copied.0, 200)
      let payload = try XCTUnwrap(copied.1["payloadBase64"] as? String)
      XCTAssertEqual(try ClipboardContent.decode(XCTUnwrap(Data(base64Encoded: payload))).restrictedSamples, original.restrictedMode)
      XCTAssertTrue(document.store.document == original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let cut = try await request("clipboard.cut"); XCTAssertEqual(cut.0, 200); XCTAssertNotNil(cut.1["document"])
      XCTAssertEqual(try indices(document.store.document), Data(repeating: 2, count: 12))
      let undone = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undone, 200); XCTAssertTrue(document.store.document == original)
      let pasted = try await request("clipboard.paste", ["payloadBase64": payload, "placement": "inPlace"]); XCTAssertEqual(pasted.0, 200)
      XCTAssertEqual(try indices(document.store.document), try indices(original)); XCTAssertEqual(document.store.document.layers.count, 1)
      let denied = try await request("clipboard.newDocument", ["payloadBase64": payload]); XCTAssertEqual(denied.0, 403)
      service.setDocumentTransfersEnabled(true)
      let created = try await request("clipboard.newDocument", ["payloadBase64": payload, "name": "Indexed transfer"]); XCTAssertEqual(created.0, 201)
      let newID = try XCTUnwrap((created.1["id"] as? String).flatMap(UUID.init(uuidString:)))
      let new = try XCTUnwrap(service.shares.first { $0.id == newID }?.document)
      defer { new.updateChangeCount(.changeCleared); new.close() }
      XCTAssertFalse(new === document)
      XCTAssertEqual(new.store.document.restrictedMode, original.restrictedMode); XCTAssertEqual(new.store.document.name, "Indexed transfer")
      XCTAssertEqual(document.store.clipboard.changeCount, systemRevision)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: ClipboardAPI.capabilities))
    }
  }
  @MainActor func testHTTPInvalidStaleBusyAndRevokedCopyDoNotChangeDocument() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); document.store.session = EditorSession(document: try fixture()); let original = document.store.document
      for (name, params): (String, [String: Any]) in [("clipboard.copy", ["merged": 1]), ("clipboard.cut", ["merged": true]), ("clipboard.copy", ["layerIDs": ["wrong"]]), ("clipboard.paste", ["payloadBase64": "!!!"])] {
        let status = try await helper.edit(service, document, name, params); XCTAssertEqual(status, 400)
      }
      let stale = try await helper.edit(service, document, "clipboard.cut", revision: "old"); XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "clipboard.cut"); XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let pending = Task { try await helper.edit(service, document, "clipboard.cut") }, deadline = Date().addingTimeInterval(5)
      while !document.store.geometryBusy, Date() < deadline { await Task.yield() }
      XCTAssertTrue(document.store.geometryBusy); service.stop(); _ = try? await pending.value
      XCTAssertTrue(document.store.document == original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testCutBackgroundMatchesDesktopAndAPIState() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var original = try fixture()
      guard case .indexed(let raster) = original.restrictedMode else { return XCTFail() }
      original = try original.replacingColorTable(raster.palette, transparentIndex: nil)
      try service.share(document); document.store.session = EditorSession(document: original)
      let desktop = EditorStore(document: original, clipboard: MemoryClipboard()); defer { desktop.renderTask?.cancel() }
      desktop.backgroundColor = .black; desktop.copyImage(cut: true); await desktop.geometryTask?.value; XCTAssertNil(desktop.error)
      let code = try await helper.edit(service, document, "clipboard.cut", ["backgroundColor": [0, 0, 0]])
      XCTAssertEqual(code, 200); XCTAssertTrue(document.store.document == desktop.document)
      XCTAssertEqual(try indices(document.store.document), Data(repeating: 0, count: 12))
      XCTAssertEqual(document.store.clipboardAPIState["systemClipboardAccess"] as? Bool, false)
    }
  }
  @MainActor func testOversizedCutRejectsBeforeMutatingHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var source = try CraftDocument(width: 640, height: 640, depth: .f32), surface = try Surface(width: 640, height: 640, depth: .f32)
      var seed: UInt32 = 1
      func next() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(bitPattern: 0x3f000000 | (seed & 0x7fffff)) }
      for y in 0..<640 { for x in 0..<640 { surface.setPixel(x: x, y: y, Pixel(next(), next(), next(), 1)) } }
      source.layers[0].content = .raster(surface); document.store.session = EditorSession(document: source); try service.share(document)
      let payload = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id]).encoded()
      XCTAssertGreaterThan(payload.count, ClipboardAPI.maximumBytes)
      let status = try await helper.edit(service, document, "clipboard.cut"); XCTAssertEqual(status, 413)
      XCTAssertTrue(document.store.document == source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNewDocumentTransferRevocationDoesNotCreateOrModifyDocuments() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let source = try CraftDocument(width: 512, height: 512).replacingRestrictedMode(.bitmap(BitmapRaster(width: 512, height: 512, bits: Data(repeating: 0xa5, count: 32768))))
      let payload = try ClipboardRenderer.copy(source, layerIDs: [source.layers[0].id]).encoded().base64EncodedString()
      let before = document.store.document, count = service.shares.count
      let pending = Task { try await helper.edit(service, document, "clipboard.newDocument", ["payloadBase64": payload]) }, deadline = Date().addingTimeInterval(5)
      while !document.store.geometryBusy, Date() < deadline { await Task.yield() }
      XCTAssertTrue(document.store.geometryBusy); service.setDocumentTransfersEnabled(false)
      let status = try await pending.value; XCTAssertEqual(status, 409)
      XCTAssertTrue(document.store.document == before); XCTAssertEqual(service.shares.count, count)
      XCTAssertFalse(document.store.geometryBusy); XCTAssertFalse(service.documentTransferBusy)
    }
  }
  @MainActor func testSmallEncodedPayloadCannotExceedDecodedExtentLimits() async throws {
    let content = try ClipboardContent.pixels(Surface(width: 3000, height: 1500, fill: .white)), bytes = try content.encoded()
    XCTAssertLessThan(bytes.count, ClipboardAPI.maximumBytes)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let before = document.store.document, count = service.shares.count
      for name in ["clipboard.paste", "clipboard.newDocument"] {
        let status = try await helper.edit(service, document, name, ["payloadBase64": bytes.base64EncodedString()])
        XCTAssertEqual(status, 413); XCTAssertTrue(document.store.document == before); XCTAssertEqual(service.shares.count, count)
      }
    }
  }
  @MainActor func testUnchangedFlatPasteAndCutDoNotMarkDocumentEdited() async throws {
    let original = try fixture(), clipboard = MemoryClipboard(), store = EditorStore(document: original, clipboard: clipboard)
    defer { store.renderTask?.cancel() }
    var changes = 0; store.onChange = { _ in changes += 1 }
    store.copyImage(); await store.geometryTask?.value
    store.pasteImage(.inPlace); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertTrue(store.document == original); XCTAssertEqual(changes, 0)
    XCTAssertEqual(store.status, "Paste in Place")
    store.copyImage(cut: true); await store.geometryTask?.value; XCTAssertEqual(changes, 1)
    let empty = store.document
    store.copyImage(cut: true); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertTrue(store.document == empty); XCTAssertEqual(changes, 1)
  }
}
