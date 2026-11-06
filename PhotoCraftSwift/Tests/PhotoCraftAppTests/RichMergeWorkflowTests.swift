import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private final class RichMergeGate:@unchecked Sendable {
  let condition=NSCondition();var released=false
  func wait(){condition.lock();while !released{condition.wait()};condition.unlock()}
  func release(){condition.lock();released=true;condition.broadcast();condition.unlock()}
}
final class RichMergeWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {try RichMergeFixture.make()}
  @MainActor func testNativeMaskedShapeMergeUndoAndSemanticRecording()async throws {
    let source=try fixture(),s=EditorStore(document:source);defer{s.renderTask?.cancel();s.geometryTask?.cancel()}
    XCTAssertTrue(s.canMerge(.down));try s.session.startActionRecording(name:"Merge")
    s.merge(.down);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,1)
    let result=s.document,action=try XCTUnwrap(s.session.actionRecording?.snapshot)
    var replay=source;try RecordedActionRenderer.prepare(action,in:source).command.apply(to:&replay);XCTAssertEqual(replay,result)
    XCTAssertEqual(ActionLibraryFile(actions:[action]).requiredVersion,1)
    _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)
    _=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document,result)
    var grouped=source;try Command.newGroup(.init(name:"Artwork"),children:[source.layers[1].id]).apply(to:&grouped)
    let g=EditorStore(document:grouped);defer{g.renderTask?.cancel()}
    XCTAssertEqual(g.menuMergeOperation,.selected);XCTAssertEqual(g.menuMergeTitle,"Merge Group");XCTAssertEqual(g.layerPanelTitle(.merge),"Merge Group")
    XCTAssertTrue(g.canPerformLayerPanel(.merge));g.performLayerPanel(.merge);await g.geometryTask?.value
    XCTAssertNil(g.error);XCTAssertEqual(g.document.layers.count,2);XCTAssertEqual(g.document.layers[0],source.layers[0]);XCTAssertFalse(g.document.layers[1].isGroup)
    _=await g.requestHistory(redo:false).value;XCTAssertEqual(g.document,grouped)
  }
  @MainActor func testHTTPNativeEquivalentMergeAndNative84Transfer()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
      let source=try self.fixture();doc.store.session=EditorSession(document:source);try service.share(doc)
      let status=try await h.edit(service,doc,"layer.merge",["operation":"down","layerIDs":[source.layers[1].id.uuidString]])
      XCTAssertEqual(status,200);XCTAssertEqual(doc.store.document,try LayerMergePreparation.prepare(source,layerIDs:[source.layers[1].id],operation:.down).result)
      XCTAssertEqual(doc.store.selectedLayerIDs,[source.layers[0].id]);XCTAssertEqual(doc.store.session.undoStack.count,1)
      service.setDocumentTransfersEnabled(true);let id=try XCTUnwrap(service.shares.first?.id)
      let file=try await h.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"84"])
      XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),doc.store.document)
    }
  }
  @MainActor func testInFlightNativeStaleAndCancelCannotPublishMerge()async throws {
    for stale in [false,true] {
      let source=try fixture(),s=EditorStore(document:source),gate=RichMergeGate();defer{gate.release();s.renderTask?.cancel()}
      s.layerMergePreparation={d,ids,op in gate.wait();try Task.checkCancellation();return try LayerMergePreparation.command(d,layerIDs:ids,operation:op)}
      s.merge(.down);let pending=s.geometryTask
      if stale {var changed=source;changed.name="Changed";s.session=EditorSession(document:changed)}else{s.cancelActiveOperation()}
      gate.release();await pending?.value
      XCTAssertEqual(s.document.layers.count,2);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPRevocationAndCancelCannotCommitWorkerResult()async throws {
    for revoke in [false,true] {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
        let source=try self.fixture(),gate=RichMergeGate();defer{gate.release()};doc.store.session=EditorSession(document:source);try service.share(doc)
        doc.store.layerMergePreparation={d,ids,op in gate.wait();try Task.checkCancellation();return try LayerMergePreparation.command(d,layerIDs:ids,operation:op)}
        let pending=Task{try await h.edit(service,doc,"layer.merge",["operation":"down","layerIDs":[source.layers[1].id.uuidString]])}
        let end=Date().addingTimeInterval(10);while !doc.store.geometryBusy && Date()<end{await Task.yield()};XCTAssertTrue(doc.store.geometryBusy)
        if revoke{service.revoke(try XCTUnwrap(service.shares.first?.id))}else{doc.store.cancelActiveOperation()}
        gate.release();let status=try await pending.value;XCTAssertEqual(status,409);XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testSchemaFactoryMenusAndToolModifierPolicyRemainAligned()throws {
    let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()}
    let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.layerMergeState))
    XCTAssertNoThrow(try BrushAPI.merge(value,schema:LayerMergeAPI.stateSchema))
    XCTAssertTrue(s.canPerformLayerPanel(.merge));XCTAssertTrue(s.canPerformLayerPanel(.mergeVisible))
    s.smartFilterMaskEditing=true;XCTAssertFalse(s.canMerge(.down));s.smartFilterMaskEditing=false
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount);XCTAssertEqual(ActionLibraryFile.maximumVersion,50)
  }
  @MainActor func testPublishedMergeEventsUseRichCompositorOnBothJobInterfaces()async throws {
    let transport=AutomationActionJobsTests.Transport(),jobs=AutomationActionJobsTests()
    var source=try fixture();source.layers[1].content = .fill(Pixel(0,0,1))
    let encoded=try PSDCodec.writeRasterLayers(source);await transport.set(encoded)
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) {service,shared in
      service.setResourceJobsEnabled(true);let untouched=shared.store.document
      for event in ["mergeLayersNew","mergeVisible"] {
        let content="[{\"_obj\":\"\(event)\"}]"
        let payload:[String:Any]=["image":["source":["url":"https://example.test/merge.psd"]],"options":["actions":[["source":["content":content,"contentType":"application/json"]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
        var outputs:[Data]=[]
        for route in ["/v1/action-jobs","/v2/execute-actions"] {
          let output=try await jobs.output(service,submit:route,payload:payload);outputs.append(output.2)
          let read=try PSDCodec.read(output.2);XCTAssertEqual(read.layers.count,1)
          XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),Data((0..<3).flatMap{_ in [UInt8(255),0,0,255,255,0,0,255,0,0,255,255,0,0,255,255]}))
        }
        XCTAssertEqual(outputs[0],outputs[1]);XCTAssertEqual(shared.store.document,untouched)
      }
      var groupSource=source
      try Command.newGroup(.init(name:"Artwork"),children:[source.layers[1].id]).apply(to:&groupSource)
      await transport.set(try PSDCodec.writeRasterLayers(groupSource))
      let groupPayload:[String:Any]=["image":["source":["url":"https://example.test/group.psd"]],"options":["actions":[["source":["content":"[{\"_obj\":\"mergeLayersNew\"}]","contentType":"application/json"]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        let output=try await jobs.output(service,submit:route,payload:groupPayload),read=try PSDCodec.read(output.2)
        XCTAssertEqual(read.layers.count,2);XCTAssertEqual(read.layers[1].name,"Artwork");XCTAssertFalse(read.layers[1].isGroup)
      }
    }
  }
}
private enum RichMergeFixture {
  static func make()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    d.layers[0].content = .raster(try Surface(width:4,height:3,fill:Pixel(1,0,0)))
    var top=Layer(name:"Blue",content:.shape(.init(kind:.rectangle,width:2,height:3,color:Pixel(0,0,1))));top.x=2;top.mask=try Surface(width:2,height:3,fill:.white)
    d.layers.append(top);d.activeLayerID=top.id;return d
  }
}
