import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AdvancedPathWorkflowTests:XCTestCase {
  @MainActor func store()throws->EditorStore{var d=try CraftDocument(width:80,height:80);d.layers[0].content = .raster(try Surface(width:80,height:80));return EditorStore(document:d,patterns:PatternLibrary(),gradients:GradientLibrary(),actions:ActionLibrary(),shapes:ShapeLibrary())}
  @MainActor func testFreeformPreviewEscapeContinuationUndoAndArchive()async throws{
    let s=try store(),original=s.document;defer{s.renderTask?.cancel()};s.tool = .freeformPen
    s.beginPath(at:.init(10,10),tolerance:2);s.extendFreeform(to:.init(20,20));XCTAssertNotNil(s.displayedVectorPath);XCTAssertEqual(s.document,original);XCTAssertTrue(s.hasToneDraft);s.finishPath(cancelGesture:true);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginPath(at:.init(10,10),tolerance:2);s.extendFreeform(to:.init(20,15));s.extendFreeform(to:.init(40,20));s.finishFreeform();XCTAssertNil(s.error);XCTAssertEqual(s.session.undoStack.count,1)
    let path=try XCTUnwrap(s.selectedVectorPath);s.beginPath(at:.init(40,20),tolerance:2);s.extendFreeform(to:.init(60,25));s.finishFreeform();XCTAssertEqual(s.selectedVectorPath?.components.count,1);XCTAssertEqual(s.selectedVectorPath?.components.first?.knots.last?.anchor,.init(60,25))
    await s.undo();XCTAssertEqual(s.selectedVectorPath,path);await s.undo();XCTAssertEqual(s.document,original);await s.redo();XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(s.document)),s.document)
    XCTAssertEqual(WorkspaceCatalog.tool("freeformPen").shortcut,"P");XCTAssertEqual(WorkspaceCatalog.tool("curvaturePen").native,.curvaturePen)
  }
  @MainActor func testCurvatureCornersClosureDraggingAndNativeConversions()async throws{
    let s=try store();defer{s.renderTask?.cancel()};s.tool = .curvaturePen
    for p in [PathPoint(10,10),.init(50,10),.init(50,50),.init(10,50)]{s.beginPath(at:p,tolerance:2);s.endPathGesture()}
    s.beginPath(at:.init(10,50),tolerance:2,clickCount:2);XCTAssertEqual(s.selectedVectorPath?.components[0].knots[3].smooth,false)
    s.beginPath(at:.init(10,10),tolerance:2);XCTAssertEqual(s.selectedVectorPath?.components[0].closed,true)
    s.beginPath(at:.init(50,50),tolerance:2);s.dragPath(to:.init(60,60));s.endPathGesture();XCTAssertEqual(s.selectedVectorPath?.components[0].knots[2].anchor,.init(60,60))
    s.pathToSelection();s.makeWorkPath();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertNotNil(s.selectedVectorPath)
    let before=s.document;s.paintSelectedPath(stroke:false);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertNotEqual(s.document,before);await s.undo();XCTAssertEqual(s.document,before)
    s.makeVectorMask();let masked=s.document;s.tool = .freeformPen;s.beginPath(at:.init(5,5),tolerance:2);s.extendFreeform(to:.init(20,5));s.finishFreeform();XCTAssertNotEqual(s.document,masked);await s.undo();XCTAssertEqual(s.document,masked)
  }
  @MainActor func testSyntheticCanvasFreeformAndCurvatureEvents()async throws{
    let s=try store(),canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:300,height:300);defer{s.renderTask?.cancel()}
    func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double,_ count:Int=1)->NSEvent{NSEvent.mouseEvent(with:type,location:.init(x:x,y:y),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:count,pressure:1)!}
    s.tool = .freeformPen;canvas.synchronizeTool();canvas.mouseDown(with:event(.leftMouseDown,80,80));canvas.mouseDragged(with:event(.leftMouseDragged,130,140));canvas.mouseUp(with:event(.leftMouseUp,180,180));XCTAssertNil(s.error);XCTAssertEqual(s.document.paths?.count,1);XCTAssertEqual(s.session.undoStack.count,1)
    s.tool = .curvaturePen;canvas.synchronizeTool();canvas.mouseDown(with:event(.leftMouseDown,100,160));canvas.mouseUp(with:event(.leftMouseUp,100,160));XCTAssertNil(s.error);XCTAssertEqual(s.document.paths?.first?.path.components.count,2)
  }
  @MainActor func testAPISharedGeometryPaintTraceUndoSchemasAndRejections()async throws{
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),shapes:ShapeLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document)
      let points=[PathPoint(0.5,0.5),.init(2.5,0.5),.init(2.5,2.5),.init(0.5,2.5)],initial=document.store.document
      let drawn=try await helper.edit(service,document,"path.draw",["points":BrushAPI.json(points),"method":"curvature","closed":true,"corners":[0,1,2,3]]);XCTAssertEqual(drawn,200)
      let path=try XCTUnwrap(document.store.document.paths?.first);XCTAssertEqual(path.path,VectorPath(components:[try PathConstruction.curvature(.init(knots:points.map{.init($0)},closed:true))]))
      let configured=try await helper.edit(service,document,"path.configure",["tool":"freeformPen","tolerance":3,"pathID":path.id.uuidString]);XCTAssertEqual(configured,200);XCTAssertEqual(document.store.tool,.freeformPen)
      let before=document.store.document;var expected=before;let id=before.activeLayerID!;try PathPainting.command(path.path,document:before,layerID:id,brush:document.store.brush,stroke:false).apply(to:&expected)
      let painted=try await helper.edit(service,document,"path.paint",["pathID":path.id.uuidString]);XCTAssertEqual(painted,200);XCTAssertEqual(document.store.document,expected)
      let undone=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(document.store.document,before)
      let stale=try await helper.edit(service,document,"path.paint",[:],revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFreeform(at:.init(0,0),tolerance:1);let busy=try await helper.edit(service,document,"path.trace");XCTAssertEqual(busy,409);document.store.finishFreeform(cancel:true)
      let invalid=try await helper.edit(service,document,"path.draw",["points":BrushAPI.json(points),"tolerance":0]);XCTAssertEqual(invalid,400)
      let bad=try await helper.edit(service,document,"path.edit",["operation":"save","path":["typo":true]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,before)
      let selection=try await helper.edit(service,document,"path.edit",["operation":"selection","pathID":path.id.uuidString]);XCTAssertEqual(selection,200)
      let traced=try await helper.edit(service,document,"path.trace",["tolerance":0.5]);XCTAssertEqual(traced,200)
      let masked=try await helper.edit(service,document,"path.edit",["operation":"vectorMask","pathID":path.id.uuidString,"layerID":id.uuidString]);XCTAssertEqual(masked,200)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document.store.document)),document.store.document)
      for name in PathAPI.commands{XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationCommand.definitions.first{$0.name==name}!.schema))}
      XCTAssertNotNil(service.state(service.shares.first!,document:document)["paths"]);XCTAssertNotEqual(document.store.document,initial)
    }
  }
}
