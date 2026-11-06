import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PathTypeCreationTests:XCTestCase {
  func source(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:500,height:300,depth:depth)
    d.paths=[NamedPath(name:"Curve",path:VectorPath(components:[.init(knots:[.init(.init(50,200),outgoing:.init(150,40)),.init(.init(450,200),incoming:.init(350,40))])]))]
    return d
  }
  @MainActor func host(_ store:EditorStore)->(CraftCanvas,NSWindow) {
    let canvas=CraftCanvas(store:store),window=NSWindow(contentRect:NSRect(x:100,y:100,width:900,height:650),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:900,height:650);canvas.synchronizeTool()
    return(canvas,window)
  }
  @MainActor func event(_ type:NSEvent.EventType,_ canvas:CraftCanvas,_ p:CGPoint,_ flags:NSEvent.ModifierFlags=[])->NSEvent {
    NSEvent.mouseEvent(with:type,location:canvas.convert(canvas.viewPoint(p),to:nil),modifierFlags:flags,timestamp:0,windowNumber:canvas.window?.windowNumber ?? 0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  }
  @MainActor func testNativeAll16ModifierCursorsCapturePathAndPreserveCancel()throws {
    _=NSApplication.shared
    for bits in 0..<16 {
      let original=try source(),store=EditorStore(document:original);store.renderTask?.cancel();defer{store.renderTask?.cancel()}
      store.tool = .text;store.zoom=1;store.pathTarget = .saved(try XCTUnwrap(original.paths?.first).id)
      let(canvas,window)=host(store);defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
      let baseline=try PathTextBaseline(try XCTUnwrap(original.paths?.first?.path.components.first)),p=baseline.locate(baseline.length*0.25).point
      var flags:NSEvent.ModifierFlags=[];for(i,flag)in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated()where bits&(1<<i) != 0{flags.insert(flag)}
      let point=CGPoint(x:p.x,y:p.y);canvas.cursorLocationInView=canvas.viewPoint(point);canvas.updateCursorModifiers(flags)
      XCTAssertEqual(canvas.toolCursor,.pathText);XCTAssertEqual(ToolCursor.pathType(available:false),.unavailable)
      canvas.mouseDown(with:event(.leftMouseDown,canvas,point,flags));XCTAssertNotNil(canvas.pathTypePress)
      canvas.updateCursorModifiers([]);XCTAssertEqual(canvas.toolCursor,.pathText)
      canvas.mouseUp(with:event(.leftMouseUp,canvas,point,[]))
      let draft=try XCTUnwrap(store.typeEditingDraft),editor=try XCTUnwrap(store.typeEditor as?CanvasPathTypeEditor)
      XCTAssertEqual(draft.content.typography?.geometry?.path,original.paths?.first?.path)
      XCTAssertEqual(try XCTUnwrap(draft.content.typography?.geometry?.start),0.25,accuracy:1e-7)
      XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNotNil(editor.pathGeometry);XCTAssertTrue(store.finishType(cancel:true));XCTAssertEqual(store.document,original)
    }
  }
  @MainActor func testNativeCurvedCaretMarkedInputRangeFormattingCommitAndUndo()async throws {
    _=NSApplication.shared
    let original=try source(),store=EditorStore(document:original);store.renderTask?.cancel();defer{store.renderTask?.cancel()}
    store.tool = .text;store.zoom=1
    let(canvas,window)=host(store);defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
    store.beginTypeOnPath(.init(path:try XCTUnwrap(original.paths?.first?.path),fraction:0.1));canvas.synchronizeTypeEditor()
    let editor=try XCTUnwrap(store.typeEditor as?CanvasPathTypeEditor)
    editor.undoManager?.beginUndoGrouping();editor.insertText("Office A\u{301}",replacementRange:NSRange(location:0,length:0));editor.undoManager?.endUndoGrouping()
    editor.undoManager?.undo();XCTAssertEqual(store.typeEditingDraft?.content.text,"")
    editor.undoManager?.redo();XCTAssertEqual(store.typeEditingDraft?.content.text,"Office A\u{301}")
    editor.setMarkedText("é",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:editor.string.utf16.count,length:0))
    XCTAssertTrue(editor.hasMarkedText());editor.unmarkText();XCTAssertTrue(editor.updateDraft());editor.configureContainer()
    editor.setSelectedRange(NSRange(location:0,length:6));store.formatType{s,_ in s.underline=true}
    XCTAssertEqual(editor.selectedRange(),NSRange(location:0,length:6));await editor.previewTask?.value
    XCTAssertNil(editor.pathError);XCTAssertFalse(editor.pathRendering)
    let geometry=try XCTUnwrap(editor.pathGeometry)
    for caret in geometry.carets where caret.visible {
      let local=editor.viewPoint(caret.baseline)
      XCTAssertEqual(editor.characterIndexForInsertion(at:local),caret.utf16Index)
      var range=NSRange();let screen=editor.firstRect(forCharacterRange:NSRange(location:caret.utf16Index,length:0),actualRange:&range)
      XCTAssertGreaterThan(screen.width,0);XCTAssertGreaterThan(screen.height,0);XCTAssertEqual(range.location,caret.utf16Index)
    }
    if let directory=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      store.image=try RasterIO.displayImage(Renderer.composite(original));canvas.needsDisplay=true
      let bitmap=try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds));canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:directory).appendingPathComponent("439-path-editor-offscreen.png"))
    }
    let text=try XCTUnwrap(store.typeEditingDraft?.content);XCTAssertTrue(store.finishType());XCTAssertNil(store.error)
    XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(store.activeLayer?.typeContent,text)
    XCTAssertEqual(store.document.paths,original.paths);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(store.document)),store.document)
    await store.undo();XCTAssertEqual(store.document,original)
  }
  @MainActor func testExistingCurveLayoutsKeepAffineCaretSourceAndCancel()async throws {
    _=NSApplication.shared
    for mode in [TextGeometry.Mode.path,.circle,.arch,.bow] {
      var document=try source(),text=TextContent(text:"Native path"),type=TextTypography(),g=TextGeometry()
      type.defaultStyle.font="HelveticaNeue";type.defaultStyle.size=24;g.mode=mode;g.fit=true;g.width=240;g.height=140
      if mode == .path{g.path=document.paths?.first?.path};type.geometry=g;text.typography=type
      let m=try NativeTextLayout.metrics(text,dpi:72),anchor=Transform2D.translation(70,30) * .rotation(12) * .scale(0.8,1.1)
      var layer=Layer(name:"Curve",content:.text(text));layer.affine=anchor * .translation(m.origin.x,m.origin.y);layer.mask=try Surface(width:70,height:60,fill:.white)
      document.layers=[layer];document.activeLayerID=layer.id
      let store=EditorStore(document:document);store.renderTask?.cancel();defer{store.renderTask?.cancel()};store.zoom=1
      let(canvas,window)=host(store);defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
      store.beginType(layer);canvas.synchronizeTypeEditor();let editor=try XCTUnwrap(store.typeEditor as?CanvasPathTypeEditor);await editor.previewTask?.value
      let caret=try XCTUnwrap(editor.pathGeometry?.carets.first),expected=anchor.point(caret.baseline.x,caret.baseline.y),actual=editor.viewPoint(caret.baseline),point=canvas.viewPoint(CGPoint(x:expected.x,y:expected.y))
      XCTAssertEqual(actual.x,point.x,accuracy:1e-7);XCTAssertEqual(actual.y,point.y,accuracy:1e-7)
      editor.insertText("!",replacementRange:NSRange(location:editor.string.utf16.count,length:0));await editor.previewTask?.value
      XCTAssertNil(editor.pathError);XCTAssertTrue(store.finishType(cancel:true));XCTAssertEqual(store.document,document);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testStaleCapturedPathToolChangeDragBusyAndUnsupportedVerticalDoNotCreate()throws {
    _=NSApplication.shared
    let original=try source(),store=EditorStore(document:original);store.renderTask?.cancel();defer{store.renderTask?.cancel()};store.zoom=1;store.tool = .text;store.pathTarget = .saved(try XCTUnwrap(original.paths?.first).id)
    let(canvas,window)=host(store);defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
    let baseline=try PathTextBaseline(try XCTUnwrap(original.paths?.first?.path.components.first)),p=baseline.locate(baseline.length*0.3).point,point=CGPoint(x:p.x,y:p.y)
    canvas.cursorLocationInView=canvas.viewPoint(point);canvas.mouseDown(with:event(.leftMouseDown,canvas,point))
    var changed=original;changed.paths?[0].name="Changed";store.session=EditorSession(document:changed);canvas.mouseUp(with:event(.leftMouseUp,canvas,point));XCTAssertNil(store.typeEditingDraft)
    store.session=EditorSession(document:original);canvas.cursorLocationInView=canvas.viewPoint(point)
    canvas.mouseDown(with:event(.leftMouseDown,canvas,point));canvas.mouseUp(with:event(.leftMouseUp,canvas,CGPoint(x:point.x+20,y:point.y)));XCTAssertNil(store.typeEditingDraft)
    canvas.cursorLocationInView=canvas.viewPoint(point);canvas.mouseDown(with:event(.leftMouseDown,canvas,point))
    XCTAssertNotNil(canvas.pathTypePress);store.tool = .zoom;canvas.synchronizeTool();XCTAssertNil(canvas.pathTypePress)
    canvas.mouseUp(with:event(.leftMouseUp,canvas,point));XCTAssertNil(store.typeEditingDraft)
    store.tool = .verticalText;canvas.synchronizeTool();canvas.cursorLocationInView=canvas.viewPoint(point);XCTAssertEqual(canvas.toolCursor,.unavailable)
    canvas.mouseDown(with:event(.leftMouseDown,canvas,point));canvas.mouseUp(with:event(.leftMouseUp,canvas,point));XCTAssertNil(store.typeEditingDraft)
    store.tool = .text;canvas.synchronizeTool();store.geometryBusy=true;store.beginTypeOnPath(.init(path:try XCTUnwrap(original.paths?.first?.path),fraction:0));XCTAssertNil(store.typeEditingDraft);store.geometryBusy=false
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testDetachedPreviewReattachmentAndCancelCannotPublishStaleDraft()async throws {
    _=NSApplication.shared
    let original=try source(),store=EditorStore(document:original);store.renderTask?.cancel();defer{store.renderTask?.cancel()};store.tool = .text;store.zoom=1
    let(canvas,window)=host(store);defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
    store.beginTypeOnPath(.init(path:try XCTUnwrap(original.paths?.first?.path),fraction:0));canvas.synchronizeTypeEditor()
    let editor=try XCTUnwrap(store.typeEditor as?CanvasPathTypeEditor)
    editor.insertText("Before reattach",replacementRange:NSRange(location:0,length:0))
    let cancelled=editor.previewTask;editor.removeFromSuperview();canvas.addSubview(editor);canvas.synchronizeTypeEditor()
    await cancelled?.value;await editor.previewTask?.value
    XCTAssertFalse(editor.pathRendering);XCTAssertNil(editor.pathError);XCTAssertEqual(editor.pathGeometry?.utf16Count,15)
    let raw=PathTypeAPI.state(store),value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:raw));XCTAssertNoThrow(try BrushAPI.merge(value,schema:PathTypeAPI.stateSchema));XCTAssertEqual(raw["editing"]as?Bool,true)
    editor.insertText("Latest",replacementRange:NSRange(location:0,length:editor.string.utf16.count));let pending=editor.previewTask
    XCTAssertTrue(store.finishType(cancel:true));await pending?.value;canvas.synchronizeTypeEditor()
    XCTAssertNil(store.typeEditor);XCTAssertNil(store.typeEditingDraft);XCTAssertNil(canvas.typeOverlay)
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(editor.pathRendering)
  }
  @MainActor func testHTTPCreateSetStateAndUndoUseSameNativePathEngineAtEveryDepth()async throws {
    let helper=AutomationTests()
    for depth in PixelDepth.allCases {
      try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
        let original=try self.source(depth);shared.store.session=EditorSession(document:original);shared.store.renderTask?.cancel();try service.share(shared)
        let native=EditorStore(document:original);native.renderTask?.cancel();defer{native.finishType(cancel:true);native.renderTask?.cancel()};native.tool = .text
        native.beginTypeOnPath(.init(path:try XCTUnwrap(original.paths?.first?.path),fraction:0.2))
        native.typeEditingDraft?.content.text="On a path";let text=try XCTUnwrap(native.typeEditingDraft?.content);XCTAssertTrue(native.finishType());XCTAssertNil(native.error)
        let status=try await helper.edit(service,shared,"text.create",["x":0,"y":0,"text":text.apiType]);XCTAssertEqual(status,200)
        let expected=try XCTUnwrap(native.activeLayer),actual=try XCTUnwrap(shared.store.activeLayer)
        XCTAssertEqual(actual.content,expected.content);XCTAssertEqual(actual.coordinateTransform,expected.coordinateTransform)
        XCTAssertEqual(try Renderer.composite(shared.store.document).rgbaData(depth:depth),try Renderer.composite(native.document).rgbaData(depth:depth))
        XCTAssertEqual(shared.store.session.undoStack.count,1);XCTAssertEqual(shared.store.document.paths,original.paths)
        let state=PathTypeAPI.state(shared.store),value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:state));XCTAssertNoThrow(try BrushAPI.merge(value,schema:PathTypeAPI.stateSchema));XCTAssertEqual(state["supported"]as?Bool,true)
        let share=try XCTUnwrap(service.shares.first);XCTAssertNotNil(service.state(share,document:shared)["pathTypeEditing"])
        let before=shared.store.document;shared.store.beginType(actual)
        let busy=try await helper.edit(service,shared,"text.set",["layerID":actual.id.uuidString,"text":text.apiType]);XCTAssertEqual(busy,409);XCTAssertTrue(shared.store.finishType(cancel:true));XCTAssertEqual(shared.store.document,before)
        let invalid=try await helper.edit(service,shared,"text.create",["x":0,"y":0,"text":["text":"X","geometry":["mode":"path","start":1]]]);XCTAssertEqual(invalid,400);XCTAssertEqual(shared.store.document,before)
        await shared.store.undo();XCTAssertEqual(shared.store.document,original)
      }
    }
  }
}
