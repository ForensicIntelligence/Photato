import Foundation
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore
import PhotoCraftImaging

final class PagedHistogramWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:131,height:67,depth:depth)
    var s=try Surface(width:129,height:66,depth:depth,fill:Pixel(0.3,0.5,0.8,0.4));s.setPixel(x:128,y:65,.white)
    d.layers[0].content = .raster(s);d.layers[0].x=2;d.selection = .init(x:4,y:5,width:110,height:60)
    return d
  }
  @MainActor func testNativeAnalysisMaximumSourceCancellationAndSupersession()async throws {
    var d=try CraftDocument(width:300_000,height:300_000)
    d.layers[0].content = .raster(try Surface(width:d.width,height:d.height,fill:.white))
    let original=d,request=LevelsAnalysisRequest(document:d,layerID:d.layers[0].id,pixelLayer:true),model=LevelsAnalysis()
    model.update(request);let old=model.task;model.cancel();await old?.value
    XCTAssertFalse(model.busy);XCTAssertNil(model.histogram);XCTAssertNil(model.error)
    model.update(request);await model.task?.value
    XCTAssertEqual(model.histogram?.samples,90_000_000_000);XCTAssertFalse(model.busy);XCTAssertNil(model.error)
    let small=try fixture(.f32),next=LevelsAnalysisRequest(document:small,layerID:small.layers[0].id,pixelLayer:true,luminance:true)
    model.update(request);model.update(next);await model.task?.value
    XCTAssertEqual(model.histogram,try next.analyze());XCTAssertEqual(d,original);model.cancel()
  }
  @MainActor func testHTTPAndNativeEveryDepthSelectionAndAdjustmentMatchWithoutHistory()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for depth in PixelDepth.allCases {
        var d=try self.fixture(depth)
        let adjustment=Layer(name:"Curves",content:.adjustment(.curves(.init())))
        d.layers.append(adjustment);document.store.session=EditorSession(document:d)
        let before=d,revision=service.revision(document.store),share=try XCTUnwrap(service.shares.first?.id)
        for pixel in [true,false] {for luminance in [false,true] {
          let id=pixel ? d.layers[0].id:adjustment.id
          let native=try LevelsAnalysisRequest(document:d,layerID:id,pixelLayer:pixel,luminance:luminance).analyze()
          let response=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":HistogramAPI.name,"revision":revision,"parameters":["layerID":id.uuidString,"luminance":luminance]])
          XCTAssertEqual(response.0.statusCode,200,String(data:response.1,encoding:.utf8) ?? "")
          let json=try XCTUnwrap(try JSONSerialization.jsonObject(with:response.1)as?[String:Any]),actual=try XCTUnwrap(json["histogram"]as?[String:Any])
          XCTAssertEqual(try JSONSerialization.data(withJSONObject:actual,options:.sortedKeys),try JSONSerialization.data(withJSONObject:HistogramAPI.json(native),options:.sortedKeys))
          XCTAssertEqual(json["revision"]as?String,revision);XCTAssertEqual(json["sourceDepth"]as?String,depth.rawValue)
        }}
        let response=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":HistogramAPI.name,"revision":revision,"parameters":["layerID":d.layers[0].id.uuidString,"useSelection":false]])
        let object=try XCTUnwrap(try JSONSerialization.jsonObject(with:response.1)as?[String:Any]),hist=try XCTUnwrap(object["histogram"]as?[String:Any])
        XCTAssertEqual(hist["samples"]as?Int,129*66)
        XCTAssertEqual(document.store.document,before);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertEqual(service.revision(document.store),revision)
      }
    }
  }
  @MainActor func testStrictSchemasMissingUnsupportedBusyStaleAndRevokedRequests()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture();document.store.session=EditorSession(document:d);try service.share(document);let id=d.layers[0].id
      for params in [[:],["layerID":"no"],["layerID":id.uuidString,"luminance":1],["layerID":id.uuidString,"extra":true]]as[[String:Any]] {
        let status=try await h.edit(service,document,HistogramAPI.name,params);XCTAssertEqual(status,400)
      }
      let missing=try await h.edit(service,document,HistogramAPI.name,["layerID":UUID().uuidString]);XCTAssertEqual(missing,404)
      let stale=try await h.edit(service,document,HistogramAPI.name,["layerID":id.uuidString],revision:"old");XCTAssertEqual(stale,409)
      service.previewBusy=true;let busy=try await h.edit(service,document,HistogramAPI.name,["layerID":id.uuidString]);XCTAssertEqual(busy,429);service.previewBusy=false
      var group=d;group.layers[0].content = .group(.init());document.store.session=EditorSession(document:group)
      let unsupported=try await h.edit(service,document,HistogramAPI.name,["layerID":id.uuidString]);XCTAssertEqual(unsupported,422)
      document.store.session=EditorSession(document:d)
      document.store.beginCurves()
      XCTAssertNotNil(document.store.curvesDraft)
      let modal=try await h.edit(service,document,HistogramAPI.name,["layerID":id.uuidString]);XCTAssertEqual(modal,409)
      document.store.cancelCurves();document.store.renderTask?.cancel()
      let def=try XCTUnwrap(AutomationCommand.definitions.first{$0.name==HistogramAPI.name}),schema=def.schema
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:schema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:HistogramAPI.capabilities))
      XCTAssertEqual(AutomationCommand.definitions.count,256);XCTAssertEqual(ActionLibraryFile.maximumVersion,51)
      let share=try XCTUnwrap(service.shares.first?.id);service.revoke(share)
      let revoked=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":HistogramAPI.name,"revision":service.revision(document.store),"parameters":["layerID":id.uuidString]])
      XCTAssertEqual(revoked.0.statusCode,404);XCTAssertEqual(document.store.document,d);XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
