import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ChannelSeparationWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth,name:"Owned separation")
    let p=try Surface(width:4,height:3,depth:depth,fill:Pixel(0.25,0.5,0.75),colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    d.layers[0].content = .raster(p);return d
  }
  @MainActor func cleanup(_ controller:CraftDocumentController){for d in controller.documents{d.close()}}
  @MainActor func testNativeCreatesEditableUnsavedGrayDocumentsAndDoesNotWriteTheSource()async throws {
    for depth in PixelDepth.allCases {
      let controller=CraftDocumentController(),source=CraftNSDocument(model:try fixture(depth));controller.addDocument(source);defer{cleanup(controller)}
      let file=FileManager.default.temporaryDirectory.appendingPathComponent("photato-owned-split-\(UUID()).photato")
      let bytes=try NativeArchive.encodeChunked(source.store.document);try bytes.write(to:file);defer{try? FileManager.default.removeItem(at:file)}
      source.fileURL=file;source.updateChangeCount(.changeDone)
      let original=source.store.document,expected=try ChannelSeparation.prepare(original)
      XCTAssertTrue(source.store.canSplitChannels)
      source.store.splitChannels();let task=source.store.geometryTask;await task?.value
      XCTAssertNil(source.store.error);XCTAssertNil(source.ownerController);XCTAssertEqual(try Data(contentsOf:file),bytes)
      let results=controller.documents.compactMap{$0 as? CraftNSDocument}
      XCTAssertEqual(results.count,3);XCTAssertEqual(Set(results.map{$0.store.document.name}),Set(expected.outputs.map{$0.document.name}))
      for doc in results {
        let result=doc.store.document,wanted=try XCTUnwrap(expected.outputs.first{$0.document.name==result.name})
        XCTAssertEqual(try result.layers[0].nativeMode?.planes,try wanted.document.layers[0].nativeMode?.planes)
        XCTAssertEqual(result.colorMode,.grayscale);XCTAssertTrue(result.layers[0].isBackground)
        XCTAssertNil(doc.fileURL);XCTAssertNil(doc.importedSourceURL);XCTAssertTrue(doc.isDocumentEdited);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
        doc.store.fill(color:.black);await doc.store.geometryTask?.value;XCTAssertNil(doc.store.error)
        XCTAssertEqual(doc.store.document.layers[0].nativeMode?.value(component:0,index:0),0)
        await doc.store.undo();XCTAssertEqual(doc.store.document,result)
        doc.store.clear();await doc.store.geometryTask?.value;XCTAssertNil(doc.store.error)
        XCTAssertEqual(doc.store.document.layers[0].nativeMode?.value(component:0,index:0),1)
        await doc.store.undo();XCTAssertEqual(doc.store.document,result)
        var brush=Brush();brush.size=3;brush.hardness=1;brush.color = .black
        doc.store.stroke([.init(x:1,y:1)],brush:brush);await doc.store.geometryTask?.value;XCTAssertNil(doc.store.error)
        XCTAssertEqual(doc.store.session.undoStack.count,1);await doc.store.undo();XCTAssertEqual(doc.store.document,result)
        let psd=try PSDCodec.read(PSDCodec.writeRasterLayers(result))
        XCTAssertEqual(psd.colorMode,.grayscale);XCTAssertEqual(try psd.layers[0].nativeMode?.planes,try result.layers[0].nativeMode?.planes)
      }
      XCTAssertEqual(source.store.document,original)
    }
  }
  @MainActor func testSelectedAuxiliaryTargetAndPublicationRollbackKeepTheSource()async throws {
    let controller=CraftDocumentController();var d=try fixture()
    let alpha=AlphaChannel(name:"Saved",pixels:try Surface(width:4,height:3,fill:.white));d.alphaChannels=[alpha]
    let source=CraftNSDocument(model:d);controller.addDocument(source);defer{cleanup(controller)}
    try source.store.selectAlphaChannel(alpha.id);XCTAssertTrue(source.store.canSplitChannels)
    let plan=try ChannelSeparation.prepare(d)
    XCTAssertThrowsError(try controller.publishChannelSeparation(plan,source:source){_ in throw CraftError.invalid("Owned rollback probe")})
    XCTAssertTrue(source.ownerController === controller);XCTAssertEqual(controller.documents.count,1);XCTAssertEqual(source.store.document,d)
    try source.store.selectEditingChannel(.red);XCTAssertTrue(source.store.canSplitChannels)
    source.store.splitChannels();await source.store.geometryTask?.value
    XCTAssertNil(source.store.error);XCTAssertNil(source.ownerController);XCTAssertEqual(controller.documents.count,4)
  }
  @MainActor func testNativeCancelAndChangedSourceCannotPublishOrClose()async throws {
    for cancel in [false,true] {
      let controller=CraftDocumentController(),source=CraftNSDocument(model:try fixture());controller.addDocument(source);defer{cleanup(controller)}
      let gate=ChannelSeparationGate();defer{gate.release()}
      source.store.splitChannelsPreparation={d,p in gate.wait();try Task.checkCancellation();return try ChannelSeparation.prepare(d,grayProfile:p)}
      source.store.splitChannels();let task=source.store.geometryTask
      if cancel{source.store.cancelActiveOperation()}else{var changed=source.store.document;changed.name="Changed";source.store.session=EditorSession(document:changed)}
      gate.release();await task?.value
      XCTAssertTrue(source.ownerController === controller);XCTAssertEqual(controller.documents.count,1);XCTAssertFalse(source.store.geometryBusy)
    }
  }
  @MainActor func testHTTPPermissionsInvalidRevisionBusyAndResultShareReplacement()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
      let controller=try XCTUnwrap(source.ownerController);defer{cleanup(controller)}
      source.store.session=EditorSession(document:try fixture());try service.share(source)
      let original=source.store.document,old=try XCTUnwrap(service.shares.first?.id)
      var status=try await h.edit(service,source,"channel.split");XCTAssertEqual(status,403)
      service.setDocumentTransfersEnabled(true);status=try await h.edit(service,source,"channel.split");XCTAssertEqual(status,403)
      service.setDocumentClosingEnabled(true)
      status=try await h.edit(service,source,"channel.split",["unknown":true]);XCTAssertEqual(status,400)
      status=try await h.edit(service,source,"channel.split",revision:"stale");XCTAssertEqual(status,409)
      source.store.geometryBusy=true;status=try await h.edit(service,source,"channel.split");source.store.geometryBusy=false;XCTAssertEqual(status,409)
      let(response,data)=try await h.request(service,path:"/v1/documents/\(old)/commands",body:["command":"channel.split","revision":service.revision(source.store),"parameters":[:]])
      XCTAssertEqual(response.statusCode,201,String(decoding:data,as:UTF8.self))
      let json=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any])
      XCTAssertEqual(json["sourceClosed"]as?Bool,true);XCTAssertEqual(json["sourceShareID"]as?String,old.uuidString)
      XCTAssertEqual((json["documents"]as?[[String:Any]])?.count,3);XCTAssertEqual(service.shares.count,3)
      XCTAssertFalse(service.shares.contains{$0.id==old});XCTAssertNil(source.ownerController);XCTAssertEqual(source.store.document,original)
      if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try data.write(to:URL(fileURLWithPath:path).appendingPathComponent("split-api-result.json"))
        try JSONSerialization.data(withJSONObject:ChannelSeparationAPI.resultSchema,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).appendingPathComponent("split-api-result-schema.json"))
      }
      for item in try XCTUnwrap(json["documents"]as?[[String:Any]]) {
        let descriptor=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:try XCTUnwrap(item["channel"])))
        XCTAssertNoThrow(try BrushAPI.merge(descriptor,schema:ChannelSeparationAPI.descriptorSchema))
      }
      for share in service.shares {
        let doc=try XCTUnwrap(share.document),state=service.state(share,document:doc)
        XCTAssertEqual(doc.store.document.colorMode,.grayscale);XCTAssertTrue(doc.isDocumentEdited)
        let stateValue=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:try XCTUnwrap(state["channelSeparation"])))
        XCTAssertNoThrow(try BrushAPI.merge(stateValue,schema:ChannelSeparationAPI.stateSchema))
        let clear=try await h.request(service,path:"/v1/documents/\(share.id)/commands",body:["command":"pixels.clear","revision":service.revision(doc.store),"parameters":["layerID":doc.store.document.layers[0].id.uuidString]])
        XCTAssertEqual(clear.0.statusCode,200,String(decoding:clear.1,as:UTF8.self));XCTAssertEqual(doc.store.document.layers[0].nativeMode?.value(component:0,index:0),1)
      }
    }
  }
  @MainActor func testHTTPFinalEightShareCapacityIsAtomicAndPreservesOtherLeases()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
      let controller=try XCTUnwrap(source.ownerController);defer{cleanup(controller)}
      source.store.session=EditorSession(document:try fixture());try service.share(source);service.setDocumentTransfersEnabled(true);service.setDocumentClosingEnabled(true)
      var others=[CraftNSDocument]()
      for _ in 0..<6 {let doc=CraftNSDocument(model:try fixture());controller.addDocument(doc);try service.share(doc);others.append(doc)}
      let before=service.shares.map(\.id),original=source.store.document
      var status=try await h.edit(service,source,"channel.split");XCTAssertEqual(status,429)
      XCTAssertEqual(service.shares.map(\.id),before);XCTAssertEqual(controller.documents.count,7);XCTAssertEqual(source.store.document,original)
      let last=try XCTUnwrap(others.last),removed=try XCTUnwrap(service.shares.first{$0.document === last}?.id);service.revoke(removed)
      let retained=Set(service.shares.dropFirst().map(\.id))
      status=try await h.edit(service,source,"channel.split");XCTAssertEqual(status,201)
      XCTAssertEqual(service.shares.count,8);XCTAssertTrue(retained.isSubset(of:Set(service.shares.map(\.id))))
      XCTAssertNil(source.ownerController)
    }
  }
  @MainActor func testHTTPRevocationCancellationPermissionsAndChangedSessionRejectLatePublication()async throws {
    for change in 0..<6 {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
        let controller=try XCTUnwrap(source.ownerController);defer{cleanup(controller)}
        source.store.session=EditorSession(document:try fixture());try service.share(source);service.setDocumentTransfersEnabled(true);service.setDocumentClosingEnabled(true)
        let original=source.store.document,gate=ChannelSeparationGate();defer{gate.release()}
        source.store.splitChannelsPreparation={d,p in gate.wait();try Task.checkCancellation();return try ChannelSeparation.prepare(d,grayProfile:p)}
        let pending=Task{try await h.edit(service,source,"channel.split")},deadline=Date().addingTimeInterval(5)
        while !source.store.geometryBusy && Date()<deadline {await Task.yield()};XCTAssertTrue(source.store.geometryBusy)
        switch change {
        case 0:service.revoke(try XCTUnwrap(service.shares.first?.id))
        case 1:source.store.cancelActiveOperation()
        case 2:service.setDocumentTransfersEnabled(false)
        case 3:service.setDocumentClosingEnabled(false)
        case 4:source.store.session=EditorSession(document:original)
        default:var changed=original;changed.name="Changed";source.store.session=EditorSession(document:changed)
        }
        gate.release();let status=try await pending.value;XCTAssertEqual(status,409)
        XCTAssertTrue(source.ownerController === controller);XCTAssertEqual(controller.documents.count,1);XCTAssertFalse(source.store.geometryBusy)
        if change != 5{XCTAssertEqual(source.store.document,original)}
      }
    }
  }
  @MainActor func testSchemaCatalogueAndUnflattenedAvailability()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
      try service.share(source);service.setDocumentTransfersEnabled(true);service.setDocumentClosingEnabled(true)
      // The harness source is transparent; do not flatten or close it implicitly.
      XCTAssertFalse(source.store.canSplitChannels)
      let status=try await h.edit(service,source,"channel.split");XCTAssertEqual(status,422)
      XCTAssertEqual(source.ownerController?.documents.count,1)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ChannelSeparationAPI.capabilities))
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:source.store.channelSeparationState))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:ChannelSeparationAPI.stateSchema))
      XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount);XCTAssertEqual(Set(AutomationCommand.definitions.map(\.name)).count,AutomationTests.expectedCommandCount)
    }
  }
}
private final class ChannelSeparationGate:@unchecked Sendable {
  private let condition=NSCondition();private var open=false
  func wait(){condition.lock();while !open{condition.wait()};condition.unlock()}
  func release(){condition.lock();open=true;condition.broadcast();condition.unlock()}
}
