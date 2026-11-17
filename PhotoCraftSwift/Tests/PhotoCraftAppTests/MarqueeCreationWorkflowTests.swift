import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MarqueeCreationWorkflowTests: XCTestCase {
  override func setUp() async throws {
    try await super.setUp()
    await MainActor.run { _ = PhotatoApp.makeDelegate(isolatedSession: true); _ = NSApplication.shared }
  }
  @MainActor private func fixture(_ tool: EditorTool = .marquee) async throws -> (EditorStore, CraftCanvas, NSWindow) {
    let (s,c,w) = try await SelectionInteractionTests().fixture()
    s.chooseTool(WorkspaceCatalog.tool(tool == .ellipticalMarquee ? "ellipticalMarquee" : tool == .polygonLasso ? "polygonLasso" : tool == .rowMarquee ? "rowMarquee" : tool == .columnMarquee ? "columnMarquee" : "marquee"))
    c.synchronizeTool();s.selectionAntiAlias=false;s.selectionFeather=0
    return (s,c,w)
  }
  @MainActor private func mouse(_ kind: NSEvent.EventType, _ x: Double, _ y: Double,
    _ c: CraftCanvas, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try SelectionInteractionTests().mouse(kind,.init(x:x,y:y),c,flags:flags)
  }
  @MainActor private func key(_ code: UInt16, up: Bool = false,
    flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    let text=code==49 ? " " : code==53 ? "\u{1b}" : code==36 ? "\r" : ""
    return try XCTUnwrap(NSEvent.keyEvent(with:up ? .keyUp:.keyDown,location:.zero,modifierFlags:flags,
      timestamp:1,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code))
  }
  private func flags(_ bits: Int) -> NSEvent.ModifierFlags {
    let values:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    return values.enumerated().reduce(NSEvent.ModifierFlags()) {
      bits & (1 << $1.offset)==0 ? $0 : $0.union($1.element)
    }
  }
  @MainActor private func close(_ s:EditorStore,_ c:CraftCanvas,_ w:NSWindow) {
    SelectionInteractionTests().close(s,c,w)
  }
  @MainActor func testBothMarqueesAllSixteenCapturedModesRepositionResizeAndUndo() async throws {
    for tool:EditorTool in [.marquee,.ellipticalMarquee] {for bits in 0..<16 {
      let (s,c,w)=try await fixture(tool);defer{close(s,c,w)}
      let original=s.document,pan=s.pan,f=flags(bits)
      let mode:SelectionMode=f.contains([.shift,.option]) ? .intersect:f.contains(.shift) ? .add:f.contains(.option) ? .subtract:.replace
      c.mouseDown(with:try mouse(.leftMouseDown,50,40,c,f))
      c.mouseDragged(with:try mouse(.leftMouseDragged,70,54,c,f))
      XCTAssertTrue(c.creatingMarquee);XCTAssertEqual(c.selectionDragMode,mode)
      c.keyDown(with:try key(49,flags:f));XCTAssertEqual(c.toolCursor,.closedHand)
      c.mouseDragged(with:try mouse(.leftMouseDragged,75,50,c,f))
      XCTAssertEqual(c.start,CGPoint(x:55,y:36));XCTAssertEqual(c.end,CGPoint(x:75,y:50))
      XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertEqual(s.pan,pan)
      c.keyUp(with:try key(49,up:true,flags:f));XCTAssertEqual(c.toolCursor,.selection(tool.symbol,mode))
      c.mouseDragged(with:try mouse(.leftMouseDragged,80,60,c,f))
      c.mouseUp(with:try mouse(.leftMouseUp,82,61,c,f));await s.geometryTask?.value;await s.renderTask?.value
      let rect=IntRect(x:55,y:36,width:27,height:25)
      var expected=original;try Command.selectShape(tool == .marquee ? .rectangle(rect):.ellipse(rect),mode,false,0).apply(to:&expected)
      XCTAssertEqual(s.document,expected,"\(tool), modifiers\(bits)");XCTAssertEqual(s.document.layers,original.layers)
      XCTAssertEqual(s.session.undoStack.count,expected == original ? 0:1);XCTAssertNil(c.marqueeCreation);XCTAssertNil(s.error)
      _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original)
      _=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document,expected)
      c.cursorLocationInView=c.viewPoint(.init(x:95,y:71));c.updateCursorModifiers([])
      XCTAssertEqual(c.toolCursor,.selection(tool.symbol,.replace))
    }}
  }
  @MainActor func testAllSixteenLiveGeometryModifiersKeepTheirShapeWhileTranslating() async throws {
    for tool:EditorTool in [.marquee,.ellipticalMarquee] {for bits in 0..<16 {
      let(s,c,w)=try await fixture(tool);defer{close(s,c,w)};let original=s.document,f=flags(bits)
      c.mouseDown(with:try mouse(.leftMouseDown,50,40,c))
      c.mouseDragged(with:try mouse(.leftMouseDragged,60,44,c,f))
      c.keyDown(with:try key(49,flags:f));c.mouseDragged(with:try mouse(.leftMouseDragged,65,41,c,f))
      XCTAssertEqual(c.toolCursor,.closedHand);XCTAssertFalse(c.panningGesture)
      c.keyUp(with:try key(49,up:true,flags:f));c.mouseUp(with:try mouse(.leftMouseUp,65,41,c,f))
      await s.geometryTask?.value;await s.renderTask?.value
      let centered=f.contains(.option),side=f.contains(.shift) ? 10:4
      let rect=IntRect(x:centered ? 45:55,y:centered ? 37-side:37,width:centered ? 20:10,height:side*(centered ? 2:1))
      var expected=original;try Command.selectShape(tool == .marquee ? .rectangle(rect):.ellipse(rect),.replace,false,0).apply(to:&expected)
      XCTAssertEqual(s.document,expected,"Live geometry \(tool), modifiers\(bits)");XCTAssertNil(s.error)
    }}
  }
  @MainActor func testSpaceHeldThroughMouseReleaseIncludesFinalDeltaAndRetainsCapturedSettings() async throws {
    let(s,c,w)=try await fixture(.ellipticalMarquee);defer{close(s,c,w)}
    s.session=EditorSession(document:try CraftDocument(width:96,height:72));let original=s.document,pan=s.pan
    s.selectionAntiAlias=true;s.selectionFeather=1
    c.mouseDown(with:try mouse(.leftMouseDown,50,40,c));c.mouseDragged(with:try mouse(.leftMouseDragged,70,54,c))
    s.selectionAntiAlias=false;s.selectionFeather=0
    c.keyDown(with:try key(49));c.mouseDragged(with:try mouse(.leftMouseDragged,75,50,c))
    c.mouseUp(with:try mouse(.leftMouseUp,78,52,c));await s.geometryTask?.value;await s.renderTask?.value
    var expected=original;try Command.selectShape(.ellipse(.init(x:58,y:38,width:20,height:14)),.replace,true,1).apply(to:&expected)
    XCTAssertEqual(s.document,expected);XCTAssertEqual(s.pan,pan);XCTAssertEqual(s.session.undoStack.count,1)
    XCTAssertEqual(c.toolCursor,.openHand);c.keyUp(with:try key(49,up:true));XCTAssertFalse(c.spaceHeld)
  }
  @MainActor func testEscapeFocusToolSourcePanelAndBusyChangesCannotCommitStaleMarquee() async throws {
    for reason in 0..<6 {
      let(s,c,w)=try await fixture();defer{close(s,c,w)};let original=s.document
      c.mouseDown(with:try mouse(.leftMouseDown,50,40,c));c.mouseDragged(with:try mouse(.leftMouseDragged,70,54,c))
      c.keyDown(with:try key(49))
      switch reason {
      case 0:c.keyDown(with:try key(53))
      case 1:c.clearCursorInput()
      case 2:s.chooseTool(WorkspaceCatalog.tool("brush"));c.synchronizeTool()
      case 3:s.session=EditorSession(document:original)
      case 4:s.layerPanelGeneration=UUID()
      default:s.geometryBusy=true
      }
      c.mouseDragged(with:try mouse(.leftMouseDragged,75,50,c));c.mouseUp(with:try mouse(.leftMouseUp,78,52,c));s.geometryBusy=false
      await s.geometryTask?.value;await s.renderTask?.value
      XCTAssertEqual(s.document,original,"Cancellation\(reason)");XCTAssertTrue(s.session.undoStack.isEmpty)
      XCTAssertNil(c.marqueeCreation);XCTAssertNil(c.start);XCTAssertNil(c.end)
      c.clearCursorInput();XCTAssertFalse(c.spaceHeld)
    }
  }
  @MainActor func testSpaceBeforePressPansAndSinglePixelMarqueesRemainExcluded() async throws {
    let(s,c,w)=try await fixture();defer{close(s,c,w)};let original=s.document
    c.keyDown(with:try key(49));c.mouseDown(with:try mouse(.leftMouseDown,50,40,c))
    XCTAssertTrue(c.panningGesture);XCTAssertNil(c.marqueeCreation);XCTAssertEqual(c.toolCursor,.closedHand)
    c.mouseDragged(with:try mouse(.leftMouseDragged,75,50,c));c.mouseUp(with:try mouse(.leftMouseUp,75,50,c))
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty);c.keyUp(with:try key(49,up:true))
    for id in ["rowMarquee","columnMarquee"] {
      s.chooseTool(WorkspaceCatalog.tool(id));c.synchronizeTool()
      c.mouseDown(with:try mouse(.leftMouseDown,50,40,c));XCTAssertNil(c.marqueeCreation)
      c.keyDown(with:try key(53));c.mouseUp(with:try mouse(.leftMouseUp,75,50,c))
      XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testActivePolygonOutranksExistingSelectionBorderForClicksAndCursor() async throws {
    let(s,c,w)=try await fixture(.polygonLasso);defer{close(s,c,w)};let original=s.document
    for p in [CGPoint(x:55,y:40),.init(x:22,y:20),.init(x:15,y:25)] {
      c.mouseDown(with:try mouse(.leftMouseDown,p.x,p.y,c));c.mouseUp(with:try mouse(.leftMouseUp,p.x,p.y,c))
      XCTAssertNil(s.selectionBorderDrag);XCTAssertFalse(c.selectionBorderGesture)
      XCTAssertEqual(c.toolCursor,.selection("lasso",.replace))
      XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
    XCTAssertEqual(c.polygonPoints.count,3);let points=c.polygonPoints
    c.keyDown(with:try key(36));await s.geometryTask?.value;await s.renderTask?.value
    var expected=original;try Command.selectShape(.polygon(points),.replace,false,0).apply(to:&expected)
    XCTAssertEqual(s.document,expected);XCTAssertEqual(s.session.undoStack.count,1);XCTAssertNil(s.error)
  }
  @MainActor func testRepositionedMarqueeMatchesExistingAPIActionArchiveAndReadOnlyCapabilities() async throws {
    let(s,c,w)=try await fixture(.ellipticalMarquee);defer{close(s,c,w)};let original=s.document
    try s.session.startActionRecording(name:"Reposition marquee")
    c.mouseDown(with:try mouse(.leftMouseDown,50,40,c));c.mouseDragged(with:try mouse(.leftMouseDragged,70,54,c))
    c.keyDown(with:try key(49));c.mouseUp(with:try mouse(.leftMouseUp,75,50,c));await s.geometryTask?.value;await s.renderTask?.value
    var replay=original;try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay)
    XCTAssertEqual(replay,s.document);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(s.document)),s.document)
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      doc.store.session=EditorSession(document:original);try service.share(doc)
      let status=try await h.edit(service,doc,"selection.shape",["shape":["ellipse":["x":55,"y":36,"width":20,"height":14]],"mode":"replace","antiAlias":false,"feather":0])
      XCTAssertEqual(status,200);XCTAssertEqual(doc.store.document,s.document)
      let revision=service.revision(doc.store),count=AutomationCommand.definitions.count
      let response=try await h.request(service,path:"/v1/capabilities")
      XCTAssertEqual(response.0.statusCode,200)
      let object=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any])
      XCTAssertNotNil((object["toolCursorFeedback"]as?[String:Any])?["marqueeCreation"])
      XCTAssertNotNil(SelectionToolAPI.capabilities["marqueeCreation"])
      XCTAssertEqual(service.revision(doc.store),revision);XCTAssertEqual(AutomationCommand.definitions.count,count)
      let stale=try await h.edit(service,doc,"selection.shape",["shape":["rectangle":["x":1,"y":1,"width":4,"height":4]]],revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(doc.store.document,s.document)
    }
  }
}
