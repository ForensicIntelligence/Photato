import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class QuickMaskTargetTransitionWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var document = try CraftDocument(width: 24, height: 16, depth: depth)
    document.selection = .init(x: 4, y: 4, width: 12, height: 8)
    document.alphaChannels = [.init(name: "Saved selection", pixels: try Surface(width: 24, height: 16, depth: depth, fill: Pixel(0.25, 0.25, 0.25)))]
    return document
  }
  @MainActor func shortcut(_ key: String, store: EditorStore) throws -> Bool {
    store.handleComponentShortcut(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
      modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
      characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0)))
  }

  @MainActor func testCompositeTargetRetainsVisibleQuickMaskAndInvertEditsOnlyImageAtAllDepths() async throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(document: try fixture(depth))
      defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
      store.toggleQuickMask()
      let original = store.document, history = store.session.undoStack.count
      XCTAssertEqual(store.editingChannel, .quickMask)
      XCTAssertTrue(try shortcut("2", store: store))
      XCTAssertNil(store.error)
      XCTAssertNil(store.editingChannel)
      XCTAssertEqual(store.displayedAuxiliaryChannel, .quickMask)
      XCTAssertTrue(store.isQuickMaskVisible)
      XCTAssertFalse(store.editingComponent)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.session.undoStack.count, history)
      XCTAssertTrue(store.canInvertPixels)
      store.invertPixels()
      await store.geometryTask?.value
      XCTAssertNil(store.error)
      var expected = original
      try Command.applyAdjustment(try XCTUnwrap(original.activeLayerID), .invert).apply(to: &expected)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.document.quickMask, original.quickMask)
      XCTAssertEqual(store.document.alphaChannels, original.alphaChannels)
      XCTAssertEqual(store.session.undoStack.count, history + 1)
      await store.undo()
      XCTAssertEqual(store.document, original)
      XCTAssertNil(store.editingChannel)
      await store.redo()
      XCTAssertEqual(store.document, expected)
      store.toggleQuickMask()
      XCTAssertNil(store.document.quickMask)
      XCTAssertNotNil(store.document.selectionMask)
    }
  }

  @MainActor func testFactoryNumberedTargetsSelectSavedAlphaAndTemporaryMaskWithoutHistory() throws {
    for depth in PixelDepth.allCases {
      let store = EditorStore(document: try fixture(depth))
      defer { store.renderTask?.cancel() }
      store.toggleQuickMask()
      let original = store.document, history = store.session.undoStack.count
      XCTAssertTrue(try shortcut("3", store: store))
      XCTAssertNil(store.error)
      XCTAssertNil(store.editingChannel)
      if depth == .u8 { XCTAssertEqual(store.componentTarget, .red) }
      else { XCTAssertEqual(store.modeComponentTargets, [0]) }
      XCTAssertTrue(try shortcut("6", store: store))
      XCTAssertEqual(store.editingChannel, .alpha(try XCTUnwrap(original.alphaChannels?.first?.id)))
      XCTAssertTrue(try shortcut("7", store: store))
      XCTAssertEqual(store.editingChannel, .quickMask)
      XCTAssertTrue(store.modeComponentTargets.isEmpty)
      XCTAssertEqual(store.componentTarget, .composite)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.session.undoStack.count, history)
      try store.selectEditingChannel(.composite)
      store.geometryBusy = true
      XCTAssertTrue(try shortcut("7", store: store))
      XCTAssertNotNil(store.error)
      XCTAssertNil(store.editingChannel)
      XCTAssertEqual(store.document, original)
      store.geometryBusy = false
    }
  }

  @MainActor func testNumericalModeTargetsCanLeaveQuickMaskWithoutChangingItsPlane() throws {
    let helper = ModeChannelWorkflowTests()
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let store = EditorStore(document: try helper.fixture(mode, depth))
      defer { store.renderTask?.cancel() }
      store.toggleQuickMask()
      let original = store.document
      try store.selectModeComponents([0])
      XCTAssertNil(store.editingChannel)
      XCTAssertEqual(store.displayedAuxiliaryChannel, .quickMask)
      XCTAssertTrue(store.canEditModeComponents)
      let command = try store.componentFillCommand(value: 0.75, opacity: 1)
      try store.executeEditorCommand(command)
      var expected = original
      try command.apply(to: &expected)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.document.quickMask, original.quickMask)
      let maskShortcut = 3 + (mode == .grayscale ? 0 : mode.componentCount)
      XCTAssertTrue(try shortcut(String(maskShortcut), store: store))
      XCTAssertEqual(store.editingChannel, .quickMask)
      XCTAssertNil(store.error)
    } }
  }

  @MainActor func testHTTPCompositeAndMaskTargetsMatchNativeAndEyeNeverChangesTarget() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      file.store.session = EditorSession(document: try self.fixture())
      let store = file.store
      store.toggleQuickMask()
      try service.share(file)
      let share = try XCTUnwrap(service.shares.first { $0.document === file })
      let original = store.document, history = store.session.undoStack.count
      let native = EditorStore(document: original)
      defer { native.renderTask?.cancel(); native.geometryTask?.cancel() }
      try native.selectEditingChannel(.composite)
      let selected = try await helper.edit(service, file, "channel.view", ["target":"RGB"])
      XCTAssertEqual(selected, 200)
      XCTAssertNil(store.editingChannel)
      XCTAssertEqual(service.state(share, document: file)["alphaChannelTarget"] as? String, "RGB")
      let path = "/v1/documents/\(share.id)"
      let preview = try await helper.request(service, path: path + "/channel-preview.png")
      XCTAssertEqual(preview.0.statusCode, 200)
      XCTAssertEqual(preview.1, try AutomationService.png(native.document, auxiliary: native.displayedAuxiliaryChannel, overlay: true))
      let priorRevision = service.revision(store)
      let hidden = try await helper.edit(service, file, "channel.view", ["target":"quickMask", "visible":false])
      XCTAssertEqual(hidden, 200)
      XCTAssertNil(store.editingChannel)
      XCTAssertNil(store.displayedAuxiliaryChannel)
      XCTAssertFalse(store.isQuickMaskVisible)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.session.undoStack.count, history)
      let stale = try await helper.edit(service, file, "channel.view", ["target":"quickMask"], revision: priorRevision)
      XCTAssertEqual(stale, 409)
      let selectedMask = try await helper.edit(service, file, "channel.view", ["target":"quickMask"])
      XCTAssertEqual(selectedMask, 200)
      XCTAssertEqual(store.editingChannel, .quickMask)
      XCTAssertFalse(store.isQuickMaskVisible)
      let compositeAgain = try await helper.edit(service, file, "channel.view", ["target":"RGB"])
      XCTAssertEqual(compositeAgain, 200)
      let inverted = try await helper.edit(service, file, "adjustment.apply", ["layerID":try XCTUnwrap(original.activeLayerID).uuidString, "adjustment":["kind":"invert"]])
      XCTAssertEqual(inverted, 200)
      native.invertPixels(); await native.geometryTask?.value
      XCTAssertEqual(store.document, native.document)
      XCTAssertEqual(store.document.quickMask, original.quickMask)
      await store.undo()
      XCTAssertEqual(store.document, original)
      store.geometryBusy = true
      let busy = try await helper.edit(service, file, "channel.view", ["target":"quickMask"])
      XCTAssertEqual(busy, 409)
      store.geometryBusy = false
      XCTAssertNil(store.editingChannel)
      let missing = try await helper.edit(service, file, "channel.view", ["target":UUID().uuidString])
      XCTAssertEqual(missing, 422)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(AutomationCommand.definitions.count, 242)
    }
  }

  @MainActor func testTargetOverrideIsScopedToMaskAndDocumentAndNativeReopenResetsIt() throws {
    let file = CraftNSDocument(model: try fixture())
    defer { file.close() }
    let store = file.store
    store.toggleQuickMask()
    let original = store.document
    try store.selectEditingChannel(.composite)
    XCTAssertNil(store.editingChannel)
    let saved = try file.data(ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(try NativeArchive.decode(saved), original)
    try file.read(from: saved, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(store.editingChannel, .quickMask)
    try store.selectEditingChannel(.composite)
    var other = original; other.id = UUID()
    store.session = EditorSession(document: other)
    XCTAssertEqual(store.editingChannel, .quickMask)
    try store.selectEditingChannel(.composite)
    store.toggleQuickMask(); store.toggleQuickMask()
    XCTAssertNotEqual(store.document.quickMask?.id, original.quickMask?.id)
    XCTAssertEqual(store.editingChannel, .quickMask)
  }

  @MainActor func testAlphaSelectionAndHiddenEyeLeaveTargetsDistinctAndInvalidRequestsAtomic() throws {
    let store = EditorStore(document: try fixture())
    defer { store.renderTask?.cancel() }
    XCTAssertThrowsError(try store.selectQuickMaskChannel())
    store.toggleQuickMask()
    let original = store.document, history = store.session.undoStack.count
    let alpha = try XCTUnwrap(original.alphaChannels?.first?.id)
    try store.selectAlphaChannel(alpha)
    try store.setQuickMaskVisibility(false)
    XCTAssertEqual(store.editingChannel, .alpha(alpha))
    XCTAssertEqual(store.displayedAuxiliaryChannel, .alpha(alpha))
    XCTAssertTrue(store.canInvertPixels)
    XCTAssertThrowsError(try store.selectAlphaChannel(UUID()))
    XCTAssertEqual(store.editingChannel, .alpha(alpha))
    try store.selectQuickMaskChannel()
    XCTAssertEqual(store.editingChannel, .quickMask)
    XCTAssertNil(store.displayedAuxiliaryChannel)
    XCTAssertFalse(store.canInvertPixels)
    try store.selectEditingChannel(.composite)
    XCTAssertTrue(store.canInvertPixels)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(store.session.undoStack.count, history)
  }
}
