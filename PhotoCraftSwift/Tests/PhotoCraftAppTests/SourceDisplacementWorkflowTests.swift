import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SourceDisplacementWorkflowTests:XCTestCase {
  func assertStatus(_ actual:Int,_ expected:Int,file:StaticString=#filePath,line:UInt=#line){XCTAssertEqual(actual,expected,file:file,line:line)}
  func data(_ name:String)throws->Data {let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/SourceDisplacement");return try Data(contentsOf:folder.appendingPathComponent(name))}
  func map()throws->FloatDisplacementMap {let m=try FloatDisplacementMap(width:7,height:5,channels:2,samples:data("stretch-u8-map.float32"),name:"Owned Float map");try m.validate();return m}
  func filter()throws->RasterFilter {var f=RasterFilter(.displace),source=SourceDisplacement();source.reference.path="Owned missing map.psd";source.map=try map();f.distortion?.source=source;f.distortion?.horizontalScale=12.75;f.distortion?.verticalScale = -8.125;f.distortion?.edge = .wrapAround;return f}
  @MainActor func testNativeMissingMapExplicitFileLoadLocalHistoryCancelCommitAndReedit()async throws {
    _ = NSApplication.shared
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("Photato-owned-displace-"+UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
    let url=root.appendingPathComponent("Owned Map.pcraft");try data("path-f32-map.pcraft").write(to:url)
    for depth in ["u8","u16","f32"] {
      let original=try PcraftImport.read(data("path-\(depth)-cached.pcraft")),id=original.layers[0].id,item=try XCTUnwrap(original.layers[0].smartFilters?.filters.first),store=EditorStore(document:original,actions:ActionLibrary());defer{store.cancelFilter();store.renderTask?.cancel()}
      store.beginSmartFilter(id,filterID:item.id);let model=DistortionWorkspace();store.distortionWorkspace=model;await model.prepare(document:original,draft:try XCTUnwrap(store.filterDraft));XCTAssertFalse(model.ready);XCTAssertNotNil(model.error);XCTAssertNil(model.filter.distortion?.source?.map);XCTAssertTrue(store.document==original)
      await model.loadMap(url);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Map preview not ready");XCTAssertEqual(model.filter.distortion?.source?.map?.samples,try data("path-f32-map.float32"));XCTAssertEqual(model.filter.distortion?.source?.reference.path,"Owned missing map.psd");XCTAssertEqual(model.undoStates.count,1)
      model.undo();await model.task?.value;XCTAssertFalse(model.ready);XCTAssertNil(model.filter.distortion?.source?.map);model.redo();await model.task?.value;XCTAssertTrue(model.ready);XCTAssertTrue(store.session.undoStack.isEmpty)
      store.cancelFilter();XCTAssertTrue(store.document==original)
      store.beginSmartFilter(id,filterID:item.id);let commit=DistortionWorkspace();store.distortionWorkspace=commit;await commit.prepare(document:original,draft:try XCTUnwrap(store.filterDraft));await commit.loadMap(url);await commit.task?.value;store.filterDraft?.filter=commit.filter;store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);let bound=store.document;XCTAssertEqual(store.session.undoStack.count,1);XCTAssertNotNil(bound.layers[0].smartFilters?.filters[0].filter.distortion?.source?.map);XCTAssertEqual(bound.minimumArchiveVersion,73)
      store.beginSmartFilter(id,filterID:item.id);let reedit=DistortionWorkspace();store.distortionWorkspace=reedit;await reedit.prepare(document:bound,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(reedit.ready);XCTAssertEqual(reedit.filter.distortion?.source?.map?.samples,try data("path-f32-map.float32"));store.cancelFilter();await store.undo();XCTAssertTrue(store.document==original);await store.redo();XCTAssertTrue(store.document==bound)
    }
  }
  @MainActor func testNativeAndHTTPBoundFloatFiltersAllDepthsHistoryAndAtomicGuards()async throws {
    let helper=AutomationTests()
    for depth in PixelDepth.allCases {for smart in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}){service,document in
        service.setDocumentTransfersEnabled(true)
        try service.share(document)
        let d=try LightingWorkflowTests().fixture(depth,smart:smart),id=d.layers[0].id,f=try self.filter();document.store.session=EditorSession(document:d);document.store.selectedLayerIDs=[id]
        let desktop=EditorStore(document:d,actions:ActionLibrary());defer{desktop.cancelFilter();desktop.renderTask?.cancel()};desktop.beginFilter(.displace);desktop.filterDraft?.filter=f;desktop.commitFilter();await desktop.geometryTask?.value;XCTAssertNil(desktop.error)
        let payload:[String:Any]=["kind":"displace","distortion":try XCTUnwrap(f.distortion).apiParameters(kind:.displace)],params:[String:Any]=["layerID":id.uuidString,"filter":payload]
        assertStatus(try await helper.edit(service,document,"filter.apply",params),200)
        var expected=desktop.document;if smart{expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(document.store.document.layers[0].smartFilters?.filters[0].id)};XCTAssertTrue(document.store.document==expected);XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(desktop.document));let changed=document.store.document
        if smart {let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato";let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"72"]);XCTAssertEqual(old.0.statusCode,422);let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"73"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1)==changed)}
        assertStatus(try await helper.edit(service,document,"filter.apply",params,revision:"stale"),409);document.store.beginFilter(.displace);let busy=try await helper.edit(service,document,"filter.apply",params);document.store.cancelFilter();XCTAssertEqual(busy,409)
        let invalid:[String:Any]=["layerID":id.uuidString,"filter":["kind":"displace","distortion":["source":["reference":["path":"never-open-this-file"],"map":["width":1,"height":1,"channels":2,"samples":"AAAA"]]]]];assertStatus(try await helper.edit(service,document,"filter.apply",invalid),400);XCTAssertTrue(document.store.document==changed)
        await document.store.undo();XCTAssertTrue(document.store.document==d)
      }
    }}
  }
  @MainActor func testImportedHTTPNoOpExplicitRebindingPersistenceAndOriginalDownload()async throws {
    let helper=AutomationTests()
    for depth in ["u8","u16","f32"] {
      let input=try data("path-\(depth)-cached.pcraft")
      try await helper.withService(pressedMouseButtons:{0}){service,parent in
        defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
        service.setDocumentTransfersEnabled(true);let upload=try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(upload.0.statusCode,201);let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),original=document.store.document,id=original.layers[0].id;var stack=try XCTUnwrap(original.layers[0].smartFilters)
        let same:[String:Any]=["layerID":id.uuidString,"stack":["enabled":stack.enabled,"filters":stack.apiState["filters"]!]];assertStatus(try await helper.edit(service,document,"smartFilter.set",same),200);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertTrue(document.store.document==original)
        stack.filters[0].filter.distortion?.source?.map=try self.map();let bind:[String:Any]=["layerID":id.uuidString,"stack":["enabled":stack.enabled,"filters":stack.apiState["filters"]!]];assertStatus(try await helper.edit(service,document,"smartFilter.set",bind),200);XCTAssertEqual(document.store.session.undoStack.count,1);let bound=document.store.document;XCTAssertEqual(bound.minimumArchiveVersion,73);XCTAssertEqual(bound.layers[0].smartObject,original.layers[0].smartObject)
        let saved=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"73"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1)==bound)
        let source=try await helper.request(service,path:"/v1/documents/\(share.id)/smart-objects/\(id)/source");XCTAssertEqual(source.0.statusCode,200);XCTAssertEqual(source.1,original.layers[0].smartObject?.data);await document.store.undo();XCTAssertTrue(document.store.document==original);XCTAssertEqual(try self.data("path-\(depth)-cached.pcraft"),input)
      }
    }
  }
  @MainActor func testActions28SchemasLegacyVersionAndExplicitAdobeBoundary()throws {
    XCTAssertEqual(PcraftImport.sourceSmartFilterCommands.count,110);XCTAssertTrue(PcraftImport.unsupportedSourceSmartFilterCommands.isEmpty);XCTAssertEqual(DistortionSettings.apiCapabilities["sourceMapVersion"] as? Int,73);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationService.documentTransferCapabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema))
    for depth in PixelDepth.allCases {let d=try LightingWorkflowTests().fixture(depth),id=d.layers[0].id,f=try filter(),operation=ActionOperation(recording:.applyFilter(id,f),in:d),action=RecordedAction(name:"Owned source Displace",steps:[.init(name:"Displace",operation:operation)]),bytes=try ActionLibraryFile(actions:[action]).encoded(),decoded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(decoded.version,28);var old=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);old["version"]=27;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)));var replayed=d,expected=d;try decoded.actions[0].apply(to:&replayed);try Command.applyFilter(id,f).apply(to:&expected);XCTAssertTrue(replayed==expected)
      var legacy=RasterFilter(.displace);legacy.distortion?.map = .init(width:1,height:1,channels:1,samples:Data([128]));let oldAction=RecordedAction(name:"Legacy8bit",steps:[.init(name:"Displace",operation:ActionOperation(recording:.applyFilter(id,legacy),in:d))]);XCTAssertEqual(try ActionLibraryFile.decode(ActionLibraryFile(actions:[oldAction]).encoded()).version,11)
      var smart=try LightingWorkflowTests().fixture(depth,smart:true);try Command.applyFilter(smart.layers[0].id,f).apply(to:&smart);XCTAssertEqual(smart.minimumArchiveVersion,73);XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psb));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"displace\"}]"))
    }
  }
  @MainActor func testBoundNativeResourceJobsAndAdobeInputFormatBoundary()async throws {
    let helper=AutomationTests()
    for (depth,media,format) in [(PixelDepth.u8,"image/png",DocumentIO.Format.png),(.f32,"image/tiff",.tiff)] {
      var input=try LightingWorkflowTests().fixture(depth,smart:true);try Command.applyFilter(input.layers[0].id,filter()).apply(to:&input);let bytes=try NativeArchive.encodeChunked(input),expectedBytes=try DocumentIO.encode(input,format:format),payload:[String:Any]=["image":["source":["url":"https://example.test/owned-displace.photato"]],"options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],"outputs":[["mediaType":media,"destination":["validityPeriod":60]]]]
      try await helper.withService(pressedMouseButtons:{0},resourceTransport:LightingWorkflowTests.Transport(bytes)){service,parent in
        service.setResourceJobsEnabled(true);let original=parent.store.document
        for route in ["/v1/action-jobs","/v2/execute-actions"] {let reply=try await helper.request(service,path:route,body:payload);XCTAssertEqual(reply.0.statusCode,202);let state=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(state["statusUrl"] as? String)));var terminal:[String:Any]?
          for _ in 0..<1000{let reply=try await helper.request(service,path:url.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any]);if ["succeeded","failed"].contains(value["status"] as? String ?? ""){terminal=value;break};try await Task.sleep(for:.milliseconds(10))}
          let done=try XCTUnwrap(terminal);if route=="/v2/execute-actions"{XCTAssertEqual(done["status"] as? String,"failed");continue};XCTAssertEqual(done["status"] as? String,"succeeded",String(describing:done));let outputs=try XCTUnwrap((done["result"] as? [String:Any])?["outputs"] as? [[String:Any]]),destination=try XCTUnwrap(outputs.first?["destination"] as? [String:Any]),outputURL=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"] as? String))),download=try await helper.request(service,path:outputURL.path);XCTAssertEqual(download.0.statusCode,200);XCTAssertEqual(download.1,expectedBytes)
        };XCTAssertTrue(parent.store.document==original)
      }
    }
  }
}
