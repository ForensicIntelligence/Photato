import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class EraserModeWorkflowTests:XCTestCase {
  func document(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:48,height:32,depth:depth);d.layers[0].content = .raster(try Surface(width:48,height:32,depth:depth,fill:Pixel(0.3,0.4,0.5)));return d
  }
  @MainActor func testNativeModesCapturedBrushPreviewCancelCommitUndoAndActions()async throws {
    for mode in EraserMode.allCases {
      let doc=try document(),store=EditorStore(document:doc,actions:ActionLibrary(),brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()}
      store.tool = .eraser;store.eraserMode=mode;store.brush.size=9;let before=store.brush
      store.beginBrush(.init(x:18,y:16,time:0),zoom:1)
      let captured=try XCTUnwrap(store.brushGesture);XCTAssertEqual(captured.eraserMode,mode);XCTAssertEqual(store.brush,before)
      store.eraserMode = mode == .block ? .brush:.block
      XCTAssertEqual(store.brushGesture?.eraserMode,mode)
      store.cancelBrush();XCTAssertEqual(store.document,doc)
      store.eraserMode=mode;try store.startRecordingAction(name:"Owned eraser",set:"Owned")
      store.beginBrush(.init(x:18,y:16,time:0),zoom:1);store.extendBrush(.init(x:28,y:16,time:100))
      var expected=doc;try XCTUnwrap(store.brushGesture?.command).apply(to:&expected)
      await store.brushPreviewTask?.value;store.finishBrush();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertNotEqual(expected,doc);XCTAssertEqual(store.session.undoStack.count,1)
      let action=try store.stopRecordingAction();var replay=doc;try action.apply(to:&replay);XCTAssertEqual(replay,expected)
      let file=try ActionLibraryFile.decode(store.actions.exportFile(action.id));XCTAssertLessThanOrEqual(file.version,54)
      _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,doc);_=await store.requestHistory(redo:true).value;XCTAssertEqual(store.document,expected)
      XCTAssertEqual(store.brush,before)
    }
  }
  @MainActor func testHighZoomNoOpAndUnsupportedHistoryAlternateNeverCreateHistory()throws {
    let doc=try document(),store=EditorStore(document:doc,brushes:BrushLibrary());defer{store.renderTask?.cancel()}
    store.tool = .eraser;store.eraserMode = .block;let before=store.brush
    store.beginBrush(.init(x:20,y:16),zoom:64);XCTAssertNil(store.brushGesture)
    for mode in EraserMode.allCases {store.eraserMode=mode;store.beginBrush(.init(x:20,y:16),zoom:1,alternate:true);XCTAssertNil(store.brushGesture)}
    XCTAssertEqual(store.document,doc);XCTAssertEqual(store.brush,before);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testAllModifierCursorsModeCaptureAndSpaceFocusRestoration()throws {
    let store=EditorStore(document:try document(),brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()};store.tool = .eraser
    let canvas=CraftCanvas(store:store)
    let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for mode in EraserMode.allCases {for bits in 0..<16 {
      var modifiers:NSEvent.ModifierFlags=[];for i in 0..<4 where bits&(1<<i) != 0 {modifiers.insert(flags[i])}
      let cursor=EditorTool.eraser.cursor(modifiers:modifiers,eraserMode:mode)
      let expected:ToolCursor=modifiers.contains(.option) ? .unavailable:mode == .block ? .blockEraser:mode == .pencil ? .symbol("pencil.tip"):.symbol("eraser")
      XCTAssertEqual(cursor,expected);XCTAssertFalse(cursor.native.image.size.width==0)
    }}
    store.eraserMode = .block;XCTAssertEqual(canvas.toolCursor,.blockEraser)
    store.beginBrush(.init(x:20,y:16),zoom:1);store.eraserMode = .pencil;XCTAssertEqual(canvas.toolCursor,.blockEraser)
    store.cancelBrush();XCTAssertEqual(canvas.toolCursor,.symbol("pencil.tip"))
    canvas.spaceHeld=true;XCTAssertEqual(canvas.toolCursor,.openHand);canvas.spaceHeld=false;XCTAssertEqual(canvas.toolCursor,.symbol("pencil.tip"))
  }
  @MainActor func testRealHTTPModesMatchNativeAtEveryDepthWithHistoryAndLegacyCompatibility()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      for depth in PixelDepth.allCases {for mode in EraserMode.allCases {
        let doc=try self.document(depth);document.store.session=EditorSession(document:doc);document.store.selectedLayerIDs=[doc.layers[0].id]
        try service.share(document)
        let native=EditorStore(document:doc,brushes:BrushLibrary());defer{native.cancelBrush();native.renderTask?.cancel()}
        native.tool = .eraser;native.eraserMode=mode;native.brush=document.store.brush
        native.beginBrush(.init(x:20,y:16,time:0),zoom:1);native.extendBrush(.init(x:28,y:16,time:100))
        let gesture=try XCTUnwrap(native.brushGesture);var expected=doc;try gesture.command.apply(to:&expected)
        let status=try await helper.edit(service,document,"paint.stroke",["eraserMode":mode.rawValue,"zoom":1,"brush":BrushAPI.json(gesture.brush),"points":BrushAPI.json(gesture.points)])
        XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected);XCTAssertEqual(document.store.session.undoStack.count,1)
        let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,doc)
      }}
      let doc=try self.document();document.store.session=EditorSession(document:doc);try service.share(document)
      var brush=document.store.brush;brush.erase=true;let points:[StrokePoint]=[.init(x:20,y:16)]
      var expected=doc;try Command.stroke(doc.layers[0].id,points,brush).apply(to:&expected)
      let status=try await helper.edit(service,document,"paint.stroke",["brush":BrushAPI.json(brush),"points":BrushAPI.json(points)])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
    }
  }
  @MainActor func testAPIConfigureAtomicValidationBusyStaleAndNoOp()async throws {
    let helper=AutomationTests()
    try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document);let doc=document.store.document,before=document.store.brush,revision=service.revision(document.store)
      let status=try await helper.edit(service,document,"brush.configure",["brush":[:],"eraserMode":"block"])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.eraserMode,.block);XCTAssertEqual(document.store.brush,before);XCTAssertNotEqual(service.revision(document.store),revision)
      let unchanged=service.revision(document.store);let noop=try await helper.edit(service,document,"brush.configure",["brush":[:],"eraserMode":"block"])
      XCTAssertEqual(noop,200);XCTAssertEqual(service.revision(document.store),unchanged)
      let bad=try await helper.edit(service,document,"brush.configure",["brush":["size":19],"eraserMode":"unknown"]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.brush,before)
      for params:[String:Any] in [["points":[["x":1,"y":1]],"eraserMode":"bad"],["points":[["x":1,"y":1]],"zoom":1],["points":[["x":1,"y":1]],"eraserMode":"block","zoom":0]] {
        let invalid=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(invalid,400)
      }
      let stale=try await helper.edit(service,document,"brush.configure",["brush":[:],"eraserMode":"pencil"],revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"brush.configure",["brush":[:],"eraserMode":"pencil"]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let empty=try await helper.edit(service,document,"paint.stroke",["points":[["x":1,"y":1]],"eraserMode":"block","zoom":64]);XCTAssertEqual(empty,200)
      XCTAssertEqual(document.store.document,doc);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertEqual(document.store.brushState["eraserMode"]as?String,"block")
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
    }
  }
  @MainActor func testMaskTargetsAndLargeSparseNativeStrokeKeepExistingCommandPaths()async throws {
    for mode in EraserMode.allCases {
      var doc=try document();doc.layers[0].mask=try Surface(width:48,height:32,fill:.white)
      let store=EditorStore(document:doc,brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()}
      store.tool = .eraser;store.eraserMode=mode;store.selectMask(doc.layers[0].id)
      store.beginBrush(.init(x:20,y:16),zoom:1);let gesture=try XCTUnwrap(store.brushGesture)
      XCTAssertFalse(gesture.brush.erase);XCTAssertEqual(gesture.brush.color,store.backgroundColor)
      var expected=doc;try gesture.command.apply(to:&expected);XCTAssertNotEqual(expected.layers[0].mask,doc.layers[0].mask)
      store.finishBrush();await store.geometryTask?.value;XCTAssertEqual(store.document,expected)
    }
    var doc=try CraftDocument(width:300000,height:300000);doc.layers[0].content = .raster(try Surface(width:300000,height:300000,fill:.white))
    var brush=Brush();brush.erase=true;let resolved=try XCTUnwrap(EraserBrush.resolve(brush,mode:.block,zoom:1))
    try Command.stroke(doc.layers[0].id,[.init(x:150000,y:150000)],resolved).apply(to:&doc)
    guard case .raster(let surface)=doc.layers[0].content else{return XCTFail("Raster")}
    XCTAssertLessThan(surface.pixel(x:150000,y:150000).a,1);XCTAssertEqual(surface.pixel(x:0,y:0),.white)
  }
  @MainActor func testHostedEraserOptionsAndSchemaExposeAllModesWithoutVersionChange()throws {
    _=NSApplication.shared;let store=EditorStore(document:try document(),brushes:BrushLibrary());defer{store.renderTask?.cancel()};store.tool = .eraser
    for mode in EraserMode.allCases {
      store.eraserMode=mode;let host=NSHostingView(rootView:EraserOptionsView(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:70);host.layoutSubtreeIfNeeded();XCTAssertEqual(store.eraserMode,mode)
    }
    for name in ["brush.configure","paint.stroke"] {
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name==name}),outer=try XCTUnwrap(definition.schema["properties"]as?[String:Any]),params=try XCTUnwrap(outer["parameters"]as?[String:Any]),fields=try XCTUnwrap(params["properties"]as?[String:Any])
      XCTAssertNotNil(fields["eraserMode"]);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:definition.schema))
    }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:BrushAPI.capabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ToolCursorAPI.capabilities))
  }
}
