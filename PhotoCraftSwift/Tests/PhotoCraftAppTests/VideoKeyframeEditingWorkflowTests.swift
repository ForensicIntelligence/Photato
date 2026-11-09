import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class VideoKeyframeEditingWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u16)throws->CraftDocument {
    var d=try CraftDocument(width:160,height:120,depth:depth,name:"Owned Keyframes 518")
    d.layers=[Layer(name:"Animated red",content:.raster(try Surface(width:30,height:20,depth:depth,fill:Pixel(1,0,0)))),Layer(name:"Destination blue",content:.raster(try Surface(width:30,height:20,depth:depth,fill:Pixel(0,0,1))))]
    d.layers[1].x=80;d.layers[1].y=60
    d.activeLayerID=d.layers[0].id;d.videoTimeline=VideoTimeline(frameRate:30,durationFrames:151)
    var s=EditorSession(document:d);let id=d.layers[0].id
    try s.execute(.video(.keyframe(.enable(id,.opacity))));try s.selectVideoFrame(30);try s.execute(.opacity(id,0.25));try s.selectVideoFrame(0)
    return s.document
  }
  @MainActor func testNativeApplicationClipboardSelectionPasteHistoryAndExactShiftedPixels()async throws {
    let original=try fixture(),source=EditorStore(document:original),target=EditorStore(document:try fixture())
    let board=VideoKeyframePasteboard();source.videoKeyframePasteboard=board;target.videoKeyframePasteboard=board
    defer{source.renderTask?.cancel();target.renderTask?.cancel()}
    source.selectAllVideoKeyframes(layerID:original.layers[0].id,property:.opacity)
    XCTAssertEqual(source.validVideoKeyframeSelection.count,2);source.copySelectedVideoKeyframes()
    XCTAssertEqual(source.document,original);XCTAssertTrue(source.session.undoStack.isEmpty)
    source.perform(.opacity(original.layers[0].id,0.5));XCTAssertEqual(board.value?.tracks[0].keys.map(\.opacity),[1,0.25])
    try target.selectVideoFrame(60);let before=target.document
    target.pasteVideoKeyframes();await target.geometryTask?.value
    XCTAssertNil(target.error);XCTAssertEqual(target.validVideoKeyframeSelection.count,2);XCTAssertEqual(target.session.undoStack.count,1)
    let after=target.document
    for frame in [0,15,30] {
      XCTAssertEqual(try Renderer.composite(original.videoDocument(at:frame)),try Renderer.composite(after.videoDocument(at:frame+60)))
    }
    do {let changed=await target.undo();XCTAssertTrue(changed)};XCTAssertEqual(target.document,before)
    do {let changed=await target.redo();XCTAssertTrue(changed)};XCTAssertEqual(target.document,after)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(after)),after)
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try NativeArchive.encodeChunked(after).write(to:URL(fileURLWithPath:folder).appendingPathComponent("Owned-Keyframes-518.photato"))
    }
  }
  @MainActor func testNativeBulkSelectionDeletionInterpolationAndControls()async throws {
    let original=try fixture(),store=EditorStore(document:original);defer{store.renderTask?.cancel()}
    store.selectAllVideoKeyframes();let selection=store.validVideoKeyframeSelection
    XCTAssertEqual(selection.count,2)
    let key=try XCTUnwrap(selection.first);store.selectVideoKeyframe(key,additive:true);XCTAssertEqual(store.validVideoKeyframeSelection.count,1)
    store.selectVideoKeyframe(key,additive:true);XCTAssertEqual(store.validVideoKeyframeSelection.count,2)
    store.editSelectedVideoKeyframes(.interpolation(selection,.hold));await store.geometryTask?.value
    XCTAssertTrue(store.document.layers[0].videoKeyframes!.allSatisfy{$0.interpolation == .hold})
    store.editSelectedVideoKeyframes(.move(selection,seconds:2,duplicate:true));await store.geometryTask?.value
    XCTAssertEqual(store.validVideoKeyframeSelection.count,2);XCTAssertEqual(store.document.layers[0].videoKeyframes?.count,4)
    store.editSelectedVideoKeyframes(.delete(store.validVideoKeyframeSelection));await store.geometryTask?.value
    XCTAssertEqual(store.document.layers[0].videoKeyframes?.count,2);XCTAssertTrue(store.validVideoKeyframeSelection.isEmpty)
    let view=NSHostingView(rootView:VideoTimelinePanel(store:store));view.frame=NSRect(x:0,y:0,width:1280,height:320);view.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(view.fittingSize.width,1280)
    let count=store.session.undoStack.count;store.geometryBusy=true;store.copySelectedVideoKeyframes();store.editSelectedVideoKeyframes(.delete(selection));store.geometryBusy=false
    XCTAssertEqual(store.session.undoStack.count,count)
  }
  @MainActor func testHTTPSelectionClipboardIsolationHistoryGuardsAndSchemas()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      let store=document.store,share=try XCTUnwrap(service.shares.first?.id)
      @MainActor func edit(_ params:[String:Any],revision:String?=nil)async throws->Int {try await helper.edit(service,document,"video.keyframe",params,revision:revision)}
      do {let code=try await edit(["operation":"selectAll"]);XCTAssertEqual(code,200)};XCTAssertEqual(store.validVideoKeyframeSelection.count,2)
      do {let code=try await edit(["operation":"copy"]);XCTAssertEqual(code,403)};XCTAssertNil(store.apiVideoKeyframeClipboard)
      service.setDocumentTransfersEnabled(true)
      let native=VideoKeyframePasteboard();store.videoKeyframePasteboard=native
      do {let code=try await edit(["operation":"copy"]);XCTAssertEqual(code,200)};XCTAssertNil(native.value);XCTAssertTrue(store.session.undoStack.isEmpty)
      do {let code=try await edit(["operation":"paste","time":2]);XCTAssertEqual(code,200)};XCTAssertEqual(store.document.layers[0].videoKeyframes?.map(\.time),[0,1,2,3]);XCTAssertEqual(store.validVideoKeyframeSelection.count,2)
      let current=store.document,history=store.session.undoStack.count,revision=service.revision(store)
      do {let code=try await edit(["operation":"deleteSelected"],revision:"old");XCTAssertEqual(code,409)}
      do {let code=try await edit(["operation":"select","keys":[["layerID":original.layers[0].id.uuidString,"keyframeID":UUID().uuidString]]]);XCTAssertEqual(code,422)}
      do {let code=try await edit(["operation":"select","keys":[],"selectionMode":"bad"]);XCTAssertEqual(code,400)}
      do {let code=try await edit(["operation":"copy","time":2]);XCTAssertEqual(code,400)}
      store.geometryBusy=true;do {let code=try await edit(["operation":"deleteSelected"]);XCTAssertEqual(code,409)};store.geometryBusy=false
      XCTAssertEqual(store.document,current);XCTAssertEqual(store.session.undoStack.count,history);XCTAssertEqual(service.revision(store),revision)
      do {let code=try await edit(["operation":"interpolateSelected","interpolation":"hold"]);XCTAssertEqual(code,200)}
      do {let code=try await edit(["operation":"deleteSelected"]);XCTAssertEqual(code,200)};XCTAssertEqual(store.document.layers[0].videoKeyframes?.count,2)
      do {let changed=await store.undo();XCTAssertTrue(changed)};XCTAssertEqual(store.document.layers[0].videoKeyframes?.count,4)
      let body=try await helper.request(service,path:"/v1/documents/\(share)")
      XCTAssertEqual(body.0.statusCode,200)
      XCTAssertNotNil(VideoAPI.stateSchema["properties"]);XCTAssertNotNil(VideoKeyframeAPI.capabilities["selectionEditing"])
      let commandSchema=try XCTUnwrap(AutomationCommand.definitions.first{$0.name==VideoKeyframeAPI.name})
      XCTAssertEqual(AutomationCommand.definitions.count,271);XCTAssertTrue(commandSchema.optionalParameters.contains("keys"))
      service.setDocumentTransfersEnabled(false);service.setDocumentTransfersEnabled(true)
      do {let code=try await edit(["operation":"paste","time":4]);XCTAssertEqual(code,409)}
      XCTAssertNil(service.currentKeyframeClipboard(store,shareID:share))
    }
  }
  @MainActor func testHTTPExplicitCrossDocumentClipboardNeedsSharedSourceRevisionAndGrant()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,source in
      source.store.session=EditorSession(document:try self.fixture());let target=CraftNSDocument(model:try self.fixture());service.controller.addDocument(target)
      defer{target.store.renderTask?.cancel();target.windowControllers.forEach{$0.close()};service.controller.removeDocument(target)}
      try service.share(source);try service.share(target);service.setDocumentTransfersEnabled(true)
      let a=try XCTUnwrap(service.shares.first{$0.document===source}?.id)
      let targetID=try XCTUnwrap(service.shares.first{$0.document===target}?.id)
      @MainActor func targetEdit(_ parameters:[String:Any])async throws->Int {
        try await helper.request(service,path:"/v1/documents/\(targetID)/commands",body:["command":"video.keyframe","revision":service.revision(target.store),"parameters":parameters]).0.statusCode
      }
      do {let code=try await helper.edit(service,source,"video.keyframe",["operation":"selectAll"]);XCTAssertEqual(code,200)}
      do {let code=try await helper.edit(service,source,"video.keyframe",["operation":"copy"]);XCTAssertEqual(code,200)}
      let before=target.store.document
      let parameters:[String:Any]=["operation":"paste","time":2,"sourceDocumentID":a.uuidString,"sourceRevision":service.revision(source.store)]
      var stale=parameters;stale["sourceRevision"]="old"
      do {let code=try await targetEdit(stale);XCTAssertEqual(code,409)};XCTAssertEqual(target.store.document,before)
      do {let code=try await targetEdit(parameters);XCTAssertEqual(code,200)}
      XCTAssertEqual(target.store.document.layers[0].videoKeyframes?.map(\.time),[0,1,2,3]);XCTAssertEqual(source.store.document.layers[0].videoKeyframes?.count,2)
      source.store.layerPanelGeneration=UUID()
      do {let code=try await targetEdit(parameters);XCTAssertEqual(code,404)}
    }
  }
}
