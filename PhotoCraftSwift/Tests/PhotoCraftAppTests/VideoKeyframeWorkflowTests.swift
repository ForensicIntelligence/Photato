import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class VideoKeyframeWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:12,height:8)
    let layer=Layer(name:"Animated square",content:.raster(try Surface(width:2,height:2,fill:Pixel(1,0,0))))
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
  func animated()throws->CraftDocument {
    var s=EditorSession(document:try fixture());let id=s.document.layers[0].id
    try s.execute(.video(.create(frameRate:4,durationFrames:9)))
    for p in [VideoProperty.position,.opacity]{try s.execute(.video(.keyframe(.enable(id,p))))}
    try s.selectVideoFrame(8);try s.execute(.move(id,8,4));try s.execute(.opacity(id,0));try s.selectVideoFrame(0);return s.document
  }
  @MainActor func testRenderedAnimationMatchesAnalyticSquareAndExports()throws {
    let model=try animated()
    for frame in stride(from:0,through:8,by:2) {
      let d=try model.videoDocument(at:frame),pixels=try Renderer.composite(d)
      for y in 0..<8 {for x in 0..<12 {
        let inside=(frame..<frame+2).contains(x) && (frame/2..<frame/2+2).contains(y)
        let expected=inside && frame<8 ? Pixel(1,0,0,Float(1-Double(frame)/8)):.clear
        let actual=pixels.pixel(x:x,y:y)
        XCTAssertEqual(actual.r,expected.r,accuracy:1.0/255);XCTAssertEqual(actual.g,expected.g);XCTAssertEqual(actual.b,expected.b);XCTAssertEqual(actual.a,expected.a,accuracy:1.0/255)
      }}
      if let path=ProcessInfo.processInfo.environment["PHOTATO_KEYFRAME_OUTPUT_DIR"] {try DocumentIO.encode(d,format:.png).write(to:URL(fileURLWithPath:path).appendingPathComponent("square-\(frame).png"))}
    }
    let export=try ImageSequenceExport.render(model,options:.init(firstFrame:0,lastFrame:8))
    XCTAssertEqual(export.files.count,10)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(model)),model)
    XCTAssertThrowsError(try DocumentIO.encode(model,format:.psd))
  }
  @MainActor func testDesktopPlaybackUsesKeysWithoutMutatingHistory()async throws {
    let model=try animated(),store=EditorStore(document:model);defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    try store.selectVideoFrame(4);XCTAssertEqual(store.document.layers[0].x,4);XCTAssertEqual(store.document.layers[0].opacity,0.5)
    store.perform(.opacity(model.layers[0].id,0.25));let after=store.document
    XCTAssertEqual(after.layers[0].videoKeyframes?.count,5)
    let undone=await store.undo();XCTAssertTrue(undone);let redone=await store.redo();XCTAssertTrue(redone);XCTAssertEqual(store.document,after)
    try store.selectVideoFrame(0);let before=store.document,count=store.session.undoStack.count
    try store.startVideoPlayback();try await Task.sleep(for:.milliseconds(300))
    XCTAssertNotNil(store.timelinePreviewVideoFrame);XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,count)
    if let frame=store.timelinePreviewVideoFrame {XCTAssertEqual(try Renderer.composite(store.previewDocument),try Renderer.composite(before.videoDocument(at:frame)))}
    store.stopTimelinePlayback()
    let view=NSHostingView(rootView:VideoTimelinePanel(store:store));view.frame=NSRect(x:0,y:0,width:1100,height:260);view.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(view.fittingSize.width,1100)
  }
  @MainActor func testAPIKeyframesMatchDesktopNative53AndGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      let model=try fixture();document.store.session=EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let shareID=try XCTUnwrap(service.shares.first?.id),id=model.layers[0].id.uuidString
      @MainActor func edit(_ name:String,_ params:[String:Any],revision:String?=nil)async throws->Int {try await helper.edit(service,document,name,params,revision:revision)}
      let create=try await edit("video.edit",["operation":"create","frameRate":4,"durationFrames":9]);XCTAssertEqual(create,200);XCTAssertTrue(document.store.timelineVisible)
      for property in ["position","opacity"]{let code=try await edit("video.keyframe",["operation":"enable","layerID":id,"property":property]);XCTAssertEqual(code,200)}
      let seek=try await edit("video.view",["frame":8]);XCTAssertEqual(seek,200)
      let move=try await edit("layer.move",["layerID":id,"x":8,"y":4]);XCTAssertEqual(move,200)
      let opacity=try await edit("layer.opacity",["layerID":id,"opacity":0]);XCTAssertEqual(opacity,200)
      let middle=try await edit("video.view",["frame":4]);XCTAssertEqual(middle,200)
      XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(animated().videoDocument(at:4)))
      let keys=try XCTUnwrap(document.store.videoState["keyframes"] as? [[String:Any]]);XCTAssertEqual(keys.count,1);XCTAssertEqual((keys[0]["keys"] as? [Any])?.count,4)
      let current=document.store.document,revision=service.revision(document.store)
      let bad=try await edit("video.keyframe",["operation":"enable","layerID":id,"property":"opacity","time":0]);XCTAssertEqual(bad,400)
      let stale=try await edit("video.keyframe",["operation":"disable","layerID":id,"property":"opacity"],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await edit("video.keyframe",["operation":"disable","layerID":id,"property":"opacity"]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      XCTAssertEqual(service.revision(document.store),revision)
      let history=document.store.session.undoStack.count
      try document.store.startVideoPlayback();let playing=try await edit("video.keyframe",["operation":"disable","layerID":id,"property":"opacity"]);XCTAssertEqual(playing,409);document.store.stopTimelinePlayback()
      XCTAssertEqual(document.store.document,current);XCTAssertEqual(document.store.session.undoStack.count,history)
      let playbackStale=try await edit("video.keyframe",["operation":"disable","layerID":id,"property":"opacity"],revision:revision);XCTAssertEqual(playbackStale,409)
      let file=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"53"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),current)
      let old=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"52"]);XCTAssertEqual(old.0.statusCode,422)
      let key=try XCTUnwrap(current.layers[0].videoKeyframes?.first{$0.property == .opacity})
      let hold=try await edit("video.keyframe",["operation":"interpolation","layerID":id,"keyframeID":key.id.uuidString,"interpolation":"hold"]);XCTAssertEqual(hold,200);XCTAssertEqual(document.store.document.layers[0].opacity,1)
      let delete=try await edit("video.keyframe",["operation":"delete","layerID":id,"keyframeID":key.id.uuidString]);XCTAssertEqual(delete,200);XCTAssertEqual(document.store.document.layers[0].opacity,0)
      let undo=await document.store.undo();XCTAssertTrue(undo);XCTAssertEqual(document.store.document.layers[0].opacity,1)
    }
  }
  @MainActor func testAPISetMoveDisableAndRemoveTimeline()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      document.store.session=EditorSession(document:try fixture());try service.share(document)
      let id=document.store.document.layers[0].id.uuidString
      let create=try await helper.edit(service,document,"video.edit",["operation":"create","frameRate":4,"durationFrames":9]);XCTAssertEqual(create,200)
      let set=try await helper.edit(service,document,"video.keyframe",["operation":"set","layerID":id,"property":"opacity","time":3]);XCTAssertEqual(set,200);XCTAssertEqual(document.store.document.videoTimeline?.durationFrames,13)
      let key=try XCTUnwrap(document.store.document.layers[0].videoKeyframes?.first)
      let move=try await helper.edit(service,document,"video.keyframe",["operation":"move","layerID":id,"keyframeID":key.id.uuidString,"time":1]);XCTAssertEqual(move,200)
      let disable=try await helper.edit(service,document,"video.keyframe",["operation":"disable","layerID":id,"property":"opacity"]);XCTAssertEqual(disable,200);XCTAssertNil(document.store.document.layers[0].videoKeyframes)
      let remove=try await helper.edit(service,document,"video.edit",["operation":"remove"]);XCTAssertEqual(remove,200);XCTAssertNil(document.store.document.videoTimeline)
      let undo=await document.store.undo();XCTAssertTrue(undo);XCTAssertNotNil(document.store.document.videoTimeline)
    }
  }
}
