import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

@MainActor private final class SilentTimelinePlayer:TimelineAudioPlaying {
  var currentTime=0.0,isPlaying=false,looping=false,starts=0,stops=0
  func start(at seconds:Double,looping:Bool)throws{currentTime=seconds;self.looping=looping;isPlaying=true;starts+=1}
  func stop(){isPlaying=false;stops+=1}
}
final class TimelineAudioWorkflowTests:XCTestCase {
  var fixture:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/audio/owned-stereo.wav")}
  func model()throws->CraftDocument{var d=try CraftDocument(width:4,height:3);d.videoTimeline = .init(frameRate:4,durationFrames:8);return d}
  func audible()throws->CraftDocument{var d=try model();let source=try TimelineAudioIO.read(fixture).0;try Command.video(.audio(.importClip(nil,.init(name:"Owned soundtrack",source:source)))).apply(to:&d);return d}
  @MainActor func testNativeImportHistoryArchiveSourceIdentityAndGuards()async throws {
    let before=try model(),store=EditorStore(document:before),bytes=try Data(contentsOf:fixture);defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    try await store.importTimelineAudio(fixture)
    let after=store.document,clip=try XCTUnwrap(store.selectedAudioClip)
    XCTAssertEqual(clip.source.data,bytes);XCTAssertEqual(clip.startTime,0);XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.timelineAudioImportID);XCTAssertNil(store.geometryTask)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(after)),after)
    let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(store.document,before);XCTAssertNil(store.selectedAudioClipID)
    let redo=await store.redo();XCTAssertTrue(redo);XCTAssertEqual(store.document,after)
    store.geometryBusy=true;do{try await store.importTimelineAudio(fixture);XCTFail("Busy import succeeded")}catch{};store.geometryBusy=false
    XCTAssertEqual(store.document,after);XCTAssertEqual(try Data(contentsOf:fixture),bytes)
  }
  @MainActor func testAudioClockPlaybackLoopStopFailureAndPreparationCancellation()async throws {
    let source=try audible(),store=EditorStore(document:source),player=SilentTimelinePlayer();var mixed=Data()
    defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    store.timelineAudioFactory={data in mixed=data;return player}
    try store.selectVideoFrame(1);let before=store.document,history=store.session.undoStack.count
    try store.startVideoPlayback()
    for _ in 0..<500 where player.starts==0{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertEqual(player.starts,1);XCTAssertEqual(player.currentTime,0.25);XCTAssertFalse(store.timelineAudioPreparing)
    XCTAssertEqual(mixed,try TimelineAudioMixer.render(before)?.wave())
    player.currentTime=0.75
    for _ in 0..<500 where store.timelinePreviewVideoFrame != 3{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertEqual(store.timelinePreviewVideoFrame,3);XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,history)
    player.isPlaying=false
    for _ in 0..<500 where store.timelineTask != nil{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertNil(store.timelineTask);XCTAssertNil(store.timelineAudioPlayer);XCTAssertEqual(player.stops,1)
    store.editVideo(.loop(true));try store.startVideoPlayback()
    for _ in 0..<500 where player.starts<2{try await Task.sleep(for:.milliseconds(2))};XCTAssertTrue(player.looping)
    store.stopTimelinePlayback();XCTAssertFalse(player.isPlaying)
    store.timelineAudioFactory={_ in throw CraftError.unsupported("Owned unavailable output")}
    try store.startVideoPlayback()
    for _ in 0..<500 where store.timelineTask != nil{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertTrue(store.error?.contains("Owned unavailable output") == true);XCTAssertFalse(store.timelineAudioPreparing)
    store.error=nil;try store.startVideoPlayback();store.stopTimelinePlayback();try await Task.sleep(for:.milliseconds(30))
    XCTAssertNil(store.timelineTask);XCTAssertNil(store.timelineAudioPreparation);XCTAssertFalse(store.timelineAudioPreparing);XCTAssertNil(store.error)
  }
  @MainActor func testRealHTTPAudioImportEditMixArchiveAndReadOnlyView()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests(),input=try Data(contentsOf:fixture)
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      document.store.session=EditorSession(document:try model());try service.share(document);service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(id)/audio"
      let result=try await files.request(service,path:path,data:input,type:"audio/wav",headers:["X-Photato-Revision":service.revision(document.store),"X-Photato-Audio-Name":"Owned%20soundtrack","X-Photato-Audio-Start":"0.5"])
      XCTAssertEqual(result.0.statusCode,200,String(decoding:result.1,as:UTF8.self))
      let object=try XCTUnwrap(JSONSerialization.jsonObject(with:result.1) as? [String:Any]),audio=try XCTUnwrap(object["audio"] as? [String:Any])
      XCTAssertTrue(audio["importOperationID"] is NSNull);XCTAssertFalse(String(decoding:result.1,as:UTF8.self).contains(input.base64EncodedString()))
      let clip=try XCTUnwrap(document.store.selectedAudioClip);XCTAssertEqual(clip.source.data,input);XCTAssertEqual(clip.name,"Owned soundtrack");XCTAssertEqual(clip.startTime,0.5)
      let settings=TimelineAudioSettings(volume:0.5,fadeIn:0.25,fadeOut:0.25)
      var expected=document.store.document;try Command.video(.audio(.settings(clip.id,settings))).apply(to:&expected)
      let edited=try await helper.edit(service,document,"audio.edit",["operation":"clipSettings","clipID":clip.id.uuidString,"volume":0.5,"muted":false,"fadeIn":0.25,"fadeOut":0.25]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document,expected)
      let history=document.store.session.undoStack.count,revision=service.revision(document.store)
      let view=try await helper.edit(service,document,"audio.view",["clipID":clip.id.uuidString,"settingsVisible":true]);XCTAssertEqual(view,200);XCTAssertNotEqual(service.revision(document.store),revision);XCTAssertEqual(document.store.session.undoStack.count,history)
      let before=document.store.document,dirty=document.isDocumentEdited
      let wav=try await files.request(service,path:path+".wav");XCTAssertEqual(wav.0.statusCode,200);XCTAssertEqual(wav.1,try TimelineAudioMixer.render(before)?.wave())
      XCTAssertEqual(document.store.document,before);XCTAssertEqual(document.isDocumentEdited,dirty);XCTAssertEqual(document.store.session.undoStack.count,history)
      let file=try await files.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"56"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),before)
      let old=try await files.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"55"]);XCTAssertEqual(old.0.statusCode,422)
      let undo=await document.store.undo();XCTAssertTrue(undo);XCTAssertEqual(document.store.selectedAudioClip?.settings,.init())
      let redo=await document.store.redo();XCTAssertTrue(redo);XCTAssertEqual(document.store.document,before)
    }
  }
  @MainActor func testAPIStaleBusyInvalidDisabledAndSanitizedCapabilities()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests(),input=try Data(contentsOf:fixture)
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      document.store.session=EditorSession(document:try audible());try service.share(document);service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(service.shares.first?.id),before=document.store.document,history=document.store.session.undoStack.count
      let path="/v1/documents/\(id)/audio",clip=try XCTUnwrap(before.videoTimeline?.audioTracks?.first?.clips.first)
      let stale=try await files.request(service,path:path,data:input,type:"audio/wav",headers:["X-Photato-Revision":"old"]);XCTAssertEqual(stale.0.statusCode,409)
      let invalid=try await helper.edit(service,document,"audio.edit",["operation":"trim","clipID":clip.id.uuidString,"startTime":0,"sourceIn":0.9,"sourceOut":0.1]);XCTAssertEqual(invalid,422)
      let extra=try await helper.edit(service,document,"audio.edit",["operation":"deleteClip","clipID":clip.id.uuidString,"volume":0.5]);XCTAssertEqual(extra,400)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"audio.edit",["operation":"deleteClip","clipID":clip.id.uuidString]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let corrupt=try await files.request(service,path:path,data:Data("broken".utf8),type:"audio/wav",headers:["X-Photato-Revision":service.revision(document.store)]);XCTAssertEqual(corrupt.0.statusCode,422)
      service.setDocumentTransfersEnabled(false)
      let disabled=try await files.request(service,path:path+".wav");XCTAssertEqual(disabled.0.statusCode,403)
      XCTAssertEqual(document.store.document,before);XCTAssertEqual(document.store.session.undoStack.count,history);XCTAssertNil(document.store.timelineAudioImportID);XCTAssertFalse(document.store.geometryBusy)
      XCTAssertEqual(TimelineAudioAPI.commands,["audio.edit","audio.view","audio.import.cancel"])
      let video=try JSONSerialization.data(withJSONObject:document.store.videoState)
      XCTAssertFalse(String(decoding:video,as:UTF8.self).contains(input.base64EncodedString()))
    }
  }
  @MainActor func testActiveHTTPImportCancellationAndPermissionRevocation()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    let input=try TimelinePCM(samples:Array(repeating:0.25,count:48_000*2*20)).wave()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      document.store.session=EditorSession(document:try model());try service.share(document)
      let id=try XCTUnwrap(service.shares.first?.id),before=document.store.document
      for revoke in [false,true] {
        service.setDocumentTransfersEnabled(true)
        let revision=service.revision(document.store)
        let task=Task{try await files.request(service,path:"/v1/documents/\(id)/audio",data:input,type:"audio/wav",headers:["X-Photato-Revision":revision])}
        for _ in 0..<500 where document.store.timelineAudioImportID==nil{try await Task.sleep(for:.milliseconds(2))}
        let operation=try XCTUnwrap(document.store.timelineAudioImportID)
        if revoke{service.setDocumentTransfersEnabled(false)}else{let result=try await helper.edit(service,document,"audio.import.cancel",["operationID":operation.uuidString]);XCTAssertEqual(result,200)}
        let result=try await task.value;XCTAssertEqual(result.0.statusCode,409,String(decoding:result.1,as:UTF8.self))
        XCTAssertEqual(document.store.document,before);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertFalse(document.store.geometryBusy);XCTAssertNil(document.store.timelineAudioImportID);XCTAssertTrue(service.audioImportOperations.isEmpty)
      }
    }
  }
  @MainActor func testReadOnlyMixCancellationOnTransferAndShareRevocation()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      var source=try audible();source.videoTimeline?.durationFrames=720
      document.store.session=EditorSession(document:source);try service.share(document)
      let id=try XCTUnwrap(service.shares.first?.id),dirty=document.isDocumentEdited
      for revokeShare in [false,true] {
        service.setDocumentTransfersEnabled(true)
        let task=Task{try await files.request(service,path:"/v1/documents/\(id)/audio.wav")}
        for _ in 0..<500 where service.audioPreviewWorkers[id]==nil{try await Task.sleep(for:.milliseconds(2))}
        XCTAssertNotNil(service.audioPreviewWorkers[id])
        if revokeShare{service.revoke(id)}else{service.setDocumentTransfersEnabled(false)}
        let response=try await task.value;XCTAssertEqual(response.0.statusCode,409)
        XCTAssertFalse(service.previewBusy);XCTAssertTrue(service.audioPreviewWorkers.isEmpty)
        XCTAssertEqual(document.store.document,source);XCTAssertEqual(document.isDocumentEdited,dirty);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testNativeAudioTrackMoveTrimCancelAndDelete()async throws {
    let store=EditorStore(document:try audible());defer{store.renderTask?.cancel()}
    store.newAudioTrack();let helper=VideoTransitionWorkflowTests()
    let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:320),styleMask:[],backing:.buffered,defer:false);window.isReleasedWhenClosed=false
    let view=VideoTrackView(frame:window.contentLayoutRect);view.store=store;window.contentView=view;defer{view.finish(cancelled:true);window.contentView=nil;window.close()}
    let layout=try XCTUnwrap(view.layout),clip=try XCTUnwrap(store.document.videoTimeline?.audioTracks?.first?.clips.first),row=try XCTUnwrap(layout.rows.firstIndex{$0.audio?.clips.first?.id==clip.id}),rect=layout.audioRect(clip,row:row),p=NSPoint(x:rect.midX,y:rect.midY)
    let moved=NSPoint(x:p.x+60,y:p.y+VideoTrackLayout.rowHeight)
    view.mouseDown(with:try helper.event(.leftMouseDown,p,view:view));view.mouseDragged(with:try helper.event(.leftMouseDragged,moved,view:view));view.mouseUp(with:try helper.event(.leftMouseUp,moved,view:view))
    XCTAssertNil(store.error);XCTAssertTrue(store.document.videoTimeline!.audioTracks![0].clips.isEmpty);XCTAssertEqual(store.document.videoTimeline!.audioTracks![1].clips[0].startTime,1)
    let undo=await store.undo();XCTAssertTrue(undo)
    XCTAssertEqual(store.selectedAudioTrackID,store.document.videoTimeline?.audioTracks?.first?.id)
    let edge=NSPoint(x:rect.maxX-2,y:rect.midY),trim=NSPoint(x:edge.x-30,y:edge.y)
    view.mouseDown(with:try helper.event(.leftMouseDown,edge,view:view));view.mouseDragged(with:try helper.event(.leftMouseDragged,trim,view:view));view.mouseUp(with:try helper.event(.leftMouseUp,trim,view:view))
    XCTAssertEqual(store.selectedAudioClip?.duration,0.5);let before=store.document
    view.begin(.audioMove(clip.id),point:p);view.gesture?.point=moved;view.finish(cancelled:true);XCTAssertEqual(store.document,before);XCTAssertFalse(store.geometryBusy)
    store.showAudioControls=true;store.editVideo(.audio(.removeClip(clip.id)));XCTAssertNil(store.selectedAudioClipID);XCTAssertFalse(store.showAudioControls)
  }
  @MainActor func testAudioTimelineOffscreenLayout()async throws {
    let store=EditorStore(document:try audible());store.videoTimelinePixelsPerSecond=240;defer{store.renderTask?.cancel()}
    let host=NSHostingView(rootView:VideoTimelinePanel(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:320)
    let window=NSWindow(contentRect:host.frame,styleMask:[],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil;window.close()}
    host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.width,1100)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_AUDIO_OUTPUT_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:root).appendingPathComponent("audio-timeline.png"))}
  }
}
