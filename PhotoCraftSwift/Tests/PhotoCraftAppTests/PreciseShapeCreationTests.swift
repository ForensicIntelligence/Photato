import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class ShapeCreationGate:@unchecked Sendable {
  private let lock=NSCondition();private var started=false,released=false
  func wait()throws{lock.lock();started=true;lock.broadcast();while !released{if Task.isCancelled{lock.unlock();throw CancellationError()};_ = lock.wait(until:Date(timeIntervalSinceNow:0.01))};lock.unlock();try Task.checkCancellation()}
  func release(){lock.lock();released=true;lock.broadcast();lock.unlock()}
  var ready:Bool{lock.lock();defer{lock.unlock()};return started}
}
final class PreciseShapeCreationTests:XCTestCase {
  override func setUp()async throws{try await super.setUp();await MainActor.run{_=NSApplication.shared;_=CraftDocumentController(workspaces:WorkspaceLibrary())}}
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try CraftDocument(width:64,height:64,depth:depth);d.layers[0].locked=false;d.layers[0].content = .raster(try Surface(width:64,height:64,depth:depth));return d}
  @MainActor func store(_ d:CraftDocument)throws->EditorStore{try ShapeWorkflowTests().store(d)}
  @MainActor func open(_ s:EditorStore,kind:ShapeGeometry.Kind = .rectangle,point:CGPoint = .init(x:20,y:20),center:Bool=false)throws->ShapeCreationDraft {
    s.tool=kind == .rectangle ? .rectangle:.ellipse
    s.beginShapeCreation(.init(original:s.document,start:point,definition:try s.currentShape(),mode:s.shapeMode,target:s.activeLayer?.id,operation:s.shapeOperation,end:point,center:center))
    return try XCTUnwrap(s.shapeCreationDraft)
  }
  @MainActor private func wait(_ gate:ShapeCreationGate)async throws{for _ in 0..<1000{if gate.ready{return};try await Task.sleep(for:.milliseconds(2))};XCTFail("Creation worker did not start");throw CancellationError()}
  @MainActor func testNoMovementClicksOpenDialogsForAllModifiersAndDragRemainsCaptured()async throws {
    let d=try fixture(),s=try store(d),canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:300,height:300);defer{s.cancelShapeCreation();s.renderTask?.cancel()}
    func event(_ type:NSEvent.EventType,_ p:CGPoint,_ flags:NSEvent.ModifierFlags=[])->NSEvent{NSEvent.mouseEvent(with:type,location:p,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!}
    let bits:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for tool:EditorTool in [.rectangle,.ellipse]{s.tool=tool
      for raw in 0..<16{
        let flags=bits.enumerated().reduce(NSEvent.ModifierFlags()){raw&(1<<$1.offset) != 0 ? $0.union($1.element):$0},p=CGPoint(x:150,y:150)
        let down=event(.leftMouseDown,p,flags),point=canvas.docPoint(down)
        canvas.mouseDown(with:down);XCTAssertNotNil(s.shapeGesture)
        canvas.mouseUp(with:event(.leftMouseUp,p))
        let draft=try XCTUnwrap(s.shapeCreationDraft);XCTAssertEqual(draft.point,point);XCTAssertEqual(draft.fromCenter,flags.contains(.option));XCTAssertEqual(draft.definition.components[0].geometry.kind,tool.shapeKind)
        XCTAssertEqual(tool.cursor(modifiers:flags),.symbol("plus",ToolCursor.geometry(flags)))
        XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertTrue(s.hasToneDraft);XCTAssertFalse(s.canDrawShapes)
        s.cancelShapeCreation();XCTAssertFalse(s.hasToneDraft)
      }
    }
    s.tool = .rectangle;canvas.mouseDown(with:event(.leftMouseDown,.init(x:130,y:130)));canvas.mouseDragged(with:event(.leftMouseDragged,.init(x:160,y:170),[.shift,.option]));canvas.mouseUp(with:event(.leftMouseUp,.init(x:160,y:170),[.shift,.option]));await s.geometryTask?.value
    XCTAssertNil(s.shapeCreationDraft);XCTAssertNil(s.error);XCTAssertEqual(s.session.undoStack.count,1)
    await s.undo();XCTAssertEqual(s.document,d)
  }
  @MainActor func testLiteralPlacementAllDepthsModesUndoRedoAndArchive()async throws {
    for depth in PixelDepth.allCases{for mode in ShapeOutputMode.allCases{for kind:ShapeGeometry.Kind in [.rectangle,.ellipse]{
      let d=try fixture(depth),s=try store(d);defer{s.cancelShapeCreation();s.renderTask?.cancel()};s.shapeMode=mode
      let draft=try open(s,kind:kind,center:true);draft.definition.components[0].geometry.width=10;draft.definition.components[0].geometry.height=8;draft.definition.fill = .init(color:Pixel(1,0,0))
      XCTAssertEqual(try draft.request.placement(),.translation(15,16));s.commitShapeCreation(draft);await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertNil(s.shapeCreationDraft);XCTAssertEqual(s.session.undoStack.count,1)
      if mode == .shape{XCTAssertEqual(s.activeLayer?.shape?.editableDefinition.components[0].geometry.width,10);XCTAssertEqual(try s.activeLayer?.shapeTransform(),.translation(15,16))}
      if mode == .path{XCTAssertNotNil(s.document.paths?.first)}else{let p=try Renderer.composite(s.document).pixel(x:20,y:20);XCTAssertEqual(p,Pixel(1,0,0))}
      let after=s.document;XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(after)),after)
      await s.undo();XCTAssertEqual(s.document,d);await s.redo();XCTAssertEqual(s.document,after)
    }}}
  }
  @MainActor func testLinkedRadiiValidationCancelAndBoundedOffscreenSheet()throws {
    let d=try fixture(),s=try store(d);defer{s.cancelShapeCreation();s.renderTask?.cancel()};let draft=try open(s)
    draft.setRadius(7,corner:2);XCTAssertEqual(draft.definition.components[0].geometry.radii,[7,7,7,7])
    draft.setLinkedCorners(false);draft.setRadius(2,corner:1);XCTAssertEqual(draft.definition.components[0].geometry.radii,[7,2,7,7]);draft.setLinkedCorners(true);XCTAssertEqual(draft.definition.components[0].geometry.radii,[7,7,7,7])
    draft.definition.components[0].geometry.width = -1;XCTAssertFalse(draft.valid);s.commitShapeCreation(draft);XCTAssertTrue(s.shapeCreationDraft === draft);XCTAssertEqual(s.document,d)
    draft.definition.components[0].geometry.width=10
    let host=NSHostingView(rootView:ShapeCreationSheet(store:s,draft:draft));host.appearance=NSAppearance(named:.darkAqua);host.frame = .init(x:0,y:0,width:360,height:460);host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.height,460)
    if let base=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:base).appendingPathComponent("435-create-rectangle-offscreen.png"))}
    s.cancelShapeCreation();XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
    XCTAssertEqual(s.shapeTemplate.components[0].geometry.radii,[0,0,0,0])
  }
  @MainActor func testCapturedPatternAndRotatedShapeCombinationUseExistingMaterialAndOneUndo()async throws {
    var d=try fixture();let base=ShapeDefinition(geometry:.init(kind:.rectangle,width:20,height:20),fill:.init(color:Pixel(0,0,1)))
    try Command.shape(.create("Base",base,.translation(10,12) * .rotation(0.2))).apply(to:&d)
    let s=try store(d);defer{s.cancelShapeCreation();s.renderTask?.cancel()};s.shapeOperation = .subtract
    let draft=try open(s,point:.init(x:18,y:19),center:true);draft.definition.components[0].geometry.width=6;draft.definition.components[0].geometry.height=4
    let request=draft.request;var expected=d;try request.command(in:d,patterns:[]).apply(to:&expected)
    s.commitShapeCreation(draft);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.session.undoStack.count,1)
    let part=try XCTUnwrap(s.activeLayer?.shape?.editableDefinition.components.last);XCTAssertEqual(part.operation,.subtract)
    XCTAssertEqual(part.transform,try XCTUnwrap(d.layers.first{$0.id==d.activeLayerID}).shapeTransform().inverted() * .translation(15,17))
    await s.undo();XCTAssertEqual(s.document,d)
    s.shapeOperation=nil;let pattern=try XCTUnwrap(s.patterns.selected);s.shapeTemplate.fill.kind = .pattern;s.shapeTemplate.fill.pattern = .init(patternID:pattern.id)
    let painted=try open(s);painted.definition.components[0].geometry.width=4;painted.definition.components[0].geometry.height=4
    XCTAssertEqual(painted.patterns,[pattern]);s.commitShapeCreation(painted);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.pattern(pattern.id),pattern)
    XCTAssertEqual(s.session.undoStack.count,1);await s.undo();XCTAssertEqual(s.document,d)
  }
  @MainActor func testSourceSessionLifecycleSettingsAndCancellationRejectStaleWork()async throws {
    for variant in ["document","session","lifecycle","tool","template","settings","cancel"]{
      let d=try fixture(),s=try store(d),gate=ShapeCreationGate(),settings=ColorSettingsStore(),controller=CraftDocumentController(workspaces:WorkspaceLibrary(),colorSettings:settings);s.documentController=controller;defer{gate.release();s.cancelShapeCreation();s.renderTask?.cancel();withExtendedLifetime(controller){}}
      let draft=try open(s);draft.definition.components[0].geometry.width=4;draft.definition.components[0].geometry.height=4
      s.shapeCreationPreparation={source,request,resources in try gate.wait();return try PreparedEdit(command:request.command(in:source,patterns:resources),document:source)}
      s.commitShapeCreation(draft);try await wait(gate)
      switch variant{
      case "document":var changed=s.document;changed.name="Changed";s.session=EditorSession(document:changed)
      case "session":s.session=EditorSession(document:d)
      case "lifecycle":s.layerPanelGeneration=UUID()
      case "tool":s.tool = .move
      case "template":s.shapeTemplate.components[0].geometry.width=22
      case "settings":var next=settings.value;next.rgbPolicy = .convertToWorking;try settings.commit(next,revision:settings.revision)
      default:s.geometryTask?.cancel()
      }
      let current=s.document;gate.release();await s.geometryTask?.value;XCTAssertEqual(s.document,current,variant);XCTAssertTrue(s.session.undoStack.isEmpty,variant)
    }
    let s=try store(fixture());defer{s.cancelShapeCreation();s.renderTask?.cancel()};let draft=try open(s);s.session=EditorSession(document:s.document);s.commitShapeCreation(draft);XCTAssertNotNil(draft.error);XCTAssertTrue(s.shapeCreationDraft === draft)
  }
  @MainActor func testNativeAndHTTPPrecisePlacementMatchAcrossModesWithoutChangingOldTransformClients()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let d=try fixture();shared.store.session=EditorSession(document:d);try service.share(shared)
      for mode in ShapeOutputMode.allCases{
        let native=try store(d);defer{native.cancelShapeCreation();native.renderTask?.cancel()};native.shapeMode=mode
        let draft=try open(native,center:true);draft.definition.components[0].geometry.width=10;draft.definition.components[0].geometry.height=8;draft.setRadius(2,corner:0);draft.definition.fill = .init(color:Pixel(1,0,0))
        let definition=draft.definition;native.commitShapeCreation(draft);await native.geometryTask?.value;XCTAssertNil(native.error)
        let status=try await helper.edit(service,shared,"shape.edit",["operation":"create","definition":BrushAPI.json(definition),"name":draft.request.name,"mode":mode.rawValue,"point":["x":20,"y":20],"fromCenter":true]);XCTAssertEqual(status,200)
        if mode == .shape{XCTAssertEqual(shared.store.activeLayer?.shape?.editableDefinition,definition);XCTAssertEqual(try shared.store.activeLayer?.shapeTransform(),.translation(15,16))}
        if mode == .path{XCTAssertEqual(shared.store.document.paths?.first?.path,native.document.paths?.first?.path)}
        else{XCTAssertEqual(try DocumentIO.encode(shared.store.document,format:.png),try DocumentIO.encode(native.document,format:.png))}
        var material=shared.store.document
        if mode == .shape{let id=try XCTUnwrap(material.activeLayerID),nativeID=try XCTUnwrap(native.document.activeLayerID);material.layers[try XCTUnwrap(material.layers.firstIndex{$0.id==id})].id=nativeID;material.activeLayerID=nativeID}
        if mode == .path{material.paths?[0].id=try XCTUnwrap(native.document.paths?.first?.id)}
        XCTAssertEqual(material,native.document)
        let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
      }
      let definition=ShapeDefinition(geometry:.init(kind:.rectangle,width:4,height:4))
      let old=try await helper.edit(service,shared,"shape.edit",["operation":"create","definition":BrushAPI.json(definition),"transform":BrushAPI.json(Transform2D.translation(3,5))]);XCTAssertEqual(old,200);XCTAssertEqual(try shared.store.activeLayer?.shapeTransform(),.translation(3,5))
    }
  }
  @MainActor func testHTTPStrictPointRulesBusyStaleAndDiscoverableDraftSchema()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let d=try fixture();shared.store.session=EditorSession(document:d);try service.share(shared)
      let def=ShapeDefinition(geometry:.init(kind:.rectangle,width:4,height:4)),base:[String:Any]=["operation":"create","definition":BrushAPI.json(def),"point":["x":20,"y":20]]
      let invalids:[[String:Any]]=[["point":NSNull()],["point":["x":1]],["point":["x":1,"y":2,"z":3]],["point":["x":1_000_001,"y":0]],["fromCenter":"yes"],["transform":BrushAPI.json(Transform2D.identity)],["mode":"pixels","combine":"subtract"],["combine":"notAnOperation"]]
      for bad in invalids{let status=try await helper.edit(service,shared,"shape.edit",base.merging(bad){_,b in b});XCTAssertEqual(status,400);XCTAssertEqual(shared.store.document,d);XCTAssertTrue(shared.store.session.undoStack.isEmpty)}
      var noPoint=base;noPoint.removeValue(forKey:"point");noPoint["fromCenter"]=true;let missing=try await helper.edit(service,shared,"shape.edit",noPoint);XCTAssertEqual(missing,400)
      let draft=try open(shared.store);let state=try XCTUnwrap(shared.store.shapeState["creationDraft"] as? [String:Any]);XCTAssertEqual(state["kind"] as? String,"rectangle");XCTAssertEqual(state["fromCenter"] as? Bool,false)
      XCTAssertTrue(JSONSerialization.isValidJSONObject(ShapeAPI.capabilities));XCTAssertTrue(JSONSerialization.isValidJSONObject(ShapeAPI.stateSchema));XCTAssertTrue(JSONSerialization.isValidJSONObject(shared.store.shapeState))
      let busy=try await helper.edit(service,shared,"shape.edit",base);XCTAssertEqual(busy,409);shared.store.cancelShapeCreation();XCTAssertEqual(shared.store.document,d);XCTAssertNil(shared.store.shapeState["creationDraft"] as? [String:Any]);XCTAssertNotNil(draft)
      let stale=try await helper.edit(service,shared,"shape.edit",base,revision:"stale");XCTAssertEqual(stale,409)
    }
  }
  func testRequestPlacementValidationAndSinglePrimitiveRules()throws {
    let definition=ShapeDefinition(geometry:.init(kind:.rectangle,width:12,height:8))
    func request(_ definition:ShapeDefinition,_ point:CGPoint,_ center:Bool)->ShapeCreationRequest{.init(definition:definition,point:point,fromCenter:center,mode:.shape,target:nil,combine:nil,name:"Rectangle")}
    XCTAssertEqual(try request(definition,.init(x:-2.5,y:7.25),false).placement(),.translation(-2.5,7.25));XCTAssertEqual(try request(definition,.init(x:-2.5,y:7.25),true).placement(),.translation(-8.5,3.25))
    for p:CGPoint in [.init(x:Double.infinity,y:0),.init(x:1_000_001,y:0)]{XCTAssertThrowsError(try request(definition,p,true).placement())}
    var transformed=definition;transformed.components[0].transform = .scale(2,2);XCTAssertThrowsError(try request(transformed,.zero,true).placement())
    transformed=definition;transformed.components.append(.init(geometry:.init()));XCTAssertThrowsError(try request(transformed,.zero,false).placement())
    transformed=definition;transformed.components[0].pathOverride=try ShapeGeometry().path();XCTAssertThrowsError(try request(transformed,.zero,false).placement())
  }
}
