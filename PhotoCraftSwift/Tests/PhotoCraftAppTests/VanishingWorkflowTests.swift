import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VanishingWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d=try CraftDocument(width:64,height:48,depth:depth),s=try Surface(width:64,height:48,depth:depth)
    for y in 0..<48 { for x in 0..<64 { s.setPixel(x:x,y:y,Pixel(Float(x)/64,Float(y)/48,0.4,(x+y)%7==0 ? 0.5:1)) } };d.layers[0].content = .raster(s);return d
  }
  func program()->VanishingProgram {
    var p=VanishingProgram();p.settings.planes=[.init(corners:[.init(4,4),.init(60,4),.init(60,44),.init(4,44)])]
    var b=VanishingOperation(.brush);b.points=[.init(18,20),.init(45,28)];b.color=Pixel(1,0,0);b.diameter=8;p.operations=[b];return p
  }
  @MainActor func testNativePlanesPaintingPasteLocalHistoryCommitReopenCancel() async throws {
    let d=try fixture(),store=EditorStore(document:d,actions:ActionLibrary());defer { store.renderTask?.cancel();store.cancelVanishingPoint() }
    store.beginVanishingPoint();let model=try XCTUnwrap(store.vanishingWorkspace);await model.prepare();XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertTrue(store.hasToneDraft)
    for p in program().settings.planes[0].corners { model.addPoint(p) };await model.task?.value;XCTAssertEqual(model.program.settings.planes.count,1)
    model.beginGesture();model.moveCorner(0,0,to:.init(5,5));model.moveCorner(0,0,to:.init(6,5));model.endGesture();await model.task?.value
    model.undo();await model.task?.value;XCTAssertEqual(model.program.settings.planes[0].corners[0],.init(4,4))
    model.tool = .brush;model.color=Pixel(1,0,0);model.diameter=8;model.stroke([.init(18,20),.init(45,28)]);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Failed brush")
    let painted=model.program;model.undo();await model.task?.value;XCTAssertTrue(model.program.operations.isEmpty);model.redo();await model.task?.value;XCTAssertEqual(model.program,painted)
    let patch=try Surface(width:8,height:6,fill:Pixel(0,1,0));model.paste(patch);await model.task?.value;model.beginGesture();model.movePaste(to:.init(35,20));model.endGesture();await model.task?.value
    XCTAssertEqual(model.program.operations.count,2);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState));XCTAssertEqual(store.document,d)
    let expected=try VanishingEdit.prepare(d,layerID:d.layers[0].id,program:model.program,sample:Renderer.composite(d)).result
    store.commitVanishingPoint();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    store.beginVanishingPoint();let reopened=try XCTUnwrap(store.vanishingWorkspace);await reopened.prepare();XCTAssertEqual(reopened.program.settings,expected.vanishingPoint);XCTAssertTrue(reopened.program.operations.isEmpty)
    reopened.tool = .brush;reopened.stroke([.init(20,20)]);let pending=reopened.task;store.cancelVanishingPoint();await pending?.value;XCTAssertEqual(store.document,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,d)
  }
  @MainActor func testRelatedPlanesCloneSourceAndClipboardSnapshot() async throws {
    let d=try fixture(),model=VanishingWorkspace(document:d,layerID:d.layers[0].id);defer { model.close() };await model.prepare()
    var p=program();p.settings.planes=[.init(corners:[.init(120,120),.init(280,120),.init(360,280),.init(40,280)])];p.operations=[];model.change(p);await model.task?.value
    // Use the source camera's original800×600 canvas for a deterministic perpendicular plane.
    let large=try CraftDocument(width:800,height:600),linked=VanishingWorkspace(document:large,layerID:large.layers[0].id);defer { linked.close() };linked.change(p);linked.tear(.top)
    XCTAssertEqual(linked.program.settings.planes.count,2);XCTAssertEqual(linked.program.settings.planes[1].parent,0)
    linked.removePlane();XCTAssertEqual(linked.program.settings.planes.count,1)
    model.change(program());await model.task?.value;model.tool = .stamp;model.setSource(.init(10,10));model.diameter=4;model.stroke([.init(40,20)]);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Failed clone")
    model.stroke([.init(42,20)]);await model.task?.value;XCTAssertEqual(try XCTUnwrap(model.program.operations.last?.sourcePoint).x,12,accuracy:1e-9);XCTAssertEqual(try XCTUnwrap(model.program.operations.last?.sourcePoint).y,10,accuracy:1e-9)
    let pixels=try Surface(width:6,height:4,fill:Pixel(0,0,1)),content=try ClipboardContent.pixels(pixels)
    await model.pasteClipboard(.native(try content.encoded()));await model.task?.value;XCTAssertEqual(model.program.operations.last?.source?.width,6)
  }
  func testPlacedLayerAlphaLocksPersistenceAndExplicitActionBoundary() throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);d.layers[0].affine = .scale(0.8,0.8);d.layers[0].x=4;d.layers[0].y=3;d.layers[0].protection=[.transparency]
      let id=d.layers[0].id,edit=try VanishingEdit.prepare(d,layerID:id,program:program(),sample:Renderer.composite(d))
      XCTAssertEqual(edit.result.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
      guard case .raster(let before)=d.layers[0].content,case .raster(let after)=edit.result.layers[0].content else { return XCTFail() }
      XCTAssertNotEqual(before,after);for y in 0..<48 { for x in 0..<64 { XCTAssertEqual(after.pixel(x:x,y:y).a,before.pixel(x:x,y:y).a) } }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)),edit.result)
      XCTAssertThrowsError(try DocumentIO.encode(edit.result,format:.psd));XCTAssertNotNil(DocumentIO.persistenceIssue(edit.result,format:.png))
      XCTAssertNotNil(ActionOperation(recording:.vanishingPoint(edit),in:d).unsupportedReason)
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"vanishingPoint\"}]"))
    }
  }
  @MainActor func testHTTPMatchesNativeAllOperationsArchive32AndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      let d=try self.fixture(),id=d.layers[0].id;document.store.session=EditorSession(document:d);try service.share(document);service.setDocumentTransfersEnabled(true)
      let settings=self.program().settings.apiValue
      let operations:[[String:Any]]=[
        ["kind":"brush","points":[["x":18,"y":20],["x":45,"y":28]],"color":["r":1,"g":0,"b":0,"a":1],"diameter":8],
        ["kind":"clone","sourcePoint":["x":12,"y":12],"points":[["x":40,"y":30]],"diameter":4],
        ["kind":"paste","sourceLayerID":id.uuidString,"at":["x":0.2,"y":0.2],"width":0.25,"angle":10]]
      let parameters:[String:Any]=["layerID":id.uuidString,"settings":settings,"operations":operations]
      var p=self.program(),clone=VanishingOperation(.clone),paste=VanishingOperation(.paste);clone.sourcePoint = .init(12,12);clone.points=[.init(40,30)];clone.diameter=4
      guard case .raster(let source)=d.layers[0].content else { return XCTFail() };paste.source=source;paste.at = .init(0.2,0.2);paste.width=0.25;paste.angle=10;p.operations += [clone,paste]
      let expected=try VanishingEdit.prepare(d,layerID:id,program:p,sample:Renderer.composite(d)).result
      let status=try await helper.edit(service,document,"filter.vanishingPoint",parameters);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
      let share=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(share)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"31"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"32"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),expected)
      let stale=try await helper.edit(service,document,"filter.vanishingPoint",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginVanishingPoint();let busy=try await helper.edit(service,document,"filter.vanishingPoint",parameters);XCTAssertEqual(busy,409);document.store.cancelVanishingPoint()
      for bad:[String:Any] in [["layerID":id.uuidString,"settings":["planes":[],"unknown":1]],["layerID":id.uuidString,"operations":[["kind":"brush","points":[["x":true,"y":1]]]]],["layerID":id.uuidString,"operations":[["kind":"brush","points":[["x":2,"y":3]],"sourceLayerID":id.uuidString]]],["layerID":id.uuidString,"newLayer":1],["layerID":id.uuidString,"operations":[["kind":"brush","points":[["x":20,"y":20]],"color":["r":2,"g":0,"b":0,"a":1]]]]] {
        let code=try await helper.edit(service,document,"filter.vanishingPoint",bad);XCTAssertEqual(code,400)
      }
      XCTAssertEqual(document.store.document,expected);_=try await helper.edit(service,document,"history.undo");XCTAssertEqual(document.store.document,d)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:VanishingSettings.apiCapabilities))
    }
  }
  @MainActor func testFactoryMenuAndOffscreenWorkspace() async throws {
    try PhotoshopMenuTests().withMenus { app,menu in
      let item=try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first{$0.identifier?.rawValue=="Filter > Vanishing Point…"});XCTAssertEqual(item.action,#selector(AppDelegate.vanishingPoint));XCTAssertEqual(item.keyEquivalent,"v");XCTAssertEqual(item.keyEquivalentModifierMask,[.option,.command]);XCTAssertFalse(app.validateMenuItem(item))
    }
    let d=try fixture(),store=EditorStore(document:d),model=VanishingWorkspace(document:d,layerID:d.layers[0].id);defer { model.close();store.renderTask?.cancel() };model.change(program());await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
    let view=NSHostingView(rootView:VanishingSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:980,height:740);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,900)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();let folder=root.appendingPathComponent("artifacts/vanishing-point-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(UUID().uuidString+".png")) } }
  }
}
