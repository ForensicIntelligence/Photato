import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SmartObjectUnpackWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var source = try CraftDocument(width: 4, height: 3)
    source.layers[0].name = "Editable original"
    source.layers.append(Layer(name: "Editable fill", content: .fill(Pixel(1, 0, 0))))
    var parent = try CraftDocument(width: 4, height: 3)
    let placed = try SmartObjectIO.placed(data: NativeArchive.encode(source), fileName: "Owned.photato", in: parent, fit: false)
    parent.layers = [placed]; parent.activeLayerID = placed.id
    return parent
  }
  @MainActor func testNativeAndHTTPRestoreSameLayerDataAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let before = try self.fixture(); file.store.session = .init(document: before); try service.share(file)
      let native = EditorStore(document: before); defer { native.renderTask?.cancel() }
      XCTAssertTrue(native.canConvertSmartObjectToLayers())
      native.convertSmartObjectToLayers(); await native.geometryTask?.value
      XCTAssertNil(native.error); XCTAssertTrue(native.document.layers.last!.isGroup)
      let status = try await helper.edit(service, file, "smartObject.convertToLayers", ["layerIDs": [before.layers[0].id.uuidString]])
      XCTAssertEqual(status, 200); XCTAssertEqual(file.store.session.undoStack.count, 1)
      // Fresh IDs differ, so compare native pixel output and editable payloads,
      // and the relative hierarchy rather than requiring random UUID equality.
      XCTAssertEqual(file.store.document.layers.map(\.content), native.document.layers.map(\.content))
      XCTAssertEqual(file.store.document.layers.map(\.name), native.document.layers.map(\.name))
      XCTAssertEqual(try Renderer.composite(file.store.document), try Renderer.composite(native.document))
      XCTAssertEqual(file.store.document.layers[0].parentID, before.layers[0].id)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(file.store.document)), file.store.document)
      let undo = try await helper.edit(service, file, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertEqual(file.store.document, before)
      await native.undo(); XCTAssertEqual(native.document, before)
    }
  }
  @MainActor func testHTTPInvalidStaleBusyAndLockedRequestsAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let before = try self.fixture(); file.store.session = .init(document: before); try service.share(file)
      let ids = [before.layers[0].id.uuidString]
      let stale = try await helper.edit(service, file, "smartObject.convertToLayers", ["layerIDs": ids], revision: "stale")
      XCTAssertEqual(stale, 409)
      file.store.geometryBusy = true
      let busy = try await helper.edit(service, file, "smartObject.convertToLayers", ["layerIDs": ids]); XCTAssertEqual(busy, 409)
      file.store.geometryBusy = false
      for values in [[], ids + ids, [UUID().uuidString]] {
        let status = try await helper.edit(service, file, "smartObject.convertToLayers", ["layerIDs": values])
        XCTAssertNotEqual(status, 200); XCTAssertEqual(file.store.document, before)
      }
      var locked = before; locked.layers[0].locked = true; file.store.session = .init(document: locked)
      let status = try await helper.edit(service, file, "smartObject.convertToLayers", ["layerIDs": ids])
      XCTAssertEqual(status, 422); XCTAssertEqual(file.store.document, locked)
      XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testCancellationAndRevokedShareDoNotPublishRestoredLayers() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let before = try self.fixture(); file.store.session = .init(document: before); try service.share(file)
      let share = try XCTUnwrap(service.shares.first?.id), revision = service.revision(file.store)
      let task = Task {
        try await service.executePreparedOperation(document: file, shareID: share, revision: revision) { original in
          let command = try SmartObjectUnpack.command(in: original, selected: [original.layers[0].id])
          try await Task.sleep(for: .seconds(5))
          return command
        }
      }
      for _ in 0..<200 where !file.store.geometryBusy { try await Task.sleep(for: .milliseconds(5)) }
      file.store.cancelActiveOperation()
      do { try await task.value; XCTFail("Cancelled conversion committed") } catch {}
      XCTAssertEqual(file.store.document, before)
      do {
        try await service.executePreparedOperation(document: file, shareID: share, revision: revision,
          validateCommit: { service.revoke(share); throw AutomationFailure(status: 409, message: "Revoked") }) { original in
            try SmartObjectUnpack.command(in: original, selected: [original.layers[0].id])
          }
        XCTFail("Revoked conversion committed")
      } catch {}
      XCTAssertEqual(file.store.document, before); XCTAssertTrue(file.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testContextTargetsAndFactoryMenuBindingAndSchemas() throws {
    var model = try fixture(), other = model.layers[0]; other.id = UUID()
    model.layers.append(other)
    let store = EditorStore(document: model); defer { store.renderTask?.cancel() }
    store.selectedLayerIDs = [model.layers[0].id]
    XCTAssertEqual(store.layerPanelSelection(other.id), [other.id])
    XCTAssertTrue(store.canConvertSmartObjectToLayers(context: other.id))
    store.geometryBusy = true; XCTAssertFalse(store.canConvertSmartObjectToLayers(context: other.id)); store.geometryBusy = false
    let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == "smartObject.convertToLayers" })
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: definition.schema))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: SmartObject.apiCapabilities))
    XCTAssertEqual(AutomationCommand.definitions.count, 267)
    XCTAssertEqual(ActionLibraryFile.maximumVersion, 60)
    try PhotoshopMenuTests().withMenus { _, menu in
      func find(_ menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
          if item.identifier?.rawValue == "Layer > Smart Objects > Convert to Layers" { return item }
          if let submenu = item.submenu, let result = find(submenu) { return result }
        }
        return nil
      }
      let item = try XCTUnwrap(find(menu))
      XCTAssertEqual(item.action, #selector(AppDelegate.convertSmartObjectToLayers))
      XCTAssertTrue(item.keyEquivalent.isEmpty)
    }
  }
}
