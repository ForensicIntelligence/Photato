import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeFilterWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {try CraftDocument(width:300_000,height:300_000)}
  @MainActor func testNativeMaximumFilterDialogPreviewCancelCommitUndoAndPersistence() async throws {
    let initial=try fixture(),store=EditorStore(document:initial)
    defer{store.renderTask?.cancel();store.geometryTask?.cancel()}
    store.updateViewport(size:CGSize(width:600,height:400),backingScale:1)
    XCTAssertTrue(store.canBeginFilterKind(.highPass));XCTAssertFalse(store.canBeginFilterKind(.cameraRaw))
    store.beginFilter(.highPass);store.render();await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image);XCTAssertEqual(store.document,initial);XCTAssertEqual(store.session.undoStack.count,0)
    store.cancelFilter();await store.renderTask?.value;XCTAssertEqual(store.document,initial)
    store.beginFilter(.highPass);store.commitFilter();await store.geometryTask?.value;await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertNotEqual(store.document,initial)
    let result=store.document;XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encode(result)),result)
    await store.undo();await store.renderTask?.value;XCTAssertEqual(store.document,initial)
    await store.redo();await store.renderTask?.value;XCTAssertEqual(store.document,result)
  }
  @MainActor func testHTTPMaximumFilterMatchesNativePixelsHistoryAndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let initial=try fixture(),native=EditorStore(document:initial),id=try XCTUnwrap(initial.activeLayerID)
      defer{native.renderTask?.cancel()}
      native.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1);native.setZoom(2048/300_000,center:true)
      try native.executeEditorCommand(.applyFilter(id,RasterFilter(.highPass)));await native.renderTask?.value;XCTAssertNil(native.error)
      document.store.session=EditorSession(document:initial)
      document.store.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1);document.store.setZoom(2048/300_000,center:true);try service.share(document)
      let params:[String:Any]=["layerID":id.uuidString,"filter":["kind":"highPass","radius":5]]
      let stale=try await helper.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let invalid=try await helper.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"highPass","radius":0]]);XCTAssertEqual(invalid,400)
      XCTAssertEqual(document.store.document,initial)
      let edited=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document,native.document)
      let shared=try XCTUnwrap(service.shares.first?.id),response=try await helper.request(service,path:"/v1/documents/\(shared)/preview.png")
      XCTAssertEqual(response.0.statusCode,200)
      XCTAssertEqual(try LargeCompositionWorkflowTests().pixels(response.1),try RasterIO.surface(XCTUnwrap(native.image)))
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,initial)
      let cap=try XCTUnwrap(RasterFilter.apiCapabilities["largeBasicRasterFilters"]as?[String:Any]);XCTAssertEqual((cap["kinds"]as?[String])?.count,8)
    }
  }
}
