import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class MagneticGate:@unchecked Sendable {
  let condition=NSCondition();var released=false
  func wait(){condition.lock();while !released{condition.wait()};condition.unlock()}
  func release(){condition.lock();released=true;condition.broadcast();condition.unlock()}
}
final class MagneticLassoWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try CraftDocument(width:32,height:24,depth:depth);d.layers[0].content = .raster(try Surface(width:32,height:24,depth:depth,fill:.white));return d}
  var points:[SelectionPoint] {[.init(4,4),.init(20,4),.init(20,18),.init(4,18)]}
  var events:[MagneticLassoEvent] {points.map{.init(.anchor,point:$0)}}
  @MainActor func begin(_ store:EditorStore)throws->MagneticLassoDraft {store.beginMagneticLasso(at:points[0],modifiers:[],feedback:{});let d=try XCTUnwrap(store.magneticDraft);for p in points.dropFirst(){d.append(.init(.anchor,point:p))};return d}
  @MainActor func key(_ code:UInt16,_ text:String="",_ flags:NSEvent.ModifierFlags=[] )throws->NSEvent {try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:1,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))}
  @MainActor func testNativeCanvasWorkflowHistoryAndFactoryToolCycle()async throws {
    let s=EditorStore(document:try fixture(),brushes:BrushLibrary());defer{s.cancelMagneticLasso();s.renderTask?.cancel()};s.chooseTool(WorkspaceCatalog.tool("magneticLasso"));XCTAssertEqual(s.tool,.magneticLasso);XCTAssertNil(s.unavailableToolID)
    let canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:480,height:360);s.updateViewport(size:canvas.frame.size,backingScale:1);s.setZoom(10,center:true)
    for p in points {let q=canvas.convert(canvas.viewPoint(CGPoint(x:p.x,y:p.y)),to:nil);let event=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:q,modifierFlags:[],timestamp:1,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:0));canvas.mouseDown(with:event);let up=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseUp,location:q,modifierFlags:[],timestamp:1.1,windowNumber:0,context:nil,eventNumber:2,clickCount:1,pressure:0));canvas.mouseUp(with:up)}
    let draft=try XCTUnwrap(s.magneticDraft);await draft.settle();XCTAssertEqual(draft.trace.anchors.count,4);XCTAssertTrue(s.session.undoStack.isEmpty)
    try s.session.startActionRecording(name:"Magnetic");canvas.keyDown(with:try key(36,"\r",.option));await draft.commitTask?.value
    XCTAssertNil(draft.error);XCTAssertNil(s.magneticDraft);XCTAssertEqual(s.session.undoStack.last?.label,"Magnetic Lasso");XCTAssertEqual(s.document.selectionMask?.bounds,.init(x:4,y:4,width:16,height:14))
    var replay=draft.original;try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==s.document);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==draft.original)
    s.chooseTool(WorkspaceCatalog.tool("lasso"));XCTAssertTrue(s.chooseShortcut("l",cycle:true));XCTAssertEqual(s.tool,.polygonLasso);XCTAssertTrue(s.chooseShortcut("l",cycle:true));XCTAssertEqual(s.tool,.magneticLasso)
  }
  @MainActor func testCancelToolReadCloseAndStaleSource()async throws {
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.cancelMagneticLasso();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()};let original=s.document
    let cancelled=try begin(s);await cancelled.settle();s.cancelMagneticLasso();XCTAssertTrue(cancelled.closed);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let changed=try begin(s);s.tool = .magneticLasso;s.tool = .move;await changed.settle();XCTAssertNil(s.magneticDraft)
    let reading=try begin(s);try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);await reading.settle();XCTAssertTrue(reading.closed);XCTAssertNil(s.magneticDraft)
    let stale=try begin(s);await stale.settle();try s.executeEditorCommand(.renameLayer(original.layers[0].id,"External"));s.finishMagneticLasso(straight:true);await stale.commitTask?.value;XCTAssertNotNil(stale.error);XCTAssertNil(s.document.selection);s.cancelMagneticLasso()
    let closing=try begin(s);doc.close();await closing.settle();XCTAssertTrue(closing.closed);XCTAssertNil(s.magneticDraft)
  }
  func testDepthProfileLockedCompositeAnd32BitAvailability()throws {
    for depth in [PixelDepth.u8,.u16] {var original=try fixture(depth);original.layers[0].locked=true;original.workingICC=try XCTUnwrap(CGColorSpace(name:CGColorSpace.displayP3)?.copyICCData() as Data?);var output=original;try MagneticLassoInput.prepare(original).command(events:events,settings:.init(),mode:.replace,straight:true).apply(to:&output);XCTAssertEqual(output.layers,original.layers);XCTAssertEqual(output.depth,depth);XCTAssertEqual(output.workingICC,original.workingICC)}
    XCTAssertThrowsError(try MagneticLassoInput.prepare(fixture(.f32)))
  }
  @MainActor func testAPIReplayMatchesNativeEveryModeAndConfiguration()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      let configured=try await h.edit(service,doc,"selection.magnetic.configure",["settings":["width":20,"frequency":80,"feather":2]]);XCTAssertEqual(configured,200);XCTAssertEqual(s.nativeMagneticSettings.width,20);XCTAssertEqual(s.selectionFeather,2);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
      for mode in SelectionMode.allCases {s.session=EditorSession(document:original);let settings=MagneticLassoSettings();let params:[String:Any]=["events":BrushAPI.json(self.events),"settings":BrushAPI.json(settings),"mode":SelectionToolAPI.modeName(mode),"straightClose":true]
        let status=try await h.edit(service,doc,"selection.magneticLasso",params);XCTAssertEqual(status,200)
        var expected=original;try MagneticLassoInput.prepare(original).command(events:self.events,settings:settings,mode:mode,straight:true).apply(to:&expected);XCTAssertTrue(s.document==expected)
        if expected != original {XCTAssertEqual(s.session.undoStack.count,1);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)}
      }
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.magneticLassoState));XCTAssertNoThrow(try BrushAPI.merge(value,schema:MagneticLassoAPI.stateSchema))
    }
  }
  @MainActor func testInvalidBusyStaleAndDeterministicRevocation()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      let base:[String:Any]=["events":BrushAPI.json(self.events)]
      for extra:[String:Any] in [["settings":["width":0]],["settings":["frequency":101]],["settings":["bad":1]],["events":[["kind":"move"]]],["events":[["kind":"remove","point":["x":1,"y":1]]]],["mode":"bad"],["straightClose":1]] {let code=try await h.edit(service,doc,"selection.magneticLasso",base.merging(extra){_,b in b});XCTAssertEqual(code,400);XCTAssertTrue(s.document==original)}
      let stale=try await h.edit(service,doc,"selection.magneticLasso",base,revision:"old");XCTAssertEqual(stale,409)
      let draft=try self.begin(s);let busy=try await h.edit(service,doc,"selection.magneticLasso",base);XCTAssertEqual(busy,409);s.cancelMagneticLasso();await draft.settle()
      let gate=MagneticGate();s.magneticPreparation={document in gate.wait();try Task.checkCancellation();return try MagneticLassoInput.prepare(document)}
      let request=Task {try await h.edit(service,doc,"selection.magneticLasso",base)};let until=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<until{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();let status=try await request.value;XCTAssertEqual(status,409);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testAll16CursorCombinationsCapturedModeAndWidthDeleteCancel()async throws {
    let s=EditorStore(document:try fixture(),brushes:BrushLibrary());defer{s.cancelMagneticLasso();s.renderTask?.cancel()};s.tool = .magneticLasso
    let canvas=CraftCanvas(store:s),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for n in 0..<16 {let f=flags.enumerated().reduce(NSEvent.ModifierFlags()){r,v in n & (1<<v.offset) != 0 ? r.union(v.element):r};let mode=s.selectionMode(modifiers:f)
      XCTAssertEqual(EditorTool.magneticLasso.cursor(modifiers:f,selection:mode),ToolCursor.selection("lasso",mode))
      s.beginMagneticLasso(at:points[0],modifiers:f,feedback:{});let draft=try XCTUnwrap(s.magneticDraft);XCTAssertEqual(draft.mode,mode)
      canvas.updateCursorModifiers(f);let expected=ToolCursor.magnetic(modifiers:f,mode:mode,active:true,alternateReady:draft.alternateReady);XCTAssertEqual(canvas.toolCursor,expected)
      canvas.updateCursorModifiers([]);XCTAssertEqual(draft.mode,mode);canvas.updateCursorModifiers(.option);XCTAssertEqual(canvas.toolCursor,.selection("pencil.tip",mode));s.cancelMagneticLasso()
    }
    let draft=try begin(s);await draft.settle();canvas.keyDown(with:try key(30,"]"));await draft.settle();XCTAssertEqual(draft.trace.settings.width,11);canvas.keyDown(with:try key(51));await draft.settle();XCTAssertEqual(draft.trace.anchors.count,3)
    canvas.keyDown(with:try key(53));XCTAssertNil(s.magneticDraft);canvas.updateCursorModifiers(.capsLock);XCTAssertTrue(canvas.magneticPrecision);XCTAssertEqual(canvas.toolCursor,.crosshair)
  }
}
