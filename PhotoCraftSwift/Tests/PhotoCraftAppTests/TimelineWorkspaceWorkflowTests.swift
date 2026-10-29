import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

@MainActor private final class WorkspaceAudioPlayer:TimelineAudioPlaying {
  var currentTime=0.0,isPlaying=false,looping=false,starts=0
  func start(at seconds:Double,looping:Bool)throws{currentTime=seconds;self.looping=looping;isPlaying=true;starts+=1}
  func stop(){isPlaying=false}
}
final class TimelineWorkspaceWorkflowTests:XCTestCase {
  func document()throws->CraftDocument {
    let frames=try [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)].enumerated().map{i,p in
      var s=try Surface(width:12,height:4,fill:.clear);for y in 0..<4{for x in i*4..<i*4+4{s.setPixel(x:x,y:y,p)}};return s
    }
    var d=try CraftDocument(width:12,height:4);d.layers[0].video=VideoClip(frames:frames,frameRate:4);d.videoTimeline = .init(frameRate:4,durationFrames:3);try d.selectVideoFrame(1);return d
  }
  @MainActor func testNativeWorkAreaGesturesUndoCancelAndPlayheadCommands()async throws {
    var d=try document();d.videoTimeline!.durationFrames=12;let store=EditorStore(document:d);store.videoTimelinePixelsPerSecond=80;defer{store.renderTask?.cancel()}
    store.editVideo(.workspace(.workArea(.init(startFrame:2,endFrame:8))))
    let before=store.document,history=store.session.undoStack.count,view=VideoTrackView(frame:NSRect(x:0,y:0,width:900,height:200));view.store=store
    view.begin(.workArea(-1),point:.zero);view.gesture?.point=NSPoint(x:20,y:0);XCTAssertEqual(view.workAreaPreview(),.init(startFrame:3,endFrame:8));view.finish(cancelled:false)
    XCTAssertEqual(store.document.videoTimeline?.workArea,.init(startFrame:3,endFrame:8));XCTAssertEqual(store.session.undoStack.count,history+1);XCTAssertFalse(store.geometryBusy)
    let undone=await store.undo();XCTAssertTrue(undone);XCTAssertEqual(store.document,before)
    view.begin(.workArea(0),point:.zero);view.gesture?.point=NSPoint(x:80,y:0);XCTAssertEqual(view.workAreaPreview(),.init(startFrame:6,endFrame:12));view.finish(cancelled:true);XCTAssertEqual(store.document,before)
    view.begin(.workArea(1),point:.zero);view.gesture?.point=NSPoint(x:-2000,y:0);view.finish(cancelled:false);XCTAssertEqual(store.document.videoTimeline?.workArea,.init(startFrame:2,endFrame:3))
    try store.selectVideoFrame(6);store.setWorkAreaStartAtPlayhead();XCTAssertEqual(store.document.videoTimeline?.workArea,.init(startFrame:6,endFrame:7))
    try store.selectVideoFrame(2);store.setWorkAreaEndAtPlayhead();XCTAssertEqual(store.document.videoTimeline?.workArea,.init(startFrame:2,endFrame:3))
  }
  @MainActor func testPreviewSurfaceExcludesGhostsAndSequenceWorkArea()async throws {
    var model=try document();model.videoTimeline!.onionSkin = .init(enabled:true,blendMode:.normal);model.videoTimeline!.workArea = .init(startFrame:1,endFrame:3)
    let store=EditorStore(document:model);defer{store.renderTask?.cancel()};store.render();await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.surface?.pixel(x:1,y:1),.clear)
    let image=try RasterIO.surface(XCTUnwrap(store.image));XCTAssertEqual(image.pixel(x:1,y:1).r,1);XCTAssertEqual(image.pixel(x:1,y:1).a,128.0/255,accuracy:0.00001)
    store.timelinePreviewVideoFrame=0;store.render(isAnimationPlayback:true);await store.renderTask?.value
    let playing=try RasterIO.surface(XCTUnwrap(store.image));XCTAssertEqual(playing.pixel(x:1,y:1),Pixel(1,0,0));XCTAssertEqual(playing.pixel(x:5,y:1).a,128.0/255,accuracy:0.00001);XCTAssertEqual(playing.pixel(x:9,y:1),.clear)
    store.timelinePreviewVideoFrame=nil;store.render();await store.renderTask?.value
    let sequence=try await store.encodedImageSequence(.init(useWorkArea:true),archive:true);XCTAssertEqual(sequence.files.count,3)
    let first=try RasterIO.read(sequence.files[0].data);XCTAssertEqual(try Renderer.composite(first).pixel(x:1,y:1),.clear)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_WORKSPACE_OUTPUT_DIR"] {
      let url=URL(fileURLWithPath:root);try sequence.archive!.write(to:url.appendingPathComponent("work-area.zip"))
      try AutomationService.png(model).write(to:url.appendingPathComponent("ordinary.png"));try AutomationService.png(model,onionSkin:true).write(to:url.appendingPathComponent("onion.png"))
    }
    XCTAssertEqual(store.document,model);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testRangedAudioPlaybackUsesRelativeClockAndPreservesDocument()async throws {
    var model=try document();let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/audio/owned-stereo.wav")
    let source=try TimelineAudioIO.read(url).0;try Command.video(.audio(.importClip(nil,.init(name:"Soundtrack",source:source)))).apply(to:&model)
    model.videoTimeline!.workArea = .init(startFrame:1,endFrame:3);try model.selectVideoFrame(0)
    let store=EditorStore(document:model),player=WorkspaceAudioPlayer();var wave=Data();defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    store.timelineAudioFactory={wave=$0;return player};try store.startVideoPlayback()
    for _ in 0..<500 where player.starts==0{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertEqual(player.currentTime,0);XCTAssertTrue(player.looping);XCTAssertEqual(try TimelineAudioIO.decode(wave).1.frames,24000)
    player.currentTime=0.25
    for _ in 0..<500 where store.timelinePreviewVideoFrame != 2{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertEqual(store.timelinePreviewVideoFrame,2);XCTAssertEqual(store.document,model);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.stopTimelinePlayback();XCTAssertNil(store.timelineTask)
  }
  @MainActor func testAPIWorkspacePreviewArchiveAndValidation()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      document.store.session=EditorSession(document:try self.document());try service.share(document);service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(id)"
      let area=try await helper.edit(service,document,"video.workArea",["operation":"set","startFrame":1,"endFrame":3]);XCTAssertEqual(area,200)
      let settings=OnionSkinSettings(enabled:true,blendMode:.normal)
      let onion=try await helper.edit(service,document,"video.onionSkin",["settings":BrushAPI.json(settings)]);XCTAssertEqual(onion,200)
      let model=document.store.document,history=document.store.session.undoStack.count
      let preview=try await files.request(service,path:path+"/onion-preview.png");XCTAssertEqual(preview.0.statusCode,200);XCTAssertEqual(preview.1,try AutomationService.png(model,onionSkin:true))
      let ordinary=try await files.request(service,path:path+"/preview.png");XCTAssertEqual(ordinary.1,try AutomationService.png(model));XCTAssertNotEqual(ordinary.1,preview.1)
      let native=try await files.request(service,path:path+"/file.photato",headers:["X-Photato-Archive-Version":"57"]);XCTAssertEqual(native.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(native.1),model)
      let old=try await files.request(service,path:path+"/file.photato",headers:["X-Photato-Archive-Version":"56"]);XCTAssertEqual(old.0.statusCode,422)
      let invalid=try await helper.edit(service,document,"video.workArea",["operation":"set","startFrame":2,"endFrame":1]);XCTAssertEqual(invalid,422)
      let extra=try await helper.edit(service,document,"video.workArea",["operation":"reset","startFrame":0]);XCTAssertEqual(extra,400)
      var malformed=try XCTUnwrap(BrushAPI.json(settings) as? [String:Any]);malformed["extra"]=1
      let bad=try await helper.edit(service,document,"video.onionSkin",["settings":malformed]);XCTAssertEqual(bad,400)
      malformed.removeValue(forKey:"extra");malformed["enabled"]="yes"
      let wrongType=try await helper.edit(service,document,"video.onionSkin",["settings":malformed]);XCTAssertEqual(wrongType,400)
      malformed["enabled"]=true;malformed["minimumOpacity"]=0.8
      let inverted=try await helper.edit(service,document,"video.onionSkin",["settings":malformed]);XCTAssertEqual(inverted,422)
      let stale=try await helper.edit(service,document,"video.workArea",["operation":"reset"],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"video.workArea",["operation":"reset"]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let conflict=try await helper.edit(service,document,"video.render",["codec":"h264","useWorkArea":true,"firstFrame":0]);XCTAssertEqual(conflict,400)
      let sequence=try await helper.request(service,path:path+"/commands",body:["command":"sequence.export","revision":service.revision(document.store),"parameters":["format":"png","useWorkArea":true]])
      XCTAssertEqual(sequence.0.statusCode,200);XCTAssertEqual(sequence.1,try ImageSequenceExport.render(model,options:.init(useWorkArea:true)).zip())
      XCTAssertEqual(document.store.document,model);XCTAssertEqual(document.store.session.undoStack.count,history)
      let undo=await document.store.undo();XCTAssertTrue(undo);XCTAssertNil(document.store.document.videoTimeline?.onionSkin)
      let redo=await document.store.redo();XCTAssertTrue(redo);XCTAssertEqual(document.store.document,model)
    }
  }
  @MainActor func testWorkspaceTimelineAndExportControlsOffscreen()async throws {
    var model=try document();model.videoTimeline!.workArea = .init(startFrame:1,endFrame:3);model.videoTimeline!.onionSkin = .init(enabled:true)
    let store=EditorStore(document:model);store.videoTimelinePixelsPerSecond=400;defer{store.renderTask?.cancel()}
    let host=NSHostingView(rootView:VideoTimelinePanel(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:320)
    let window=NSWindow(contentRect:host.frame,styleMask:[],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil;window.close()}
    host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.width,1100)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_WORKSPACE_OUTPUT_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:root).appendingPathComponent("workspace-timeline.png"))}
    let controls=VideoRenderAccessory(document:model);controls.workArea.state = .on;controls.changed();XCTAssertFalse(controls.first.isEnabled);XCTAssertFalse(controls.last.isEnabled)
    let options=try controls.options();XCTAssertTrue(options.useWorkArea);XCTAssertNil(options.lastFrame);XCTAssertEqual(try options.plan(for:model).sourceStart,0.25)
  }
}
