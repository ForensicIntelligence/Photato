import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class TimelineWorkflowTests: XCTestCase {
  func source() throws -> CraftDocument {
    var d=try CraftDocument(width:8,height:6)
    d.layers[0].content = .raster(try Surface(width:2,height:2,depth:.u8,fill:Pixel(1,0,0)))
    return d
  }
  @MainActor func testNativeFrameChangesAlterActualCompositeAndPlaybackIsTransient() async throws {
    let store=EditorStore(document:try source());defer{store.stopTimelinePlayback();store.renderTask?.cancel()}
    store.editTimeline(.create);let first=try XCTUnwrap(store.document.animation?.selectedFrameID)
    store.editTimeline(.duplicate);let second=try XCTUnwrap(store.document.animation?.selectedFrameID)
    store.perform(.move(store.document.layers[0].id,4,2));let moved=try Renderer.composite(store.document)
    XCTAssertEqual(moved.pixel(x:4,y:2),Pixel(1,0,0));XCTAssertEqual(moved.pixel(x:0,y:0).a,0)
    try store.selectTimelineFrame(first);let original=store.document,count=store.session.undoStack.count
    try store.startTimelinePlayback();try await Task.sleep(for:.milliseconds(135))
    XCTAssertEqual(store.document,original);XCTAssertEqual(store.session.undoStack.count,count)
    store.stopTimelinePlayback();XCTAssertNil(store.timelinePreviewFrameID)
    try store.selectTimelineFrame(second);XCTAssertEqual(try Renderer.composite(store.document),moved)
    store.geometryBusy=true;XCTAssertThrowsError(try store.selectTimelineFrame(first));XCTAssertThrowsError(try store.startTimelinePlayback());store.geometryBusy=false
  }
  @MainActor func testVisibilityDraftPreviewsWithoutChangingAnySavedFrame() async throws {
    let store=EditorStore(document:try source());defer{store.renderTask?.cancel()}
    store.editTimeline(.create);store.editTimeline(.duplicate)
    let before=store.document,history=store.session.undoStack.count
    let token=try XCTUnwrap(store.beginLayerVisibilityDrag(before.layers[0].id))
    let preview=try Renderer.composite(store.previewDocument)
    XCTAssertEqual(preview.pixel(x:0,y:0).a,0)
    XCTAssertEqual(store.document,before);XCTAssertEqual(store.session.undoStack.count,history)
    store.finishLayerVisibilityDrag(token,cancel:true);XCTAssertEqual(store.document,before)
    let commit=try XCTUnwrap(store.beginLayerVisibilityDrag(before.layers[0].id));store.finishLayerVisibilityDrag(commit)
    XCTAssertFalse(store.document.layers[0].visible)
    let first=try XCTUnwrap(before.animation?.frames.first?.id);try store.selectTimelineFrame(first)
    XCTAssertTrue(store.document.layers[0].visible)
  }
  func testSavePolicyAndPSDAreExplicitWhileNativeReopens() throws {
    var d=try source();try Command.animation(.create).apply(to:&d)
    XCTAssertNil(DocumentIO.persistenceIssue(d,format:.native));XCTAssertNotNil(DocumentIO.persistenceIssue(d,format:.psd))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    XCTAssertEqual(try NativeArchive.decode(DocumentIO.encode(d,format:.native)),d)
  }
  @MainActor func testTimelineFactoryMenuAndLayout() throws {
    let helper=PhotoshopMenuTests()
    try helper.withMenus { _,menu in
      let item=try XCTUnwrap(helper.allItems(menu).first{$0.identifier?.rawValue=="Window > Timeline"})
      XCTAssertEqual(item.action,#selector(AppDelegate.showTimeline));XCTAssertEqual(item.keyEquivalent,"")
    }
    let store=EditorStore(document:try source());defer{store.renderTask?.cancel()};store.editTimeline(.create)
    let view=NSHostingView(rootView:TimelinePanel(store:store));view.frame=NSRect(x:0,y:0,width:1100,height:166);view.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(view.fittingSize.height,180);XCTAssertLessThanOrEqual(view.fittingSize.width,1100)
  }
  @MainActor func testAPIFrameTransactionsMatchDesktopAndRejectStaleBusyInvalid() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      try service.share(document);let store=document.store
      let status=try await helper.edit(service,document,"animation.edit",["operation":"create"]);XCTAssertEqual(status,200)
      let first=try XCTUnwrap(store.document.animation?.selectedFrameID),stale=service.revision(store)
      let duplicate=try await helper.edit(service,document,"animation.edit",["operation":"duplicate"]);XCTAssertEqual(duplicate,200)
      let second=try XCTUnwrap(store.document.animation?.selectedFrameID),layer=store.document.layers[0].id
      let moved=try await helper.edit(service,document,"layer.move",["layerID":layer.uuidString,"x":2,"y":1]);XCTAssertEqual(moved,200)
      let current=store.document;let count=store.session.undoStack.count
      let selected=try await helper.edit(service,document,"animation.view",["frameID":first.uuidString,"visible":true]);XCTAssertEqual(selected,200)
      XCTAssertEqual(store.document.layers[0].x,0);XCTAssertEqual(store.session.undoStack.count,count);XCTAssertTrue(store.timelineVisible)
      let expected=try current.animationDocument(at:first);XCTAssertEqual(store.document,expected)
      let staleStatus=try await helper.edit(service,document,"animation.edit",["operation":"delay","delay":0.5],revision:stale);XCTAssertEqual(staleStatus,409)
      let invalid=try await helper.edit(service,document,"animation.edit",["operation":"duplicate","delay":1]);XCTAssertEqual(invalid,400)
      store.geometryBusy=true
      let busy=try await helper.edit(service,document,"animation.view",["frameID":second.uuidString]);XCTAssertEqual(busy,409);store.geometryBusy=false
      XCTAssertEqual(store.document,expected)
      let result=try await helper.edit(service,document,"animation.edit",["operation":"tween","count":1,"position":true,"opacity":false]);XCTAssertEqual(result,200)
      XCTAssertEqual(store.document.animation?.frames.count,3)
      let state=store.animationState;XCTAssertNotNil(state["animation"])
      let playing=try await helper.edit(service,document,"animation.view",["playing":true]);XCTAssertEqual(playing,200)
      let playingRevision=service.revision(store),playingDocument=store.document
      let whilePlaying=try await helper.edit(service,document,"animation.edit",["operation":"duplicate"]);XCTAssertEqual(whilePlaying,409)
      try await Task.sleep(for:.milliseconds(150))
      XCTAssertEqual(service.revision(store),playingRevision);XCTAssertEqual(store.document,playingDocument)
      let stopped=try await helper.edit(service,document,"animation.view",["playing":false],revision:playingRevision);XCTAssertEqual(stopped,200)
      service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(service.shares.first?.id)
      let old=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"49"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"50"]);XCTAssertEqual(saved.0.statusCode,200)
      XCTAssertEqual(try NativeArchive.decode(saved.1),store.document)
    }
  }
}
