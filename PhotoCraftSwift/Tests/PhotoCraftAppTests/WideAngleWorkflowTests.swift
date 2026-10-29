import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class WideAngleWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false) throws -> CraftDocument { try BlurGalleryWorkflowTests().fixture(depth,smart:smart) }
  func filter()->RasterFilter { var f=RasterFilter(.adaptiveWideAngle);f.wideAngle?.model = .fisheye;f.wideAngle?.focalLength=12;var c=WideAngleSettings.Constraint(points:[.init(0.1,0.25),.init(0.9,0.3)]);c.setOrientation(.horizontal,at:0);f.wideAngle?.constraints=[c];return f }
  func testDepthSelectionLocksHistoryAndInvalidAtomicity() throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
      try session.execute(.applyFilter(id,RasterFilter(.adaptiveWideAngle)));XCTAssertEqual(session.document,d)
      try session.execute(.applyFilter(id,filter()));XCTAssertNotEqual(session.document.layers[0].content,d.layers[0].content);let after=session.document
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,after)
      var selected=d;selected.selection = .init(x:8,y:8,width:12,height:12);try Command.applyFilter(id,filter()).apply(to:&selected)
      guard case .raster(let original)=d.layers[0].content,case .raster(let result)=selected.layers[0].content else { return XCTFail() };XCTAssertEqual(result.pixel(x:0,y:0),original.pixel(x:0,y:0))
      var locked=d;locked.layers[0].protection=[.transparency];var edgeFilter=filter();edgeFilter.wideAngle?.scale=50
      try Command.applyFilter(id,edgeFilter).apply(to:&locked)
      guard case .raster(let lockedPixels)=locked.layers[0].content else { return XCTFail() }
      for y in 0..<32 { for x in 0..<40 { XCTAssertEqual(lockedPixels.pixel(x:x,y:y).a,original.pixel(x:x,y:y).a) } }
      locked.layers[0].protection=[.image];let protected=locked;XCTAssertThrowsError(try Command.applyFilter(id,edgeFilter).apply(to:&locked));XCTAssertEqual(locked,protected)
      var bad=filter();bad.wideAngle?.scale = .nan;let before=session.document;XCTAssertThrowsError(try session.execute(.applyFilter(id,bad)));XCTAssertEqual(session.document,before)
      var channel=d;try Command.channel(.quickMask(true,.init())).apply(to:&channel);let channelBefore=channel;XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter())).apply(to:&channel));XCTAssertEqual(channel,channelBefore)
    }
  }
  func testNative31SmartFilterSourceRetentionMaskAndInterchangeBoundary() throws {
    var d=try fixture(smart:true);let before=d,id=d.layers[0].id,f=filter()
    try Command.applyFilter(id,f).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,31);XCTAssertEqual(d.layers[0].smartObject,before.layers[0].smartObject);XCTAssertEqual(d.layers[0].content,before.layers[0].content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d);XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
    XCTAssertNotEqual(try Renderer.composite(d),try Renderer.composite(before))
    var stack=d.layers[0].smartFilters!;stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(before))
    stack.filters[0].opacity=1;stack.mask=try Surface(width:40,height:32,depth:.u8,fill:.clear);try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(before))
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"adaptiveWideAngle\"}]"))
  }
  @MainActor func testNativeLinesPolygonsOrientationsUndoCommitCancelAndLayout() async throws {
    let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer { store.renderTask?.cancel() }
    store.beginFilter(.adaptiveWideAngle);let model=WideAngleWorkspace();await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d)
    model.beginGesture();model.addLine(.init(0.1,0.25),.init(0.9,0.3),axis:true);model.endGesture();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(model.constraint?.orientation(0),.horizontal)
    let changed=model.settings;model.undo();await model.task?.value;XCTAssertEqual(model.settings,.init());model.redo();await model.task?.value;XCTAssertEqual(model.settings,changed)
    model.addPolygonPoint(.init(0.2,0.6));model.addPolygonPoint(.init(0.8,0.6));model.addPolygonPoint(.init(0.8,0.9));model.finishPolygon();await model.task?.value
    XCTAssertEqual(model.settings.constraints.count,2);XCTAssertEqual(model.constraint?.segmentCount,3)
    model.selectedSegment=1;model.orient(.vertical);await model.task?.value;XCTAssertEqual(model.constraint?.orientation(1),.vertical);XCTAssertEqual(model.constraint?.orientation(0),.free)
    model.remove();await model.task?.value;model.beginGesture();model.movePoint(constraint:0,point:0,to:.init(0.15,0.25));model.movePoint(constraint:0,point:0,to:.init(0.2,0.25));model.endGesture();await model.task?.value
    model.undo();await model.task?.value;XCTAssertEqual(model.settings,changed)
    let view=NSHostingView(rootView:WideAngleSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:940,height:720);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();let folder=root.appendingPathComponent("artifacts/wide-angle-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(UUID().uuidString+".png")) } }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState))
    let committed=model.settings;store.filterDraft?.filter.wideAngle=committed;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=d,f=RasterFilter(.adaptiveWideAngle);f.wideAngle=committed;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters!.filters[0].id;XCTAssertEqual(store.document,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,d)
    store.beginFilter(.adaptiveWideAngle);let cancel=WideAngleWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.change(filter().wideAngle!);let task=cancel.task;cancel.close();store.cancelFilter();await task?.value;XCTAssertEqual(store.document,d)
  }
  func testPreviewCoordinatesAndFilterPrefix() throws {
    var s=WideAngleSettings();s.scale=80;let mesh=try WideAngleSolver.solve(s,width:40,height:32)
    let map=WideAngleCoordinates(mesh:mesh,transform:.translation(12,7),sourceSize:.init(width:40,height:32),scale:3,offset:.init(x:20,y:30)),p=PathPoint(0.25,0.75)
    let back=try XCTUnwrap(map.source(map.screen(p)));XCTAssertEqual(back.x,p.x,accuracy:1e-9);XCTAssertEqual(back.y,p.y,accuracy:1e-9)
    XCTAssertNil(map.source(.init(x:0,y:0)))
    var d=try fixture(smart:true),f=RasterFilter(.adaptiveWideAngle);f.wideAngle=s;let id=d.layers[0].id
    try Command.applyFilter(id,f).apply(to:&d);let fid=d.layers[0].smartFilters!.filters[0].id
    let prefix=try FilterDraft(id:id,filter:f,filterID:fid).inputLayer(in:d)
    var original=d.layers[0];original.smartFilters=nil
    XCTAssertEqual(prefix.content,try SmartFilterEngine.renderedLayer(original,in:d).content)
  }
  @MainActor func testHTTPSharedEngineProfilesSmartFilterNative31AndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let d=try self.fixture(),id=d.layers[0].id;document.store.session=EditorSession(document:d);var expected=d;try Command.applyFilter(id,self.filter()).apply(to:&expected)
      let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(self.filter().wideAngle!))
      let params:[String:Any]=["layerID":id.uuidString,"filter":["kind":"adaptiveWideAngle","wideAngle":encoded]]
      let code=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(code,200);XCTAssertEqual(document.store.document,expected)
      let smart=try self.fixture(smart:true),sid=smart.layers[0].id;document.store.session=EditorSession(document:smart)
      let request:[String:Any]=["layerID":sid.uuidString,"filter":["kind":"adaptiveWideAngle","wideAngle":["scale":80]]]
      let applied=try await helper.edit(service,document,"filter.apply",request);XCTAssertEqual(applied,200);let changed=document.store.document
      let share=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(share)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"30"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"31"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.wideAngle?.scale=70;var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await helper.edit(service,document,"smartFilter.set",["layerID":sid.uuidString,"stack":payload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      _=try await helper.edit(service,document,"history.undo");XCTAssertEqual(document.store.document,changed)
      let stale=try await helper.edit(service,document,"filter.apply",request,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.adaptiveWideAngle);let busy=try await helper.edit(service,document,"filter.apply",request);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let bad=try await helper.edit(service,document,"filter.apply",["layerID":sid.uuidString,"filter":["kind":"adaptiveWideAngle","wideAngle":["scale":true]]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,changed)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:WideAngleSettings.apiCapabilities))
    }
  }
  @MainActor func testPlacedSmartObjectCoordinatesAndRecordedBatch() async throws {
    var d=try fixture(smart:true);d.layers[0].affine = .scale(1.5,0.75)
    let projected=try SmartFilterEngine.renderedLayer(d.layers[0],in:d)
    guard case .raster(let pixels)=projected.content else { return XCTFail() }
    let model=WideAngleWorkspace();await model.prepare(document:d,draft:FilterDraft(id:d.layers[0].id,filter:filter()))
    XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(model.sourceSize,CGSize(width:pixels.width,height:pixels.height));XCTAssertEqual(model.sourceTransform,projected.coordinateTransform);model.close()
    let root=try ActionBatchTests().folder();defer { try? FileManager.default.removeItem(at:root) }
    let source=try fixture(),f=filter()
    let action=RecordedAction(name:"Wide Angle",steps:[.init(name:"Adaptive Wide Angle",operation:.filter(.active,f))])
    let portable=try JSONDecoder().decode(RecordedAction.self,from:JSONEncoder().encode(action));let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];XCTAssertEqual(try encoder.encode(portable),try encoder.encode(action))
    var expected=source;try Command.applyFilter(source.layers[0].id,f).apply(to:&expected)
    let results=try await ActionBatch.run(sources:[.init(document:source)],action:portable,destination:root,format:.native)
    let output=try XCTUnwrap(results.first?.output);XCTAssertEqual(try DocumentIO.read(root.appendingPathComponent(output)),expected)
    let helper=AutomationTests(),library=ActionLibrary();try library.save(action)
    try await helper.withService(actions:library,pressedMouseButtons:{0}) { service,document in
      document.store.session=EditorSession(document:source);try service.share(document);service.setDocumentSavesEnabled(true);service.setSaveDirectory(root)
      let share=try XCTUnwrap(service.shares.first?.id)
      let parameters:[String:Any]=["actionID":action.id.uuidString,"sources":[["id":share.uuidString,"revision":service.revision(document.store)]],"format":"photato","suffix":"-api"]
      let response=try await helper.request(service,path:"/v1/documents/\(share)/commands",body:["command":"actions.batch","revision":service.revision(document.store),"parameters":parameters]);XCTAssertEqual(response.0.statusCode,200)
      let body=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any]),item=try XCTUnwrap((body["results"] as? [[String:Any]])?.first),file=try XCTUnwrap(item["output"] as? String)
      XCTAssertEqual(try DocumentIO.read(root.appendingPathComponent(file)),expected);XCTAssertEqual(document.store.document,source)
    }
  }

}
