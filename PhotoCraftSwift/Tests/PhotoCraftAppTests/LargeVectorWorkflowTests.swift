import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeVectorWorkflowTests:XCTestCase {
  @MainActor func testMaximumNativeAndHTTPVectorMaskPreviewHistoryPersistenceAndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      var initial=try CraftDocument(width:300_000,height:300_000)
      let points=[PathPoint(299_980,299_980),PathPoint(299_996,299_980),PathPoint(299_996,299_996),PathPoint(299_980,299_996)]
      let path=VectorPath(components:[PathComponent(knots:points.map{PathKnot($0)},closed:true)],inverted:true)
      let saved=NamedPath(name:"Owned path",path:path);initial.paths=[saved]
      let layer=try XCTUnwrap(initial.activeLayerID),native=EditorStore(document:initial)
      defer {native.renderTask?.cancel()}
      native.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1);native.setZoom(2048/300_000,center:true)
      try native.executeEditorCommand(.vectorMask(layer,VectorMask(path:path)))
      await native.renderTask?.value;XCTAssertNil(native.error)
      let expected=native.document;XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encode(expected)),expected)
      document.store.session=EditorSession(document:initial)
      document.store.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1);document.store.setZoom(2048/300_000,center:true)
      try service.share(document)
      let params:[String:Any]=["operation":"vectorMask","layerID":layer.uuidString,"pathID":saved.id.uuidString]
      let stale=try await helper.edit(service,document,"path.edit",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"path.edit",params);XCTAssertEqual(busy,409)
      document.store.geometryBusy=false
      let changed=try await helper.edit(service,document,"path.edit",params);XCTAssertEqual(changed,200)
      XCTAssertEqual(document.store.document,expected);XCTAssertEqual(document.store.session.undoStack.count,1)
      document.store.render();await document.store.renderTask?.value;XCTAssertNil(document.store.error)
      let id=try XCTUnwrap(service.shares.first?.id),response=try await helper.request(service,path:"/v1/documents/\(id)/preview.png")
      XCTAssertEqual(response.0.statusCode,200)
      XCTAssertEqual(try LargeCompositionWorkflowTests().pixels(response.1),try RasterIO.surface(XCTUnwrap(native.image)))
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,initial)
      let redo=try await helper.edit(service,document,"history.redo");XCTAssertEqual(redo,200);XCTAssertEqual(document.store.document,expected)
      let capability=try XCTUnwrap(RasterStorageAPI.capabilities["pagedComposition"]as?[String:Any]);XCTAssertEqual(capability["unfeatheredVectorMasks"]as?Bool,true)
      XCTAssertEqual(capability["vectorGrayScratchMaximumBytes"]as?Int,90_000_300_000)
    }
  }
}
