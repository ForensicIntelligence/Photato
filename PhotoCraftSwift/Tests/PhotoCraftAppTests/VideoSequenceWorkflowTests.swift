import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class VideoSequenceWorkflowTests: XCTestCase {
  func source(_ pixel:Pixel) throws -> CraftDocument {var d=try CraftDocument(width:4,height:3);d.layers[0].content = .raster(try Surface(width:4,height:3,fill:pixel));return d}
  func movie() throws -> CraftDocument {try VideoSequence.make([source(Pixel(1,0,0)),source(Pixel(0,1,0)),source(Pixel(0,0,1))],frameRate:10,name:"Owned sequence")}
  @MainActor func testFileImportUsesNumericOrderAndOneVideoLayer() throws {
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    let names=["frame10.png","frame2.png","frame1.png"],colors=[Pixel(0,0,1),Pixel(0,1,0),Pixel(1,0,0)]
    let urls=names.map{dir.appendingPathComponent($0)}
    for (url,pixel) in zip(urls,colors) {try DocumentIO.encode(source(pixel),format:.png).write(to:url)}
    let original=try urls.map{try Data(contentsOf:$0)}
    let d=try VideoSequenceImport.read(urls,frameRate:24,name:"Sequence")
    XCTAssertEqual(d.layers.count,1);XCTAssertEqual(d.videoTimeline?.durationFrames,3);XCTAssertEqual(d.layers[0].video?.frameRate,24)
    for (i,pixel) in [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)].enumerated() {XCTAssertEqual(try Renderer.composite(d.videoDocument(at:i)).pixel(x:0,y:0),pixel)}
    XCTAssertEqual(try urls.map{try Data(contentsOf:$0)},original)
    XCTAssertThrowsError(try VideoSequence.make([source(.white),CraftDocument(width:3,height:3)],frameRate:24,name:"Mismatch"))
    XCTAssertThrowsError(try VideoSequence.make([source(.white)],frameRate:24,name:"Budget",maximumBytes:1))
    XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
  }
  @MainActor func testNativeViewPlaybackPreviewAndPainting() async throws {
    let d=try movie(),store=EditorStore(document:d);defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    XCTAssertTrue(store.timelineVisible);XCTAssertTrue(store.canPerformLayerPanel(.rasterize))
    try store.selectVideoFrame(1);XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(try Renderer.composite(store.previewDocument).pixel(x:0,y:0),Pixel(0,1,0))
    store.perform(.fill(d.layers[0].id,.white));XCTAssertEqual(store.document.layers[0].video!.frames[1].pixel(x:0,y:0),.white)
    try store.selectVideoFrame(0);let before=store.document,history=store.session.undoStack.count
    try store.startVideoPlayback();try await Task.sleep(for:.milliseconds(130))
    XCTAssertNotNil(store.timelinePreviewVideoFrame);XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,history)
    store.stopTimelinePlayback();XCTAssertNil(store.timelinePreviewVideoFrame)
    let view=NSHostingView(rootView:VideoTimelinePanel(store:store));view.frame=NSRect(x:0,y:0,width:1100,height:166);view.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(view.fittingSize.width,1100)
  }
  @MainActor func testAPICreationTimingPaintingNative51AndRevisionGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,first in
      first.store.session=EditorSession(document:try source(Pixel(1,0,0)))
      let second=CraftNSDocument(model:try source(Pixel(0,1,0)));service.controller.addDocument(second)
      defer {for d in service.controller.documents.compactMap({$0 as? CraftNSDocument}) {d.store.stopTimelinePlayback();d.store.renderTask?.cancel();d.windowControllers.forEach{$0.close()};service.controller.removeDocument(d)}}
      try service.share(first);try service.share(second);service.setDocumentTransfersEnabled(true)
      let ids=service.shares.map(\.id),a=first.store.document,b=second.store.document
      let reply=try await helper.request(service,path:"/v1/documents/\(ids[0])/commands",body:["command":"video.sequence","revision":service.revision(first.store),"parameters":["name":"API Video","frameRate":12,"sources":[["id":ids[0].uuidString,"revision":service.revision(first.store)],["id":ids[1].uuidString,"revision":service.revision(second.store)]]]])
      XCTAssertEqual(reply.0.statusCode,201,String(decoding:reply.1,as:UTF8.self))
      let video=try XCTUnwrap(service.shares.last?.document),id=try XCTUnwrap(service.shares.last?.id)
      XCTAssertEqual(video.store.document.layers.count,1);XCTAssertEqual(video.store.document.layers[0].video?.frames.count,2)
      XCTAssertEqual(first.store.document,a);XCTAssertEqual(second.store.document,b)
      @MainActor func command(_ name:String,_ params:[String:Any],revision:String?=nil) async throws -> Int {
        try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":name,"revision":revision ?? service.revision(video.store),"parameters":params]).0.statusCode
      }
      let seek=try await command("video.view",["frame":1]);XCTAssertEqual(seek,200)
      XCTAssertEqual(try Renderer.composite(video.store.document).pixel(x:0,y:0),Pixel(0,1,0))
      let painted=try await command("layer.fill",["layerID":video.store.document.layers[0].id.uuidString,"r":1,"g":1,"b":1,"a":1]);XCTAssertEqual(painted,200)
      XCTAssertEqual(video.store.document.layers[0].video!.frames[1].pixel(x:0,y:0),.white)
      let revision=service.revision(video.store)
      let edit=try await command("video.edit",["operation":"frameRate","frameRate":24]);XCTAssertEqual(edit,200)
      XCTAssertEqual(video.store.document.videoTimeline?.durationFrames,4)
      let stale=try await command("video.edit",["operation":"loop","looping":false],revision:revision);XCTAssertEqual(stale,409)
      let bad=try await command("video.edit",["operation":"frameRate","frameRate":0]);XCTAssertEqual(bad,400)
      video.store.geometryBusy=true;let busy=try await command("video.view",["frame":0]);XCTAssertEqual(busy,409);video.store.geometryBusy=false
      let file=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"51"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),video.store.document)
      let old=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"50"]);XCTAssertEqual(old.0.statusCode,422)
      let desktop=try VideoSequence.make([a,b],frameRate:12,name:"API Video");XCTAssertEqual(desktop.layers[0].video?.frames[0],video.store.document.layers[0].video?.frames[0]);XCTAssertEqual(desktop.layers[0].video?.frames[1].pixel(x:0,y:0),Pixel(0,1,0))
    }
  }
  @MainActor func testIndependentPNGFramesKeepPositionsAndAlpha() throws {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/videoSequence")
    let urls=["frame10.png","frame1.png","frame2.png"].map{root.appendingPathComponent($0)}
    let d=try VideoSequenceImport.read(urls,frameRate:12,name:"Independent sequence")
    let spots=[(0,0,Pixel(1,0,0)),(1,1,Pixel(0,1,0,128.0/255)),(3,2,Pixel(0,0,1))]
    for i in 0..<3 {
      let frame=try d.videoDocument(at:i),surface=try Renderer.composite(frame)
      for y in 0..<3 { for x in 0..<4 {
        let expected=x==spots[i].0 && y==spots[i].1 ? spots[i].2 : Pixel.clear
        XCTAssertEqual(surface.pixel(x:x,y:y),expected)
      } }
      if let output=ProcessInfo.processInfo.environment["PHOTATO_VIDEO_OUTPUT_DIR"] {
        try DocumentIO.encode(frame,format:.png).write(to:URL(fileURLWithPath:output).appendingPathComponent("frame-\(i).png"))
      }
    }
  }
  @MainActor func testAPISequenceCancellationAndPermission() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      var source=try CraftDocument(width:1536,height:1536);source.layers[0].content = .fill(.white)
      document.store.session=EditorSession(document:source);try service.share(document)
      let id=try XCTUnwrap(service.shares.first?.id)
      let params:[String:Any]=["name":"Cancellable sequence","frameRate":30,"sources":[["id":id.uuidString,"revision":service.revision(document.store)]]]
      let disabled=try await helper.edit(service,document,"video.sequence",params);XCTAssertEqual(disabled,403)
      service.setDocumentTransfersEnabled(true)
      let job=Task {try await helper.edit(service,document,"video.sequence",params)}
      for _ in 0..<200 where service.videoSequenceOperationID == nil {try await Task.sleep(for:.milliseconds(5))}
      let operation=try XCTUnwrap(service.videoSequenceOperationID)
      let cancelled=try await helper.edit(service,document,"video.sequence.cancel",["operationID":operation.uuidString]);XCTAssertEqual(cancelled,200)
      let result=try await job.value;XCTAssertEqual(result,409)
      XCTAssertEqual(document.store.document,source);XCTAssertEqual(service.shares.count,1);XCTAssertFalse(document.store.geometryBusy);XCTAssertNil(service.videoSequenceOperationID)
      let missing=try await helper.edit(service,document,"video.sequence.cancel",["operationID":operation.uuidString]);XCTAssertEqual(missing,409)
    }
  }
}
