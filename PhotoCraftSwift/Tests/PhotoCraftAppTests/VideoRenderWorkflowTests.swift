import AppKit
import AVFoundation
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class VideoRenderWorkflowTests:XCTestCase {
  func document(size:Int=32,frames:Int=4)throws->CraftDocument {
    var d=try CraftDocument(width:size,height:size);d.layers[0].content = .fill(Pixel(1,0,0))
    d.videoTimeline = .init(frameRate:4,durationFrames:frames);return d
  }
  @MainActor func testNativeExportPublicationHistoryAndControls()async throws {
    let d=try document(),store=EditorStore(document:d);defer{store.renderTask?.cancel()}
    let output=try await store.encodedVideo(.init(codec:.uncompressed));defer{output.discard()}
    XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.videoRenderID)
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:dir)}
    let target=dir.appendingPathComponent("movie.mov");try Data("original".utf8).write(to:target)
    let abandoned=try PreparedVideoPublication(output:output,destination:target);abandoned.discard();XCTAssertEqual(try Data(contentsOf:target),Data("original".utf8))
    let prepared=try PreparedVideoPublication(output:output,destination:target);try prepared.commit();prepared.discard()
    XCTAssertEqual(try Data(contentsOf:target),try Data(contentsOf:output.url))
    let accessory=VideoRenderAccessory(document:d)
    XCTAssertEqual(try accessory.options().codec,.h264);XCTAssertFalse(accessory.alpha.isEnabled);XCTAssertTrue(accessory.bitRate.isEnabled)
    accessory.codec.selectItem(at:3);accessory.changed();accessory.alpha.state = .on
    XCTAssertTrue(try accessory.options().preserveAlpha);XCTAssertFalse(accessory.bitRate.isEnabled)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_VIDEO_RENDER_OUTPUT_DIR"] {
      let host=NSView(frame:NSRect(x:0,y:0,width:560,height:360));host.wantsLayer=true
      let appearance=NSAppearance(named:.darkAqua)!;host.appearance=appearance;accessory.view.appearance=appearance
      appearance.performAsCurrentDrawingAppearance { host.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor }
      accessory.view.frame.origin=NSPoint(x:20,y:20);host.addSubview(accessory.view)
      let window=NSWindow(contentRect:host.bounds,styleMask:[.titled],backing:.buffered,defer:false)
      window.appearance=appearance;window.isReleasedWhenClosed=false;window.contentView=host;defer{window.close()}
      host.layoutSubtreeIfNeeded();XCTAssertTrue(host.bounds.contains(accessory.view.frame))
      let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:root).appendingPathComponent("render-video-settings.png"))
    }
    accessory.first.stringValue="0";XCTAssertThrowsError(try accessory.options())
    try PhotoshopMenuTests().withMenus { delegate,menu in
      let item=try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first{$0.identifier?.rawValue=="File > Export > Render Video…"})
      XCTAssertEqual(item.action,#selector(AppDelegate.renderVideo));XCTAssertFalse(delegate.validateMenuItem(item))
    }
  }
  @MainActor func testAPIFileDeliverySchemasPermissionsAndStaleRevision()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let model=try self.document();document.store.session=EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(service.shares.first?.id.uuidString),revision=service.revision(document.store)
      let response=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"video.render","revision":revision,"parameters":["codec":"uncompressed","includeAudio":false]])
      XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(response.0.value(forHTTPHeaderField:"Content-Type"),"video/quicktime");XCTAssertTrue(MovieIO.recognizes(response.1))
      let decoded=try MovieIO.decode(response.1,name:"API export");XCTAssertEqual(decoded.layers[0].video?.frames.count,4)
      XCTAssertEqual(document.store.document,model);XCTAssertEqual(service.revision(document.store),revision);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let bad=try await helper.edit(service,document,"video.render",["codec":"h264","preserveAlpha":true]);XCTAssertEqual(bad,422)
      let unknown=try await helper.edit(service,document,"video.render",["codec":"unknown"]);XCTAssertEqual(unknown,400)
      let stale=try await helper.edit(service,document,"video.render",["codec":"h264"],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"video.render",["codec":"h264"]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      service.setDocumentTransfersEnabled(false);let denied=try await helper.edit(service,document,"video.render",["codec":"h264"]);XCTAssertEqual(denied,403)
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="video.render"});XCTAssertNotNil(definition.schema["properties"])
      XCTAssertNotNil(AutomationService.capabilities["videoRender"])
    }
  }
  @MainActor func testCancellationRevocationAndClosurePreventOutput()async throws {
    let helper=AutomationTests()
    for mode in 0..<3 {
      try await helper.withService(pressedMouseButtons:{0}){service,document in
        let model=try self.document(size:256,frames:400);document.store.session=EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
        let job=Task{try await helper.edit(service,document,"video.render",["codec":"h264"])}
        for _ in 0..<200 where document.store.videoRenderID == nil{try await Task.sleep(for:.milliseconds(5))}
        let id=try XCTUnwrap(document.store.videoRenderID),worker=try XCTUnwrap(document.store.videoRenderWorker)
        if mode==0{let cancelled=try await helper.edit(service,document,"video.render.cancel",["operationID":id.uuidString]);XCTAssertEqual(cancelled,200)}
        else if mode==1{service.setDocumentTransfersEnabled(false)}else{document.close()}
        XCTAssertTrue(worker.isCancelled || mode==2)
        let result=try await job.value;XCTAssertEqual(result,409);XCTAssertEqual(document.store.document,model);XCTAssertNil(document.store.videoRenderID);XCTAssertTrue(service.videoRenderShares.isEmpty)
      }
    }
  }
}
