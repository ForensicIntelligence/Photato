import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RenderWorkflowTests:XCTestCase {
  let kinds=RasterFilter.Kind.allCases.filter(\.isRender)
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func filter(_ kind:RasterFilter.Kind)->RasterFilter {
    var f=RasterFilter(kind)
    if kind != .lensFlare {f.renderSettings?.seed=42;f.renderSettings?.foreground=Pixel(0.2,0.4,0.7);f.renderSettings?.background=Pixel(0.8,0.2,0.1)}
    if kind == .fibers {f.renderSettings?.variance=36;f.renderSettings?.strength=18}
    if kind == .lensFlare {f.renderSettings?.brightness=175;f.renderSettings?.centerX=0.23;f.renderSettings?.centerY=0.37;f.renderSettings?.lens = .moviePrime}
    return f
  }
  func testEveryRenderDepthSelectionLocksAndDocumentUndo()throws {
    for kind in kinds {for depth in PixelDepth.allCases {
      let f=filter(kind),d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
      try session.execute(.applyFilter(id,f));let edited=session.document;XCTAssertNotEqual(edited,d,"\(kind) \(depth)")
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edited)
      var selected=d;selected.layers[0].x=3;selected.layers[0].y=2;selected.selection = .init(x:13,y:10,width:10,height:8)
      try Command.applyFilter(id,f).apply(to:&selected)
      guard case .raster(let before)=d.layers[0].content,case .raster(let after)=selected.layers[0].content else {return XCTFail()}
      var changed=0
      for y in 0..<32 {for x in 0..<40 {
        if (10..<20).contains(x) && (8..<16).contains(y) {if after.pixel(x:x,y:y) != before.pixel(x:x,y:y) {changed+=1}}
        else {XCTAssertEqual(after.pixel(x:x,y:y),before.pixel(x:x,y:y))}
      }};XCTAssertGreaterThan(changed,0,kind.rawValue)
      var locked=d;locked.layers[0].protection=[.transparency];try Command.applyFilter(id,f).apply(to:&locked)
      guard case .raster(let protected)=locked.layers[0].content else {return XCTFail()}
      for y in 0..<32 {for x in 0..<40 {XCTAssertEqual(protected.pixel(x:x,y:y).a,before.pixel(x:x,y:y).a)}}
      locked=d;locked.layers[0].locked=true;let original=locked;XCTAssertThrowsError(try Command.applyFilter(id,f).apply(to:&locked));XCTAssertEqual(locked,original)
    }}
  }
  func testSmartSourceMaskNative42Actions14AndUnsupportedInterchange()throws {
    for kind in kinds {
      let f=filter(kind);var smart=try fixture(smart:true);let original=smart,id=smart.layers[0].id
      try Command.applyFilter(id,f).apply(to:&smart);let output=try Renderer.composite(smart)
      XCTAssertNotEqual(output,try Renderer.composite(original));XCTAssertEqual(smart.minimumArchiveVersion,42)
      XCTAssertEqual(smart.layers[0].content,original.layers[0].content);XCTAssertEqual(smart.layers[0].smartObject,original.layers[0].smartObject)
      for bytes in [try NativeArchive.encode(smart),try NativeArchive.encodeChunked(smart)] {let decoded=try NativeArchive.decode(bytes);XCTAssertEqual(decoded,smart);XCTAssertEqual(try Renderer.composite(decoded),output)}
      var raw=try PropertyListSerialization.propertyList(from:NativeArchive.encode(smart),format:nil) as! [String:Any];raw["version"]=41
      XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:raw,format:.binary,options:0)))
      XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(kind.rawValue)\"}]"))
      let stack=smart.layers[0].smartFilters!
      try Command.smartFilterMask(id,.maskFill(id,0)).apply(to:&smart);XCTAssertEqual(try Renderer.composite(smart),try Renderer.composite(original))
      for operation in [ActionOperation.filter(.active,f),.filters(.active,stack)] {
        let action=RecordedAction(name:kind.title,steps:[.init(name:kind.title,operation:operation)]),bytes=try ActionLibraryFile(actions:[action]).encoded()
        let decoded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(decoded.version,14);XCTAssertEqual(try decoded.encoded(),bytes);var replay=original;try XCTUnwrap(decoded.actions[0].steps[0].operation.command(in:replay)).apply(to:&replay);XCTAssertEqual(try Renderer.composite(replay),output)
        var json=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];json["version"]=13;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:json)))
      }
      var channel=try fixture();try Command.channel(.quickMask(true,.init())).apply(to:&channel);let before=channel
      XCTAssertThrowsError(try Command.channel(.filter(.quickMask,f)).apply(to:&channel));XCTAssertEqual(channel,before)
    }
  }
  @MainActor func testWorkspacePreviewHistoryCancelCommitReeditAndImmediateMenus()async throws {
    for kind in kinds {
      let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer {store.renderTask?.cancel();store.cancelFilter()}
      store.backgroundColor=Pixel(0.2,0.4,0.7)
      store.beginFilter(kind)
      if kind.isImmediateRender {
        XCTAssertNil(store.filterDraft);await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
        let applied=try XCTUnwrap(store.document.layers[0].smartFilters?.filters.first?.filter)
        XCTAssertEqual(applied.renderSettings?.background,store.backgroundColor);XCTAssertEqual(applied.renderSettings?.foreground,store.brush.color)
        var expected=d;try Command.applyFilter(d.layers[0].id,applied).apply(to:&expected)
        expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(store.document.layers[0].smartFilters?.filters.first?.id)
        XCTAssertEqual(store.document,expected)
        let filterID=try XCTUnwrap(store.document.layers[0].smartFilters?.filters.first?.id)
        store.beginSmartFilter(d.layers[0].id,filterID:filterID);XCTAssertEqual(store.filterDraft?.filter,applied)
        let editModel=RenderWorkspace();await editModel.prepare(document:store.document,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(editModel.ready,editModel.error ?? "Not ready");editModel.close();store.cancelFilter()
        await store.undo();XCTAssertEqual(store.document,d)
        XCTAssertEqual(AppDelegate.filterMenus["Filter > Render > \(kind.title)"],kind);continue
      }
      if kind == .fibers {XCTAssertEqual(store.filterDraft?.filter.renderSettings?.background,store.backgroundColor)}
      let initial=try XCTUnwrap(store.filterDraft).filter,model=RenderWorkspace();store.renderWorkspace=model
      await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d)
      model.change(filter(kind));let changed=model.filter
      XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:try XCTUnwrap(model.apiState["filter"]))),changed)
      model.undo();XCTAssertEqual(model.filter,initial);model.redo();XCTAssertEqual(model.filter,changed)
      await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view=NSHostingView(rootView:RenderSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)))
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
      view.appearance=NSAppearance(named:.aqua);window.contentView=view;view.frame=NSRect(x:0,y:0,width:840,height:620);view.layoutSubtreeIfNeeded();view.displayIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) {let path=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/render-offscreen");try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true);try png.write(to:path.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png"))}}
      window.contentView=nil;store.filterDraft?.filter=model.filter;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
      let edited=store.document;await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,edited)
      store.beginSmartFilter(d.layers[0].id,filterID:try XCTUnwrap(edited.layers[0].smartFilters?.filters.first?.id));XCTAssertEqual(store.filterDraft?.filter,changed);store.cancelFilter();XCTAssertEqual(store.document,edited)
      store.session=EditorSession(document:d);store.beginFilter(kind);let cancelled=RenderWorkspace();await cancelled.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancelled.change(changed);let pending=cancelled.task;cancelled.close();store.cancelFilter();await pending?.value;XCTAssertEqual(store.document,d)
      XCTAssertEqual(AppDelegate.filterMenus["Filter > Render > \(kind.title)…"],kind)
    }
  }
  @MainActor func testGestureHistoryInvalidRecoveryAndCancelledPreview()async throws {
    let d=try fixture(),model=RenderWorkspace();await model.prepare(document:d,draft:.init(id:d.layers[0].id,filter:RasterFilter(.fibers)))
    model.beginGesture();model.update{$0.renderSettings?.variance=25};model.update{$0.renderSettings?.variance=40};model.endGesture();XCTAssertEqual(model.undoStates.count,1)
    model.undo();XCTAssertEqual(model.filter.renderSettings?.variance,16);model.redo();XCTAssertEqual(model.filter.renderSettings?.variance,40)
    let valid=model.filter;var invalid=valid;invalid.renderSettings?.variance=65;model.change(invalid);XCTAssertNotNil(model.error);XCTAssertEqual(model.filter,valid)
    model.change(valid);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready");model.close()
  }
  @MainActor func testFlareCenterGestureCoalescesAndCancelsPreview()async throws {
    let d=try fixture(),model=RenderWorkspace();await model.prepare(document:d,draft:.init(id:d.layers[0].id,filter:RasterFilter(.lensFlare)))
    XCTAssertTrue(model.ready,model.error ?? "Not ready");let initial=model.filter
    model.beginGesture();model.setFlareCenter(PathPoint(0.6,0.3));model.setFlareCenter(PathPoint(0.8,0.2));model.endGesture()
    XCTAssertEqual(model.undoStates.count,1);XCTAssertEqual(model.filter.renderSettings?.centerX,0.8);XCTAssertEqual(model.filter.renderSettings?.centerY,0.2)
    let moved=model.filter;await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    model.undo();XCTAssertEqual(model.filter,initial);model.redo();XCTAssertEqual(model.filter,moved)
    model.setFlareCenter(PathPoint(.nan,0));XCTAssertEqual(model.filter,moved)
    model.setFlareCenter(PathPoint(-3,4));XCTAssertEqual(model.filter.renderSettings?.centerX,-0.5);XCTAssertEqual(model.filter.renderSettings?.centerY,1.5)
    let task=model.task;model.close();await task?.value
  }
  @MainActor func testEmptyLayerGeneratorsAndCapturedColorsThroughHTTP()async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for kind in [RasterFilter.Kind.clouds,.fibers] {
        var original=try CraftDocument(width:12,height:8);original.layers[0].content = .raster(try Surface(width:1,height:1));original.layers[0].x=5;original.layers[0].y=4
        document.store.session=EditorSession(document:original);var f=RasterFilter(kind);f.renderSettings?.foreground=Pixel(0,1,0);f.renderSettings?.background=Pixel(0,1,0)
        let code=try await h.edit(service,document,"filter.apply",["layerID":original.layers[0].id.uuidString,"filter":f.apiState]);XCTAssertEqual(code,200)
        let result=try Renderer.composite(document.store.document)
        for y in 0..<8 {for x in 0..<12 {XCTAssertEqual(result.pixel(x:x,y:y),Pixel(0,1,0))}}
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
      }
    }
  }
  @MainActor func testHTTPDesktopEquivalenceSmartReeditNative42AndGuards()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for kind in self.kinds {
        let d=try self.fixture(),id=d.layers[0].id,f=self.filter(kind);document.store.session=EditorSession(document:d)
        let payload=f.apiState;var expected=d;try Command.applyFilter(id,f).apply(to:&expected)
        let status=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":payload]);XCTAssertEqual(status,200,kind.rawValue);XCTAssertEqual(document.store.document,expected)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }
      let d=try self.fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d)
      let params:[String:Any]=["layerID":id.uuidString,"filter":self.filter(.fibers).apiState]
      let status=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200)
      let changed=document.store.document,share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"41"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"42"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.renderSettings?.variance=30
      var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,changed)
      let stale=try await h.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.fibers);let busy=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
      for bad in [["kind":"fibers","render":["variance":65]],["kind":"lensFlare","render":["lens":"invalid"]],["kind":"clouds","render":["brightness":100]]] as [[String:Any]] {
        let code=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":bad]);XCTAssertEqual(code,400);XCTAssertEqual(document.store.document,changed)
      }
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema))
      let capabilities=try XCTUnwrap(RasterFilter.apiCapabilities["render"] as? [String:Any]);XCTAssertEqual(Set(capabilities["kinds"] as? [String] ?? []),Set(self.kinds.map(\.rawValue)))
    }
  }
}
