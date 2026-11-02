import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ExposureWorkflowTests:XCTestCase {
  let settings=ExposureAdjustment(exposure:0.5,offset:0.01,gammaCorrection:1.2)
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:8,height:5)
    d.layers[0].content = .raster(try Surface(width:8,height:5,fill:Pixel(0.2,0.4,0.6)))
    return d
  }
  @MainActor func testNativePreviewCancelApplyEditablePropertiesHistoryAndActions23()async throws {
    _ = NSApplication.shared
    var original=try fixture();original.selection = .init(x:2,y:1,width:4,height:3)
    let store=EditorStore(document:original);defer{store.renderTask?.cancel()}
    store.beginClassicAdjustment(.exposure);store.classicAdjustmentDraft?.adjustment = .exposure(settings)
    store.render();await store.renderTask?.value
    XCTAssertEqual(store.document,original);XCTAssertNotEqual(store.surface,try Renderer.composite(original))
    store.cancelClassicAdjustment();await store.renderTask?.value;XCTAssertEqual(store.surface,try Renderer.composite(original))
    store.beginClassicAdjustment(.exposure);store.classicAdjustmentDraft?.adjustment = .exposure(settings)
    store.commitClassicAdjustment();await store.geometryTask?.value;XCTAssertNil(store.error)
    let baked=store.document;await store.undo();XCTAssertEqual(store.document,original);await store.redo();XCTAssertEqual(store.document,baked);await store.undo()
    store.addClassicAdjustment(.exposure);let id=try XCTUnwrap(store.activeLayer?.id)
    store.setClassicAdjustment(id,.exposure(settings));await store.renderTask?.value
    XCTAssertEqual(store.activeLayer?.content,.adjustment(.classic(.exposure(settings))))
    let layer=try ClassicAdjustment.exposure(settings).layer(in:original)
    let operation=ActionOperation(recording:.addLayer(layer),in:original)
    XCTAssertNil(operation.unsupportedReason)
    let action=RecordedAction(name:"Exposure",steps:[.init(name:"Exposure",operation:operation)])
    let library=ActionLibraryFile(actions:[action]);XCTAssertEqual(library.requiredVersion,23)
    let decoded=try ActionLibraryFile.decode(library.encoded());XCTAssertEqual(decoded.version,23)
    var replay=original;try decoded.actions[0].apply(to:&replay)
    XCTAssertEqual(replay.layers.last?.content,layer.content);XCTAssertEqual(replay.layers.last?.mask,layer.mask)
    store.perform(.lock(id,true));let locked=store.document
    store.setClassicAdjustment(id,.exposure());XCTAssertEqual(store.document,locked)
  }
  @MainActor func testPhotatoHTTPAllControlsStateRevisionBusyArchiveAndInvalidNumbers()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,doc in
      let original=try self.fixture();doc.store.session = EditorSession(document:original)
      try service.share(doc);service.setDocumentTransfersEnabled(true)
      let share=try XCTUnwrap(service.shares.first)
      let value=ClassicAdjustment.exposure(self.settings)
      let created=try await helper.edit(service,doc,"adjustment.create",["adjustment":value.apiObject]);XCTAssertEqual(created,200)
      let id=try XCTUnwrap(doc.store.activeLayer?.id)
      let desktop=EditorStore(document:original);defer{desktop.renderTask?.cancel()}
      desktop.addClassicAdjustment(.exposure);desktop.setClassicAdjustment(desktop.document.activeLayerID!,.exposure(self.settings))
      XCTAssertEqual(try Renderer.composite(doc.store.document).rgbaData(depth:.u8),try Renderer.composite(desktop.document).rgbaData(depth:.u8))
      XCTAssertEqual(doc.store.activeLayer?.content,desktop.activeLayer?.content)
      let state=service.state(share,document:doc);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:state))
      for version in ["66","67"] {
        let reply=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":version])
        XCTAssertEqual(reply.0.statusCode,version=="67" ? 200:422)
        if version=="67" {XCTAssertEqual(try NativeArchive.decode(reply.1),doc.store.document)}
      }
      let before=doc.store.document
      for raw:[String:Any] in [["kind":"exposure","offset":true],["kind":"exposure","exposure":21],["kind":"exposure","offset":0.6],["kind":"exposure","gammaCorrection":0],["kind":"exposure","gamma":1]] {
        let invalid=try await helper.edit(service,doc,"adjustment.set",["layerID":id.uuidString,"adjustment":raw]);XCTAssertEqual(invalid,400)
        XCTAssertEqual(doc.store.document,before)
      }
      let stale=try await helper.edit(service,doc,"adjustment.set",["layerID":id.uuidString,"adjustment":value.apiObject],revision:"stale");XCTAssertEqual(stale,409)
      _ = try await helper.edit(service,doc,"history.undo");XCTAssertEqual(doc.store.document,original)
      doc.store.beginClassicAdjustment(.exposure)
      let busy=try await helper.edit(service,doc,"adjustment.apply",["layerID":original.layers[0].id.uuidString,"adjustment":value.apiObject]);XCTAssertEqual(busy,409)
      doc.store.cancelClassicAdjustment()
      let legacy=try AdjustmentBrushAPI.decode(.object(["exposure":.number(0.5)]),kind:.exposure,base:.exposure(1))
      XCTAssertEqual(legacy,.exposure(0.5))
      for complete in [false,true] {
        var controls:[String:Any] = ["exposure":0.5]
        if complete {controls["offset"]=0.01;controls["gammaCorrection"]=1.2}
        let status=try await helper.edit(service,doc,"adjustmentBrush.stroke",["newLayer":true,"kind":"exposure","settings":controls,"points":[["x":3,"y":2]],"brush":["size":3,"hardness":1]])
        XCTAssertEqual(status,200)
        XCTAssertEqual(doc.store.activeLayer?.content,complete ? .adjustment(.classic(.exposure(self.settings))):.adjustment(.exposure(0.5)))
        _ = try await helper.edit(service,doc,"history.undo");XCTAssertEqual(doc.store.document,original)
      }
      let full=try AdjustmentBrushAPI.decode(.object(["offset":.number(0.01),"gammaCorrection":.number(1.2)]),kind:.exposure,base:AdjustmentBrushKind.exposure.initial)
      guard case .classic(let brush)=full else{return XCTFail("Complete Exposure brush")}
      XCTAssertEqual(brush.exposureSettings?.offset,0.01);XCTAssertEqual(brush.exposureSettings?.gammaCorrection,1.2)
    }
  }
  @MainActor func testPublishedAdobeAddEditPlacementsAndStrictContract() throws {
    var d=try fixture();d.layers[0].name="Base"
    let group=Layer(name:"Group",content:.group(.init()));d.layers.append(group)
    for placement in ["top","bottom","above","below","into"] {
      var position:[String:Any]=["type":placement]
      if ["above","below","into"].contains(placement){position["referenceLayer"]=["name":placement=="into" ? "Group":"Base"]}
      let fields:[String:Any]=["type":"adjustment_layer","name":"Added","operation":["type":"add","placement":position],"adjustments":["type":"exposure","exposure":["exposureValue":0.5,"offset":0.01,"gammaCorrection":1.2]]]
      var session=EditorSession(document:d)
      try AdobeExposureEdit(fields,path:"test").apply(to:&session)
      let added=try XCTUnwrap(session.document.layers.first{$0.name=="Added"})
      XCTAssertEqual(added.content,.adjustment(.classic(.exposure(settings))))
      XCTAssertEqual(added.parentID,placement=="into" ? group.id:nil)
      if placement=="bottom" {XCTAssertEqual(session.document.children(of:nil).first?.id,added.id)}
      let patch:[String:Any]=["name":"Added","operation":["type":"edit"],"adjustments":["type":"exposure","exposure":["offset":0.02]]]
      try AdobeExposureEdit(patch,path:"test").apply(to:&session)
      guard case .adjustment(.classic(let edited))=session.document.layers.first(where:{$0.id==added.id})?.content else{return XCTFail()}
      XCTAssertEqual(edited.exposureSettings,.init(exposure:0.5,offset:0.02,gammaCorrection:1.2))
      for raw:[String:Any] in [["exposure":1],["exposureValue":true],["gammaCorrection":0],["offset":0.6]] {
        var bad=fields;bad["adjustments"]=["type":"exposure","exposure":raw]
        XCTAssertThrowsError(try AdobeExposureEdit(bad,path:"test").apply(to:&session))
      }
    }
  }
  private actor Transport:AdobeResourceTransport {
    let bytes:Data
    init(_ bytes:Data){self.bytes=bytes}
    func fetch(_ url:URL)async throws->Data{bytes}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Fixture hosted output only.")}
  }
  @MainActor func testAdobeCompositeHTTPJobReturnsEditableExposureAndSameNativePixels()async throws {
    let original=try fixture(),source=try DocumentIO.encode(original,format:.psd)
    let add:[String:Any]=["type":"adjustment_layer","name":"Exposure","operation":["type":"add","placement":["type":"top"]],"adjustments":["type":"exposure","exposure":["exposureValue":0.5,"offset":0.01,"gammaCorrection":1.2]]]
    let patch:[String:Any]=["name":"Exposure","operation":["type":"edit"],"adjustments":["type":"exposure","exposure":["offset":0.02]]]
    let payload:[String:Any]=["image":["source":["url":"https://example.test/owned.psd"]],"edits":["layers":[add,patch]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:Transport(source)){service,doc in
      service.setResourceJobsEnabled(true);let before=doc.store.document
      let result=try await AutomationActionJobsTests().output(service,submit:"/v2/create-composite",payload:payload,expectedMediaType:"image/vnd.adobe.photoshop")
      let reopened=try PSDCodec.read(result.2)
      let final=ClassicAdjustment.exposure(.init(exposure:0.5,offset:0.02,gammaCorrection:1.2))
      XCTAssertEqual(reopened.layers.last?.content,.adjustment(.classic(final)))
      var expected=try PSDCodec.read(source);expected.layers.append(try final.layer(in:expected))
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:.u8),try Renderer.composite(expected).rgbaData(depth:.u8))
      XCTAssertEqual(doc.store.document,before)
    }
  }
}
