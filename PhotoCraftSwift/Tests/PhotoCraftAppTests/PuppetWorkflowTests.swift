import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PuppetWorkflowTests:XCTestCase {
  func settings()->PuppetSettings {
    var s=PuppetSettings();s.pins=[.init(source:PathPoint(14,12)),.init(source:PathPoint(32,12),destination:PathPoint(38,10)),.init(source:PathPoint(22,26),destination:PathPoint(24,28))];return s
  }
  func filter(_ settings:PuppetSettings?=nil)->RasterFilter { var f=RasterFilter(.puppetWarp);f.puppet=settings ?? self.settings();return f }
  func mesh()->PuppetMesh {
    let points=(0..<4).flatMap { y in (0..<5).map { x in PathPoint(Double(x)*10,Double(y)*10) } };var tris=[[Int]]()
    for y in 0..<3 { for x in 0..<4 { let a=y*5+x,b=a+1,c=a+6,d=a+5;tris += (x+y)%2 == 0 ? [[a,b,c],[a,c,d]]:[[a,b,d],[b,c,d]] } };return PuppetMesh(vertices:points,triangles:tris,spacing:10)
  }
  func testSolverMatchesOriginalRustModesRotationAndDepth() throws {
    struct Oracle:Decodable { let modes:[String:[[Double]]];let order:[Int] }
    let data=try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/Puppet/original.json")),oracle=try JSONDecoder().decode(Oracle.self,from:data)
    let pins=[PuppetPin(source:PathPoint(0,0),destination:PathPoint(3,-2),rotation:12),PuppetPin(source:PathPoint(40,0),destination:PathPoint(43,3),depth:2),PuppetPin(source:PathPoint(0,30),destination:PathPoint(-4,30),depth:-1)]
    let solver=try PuppetSolver(mesh:mesh(),pins:pins)
    for mode in PuppetSettings.Mode.allCases {
      let points=try solver.solve(pins:pins,mode:mode),expected=try XCTUnwrap(oracle.modes[mode.rawValue.capitalized])
      for (p,q) in zip(points,expected) { XCTAssertEqual(p.x,q[0],accuracy:1e-7);XCTAssertEqual(p.y,q[1],accuracy:1e-7) }
      for (index,pin) in zip([0,4,15],pins) { XCTAssertLessThan(hypot(points[index].x-pin.destination.x,points[index].y-pin.destination.y),0.02) }
    }
    XCTAssertEqual(solver.drawOrder(pins:pins),oracle.order)
  }
  func testDisconnectedComponentsStayAtRestAndIdentityIsExact() throws {
    var m=mesh();let start=m.vertices.count;m.vertices += [PathPoint(100,100),PathPoint(110,100),PathPoint(100,110)];m.triangles.append([start,start+1,start+2])
    let pins=[PuppetPin(source:PathPoint(0,0),destination:PathPoint(4,7))],solver=try PuppetSolver(mesh:m,pins:pins),points=try solver.solve(pins:pins,mode:.rigid)
    for i in 0..<start { XCTAssertEqual(points[i].x,m.vertices[i].x+4,accuracy:1e-7);XCTAssertEqual(points[i].y,m.vertices[i].y+7,accuracy:1e-7) }
    for i in start..<m.vertices.count { XCTAssertEqual(points[i].x,m.vertices[i].x,accuracy:1e-7);XCTAssertEqual(points[i].y,m.vertices[i].y,accuracy:1e-7) }
    let d=try WarpWorkflowTests().fixture(.f32);var copy=d;try Command.applyFilter(d.layers[0].id,RasterFilter(.puppetWarp)).apply(to:&copy);XCTAssertTrue(copy == d)
  }
  func testChannelTargetsAndUnverifiedDescriptorsRejectAtomically() throws {
    var d=try WarpWorkflowTests().fixture();try Command.channel(.quickMask(true,.init())).apply(to:&d);let before=d
    XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter())).apply(to:&d));XCTAssertTrue(d == before)
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"puppetWarp\"}]"))
  }
  func testCoverageDensityExpansionAndInvalidPrograms() throws {
    var s=try Surface(width:120,height:80)
    for y in 10..<70 { for x in 20..<100 { s.setPixel(x:x,y:y,.white) } }
    let few=try PuppetMesh.build(s,density:.fewer,expansion:0),more=try PuppetMesh.build(s,density:.more,expansion:0)
    XCTAssertGreaterThan(more.vertices.count,few.vertices.count)
    let shrunk=try PuppetMesh.build(s,density:.normal,expansion:-8),grown=try PuppetMesh.build(s,density:.normal,expansion:8)
    XCTAssertGreaterThan(grown.vertices.count,shrunk.vertices.count)
    XCTAssertTrue(try PuppetMesh.build(Surface(width:10,height:10),density:.normal,expansion:2).vertices.isEmpty)
    for json in ["{\"pins\":[{\"source\":{\"x\":0,\"y\":0},\"unknown\":1}]}","{\"mode\":\"invalid\"}","{\"expansion\":201}","{\"density\":false}"] { XCTAssertThrowsError(try PuppetSettings.decodeJSON(Data(json.utf8))) }
    var p=settings();p.pins.append(p.pins[0]);XCTAssertThrowsError(try p.validate());p=settings();p.pins[0].rotation = .infinity;XCTAssertThrowsError(try p.validate())
    let defaults=try PuppetSettings.decodeJSON(Data("{\"pins\":[{\"source\":{\"x\":5,\"y\":6}}]}".utf8));XCTAssertEqual(defaults.pins[0].destination,PathPoint(5,6));XCTAssertTrue(defaults.isIdentity)
  }
  func testRasterDepthsMasksHistoryAndHDRTranslation() throws {
    for depth in PixelDepth.allCases {
      var d=try WarpWorkflowTests().fixture(depth),mask=try Surface(width:24,height:20,depth:depth,fill:.white);mask.setPixel(x:8,y:8,Pixel(0.3,0.3,0.3))
      d.layers[0].mask=mask;var properties=MaskProperties();properties.enabled=false;properties.density=0.6;properties.feather=2;d.layers[0].maskProperties=properties
      if depth == .f32,case .raster(var pixels)=d.layers[0].content { pixels.setLinearPixel(x:8,y:8,Pixel(3.5,-0.1,2,1));d.layers[0].content = .raster(pixels) }
      var settings=PuppetSettings();settings.interpolation = .nearest;settings.pins=[.init(source:PathPoint(14,12),destination:PathPoint(17,14))]
      var session=EditorSession(document:d);try session.execute(.applyFilter(d.layers[0].id,filter(settings)));let result=session.document
      XCTAssertEqual(result.layers[0].maskProperties,properties);XCTAssertEqual(result.layers[0].mask?.depth,depth)
      if depth == .f32 { let image=try Renderer.composite(result);XCTAssertEqual(image.linearPixel(x:23,y:20).r,3.5,accuracy:0.0001) }
      XCTAssertNil(result.layers[0].smartFilters);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result)) == result)
      try session.undo();XCTAssertTrue(session.document == d);try session.redo();XCTAssertTrue(session.document == result)
    }
  }
  func testSmartFilterSourceNative25ReeditRasterizationAndTransforms() throws {
    var d=try WarpWorkflowTests().fixture(smart:true);let id=d.layers[0].id,source=d.layers[0].content,original=d.layers[0].smartObject
    try Command.applyFilter(id,filter()).apply(to:&d)
    XCTAssertEqual(d.layers[0].content,source);XCTAssertEqual(d.layers[0].smartObject,original);XCTAssertEqual(d.minimumArchiveVersion,25)
    for bytes in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] { XCTAssertTrue(try NativeArchive.decode(bytes) == d) }
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d,format:.psd))
    let image=try Renderer.composite(d);var raster=d;try Command.rasterize(id,Renderer.layerSurface(d.layers[0],in:d)).apply(to:&raster);XCTAssertNil(raster.layers[0].smartObject);XCTAssertEqual(try Renderer.composite(raster),image)
    let before=d.layers[0].smartFilters!.filters[0].filter.puppet!
    try Command.move(id,d.layers[0].x+4,d.layers[0].y+3).apply(to:&d)
    XCTAssertEqual(d.layers[0].smartFilters!.filters[0].filter.puppet!.pins[0].source,PathPoint(before.pins[0].source.x+4,before.pins[0].source.y+3))
    try Command.transform(id,.scale(2,2),.nearest).apply(to:&d)
    XCTAssertEqual(d.layers[0].smartFilters!.filters[0].filter.puppet!.pins[0].source.x,(before.pins[0].source.x+4)*2)
    var stack=d.layers[0].smartFilters!;stack.filters[0].filter.puppet?.pins[1].destination.x += 4;try Command.smartFilters(id,stack).apply(to:&d)
    XCTAssertEqual(d.layers[0].content,source)
    let replacement=try WarpWorkflowTests().fixture();try SmartObjectIO.replacement(in:d,layerID:id,source:replacement,preserveSize:true).apply(to:&d);XCTAssertEqual(d.layers[0].smartFilters,stack)
    var rotation=PuppetSettings();rotation.pins=[.init(source:PathPoint(3,4),rotation:20)];XCTAssertEqual(rotation.transformed(.scale(-1,1)).pins[0].rotation,-20)
  }
  func testSmartFilterOrderOpacityMaskAndWarpComposition() throws {
    let original=try WarpWorkflowTests().fixture(smart:true),id=original.layers[0].id;var d=original
    try Command.applyFilter(id,filter()).apply(to:&d);let output=try Renderer.composite(d);XCTAssertNotEqual(output,try Renderer.composite(original))
    var stack=d.layers[0].smartFilters!;stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(original))
    stack.filters[0].opacity=1;stack.mask=try Surface(width:d.width,height:d.height,fill:.black);try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(original))
    var a=original,b=original;try Command.applyFilter(id,RasterFilter(.mosaic)).apply(to:&a);try Command.applyFilter(id,filter()).apply(to:&a)
    try Command.applyFilter(id,filter()).apply(to:&b);try Command.applyFilter(id,RasterFilter(.mosaic)).apply(to:&b);XCTAssertNotEqual(try Renderer.composite(a),try Renderer.composite(b))
    var warp=WarpDefinition();warp.style = .arch;warp.bend=20
    var combined=try WarpEdit.prepare(original,layerID:id,warp:warp).result;try Command.applyFilter(id,filter()).apply(to:&combined);XCTAssertEqual(combined.layers[0].warp,warp);XCTAssertEqual(combined.layers[0].content,original.layers[0].content);_ = try Renderer.composite(combined)
  }
  @MainActor func testWorkspacePinsLocalUndoCancelAndCommit() async throws {
    let d=try WarpWorkflowTests().fixture(smart:true),store=EditorStore(document:d);defer { store.renderTask?.cancel() }
    store.beginFilter(.puppetWarp);let model=PuppetWorkspace();await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready")
    model.add(PathPoint(14,12));model.add(PathPoint(32,12));model.beginGesture();model.move(1,to:PathPoint(38,10));model.endGesture();await model.task?.value
    XCTAssertTrue(model.ready,model.error ?? "Preview not ready");XCTAssertTrue(store.document == d)
    let triangle=try XCTUnwrap(model.mesh?.triangles.first),rest=try XCTUnwrap(model.mesh?.vertices)
    let visible=PathPoint(triangle.reduce(model.origin.x*3){$0+model.deformed[$1].x}/3,triangle.reduce(model.origin.y*3){$0+model.deformed[$1].y}/3)
    let source=PathPoint(triangle.reduce(model.origin.x*3){$0+rest[$1].x}/3,triangle.reduce(model.origin.y*3){$0+rest[$1].y}/3),mapped=model.sourcePoint(for:visible)
    XCTAssertEqual(mapped.x,source.x,accuracy:1e-7);XCTAssertEqual(mapped.y,source.y,accuracy:1e-7)
    let settings=model.settings;model.undo();await model.task?.value;XCTAssertEqual(model.settings.pins[1].destination,PathPoint(32,12));model.redo();await model.task?.value;XCTAssertEqual(model.settings,settings)
    let view=NSHostingView(rootView:PuppetSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:880,height:660);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,700)
    await model.task?.value
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();try png.write(to:root.appendingPathComponent("artifacts/puppet-offscreen.png")) } }
    store.filterDraft?.filter.puppet=settings;store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=d;try Command.applyFilter(d.layers[0].id,filter(settings)).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters!.filters[0].id;XCTAssertTrue(store.document == expected)
    await store.undo();store.renderTask?.cancel();XCTAssertTrue(store.document == d)
    store.beginFilter(.puppetWarp);let cancelled=PuppetWorkspace();await cancelled.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancelled.change(settings);let pending=cancelled.task;cancelled.close();store.cancelFilter();await pending?.value;XCTAssertTrue(store.document == d)
    model.close()
  }
  @MainActor func testHTTPParityStatePersistenceAndGuards() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) { service,document in
      let d=try WarpWorkflowTests().fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d);service.setDocumentTransfersEnabled(true);try service.share(document)
      let program=try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings()))
      let parameters:[String:Any]=["layerID":id.uuidString,"filter":["kind":"puppetWarp","puppet":program]],helper=AutomationTests(),revision=service.revision(document.store)
      var expected=d;try Command.applyFilter(id,filter()).apply(to:&expected)
      let code=try await helper.edit(service,document,"filter.apply",parameters);XCTAssertEqual(code,200);expected.layers[0].smartFilters?.filters[0].id=document.store.document.layers[0].smartFilters!.filters[0].id;XCTAssertTrue(document.store.document == expected)
      let stale=try await helper.edit(service,document,"filter.apply",parameters,revision:revision);XCTAssertEqual(stale,409)
      let bad=try await helper.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"puppetWarp","puppet":["expansion":300]]]);XCTAssertEqual(bad,400)
      let share=try XCTUnwrap(service.shares.first?.id)
      let rejected=try await helper.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"24"]);XCTAssertEqual(rejected.0.statusCode,422)
      let saved=try await helper.request(service,path:"/v1/documents/\(share)/file.photato",headers:["X-Photato-Archive-Version":"25"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1) == expected)
      var stack=try XCTUnwrap(document.store.document.layers[0].smartFilters);stack.filters[0].filter.puppet?.pins[1].destination.y += 3
      var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await helper.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edited,200)
      var revised=expected;try Command.smartFilters(id,stack).apply(to:&revised);XCTAssertTrue(document.store.document == revised)
      let reeditUndo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(reeditUndo,200);XCTAssertTrue(document.store.document == expected)
      document.store.beginFilter(.puppetWarp);let busy=try await helper.edit(service,document,"filter.apply",parameters);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let undone=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undone,200);XCTAssertTrue(document.store.document == d)
      var channel=d;try Command.channel(.quickMask(true,.init())).apply(to:&channel);document.store.session=EditorSession(document:channel)
      let channelStatus=try await helper.edit(service,document,"channel.edit",["action":"filter","target":"quickMask","filter":["kind":"puppetWarp","puppet":program]]);XCTAssertEqual(channelStatus,422);XCTAssertTrue(document.store.document == channel)
      var locked=d;locked.layers[0].protectionFlags = .position;document.store.session=EditorSession(document:locked)
      let protected=try await helper.edit(service,document,"filter.apply",parameters);XCTAssertEqual(protected,422);XCTAssertTrue(document.store.document == locked)
    }
  }
}
