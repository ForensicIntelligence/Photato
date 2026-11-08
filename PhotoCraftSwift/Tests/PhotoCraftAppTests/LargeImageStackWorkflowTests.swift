import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeImageStackWorkflowTests:XCTestCase {
  func source(_ value:Float,width:Int=300000,height:Int=300000)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:.f32)
    d.layers[0].content = .raster(try Surface(width:width,height:height,depth:.f32,fill:Pixel(value,value,value)).interpretingSamples(as:.linearRGB));return d
  }
  @MainActor func testNativeAcceptsSeventeenOpenSourcesWithPreviewCancelAndCommit()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,original in
      defer{ImageStackWorkflowTests().cleanup(service,original)}
      for i in 0..<17{
        let model=try source(Float(i)/16,width:1,height:1)
        if i==0{original.store.session=EditorSession(document:model)}else{service.controller.addDocument(CraftNSDocument(model:model))}
      }
      let documents=service.controller.documents.compactMap{$0 as? CraftNSDocument},before=documents.map{$0.store.document}
      service.controller.beginImageStack(statistics:true,display:false)
      let workspace=try XCTUnwrap(service.controller.imageStackWorkspace);workspace.addOpenDocuments();XCTAssertEqual(workspace.sources.count,17)
      workspace.refresh();await workspace.task?.value;XCTAssertTrue(workspace.ready,workspace.error ?? "Not ready")
      XCTAssertEqual(workspace.result?.sourceCount,17);XCTAssertEqual(workspace.image?.width,1)
      service.controller.cancelImageStack();XCTAssertEqual(documents.map{$0.store.document},before);XCTAssertEqual(service.controller.documents.count,17)
      service.controller.beginImageStack(statistics:true,display:false);let second=try XCTUnwrap(service.controller.imageStackWorkspace)
      second.addOpenDocuments();second.refresh();await second.task?.value
      let created=try second.commit(display:false);XCTAssertTrue(created.isDocumentEdited);XCTAssertNil(created.fileURL)
      XCTAssertEqual(try SmartObjectIO.sourceDocument(XCTUnwrap(created.store.activeLayer?.smartObject)).layers.count,17)
      XCTAssertEqual(documents.map{$0.store.document},before);XCTAssertTrue(documents.allSatisfy{$0.store.session.undoStack.isEmpty})
    }
  }
  @MainActor func testMaximumNativePreviewIsBoundedAndStaleSourceRequiresRefresh()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,original in
      defer{ImageStackWorkflowTests().cleanup(service,original)}
      original.store.session=EditorSession(document:try source(0))
      let other=CraftNSDocument(model:try source(1));service.controller.addDocument(other)
      service.controller.beginImageStack(statistics:true,display:false);let workspace=try XCTUnwrap(service.controller.imageStackWorkspace)
      workspace.settings.mode = .mean;workspace.addOpenDocuments();workspace.refresh();await workspace.task?.value
      XCTAssertTrue(workspace.ready,workspace.error ?? "Not ready");XCTAssertEqual(workspace.image?.width,2048);XCTAssertEqual(workspace.image?.height,2048)
      XCTAssertEqual(workspace.result?.document.width,300000);XCTAssertTrue(original.store.session.undoStack.isEmpty)
      try original.store.session.execute(.renameLayer(original.store.document.layers[0].id,"Renamed source"));original.store.revision+=1
      XCTAssertThrowsError(try workspace.commit(display:false));XCTAssertEqual(service.controller.documents.count,2)
      workspace.refresh();await workspace.task?.value;XCTAssertTrue(workspace.ready,workspace.error ?? "Not ready")
      let created=try workspace.commit(display:false);XCTAssertEqual(created.store.document.width,300000)
      XCTAssertEqual(try SmartObjectIO.sourceDocument(XCTUnwrap(created.store.activeLayer?.smartObject)).layers.count,2)
    }
  }
  @MainActor func testSevenMaximumSharedSourcesModesNoneUndoAndNativeDownload()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,original in
      defer{ImageStackWorkflowTests().cleanup(service,original)}
      for i in 0..<7{
        let model=try source(Float(i)/8),document:CraftNSDocument
        if i==0{original.store.session=EditorSession(document:model);document=original}else{document=CraftNSDocument(model:model);service.controller.addDocument(document)}
        try service.share(document)
      }
      let before=service.shares.map{$0.document!.store.document},sources=service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]}
      let parameters:[String:Any]=["sources":sources,"settings":["createSmartObject":true,"mode":"mean"],"name":"Large API Stack"]
      let disabled=try await helper.edit(service,original,"document.imageStack",parameters);XCTAssertEqual(disabled,403)
      service.setDocumentTransfersEnabled(true)
      let response=try await helper.request(service,path:"/v1/documents/\(service.shares[0].id)/commands",body:["command":"document.imageStack","revision":service.revision(original.store),"parameters":parameters])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.last),created=try XCTUnwrap(share.document),layer=try XCTUnwrap(created.store.activeLayer),data=try XCTUnwrap(layer.smartObject?.data)
      XCTAssertEqual(service.shares.count,8);XCTAssertEqual(created.store.document.width,300000)
      XCTAssertEqual(try SmartObjectIO.sourceDocument(XCTUnwrap(layer.smartObject)).layers.count,7)
      @MainActor func editCreated(_ name:String,_ parameters:[String:Any]=[:])async throws->Int {
        // The API creates and shows a real window. Wait for its initial viewport
        // render, then use the public state revision just as an HTTP client does.
        await created.store.renderTask?.value
        _ = await created.store.layerContentFilter.waitForCurrent()
        let state=try await helper.request(service,path:"/v1/documents/\(share.id)")
        XCTAssertEqual(state.0.statusCode,200)
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:state.1)as?[String:Any]),revision=try XCTUnwrap(object["revision"]as?String)
        let response=try await helper.request(service,path:"/v1/documents/\(share.id)/commands",body:["command":name,"revision":revision,"parameters":parameters])
        XCTAssertLessThan(response.0.statusCode,400,String(decoding:response.1,as:UTF8.self));return response.0.statusCode
      }
      for mode in ImageStackMode.allCases{
        let status=try await editCreated("smartObject.stackMode",["layerID":layer.id.uuidString,"mode":mode.rawValue]);XCTAssertEqual(status,200)
        XCTAssertEqual(created.store.activeLayer?.smartObject?.data,data)
      }
      let prior=created.store.document
      let none=try await editCreated("smartObject.stackMode",["layerID":layer.id.uuidString,"mode":"none"]);XCTAssertEqual(none,200);XCTAssertNil(created.store.activeLayer?.smartObject?.stackMode)
      let undo=try await editCreated("history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(created.store.document,prior)
      let file=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"89"])
      XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decodePaged(file.1),created.store.document)
      XCTAssertEqual(service.shares.prefix(7).map{$0.document!.store.document},before)
      XCTAssertTrue(service.shares.prefix(7).allSatisfy{$0.document!.store.session.undoStack.isEmpty})
    }
  }
  @MainActor func testLargeAPIGuardsCapabilityAndPublishedDescriptorShareSameEngine()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,original in
      defer{ImageStackWorkflowTests().cleanup(service,original)}
      original.store.session=EditorSession(document:try source(0));try service.share(original)
      let other=CraftNSDocument(model:try source(1));service.controller.addDocument(other);try service.share(other);service.setDocumentTransfersEnabled(true)
      let sources=service.shares.map{["id":$0.id.uuidString,"revision":service.revision($0.document!.store)]},before=original.store.document
      var parameters:[String:Any]=["sources":sources,"settings":["createSmartObject":true,"mode":"mean","align":true]]
      let oversized=try await helper.edit(service,original,"document.imageStack",parameters);XCTAssertGreaterThanOrEqual(oversized,400)
      var stale=sources;stale[1]["revision"]="stale";parameters["sources"]=stale;parameters["settings"]=["createSmartObject":true,"mode":"mean"]
      let invalid=try await helper.edit(service,original,"document.imageStack",parameters);XCTAssertEqual(invalid,409);XCTAssertEqual(original.store.document,before)
      let capabilities=ImageStackSettings.apiCapabilities,capacity=try XCTUnwrap(capabilities["capacity"]as?[String:Any])
      XCTAssertEqual(capacity["maximumNativeSources"]as?Int,LayerLimits.maximumLayers);XCTAssertEqual(capacity["maximumAPISources"]as?Int,7);XCTAssertEqual(capacity["maximumDocumentPixels"]as?Int,90000000000)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:capabilities));XCTAssertEqual(AutomationCommand.definitions.count,267)
      var settings=ImageStackSettings();settings.createSmartObject=true;settings.mode = .mean
      let d=try ImageStack.prepare([before,other.store.document],settings:settings).document,id=d.layers[0].id
      let program=try PhotoshopActionProgram(actionJSON:#"[{"_obj":"applyImageStackPluginRenderer","imageStackPlugin":{"_class":"$summ"},"name":"Stack"}]"#)
      let result=try program.applying(to:d,stackRenderer:{try ImageStack.command(in:$0,layerID:$1,mode:$2)})
      var expected=EditorSession(document:d);try expected.execute(ImageStack.command(in:d,layerID:id,mode:.summation))
      XCTAssertEqual(result.session.document,expected.document);XCTAssertEqual(result.session.undoStack.count,1)
    }
  }
}
