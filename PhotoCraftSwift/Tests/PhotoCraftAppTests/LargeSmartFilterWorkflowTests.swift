import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeSmartFilterWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:300_000,height:300_000)
    try SmartObjectIO.convert(in:d,selected:[d.layers[0].id]).apply(to:&d)
    return d
  }
  @MainActor func testHTTPMaximumSmartObjectConversionPixelsUndoAndGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let initial=try CraftDocument(width:300_000,height:300_000),id=try XCTUnwrap(initial.activeLayerID)
      shared.store.session=EditorSession(document:initial)
      shared.store.updateViewport(size:CGSize(width:600,height:400),backingScale:1);try service.share(shared)
      let parameters:[String:Any]=["layerIDs":[id.uuidString]]
      let stale=try await helper.edit(service,shared,"smartObject.convert",parameters,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.geometryBusy=true;let busy=try await helper.edit(service,shared,"smartObject.convert",parameters);XCTAssertEqual(busy,409);shared.store.geometryBusy=false
      let invalid=try await helper.edit(service,shared,"smartObject.convert",["layerIDs":[]]);XCTAssertEqual(invalid,400);XCTAssertEqual(shared.store.document,initial)
      let converted=try await helper.edit(service,shared,"smartObject.convert",parameters);XCTAssertEqual(converted,200)
      let result=shared.store.document,source=try SmartObjectIO.sourceDocument(XCTUnwrap(result.layers[0].smartObject))
      XCTAssertEqual(source.width,initial.width);XCTAssertEqual(source.height,initial.height)
      XCTAssertEqual(source.layers[0].content,initial.layers[0].content)
      XCTAssertEqual(try Renderer.composite(result),try Renderer.composite(fixture()))
      let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,initial)
    }
  }
  @MainActor func testNativeMaximumSmartFilterPreviewEditBlendCancelHistoryAndPersistence()async throws {
    let d=try fixture(),id=d.layers[0].id,store=EditorStore(document:d)
    defer{store.renderTask?.cancel();store.geometryTask?.cancel()}
    store.updateViewport(size:CGSize(width:600,height:400),backingScale:1)
    XCTAssertTrue(store.canBeginFilterKind(.highPass));XCTAssertFalse(store.canBeginFilterKind(.cameraRaw))
    store.beginFilter(.highPass);await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image);XCTAssertEqual(store.document,d)
    store.cancelFilter();await store.renderTask?.value;XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginFilter(.highPass);store.commitFilter();await store.geometryTask?.value;await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document.layers[0].smartObject,d.layers[0].smartObject)
    XCTAssertEqual(store.document.layers[0].content,d.layers[0].content)
    let first=store.document,filterID=try XCTUnwrap(first.layers[0].smartFilters?.filters[0].id)
    store.beginSmartFilter(id,filterID:filterID);store.filterDraft?.opacity=0.5;store.filterDraft?.blendMode = .multiply
    store.commitFilter();await store.geometryTask?.value;await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document.layers[0].smartFilters?.filters[0].opacity,0.5)
    let edited=store.document;XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(edited)),edited)
    await store.undo();await store.renderTask?.value;XCTAssertEqual(store.document,first)
    await store.undo();await store.renderTask?.value;XCTAssertEqual(store.document,d)
    await store.redo();await store.renderTask?.value;XCTAssertEqual(store.document,first)
  }
  @MainActor func testHTTPMaximumSmartStackMatchesNativePixelsAndGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let d=try fixture(),id=d.layers[0].id,native=EditorStore(document:d)
      defer{native.renderTask?.cancel()}
      var stack=SmartFilterStack();stack.filters=[SmartFilter(filter:RasterFilter(.highPass),opacity:0.5,blendMode:.multiply)]
      try stack.createMask(in:d)
      try native.executeEditorCommand(.smartFilters(id,stack))
      native.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1);native.setZoom(2048/300_000,center:true);await native.renderTask?.value
      shared.store.session=EditorSession(document:d)
      shared.store.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1);shared.store.setZoom(2048/300_000,center:true);try service.share(shared)
      var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let params:[String:Any]=["layerID":id.uuidString,"stack":payload]
      let stale=try await helper.edit(service,shared,"smartFilter.set",params,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.geometryBusy=true;let busy=try await helper.edit(service,shared,"smartFilter.set",params);XCTAssertEqual(busy,409);shared.store.geometryBusy=false
      let invalid=try await helper.edit(service,shared,"smartFilter.set",["layerID":id.uuidString,"stack":["enabled":1,"filters":[]]]);XCTAssertEqual(invalid,400);XCTAssertEqual(shared.store.document,d)
      let applied=try await helper.edit(service,shared,"smartFilter.set",params);XCTAssertEqual(applied,200);XCTAssertEqual(shared.store.document,native.document)
      let sharedID=try XCTUnwrap(service.shares.first?.id),preview=try await helper.request(service,path:"/v1/documents/\(sharedID)/preview.png")
      XCTAssertEqual(preview.0.statusCode,200)
      XCTAssertEqual(try LargeCompositionWorkflowTests().pixels(preview.1),try RasterIO.surface(XCTUnwrap(native.image)))
      let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
      let cap=try XCTUnwrap(SmartFilterStack.apiCapabilities["largeRGBStacks"]as?[String:Any]);XCTAssertEqual((cap["kinds"]as?[String])?.count,8)
      XCTAssertEqual((SmartObject.apiCapabilities["largeRGBSources"]as?[String:Any])?["logicalMaximumPixels"]as?Int,Surface.maxPixels)
      XCTAssertEqual(EmbeddedSourceAPI.capabilities["maximumRGBSourcePixels"]as?Int,Surface.maxPixels)
    }
  }
}
