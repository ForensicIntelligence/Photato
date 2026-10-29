import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VideoFrameConversionWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    let pixels=try [Pixel(1,0,0),Pixel(0,0,1)].map{try Surface(width:4,height:3,fill:$0)}
    d.layers[0].video = .init(frames:pixels,frameRate:2)
    d.videoTimeline = .init(frameRate:4,durationFrames:4)
    d.videoTimeline!.audioTracks=[.init(name:"Source audio",clips:[.init(name:"Retained source",source:.init(data:Data([1,2,3]),duration:1))])]
    try d.selectVideoFrame(0);return d
  }
  @MainActor func testNativeConversionRecoveryAndCancellation()async throws {
    let source=try fixture(),store=EditorStore(document:source)
    defer{store.geometryTask?.cancel();store.renderTask?.cancel();store.stopTimelinePlayback()}
    store.editTimeline(.convertFromVideo);await store.geometryTask?.value;XCTAssertNil(store.error)
    let frames=store.document;XCTAssertEqual(frames.animation?.frames.count,4)
    XCTAssertEqual(store.session.undoStack.count,1)
    store.editTimeline(.restoreVideoSource);await store.geometryTask?.value;XCTAssertNil(store.error)
    XCTAssertEqual(store.document,source)
    let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(store.document,frames)
    store.editTimeline(.convertToVideo(4));store.geometryTask?.cancel();await store.geometryTask?.value
    XCTAssertEqual(store.document,frames);XCTAssertFalse(store.geometryBusy)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_REVERSE_OUTPUT_DIR"] {
      let host=NSHostingView(rootView:TimelinePanel(store:store));host.frame=NSRect(x:0,y:0,width:1100,height:180)
      let window=NSWindow(contentRect:host.frame,styleMask:[],backing:.buffered,defer:false)
      window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua);window.contentView=host
      defer{window.contentView=nil;window.close()}
      host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));host.layoutSubtreeIfNeeded()
      if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:root).appendingPathComponent("sampled-frames.png"))
      }
    }
  }
  @MainActor func testAPIConversionStatePrivacyArchiveRecoveryAndGuards()async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let source=try self.fixture();document.store.session=EditorSession(document:source)
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let extra=try await helper.edit(service,document,"animation.edit",["operation":"fromVideo","frameRate":4]);XCTAssertEqual(extra,400)
      let stale=try await helper.edit(service,document,"animation.edit",["operation":"fromVideo"],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"animation.edit",["operation":"fromVideo"]);XCTAssertEqual(busy,409)
      document.store.geometryBusy=false;XCTAssertEqual(document.store.document,source)
      let result=try await helper.edit(service,document,"animation.edit",["operation":"fromVideo"]);XCTAssertEqual(result,200)
      let frames=document.store.document,id=try XCTUnwrap(service.shares.first?.id)
      let state=try await files.request(service,path:"/v1/documents/\(id)")
      let value=try XCTUnwrap(JSONSerialization.jsonObject(with:state.1) as? [String:Any])
      let animationState=try XCTUnwrap(value["animation"] as? [String:Any])
      let animation=try XCTUnwrap(animationState["animation"] as? [String:Any])
      let sampling=try XCTUnwrap(animation["sampledTimeline"] as? [String:Any]);XCTAssertEqual(sampling["hasAudio"] as? Bool,true);XCTAssertNil(sampling["audioTracks"])
      XCTAssertFalse(String(data:try JSONSerialization.data(withJSONObject:animation),encoding:.utf8)!.contains("AQID"))
      XCTAssertNotNil(animation["retainedSource"]);XCTAssertNil(animation["retainedVideoSource"])
      let frameState=try XCTUnwrap((animation["frames"] as? [[String:Any]])?.first)
      let layer=try XCTUnwrap((frameState["layers"] as? [[String:Any]])?.first)
      XCTAssertNotNil(layer["payloadSummary"]);XCTAssertNil(layer["payload"])
      let old=try await files.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"59"]);XCTAssertEqual(old.0.statusCode,422)
      let archive=try await files.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"60"])
      XCTAssertEqual(archive.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(archive.1),frames)
      let forward=try await helper.edit(service,document,"animation.edit",["operation":"toVideo","frameRate":4]);XCTAssertEqual(forward,200)
      let video=document.store.videoState
      let timeline=try XCTUnwrap(video["timeline"] as? [String:Any]);XCTAssertNotNil(timeline["retainedSource"]);XCTAssertNil(timeline["retainedFrameSources"])
      let keys=try XCTUnwrap((video["keyframes"] as? [[String:Any]])?.first?["keys"] as? [[String:Any]])
      XCTAssertTrue(keys.contains{($0["property"] as? String)=="content" && $0["contentSummary"] != nil})
      XCTAssertTrue(keys.allSatisfy{$0["content"]==nil})
      for i in 0..<4 {XCTAssertEqual(try Renderer.composite(document.store.document.videoDocument(at:i)),try Renderer.composite(source.videoDocument(at:i)))}
      let restored=try await helper.edit(service,document,"animation.edit",["operation":"restoreVideoSource"]);XCTAssertEqual(restored,200)
      XCTAssertEqual(document.store.document,source)
      let absent=try await helper.edit(service,document,"animation.edit",["operation":"restoreVideoSource"]);XCTAssertEqual(absent,422)
    }
  }
}
