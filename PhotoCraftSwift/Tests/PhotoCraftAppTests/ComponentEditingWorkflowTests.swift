import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class ComponentEditingWorkflowTests: XCTestCase {
  @MainActor func testUnsupportedDepthCannotEnterComponentContext() throws {
    for depth in [PixelDepth.u16, .f32] {
      let store = EditorStore(document: try CraftDocument(width: 3, height: 2, depth: depth))
      defer { store.renderTask?.cancel() }
      let original = store.document
      let revision = store.revision
      XCTAssertThrowsError(try store.selectEditingChannel(.red))
      XCTAssertEqual(store.componentTarget, .composite)
      XCTAssertEqual(store.channelView, RGBChannelView())
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.revision, revision)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testTargetIsIndependentOfPreviewAndPreservesDocumentHistory() throws {
    let doc = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 3, height: 2))
    defer { doc.close() }
    let store = doc.store
    let original = store.document
    store.previewChannel(.red)
    XCTAssertEqual(store.componentTarget, .composite)
    let revision = store.revision
    try store.selectEditingChannel(.red)
    XCTAssertGreaterThan(
      store.revision, revision, "Same preview, new editing context must stale clients")
    store.previewChannel(.blue)
    XCTAssertEqual(store.componentTarget, .red)
    XCTAssertEqual(store.channelView.preview, .blue)
    XCTAssertTrue(store.setChannelVisibility(.green, visible: true))
    XCTAssertEqual(store.componentTarget, .red)
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(doc.isDocumentEdited)
    try store.selectEditingChannel(.composite)
    XCTAssertFalse(store.editingComponent)
  }

  @MainActor func testUnsupportedWritersAndPreparedEditsCannotChangeOtherChannels() throws {
    let store = EditorStore(document: try CraftDocument(width: 3, height: 2))
    defer { store.renderTask?.cancel() }
    let original = store.document
    let id = try XCTUnwrap(original.activeLayerID)
    let prepared = try PreparedEdit(command: .fill(id, .white), document: original)
    try store.selectEditingChannel(.red)
    for command: Command in [
      .fill(id, .white), .clear(id), .move(id, 2, 1), .stroke(id, [], Brush()),
      .desaturate(id), .applyAdjustment(id, .levels(.init())),
      .fillComponents(id, .init(components: .green, value: 1)),
      .maskFill(id, 1), .newPixelLayer(.init(name: "Unsafe")),
    ] {
      XCTAssertThrowsError(try store.executeEditorCommand(command), command.label)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
    XCTAssertThrowsError(try store.executeCompositePreparedEdit(prepared))
    XCTAssertFalse(store.clipboardTargetAvailable)
    XCTAssertFalse(store.canBeginLevels)
    XCTAssertFalse(store.canTransformActiveLayer)
    XCTAssertFalse(store.canUseMenuPixelEdit)
    XCTAssertTrue(store.canUseMenuFill)
    store.tool = .brush
    XCTAssertFalse(store.canUseComponentCanvasTool)
    store.tool = .marquee
    XCTAssertTrue(store.canUseComponentCanvasTool)
    store.fill(color: Pixel(1, 0, 0))
    XCTAssertNotNil(store.error)
    XCTAssertEqual(store.document, original)
  }

  @MainActor func testBusyMaskReloadAndShortcutLifecycle() throws {
    let doc = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 3, height: 2))
    defer { doc.close() }
    let store = doc.store
    let saved = try doc.data(ofType: CraftNSDocument.nativeType)
    store.coalesce(true)
    XCTAssertThrowsError(try store.selectEditingChannel(.red))
    store.coalesce(false)
    for (key, channel): (String, RGBChannelPreview) in [
      ("3", .red), ("4", .green), ("5", .blue), ("2", .composite),
    ] {
      let event = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
          characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0))
      XCTAssertTrue(store.handleComponentShortcut(event))
      XCTAssertEqual(store.componentTarget, channel)
    }
    let id = try XCTUnwrap(store.document.activeLayerID)
    try store.executeEditorCommand(.createMask(id, .revealAll))
    try store.selectEditingChannel(.red)
    store.selectMask(id)
    XCTAssertTrue(store.editingMask)
    XCTAssertEqual(store.componentTarget, .composite)
    try store.selectEditingChannel(.red)
    XCTAssertFalse(store.editingMask)
    try doc.read(from: saved, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(store.componentTarget, .composite)
    XCTAssertEqual(store.channelView, RGBChannelView())
  }

  @MainActor func testRealHTTPTargetFillMatchesDesktopAndSharesUndoAndGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService { service, doc in
      let store = doc.store
      let id = try XCTUnwrap(store.document.activeLayerID)
      try store.executeEditorCommand(.fill(id, Pixel(32.0 / 255, 96.0 / 255, 192.0 / 255, 0.5)))
      let original = store.document
      try service.share(doc)
      let staleRevision = service.revision(store)
      let target = try await helper.edit(service, doc, "channel.target", ["channel": "Red"])
      XCTAssertEqual(target, 200)
      let stale = try await helper.edit(
        service, doc, "channel.fill", ["value": 1, "opacity": 0.5], revision: staleRevision)
      XCTAssertEqual(stale, 409)
      let desktop = EditorStore(document: original)
      defer { desktop.renderTask?.cancel() }
      try desktop.selectEditingChannel(.red)
      desktop.fill(color: .white, opacity: 0.5)
      let fill = try await helper.edit(service, doc, "channel.fill", ["value": 1, "opacity": 0.5])
      XCTAssertEqual(fill, 200)
      XCTAssertEqual(store.document, desktop.document)
      XCTAssertEqual(store.session.undoStack.last?.label, "Fill")
      store.undo()
      XCTAssertEqual(store.document, original)
      let redo = try await helper.edit(service, doc, "history.redo")
      XCTAssertEqual(redo, 200)
      XCTAssertEqual(store.document, desktop.document)
      let edited = store.document
      let invalid = try await helper.edit(service, doc, "channel.fill", ["value": 1, "opacity": 2])
      XCTAssertEqual(invalid, 400)
      store.geometryBusy = true
      let busy = try await helper.edit(service, doc, "channel.target", ["channel": "Blue"])
      XCTAssertEqual(busy, 409)
      store.geometryBusy = false
      let wrongWriter = try await helper.edit(
        service, doc, "layer.fill", ["layerID": id.uuidString, "r": 1, "g": 0, "b": 0, "a": 1])
      XCTAssertEqual(wrongWriter, 422)
      XCTAssertEqual(store.document, edited)
      let preview = try await helper.edit(service, doc, "view.channelPreview", ["channel": "Blue"])
      XCTAssertEqual(preview, 200)
      XCTAssertEqual(store.componentTarget, .red)
      let share = try XCTUnwrap(service.shares.first)
      let state = service.state(share, document: doc)
      XCTAssertEqual(state["channelTarget"] as? String, "Red")
      XCTAssertEqual((state["channelView"] as? [String: Any])?["componentEditing"] as? Bool, true)
    }
  }
}
