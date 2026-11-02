import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class BackgroundLayerWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {try DocumentCreation.blank(width:9,height:7,depth:depth)}
  @MainActor func testNativeSheetCancelCommitGuardHistoryAndActions32()async throws {
    let original=try fixture(),s=EditorStore(document:original);defer{s.backgroundLayerDraft=nil;s.renderTask?.cancel()}
    XCTAssertTrue(s.canConvertBackground);XCTAssertFalse(s.canBeginLayerOpacity);s.beginBackgroundConversion();let canceled=try XCTUnwrap(s.backgroundLayerDraft);XCTAssertTrue(s.hasToneDraft);XCTAssertFalse(s.canNavigateHistory);s.backgroundLayerDraft=nil;s.commitBackgroundConversion(canceled);XCTAssertEqual(s.document,original)
    s.beginBackgroundConversion();let draft=try XCTUnwrap(s.backgroundLayerDraft);draft.options.name="Editable";draft.opacity=62.5;draft.options.mode = .multiply;try s.session.startActionRecording(name:"Background");s.commitBackgroundConversion(draft);XCTAssertNil(s.backgroundLayerDraft);XCTAssertNil(s.error);XCTAssertFalse(s.activeLayer?.isBackground ?? true);XCTAssertEqual(s.activeLayer?.opacity,0.625);XCTAssertTrue(s.canBeginLayerOpacity)
    var file=ActionLibraryFile();file.actions=[try XCTUnwrap(s.session.actionRecording?.snapshot)];XCTAssertEqual(try ActionLibraryFile.decode(file.encoded()).version,32);var replay=original;try file.actions[0].apply(to:&replay);XCTAssertEqual(replay,s.document);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)
    s.beginLayerName(original.layers[0].id);XCTAssertNotNil(s.backgroundLayerDraft);XCTAssertNil(s.layerNameDraft);s.backgroundLayerDraft=nil;s.toggleFullLayerProtection();XCTAssertEqual(s.activeLayer?.name,"Layer 0");XCTAssertFalse(s.activeLayer?.isBackground ?? true)
  }
  @MainActor func testNativeStaleReadCloseAndFactoryMenuLifecycle()throws {
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.backgroundLayerDraft=nil;s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}
    s.beginBackgroundConversion();let draft=try XCTUnwrap(s.backgroundLayerDraft);try s.session.execute(.visibility(s.document.layers[0].id,false));s.commitBackgroundConversion(draft);XCTAssertNotNil(draft.error);XCTAssertTrue(s.activeLayer?.isBackground ?? false)
    try doc.read(from:NativeArchive.encodeChunked(fixture()),ofType:CraftNSDocument.nativeType);XCTAssertNil(s.backgroundLayerDraft);s.beginBackgroundConversion();doc.close();XCTAssertNil(s.backgroundLayerDraft)
    let menus=PhotoshopMenuTests();try menus.withMenus{_,menu in XCTAssertNotNil(menus.allItems(menu).first{$0.action == #selector(AppDelegate.backgroundLayerConversion)})}
  }
  @MainActor func testHTTPConversionsClearHistoryAndNative83AtEveryDepth()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let s=doc.store;service.setDocumentTransfersEnabled(true)
      for depth in PixelDepth.allCases {let original=try self.fixture(depth),id=original.layers[0].id;s.session=EditorSession(document:original);s.backgroundColor=Pixel(0.25,0.5,0.75);try service.share(doc)
        let clear=try await h.edit(service,doc,"pixels.clear",["layerID":id.uuidString]);XCTAssertEqual(clear,200);var expected=original;try Command.backgroundLayer(.clear(id,s.backgroundColor)).apply(to:&expected);XCTAssertEqual(s.document,expected);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)
        let converted=try await h.edit(service,doc,"layer.background",["layerID":id.uuidString,"operation":"toLayer","name":"Editable","opacity":0.625,"mode":"Multiply"]);XCTAssertEqual(converted,200);XCTAssertFalse(s.activeLayer?.isBackground ?? true)
        let restored=try await h.edit(service,doc,"layer.background",["layerID":id.uuidString,"operation":"fromLayer","backgroundColor":[0,0,0,1]]);XCTAssertEqual(restored,200);XCTAssertTrue(s.activeLayer?.isBackground ?? false)
        let state=s.backgroundLayerState;XCTAssertEqual(state["hasBackground"] as? Bool,true);XCTAssertEqual(state["activeIsBackground"] as? Bool,true)
        let shared=try XCTUnwrap(service.shares.first?.id);let rejected=try await h.request(service,path:"/v1/documents/\(shared)/file.photato");XCTAssertEqual(rejected.0.statusCode,422)
        let output=try await h.request(service,path:"/v1/documents/\(shared)/file.photato",headers:["X-Photato-Archive-Version":"83"]);XCTAssertEqual(output.0.statusCode,200);XCTAssertEqual(output.1,try NativeArchive.encodeChunked(s.document,minimumVersion:83));XCTAssertEqual(try NativeArchive.decode(output.1),s.document)
      }
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndRevokedShareAreAtomic()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in let s=doc.store,original=try self.fixture();s.session=EditorSession(document:original);try service.share(doc);let id=original.layers[0].id.uuidString
      for params:[String:Any] in [["layerID":"bad","operation":"toLayer"],["layerID":id,"operation":"wrong"],["layerID":id,"operation":"toLayer","opacity":2],["layerID":id,"operation":"fromLayer","backgroundColor":[0,0,0,0.5]]] {let code=try await h.edit(service,doc,"layer.background",params);XCTAssertEqual(code,400);XCTAssertEqual(s.document,original)}
      let stale=try await h.edit(service,doc,"layer.background",["layerID":id,"operation":"toLayer"],revision:"old");XCTAssertEqual(stale,409);s.beginBackgroundConversion();let busy=try await h.edit(service,doc,"layer.background",["layerID":id,"operation":"toLayer"]);XCTAssertEqual(busy,409);s.backgroundLayerDraft=nil;let shared=try XCTUnwrap(service.shares.first?.id);service.revoke(shared);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  func testPublishedBackgroundAddReplaceConvertOrderedEditDeleteAndManifest()throws {
    let url=URL(string:"https://example.test/image.psd")!,image=try PSDCodec.writeRasterLayers(fixture());var session=EditorSession(document:try CraftDocument(width:9,height:7))
    let add:[String:Any]=["type":"background_layer","operation":["type":"add"],"image":["source":["url":url.absoluteString]]]
    try AdobeCompositeEdit(add,path:"layers[0]").apply(to:&session,resources:[url:image]);XCTAssertTrue(session.document.layers[0].isBackground);XCTAssertEqual(session.document.layers.count,2)
    let replace:[String:Any]=["type":"background_layer","operation":["type":"edit"],"id":0,"isVisible":false,"image":["source":["url":url.absoluteString]]];try AdobeCompositeEdit(replace,path:"layers[1]").apply(to:&session,resources:[url:image]);XCTAssertFalse(session.document.layers[0].visible)
    let convert:[String:Any]=["type":"background_layer","operation":["type":"edit"],"id":0,"convertToLayer":true,"convertedLayerName":"Converted"];try AdobeCompositeEdit(convert,path:"layers[2]").apply(to:&session,resources:[:]);XCTAssertFalse(session.document.layers[0].isBackground)
    try AdobeCompositeEdit(["name":"Converted","operation":["type":"edit"],"protection":["transparency"]],path:"layers[3]").apply(to:&session,resources:[:]);XCTAssertTrue(session.document.layers[0].protection.locksTransparency)
    var single=EditorSession(document:try fixture());let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:AdobeArtboardRequest.manifest(single.document)) as? [String:Any]),layers=try XCTUnwrap(manifest["layers"] as? [[String:Any]]);XCTAssertEqual(layers[0]["id"] as? Int,0);XCTAssertEqual(layers[0]["type"] as? String,"background_layer");XCTAssertEqual((layers[0]["background"] as? [String:Any])?["canConvertToLayer"] as? Bool,true)
    try AdobeCompositeEdit(["type":"background_layer","operation":["type":"delete"],"id":0],path:"layers[0]").apply(to:&single,resources:[:]);XCTAssertTrue(single.document.layers.isEmpty)
    for extra:[String:Any] in [["opacity":0.5],["protection":["all"]],["operation":["type":"move"]],["operation":["type":"add","placement":["type":"bottom"]]]] {XCTAssertThrowsError(try AdobeCompositeEdit(add.merging(extra){_,b in b},path:"layers[0]"))}
  }
  @MainActor func testPublishedHTTPBackgroundConversionUsesSharedEngineAndStrictBytes()async throws {
    let jobs=AutomationActionJobsTests(),transport=AutomationActionJobsTests.Transport(),h=AutomationTests();try await h.withService(pressedMouseButtons:{0},resourceTransport:transport){service,shared in
      let untouched=shared.store.document,input=try PSDCodec.writeRasterLayers(self.fixture());await transport.set(input);service.setResourceJobsEnabled(true)
      let payload:[String:Any]=["image":["source":["url":"https://example.test/input.psd"]],"edits":["layers":[["type":"background_layer","operation":["type":"edit"],"id":0,"convertToLayer":true,"convertedLayerName":"Editable"],["name":"Editable","operation":["type":"edit"],"protection":["transparency"]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
      let result=try await jobs.output(service,submit:"/v2/create-composite",payload:payload);var expected=try PSDCodec.read(input);try Command.backgroundLayer(.toLayer(expected.layers[0].id,.init(name:"Editable"))).apply(to:&expected);expected.layers[0].protection = .transparency;XCTAssertEqual(result.2,try PSDCodec.writeRasterLayers(expected));XCTAssertFalse(try PSDCodec.read(result.2).layers[0].isBackground);XCTAssertEqual(shared.store.document,untouched)
    }
  }
}
