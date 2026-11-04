import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class QuickMaskVisibilityWorkflowTests: XCTestCase {
  @MainActor func fixture() throws -> CraftDocument {
    var model = try CraftNSDocument.blankModel(width: 24, height: 16, background: .white)
    model.selection = .init(x: 4, y: 4, width: 12, height: 8)
    return model
  }

  @MainActor func testEyeVisibilityPreservesQuickMaskTargetPixelsHistoryAndNativeFile() async throws {
    let file = CraftNSDocument(model: try fixture())
    defer { file.close() }
    let store = file.store
    store.toggleQuickMask()
    await store.renderTask?.value
    let original = store.document
    let archive = try file.data(ofType: CraftNSDocument.nativeType)
    let undo = store.session.undoStack.count
    let visible = try RasterIO.surface(XCTUnwrap(store.image))
    XCTAssertTrue(store.isQuickMaskVisible)
    try store.setQuickMaskVisibility(false)
    await store.renderTask?.value
    XCTAssertFalse(store.isQuickMaskVisible)
    XCTAssertEqual(store.editingChannel, .quickMask)
    XCTAssertNil(store.displayedAuxiliaryChannel)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(store.session.undoStack.count, undo)
    XCTAssertEqual(try file.data(ofType: CraftNSDocument.nativeType), archive)
    let hidden = try RasterIO.surface(XCTUnwrap(store.image))
    XCTAssertNotEqual(hidden, visible)
    XCTAssertEqual(hidden.pixel(x: 0, y: 0), .white)
    let revision = store.revision
    try store.setQuickMaskVisibility(false)
    XCTAssertEqual(store.revision, revision)
    try store.setQuickMaskVisibility(true)
    await store.renderTask?.value
    XCTAssertEqual(try RasterIO.surface(XCTUnwrap(store.image)), visible)
    XCTAssertEqual(store.displayedAuxiliaryChannel, .quickMask)
  }

  @MainActor func testHiddenQuickMaskRejectsBrushUntilShownAndPreservesUndo() async throws {
    let store = EditorStore(document: try fixture())
    defer { store.renderTask?.cancel() }
    store.tool = .brush
    store.toggleQuickMask()
    try store.setQuickMaskVisibility(false)
    let before = store.document
    let undo = store.session.undoStack.count
    var brush = Brush(); brush.size = 4; brush.hardness = 1; brush.color = .black
    store.stroke([.init(x: 8, y: 8)], brush: brush)
    XCTAssertEqual(store.document, before)
    XCTAssertEqual(store.session.undoStack.count, undo)
    XCTAssertEqual(store.error, EditorStore.hiddenQuickMaskBrushMessage)
    store.error = nil
    store.beginBrush(.init(x: 8, y: 8), zoom: 1)
    XCTAssertNil(store.brushGesture)
    XCTAssertEqual(store.error, EditorStore.hiddenQuickMaskBrushMessage)
    try store.setQuickMaskVisibility(true)
    store.error = nil
    store.stroke([.init(x: 8, y: 8)], brush: brush)
    XCTAssertEqual(store.document.layers, before.layers)
    XCTAssertEqual(store.document.quickMask?.pixels.pixel(x: 8, y: 8).r, 0)
    XCTAssertEqual(store.editingChannel, .quickMask)
    XCTAssertTrue(store.isQuickMaskVisible)
    await store.undo()
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.isQuickMaskVisible)
    try store.setQuickMaskVisibility(false)
    store.toggleQuickMask()
    XCTAssertNil(store.document.quickMask)
    store.toggleQuickMask()
    XCTAssertNotEqual(store.document.quickMask?.id, before.quickMask?.id)
    XCTAssertTrue(store.isQuickMaskVisible)
  }

  @MainActor func testVisibilityIsScopedToDocumentAndMaskAndRejectsBusyOrMissingTargets() throws {
    let store = EditorStore(document: try fixture())
    defer { store.renderTask?.cancel() }
    XCTAssertThrowsError(try store.setQuickMaskVisibility(false))
    store.toggleQuickMask()
    let original = store.document
    store.geometryBusy = true
    XCTAssertThrowsError(try store.setQuickMaskVisibility(false))
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.isQuickMaskVisible)
    store.geometryBusy = false
    try store.setQuickMaskVisibility(false)
    var other = original; other.id = UUID()
    store.session = EditorSession(document: other)
    XCTAssertTrue(store.isQuickMaskVisible)
    XCTAssertEqual(store.editingChannel, .quickMask)
  }

  @MainActor func testHTTPVisibilityMatchesNativeCanvasAndLeavesOrdinaryPreviewAndArchiveUnchanged() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: try self.fixture())
      let defaults = file.store.quickMaskOptions
      defer { file.store.quickMaskOptions = defaults }
      try service.share(file)
      let entered = try await helper.edit(service, file, "channel.edit", ["action":"quickMask", "enabled":true, "overlayColor":[1,0,0], "opacity":0.5, "indicates":"maskedAreas"])
      XCTAssertEqual(entered, 200)
      let share = try XCTUnwrap(service.shares.first { $0.document === file })
      let path = "/v1/documents/\(share.id)"
      let original = file.store.document
      let archive = try file.data(ofType: CraftNSDocument.nativeType)
      let undo = file.store.session.undoStack.count
      let plain = try await helper.request(service, path: path + "/preview.png")
      let overlay = try await helper.request(service, path: path + "/channel-preview.png")
      XCTAssertNotEqual(plain.1, overlay.1)
      let status = try await helper.edit(service, file, "channel.view", ["target":"quickMask", "visible":false])
      XCTAssertEqual(status, 200)
      await file.store.renderTask?.value
      let hidden = try await helper.request(service, path: path + "/channel-preview.png")
      XCTAssertEqual(hidden.1, plain.1)
      let unchanged = try await helper.request(service, path: path + "/preview.png")
      XCTAssertEqual(unchanged.1, plain.1)
      let state = service.state(share, document: file)
      XCTAssertEqual(state["quickMaskVisible"] as? Bool, false)
      XCTAssertEqual(state["alphaChannelTarget"] as? String, "quickMask")
      let blocked = try await helper.edit(service, file, "channel.edit", ["action":"stroke", "target":"quickMask", "size":4, "points":[["x":8,"y":8]], "value":0])
      XCTAssertEqual(blocked, 422)
      XCTAssertEqual(file.store.document, original)
      XCTAssertEqual(file.store.session.undoStack.count, undo)
      XCTAssertEqual(try file.data(ofType: CraftNSDocument.nativeType), archive)
      let revision = service.revision(file.store)
      let noop = try await helper.edit(service, file, "channel.view", ["target":"quickMask", "visible":false])
      XCTAssertEqual(noop, 200)
      XCTAssertEqual(service.revision(file.store), revision)
      try file.store.setQuickMaskVisibility(true)
      await file.store.renderTask?.value
      let shown = try await helper.request(service, path: path + "/channel-preview.png")
      XCTAssertEqual(shown.1, overlay.1)
    }
  }

  @MainActor func testHTTPInvalidMissingBusyAndStaleVisibilityRequestsAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: try self.fixture())
      try service.share(file)
      let missing = try await helper.edit(service, file, "channel.view", ["target":"quickMask", "visible":false])
      XCTAssertEqual(missing, 422)
      file.store.toggleQuickMask()
      let before = file.store.document
      for parameters: [String:Any] in [["target":"quickMask","visible":"no"], ["target":"RGB","visible":"no"], ["target":UUID().uuidString,"visible":"no"]] {
        let invalid = try await helper.edit(service, file, "channel.view", parameters)
        XCTAssertEqual(invalid, 400)
      }
      let revision = service.revision(file.store)
      try file.store.setQuickMaskVisibility(false)
      let stale = try await helper.edit(service, file, "channel.view", ["target":"quickMask","visible":true], revision: revision)
      XCTAssertEqual(stale, 409)
      file.store.geometryBusy = true
      let busy = try await helper.edit(service, file, "channel.view", ["target":"quickMask","visible":true])
      XCTAssertEqual(busy, 409)
      file.store.geometryBusy = false
      XCTAssertFalse(file.store.isQuickMaskVisible)
      XCTAssertEqual(file.store.document, before)
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "channel.view" })
      let envelope = try XCTUnwrap(definition.schema["properties"] as? [String:[String:Any]])
      let properties = try XCTUnwrap(envelope["parameters"]?["properties"] as? [String:[String:Any]])
      XCTAssertEqual(properties["visible"]?["type"] as? String, "boolean")
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
}
