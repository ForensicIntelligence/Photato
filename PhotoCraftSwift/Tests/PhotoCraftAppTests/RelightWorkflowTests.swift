import AppKit
import Foundation
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RelightWorkflowTests:XCTestCase {
  actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data){self.data=data}
    func fetch(_ url:URL)async throws->Data{data}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Owned hosted-output test only.")}
  }
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func filter()->RasterFilter {var f=RasterFilter(.relight);f.relight?.angle = -110;f.relight?.warmth = -35;f.relight?.intensity=70;return f}
  func source(_ name:String)throws->Data {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/Relight")
    return try Data(contentsOf:folder.appendingPathComponent(name))
  }
  @MainActor func testNativePreviewLocalHistoryCancelCommitAndReeditAtAllDepths()async throws {
    _ = NSApplication.shared
    for depth in PixelDepth.allCases {
      let d=try fixture(depth,smart:true),id=d.layers[0].id,store=EditorStore(document:d,actions:ActionLibrary())
      defer{store.cancelFilter();store.renderTask?.cancel()}
      store.beginFilter(.relight);XCTAssertEqual(store.filterDraft?.preview,false)
      let model=RelightWorkspace();store.relightWorkspace=model;await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft))
      XCTAssertTrue(model.ready,model.error ?? "Preview not ready");XCTAssertTrue(store.document==d);XCTAssertTrue(store.session.undoStack.isEmpty)
      let initial=model.state;model.beginGesture();model.change(try XCTUnwrap(filter().relight));var settings=model.settings;settings.warmth=20;model.change(settings);model.endGesture()
      XCTAssertEqual(model.undoStates.count,1);let changed=model.state;model.undo();XCTAssertEqual(model.state,initial);model.redo();XCTAssertEqual(model.state,changed);await model.task?.value;XCTAssertTrue(model.ready)
      var invalid=settings;invalid.intensity=101;model.change(invalid);XCTAssertNotNil(model.error);XCTAssertEqual(model.state,changed);model.change(settings);await model.task?.value;XCTAssertTrue(model.ready)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState))
      store.filterDraft?.filter.relight=model.settings;store.commitFilter();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);let committed=store.document,item=try XCTUnwrap(committed.layers[0].smartFilters?.filters.first)
      var expected=d,f=RasterFilter(.relight);f.relight=settings;try Command.applyFilter(id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=item.id
      XCTAssertTrue(committed==expected);XCTAssertEqual(try Renderer.composite(committed),try Renderer.composite(expected))
      store.beginSmartFilter(id,filterID:item.id);let reedit=RelightWorkspace();store.relightWorkspace=reedit;await reedit.prepare(document:committed,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(reedit.ready);XCTAssertEqual(reedit.settings,settings)
      reedit.beginGesture();reedit.blending(opacity:0.3,mode:.multiply);reedit.blending(opacity:0.4,mode:.screen);reedit.endGesture();let blend=reedit.state;XCTAssertEqual(reedit.undoStates.count,1)
      reedit.undo();XCTAssertEqual(reedit.opacity,1);XCTAssertEqual(reedit.mode,.normal);reedit.redo();XCTAssertEqual(reedit.state,blend)
      reedit.change(.init());XCTAssertEqual(reedit.settings,RelightSettings());reedit.undo();XCTAssertEqual(reedit.state,blend)
      let pending=reedit.task;store.cancelFilter();await pending?.value;XCTAssertTrue(store.document==committed);XCTAssertEqual(store.session.undoStack.count,1)
      await store.undo();XCTAssertTrue(store.document==d);await store.redo();XCTAssertTrue(store.document==committed)
    }
  }
  @MainActor func testScaledPreviewRestartAndCancellationDiscardOldState()async throws {
    var d=try CraftDocument(width:300,height:220);d.layers[0].content = .raster(try Surface(width:300,height:220,fill:Pixel(0.4,0.6,0.2,1)))
    let model=RelightWorkspace(),draft=FilterDraft(id:d.layers[0].id,filter:.init(.relight));await model.prepare(document:d,draft:draft)
    XCTAssertTrue(model.ready,model.error ?? "Scaled preview not ready");XCTAssertEqual(model.image?.width,192);XCTAssertEqual(model.image?.height,140)
    model.change(try XCTUnwrap(filter().relight));let pending=model.task;model.close();await pending?.value;XCTAssertFalse(model.rendering)
    let small=try fixture(.f32);await model.prepare(document:small,draft:.init(id:small.layers[0].id,filter:.init(.relight)))
    XCTAssertTrue(model.ready,model.error ?? "Restart not ready");XCTAssertEqual(model.image?.width,40);XCTAssertEqual(model.image?.height,32);XCTAssertEqual(model.settings,RelightSettings());XCTAssertTrue(model.undoStates.isEmpty);XCTAssertTrue(model.redoStates.isEmpty)
    let oldImage=model.image;for angle in [20.0,40,80]{var s=model.settings;s.angle=angle;model.change(s)};await model.task?.value
    XCTAssertTrue(model.ready);XCTAssertEqual(model.settings.angle,80);XCTAssertNotNil(oldImage)
    let view=NSHostingView(rootView:RelightSheet(store:EditorStore(document:small,actions:ActionLibrary()),model:model));view.frame=NSRect(x:0,y:0,width:720,height:500);view.layoutSubtreeIfNeeded();XCTAssertGreaterThanOrEqual(view.fittingSize.width,700);model.close()
  }
  @MainActor func testNativeAndHTTPFiltersSmartBlendingHistoryAndAtomicGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for depth in PixelDepth.allCases {for smart in [false,true] {
        let d=try self.fixture(depth,smart:smart),id=d.layers[0].id,f=self.filter();document.store.session=EditorSession(document:d);document.store.selectedLayerIDs=[id]
        let desktop=EditorStore(document:d,actions:ActionLibrary());defer{desktop.cancelFilter();desktop.renderTask?.cancel()}
        desktop.beginFilter(.relight);desktop.filterDraft?.filter=f;desktop.commitFilter();await desktop.geometryTask?.value;XCTAssertNil(desktop.error)
        let payload:[String:Any]=["kind":"relight","relight":BrushAPI.json(try XCTUnwrap(f.relight))],params:[String:Any]=["layerID":id.uuidString,"filter":payload]
        let status=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200)
        var expected=desktop.document;if smart{expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(document.store.document.layers[0].smartFilters?.filters.first?.id)}
        XCTAssertTrue(document.store.document==expected);XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(desktop.document));XCTAssertEqual(document.store.session.undoStack.count,1)
        var changed=document.store.document
        if smart {
          let item=try XCTUnwrap(changed.layers[0].smartFilters?.filters.first);desktop.session=EditorSession(document:changed);desktop.beginSmartFilter(id,filterID:item.id);desktop.filterDraft?.opacity=0.4;desktop.filterDraft?.blendMode = .multiply;desktop.commitFilter();await desktop.geometryTask?.value
          var stack=try XCTUnwrap(changed.layers[0].smartFilters);stack.filters[0].opacity=0.4;stack.filters[0].blendMode = .multiply
          let status=try await helper.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":["enabled":stack.enabled,"filters":stack.apiState["filters"]!]])
          XCTAssertEqual(status,200);XCTAssertTrue(document.store.document==desktop.document);changed=document.store.document
          let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
          let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"70"]);XCTAssertEqual(old.0.statusCode,422)
          let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"71"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1)==changed)
        }
        let stale=try await helper.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
        document.store.beginFilter(.relight);let busy=try await helper.edit(service,document,"filter.apply",params);document.store.cancelFilter();XCTAssertEqual(busy,409)
        let bad=try await helper.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"relight","relight":["softness":0]]]);XCTAssertEqual(bad,400);XCTAssertTrue(document.store.document==changed)
        let undoCount=document.store.session.undoStack.count;for _ in 0..<undoCount{await document.store.undo()};XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertTrue(document.store.document==d)
        let share=try XCTUnwrap(service.shares.first);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      }}
    }
  }
  @MainActor func testActions26Native71SchemasAndPublishedDescriptorBoundaries()throws {
    XCTAssertEqual(AppDelegate.filterMenus["Filter > Photato > Relight…"],.relight)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RelightSettings.apiCapabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationService.documentTransferCapabilities))
    XCTAssertTrue((RelightSettings.apiCapabilities["scope"] as? String)?.contains("not Adobe Harmonize") == true)
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id,f=filter(),operation=ActionOperation(recording:.applyFilter(id,f),in:d),action=RecordedAction(name:"Owned Relight",steps:[.init(name:"Relight",operation:operation)])
      let bytes=try ActionLibraryFile(actions:[action]).encoded(),decoded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(decoded.version,26)
      var downgraded=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);downgraded["version"]=25;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
      var replayed=d,expected=d;try decoded.actions[0].apply(to:&replayed);try Command.applyFilter(id,f).apply(to:&expected);XCTAssertTrue(replayed==expected)
      var smart=try fixture(depth,smart:true);try Command.applyFilter(smart.layers[0].id,f).apply(to:&smart);XCTAssertEqual(smart.minimumArchiveVersion,71)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encode(smart))==smart);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(smart))==smart)
      let stack=try XCTUnwrap(smart.layers[0].smartFilters),stackAction=RecordedAction(name:"Relight stack",steps:[.init(name:"Relight stack",operation:.filters(.active,stack))]);XCTAssertEqual(try ActionLibraryFile.decode(ActionLibraryFile(actions:[stackAction]).encoded()).version,26)
      XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psb));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"relight\"}]"))
      let store=EditorStore(document:d,actions:ActionLibrary());defer{store.renderTask?.cancel()};XCTAssertTrue(store.canBeginFilterKind(.relight));XCTAssertEqual(store.actionState["supportedVersions"] as? [Int],Array(1...29))
    }
  }
  @MainActor func testOriginalCachedImportHTTPNoOpReeditAndSourceRetention()async throws {
    let helper=AutomationTests()
    for depth in ["u8","u16","f32"] {
      let input=try source("default-\(depth)-cached.pcraft")
      try await helper.withService(pressedMouseButtons:{0}){service,parent in
        defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
        service.setDocumentTransfersEnabled(true);let upload=try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(upload.0.statusCode,201)
        let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),original=document.store.document,layer=try XCTUnwrap(original.layers.first),stack=try XCTUnwrap(layer.smartFilters),item=try XCTUnwrap(stack.filters.first)
        let payload:[String:Any]=["enabled":stack.enabled,"filters":stack.apiState["filters"]!]
        let status=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload]);XCTAssertEqual(status,200);XCTAssertTrue(document.store.document==original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
        document.store.beginSmartFilter(layer.id,filterID:item.id);let model=RelightWorkspace();document.store.relightWorkspace=model;await model.prepare(document:original,draft:try XCTUnwrap(document.store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Source preview failed");XCTAssertEqual(model.settings,item.filter.relight)
        document.store.cancelFilter();XCTAssertTrue(document.store.document==original)
        let source=try await helper.request(service,path:"/v1/documents/\(share.id)/smart-objects/\(layer.id)/source");XCTAssertEqual(source.0.statusCode,200);XCTAssertEqual(source.1,layer.smartObject?.data);XCTAssertEqual(try self.source("default-\(depth)-cached.pcraft"),input)
      }
    }
  }
  @MainActor func testOriginalRelightResourceOutputsAndAdobeFormatBoundary()async throws {
    let helper=AutomationTests()
    for (depth,media,format) in [("u8","image/png",DocumentIO.Format.png),("f32","image/tiff",DocumentIO.Format.tiff)] {
      let input=try source("default-\(depth)-cached.pcraft"),payload:[String:Any]=["image":["source":["url":"https://example.test/owned-relight.pcraft"]],"options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],"outputs":[["mediaType":media,"destination":["validityPeriod":60]]]]
      try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
        service.setResourceJobsEnabled(true);let original=parent.store.document
        for route in ["/v1/action-jobs","/v2/execute-actions"] {
          let reply=try await helper.request(service,path:route,body:payload);XCTAssertEqual(reply.0.statusCode,202)
          let state=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(state["statusUrl"] as? String)))
          var terminal:[String:Any]?
          for _ in 0..<1000{let reply=try await helper.request(service,path:url.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any]);if ["succeeded","failed"].contains(value["status"] as? String ?? ""){terminal=value;break};try await Task.sleep(for:.milliseconds(10))}
          let result=try XCTUnwrap(terminal);XCTAssertEqual(result["status"] as? String,route.hasPrefix("/v1") ? "succeeded":"failed","\(result)")
          if route.hasPrefix("/v1") {
            let outputs=try XCTUnwrap((result["result"] as? [String:Any])?["outputs"] as? [[String:Any]]),destination=try XCTUnwrap(outputs.first?["destination"] as? [String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"] as? String)))
            let output=try await helper.request(service,path:url.path);XCTAssertEqual(output.0.statusCode,200);XCTAssertEqual(output.1,try DocumentIO.encode(PcraftImport.read(input),format:format))
          }
        };XCTAssertTrue(parent.store.document==original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
      }
    }
  }
}
