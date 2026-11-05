import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MaskRemovalWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u16, smart: Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 8, depth: depth)
    d.layers[0].background = nil
    d.layers[0].content = .raster(try Surface(width: 8, height: 8, depth: depth, fill: Pixel(0.8, 0.2, 0.1, 0.8)))
    var id = d.layers[0].id
    if smart {
      try SmartObjectIO.convert(in: d, selected: [id]).apply(to: &d)
      id = d.layers[0].id
      var filter = RasterFilter(.mosaic); filter.cellSize = 2
      try Command.applyFilter(id, filter).apply(to: &d)
    }
    d.layers[0].mask = try Surface(width: 8, height: 8, depth: depth, fill: Pixel(0.5, 0.5, 0.5))
    d.layers[0].maskProperties = MaskProperties()
    d.layers[0].vectorMask = VectorMask(path: VectorPath())
    d.activeLayerID = id
    try d.validate()
    return d
  }
  @MainActor func select(_ target: ManagedMaskTarget, in store: EditorStore) {
    let id = store.document.layers[0].id
    switch target {
    case .layerMask: store.selectMask(id)
    case .vectorMask: store.selectPath(.vectorMask(id), revealPanel: false)
    case .smartFilterMask: store.selectSmartFilterMask(id)
    }
  }

  @MainActor func testSelectedMaskFooterMatchesHTTPPreservesLayerOtherMasksAndUndo() async throws {
    let helper = AutomationTests()
    try await helper.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, shared in
      for depth in PixelDepth.allCases {
        for target in ManagedMaskTarget.allCases {
          for operation in target == .layerMask ? [MaskManagementRequest.Operation.delete, .apply] : [.delete] {
            let original = try fixture(depth, smart: target == .smartFilterMask), id = original.layers[0].id
            shared.store.session = EditorSession(document: original)
            shared.store.selectedLayerIDs = [id]
            select(target, in: shared.store)
            if service.shares.isEmpty { try service.share(shared) }
            let native = EditorStore(document: original, actions: ActionLibrary())
            defer { native.renderTask?.cancel() }
            if target != .vectorMask { try native.startRecordingAction(name: "Remove Mask", set: "Test") }
            select(target, in: native)
            XCTAssertEqual(native.footerMaskTarget, target)
            XCTAssertTrue(native.canDeleteFromLayerFooter)
            XCTAssertFalse(native.canRequestLayerDeletion(), "The sole layer must survive mask deletion.")
            native.layerDeletionConfirmation = { _ in XCTFail("Mask trash cannot delete its layer."); return .contents }
            native.maskRemovalConfirmation = { prompt in
              XCTAssertEqual(prompt.target, target)
              XCTAssertTrue(native.confirmingLayerDeletion)
              XCTAssertFalse(native.canBeginLayerCreation)
              return operation == .apply ? .apply : .delete
            }
            native.deleteLayersFromFooter(modifiers: [])
            await native.geometryTask?.value
            XCTAssertNil(native.error)
            let result = native.document
            XCTAssertEqual(result.layers.count, 1); XCTAssertEqual(result.layers[0].id, id)
            XCTAssertEqual(result.layers[0].smartObject, original.layers[0].smartObject)
            switch target {
            case .layerMask:
              XCTAssertNil(result.layers[0].mask)
              XCTAssertEqual(result.layers[0].vectorMask, original.layers[0].vectorMask)
              if operation == .delete { XCTAssertEqual(result.layers[0].content, original.layers[0].content) }
              else { XCTAssertNotEqual(result.layers[0].content, original.layers[0].content) }
            case .vectorMask:
              XCTAssertNil(result.layers[0].vectorMask)
              XCTAssertEqual(result.layers[0].mask, original.layers[0].mask)
              XCTAssertEqual(result.layers[0].content, original.layers[0].content)
            case .smartFilterMask:
              XCTAssertNil(result.layers[0].smartFilters?.mask)
              XCTAssertEqual(result.layers[0].smartFilters?.filters, original.layers[0].smartFilters?.filters)
              XCTAssertEqual(result.layers[0].mask, original.layers[0].mask)
            }
            XCTAssertEqual(native.session.undoStack.count, 1)
            XCTAssertNil(native.footerMaskTarget)
            if target != .vectorMask {
              let action = try native.stopRecordingAction()
              var replay = original; try action.apply(to: &replay)
              XCTAssertEqual(replay, result)
            }
            let parameters: [String: Any] = ["layerID": id.uuidString, "target": target.rawValue, "operation": operation.rawValue]
            var status = try await helper.edit(service, shared, MaskManagementAPI.command, parameters)
            XCTAssertEqual(status, 200); XCTAssertEqual(shared.store.document, result)
            XCTAssertNil(shared.store.footerMaskTarget)
            XCTAssertEqual(try NativeArchive.encodeChunked(shared.store.document), try NativeArchive.encodeChunked(result))
            XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)
            XCTAssertEqual(shared.store.session.undoStack.count, 1)
            await native.undo(); status = try await helper.edit(service, shared, "history.undo")
            XCTAssertEqual(status, 200); XCTAssertEqual(native.document, original); XCTAssertEqual(shared.store.document, original)
            await native.redo(); status = try await helper.edit(service, shared, "history.redo")
            XCTAssertEqual(status, 200); XCTAssertEqual(native.document, result); XCTAssertEqual(shared.store.document, result)
          }
        }
      }
    }
  }

  @MainActor func testAllModifiersCancelBusyLockedAndStaleConfirmationCannotDeleteLayer() async throws {
    let original = try fixture(), id = original.layers[0].id
    let flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      let store = EditorStore(document: original)
      defer { store.renderTask?.cancel() }
      select(.layerMask, in: store)
      var prompts = 0
      store.maskRemovalConfirmation = { _ in prompts += 1; return .cancel }
      let modifiers = flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
      store.deleteLayersFromFooter(modifiers: modifiers); await store.geometryTask?.value
      XCTAssertEqual(prompts, modifiers.contains(.option) ? 0 : 1)
      XCTAssertEqual(store.document.layers.count, 1)
      XCTAssertEqual(store.document.layers[0].mask == nil, modifiers.contains(.option))
      XCTAssertEqual(store.session.undoStack.count, modifiers.contains(.option) ? 1 : 0)
    }
    for stale in ["content", "target", "session"] {
      let store = EditorStore(document: original)
      defer { store.renderTask?.cancel() }
      select(.layerMask, in: store)
      store.maskRemovalConfirmation = { _ in
        if stale == "content" { try! store.session.execute(.renameLayer(id, "Changed")) }
        if stale == "target" { store.maskEditingLayerID = nil }
        if stale == "session" { store.session = EditorSession(document: original) }
        return .delete
      }
      store.deleteLayersFromFooter(modifiers: [])
      XCTAssertNotNil(store.error); XCTAssertNotNil(store.document.layers[0].mask)
      XCTAssertEqual(store.document.layers.count, 1); XCTAssertFalse(store.confirmingLayerDeletion)
    }
    var locked = original; locked.layers[0].locked = true
    let store = EditorStore(document: locked)
    defer { store.renderTask?.cancel() }
    select(.layerMask, in: store)
    store.maskRemovalConfirmation = { _ in XCTFail("Locked mask cannot prompt."); return .delete }
    XCTAssertFalse(store.canDeleteFromLayerFooter)
    store.deleteLayersFromFooter(modifiers: [.option]); XCTAssertEqual(store.document, locked)
    store.session = EditorSession(document: original); select(.layerMask, in: store)
    store.geometryBusy = true
    XCTAssertFalse(store.canDeleteFromLayerFooter)
    store.deleteLayersFromFooter(modifiers: [.option]); XCTAssertEqual(store.document, original)
    store.geometryBusy = false
  }

  @MainActor func testAPIInvalidBusyStaleSchemasAndNativeAlertChoices() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      let original = try fixture(), id = original.layers[0].id
      shared.store.session = EditorSession(document: original); shared.store.selectedLayerIDs = [id]
      select(.layerMask, in: shared.store); try service.share(shared)
      let parameters: [String: Any] = ["layerID": id.uuidString, "operation": "delete"]
      for invalid: [String: Any] in [["target": "unknown"], ["target": true], ["operation": "remove"], ["layerID": false]] {
        var request = parameters; for (k, v) in invalid { request[k] = v }
        let status = try await helper.edit(service, shared, MaskManagementAPI.command, request)
        XCTAssertEqual(status, 400); XCTAssertEqual(shared.store.document, original)
      }
      var status = try await helper.edit(service, shared, MaskManagementAPI.command, parameters, revision: "stale")
      XCTAssertEqual(status, 409)
      shared.store.confirmingLayerDeletion = true
      status = try await helper.edit(service, shared, MaskManagementAPI.command, parameters)
      XCTAssertEqual(status, 409); shared.store.confirmingLayerDeletion = false
      status = try await helper.edit(service, shared, MaskManagementAPI.command,
        ["layerID": id.uuidString, "target": "vectorMask", "operation": "apply"])
      XCTAssertEqual(status, 422); XCTAssertEqual(shared.store.document, original)
      let state = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: shared.store.maskManagementState))
      XCTAssertNoThrow(try BrushAPI.merge(state, schema: MaskManagementAPI.stateSchema))
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
      XCTAssertEqual(ActionLibraryFile.maximumVersion, 49)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: MaskManagementAPI.capabilities))
      status = try await helper.edit(service, shared, MaskManagementAPI.command, parameters)
      XCTAssertEqual(status, 200); XCTAssertNil(shared.store.document.layers[0].mask)
    }
    for (target, apply) in [(ManagedMaskTarget.layerMask, true), (.layerMask, false), (.vectorMask, false), (.smartFilterMask, false)] {
      let alert = MaskRemovalAlert.make(.init(target: target, layerName: "Owned artwork", canApply: apply))
      XCTAssertEqual(alert.buttons.map(\.title), target == .layerMask ? ["Apply", "Delete", "Cancel"] : ["Delete", "Cancel"])
      if target == .layerMask { XCTAssertEqual(alert.buttons[0].isEnabled, apply) }
      XCTAssertEqual(alert.buttons.last?.keyEquivalent, "\u{1b}")
      alert.layout()
      let view = try XCTUnwrap(alert.window.contentView)
      for button in alert.buttons { XCTAssertTrue(view.bounds.contains(button.convert(button.bounds, to: view))) }
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
          URL(fileURLWithPath: path).appendingPathComponent("mask-removal-\(target.rawValue)-\(apply).png"))
      }
    }
  }
}
