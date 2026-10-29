import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VideoTransitionWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    var a=Layer(name:"Opening — red",content:.fill(Pixel(1,0,0))),b=Layer(name:"Closing — blue",content:.fill(Pixel(0,0,1)))
    a.videoTiming = .init(startTime:0,duration:1);b.videoTiming = .init(startTime:1,duration:1)
    d.layers=[a,b];d.activeLayerID=b.id;d.videoTimeline = .init(frameRate:4,durationFrames:8);return d
  }
  func transition(_ d:CraftDocument)->VideoTransition{.init(layerID:d.layers[1].id,previousLayerID:d.layers[0].id,kind:.crossFade,duration:1)}
  @MainActor func testPreviewExportAndPlaybackUseTheSameTransition()async throws {
    let model=try fixture(),store=EditorStore(document:model);defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    store.editVideo(.transition(.set(transition(model))));XCTAssertNil(store.error)
    for frame in 0..<8 {
      try store.selectVideoFrame(frame)
      XCTAssertEqual(try Renderer.composite(store.previewDocument),try Renderer.composite(store.document))
      if let root=ProcessInfo.processInfo.environment["PHOTATO_TRANSITION_OUTPUT_DIR"] {
        try DocumentIO.encode(store.document,format:.png).write(to:URL(fileURLWithPath:root).appendingPathComponent("crossfade-\(frame).png"))
      }
    }
    let edited=store.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edited)),edited)
    let files=try ImageSequenceExport.render(edited,options:.init(firstFrame:0,lastFrame:7));XCTAssertEqual(files.files.count,9)
    try store.selectVideoFrame(2);let before=store.document,history=store.session.undoStack.count
    try store.startVideoPlayback();try await Task.sleep(for:.milliseconds(300))
    XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,history)
    if let frame=store.timelinePreviewVideoFrame{XCTAssertEqual(try Renderer.composite(store.previewDocument),try Renderer.composite(before.videoDocument(at:frame)))}
    store.stopTimelinePlayback()
  }
  @MainActor func testAPITransitionSetUpdateDeleteStateArchiveAndGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let model=try fixture();document.store.session=EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let params:[String:Any]=["operation":"transition","layerID":model.layers[1].id.uuidString,"previousLayerID":model.layers[0].id.uuidString,"kind":"crossFade","edge":"start","duration":1]
      let code=try await helper.edit(service,document,"video.edit",params);XCTAssertEqual(code,200)
      let transition=try XCTUnwrap(document.store.document.videoTimeline?.transitions?.first)
      let view=try await helper.edit(service,document,"video.view",["frame":4,"pixelsPerSecond":120,"transitionID":transition.id.uuidString]);XCTAssertEqual(view,200)
      XCTAssertEqual(document.store.videoState["pixelsPerSecond"] as? Double,120);XCTAssertEqual(document.store.videoSelectedTransitionID,transition.id)
      let p=try Renderer.composite(document.store.previewDocument).pixel(x:0,y:0);XCTAssertEqual(p.r,0.5,accuracy:0.00001);XCTAssertEqual(p.b,0.5,accuracy:0.00001);XCTAssertEqual(p.a,1)
      let before=document.store.document,undoCount=document.store.session.undoStack.count
      var bad=params;bad["color"]=["r":1,"g":0,"b":0,"a":1]
      let invalid=try await helper.edit(service,document,"video.edit",bad);XCTAssertEqual(invalid,422)
      let irrelevant=try await helper.edit(service,document,"video.edit",["operation":"removeTransition","transitionID":transition.id.uuidString,"duration":1]);XCTAssertEqual(irrelevant,400)
      let stale=try await helper.edit(service,document,"video.edit",params,revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"video.edit",params);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      XCTAssertEqual(document.store.document,before);XCTAssertEqual(document.store.session.undoStack.count,undoCount)
      let shareID=try XCTUnwrap(service.shares.first?.id)
      let file=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"55"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),before)
      let old=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"54"]);XCTAssertEqual(old.0.statusCode,422)
      var update=params;update["transitionID"]=transition.id.uuidString;update["duration"]=0.5
      let updated=try await helper.edit(service,document,"video.edit",update);XCTAssertEqual(updated,200);XCTAssertEqual(document.store.document.videoTimeline?.transitions?.count,1)
      let deleted=try await helper.edit(service,document,"video.edit",["operation":"removeTransition","transitionID":transition.id.uuidString]);XCTAssertEqual(deleted,200);XCTAssertNil(document.store.videoSelectedTransitionID)
      let undo=await document.store.undo();XCTAssertTrue(undo);XCTAssertEqual(document.store.document.videoTimeline?.transitions?.first?.duration,0.5)
      let history=document.store.session.undoStack.count,prior=service.revision(document.store)
      document.store.videoTimelinePixelsPerSecond=90;XCTAssertNotEqual(service.revision(document.store),prior);XCTAssertEqual(document.store.session.undoStack.count,history)
    }
  }
  @MainActor func testTransitionEditorUsesSelectedClipAndClearsRemovedSelection()throws {
    let model=try fixture(),store=EditorStore(document:model);defer{store.renderTask?.cancel()}
    let t=transition(model);store.editVideo(.transition(.set(t)))
    store.select(model.layers[0].id);store.videoSelectedTransitionID=t.id
    let editor=VideoTransitionControls(store:store)
    XCTAssertEqual(editor.active?.id,t.layerID)
    XCTAssertEqual(editor.previous?.id,t.previousLayerID)
    store.editVideo(.transition(.remove(t.id)));XCTAssertNil(store.videoSelectedTransitionID)
    store.videoTransitionEditorVisible=true;store.editVideo(.remove)
    XCTAssertFalse(store.videoTransitionEditorVisible);XCTAssertNil(store.document.videoTimeline)
  }
  @MainActor func event(_ type:NSEvent.EventType,_ point:NSPoint,view:NSView,clicks:Int=1)throws->NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with:type,location:view.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:view.window?.windowNumber ?? 0,context:nil,eventNumber:0,clickCount:clicks,pressure:1))
  }
  @MainActor func testNativeTrackClickDragTrimPlayheadAndCancel()async throws {
    let store=EditorStore(document:try fixture());defer{store.renderTask?.cancel()}
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:250),styleMask:[],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false
    let view=VideoTrackView(frame:NSRect(x:0,y:0,width:1100,height:250));view.store=store;window.contentView=view;defer{view.finish(cancelled:true);window.contentView=nil;window.close()}
    let id=store.document.layers[0].id,originalOrder=store.document.layers.map(\.id)
    let layout=try XCTUnwrap(view.layout),row=try XCTUnwrap(layout.rows.firstIndex{$0.clips.contains{$0.id==id}}),rect=layout.rect(store.document.layers[0],row:row),point=NSPoint(x:rect.midX,y:rect.midY)
    view.mouseDown(with:try event(.leftMouseDown,point,view:view));XCTAssertTrue(store.geometryBusy)
    view.mouseUp(with:try event(.leftMouseUp,point,view:view));XCTAssertFalse(store.geometryBusy);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(store.document.layers.map(\.id),originalOrder)
    view.mouseDown(with:try event(.leftMouseDown,point,view:view))
    let moved=NSPoint(x:point.x+60,y:point.y)
    view.mouseDragged(with:try event(.leftMouseDragged,moved,view:view));view.mouseUp(with:try event(.leftMouseUp,moved,view:view))
    XCTAssertNil(store.error);XCTAssertEqual(store.document.layers.first{$0.id==id}?.videoTiming?.startTime,1);XCTAssertEqual(store.document.layers.map(\.id),originalOrder);XCTAssertEqual(store.session.undoStack.count,1)
    let undo=await store.undo();XCTAssertTrue(undo)
    let edge=NSPoint(x:rect.maxX-2,y:rect.midY),trimmed=NSPoint(x:edge.x-30,y:edge.y)
    view.mouseDown(with:try event(.leftMouseDown,edge,view:view));view.mouseDragged(with:try event(.leftMouseDragged,trimmed,view:view));view.mouseUp(with:try event(.leftMouseUp,trimmed,view:view))
    XCTAssertEqual(store.document.layers.first{$0.id==id}?.videoTiming?.duration,0.5)
    let current=store.document
    view.mouseDown(with:try event(.leftMouseDown,NSPoint(x:VideoTrackLayout.labelWidth+60,y:10),view:view));XCTAssertEqual(store.document.videoTimeline?.currentFrame,4)
    view.finish(cancelled:true);XCTAssertEqual(store.document,current);XCTAssertFalse(store.geometryBusy)
    let selected=store.document.activeLayerID!
    view.begin(.move(selected),point:point);view.gesture?.point=moved;view.finish(cancelled:true);XCTAssertEqual(store.document,current)
  }
  @MainActor func testNativeTransitionDurationGestureAndWindowRemovalReleaseBusy()throws {
    let model=try fixture(),store=EditorStore(document:model);defer{store.renderTask?.cancel()}
    let t=transition(model);store.editVideo(.transition(.set(t)))
    let view=VideoTrackView(frame:NSRect(x:0,y:0,width:1100,height:250));view.store=store
    view.begin(.transition(t.id,false),point:.zero);view.gesture?.point=NSPoint(x:15,y:0);view.finish(cancelled:false)
    XCTAssertEqual(store.document.videoTimeline?.transitions?.first?.duration,1.5);XCTAssertFalse(store.geometryBusy)
    view.begin(.move(model.layers[0].id),point:.zero);XCTAssertTrue(store.geometryBusy);view.viewWillMove(toWindow:nil);XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.videoTimelineGestureID)
  }
  @MainActor func testGraphicalTimelineOffscreenLayoutAndCapture()async throws {
    var model=try fixture();let ids=model.layers.map(\.id)
    try Command.video(.arrange(.group("Video Group 1",ids))).apply(to:&model)
    let t=VideoTransition(layerID:ids[1],previousLayerID:ids[0],kind:.crossFade,duration:1);try Command.video(.transition(.set(t))).apply(to:&model)
    let store=EditorStore(document:model);store.videoTimelinePixelsPerSecond=240;store.videoSelectedTransitionID=t.id;defer{store.renderTask?.cancel()}
    let host=NSHostingView(rootView:VideoTimelinePanel(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:320)
    let window=NSWindow(contentRect:host.frame,styleMask:[],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil;window.close()}
    host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.width,1100)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TRANSITION_OUTPUT_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
      host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:root).appendingPathComponent("timeline-offscreen.png"))
    }
  }
}
