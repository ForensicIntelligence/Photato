import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AdvancedTypographyWorkflowTests:XCTestCase {
  func testAdvancedTypeActionVersionAndLegacyArchiveRejection()throws {
    var text=TextContent(text:"Vertical");text.typography=TextTypography();text.typography?.orientation = .vertical
    let action=RecordedAction(name:"Type",steps:[.init(name:"Type",operation:.addContent("Type",.text(text)))])
    let file=ActionLibraryFile(actions:[action]),bytes=try file.encoded()
    XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,6)
    var raw=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];raw["version"]=5
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:raw)))
    var document=try CraftDocument(width:300,height:300);try action.apply(to:&document)
    let data=try NativeArchive.encode(document)
    XCTAssertEqual(try NativeArchive.decode(data),document)
    var legacy=try PropertyListSerialization.propertyList(from:data,format:nil) as! [String:Any];legacy["version"]=33
    XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:legacy,format:.binary,options:0)))
  }
  @MainActor func testVerticalEditorGlyphCommitCancelAndHistory()async throws {
    _ = NSApplication.shared
    let s=EditorStore(document:try CraftDocument(width:300,height:300),actions:ActionLibrary(),shapes:ShapeLibrary())
    defer{s.renderTask?.cancel()};let before=s.document;s.tool = .verticalText
    s.beginType(at:.init(x:10,y:10),end:.init(x:10,y:10))
    let draft=try XCTUnwrap(s.typeEditingDraft),editor=try CanvasTypeEditor(store:s,draft:draft);s.typeEditor=editor
    let window=NSWindow(contentRect:.init(x:0,y:0,width:300,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView=editor;window.makeFirstResponder(editor)
    defer{editor.delegate=nil;window.contentView=nil;window.orderOut(nil)}
    XCTAssertEqual(editor.layoutOrientation,.vertical)
    editor.insertText("Native 日本語",replacementRange:.init(location:0,length:0))
    XCTAssertEqual(draft.content.typography?.writingOrientation,.vertical)
    editor.setSelectedRange(.init(location:0,length:6));s.setFontFeature("liga",0)
    let glyph=try XCTUnwrap(NativeFonts.glyphs("HelveticaNeue").first{$0.unicode=="A"})
    editor.setSelectedRange(.init(location:editor.string.utf16.count,length:0));s.insertGlyph(font:"HelveticaNeue",glyph:glyph)
    XCTAssertTrue(editor.string.hasSuffix("A"));XCTAssertNil(s.error)
    XCTAssertEqual(s.document,before);XCTAssertTrue(s.finishType());s.typeEditor=nil
    let finished=s.document;XCTAssertEqual(s.session.undoStack.count,1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(finished)),finished)
    await s.undo();XCTAssertEqual(s.document,before);await s.redo();XCTAssertEqual(s.document,finished)
    s.beginType(try XCTUnwrap(s.activeLayer));s.setTypeOrientation(.horizontal);XCTAssertTrue(s.finishType(cancel:true));s.typeEditor=nil;XCTAssertEqual(s.document,finished)
    s.setTypeOrientation(.horizontal);XCTAssertEqual(s.editableType?.typography?.writingOrientation,.horizontal)
    await s.undo();XCTAssertEqual(s.document,finished)
    XCTAssertEqual(WorkspaceCatalog.tool("verticalType").native,.verticalText)
  }
  @MainActor func testNativeAPIFontsGlyphsArchiveNegotiationAndAtomicErrors()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),shapes:ShapeLibrary(),pressedMouseButtons:{0}){service,shared in
      shared.store.session=EditorSession(document:try CraftDocument(width:300,height:300));try service.share(shared);service.setDocumentTransfersEnabled(true)
      let create=try await h.edit(service,shared,"text.create",["x":10,"y":10,"text":["text":"A😀B","orientation":"vertical","style":["font":"HelveticaNeue","fontOptions":["features":[["tag":"liga","value":0]]]]]])
      XCTAssertEqual(create,200)
      let layer=try XCTUnwrap(shared.store.activeLayer),before=shared.store.document,share=try XCTUnwrap(service.shares.first)
      let inspect=try await h.request(service,path:"/v1/documents/\(share.id)/commands",body:["command":"font.inspect","revision":service.revision(shared.store),"parameters":["font":"Skia","count":8]])
      XCTAssertEqual(inspect.0.statusCode,200)
      let info=try JSONSerialization.jsonObject(with:inspect.1) as! [String:Any]
      XCTAssertFalse((info["axes"] as? [[String:Any]] ?? []).isEmpty);XCTAssertEqual((info["glyphs"] as? [Any])?.count,8)
      let glyph=try XCTUnwrap(NativeFonts.glyphs("HelveticaNeue").first{$0.unicode=="A"})
      let args:[String:Any]=["layerID":layer.id.uuidString,"font":"HelveticaNeue","glyphID":Int(glyph.id),"location":4]
      let inserted=try await h.edit(service,shared,"text.glyph",args);XCTAssertEqual(inserted,200)
      let desktop=EditorStore(document:before,actions:ActionLibrary(),shapes:ShapeLibrary());desktop.insertGlyph(font:"HelveticaNeue",glyph:glyph);defer{desktop.renderTask?.cancel()}
      XCTAssertEqual(shared.store.document,desktop.document)
      guard case .text(let text)=shared.store.activeLayer?.content else{return XCTFail()}
      XCTAssertEqual(text.text,"A😀BA");XCTAssertEqual(text.typography?.runs.last?.style.glyphOverride?.glyph,glyph.id)
      let modern=try await h.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"34"])
      XCTAssertEqual(modern.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(modern.1),shared.store.document)
      let old=try await h.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"33"]);XCTAssertNotEqual(old.0.statusCode,200)
      let undo=try await h.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,before)
      let stale=try await h.edit(service,shared,"text.glyph",args,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.beginType(layer);let busy=try await h.edit(service,shared,"text.glyph",args);XCTAssertEqual(busy,409);shared.store.finishType(cancel:true)
      var bad=args;bad["location"]=2
      let split=try await h.edit(service,shared,"text.glyph",bad);XCTAssertEqual(split,400)
      let unknown=try await h.edit(service,shared,"text.set",["layerID":layer.id.uuidString,"text":["text":"bad","style":["fontOptions":["oops":1]]]])
      XCTAssertEqual(unknown,400);XCTAssertEqual(shared.store.document,before)
      for name in FontAPI.commands{XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationCommand.definitions.first{$0.name==name}!.schema))}
    }
  }
  func testPublishedVerticalAndSmallCapsUseNativeEditableText()throws {
    let h=NativeTypeWorkflowTests();var edit=h.addition()
    edit["text"]=["content":"Vertical text","textOrientation":"vertical","frame":["type":"area","bounds":["left":10,"top":20,"right":150,"bottom":250]],"characterStyles":[["characterStyle":["font":["postScriptName":"TimesNewRomanPSMT"],"fontSize":24,"capsOption":"small_caps"]]]]
    let result=try h.request([edit]).applying(to:CraftDocument(width:300,height:300)).session.document
    guard case .text(let text)=result.layers.last?.content else{return XCTFail()}
    XCTAssertEqual(text.typography?.writingOrientation,.vertical)
    XCTAssertEqual(text.typography?.defaultStyle.fontOptions?.features.first{$0.tag=="smcp"}?.value,1)
    let reopened=try PSDCodec.read(PSDCodec.writeRasterLayers(result))
    guard case .text(let restored)=reopened.layers.last?.content else{return XCTFail()}
    XCTAssertEqual(restored.typography?.writingOrientation,.vertical)
    XCTAssertEqual(restored.typography?.defaultStyle.fontOptions,text.typography?.defaultStyle.fontOptions)
  }
}
