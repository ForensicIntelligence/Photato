import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ShapedTypeWorkflowTests:XCTestCase {
  func source()throws->CraftDocument {
    var d=try CraftDocument(width:500,height:400),text=TextContent(text:"Photato on a curve")
    text.typography=TextTypography();text.typography?.defaultStyle.size=30
    var layer=Layer(name:"Type",content:.text(text));layer.x=60;layer.y=70
    d.layers=[layer];d.activeLayerID=layer.id
    d.paths=[NamedPath(name:"Curve",path:VectorPath(components:[.init(knots:[.init(.init(60,160),outgoing:.init(140,40)),.init(.init(400,160),incoming:.init(300,40))])]))]
    return d
  }
  @MainActor func testWorkspacePreviewCancelLocalHistoryCommitAndRetainedEditing()async throws {
    _=NSApplication.shared
    let before=try source(),s=EditorStore(document:before,actions:ActionLibrary(),shapes:ShapeLibrary())
    defer{s.cancelShapedType();s.renderTask?.cancel()}
    s.beginShapedType(.circle);let draft=try XCTUnwrap(s.shapedTypeDraft);await draft.task?.value
    XCTAssertNil(draft.error);XCTAssertTrue(draft.ready);XCTAssertNotNil(draft.image);XCTAssertEqual(s.document,before)
    var geometry=draft.settings;geometry.end=0.75;draft.change(geometry);await draft.task?.value
    draft.undo();await draft.task?.value;XCTAssertEqual(draft.settings.end,1)
    draft.redo();await draft.task?.value;XCTAssertEqual(draft.settings.end,0.75)
    s.cancelShapedType();XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginShapedType(.warp);let warp=try XCTUnwrap(s.shapedTypeDraft)
    var setting=warp.settings;setting.warp.style = .arc;setting.warp.bend=45;warp.change(setting);await warp.task?.value
    XCTAssertNil(warp.error);XCTAssertTrue(warp.ready)
    if let directory=ProcessInfo.processInfo.environment["PHOTATO_SHAPED_OUTPUT"] {
      let view=NSHostingView(rootView:ShapedTypeSheet(store:s,model:warp).padding(12).background(Color(nsColor:.windowBackgroundColor)));view.appearance=NSAppearance(named:.aqua);view.frame = .init(x:0,y:0,width:790,height:590)
      let window=NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false);window.appearance=view.appearance;window.contentView=view;view.layoutSubtreeIfNeeded()
      defer{window.contentView=nil;window.orderOut(nil)}
      let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:directory).appendingPathComponent("shaped-workspace-offscreen.png"))
    }
    s.commitShapedType();XCTAssertNil(s.error);XCTAssertEqual(s.session.undoStack.count,1)
    let shaped=s.document;XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(shaped)),shaped)
    await s.undo();XCTAssertEqual(s.document,before);await s.redo();XCTAssertEqual(s.document,shaped)
    s.beginShapedType();let edit=try XCTUnwrap(s.shapedTypeDraft)
    edit.content.text="Still editable";edit.refresh();await edit.task?.value;s.commitShapedType()
    XCTAssertEqual(s.editableType?.text,"Still editable");XCTAssertEqual(s.editableType?.typography?.geometry,setting)
    await s.undo();XCTAssertEqual(s.document,shaped)
  }
  @MainActor func testNativeHTTPLayoutMatchesDesktopAndRejectsStaleBusyAndInvalid()async throws {
    let h=AutomationTests(),before=try source()
    try await h.withService(actions:ActionLibrary(),shapes:ShapeLibrary(),pressedMouseButtons:{0}){service,shared in
      shared.store.session=EditorSession(document:before);try service.share(shared);service.setDocumentTransfersEnabled(true)
      let layer=try XCTUnwrap(before.layers.first),path=try XCTUnwrap(before.paths?.first)
      let desktop=EditorStore(document:before,actions:ActionLibrary(),shapes:ShapeLibrary());defer{desktop.cancelShapedType();desktop.renderTask?.cancel()}
      desktop.pathTarget = .saved(path.id);desktop.beginShapedType(.path)
      let draft=try XCTUnwrap(desktop.shapedTypeDraft);await draft.task?.value;XCTAssertNil(draft.error);desktop.commitShapedType()
      let args:[String:Any]=["layerID":layer.id.uuidString,"pathID":path.id.uuidString,"settings":["mode":"path"]]
      let edited=try await h.edit(service,shared,"text.layout",args);XCTAssertEqual(edited,200);XCTAssertEqual(shared.store.document,desktop.document)
      let share=try XCTUnwrap(service.shares.first),shaped=shared.store.document
      let current=try await h.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"35"])
      XCTAssertEqual(current.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(current.1),shaped)
      let legacy=try await h.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"34"]);XCTAssertNotEqual(legacy.0.statusCode,200)
      let stale=try await h.edit(service,shared,"text.layout",args,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.beginShapedType();await shared.store.shapedTypeDraft?.task?.value
      let busy=try await h.edit(service,shared,"text.layout",args);XCTAssertEqual(busy,409);shared.store.cancelShapedType()
      for settings:[String:Any] in [["mode":"circle","end":0],["mode":"path"],["mode":"warp","warp":["bend":101]],["mode":"block","typo":1]] {
        let bad=try await h.edit(service,shared,"text.layout",["layerID":layer.id.uuidString,"settings":settings]);XCTAssertEqual(bad,400)
      }
      XCTAssertEqual(shared.store.document,shaped)
      let undone=try await h.edit(service,shared,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(shared.store.document,before)
      let redone=try await h.edit(service,shared,"history.redo");XCTAssertEqual(redone,200)
      let removed=try await h.edit(service,shared,"text.layout",["layerID":layer.id.uuidString,"enabled":false]);XCTAssertEqual(removed,200);XCTAssertNil(shared.store.editableType?.typography?.geometry)
      let updated=try await h.edit(service,shared,"text.set",["layerID":layer.id.uuidString,"text":["text":"Circle","geometry":["mode":"circle","width":150,"height":150,"fit":true]]]);XCTAssertEqual(updated,200)
      let created=try await h.edit(service,shared,"text.create",["x":20,"y":20,"text":["text":"Bow","geometry":["mode":"bow","fit":true]]]);XCTAssertEqual(created,200)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:shared)))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationCommand.definitions.first{$0.name=="text.layout"}!.schema))
    }
  }
  func testLayoutActionsVersionAndArchiveDowngradeRejection()throws {
    var d=try source();guard case .text(var text)=d.layers[0].content else{return XCTFail()}
    var g=TextGeometry();g.mode = .arch;g.fit=true;text.typography?.geometry=g;d.layers[0].content = .text(text)
    let action=RecordedAction(name:"Type",steps:[.init(name:"Type",operation:.addContent("Type",.text(text)))])
    let bytes=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,7)
    var raw=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];raw["version"]=6
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:raw)))
    let data=try NativeArchive.encode(d);var plist=try PropertyListSerialization.propertyList(from:data,format:nil) as! [String:Any];plist["version"]=34
    XCTAssertThrowsError(try NativeArchive.decode(PropertyListSerialization.data(fromPropertyList:plist,format:.binary,options:0)))
  }
}
