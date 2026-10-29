import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class AnimationInterchangeTests: XCTestCase {
  var fixture: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/animation/owned-disposal.gif") }
  @MainActor func testNativeOpenEncoderAndHTTPImportExportAreEquivalent() async throws {
    let input=try Data(contentsOf:fixture),native=try DocumentIO.read(fixture)
    XCTAssertEqual(native.animation?.frames.count,4)
    let store=EditorStore(document:native);defer{store.renderTask?.cancel()}
    XCTAssertTrue(store.timelineVisible)
    let bytes=try await store.encodedAnimation();XCTAssertEqual(bytes,try AnimationGIF.encode(native))
    XCTAssertEqual(store.document,native);XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.animationExportID)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,_ in
      defer { for document in service.controller.documents.compactMap({$0 as? CraftNSDocument}) { document.store.renderTask?.cancel();service.controller.removeDocument(document) } }
      service.setDocumentTransfersEnabled(true)
      let imported=try await files.request(service,path:"/v1/documents/import",data:input,type:"image/gif")
      XCTAssertEqual(imported.0.statusCode,201,String(decoding:imported.1,as:UTF8.self))
      let document=try XCTUnwrap(service.shares.first?.document),id=try XCTUnwrap(service.shares.first?.id)
      XCTAssertEqual(document.store.document.animation?.frames.count,4)
      let before=document.store.document,revision=service.revision(document.store),dirty=document.isDocumentEdited
      let result=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"animation.export","revision":revision,"parameters":["format":"gif"]])
      XCTAssertEqual(result.0.statusCode,200,String(decoding:result.1.prefix(250),as:UTF8.self));XCTAssertEqual(result.0.value(forHTTPHeaderField:"Content-Type"),"image/gif")
      XCTAssertEqual(result.1,try AnimationGIF.encode(before));XCTAssertEqual(result.1,bytes)
      XCTAssertEqual(document.store.document,before);XCTAssertEqual(document.isDocumentEdited,dirty);XCTAssertEqual(service.revision(document.store),revision)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      for (params,expected) in [(["format":"png"] as [String:Any],400),(["format":"gif","alphaThreshold":2],400)] {
        let status=try await helper.edit(service,document,"animation.export",params);XCTAssertEqual(status,expected)
      }
      let stale=try await helper.edit(service,document,"animation.export",["format":"gif"],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"animation.export",["format":"gif"]);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      service.setDocumentTransfersEnabled(false)
      let disabled=try await helper.edit(service,document,"animation.export",["format":"gif"]);XCTAssertEqual(disabled,403)
    }
  }
  @MainActor func testCancelActiveAPIExportPreservesSourceAndReleasesBusyState() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      var d=try CraftDocument(width:512,height:512)
      let layer=Layer(name:"Frame",content:.raster(try Surface(width:512,height:512,fill:Pixel(1,0,0))))
      d.layers=[layer];d.activeLayerID=layer.id;d.animation=FrameAnimation(layers:d.layers)
      d.animation!.frames=(0..<100).map{_ in AnimationFrame(layers:d.layers)};d.animation!.selectedFrameID=d.animation!.frames[0].id
      document.store.session=EditorSession(document:d);try service.share(document);service.setDocumentTransfersEnabled(true)
      let worker=Task { try await helper.edit(service,document,"animation.export",["format":"gif"]) }
      for _ in 0..<200 where document.store.animationExportID == nil { try await Task.sleep(for:.milliseconds(5)) }
      let operation=try XCTUnwrap(document.store.animationExportID)
      let cancelled=try await helper.edit(service,document,"animation.export.cancel",["operationID":operation.uuidString]);XCTAssertEqual(cancelled,200)
      let result=try await worker.value;XCTAssertEqual(result,409)
      XCTAssertEqual(document.store.document,d);XCTAssertNil(document.store.animationExportID);XCTAssertFalse(document.store.geometryBusy)
      let missing=try await helper.edit(service,document,"animation.export.cancel",["operationID":operation.uuidString]);XCTAssertEqual(missing,409)
    }
  }
  func testFailedOrCancelledExportPreservesDestination() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("existing.gif"),original=Data("existing owned content".utf8);try original.write(to:url)
    let worker=Task { try await Task.sleep(for:.milliseconds(10));try AnimationExport.write(Data("replacement".utf8),to:url) };worker.cancel()
    do { try await worker.value;XCTFail("Cancelled write succeeded") } catch is CancellationError {}
    XCTAssertEqual(try Data(contentsOf:url),original)
    let bytes=try AnimationGIF.encode(DocumentIO.read(fixture));try AnimationExport.write(bytes,to:url);XCTAssertEqual(try Data(contentsOf:url),bytes)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),["existing.gif"])
  }
}
