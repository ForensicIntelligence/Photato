import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PhotoDetailWorkflowTests:XCTestCase {
  let kinds:[RasterFilter.Kind]=[.smartSharpen,.reduceNoise]
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument { try BlurGalleryWorkflowTests().fixture(depth,smart:smart) }
  func filter(_ kind:RasterFilter.Kind)->RasterFilter { var f=RasterFilter(kind);if kind == .smartSharpen { f.sharpen?.remove = .motion;f.sharpen?.radius=2;f.sharpen?.angle=30;f.sharpen?.shadows.fadeAmount=25 } else { f.denoise?.perChannel=["blue":.init(strength:4,preserveDetails:30)];f.denoise?.removeJpegArtifact=true };return f }
  func testSelectionHistoryDepthSmartFiltersNative37AndActions9()throws {
    for kind in kinds {
      let f=filter(kind)
      for depth in PixelDepth.allCases {
        let d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
        try session.execute(.applyFilter(id,f));let edited=session.document;XCTAssertNotEqual(edited,d);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edited)
        var selected=d;selected.selection = .init(x:10,y:8,width:10,height:8);try Command.applyFilter(id,f).apply(to:&selected)
        guard case .raster(let a)=d.layers[0].content,case .raster(let b)=selected.layers[0].content else { return XCTFail() };XCTAssertEqual(a.pixel(x:0,y:0),b.pixel(x:0,y:0));XCTAssertNotEqual(a.pixel(x:14,y:12),b.pixel(x:14,y:12))
        var locked=d;locked.layers[0].locked=true;XCTAssertThrowsError(try Command.applyFilter(id,f).apply(to:&locked))
      }
      var smart=try fixture(smart:true);let original=smart,id=smart.layers[0].id;try Command.applyFilter(id,f).apply(to:&smart)
      XCTAssertEqual(smart.minimumArchiveVersion,37);XCTAssertEqual(smart.layers[0].content,original.layers[0].content);XCTAssertEqual(smart.layers[0].smartObject,original.layers[0].smartObject)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(smart)),smart);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(smart)),smart)
      var raw=try PropertyListSerialization.propertyList(from:NativeArchive.encode(smart),format:nil) as! [String:Any];raw["version"]=36;XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:raw,format:.binary,options:0)))
      XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(kind.rawValue)\"}]"))
      var stack=smart.layers[0].smartFilters!;stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&smart);XCTAssertEqual(try Renderer.composite(smart),try Renderer.composite(original))
      for operation in [ActionOperation.filter(.active,f),.filters(.active,stack)] {
        let action=RecordedAction(name:kind.title,steps:[.init(name:kind.title,operation:operation)]),bytes=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,9)
        var json=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];json["version"]=8;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:json)))
      }
      var channel=try fixture();try Command.channel(.quickMask(true,.init())).apply(to:&channel);let before=channel;XCTAssertThrowsError(try Command.channel(.filter(.quickMask,f)).apply(to:&channel));XCTAssertEqual(channel,before)
    }
  }
  @MainActor func testNativeWorkspacePreviewUndoCancelCommitReeditAndOffscreen()async throws {
    for kind in kinds {
      let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer { store.renderTask?.cancel();store.cancelFilter() }
      store.beginFilter(kind);let model=PhotoDetailWorkspace();store.photoDetailWorkspace=model;await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d)
      model.change(filter(kind));let changed=model.filter;XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:try XCTUnwrap(model.apiState["filter"]))),changed);model.undo();XCTAssertEqual(model.filter,RasterFilter(kind));model.redo();XCTAssertEqual(model.filter,changed);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view=NSHostingView(rootView:PhotoDetailSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)));view.appearance=NSAppearance(named:.aqua)
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=view;window.appearance=view.appearance;view.frame=NSRect(x:0,y:0,width:840,height:620);view.layoutSubtreeIfNeeded();view.displayIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/photo-detail-offscreen");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try png.write(to:root.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png")) } };window.contentView=nil
      store.filterDraft?.filter=model.filter;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
      var expected=d;try Command.applyFilter(d.layers[0].id,changed).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters?.filters[0].id ?? UUID();XCTAssertEqual(store.document,expected)
      let reedit=PhotoDetailWorkspace(),draft=FilterDraft(id:d.layers[0].id,filter:changed,filterID:try XCTUnwrap(store.document.layers[0].smartFilters?.filters[0].id));await reedit.prepare(document:store.document,draft:draft);XCTAssertEqual(reedit.filter,changed);reedit.close()
      let undone=await store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(store.document,d)
      store.beginFilter(kind);let cancel=PhotoDetailWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.change(changed);let task=cancel.task;cancel.close();store.cancelFilter();await task?.value;XCTAssertEqual(store.document,d)
    }
    XCTAssertEqual(AppDelegate.filterMenus["Filter > Sharpen > Smart Sharpen…"],.smartSharpen);XCTAssertEqual(AppDelegate.filterMenus["Filter > Noise > Reduce Noise…"],.reduceNoise)
  }
  @MainActor func testHTTPDesktopEquivalenceSmartReeditNative37AndGuards()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let variants:[[String:Any]]=[
        ["kind":"smartSharpen","sharpen":["remove":"gaussian","amount":150,"shadows":["fadeAmount":40]]],
        ["kind":"smartSharpen","sharpen":["remove":"lens","radius":3]],
        ["kind":"smartSharpen","sharpen":["remove":"motion","angle":60,"radius":2]],
        ["kind":"reduceNoise","denoise":["strength":8,"removeJpegArtifact":true,"perChannel":["blue":["strength":5]]]]]
      for payload in variants {
        let d=try self.fixture(),f=try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:payload));document.store.session=EditorSession(document:d);var expected=d;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected)
        let code=try await h.edit(service,document,"filter.apply",["layerID":d.layers[0].id.uuidString,"filter":payload]);XCTAssertEqual(code,200);XCTAssertEqual(document.store.document,expected)
      }
      for payload in [variants[2],variants[3]] {
        let d=try self.fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d);let params:[String:Any]=["layerID":id.uuidString,"filter":payload]
        let status=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200);let changed=document.store.document,share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
        let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"36"]);XCTAssertEqual(old.0.statusCode,422)
        let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"37"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
        var stack=changed.layers[0].smartFilters!;stack.filters[0].opacity=0.5;var stackPayload=stack.apiState;stackPayload.removeValue(forKey:"hasMask");stackPayload.removeValue(forKey:"maskTransform")
        let edited=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":stackPayload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,changed)
        let stale=try await h.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
        document.store.beginFilter(.smartSharpen);let busy=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
        let bad=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"reduceNoise","denoise":["strength":99]]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,changed)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      }
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema))
    }
  }
}
