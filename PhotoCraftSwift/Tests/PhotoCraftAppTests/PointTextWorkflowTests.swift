import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PointTextWorkflowTests:XCTestCase {
  func text(_ alignment:TypeParagraph.Alignment = .left,vertical:Bool=false,string:String="Alpha")->TextContent {
    var value=TextContent(text:string,fontName:"HelveticaNeue",size:16,color:.black),type=TextTypography()
    type.defaultStyle.font="HelveticaNeue";type.defaultStyle.size=16;type.defaultParagraph.alignment=alignment
    if vertical{type.orientation = .vertical};value.typography=type;return value
  }
  func model(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var document=try CraftDocument(width:180,height:140,depth:depth)
    var layer=Layer(name:"Point",content:.text(text()));layer.x=70;layer.y=40
    document.layers=[layer];document.activeLayerID=layer.id;return document
  }
  @MainActor func caret(_ editor:CanvasTypeEditor,_ window:NSWindow,_ position:Int)throws->NSRect {
    var range=NSRange()
    let screen=editor.firstRect(forCharacterRange:NSRange(location:position,length:0),actualRange:&range)
    XCTAssertTrue(screen.width>0 || screen.height>0,"Caret must not be outside the editor")
    return editor.convert(window.convertFromScreen(screen),from:nil)
  }
  @MainActor func testNativeEditorCaretAndHitTestingUseSamePointCropAtBothOrientations() throws {
    _ = NSApplication.shared
    for vertical in [false,true] {for alignment in [TypeParagraph.Alignment.center,.right] {
      let store=EditorStore(document:try model());store.renderTask?.cancel();defer{store.renderTask?.cancel()}
      store.beginType(try XCTUnwrap(store.activeLayer));let draft=try XCTUnwrap(store.typeEditingDraft)
      draft.content=text(alignment,vertical:vertical)
      let editor=try CanvasTypeEditor(store:store,draft:draft);store.typeEditor=editor
      let window=NSWindow(contentRect:NSRect(x:100,y:100,width:400,height:200),styleMask:[.borderless],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=editor;window.makeFirstResponder(editor)
      defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
      editor.frame=NSRect(x:0,y:0,width:400,height:200);editor.configureContainer()
      let metrics=try NativeTextLayout.editingMetrics(draft.content,dpi:72)
      XCTAssertEqual(editor.textContainerOrigin.x,-metrics.layoutOrigin.x)
      XCTAssertEqual(editor.textContainer?.containerSize.width,65536)
      XCTAssertLessThan(metrics.width,100);XCTAssertLessThan(metrics.height,100)
      for position in [0,5] {
        let rect=try caret(editor,window,position)
        XCTAssertTrue(editor.bounds.insetBy(dx:-1,dy:-1).intersects(rect.insetBy(dx:-0.1,dy:-0.1)))
        XCTAssertEqual(editor.characterIndexForInsertion(at:NSPoint(x:rect.midX,y:rect.midY)),position)
      }
      editor.setSelectedRange(NSRange(location:1,length:3));store.formatType{s,_ in s.underline=true}
      XCTAssertEqual(editor.selectedRange(),NSRange(location:1,length:3));XCTAssertTrue(store.finishType());XCTAssertNil(store.error)
    }}
  }
  @MainActor func testEmptyTypingAndCanvasFrameKeepTheInsertionPointWhileAlignmentChanges() throws {
    _ = NSApplication.shared
    for alignment in [TypeParagraph.Alignment.center,.right] {
      let store=EditorStore(document:try CraftDocument(width:300,height:160));store.renderTask?.cancel();store.zoom=1
      defer{store.renderTask?.cancel()}
      let canvas=CraftCanvas(store:store),window=NSWindow(contentRect:NSRect(x:100,y:100,width:1000,height:650),styleMask:[.borderless],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=canvas;canvas.frame=NSRect(x:0,y:0,width:1000,height:650)
      defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
      store.beginType(at:NSPoint(x:120,y:70),end:NSPoint(x:120,y:70))
      let draft=try XCTUnwrap(store.typeEditingDraft);draft.content=text(alignment,string:"")
      canvas.synchronizeTypeEditor();let editor=try XCTUnwrap(store.typeEditor);window.makeFirstResponder(editor)
      let point=window.convertPoint(toScreen:canvas.convert(canvas.viewPoint(NSPoint(x:120,y:70)),to:nil))
      var actual=NSRange();let empty=editor.firstRect(forCharacterRange:NSRange(location:0,length:0),actualRange:&actual)
      XCTAssertEqual(empty.minX,point.x,accuracy:0.000001)
      editor.insertText("Alpha",replacementRange:NSRange(location:0,length:0));canvas.synchronizeTypeEditor()
      let first=editor.firstRect(forCharacterRange:NSRange(location:0,length:0),actualRange:&actual)
      let last=editor.firstRect(forCharacterRange:NSRange(location:5,length:0),actualRange:&actual)
      XCTAssertTrue(first.height>0);XCTAssertTrue(last.height>0)
      XCTAssertEqual(alignment == .right ? last.minX:(first.minX+last.minX)/2,point.x,accuracy:0.000001)
      XCTAssertTrue(store.finishType());XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
      let layer=try XCTUnwrap(store.activeLayer),metrics=try NativeTextLayout.metrics(try XCTUnwrap(layer.typeContent),dpi:72)
      let anchor=layer.coordinateTransform.point(-metrics.origin.x,-metrics.origin.y)
      XCTAssertEqual(anchor.x,120,accuracy:0.000001);XCTAssertEqual(anchor.y,70,accuracy:0.000001)
    }
  }
  @MainActor func testRichLastLineEditorMatchesRendererAfterRepeatedFreshLayouts() throws {
    _ = NSApplication.shared
    for lastLine in [TypeParagraphFormatting.LastLine.center,.right] {
      let store=EditorStore(document:try model());store.renderTask?.cancel();defer{store.renderTask?.cancel()}
      store.beginType(try XCTUnwrap(store.activeLayer));let draft=try XCTUnwrap(store.typeEditingDraft)
      draft.content=text(.justified)
      draft.content.typography?.defaultParagraph.formatting = .init()
      draft.content.typography?.defaultParagraph.formatting?.lastLine = lastLine
      let editor=try CanvasTypeEditor(store:store,draft:draft);store.typeEditor=editor
      let window=NSWindow(contentRect:NSRect(x:100,y:100,width:400,height:200),styleMask:[.borderless],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.contentView=editor;window.makeFirstResponder(editor)
      defer{store.finishType(cancel:true);window.contentView=nil;window.close()}
      editor.frame=NSRect(x:0,y:0,width:400,height:200)
      let metrics=try NativeTextLayout.editingMetrics(draft.content,dpi:72)
      var previous:NSRect?
      for _ in 0..<8 {
        editor.configureContainer()
        let manager=try XCTUnwrap(editor.layoutManager),container=try XCTUnwrap(editor.textContainer)
        manager.invalidateLayout(forCharacterRange:NSRange(location:0,length:editor.string.utf16.count),actualCharacterRange:nil)
        manager.ensureLayout(for:container)
        let rect=try caret(editor,window,0),end=try caret(editor,window,5)
        XCTAssertGreaterThanOrEqual(rect.minX,0)
        XCTAssertLessThan(rect.minX,2)
        XCTAssertEqual(lastLine == .right ? end.minX:(rect.minX+end.minX)/2,-metrics.origin.x,accuracy:0.000001)
        if let previous{XCTAssertEqual(rect,previous)}
        previous=rect
        XCTAssertEqual(editor.characterIndexForInsertion(at:NSPoint(x:rect.midX,y:rect.midY)),0)
      }
      XCTAssertTrue(editor.updateDraft());XCTAssertEqual(draft.content.typography?.defaultParagraph.formatting?.lastLine,lastLine)
      XCTAssertTrue(store.finishType());XCTAssertNil(store.error)
    }
  }
  @MainActor func testAllDepthNativeAndHTTPAlignmentPreserveMasksArchivePixelsAndSingleUndo() async throws {
    let helper=AutomationTests()
    for depth in PixelDepth.allCases {
      try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
        var original=try self.model(depth)
        original.layers[0].affine=original.layers[0].coordinateTransform * .scale(1.15,0.9);original.layers[0].x=0;original.layers[0].y=0
        original.layers[0].mask=try Surface(width:100,height:70,depth:.u8,fill:.white)
        let mask=original.layers[0].maskCoordinateTransform
        document.store.session=EditorSession(document:original);document.store.renderTask?.cancel()
        let native=EditorStore(document:original);native.renderTask?.cancel();defer{native.renderTask?.cancel()}
        native.formatType(paragraph:true){_,p in p.alignment = .right}
        XCTAssertNil(native.error);XCTAssertEqual(native.session.undoStack.count,1)
        let expected=native.document,layer=try XCTUnwrap(native.activeLayer)
        XCTAssertEqual(layer.maskCoordinateTransform.tx,mask.tx,accuracy:1e-9);XCTAssertEqual(layer.maskCoordinateTransform.ty,mask.ty,accuracy:1e-9)
        try service.share(document)
        let status=try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":try XCTUnwrap(layer.typeContent).apiType]);XCTAssertEqual(status,200)
        XCTAssertEqual(document.store.document,expected);XCTAssertEqual(document.store.session.undoStack.count,1)
        XCTAssertEqual(try DocumentIO.encode(document.store.document,format:.native),try DocumentIO.encode(expected,format:.native))
        XCTAssertEqual(try Renderer.composite(document.store.document).rgbaData(depth:depth),try Renderer.composite(expected).rgbaData(depth:depth))
        let state=PointTextAPI.state(document.store),value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:state))
        XCTAssertNoThrow(try BrushAPI.merge(value,schema:PointTextAPI.stateSchema))
        XCTAssertEqual((state["metrics"]as?[String:Any])?["pointAnchored"]as?Bool,true)
        let share=try XCTUnwrap(service.shares.first);XCTAssertNotNil(service.state(share,document:document)["textGeometry"])
        let before=document.store.document
        let invalid=try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":["text":"Alpha","style":["size":-1]]]);XCTAssertEqual(invalid,400);XCTAssertEqual(document.store.document,before)
        document.store.beginType(try XCTUnwrap(document.store.activeLayer))
        let busy=try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":try XCTUnwrap(layer.typeContent).apiType]);XCTAssertEqual(busy,409)
        XCTAssertTrue(document.store.finishType(cancel:true));XCTAssertEqual(document.store.document,before)
        await document.store.undo();XCTAssertEqual(document.store.document,original)
      }
    }
  }
  @MainActor func testMaximumSparseCanvasPortableActionAndStateKeepTheSameSmallTypeGeometry() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      var original=try CraftDocument(width:300000,height:300000)
      var layer=Layer(name:"Maximum point",content:.text(self.text()));layer.x=299950;layer.y=299900
      original.layers=[layer];original.activeLayerID=layer.id
      document.store.session=EditorSession(document:original);document.store.renderTask?.cancel()
      let changed=self.text(.center),command=try ShapedTextLayout.replacement(layer,content:changed,document:original)
      let action=RecordedAction(name:"Point",steps:[.init(name:"Align",operation:try XCTUnwrap(ActionOperation(recording:command,in:original)))])
      let encoded=try ActionLibraryFile(actions:[action]).encoded(),decoded=try ActionLibraryFile.decode(encoded)
      var expected=original,replay=original;try command.apply(to:&expected);try decoded.actions[0].apply(to:&replay)
      XCTAssertEqual(replay,expected);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(expected)),expected)
      try service.share(document)
      let status=try await helper.edit(service,document,"text.set",["layerID":layer.id.uuidString,"text":changed.apiType]);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
      let surface=try NativeTextLayout.render(changed,document:expected);XCTAssertLessThan(surface.width*surface.height,10000)
      XCTAssertEqual(AutomationCommand.definitions.count,251);XCTAssertEqual(ActionLibraryFile.maximumVersion,50)
      await document.store.undo();XCTAssertEqual(document.store.document,original)
    }
  }
}
