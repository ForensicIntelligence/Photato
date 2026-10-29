import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class DistortionWorkflowTests:XCTestCase {
  let kinds=RasterFilter.Kind.allCases.filter(\.isDistortion)
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func filter(_ kind:RasterFilter.Kind)->RasterFilter {
    var f=RasterFilter(kind)
    if kind == .displace {f.distortion?.map = .init(width:2,height:1,channels:2,samples:Data([150,104,90,177]),name:"Original test map")}
    if kind == .shear {f.distortion?.points=[.init(0,0),.init(0.4,0.6),.init(1,-0.3)]}
    if kind == .wave {f.distortion?.generators=7}
    if kind == .pinch || kind == .spherize || kind == .ripple || kind == .zigzag {f.distortion?.amount=75}
    if kind == .twirl {f.distortion?.angle=120}
    if kind == .polarCoordinates {f.distortion?.polarMode = .polarToRectangular}
    return f
  }
  func testEveryDistortionDepthSelectionLocksAndDocumentUndo()throws {
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
  func testSmartSourceMaskNative39Actions11AndUnsupportedInterchange()throws {
    for kind in kinds {
      let f=filter(kind);var smart=try fixture(smart:true);let original=smart,id=smart.layers[0].id
      try Command.applyFilter(id,f).apply(to:&smart);let output=try Renderer.composite(smart)
      XCTAssertNotEqual(output,try Renderer.composite(original));XCTAssertEqual(smart.minimumArchiveVersion,39)
      XCTAssertEqual(smart.layers[0].content,original.layers[0].content);XCTAssertEqual(smart.layers[0].smartObject,original.layers[0].smartObject)
      for bytes in [try NativeArchive.encode(smart),try NativeArchive.encodeChunked(smart)] {let decoded=try NativeArchive.decode(bytes);XCTAssertEqual(decoded,smart);XCTAssertEqual(try Renderer.composite(decoded),output)}
      var raw=try PropertyListSerialization.propertyList(from:NativeArchive.encode(smart),format:nil) as! [String:Any];raw["version"]=38
      XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:raw,format:.binary,options:0)))
      XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(kind.rawValue)\"}]"))
      let stack=smart.layers[0].smartFilters!
      try Command.smartFilterMask(id,.maskFill(id,0)).apply(to:&smart);XCTAssertEqual(try Renderer.composite(smart),try Renderer.composite(original))
      for operation in [ActionOperation.filter(.active,f),.filters(.active,stack)] {
        let action=RecordedAction(name:kind.title,steps:[.init(name:kind.title,operation:operation)]),bytes=try ActionLibraryFile(actions:[action]).encoded()
        let decoded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(decoded.version,11);XCTAssertEqual(try decoded.encoded(),bytes);var replay=original;try XCTUnwrap(decoded.actions[0].steps[0].operation.command(in:replay)).apply(to:&replay);XCTAssertEqual(try Renderer.composite(replay),output)
        var json=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];json["version"]=10;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:json)))
      }
      var channel=try fixture();try Command.channel(.quickMask(true,.init())).apply(to:&channel);let before=channel
      XCTAssertThrowsError(try Command.channel(.filter(.quickMask,f)).apply(to:&channel));XCTAssertEqual(channel,before)
    }
  }
  @MainActor func testWorkspacePreviewUndoCancelCommitReeditAndControls()async throws {
    for kind in kinds {
      let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer {store.renderTask?.cancel();store.cancelFilter()}
      store.beginFilter(kind);let model=DistortionWorkspace();store.distortionWorkspace=model
      await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertEqual(store.document,d)
      if kind == .displace {XCTAssertFalse(model.ready);XCTAssertNotNil(model.image)}else{XCTAssertTrue(model.ready,model.error ?? "Not ready")}
      model.change(filter(kind));let changed=model.filter
      XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:try XCTUnwrap(model.apiState["filter"]))),changed)
      model.undo();XCTAssertEqual(model.filter,RasterFilter(kind));model.redo();XCTAssertEqual(model.filter,changed)
      await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view=NSHostingView(rootView:DistortionSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)))
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
      view.appearance=NSAppearance(named:.aqua);window.contentView=view;view.frame=NSRect(x:0,y:0,width:840,height:620);view.layoutSubtreeIfNeeded();view.displayIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds),[RasterFilter.Kind.displace,.shear,.wave].contains(kind) {
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if let png=bitmap.representation(using:.png,properties:[:]) {
          let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/distortion-offscreen")
          try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try png.write(to:root.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png"))
        }
      };window.contentView=nil
      store.filterDraft?.filter=changed;model.close();store.commitFilter();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
      var expected=d;try Command.applyFilter(d.layers[0].id,changed).apply(to:&expected)
      expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters?.filters[0].id ?? UUID();XCTAssertEqual(store.document,expected)
      let reedit=DistortionWorkspace(),draft=FilterDraft(id:d.layers[0].id,filter:changed,filterID:try XCTUnwrap(store.document.layers[0].smartFilters?.filters[0].id))
      await reedit.prepare(document:store.document,draft:draft);XCTAssertEqual(reedit.filter,changed);XCTAssertTrue(reedit.ready,reedit.error ?? "Not ready");reedit.close()
      let undone=await store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(store.document,d)
      store.beginFilter(kind);let cancel=DistortionWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.change(changed)
      let pending=cancel.task;cancel.close();store.cancelFilter();await pending?.value;XCTAssertEqual(store.document,d)
      XCTAssertEqual(AppDelegate.filterMenus["Filter > Distort > \(kind.title)…"],kind)
    }
  }
  @MainActor func testMapImportGestureUndoInvalidRecoveryAndCancelledPreview()async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("Photato-Distortion-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
    var map=try CraftDocument(width:2,height:1);map.layers[0].content = .raster(try Surface(width:2,height:1,fill:Pixel(128.0/255,128.0/255,128.0/255)))
    let url=root.appendingPathComponent("Neutral.png");try DocumentIO.encode(map,format:.png).write(to:url)
    let decoded=try DistortionWorkspace.readMap(url);XCTAssertEqual(decoded.channels,1);XCTAssertEqual(decoded.samples,Data([128,128]))
    map.layers[0].content = .raster(try Surface(width:2,height:1,fill:Pixel(1,0,0.5)));let color=root.appendingPathComponent("Color.png");try DocumentIO.encode(map,format:.png).write(to:color)
    let rgb=try DistortionWorkspace.readMap(color);XCTAssertEqual(rgb.channels,2);XCTAssertEqual(rgb.samples,Data([255,0,255,0]))
    let d=try fixture(),model=DistortionWorkspace();await model.prepare(document:d,draft:.init(id:d.layers[0].id,filter:RasterFilter(.displace)))
    await model.loadMap(url);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(model.filter.distortion?.map,decoded)
    model.beginGesture();model.update{$0.distortion?.horizontalScale=20};model.update{$0.distortion?.horizontalScale=30};model.endGesture()
    XCTAssertEqual(model.undoStates.count,2);model.undo();XCTAssertEqual(model.filter.distortion?.horizontalScale,10);model.redo();XCTAssertEqual(model.filter.distortion?.horizontalScale,30)
    let valid=model.filter;var invalid=valid;invalid.distortion?.horizontalScale=1000;model.change(invalid);XCTAssertNotNil(model.error);XCTAssertEqual(model.filter,valid)
    model.change(valid);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    model.close();await model.loadMap(color);XCTAssertEqual(model.filter,valid)
    let invalidURL=root.appendingPathComponent("Invalid.png");try Data([0,1,2,3]).write(to:invalidURL);XCTAssertThrowsError(try DistortionWorkspace.readMap(invalidURL))
  }
  @MainActor func testHTTPDesktopEquivalenceSmartReeditNative39AndGuards()async throws {
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
      let params:[String:Any]=["layerID":id.uuidString,"filter":self.filter(.displace).apiState]
      let status=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200)
      let changed=document.store.document,share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"38"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"39"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.distortion?.horizontalScale=30
      var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,changed)
      let stale=try await h.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.displace);let busy=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
      for bad in [["kind":"displace"],["kind":"wave","distortion":["generators":1000]],["kind":"shear","distortion":["points":[]]]] as [[String:Any]] {
        let code=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":bad]);XCTAssertEqual(code,400);XCTAssertEqual(document.store.document,changed)
      }
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema))
      let capabilities=try XCTUnwrap(RasterFilter.apiCapabilities["distortion"] as? [String:Any]);XCTAssertEqual(Set(capabilities["kinds"] as? [String] ?? []),Set(self.kinds.map(\.rawValue)))
    }
  }
}
