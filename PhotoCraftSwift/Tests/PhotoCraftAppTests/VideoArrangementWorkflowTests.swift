import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VideoArrangementWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    let frames=try [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1)].map{try Surface(width:4,height:3,fill:$0)}
    var layer=Layer(name:"Clip",content:.raster(frames[0]));layer.video=VideoClip(frames:frames,frameRate:2)
    d.layers=[layer];d.activeLayerID=layer.id;d.videoTimeline=VideoTimeline(frameRate:8,durationFrames:12);return d
  }
  @MainActor func testSplitRenderExportsAndPreviewHaveNoGap()throws {
    let before=try fixture();let store=EditorStore(document:before);defer{store.renderTask?.cancel()}
    try store.selectVideoFrame(3);store.editVideo(.arrange(.split([before.layers[0].id])))
    XCTAssertNil(store.error);XCTAssertEqual(store.document.layers.count,2)
    for frame in 0..<12 {
      try store.selectVideoFrame(frame)
      let expected=try Renderer.composite(before.videoDocument(at:frame))
      XCTAssertEqual(try Renderer.composite(store.document),expected)
      XCTAssertEqual(try Renderer.composite(store.previewDocument),expected)
      if let path=ProcessInfo.processInfo.environment["PHOTATO_ARRANGEMENT_OUTPUT_DIR"] {
        try DocumentIO.encode(store.document,format:.png).write(to:URL(fileURLWithPath:path).appendingPathComponent("split-\(frame).png"))
      }
    }
    let view=NSHostingView(rootView:VideoTimelinePanel(store:store));view.frame=NSRect(x:0,y:0,width:1100,height:260);view.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(view.fittingSize.width,1100)
  }
  @MainActor func testTimedFillAndGroupComposeWithoutFlattening()throws {
    var d=try CraftDocument(width:4,height:3);let first=Layer(name:"Red",content:.fill(Pixel(1,0,0))),second=Layer(name:"Blue",content:.fill(Pixel(0,0,1)))
    d.layers=[first,second];d.activeLayerID=first.id
    try Command.video(.create(frameRate:4,durationFrames:4)).apply(to:&d)
    try Command.video(.arrange(.group("Sequence",[first.id,second.id]))).apply(to:&d)
    for frame in 0..<8 {
      let color=try Renderer.composite(d.videoDocument(at:frame)).pixel(x:1,y:1)
      XCTAssertEqual(color,frame<4 ? Pixel(1,0,0):Pixel(0,0,1))
    }
    XCTAssertEqual(d.layers[0].content,first.content);XCTAssertEqual(d.layers[1].content,second.content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
  }
  @MainActor func testAPIEditingMatchesDesktopHistoryStateNative54AndGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let model=try fixture();document.store.session=EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let id=model.layers[0].id.uuidString
      let seek=try await helper.edit(service,document,"video.view",["frame":3]);XCTAssertEqual(seek,200)
      let before=document.store.document
      let split=try await helper.edit(service,document,"video.edit",["operation":"split","layerIDs":[id]]);XCTAssertEqual(split,200)
      var expected=before;try Command.video(.arrange(.split([model.layers[0].id]))).apply(to:&expected)
      for frame in 0..<12 {XCTAssertEqual(try Renderer.composite(document.store.document.videoDocument(at:frame)),try Renderer.composite(expected.videoDocument(at:frame)))}
      let after=document.store.document
      let undo=await document.store.undo();XCTAssertTrue(undo);XCTAssertEqual(document.store.document,before)
      let redo=await document.store.redo();XCTAssertTrue(redo);XCTAssertEqual(document.store.document,after)
      let group=try await helper.edit(service,document,"video.edit",["operation":"group","name":"Track","layerIDs":after.layers.map{$0.id.uuidString}]);XCTAssertEqual(group,200)
      let groupID=document.store.document.activeLayerID!.uuidString
      let move=try await helper.edit(service,document,"video.edit",["operation":"arrange","layerID":after.layers[1].id.uuidString,"groupID":groupID,"position":0]);XCTAssertEqual(move,200)
      let start=try await helper.edit(service,document,"video.edit",["operation":"groupStart","layerID":groupID,"startTime":1]);XCTAssertEqual(start,200)
      let stable=document.store.document,revision=service.revision(document.store)
      let bad=try await helper.edit(service,document,"video.edit",["operation":"split","layerIDs":[id],"position":0]);XCTAssertEqual(bad,400)
      let stale=try await helper.edit(service,document,"video.edit",["operation":"split","layerIDs":[id]],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"video.edit",["operation":"split","layerIDs":[id]]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      XCTAssertEqual(document.store.document,stable);XCTAssertEqual(service.revision(document.store),revision)
      let shareID=try XCTUnwrap(service.shares.first?.id)
      let file=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"54"]);XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),stable)
      let old=try await helper.request(service,path:"/v1/documents/\(shareID)/file.photato",headers:["X-Photato-Archive-Version":"53"]);XCTAssertEqual(old.0.statusCode,422)
      let state=try XCTUnwrap(document.store.videoState["arrangement"] as? [String:Any]);XCTAssertEqual((state["groups"] as? [Any])?.count,1)
      let detach=try await helper.edit(service,document,"video.edit",["operation":"arrange","layerID":id,"groupID":NSNull(),"position":0]);XCTAssertEqual(detach,200)
    }
  }
}
