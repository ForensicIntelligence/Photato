import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PSDPathWorkflowTests: XCTestCase {
  @MainActor private static var bootstrap: CraftDocumentController?
  @MainActor private func bootstrapApp() {
    if Self.bootstrap == nil {
      Self.bootstrap = CraftDocumentController(workspaces:WorkspaceLibrary())
    }
    _ = NSApplication.shared
  }
  private func model() throws -> CraftDocument {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/psd-path-semantics")
    return try PSDCodec.read(Data(contentsOf:folder.appendingPathComponent("photoshop-path-semantics.psd")))
  }
  @MainActor func testNativeImportedPathSelectionPreviewCancelUndoAndPersistence() async throws {
    bootstrapApp()
    var initial=try model()
    let layer=try XCTUnwrap(initial.layers.first(where:{$0.name=="Subtract then Intersect"}))
    initial.activeLayerID=layer.id
    let store=EditorStore(document:initial)
    defer {store.renderTask?.cancel()}
    store.selectPath(.vectorMask(layer.id))
    store.tool = .directSelection
    store.beginPath(at:.init(4,4),tolerance:2)
    store.dragPath(to:.init(5,5))
    XCTAssertEqual(store.document,initial)
    XCTAssertNotEqual(store.previewDocument,initial)
    store.finishPath(cancelGesture:true)
    XCTAssertEqual(store.previewDocument,initial)
    store.pathToSelection()
    XCTAssertNil(store.error)
    XCTAssertEqual(store.document.selectionCoverage(x:20,y:20),0)
    XCTAssertEqual(store.document.selectionCoverage(x:30,y:20),1)
    let selected=store.document
    XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(selected)),selected)
    await store.undo();XCTAssertEqual(store.document,initial)
    await store.redo();XCTAssertEqual(store.document,selected)
  }
  @MainActor func testRealHTTPImportedPathSelectionMatchesNativeHistoryAndRejectsStaleOrBusy() async throws {
    bootstrapApp()
    var initial=try model()
    let layer=try XCTUnwrap(initial.layers.first(where:{$0.name=="Subtract then Intersect"}))
    initial.activeLayerID=layer.id
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      document.store.session=EditorSession(document:initial)
      document.store.selectPath(.vectorMask(layer.id))
      let native=EditorStore(document:initial)
      defer {native.renderTask?.cancel()}
      native.selectPath(.vectorMask(layer.id));native.pathToSelection()
      XCTAssertNil(native.error)
      try service.share(document)
      let parameters:[String:Any]=["operation":"selection"]
      let stale=try await helper.edit(service,document,"path.edit",parameters,revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,initial)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"path.edit",parameters)
      XCTAssertEqual(busy,409);XCTAssertEqual(document.store.document,initial)
      document.store.geometryBusy=false
      let edited=try await helper.edit(service,document,"path.edit",parameters)
      XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document,native.document)
      XCTAssertEqual(document.store.session.undoStack.count,1)
      let undo=try await helper.edit(service,document,"history.undo")
      XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,initial)
      let redo=try await helper.edit(service,document,"history.redo")
      XCTAssertEqual(redo,200);XCTAssertEqual(document.store.document,native.document)
      let filling=try XCTUnwrap(PathAPI.capabilities["vectorFilling"] as? [String:Any])
      XCTAssertNotNil(filling["leadingSubtract"]);XCTAssertNotNil(filling["PSD"])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:PathAPI.capabilities))
      let capability=try await helper.request(service,path:"/v1/capabilities")
      XCTAssertEqual(capability.0.statusCode,200)
      XCTAssertTrue(String(decoding:capability.1,as:UTF8.self).contains("leadingSubtract"))
    }
  }
}
