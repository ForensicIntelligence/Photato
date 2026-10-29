import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

@MainActor private final class ConversionAudioPlayer:TimelineAudioPlaying {
  var currentTime=0.0,isPlaying=false,looping=false
  func start(at seconds:Double,looping:Bool)throws {currentTime=seconds;self.looping=looping;isPlaying=true}
  func stop(){isPlaying=false}
}
final class FrameTimelineConversionWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    d.layers[0].content = .raster(try Surface(width:2,height:2,fill:Pixel(1,0,0)))
    var a=FrameAnimation(layers:d.layers);a.frames[0].delay=0.25;a.loopCount=3
    var moved=AnimationFrame(layers:d.layers,delay:0.5);moved.layers[0].x=2;moved.layers[0].y=1;moved.layers[0].opacity=0.5
    var hidden=AnimationFrame(layers:d.layers,delay:0.25);hidden.layers[0].visible=false
    a.frames += [moved,hidden];d.animation=a;return d
  }
  @MainActor func testNativeConversionUndoRedoAndOffscreenTimeline()async throws {
    let original=try fixture(),store=EditorStore(document:original);defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    store.editTimeline(.convertToVideo(8));await store.geometryTask?.value;XCTAssertNil(store.error)
    let converted=store.document
    XCTAssertNil(converted.animation);XCTAssertEqual(converted.videoTimeline?.durationFrames,8)
    XCTAssertEqual(converted.videoTimeline?.finiteLoopCount,3);XCTAssertEqual(store.session.undoStack.count,1)
    let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(store.document,original)
    let redo=await store.redo();XCTAssertTrue(redo);XCTAssertEqual(store.document,converted)
    store.geometryBusy=true;store.editTimeline(.convertToVideo(8));XCTAssertEqual(store.document,converted);store.geometryBusy=false
    if let root=ProcessInfo.processInfo.environment["PHOTATO_CONVERSION_OUTPUT_DIR"] {
      store.videoTimelinePixelsPerSecond=480
      let host=NSHostingView(rootView:VideoTimelinePanel(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:320)
      let window=NSWindow(contentRect:host.frame,styleMask:[],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil;window.close()}
      host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));host.layoutSubtreeIfNeeded()
      if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:root).appendingPathComponent("converted-timeline.png"))}
    }
  }
  @MainActor func testAPIConversionStateRenderingArchiveAndGuards()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document);service.setDocumentTransfersEnabled(true)
      let parameters:[String:Any]=["operation":"toVideo","frameRate":8]
      let extra=try await helper.edit(service,document,"animation.edit",["operation":"toVideo","frameRate":8,"delay":1]);XCTAssertEqual(extra,400)
      let missing=try await helper.edit(service,document,"animation.edit",["operation":"toVideo"]);XCTAssertEqual(missing,400)
      let invalid=try await helper.edit(service,document,"animation.edit",["operation":"toVideo","frameRate":241]);XCTAssertEqual(invalid,400)
      let stale=try await helper.edit(service,document,"animation.edit",parameters,revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"animation.edit",parameters);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let result=try await helper.edit(service,document,"animation.edit",parameters);XCTAssertEqual(result,200)
      let converted=document.store.document
      var expected=original;try Command.animation(.convertToVideo(8)).apply(to:&expected)
      for i in expected.layers.indices {
        for j in (expected.layers[i].videoKeyframes ?? []).indices {expected.layers[i].videoKeyframes![j].id=converted.layers[i].videoKeyframes![j].id}
      }
      XCTAssertEqual(converted,expected)
      for frame in 0..<8 {
        let index=frame<2 ? 0:frame<6 ? 1:2
        XCTAssertEqual(try Renderer.composite(converted.videoDocument(at:frame)),try Renderer.composite(original.animationDocument(at:original.animation!.frames[index].id)))
      }
      let id=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(id)/file.photato"
      let old=try await files.request(service,path:path,headers:["X-Photato-Archive-Version":"58"]);XCTAssertEqual(old.0.statusCode,422)
      let capabilities=try await files.request(service,path:"/v1/capabilities")
      XCTAssertEqual(capabilities.0.statusCode,200)
      let caps=try XCTUnwrap(JSONSerialization.jsonObject(with:capabilities.1) as? [String:Any])
      let animationCaps=try XCTUnwrap(caps["animation"] as? [String:Any])
      XCTAssertEqual(animationCaps["nativeArchiveVersion"] as? Int,60)
      XCTAssertTrue((animationCaps["operations"] as? [String])?.contains("toVideo") == true)
      let state=try await files.request(service,path:"/v1/documents/\(id)")
      XCTAssertEqual(state.0.statusCode,200)
      let value=try XCTUnwrap(JSONSerialization.jsonObject(with:state.1) as? [String:Any])
      let video=try XCTUnwrap(value["video"] as? [String:Any]),timeline=try XCTUnwrap(video["timeline"] as? [String:Any])
      XCTAssertEqual(timeline["finiteLoopCount"] as? Int,3)
      let tracks=try XCTUnwrap(video["keyframes"] as? [[String:Any]])
      let keys=try XCTUnwrap(tracks.first?["keys"] as? [[String:Any]])
      XCTAssertTrue(keys.contains{($0["property"] as? String)=="visibility" && ($0["interpolation"] as? String)=="hold" && ($0["frameComposition"] as? Bool)==true})
      let current=try await files.request(service,path:path,headers:["X-Photato-Archive-Version":"59"]);XCTAssertEqual(current.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(current.1),converted)
      let undone=await document.store.undo();XCTAssertTrue(undone);XCTAssertEqual(document.store.document,original)
    }
  }
  func testConvertedSequenceExportRetainsAllSamples()throws {
    let d=try fixture().convertingFrameAnimation(frameRate:8)
    let output=try ImageSequenceExport.render(d,options:.init())
    XCTAssertEqual(output.files.filter{$0.name.hasSuffix(".png")}.count,8)
    let manifest=try XCTUnwrap(output.files.first{$0.name=="sequence.json"})
    let metadata=try XCTUnwrap(JSONSerialization.jsonObject(with:manifest.data) as? [String:Any])
    XCTAssertEqual(metadata["loopCount"] as? Int,3)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_CONVERSION_OUTPUT_DIR"] {
      try output.zip().write(to:URL(fileURLWithPath:root).appendingPathComponent("converted-sequence.zip"))
    }
  }
  @MainActor func testFiniteAudioPlaybackCompletesWholePassFromSelectedFrame()async throws {
    var d=try fixture().convertingFrameAnimation(frameRate:8);d.videoTimeline!.finiteLoopCount=1;d.videoTimeline!.looping=false
    let pcm=try TimelinePCM(samples:[Float](repeating:0,count:96000))
    d.videoTimeline!.audioTracks=[.init(name:"Sound",clips:[.init(name:"Silence",source:.init(data:try pcm.wave(),duration:1))])]
    let store=EditorStore(document:d),player=ConversionAudioPlayer();defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    try store.selectVideoFrame(2);let before=store.document
    store.timelineAudioFactory={_ in player};try store.startVideoPlayback()
    for _ in 0..<500 where !player.isPlaying{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertTrue(player.isPlaying);XCTAssertTrue(player.looping);XCTAssertEqual(player.currentTime,0.25)
    for (time,frame) in [(0.875,7),(0.0,0),(0.125,1)] {
      player.currentTime=time
      for _ in 0..<500 where store.timelinePreviewVideoFrame != frame {try await Task.sleep(for:.milliseconds(2))}
      XCTAssertEqual(store.timelinePreviewVideoFrame,frame);XCTAssertNotNil(store.timelineTask)
    }
    player.currentTime=0.25
    for _ in 0..<500 where store.timelineTask != nil{try await Task.sleep(for:.milliseconds(2))}
    XCTAssertNil(store.timelineTask);XCTAssertFalse(player.isPlaying);XCTAssertEqual(store.document,before);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
