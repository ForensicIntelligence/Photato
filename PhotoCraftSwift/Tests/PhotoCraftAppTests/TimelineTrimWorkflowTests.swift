import AppKit
import XCTest
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class TimelineTrimWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    d.videoTimeline = .init(frameRate:4,durationFrames:16);d.videoTimeline!.workArea = .init(startFrame:3,endFrame:11)
    d.layers[0].videoTiming = .init(startTime:0,duration:4);return d
  }
  @MainActor func testNativeTrimUndoAndTracksStayInsideOutputRange()async throws {
    let d=try fixture(),store=EditorStore(document:d);defer{store.renderTask?.cancel()}
    XCTAssertTrue(store.canTrimTimelineToWorkArea);store.trimTimelineToWorkArea()
    XCTAssertEqual(store.document.videoTimeline?.durationFrames,8);XCTAssertFalse(store.canTrimTimelineToWorkArea)
    let layout=VideoTrackLayout(document:store.document,pixelsPerSecond:80),rect=layout.rect(store.document.layers[0],row:0)
    XCTAssertEqual(rect.minX,VideoTrackLayout.labelWidth);XCTAssertEqual(rect.maxX,VideoTrackLayout.labelWidth+160)
    let undone=await store.undo();XCTAssertTrue(undone);XCTAssertEqual(store.document,d)
    let redone=await store.redo();XCTAssertTrue(redone);XCTAssertEqual(store.document.minimumArchiveVersion,58)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TRIM_OUTPUT_DIR"] {
      let host=NSHostingView(rootView:VideoTimelinePanel(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:320)
      let window=NSWindow(contentRect:host.frame,styleMask:[],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil;window.close()}
      host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));host.layoutSubtreeIfNeeded()
      if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:root).appendingPathComponent("trimmed-timeline.png"))}
    }
  }
  @MainActor func testAPITrimMatchesNativeStatePersistenceAndGuards()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document);service.setDocumentTransfersEnabled(true)
      var expected=original;try Command.video(.workspace(.trimToWorkArea)).apply(to:&expected)
      let extra=try await helper.edit(service,document,"video.trimWorkArea",["extra":true]);XCTAssertEqual(extra,400)
      let stale=try await helper.edit(service,document,"video.trimWorkArea",[:],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"video.trimWorkArea",[:]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let result=try await helper.edit(service,document,"video.trimWorkArea",[:]);XCTAssertEqual(result,200);XCTAssertEqual(document.store.document,expected)
      let id=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(id)/file.photato"
      let old=try await files.request(service,path:path,headers:["X-Photato-Archive-Version":"57"]);XCTAssertEqual(old.0.statusCode,422)
      let current=try await files.request(service,path:path,headers:["X-Photato-Archive-Version":"58"]);XCTAssertEqual(current.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(current.1),expected)
      let undone=await document.store.undo();XCTAssertTrue(undone);XCTAssertEqual(document.store.document,original)
    }
  }
  @MainActor func testCroppedEdgeDraggingAndSignedAPICommandsMatch()throws {
    var d=try fixture()
    let data=try TimelinePCM(samples:[Float](repeating:0,count:384000)).wave()
    let audio=TimelineAudioClip(name:"Sound",source:.init(data:data,duration:4))
    d.videoTimeline!.audioTracks=[.init(name:"Track",clips:[audio])]
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    let store=EditorStore(document:d);defer{store.renderTask?.cancel()}
    let id=d.layers[0].id
    var right=d;try Command.video(store.trimVideoClip(id,leading:false,seconds:-0.25)).apply(to:&right)
    XCTAssertEqual(right.layers[0].videoTiming?.startTime,-0.75);XCTAssertEqual(right.layers[0].videoTiming?.duration,2.5)
    var left=d;try Command.video(store.trimVideoClip(id,leading:true,seconds:0.25)).apply(to:&left)
    XCTAssertEqual(left.layers[0].videoTiming?.startTime,0.25);XCTAssertEqual(left.layers[0].videoTiming?.duration,3)
    var sound=d;try Command.video(.audio(store.audioTrimCommand(audio.id,leading:false,delta:-0.25))).apply(to:&sound)
    XCTAssertEqual(sound.videoTimeline?.audioTracks?.first?.clips.first?.sourceOut,2.5)
    let videoCommand=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"video.edit","revision":"test","parameters":["operation":"stillTiming","layerID":id.uuidString,"startTime":-0.75,"duration":2.5]]))
    var api=d;try videoCommand.videoCommand().apply(to:&api);XCTAssertEqual(api,right)
    let audioCommand=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"audio.edit","revision":"test","parameters":["operation":"trim","clipID":audio.id.uuidString,"startTime":-0.75,"sourceIn":0,"sourceOut":2.5]]))
    api=d;try audioCommand.timelineAudioCommand().apply(to:&api);XCTAssertEqual(api,sound)
    var untrimmed=d;untrimmed.videoTimeline!.trimmedToWorkArea=nil
    XCTAssertThrowsError(try videoCommand.videoCommand().apply(to:&untrimmed))
  }
  func testTrimmedSequenceUsesOutputDurationAndPreservedPixels()throws {
    var d=try exportFixture()
    try Command.video(.workspace(.trimToWorkArea)).apply(to:&d)
    let output=try ImageSequenceExport.render(d,options:.init())
    XCTAssertEqual(output.files.filter{$0.name.hasSuffix(".png")}.count,5)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TRIM_OUTPUT_DIR"] {
      try output.zip().write(to:URL(fileURLWithPath:root).appendingPathComponent("trimmed-sequence.zip"))
    }
  }
  func exportFixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    var a=Layer(name:"Red",content:.fill(Pixel(1,0,0))),b=Layer(name:"Blue",content:.fill(Pixel(0,0,1)))
    a.videoTiming = .init(startTime:0,duration:1);b.videoTiming = .init(startTime:1,duration:1)
    d.layers=[a,b];d.activeLayerID=b.id;d.videoTimeline = .init(frameRate:8,durationFrames:16)
    try Command.video(.transition(.set(.init(layerID:b.id,previousLayerID:a.id,kind:.crossFade,duration:1)))).apply(to:&d)
    d.videoTimeline!.workArea = .init(startFrame:6,endFrame:11);return d
  }
}
