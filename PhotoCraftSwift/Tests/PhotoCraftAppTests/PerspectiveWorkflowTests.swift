import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PerspectiveWorkflowTests:XCTestCase {
  func settings()->PerspectiveSettings {
    var s=PerspectiveSettings();s.planes=[.init(source:[PathPoint(12,10),PathPoint(36,10),PathPoint(36,30),PathPoint(12,30)],destination:[PathPoint(12,10),PathPoint(39,8),PathPoint(38,32),PathPoint(10,30)])];return s
  }
  func adjacent()->PerspectiveSettings {
    var s=PerspectiveSettings();s.planes=[.init(source:[PathPoint(0,0),PathPoint(40,0),PathPoint(40,30),PathPoint(0,30)],destination:[PathPoint(-3,4),PathPoint(40,-4),PathPoint(45,32),PathPoint(1,34)]),.init(source:[PathPoint(40,0),PathPoint(80,10),PathPoint(80,40),PathPoint(40,30)],destination:[PathPoint(40,-4),PathPoint(90,2),PathPoint(82,45),PathPoint(45,32)])];return s
  }
  func filter(_ settings:PerspectiveSettings?=nil)->RasterFilter { var f=RasterFilter(.perspectiveWarp);f.perspective=settings ?? self.settings();return f }
  func testGeometryMatchesOriginalRustSharedEdgesAndStraightening() throws {
    struct Oracle:Decodable { let input:[[Double]],mapped:[[Double]],horizontal:[[[Double]]],vertical:[[[Double]]],auto:[[[Double]]],groups:[[[Int]]] }
    let data=try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/Perspective/original.json")),oracle=try JSONDecoder().decode(Oracle.self,from:data),s=adjacent(),map=try PerspectiveMap(s)
    for (p,q) in zip(oracle.input,oracle.mapped) { let output=map.point(PathPoint(p[0],p[1]));XCTAssertEqual(output.x,q[0],accuracy:1e-9);XCTAssertEqual(output.y,q[1],accuracy:1e-9) }
    XCTAssertEqual(s.linkedCorners,oracle.groups.map{$0.map{$0[0]*4+$0[1]}})
    for mode in PerspectiveSettings.Straighten.allCases {
      let result=s.straightened(mode),expected=mode == .horizontal ? oracle.horizontal:mode == .vertical ? oracle.vertical:oracle.auto
      for (plane,quad) in zip(result.planes,expected) { for (p,q) in zip(plane.destination,quad) { XCTAssertEqual(p.x,q[0],accuracy:1e-9);XCTAssertEqual(p.y,q[1],accuracy:1e-9) } }
    }
    for j in 0...20 {
      let t=Double(j)/20,a=map.planePoint(0,u:1-1e-8,v:t,warped:true),b=map.planePoint(1,u:1e-8,v:t,warped:true)
      // The second plane's projective edge parameter differs; compare identical
      // source locations approached from either side instead.
      let p=PathPoint(40,30*t),left=map.point(PathPoint(p.x-1e-7,p.y)),right=map.point(PathPoint(p.x+1e-7,p.y))
      XCTAssertLessThan(hypot(left.x-right.x,left.y-right.y),1e-5);XCTAssertTrue([a.x,a.y,b.x,b.y].allSatisfy(\.isFinite))
    }
  }
  func testLinkedCornerMovesSnappingAndPersistentEdgeLocks() throws {
    let s=adjacent();var moved=s.movingCorner(plane:0,corner:1,to:PathPoint(43,-8),layout:false)
    XCTAssertEqual(moved.planes[0].destination[1],moved.planes[1].destination[0]);try moved.validate()
    moved.locks=[.init(plane:0,edge:0,axis:.horizontal)];moved=moved.normalized()
    XCTAssertEqual(moved.planes[0].destination[0].y,moved.planes[0].destination[1].y)
    moved=moved.movingCorner(plane:1,corner:0,to:PathPoint(45,-10),layout:false)
    XCTAssertEqual(moved.planes[0].destination[0].y,-10);XCTAssertEqual(moved.planes[0].destination[1].y,-10)
    let rotated=moved.transformed(.rotation(90));XCTAssertEqual(rotated.locks.first?.axis,.vertical)
    XCTAssertTrue(moved.transformed(.rotation(30)).locks.isEmpty)
    var raw=s;raw.locks=[.init(plane:0,edge:0,axis:.horizontal)];let canonical=raw.normalized(),tilted=raw.transformed(.rotation(30))
    XCTAssertEqual(tilted.planes[0].destination[0],canonical.planes[0].destination[0].transformed(.rotation(30)))
    let translated=moved.transformed(.translation(3,4));XCTAssertEqual(translated.planes[0].source[0],PathPoint(3,4));XCTAssertEqual(translated.locks,moved.locks)
  }
  func testStrictProgramsDegenerateHorizonAndUnsupportedTargets() throws {
    let payload=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings())) as! [String:Any]
    XCTAssertEqual(try PerspectiveSettings.decodeJSON(JSONSerialization.data(withJSONObject:payload)),settings())
    var simple=payload;simple["planes"]=[["source":[["x":0,"y":0],["x":4,"y":0],["x":4,"y":4],["x":0,"y":4]]]];XCTAssertTrue(try PerspectiveSettings.decodeJSON(JSONSerialization.data(withJSONObject:simple)).isIdentity)
    for raw in ["{\"planes\":false}","{\"planes\":[{\"source\":[]}]}","{\"straighten\":\"unknown\"}","{\"unknown\":1}","{\"locks\":[{\"plane\":0,\"edge\":0,\"axis\":\"horizontal\"}]}"] { XCTAssertThrowsError(try PerspectiveSettings.decodeJSON(Data(raw.utf8))) }
    var invalid=settings();invalid.planes[0].destination.swapAt(1,2);XCTAssertThrowsError(try invalid.validate());invalid=settings();invalid.planes[0].source[0].x = .infinity;XCTAssertThrowsError(try invalid.validate())
    var horizon=PerspectiveSettings();horizon.planes=[.init(source:[PathPoint(0,0),PathPoint(1,0),PathPoint(1,1),PathPoint(0,1)],destination:[PathPoint(0,0),PathPoint(1,0),PathPoint(2,1),PathPoint(0,1)])]
    XCTAssertThrowsError(try PerspectiveEngine.mapping(width:10,height:10,origin:PathPoint(0,0),settings:horizon))
    var d=try WarpWorkflowTests().fixture();try Command.channel(.quickMask(true,.init())).apply(to:&d);let before=d
    XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter())).apply(to:&d));XCTAssertTrue(d == before)
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"perspectiveWarp\"}]"))
    d=try WarpWorkflowTests().fixture();d.selection=IntRect(x:0,y:0,width:2,height:2);XCTAssertThrowsError(try PerspectiveEngine.validateTarget(d,layerID:d.layers[0].id))
  }
  func testRasterDepthsExactTranslationMasksIdentityAndHistory() throws {
    for depth in PixelDepth.allCases {
      var d=try WarpWorkflowTests().fixture(depth),mask=try Surface(width:24,height:20,depth:depth,fill:.white);mask.setPixel(x:8,y:8,Pixel(0.3,0.3,0.3));d.layers[0].mask=mask
      var properties=MaskProperties();properties.enabled=false;properties.density=0.6;properties.feather=2;d.layers[0].maskProperties=properties
      if depth == .f32,case .raster(var pixels)=d.layers[0].content { pixels.setLinearPixel(x:8,y:8,Pixel(3.5,-0.1,2,1));d.layers[0].content = .raster(pixels) }
      var identity=d;try Command.applyFilter(d.layers[0].id,RasterFilter(.perspectiveWarp)).apply(to:&identity);XCTAssertTrue(identity == d)
      var s=settings();s.interpolation = .nearest;s.planes[0].destination=s.planes[0].source.map{PathPoint($0.x+3,$0.y+2)}
      var session=EditorSession(document:d);try session.execute(.applyFilter(d.layers[0].id,filter(s)));let result=session.document
      XCTAssertEqual(result.layers[0].maskProperties,properties);XCTAssertEqual(result.layers[0].mask?.depth,depth)
      if depth == .f32 { XCTAssertEqual(try Renderer.composite(result).linearPixel(x:23,y:20).r,3.5,accuracy:0.0001) }
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result)) == result);try session.undo();XCTAssertTrue(session.document == d);try session.redo();XCTAssertTrue(session.document == result)
    }
  }
  func testSmartSourceNative26ReeditTransformsAndRasterization() throws {
    var d=try WarpWorkflowTests().fixture(smart:true);let original=d,id=d.layers[0].id
    try Command.applyFilter(id,filter()).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,26);XCTAssertEqual(d.layers[0].content,original.layers[0].content);XCTAssertEqual(d.layers[0].smartObject,original.layers[0].smartObject)
    for bytes in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] { XCTAssertTrue(try NativeArchive.decode(bytes) == d) }
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d,format:.psd))
    var stack=d.layers[0].smartFilters!;stack.filters[0].filter.perspective?.planes[0].destination[1].x += 2;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(d.layers[0].smartFilters,stack)
    let image=try Renderer.composite(d);var raster=d;try Command.rasterize(id,Renderer.layerSurface(d.layers[0],in:d)).apply(to:&raster);XCTAssertEqual(try Renderer.composite(raster),image)
    let source=stack.filters[0].filter.perspective!.planes[0].source[0];try Command.move(id,d.layers[0].x+4,d.layers[0].y+3).apply(to:&d)
    XCTAssertEqual(d.layers[0].smartFilters!.filters[0].filter.perspective!.planes[0].source[0],PathPoint(source.x+4,source.y+3))
    try Command.transform(id,.scale(2,2),.nearest).apply(to:&d);XCTAssertEqual(d.layers[0].smartFilters!.filters[0].filter.perspective!.planes[0].source[0],PathPoint((source.x+4)*2,(source.y+3)*2))
  }
  func testSmartStackMasksOpacityOrderAndPuppetComposition() throws {
    let original=try WarpWorkflowTests().fixture(smart:true),id=original.layers[0].id;var d=original
    try Command.applyFilter(id,filter()).apply(to:&d);let output=try Renderer.composite(d);XCTAssertNotEqual(output,try Renderer.composite(original))
    var stack=d.layers[0].smartFilters!;stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(original))
    stack.filters[0].opacity=1;stack.mask=try Surface(width:d.width,height:d.height,fill:.black);try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(original))
    var a=original,b=original;try Command.applyFilter(id,RasterFilter(.mosaic)).apply(to:&a);try Command.applyFilter(id,filter()).apply(to:&a);try Command.applyFilter(id,filter()).apply(to:&b);try Command.applyFilter(id,RasterFilter(.mosaic)).apply(to:&b);XCTAssertNotEqual(try Renderer.composite(a),try Renderer.composite(b))
    var combined=original;try Command.applyFilter(id,PuppetWorkflowTests().filter()).apply(to:&combined);try Command.applyFilter(id,filter()).apply(to:&combined);XCTAssertEqual(combined.layers[0].content,original.layers[0].content);XCTAssertEqual(combined.layers[0].smartFilters?.filters.count,2);_ = try Renderer.composite(combined)
  }
  @MainActor func testNativeLayoutWarpLocksUndoCommitCancelAndReedit() async throws {
    let d=try WarpWorkflowTests().fixture(smart:true),store=EditorStore(document:d);defer { store.renderTask?.cancel() }
    store.beginFilter(.perspectiveWarp);let model=PerspectiveWorkspace();await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready")
    model.addRectangle(PathPoint(12,10),PathPoint(24,30));model.addRectangle(PathPoint(24,10),PathPoint(36,30));model.mode = .warp
    model.beginGesture();model.move(plane:0,corner:1,to:PathPoint(26,8));model.endGesture();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    XCTAssertEqual(model.settings.planes[0].destination[1],model.settings.planes[1].destination[0]);let moved=model.settings
    model.toggleLock(plane:0,edge:0);await model.task?.value;XCTAssertEqual(model.settings.locks.count,1);model.undo();await model.task?.value;XCTAssertEqual(model.settings,moved);model.redo();await model.task?.value
    let view=NSHostingView(rootView:PerspectiveSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:880,height:680);view.layoutSubtreeIfNeeded();await model.task?.value;XCTAssertGreaterThan(view.fittingSize.width,700)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();try png.write(to:root.appendingPathComponent("artifacts/perspective-offscreen.png")) } }
    let settings=model.settings;store.filterDraft?.filter.perspective=settings;store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertNil(store.perspectiveWorkspace);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=d;try Command.applyFilter(d.layers[0].id,filter(settings)).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters!.filters[0].id;XCTAssertTrue(store.document == expected)
    store.beginSmartFilter(d.layers[0].id,filterID:expected.layers[0].smartFilters!.filters[0].id);let reopened=PerspectiveWorkspace();await reopened.prepare(document:store.document,draft:try XCTUnwrap(store.filterDraft));XCTAssertEqual(reopened.settings,settings);XCTAssertNotNil(reopened.layoutImage);reopened.close();store.cancelFilter()
    await store.undo();store.renderTask?.cancel();XCTAssertTrue(store.document == d)
    store.beginFilter(.perspectiveWarp);let cancelled=PerspectiveWorkspace();await cancelled.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancelled.change(settings);let pending=cancelled.task;cancelled.close();store.cancelFilter();await pending?.value;XCTAssertTrue(store.document == d);model.close()
  }
  @MainActor func testHTTPParityReeditNative26AndInvalidBusyStaleGuards() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,document in
      let d=try WarpWorkflowTests().fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d);service.setDocumentTransfersEnabled(true);try service.share(document)
      let program=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings())),parameters:[String:Any]=["layerID":id.uuidString,"filter":["kind":"perspectiveWarp","perspective":program]],helper=AutomationTests(),revision=service.revision(document.store)
      var expected=d;try Command.applyFilter(id,filter()).apply(to:&expected)
      let code=try await helper.edit(service,document,"filter.apply",parameters);XCTAssertEqual(code,200);expected.layers[0].smartFilters?.filters[0].id=document.store.document.layers[0].smartFilters!.filters[0].id;XCTAssertTrue(document.store.document == expected)
      let share=try XCTUnwrap(service.shares.first?.id),old=try await helper.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"25"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"26"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1) == expected)
      var stack=expected.layers[0].smartFilters!;stack.filters[0].filter.perspective?.planes[0].destination[1].x += 2;var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await helper.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edited,200);var revised=expected;try Command.smartFilters(id,stack).apply(to:&revised);XCTAssertTrue(document.store.document == revised)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(document.store.document == expected)
      let stale=try await helper.edit(service,document,"filter.apply",parameters,revision:revision);XCTAssertEqual(stale,409)
      let bad=try await helper.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"perspectiveWarp","perspective":["planes":[["source":[]]]]]]);XCTAssertEqual(bad,400)
      document.store.beginFilter(.perspectiveWarp);let busy=try await helper.edit(service,document,"filter.apply",parameters);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let undone=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undone,200);XCTAssertTrue(document.store.document == d)
      var channel=d;try Command.channel(.quickMask(true,.init())).apply(to:&channel);document.store.session=EditorSession(document:channel)
      let channelStatus=try await helper.edit(service,document,"channel.edit",["action":"filter","target":"quickMask","filter":["kind":"perspectiveWarp","perspective":program]]);XCTAssertEqual(channelStatus,422);XCTAssertTrue(document.store.document == channel)
    }
  }
}
