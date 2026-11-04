import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RGB8MultiComponentTests: XCTestCase {
  func fixture(width: Int = 7, height: Int = 5) throws -> CraftDocument {
    try LegacyRGB8ComponentTests().fixture(width: width, height: height)
  }
  @MainActor func close(_ store: EditorStore) {
    store.cancelBrush(); store.geometryTask?.cancel(); store.renderTask?.cancel()
  }
  func bytes(_ document: CraftDocument, x: Int = 2, y: Int = 2) throws -> [UInt8] {
    guard case .raster(let pixels) = document.layers[0].content else { throw CraftError.invalid("Missing owned raster") }
    let p = pixels.pixel(x: x, y: y)
    return [p.r,p.g,p.b,p.a].map { UInt8((unit($0) * 255).rounded()) }
  }
  @MainActor func testRowsAddRemoveCompositeAndSingletonWithoutDocumentMutation() throws {
    let original = try fixture(), s = EditorStore(document: original); defer { close(s) }
    try s.selectColorComponentRow(0, modifiers: [])
    XCTAssertEqual(s.componentTarget, .red); XCTAssertTrue(s.modeComponentTargets.isEmpty)
    try s.selectColorComponentRow(1, modifiers: .shift)
    XCTAssertEqual(s.effectiveComponentTargets, [0,1]); XCTAssertEqual(s.modeComponentTargets, [0,1])
    XCTAssertEqual(s.colorComponentTargetTitle, "Red, Green")
    XCTAssertFalse(s.isColorComponentSelected(nil)); XCTAssertTrue(s.isColorComponentSelected(0))
    XCTAssertTrue(s.isColorComponentSelected(1)); XCTAssertFalse(s.isColorComponentSelected(2))
    XCTAssertEqual(s.channelView.visible, [.red,.green])
    try s.selectColorComponentRow(0, modifiers: .shift)
    XCTAssertEqual(s.componentTarget, .green); XCTAssertTrue(s.modeComponentTargets.isEmpty)
    try s.selectColorComponentRow(1, modifiers: .shift)
    XCTAssertEqual(s.effectiveComponentTargets, [1]) // Current final-target policy, not a Photoshop claim.
    try s.selectColorComponentRow(nil, modifiers: .shift)
    XCTAssertTrue(s.isCompositeColorTarget); XCTAssertEqual(s.channelView.visible, RGBChannelView.components)
    try s.selectColorComponentRow(0, modifiers: .shift)
    XCTAssertEqual(s.effectiveComponentTargets, [1,2])
    try s.selectColorComponentRow(0, modifiers: .shift)
    XCTAssertTrue(s.isCompositeColorTarget); XCTAssertTrue(s.isColorComponentSelected(nil))
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertFalse(s.document.hasNativeModeStorage)
  }
  @MainActor func testAllModifierCombinationsUseSharedRowPolicyAtEveryRGBDepthAndCMYK() throws {
    let modifiers: [NSEvent.ModifierFlags] = [.control,.command,.option,.shift]
    let documents = [try fixture(), try ModeChannelWorkflowTests().fixture(.rgb,.u16),
      try ModeChannelWorkflowTests().fixture(.rgb,.f32), try ModeChannelWorkflowTests().fixture(.cmyk,.u16)]
    for document in documents {
      let s = EditorStore(document: document); defer { close(s) }
      for bits in 0..<16 {
        let flags = modifiers.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
        try s.selectColorComponentRow(0, modifiers: [])
        try s.selectColorComponentRow(1, modifiers: flags)
        XCTAssertEqual(s.effectiveComponentTargets, flags.contains(.shift) ? [0,1] : [1])
        XCTAssertEqual(s.document, document); XCTAssertTrue(s.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testPairFillAndInvertPreserveLiteralUntargetedAndAlphaBytesWithUndo() async throws {
    let original = try fixture()
    for values in [[0,1],[0,2],[1,2]] {
      let pair = Set(values)
      let s = EditorStore(document: original); defer { close(s) }
      try s.selectModeComponents(pair)
      try s.executeEditorCommand(s.componentFillCommand(value: 0, opacity: 1))
      let literal: [UInt8] = [19,101,211,127]
      XCTAssertEqual(try bytes(s.document), literal.enumerated().map { pair.contains($0.offset) ? 0 : $0.element })
      XCTAssertEqual(s.session.undoStack.count, 1)
      await s.undo(); XCTAssertEqual(s.document, original); XCTAssertEqual(s.effectiveComponentTargets, pair)
      try s.executeEditorCommand(.applyAdjustment(original.layers[0].id, .invert))
      XCTAssertEqual(try bytes(s.document), literal.enumerated().map { pair.contains($0.offset) ? 255 - $0.element : $0.element })
      await s.undo(); XCTAssertEqual(s.document, original)
      XCTAssertFalse(s.document.hasNativeModeStorage)
    }
  }
  @MainActor func testBrushAndFilterCapturePairPreviewCancelCommitAndStaleTargetGuards() async throws {
    let original = try fixture(), s = EditorStore(document: original); defer { close(s) }
    try s.selectModeComponents([0,2]); s.tool = .brush
    s.brush.size = 1; s.brush.hardness = 1; s.brush.color = .white
    s.beginBrush(.init(x: 2.5, y: 2.5), zoom: 1)
    guard case .modeComponents(let preview) = try XCTUnwrap(s.brushPreviewCommand) else { return XCTFail() }
    XCTAssertEqual(preview.components, [0,2]); XCTAssertEqual(s.document, original)
    XCTAssertThrowsError(try s.selectModeComponents([1]))
    s.cancelBrush(); XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginBrush(.init(x: 2.5, y: 2.5), zoom: 1); s.finishBrush(); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(try bytes(s.document), [255,101,255,127])
    XCTAssertEqual(s.session.undoStack.count, 1); await s.undo(); XCTAssertEqual(s.document, original)
    s.beginFilter(.highPass); let draft = try XCTUnwrap(s.filterDraft)
    XCTAssertEqual(draft.modeComponents, [0,2]); XCTAssertThrowsError(try s.selectModeComponents([1]))
    s.cancelFilter(); XCTAssertEqual(s.document, original)
    let command = Command.modeComponents(.init(layerID: original.layers[0].id, components: [0,2], operation: .invert))
    let prepared = try PreparedEdit(command: command, document: original)
    try s.selectModeComponents([1]); XCTAssertThrowsError(try s.executeCompositePreparedEdit(prepared, allowModeComponents: true))
    XCTAssertEqual(s.document, original)
  }
  @MainActor func testPreviewEyesAndQuickMaskAreIndependentOfSelectedPair() throws {
    let s = EditorStore(document: try fixture()); defer { close(s) }
    s.toggleQuickMask(); let original = s.document, mask = try XCTUnwrap(original.quickMask)
    try s.selectModeComponents([0,1]); XCTAssertNil(s.editingChannel)
    XCTAssertEqual(s.document.quickMask, mask); XCTAssertEqual(s.effectiveComponentTargets, [0,1])
    s.previewChannel(.blue)
    XCTAssertEqual(s.effectiveComponentTargets, [0,1]); XCTAssertEqual(s.modeVisibleComponents, [2])
    XCTAssertEqual(s.documentModeState["visibleComponents"] as? [Int], [2])
    XCTAssertEqual(s.documentModeState["editingComponents"] as? [Int], [0,1])
    try s.selectQuickMaskChannel(); XCTAssertTrue(s.effectiveComponentTargets.isEmpty)
    try s.selectModeComponents([1,2]); XCTAssertNil(s.editingChannel); XCTAssertEqual(s.document, original)
    let replacement = try fixture(); s.session = EditorSession(document: replacement)
    XCTAssertTrue(s.modeComponentTargets.isEmpty); XCTAssertTrue(s.isCompositeColorTarget)
  }
  @MainActor func testMaximumSparseCanvasPairFillAndLocalStrokeRemainBounded() async throws {
    let original = try fixture(width: 300000, height: 300000), s = EditorStore(document: original); defer { close(s) }
    try s.selectModeComponents([0,2]); try s.executeEditorCommand(s.componentFillCommand(value: 0, opacity: 1))
    XCTAssertEqual(try bytes(s.document, x: 299999, y: 299999), [0,101,0,127])
    let filled = s.document
    var brush = Brush(); brush.size = 1; brush.hardness = 1; brush.color = .white
    try s.executeEditorCommand(.stroke(original.layers[0].id, [.init(x: 299999.5, y: 299999.5)], brush))
    XCTAssertEqual(try bytes(s.document, x: 299999, y: 299999), [255,101,255,127])
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encode(s.document)), s.document)
    await s.undo(); XCTAssertEqual(s.document, filled); await s.undo(); XCTAssertEqual(s.document, original)
  }
  @MainActor func testHTTPPairSelectionStatePreviewFillAndLegacySingletonMatchNative() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let original = try self.fixture(); document.store.session = EditorSession(document: original); try service.share(document)
      let share = try XCTUnwrap(service.shares.first), desktop = EditorStore(document: original); defer { self.close(desktop) }
      for pair in [[0,1],[0,2],[1,2]] {
        try desktop.selectModeComponents(Set(pair))
        let selected = try await helper.edit(service, document, "mode.channel.select", ["components": pair])
        XCTAssertEqual(selected, 200); XCTAssertEqual(document.store.document, original); XCTAssertFalse(document.isDocumentEdited)
        let state = service.state(share, document: document)
        XCTAssertEqual(state["channelTarget"] as? String, desktop.colorComponentTargetTitle)
        let numerical = try XCTUnwrap(state["documentMode"] as? [String: Any])
        XCTAssertEqual(numerical["editingComponents"] as? [Int], pair); XCTAssertEqual(numerical["visibleComponents"] as? [Int], pair)
        let preview = try await helper.request(service, path: "/v1/documents/\(share.id)/channel-preview.png")
        XCTAssertEqual(preview.0.statusCode, 200)
        XCTAssertEqual(preview.1, try AutomationService.png(original, channelView: desktop.channelView))
        try desktop.executeEditorCommand(desktop.componentFillCommand(value: 0, opacity: 1))
        let filled = try await helper.edit(service, document, "channel.fill", ["value": 0, "opacity": 1])
        XCTAssertEqual(filled, 200); XCTAssertEqual(document.store.document, desktop.document)
        let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
        await desktop.undo(); XCTAssertEqual(document.store.document, original)
      }
      for components in [[],[0],[1],[2],[0,1,2]] as [[Int]] {
        let selected = try await helper.edit(service, document, "mode.channel.select", ["components": components])
        XCTAssertEqual(selected, 200); XCTAssertTrue(document.store.modeComponentTargets.isEmpty)
      }
      let singleton = try await helper.edit(service, document, "channel.target", ["channel": "Red"])
      XCTAssertEqual(singleton, 200); XCTAssertEqual(document.store.componentTarget, .red)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      let capabilities = try XCTUnwrap(DocumentModeAPI.capabilities["colorComponentSelection"] as? [String: Any])
      XCTAssertEqual(capabilities["ordinaryRGB8"] as? Bool, true); XCTAssertTrue(JSONSerialization.isValidJSONObject(capabilities))
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndMismatchedTargetsLeavePairAndSourceUntouched() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let original = try self.fixture(); document.store.session = EditorSession(document: original); try service.share(document)
      try document.store.selectModeComponents([0,2])
      let invalidSets: [[Double]] = [[-1],[3],[1,1],[0.5]]
      for values in invalidSets {
        let invalid = try await helper.edit(service, document, "mode.channel.select", ["components": values]); XCTAssertEqual(invalid, 400)
      }
      let stale = try await helper.edit(service, document, "mode.channel.select", ["components": [1]], revision: "stale")
      XCTAssertEqual(stale, 409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service, document, "mode.channel.select", ["components": [1]])
      XCTAssertEqual(busy, 409); document.store.geometryBusy = false
      let mismatch = try await helper.edit(service, document, "mode.channel.edit", ["layerID": original.layers[0].id.uuidString, "components": [1], "action": "invert"])
      XCTAssertEqual(mismatch, 422); XCTAssertEqual(document.store.effectiveComponentTargets, [0,2])
      XCTAssertEqual(document.store.document, original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
