import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class LayerDeletionWorkflowTests: XCTestCase {
  @MainActor func testFactoryRenameGroupTitleAndDeleteMenuReachNativeConfirmation() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let document = CraftNSDocument(model: try CraftDocument(width: 3, height: 2))
      app.controller.addDocument(document)
      document.makeWindowControllers()
      XCTAssertTrue(app.controller.documentWindows.activate(document))
      defer { document.close() }
      let store = document.store
      store.groupSelection()
      let group = try XCTUnwrap(store.activeLayer)
      let rename = try XCTUnwrap(
        PhotoshopMenuTests().allItems(menu).first {
          $0.action == #selector(AppDelegate.renameLayer)
        })
      XCTAssertTrue(app.validateMenuItem(rename))
      XCTAssertEqual(rename.title, "Rename Group…")
      XCTAssertEqual(rename.keyEquivalent, "")
      var requests = 0
      store.layerDeletionConfirmation = { request in
        requests += 1
        XCTAssertEqual(request.group?.id, group.id)
        return .cancel
      }
      app.delete()
      XCTAssertEqual(requests, 1)
      XCTAssertEqual(store.activeLayer, group)
    }
  }
  @MainActor func testCancelPreservesDocumentAndConfirmedDeleteUndoesOnce() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let original = store.document
    let ids = original.layers.map(\.id)
    store.selectedLayerIDs = [ids[0], ids[2]]
    var requests = 0
    store.layerDeletionConfirmation = { request in
      requests += 1
      XCTAssertEqual(request.selected, [ids[0], ids[2]])
      XCTAssertTrue(store.confirmingLayerDeletion)
      XCTAssertFalse(store.canBeginLayerCreation)
      store.perform(.renameLayer(ids[1], "Must not edit under dialog"))
      return .cancel
    }
    store.requestLayerDeletion()
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(store.selectedLayerIDs, [ids[0], ids[2]])
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(store.confirmingLayerDeletion)
    store.layerDeletionConfirmation = { _ in .contents }
    store.requestLayerDeletion()
    XCTAssertEqual(store.document.layers.map(\.id), [ids[1]])
    XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo()
    XCTAssertEqual(store.document, original)
  }
  @MainActor func testFooterOptionBypassesPromptAndPlainClickPrompts() throws {
    for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.option, .shift]] {
      let store = try GroupWorkflowTests().store()
      defer { store.renderTask?.cancel() }
      var requests = 0
      store.layerDeletionConfirmation = { _ in
        requests += 1
        return .cancel
      }
      store.deleteLayersFromFooter(modifiers: flags)
      XCTAssertEqual(requests, flags.contains(.option) ? 0 : 1)
      XCTAssertEqual(store.document.layers.count, flags.contains(.option) ? 2 : 3)
    }
  }
  @MainActor func testStaleConfirmationDoesNotDeleteChangedDocumentOrSelection() throws {
    for changeSelection in [false, true] {
      let store = try GroupWorkflowTests().store()
      defer { store.renderTask?.cancel() }
      let ids = store.document.layers.map(\.id)
      store.layerDeletionConfirmation = { _ in
        if changeSelection {
          store.selectedLayerIDs = [ids[2]]
        } else {
          try! store.session.execute(.renameLayer(ids[1], "External"))
        }
        return .contents
      }
      store.requestLayerDeletion()
      XCTAssertEqual(store.document.layers.count, 3)
      XCTAssertNotNil(store.error)
      XCTAssertFalse(store.confirmingLayerDeletion)
      XCTAssertEqual(store.session.undoStack.count, changeSelection ? 0 : 1)
    }
  }
  @MainActor func testGroupOnlyKeepsEditableChildrenWithOneUndo() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.selectedLayerIDs = Set(store.document.layers.map(\.id))
    store.groupSelection()
    let original = store.document
    let group = try XCTUnwrap(store.activeLayer)
    XCTAssertTrue(store.canRequestLayerDeletion())
    let request = LayerDeletionRequest(original: original, selected: [group.id])
    XCTAssertFalse(request.canDeleteContents)
    XCTAssertTrue(request.canDeleteGroupOnly)
    store.layerDeletionConfirmation = { _ in .groupOnly }
    store.requestLayerDeletion()
    XCTAssertEqual(store.document.layers.count, 3)
    XCTAssertTrue(store.document.layers.allSatisfy { !$0.isGroup && $0.parentID == nil })
    for child in store.document.layers {
      XCTAssertEqual(child.content, original.layers.first { $0.id == child.id }?.content)
    }
    XCTAssertEqual(store.session.undoStack.count, 2)
    await store.undo()
    XCTAssertEqual(store.document, original)
  }
  @MainActor func testNativeAlertsShowChoicesAndFinalLayerNeverPrompts() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let request = LayerDeletionRequest(original: store.document, selected: store.groupSelectionIDs)
    let alert = LayerDeletionAlert.make(request)
    XCTAssertEqual(alert.buttons.map(\.title), ["Yes", "No"])
    XCTAssertEqual(alert.buttons[1].keyEquivalent, "\u{1b}")
    XCTAssertTrue(alert.messageText.contains(store.activeLayer!.name))
    store.selectedLayerIDs = Set(store.document.layers.map(\.id))
    store.groupSelection()
    let groupAlert = LayerDeletionAlert.make(
      LayerDeletionRequest(original: store.document, selected: store.groupSelectionIDs))
    XCTAssertEqual(groupAlert.buttons.map(\.title), ["Group and Contents", "Group Only", "Cancel"])
    XCTAssertFalse(groupAlert.buttons[0].isEnabled)
    XCTAssertTrue(groupAlert.buttons[1].isEnabled)
    XCTAssertEqual(groupAlert.buttons[0].keyEquivalent, "")
    XCTAssertEqual(groupAlert.buttons[1].keyEquivalent, "\r")
    for candidate in [alert, groupAlert] {
      candidate.layout()
      let content = try XCTUnwrap(candidate.window.contentView)
      for button in candidate.buttons {
        XCTAssertGreaterThan(button.frame.width, 40)
        XCTAssertGreaterThan(button.frame.height, 15)
        XCTAssertTrue(content.bounds.contains(button.convert(button.bounds, to: content)))
      }
    }

    let single = EditorStore(document: try CraftDocument(width: 2, height: 2))
    defer { single.renderTask?.cancel() }
    single.layerDeletionConfirmation = { _ in
      XCTFail("Final layer cannot be deleted")
      return .contents
    }
    single.requestLayerDeletion()
    single.requestLayerDeletion(bypassingConfirmation: true)
    XCTAssertEqual(single.document.layers.count, 1)
  }
}
