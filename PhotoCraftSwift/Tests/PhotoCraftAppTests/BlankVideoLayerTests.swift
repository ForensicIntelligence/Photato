import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class BlankVideoLayerTests:XCTestCase {
  func model(_ depth:PixelDepth = .u8,frames:Int=1200)throws->CraftDocument {
    var doc=try CraftDocument(width:12,height:8,depth:depth)
    try Command.video(.create(frameRate:24,durationFrames:frames)).apply(to:&doc)
    try doc.selectVideoFrame(19);return doc
  }
  @MainActor func testNativeCreationAllDepthsFramePaintingUndoAndFileReopen()async throws {
    _ = NSApplication.shared
    for depth in PixelDepth.allCases {
      let before=try model(depth),s=EditorStore(document:before);defer{s.renderTask?.cancel()}
      XCTAssertTrue(s.canCreateBlankVideoLayer);s.createBlankVideoLayer();s.renderTask?.cancel()
      XCTAssertNil(s.error);XCTAssertTrue(s.timelineVisible);XCTAssertEqual(s.document.videoTimeline,before.videoTimeline)
      XCTAssertEqual(s.session.undoStack.count,1);let id=try XCTUnwrap(s.document.activeLayerID)
      XCTAssertEqual(s.activeLayer?.video?.frames.count,1200);XCTAssertEqual(s.activeLayer?.video?.frames.storedFrameCount,1)
      try s.executeEditorCommand(.fill(id,Pixel(0,1,0)));s.renderTask?.cancel()
      let painted=s.document
      XCTAssertEqual(s.activeLayer?.video?.frames[19].pixel(x:2,y:2),Pixel(0,1,0))
      XCTAssertEqual(s.activeLayer?.video?.frames[18].pixel(x:2,y:2),.clear)
      XCTAssertEqual(s.activeLayer?.video?.frames[20].pixel(x:2,y:2),.clear)
      let dir=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:dir)}
      let url=dir.appendingPathComponent("Owned blank footage.photato");try NativeArchive.encodeChunked(painted).write(to:url)
      XCTAssertEqual(try NativeArchive.readPaged(url),painted)
      await s.undo();XCTAssertEqual(s.activeLayer?.video?.frames.storedFrameCount,1)
      await s.redo();XCTAssertEqual(s.document,painted)
      await s.undo();await s.undo();XCTAssertEqual(s.document,before)
    }
  }
  @MainActor func testNativeBrushGesturePreviewCancelAndCommitKeepOtherFramesClear()async throws {
    let store=EditorStore(document:try model());defer{store.cancelBrush();store.renderTask?.cancel()}
    store.createBlankVideoLayer();store.renderTask?.cancel();let before=store.document
    store.tool = .brush;store.brush.size=3;store.brush.hardness=1;store.brush.color=Pixel(1,0,0)
    let id=try XCTUnwrap(store.document.activeLayerID)
    store.beginBrush(.init(x:3,y:3,time:0),zoom:1);store.extendBrush(.init(x:8,y:3,time:20))
    await store.brushPreviewTask?.value;await store.renderTask?.value
    XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertNotNil(store.brushGesture);store.cancelBrush();await store.renderTask?.value
    XCTAssertEqual(store.document,before)
    store.beginBrush(.init(x:3,y:3,time:0),zoom:1);store.extendBrush(.init(x:8,y:3,time:20))
    let command=try XCTUnwrap(store.brushGesture?.command);var expected=before;try command.apply(to:&expected)
    store.finishBrush();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,2)
    let frames=try XCTUnwrap(store.document.layers.first(where:{$0.id==id})?.video?.frames)
    XCTAssertEqual(frames.storedFrameCount,2);XCTAssertEqual(frames[18].pixel(x:4,y:3),.clear)
    XCTAssertEqual(frames[20].pixel(x:4,y:3),.clear);XCTAssertGreaterThan(frames[19].pixel(x:4,y:3).a,0)
    await store.undo();XCTAssertEqual(store.document,before)
  }
  @MainActor func testNativeAvailabilityAndMenuBindingKeepCapturedFactoryKey()throws {
    let h=PhotoshopMenuTests()
    try h.withMenus{app,menu in
      let item=try XCTUnwrap(h.allItems(menu).first{$0.identifier?.rawValue=="Layer > Video Layers > New Blank Video Layer"})
      XCTAssertEqual(item.action,#selector(AppDelegate.newBlankVideoLayer));XCTAssertEqual(item.keyEquivalent,"")
      XCTAssertTrue(app.responds(to:item.action!));XCTAssertEqual(AutomationCommand.definitions.count,267)
    }
    let s=EditorStore(document:try CraftDocument(width:12,height:8));defer{s.renderTask?.cancel()}
    XCTAssertFalse(s.canCreateBlankVideoLayer);let noTimeline=s.document;s.createBlankVideoLayer();XCTAssertEqual(s.document,noTimeline)
    var masked=try model();masked.layers[0].mask=try Surface(width:12,height:8,fill:.white)
    s.session=EditorSession(document:masked);XCTAssertTrue(s.canCreateBlankVideoLayer)
    s.geometryBusy=true;XCTAssertFalse(s.canCreateBlankVideoLayer);s.geometryBusy=false
    s.showAI=true;XCTAssertFalse(s.canCreateBlankVideoLayer);s.showAI=false
    s.maskEditingLayerID=s.activeLayer?.id;XCTAssertFalse(s.canCreateBlankVideoLayer);s.maskEditingLayerID=nil
    XCTAssertTrue(s.canCreateBlankVideoLayer)
    let state=s.videoState,properties=try XCTUnwrap(VideoAPI.stateSchema["properties"]as?[String:Any])
    XCTAssertEqual(state["canCreateBlankLayer"]as?Bool,true);XCTAssertTrue(Set(state.keys).isSubset(of:Set(properties.keys)))
  }
  @MainActor func testHTTPBlankCreationBrushEqualityTimingAndNative90Downloads()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      doc.store.session=EditorSession(document:try self.model());doc.store.renderTask?.cancel()
      try service.share(doc);let shared=try XCTUnwrap(service.shares.first),base="/v1/documents/\(shared.id)",before=doc.store.document
      let native=EditorStore(document:before);defer{native.renderTask?.cancel();doc.store.renderTask?.cancel()}
      native.createBlankVideoLayer();native.renderTask?.cancel()
      let status=try await h.edit(service,doc,"video.edit",["operation":"blankLayer"]);XCTAssertEqual(status,200)
      let id=try XCTUnwrap(doc.store.document.activeLayerID)
      var expected=native.document;expected.layers[expected.layers.count-1].id=id;expected.activeLayerID=id
      XCTAssertEqual(doc.store.document,expected);XCTAssertEqual(doc.store.session.undoStack.count,1)
      let clip=try XCTUnwrap((doc.store.videoState["clips"]as?[[String:Any]])?.first)
      let schema=try XCTUnwrap((VideoAPI.stateSchema["properties"]as?[String:Any])?["clips"]as?[String:Any])
      let allowed=try XCTUnwrap((schema["items"]as?[String:Any])?["properties"]as?[String:Any])
      XCTAssertTrue(Set(clip.keys).isSubset(of:Set(allowed.keys)));XCTAssertEqual(clip["sourceFrames"]as?Int,1200)
      XCTAssertEqual(clip["storedFrames"]as?Int,1);XCTAssertEqual(clip["sparseFrames"]as?Bool,true)
      let configured=try await h.edit(service,doc,"brush.configure",["brush":["size":3,"hardness":1,"color":["r":1,"g":0,"b":0,"a":1]]]);XCTAssertEqual(configured,200)
      let points:[StrokePoint]=[.init(x:3,y:3,time:0),.init(x:7,y:3,time:20)]
      var painted=doc.store.document;try Command.stroke(id,points,doc.store.brush).apply(to:&painted)
      let stroke=try await h.edit(service,doc,"paint.stroke",["target":"pixels","points":BrushAPI.json(points)]);XCTAssertEqual(stroke,200)
      XCTAssertEqual(doc.store.document,painted);XCTAssertEqual(doc.store.activeLayer?.video?.frames.storedFrameCount,2)
      let untouched=try XCTUnwrap(doc.store.activeLayer?.video?.frames[18]);XCTAssertEqual(untouched.pixel(x:3,y:3),.clear)
      let trimmed=try await h.edit(service,doc,"video.edit",["operation":"timing","layerID":id.uuidString,"startTime":0,"inFrame":600,"outFrame":1200,"frameRate":24]);XCTAssertEqual(trimmed,200)
      service.setDocumentTransfersEnabled(true)
      for version in [nil,"89"]as[String?] {
        let old=try await h.request(service,path:base+"/file.photato",headers:version.map{["X-Photato-Archive-Version":$0]} ?? [:])
        XCTAssertEqual(old.0.statusCode,422)
      }
      let file=try await h.request(service,path:base+"/file.photato",headers:["X-Photato-Archive-Version":"90"])
      XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decodePaged(file.1),doc.store.document)
    }
  }
  @MainActor func testHTTPBlankStrictParametersBusyStaleAndUnavailableContextDoNotEdit()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      try service.share(doc);let before=doc.store.document
      var status=try await h.edit(service,doc,"video.edit",["operation":"blankLayer"]);XCTAssertEqual(status,409);XCTAssertEqual(doc.store.document,before)
      var masked=try self.model();masked.layers[0].mask=try Surface(width:12,height:8,fill:.white)
      doc.store.session=EditorSession(document:masked);doc.store.renderTask?.cancel();let original=doc.store.document
      status=try await h.edit(service,doc,"video.edit",["operation":"blankLayer","name":"Unused"]);XCTAssertEqual(status,400)
      status=try await h.edit(service,doc,"video.edit",["operation":"blankLayer"],revision:"stale");XCTAssertEqual(status,409)
      doc.store.geometryBusy=true;status=try await h.edit(service,doc,"video.edit",["operation":"blankLayer"]);XCTAssertEqual(status,409);doc.store.geometryBusy=false
      doc.store.maskEditingLayerID=doc.store.activeLayer?.id;status=try await h.edit(service,doc,"video.edit",["operation":"blankLayer"]);XCTAssertEqual(status,409);doc.store.maskEditingLayerID=nil
      XCTAssertEqual(doc.store.document,original);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
}
