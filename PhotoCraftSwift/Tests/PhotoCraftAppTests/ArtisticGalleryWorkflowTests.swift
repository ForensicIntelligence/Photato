import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ArtisticGalleryWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument { try BlurGalleryWorkflowTests().fixture(depth,smart:smart) }
  func filter(_ kinds:[GalleryFilter] = [.cutout,.glowingEdges])->RasterFilter { var f=RasterFilter(.filterGallery);f.artistic?.effects=kinds.map{GalleryEffect($0)};return f }
  func testGallerySelectionDepthHistorySmartFilterPersistenceAndActions()throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
      try session.execute(.applyFilter(id,filter()));let changed=session.document;XCTAssertNotEqual(changed,d);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,changed)
      var selected=d;selected.selection = .init(x:10,y:8,width:10,height:8);try Command.applyFilter(id,filter()).apply(to:&selected)
      guard case .raster(let a)=d.layers[0].content,case .raster(let b)=selected.layers[0].content else{return XCTFail()};XCTAssertEqual(a.pixel(x:0,y:0),b.pixel(x:0,y:0));XCTAssertNotEqual(a.pixel(x:14,y:12),b.pixel(x:14,y:12))
    }
    var d=try fixture(smart:true);let original=d,id=d.layers[0].id
    try Command.applyFilter(id,filter()).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,36);XCTAssertEqual(d.layers[0].smartObject,original.layers[0].smartObject);XCTAssertEqual(d.layers[0].content,original.layers[0].content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d);XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
    var stack=d.layers[0].smartFilters!;stack.filters[0].filter.artistic?.effects[0].values["numberOfLevels"]=7;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertNotEqual(try Renderer.composite(d),try Renderer.composite(original))
    let action=RecordedAction(name:"Gallery",steps:[.init(name:"Gallery",operation:.filter(.active,filter()))]);let encoded=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(encoded).version,8)
    var raw=try JSONSerialization.jsonObject(with:encoded) as! [String:Any];raw["version"]=7;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:raw)))
    var plist=try PropertyListSerialization.propertyList(from:NativeArchive.encode(d),format:nil) as! [String:Any];plist["version"]=35;XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:plist,format:.binary,options:0)))
    stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(original))
    var channel=try fixture();try Command.channel(.quickMask(true,.init())).apply(to:&channel);let before=channel;XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter())).apply(to:&channel));XCTAssertEqual(channel,before)
  }
  @MainActor func testWorkspacePreviewStackUndoCancelCommitAndReedit()async throws {
    let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer{store.renderTask?.cancel();store.cancelFilter()}
    store.beginFilter(.filterGallery);let model=ArtisticGalleryWorkspace();store.artisticGalleryWorkspace=model;await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));await model.thumbnailTask?.value
    XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(model.thumbnails.count,47);XCTAssertEqual(store.document,d)
    model.choose(.cutout);model.add();model.choose(.glowingEdges);model.move(-1);let settings=model.settings
    model.undo();XCTAssertEqual(model.settings.effects.last?.filter,.glowingEdges);model.redo();XCTAssertEqual(model.settings,settings)
    model.update{$0.visible=false};model.undo();model.remove();model.undo();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    let view=NSHostingView(rootView:ArtisticGallerySheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)));view.appearance=NSAppearance(named:.aqua);let window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:660),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=view;window.appearance=view.appearance;view.frame=NSRect(x:0,y:0,width:960,height:660);view.layoutSubtreeIfNeeded();view.displayIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,900)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]){let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/gallery-offscreen");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try png.write(to:root.appendingPathComponent(UUID().uuidString+".png"))}}
    window.contentView=nil
    store.filterDraft?.filter.artistic=model.settings;let committed=model.settings;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=d,f=filter();f.artistic=committed;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters?.filters[0].id ?? UUID();XCTAssertEqual(store.document,expected)
    let draft=FilterDraft(id:d.layers[0].id,filter:f,filterID:try XCTUnwrap(store.document.layers[0].smartFilters?.filters[0].id));let reedit=ArtisticGalleryWorkspace();await reedit.prepare(document:store.document,draft:draft);XCTAssertEqual(reedit.settings,committed);reedit.close()
    let undone=await store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(store.document,d)
    store.beginFilter(.filterGallery);let cancel=ArtisticGalleryWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.choose(.watercolor);let task=cancel.task;cancel.close();store.cancelFilter();await task?.value;XCTAssertEqual(store.document,d)
    XCTAssertEqual(AppDelegate.filterMenus["Filter > Filter Gallery…"],.filterGallery)
  }
  @MainActor func testHTTPAllEffectsDesktopEquivalenceSmartReeditNative36AndGuards()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for kind in GalleryFilter.allCases {
        let d=try self.fixture();document.store.session=EditorSession(document:d);var expected=d;try Command.applyFilter(d.layers[0].id,self.filter([kind])).apply(to:&expected)
        let code=try await h.edit(service,document,"filter.apply",["layerID":d.layers[0].id.uuidString,"filter":["kind":"filterGallery","artistic":["effects":[["filter":kind.rawValue]]]]]);XCTAssertEqual(code,200,kind.rawValue);XCTAssertEqual(document.store.document,expected,kind.rawValue)
      }
      let d=try self.fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d)
      let params:[String:Any]=["layerID":id.uuidString,"filter":["kind":"filterGallery","artistic":["effects":[["filter":"cutout"],["filter":"glowingEdges"]]]]]
      let status=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200);let changed=document.store.document,share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"35"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"36"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.artistic?.effects.reverse();var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,changed)
      let stale=try await h.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.filterGallery);let busy=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let bad=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"filterGallery","artistic":["effects":[["filter":"cutout","values":["numberOfLevels":99]]]]]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,changed)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"filterGallery\"}]"))
    }
  }
}
