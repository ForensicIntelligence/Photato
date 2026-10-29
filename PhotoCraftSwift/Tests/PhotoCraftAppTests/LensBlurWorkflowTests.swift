import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LensBlurWorkflowTests:XCTestCase {
  let kinds:[RasterFilter.Kind]=[.lensBlur]
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument { try BlurGalleryWorkflowTests().fixture(depth,smart:smart) }
  func filter(_ kind:RasterFilter.Kind = .lensBlur)->RasterFilter { var f=RasterFilter(kind);f.lensBlur?.radius=5;f.lensBlur?.blades=5;f.lensBlur?.noiseAmount=2;return f }
  func testSelectionHistoryDepthSmartFiltersNative38AndActions10()throws {
    for kind in kinds {
      let f=filter(kind)
      for depth in [PixelDepth.u8,.u16] {
        let d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
        try session.execute(.applyFilter(id,f));let edited=session.document;XCTAssertNotEqual(edited,d);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edited)
        var selected=d;selected.selection = .init(x:10,y:8,width:10,height:8);try Command.applyFilter(id,f).apply(to:&selected)
        guard case .raster(let a)=d.layers[0].content,case .raster(let b)=selected.layers[0].content else { return XCTFail() };XCTAssertEqual(a.pixel(x:0,y:0),b.pixel(x:0,y:0));XCTAssertNotEqual(a.pixel(x:14,y:12),b.pixel(x:14,y:12))
        var locked=d;locked.layers[0].locked=true;XCTAssertThrowsError(try Command.applyFilter(id,f).apply(to:&locked))
      }
      var smart=try fixture(smart:true);let original=smart,id=smart.layers[0].id;try Command.applyFilter(id,f).apply(to:&smart)
      XCTAssertEqual(smart.minimumArchiveVersion,38);XCTAssertEqual(smart.layers[0].content,original.layers[0].content);XCTAssertEqual(smart.layers[0].smartObject,original.layers[0].smartObject)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(smart)),smart);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(smart)),smart)
      var raw=try PropertyListSerialization.propertyList(from:NativeArchive.encode(smart),format:nil) as! [String:Any];raw["version"]=37;XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:raw,format:.binary,options:0)))
      XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(kind.rawValue)\"}]"))
      var stack=smart.layers[0].smartFilters!;stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&smart);XCTAssertEqual(try Renderer.composite(smart),try Renderer.composite(original))
      for operation in [ActionOperation.filter(.active,f),.filters(.active,stack)] {
        let action=RecordedAction(name:kind.title,steps:[.init(name:kind.title,operation:operation)]),bytes=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,10)
        var json=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];json["version"]=9;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:json)))
      }
      var channel=try fixture();try Command.channel(.quickMask(true,.init())).apply(to:&channel);let before=channel;XCTAssertThrowsError(try Command.channel(.filter(.quickMask,f)).apply(to:&channel));XCTAssertEqual(channel,before)
    }
  }
  @MainActor func testNativeWorkspacePreviewUndoCancelCommitReeditAndOffscreen()async throws {
    for kind in kinds {
      let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer { store.renderTask?.cancel();store.cancelFilter() }
      store.beginFilter(kind);let model=LensBlurWorkspace();store.lensBlurWorkspace=model;await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d)
      model.change(filter(kind));let changed=model.filter;XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:try XCTUnwrap(model.apiState["filter"]))),changed);model.undo();XCTAssertEqual(model.filter,RasterFilter(kind));model.redo();XCTAssertEqual(model.filter,changed);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view=NSHostingView(rootView:LensBlurSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)));view.appearance=NSAppearance(named:.aqua)
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.borderless],backing:.buffered,defer:false);window.contentView=view;window.appearance=view.appearance;view.frame=NSRect(x:0,y:0,width:840,height:620);view.layoutSubtreeIfNeeded();view.displayIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/lens-blur-offscreen");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try png.write(to:root.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png")) } };window.contentView=nil
      store.filterDraft?.filter=model.filter;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
      var expected=d;try Command.applyFilter(d.layers[0].id,changed).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters?.filters[0].id ?? UUID();XCTAssertEqual(store.document,expected)
      let reedit=LensBlurWorkspace(),draft=FilterDraft(id:d.layers[0].id,filter:changed,filterID:try XCTUnwrap(store.document.layers[0].smartFilters?.filters[0].id));await reedit.prepare(document:store.document,draft:draft);XCTAssertEqual(reedit.filter,changed);reedit.close()
      let undone=await store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(store.document,d)
      store.beginFilter(kind);let cancel=LensBlurWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.change(changed);let task=cancel.task;cancel.close();store.cancelFilter();await task?.value;XCTAssertEqual(store.document,d)
    }
    XCTAssertEqual(AppDelegate.filterMenus["Filter > Blur > Lens Blur…"],.lensBlur)
    let hdr=EditorStore(document:try fixture(.f32));defer { hdr.renderTask?.cancel() };XCTAssertFalse(hdr.canBeginFilterKind(.lensBlur))
  }
  func depthFixture(smart:Bool=true)throws->CraftDocument {
    var d=try fixture(smart:smart);d.layers[0].mask=try Surface(width:40,height:32,fill:.white)
    let channel=AlphaChannel(name:"Focus",pixels:try Surface(width:40,height:32,fill:.white));d.alphaChannels=[channel];return d
  }
  func testDepthReferenceLifecycleHistoryCacheMaskIsolationAndMissingReferences()throws {
    for source in [LensBlurSettings.DepthSource.layerMask,.alphaChannel] {
      var d=try depthFixture();let id=d.layers[0].id,channel=d.alphaChannels![0].id;var f=filter();f.lensBlur?.noiseAmount=0;f.lensBlur?.depthSource=source;f.lensBlur?.depthChannelID=source == .alphaChannel ? channel:nil
      try Command.applyFilter(id,f).apply(to:&d);let before=d,cache=try Renderer.render(d)
      let removals:[Command]=source == .layerMask ? [.deleteMask(id),.applyMask(id),.mask(id,nil)]:[.channel(.delete(channel))]
      for command in removals { XCTAssertThrowsError(try command.apply(to:&d));XCTAssertEqual(d,before) }
      // A Smart Filter mask is independent of the layer-mask depth source.
      try Command.smartFilterMask(id,.deleteMask(id)).apply(to:&d);XCTAssertNil(d.layers[0].smartFilters?.mask);XCTAssertNotNil(d.layers[0].mask)
      d=before
      if source == .layerMask {
        try Command.maskFill(id,0).apply(to:&d)
        var props=d.layers[0].effectiveMaskProperties;props.enabled=false;try Command.maskProperties(id,props).apply(to:&d)
      } else {
        try Command.channel(.rename(channel,"Renamed depth")).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),cache.surface)
        var updated=d.alphaChannels![0];updated.pixels=try Surface(width:40,height:32,fill:.black);d.alphaChannels=[updated]
      }
      let fresh=try Renderer.composite(d);XCTAssertNotEqual(try fresh.rgbaData(depth:.u8),try cache.surface.rgbaData(depth:.u8));XCTAssertEqual(try Renderer.render(d,reusing:cache).surface,fresh)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      var session=EditorSession(document:before);try session.execute(.smartFilters(id,nil));try session.execute(source == .layerMask ? .deleteMask(id):.channel(.delete(channel)));try session.undo();try session.undo();XCTAssertEqual(session.document,before)
      var invalid=f;invalid.lensBlur?.depthSource = .alphaChannel;invalid.lensBlur?.depthChannelID=UUID();var stack=before.layers[0].smartFilters!;stack.enabled=false;stack.filters[0].filter=invalid
      var rejected=before;XCTAssertThrowsError(try Command.smartFilters(id,stack).apply(to:&rejected));XCTAssertEqual(rejected,before)
      rejected.layers[0].smartFilters=stack;XCTAssertThrowsError(try rejected.validate())
    }
  }
  @MainActor func testDepthPickerUsesCurrentInputCoordinatesAndLocalUndo()async throws {
    var d=try depthFixture();let id=d.layers[0].id;d.layers[0].x=3;d.layers[0].y=2
    d.layers[0].mask?.setPixel(x:4,y:5,Pixel(0.6,0.6,0.6));d.alphaChannels?[0].pixels.setPixel(x:7,y:7,Pixel(0.2,0.2,0.2))
    let model=LensBlurWorkspace();await model.prepare(document:d,draft:FilterDraft(id:id,filter:filter()));defer { model.close() }
    XCTAssertEqual(model.depthChoices.count,4);model.setDepth("layerMask");model.pickFocus(x:7.5,y:7.5);XCTAssertEqual(model.filter.lensBlur?.focalDistance ?? -1,153,accuracy:0.01)
    model.setDepth(d.alphaChannels![0].id.uuidString);model.pickFocus(x:7.5,y:7.5);XCTAssertEqual(model.filter.lensBlur?.focalDistance ?? -1,51,accuracy:0.01)
    model.update{$0.lensBlur?.invert=true};model.pickFocus(x:7.5,y:7.5);XCTAssertEqual(model.filter.lensBlur?.focalDistance ?? -1,204,accuracy:0.01)
    model.undo();XCTAssertEqual(model.filter.lensBlur?.focalDistance ?? -1,51,accuracy:0.01);model.redo();XCTAssertEqual(model.filter.lensBlur?.focalDistance ?? -1,204,accuracy:0.01)
    await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState))
  }
  @MainActor func testHTTPDesktopDepthSourcesSmartReeditNative38AndGuards()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for source in LensBlurSettings.DepthSource.allCases {
        let d=try self.depthFixture(smart:false),id=d.layers[0].id;document.store.session=EditorSession(document:d)
        var settings:[String:Any]=["depthSource":source.rawValue,"radius":5,"blades":4,"noiseAmount":5,"distribution":"gaussian","monochromatic":true]
        if source == .alphaChannel { settings["depthChannelID"]=d.alphaChannels![0].id.uuidString }
        let payload:[String:Any]=["kind":"lensBlur","lensBlur":settings],f=try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:payload));var expected=d;try Command.applyFilter(id,f).apply(to:&expected)
        let result=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":payload]);XCTAssertEqual(result,200);XCTAssertEqual(document.store.document,expected)
      }
      let d=try self.depthFixture(),id=d.layers[0].id;document.store.session=EditorSession(document:d)
      let payload:[String:Any]=["kind":"lensBlur","lensBlur":["depthSource":"alphaChannel","depthChannelID":d.alphaChannels![0].id.uuidString,"radius":6]],params:[String:Any]=["layerID":id.uuidString,"filter":payload]
      let status=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200);let changed=document.store.document,share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let old=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"37"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"38"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.lensBlur?.focalDistance=255;var stackPayload=stack.apiState;stackPayload.removeValue(forKey:"hasMask");stackPayload.removeValue(forKey:"maskTransform")
      let edited=try await h.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":stackPayload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,changed)
      let stale=try await h.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.lensBlur);let busy=try await h.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let bad=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"lensBlur","lensBlur":["radius":101]]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,changed)
      let missing=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"lensBlur","lensBlur":["depthSource":"alphaChannel","depthChannelID":UUID().uuidString]]]);XCTAssertEqual(missing,422);XCTAssertEqual(document.store.document,changed)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema))
    }
  }
}
