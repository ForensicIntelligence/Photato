import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MovieWorkflowTests:XCTestCase {
  var fixture:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/movies/owned-vfr-audio.mov")}
  @MainActor func testOpenAndNativeLayerImportPreserveSourceAndUndo() async throws {
    XCTAssertEqual(DocumentOpenFormat.detect(fixture),.movie)
    let prepared=try PreparedLocalDocument.read(fixture,format:.movie),bytes=try Data(contentsOf:fixture)
    XCTAssertNil(prepared.format);XCTAssertEqual(prepared.model.layers[0].video?.movie?.data,bytes)
    let opened=prepared.makeDocument(url:fixture);XCTAssertNil(opened.fileURL);XCTAssertEqual(opened.importedSourceURL,fixture.standardizedFileURL.resolvingSymlinksInPath());opened.store.renderTask?.cancel()
    let target=try CraftDocument(width:32,height:24),store=EditorStore(document:target);defer{store.renderTask?.cancel()}
    try await store.importMovieLayer(fixture);XCTAssertEqual(store.document.layers.count,2);XCTAssertTrue(store.timelineVisible)
    XCTAssertEqual(store.document.layers.last?.video?.movie?.data,bytes);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.moviePlacementID)
    let after=store.document;let undone=await store.undo();XCTAssertTrue(undone);XCTAssertEqual(store.document,target);let redone=await store.redo();XCTAssertTrue(redone);XCTAssertEqual(store.document,after)
    XCTAssertEqual(try Data(contentsOf:fixture),bytes)
    store.geometryBusy=true;do{try await store.importMovieLayer(fixture);XCTFail("Busy import succeeded")}catch{};XCTAssertEqual(store.document,after);store.geometryBusy=false
  }
  @MainActor func testRealHTTPMovieUploadPlacementArchiveAndGuards() async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests(),input=try Data(contentsOf:fixture),native=try DocumentIO.read(fixture)
    try await helper.withService(pressedMouseButtons:{0}) {service,target in
      defer{for d in service.controller.documents.compactMap({$0 as? CraftNSDocument}){d.store.renderTask?.cancel();service.controller.removeDocument(d)}}
      try service.share(target);let targetID=try XCTUnwrap(service.shares.first?.id)
      service.setDocumentTransfersEnabled(true)
      let response=try await files.request(service,path:"/v1/documents/import",data:input,type:"video/quicktime")
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let sourceShare=try XCTUnwrap(service.shares.first(where:{$0.id != targetID})),source=try XCTUnwrap(sourceShare.document)
      XCTAssertEqual(source.store.document.layers[0].video,native.layers[0].video)
      let movie=try XCTUnwrap((source.store.videoState["clips"] as? [[String:Any]])?.first?["movie"] as? [String:Any]);XCTAssertEqual(movie["audioTracks"] as? Int,1);XCTAssertEqual(movie["audioPlayback"] as? Bool,true)
      let original=target.store.document,params:[String:Any]=["sourceDocumentID":sourceShare.id.uuidString,"sourceRevision":service.revision(source.store)]
      let status=try await helper.edit(service,target,"video.place",params);XCTAssertEqual(status,200);XCTAssertEqual(target.store.document.layers.count,original.layers.count+1)
      let expected=try MovieIO.layer(from:native,into:original)
      XCTAssertEqual(target.store.document.layers.last?.video,expected.video);XCTAssertEqual(target.store.session.undoStack.count,1)
      let undone=await target.store.undo();XCTAssertTrue(undone);XCTAssertEqual(target.store.document,original)
      var stale=params;stale["sourceRevision"]="stale";let staleStatus=try await helper.edit(service,target,"video.place",stale);XCTAssertEqual(staleStatus,409)
      target.store.geometryBusy=true;let busy=try await helper.edit(service,target,"video.place",params);XCTAssertEqual(busy,409);target.store.geometryBusy=false
      service.setDocumentTransfersEnabled(false);let disabled=try await helper.edit(service,target,"video.place",params);XCTAssertEqual(disabled,403);service.setDocumentTransfersEnabled(true)
      let headers=["If-Match":service.revision(source.store),"X-Photato-Archive-Version":"52"]
      let archive=try await files.request(service,path:"/v1/documents/\(sourceShare.id)/file.photato",headers:headers)
      XCTAssertEqual(archive.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(archive.1),source.store.document)
      let old=try await files.request(service,path:"/v1/documents/\(sourceShare.id)/file.photato",headers:["If-Match":service.revision(source.store),"X-Photato-Archive-Version":"51"]);XCTAssertEqual(old.0.statusCode,422)
      let invalid=try await files.request(service,path:"/v1/documents/import",data:Data("invalid".utf8),type:"video/mp4");XCTAssertEqual(invalid.0.statusCode,422)
    }
  }
  @MainActor func testActivePlacementCancellationAndPermissionRevocation() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,target in
      try service.share(target)
      var model=try CraftDocument(width:512,height:512,depth:.u16)
      let surface=try Surface(width:512,height:512,depth:.u16,fill:Pixel(0.3,0.4,0.5))
      var layer=Layer(name:"Owned cancellation sequence",content:.raster(surface))
      layer.video=VideoClip(frames:Array(repeating:surface,count:24),frameRate:24)
      model.layers=[layer];model.activeLayerID=layer.id;model.videoTimeline=VideoTimeline(frameRate:24,durationFrames:24)
      let source=CraftNSDocument(model:model);service.controller.addDocument(source);try service.share(source)
      defer{source.store.renderTask?.cancel();target.store.renderTask?.cancel();service.controller.removeDocument(source)}
      let id=try XCTUnwrap(service.shares.first(where:{$0.document===source})?.id),before=target.store.document
      for revoke in [false,true] {
        service.setDocumentTransfersEnabled(true)
        let worker=Task{try await helper.edit(service,target,"video.place",["sourceDocumentID":id.uuidString,"sourceRevision":service.revision(source.store)])}
        for _ in 0..<200 where target.store.moviePlacementID == nil {try await Task.sleep(for:.milliseconds(5))}
        let operation=try XCTUnwrap(target.store.moviePlacementID)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let cancelled=try await helper.edit(service,target,"video.place.cancel",["operationID":operation.uuidString]);XCTAssertEqual(cancelled,200)
        }
        let result=try await worker.value;XCTAssertEqual(result,409)
        XCTAssertEqual(target.store.document,before);XCTAssertTrue(target.store.session.undoStack.isEmpty);XCTAssertFalse(target.store.geometryBusy);XCTAssertNil(target.store.moviePlacementID)
      }
    }
  }

}
