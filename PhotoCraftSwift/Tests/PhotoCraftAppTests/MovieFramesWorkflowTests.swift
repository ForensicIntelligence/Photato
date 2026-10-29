import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class MovieFramesWorkflowTests: XCTestCase {
  var fixture: URL {MovieWorkflowTests().fixture}
  var longFixture: URL {fixture.deletingLastPathComponent().appendingPathComponent("owned-too-many.mov")}
  func header(_ options: MovieFrameImportOptions) throws -> String {String(decoding:try JSONEncoder().encode(options),as:UTF8.self)}
  @MainActor func cleanup(_ service: AutomationService,_ first: CraftNSDocument) {service.controller.cancelMovieFrames();HDRMergeWorkflowTests().cleanup(service.controller,except:first)}
  @MainActor func testStrictUploadOptionsAndDiscovery() throws {
    XCTAssertNil(try MovieFramesAPI.options(nil));XCTAssertEqual(try MovieFramesAPI.options("{}"),MovieFrameImportOptions())
    for value in ["[]","{\"every\":0}","{\"every\":1.5}","{\"unknown\":true}","{\"start\":2,\"end\":1}","{\"makeAnimation\":\"yes\"}","{\"every\":10001}"] {XCTAssertThrowsError(try MovieFramesAPI.options(value),value)}
    XCTAssertNotNil(AutomationService.capabilities["movieFramesImport"])
    XCTAssertNotNil(AutomationService.documentTransferCapabilities["movieFramesImport"])
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:MovieFramesAPI.cancelPath),65_536)
  }
  @MainActor func testNativePreviewControlsMenuAndNewEditableDocument() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      defer {cleanup(service,first)}
      let sourceURL = fixture.deletingLastPathComponent().appendingPathComponent("owned-h264.mp4")
      let original = first.store.document,bytes = try Data(contentsOf:sourceURL)
      service.controller.beginMovieFrames(display:false)
      let model = try XCTUnwrap(service.controller.movieFramesWorkspace);model.load(sourceURL);await model.loadTask?.value
      XCTAssertNil(model.error);XCTAssertNotNil(model.player);XCTAssertEqual(model.source?.data,bytes)
      for _ in 0..<100 where model.player?.currentItem?.status == .unknown {try await Task.sleep(for:.milliseconds(10))}
      XCTAssertEqual(model.player?.currentItem?.status,.readyToPlay,model.player?.currentItem?.error?.localizedDescription ?? "Preview item did not become ready")
      let previewURL = try XCTUnwrap(model.source?.url);XCTAssertTrue(FileManager.default.fileExists(atPath:previewURL.path))
      model.options.selectedRange = true;model.options.start = 0.12;model.options.end = 0.44;model.options.every = 2
      let expected = try MovieFrames.decode(bytes,name:"owned-h264",options:model.options)
      let previous = NSApp.mainMenu;defer {NSApp.mainMenu = previous};AppDelegate().installPhotoshopMenus()
      let item = NSApp.mainMenu?.items.first{$0.title == "File"}?.submenu?.items.first{$0.title == "Import"}?.submenu?.items.first{$0.title == "Video Frames to Layers…"}
      XCTAssertEqual(item?.action,#selector(AppDelegate.videoFramesToLayers));XCTAssertEqual(item?.keyEquivalent,"")
      if let directory = ProcessInfo.processInfo.environment["PHOTATO_MOVIE_FRAMES_OUTPUT"] {
        let root = URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let host = NSHostingView(rootView:MovieFramesView(model:model).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:540),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.aqua);window.contentView = host
        host.frame = NSRect(x:0,y:0,width:820,height:540);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(100));host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:root.appendingPathComponent("movie-frames-controls.png"));window.close()
      }
      model.run(display:false);await model.task?.value
      XCTAssertNil(model.error);let created = try XCTUnwrap(model.created)
      XCTAssertEqual(created.store.document.layers.map(\.content),expected.layers.map(\.content));XCTAssertEqual(created.store.document.animation?.frames.map(\.delay),expected.animation?.frames.map(\.delay))
      XCTAssertTrue(created.isDocumentEdited);XCTAssertNil(created.fileURL);XCTAssertTrue(created.store.timelineVisible)
      XCTAssertEqual(first.store.document,original);XCTAssertEqual(try Data(contentsOf:sourceURL),bytes)
      XCTAssertFalse(FileManager.default.fileExists(atPath:previewURL.path));XCTAssertNil(service.controller.movieFramesWorkspace)
      XCTAssertEqual(created.store.document.minimumArchiveVersion,60)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(created.store.document)),created.store.document)
    }
  }
  @MainActor func testNativeCancelAndClosePublishNothing() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      defer {cleanup(service,first)}
      for close in [false,true] {
        service.controller.beginMovieFrames(display:false);let model = try XCTUnwrap(service.controller.movieFramesWorkspace)
        model.load(longFixture);await model.loadTask?.value;XCTAssertNil(model.error)
        model.options.selectedRange = true
        for invalid in [Double.nan,Double.infinity,-1,1e200] {model.options.start = invalid;model.seekStart()}
        model.run(display:false);XCTAssertNotNil(model.error);XCTAssertNil(model.created)
        model.options = .init();model.options.every = 9;model.run(display:false)
        if close {service.controller.cancelMovieFrames()} else {model.cancelImport()}
        await model.task?.value
        XCTAssertNil(model.created);XCTAssertEqual(service.controller.documents.count,1);XCTAssertFalse(model.busy)
        service.controller.cancelMovieFrames()
      }
    }
  }
  @MainActor func testHTTPUploadMatchesNativeAndSelectedLongMovieWithGuards() async throws {
    let files = DocumentIOWorkflowTests(),bytes = try Data(contentsOf:fixture)
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      defer {cleanup(service,first)}
      let before = first.store.document
      var options = MovieFrameImportOptions();options.selectedRange = true;options.start = 0.12;options.end = 0.44;options.every = 2
      let headers = ["X-Photato-Movie-Frames":try header(options),"X-Photato-Name":"Owned frames"]
      let denied = try await files.request(service,path:"/v1/documents/import",data:bytes,type:"video/quicktime",headers:headers);XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let response = try await files.request(service,path:"/v1/documents/import",data:bytes,type:"video/quicktime",headers:headers)
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let document = try XCTUnwrap(service.shares.first?.document),native = try MovieFrames.decode(bytes,name:"Owned frames",options:options)
      XCTAssertEqual(document.store.document.layers.map(\.content),native.layers.map(\.content));XCTAssertEqual(document.store.document.animation?.frames.map(\.delay),native.animation?.frames.map(\.delay));XCTAssertTrue(document.store.timelineVisible)
      XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertEqual(first.store.document,before)
      let invalid = try await files.request(service,path:"/v1/documents/import",data:bytes,type:"video/quicktime",headers:["X-Photato-Movie-Frames":"{\"unknown\":true}"]);XCTAssertEqual(invalid.0.statusCode,400)
      options = .init();options.every = 9;options.makeAnimation = false
      let longer = try await files.request(service,path:"/v1/documents/import",data:Data(contentsOf:longFixture),type:"video/quicktime",headers:["X-Photato-Movie-Frames":try header(options)])
      XCTAssertEqual(longer.0.statusCode,201,String(decoding:longer.1,as:UTF8.self));let layers = try XCTUnwrap(service.shares.last?.document).store.document
      XCTAssertNil(layers.animation);XCTAssertGreaterThan(layers.layers.count,1);XCTAssertLessThanOrEqual(layers.layers.count,64)
      XCTAssertNil(service.movieFramesImportOperationID);XCTAssertNil(service.movieFramesImportTask);XCTAssertFalse(service.documentTransferBusy)
    }
  }
  @MainActor func testHTTPActiveCancellationAndPermissionRevocationPublishNothing() async throws {
    let files = DocumentIOWorkflowTests(),bytes = try Data(contentsOf:longFixture);var options = MovieFrameImportOptions();options.every = 9
    for revoke in [false,true] {
      try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
        defer {cleanup(service,first)}
        service.setDocumentTransfersEnabled(true)
        let task = Task {try await files.request(service,path:"/v1/documents/import",data:bytes,type:"video/quicktime",headers:["X-Photato-Movie-Frames":try header(options)])}
        let deadline = Date().addingTimeInterval(10)
        while service.movieFramesImportOperationID == nil && Date()<deadline {try await Task.sleep(for:.milliseconds(2))}
        let operation = try XCTUnwrap(service.movieFramesImportOperationID)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let reply = try await files.request(service,path:MovieFramesAPI.cancelPath,data:JSONSerialization.data(withJSONObject:["operationID":operation.uuidString]),type:"application/json")
          XCTAssertEqual(reply.0.statusCode,200)
        }
        let result = try await task.value;XCTAssertEqual(result.0.statusCode,409);XCTAssertEqual(service.controller.documents.count,1);XCTAssertTrue(service.shares.isEmpty);XCTAssertNil(service.movieFramesImportTask);XCTAssertFalse(service.documentTransferBusy)
      }
    }
  }
}
