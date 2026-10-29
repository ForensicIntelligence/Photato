import AppKit
import Foundation
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ImageSequenceExportTests: XCTestCase {
  var fixtures: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures") }
  func video() throws -> CraftDocument { try VideoSequenceImport.read(["frame10.png","frame2.png","frame1.png"].map{fixtures.appendingPathComponent("videoSequence/"+$0)},frameRate:12,name:"Owned sequence") }
  func animation() throws -> CraftDocument { try DocumentIO.read(fixtures.appendingPathComponent("animation/owned-disposal.gif")) }
  func manifest(_ output:ImageSequenceOutput) throws -> [String:Any] { try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(output.files.last?.data)) as? [String:Any]) }
  func save(_ output:ImageSequenceOutput,_ name:String) throws {
    if let path = ProcessInfo.processInfo.environment["PHOTATO_SEQUENCE_OUTPUT_DIR"] { try output.zip().write(to:URL(fileURLWithPath:path).appendingPathComponent(name+".zip")) }
  }
  @MainActor func testNativeVideoAndAnimationRangeTimingNumberingAndHistory() async throws {
    let model = try video(),store = EditorStore(document:model);defer{store.renderTask?.cancel()}
    let output = try await store.encodedImageSequence(.init(prefix:"shot_",firstFrame:1,lastFrame:2,startNumber:9,digits:2))
    XCTAssertEqual(output.files.map(\.name),["shot_09.png","shot_10.png","sequence.json"])
    let rows = try XCTUnwrap(manifest(output)["frames"] as? [[String:Any]])
    XCTAssertEqual(rows.map{$0["sourceFrame"] as? Int},[1,2]);XCTAssertEqual(try XCTUnwrap(rows[0]["time"] as? Double),1.0/12,accuracy:1e-12)
    for (offset,file) in output.files.dropLast().enumerated() { XCTAssertEqual(file.data,try DocumentIO.encode(model.videoDocument(at:offset+1),format:.png)) }
    XCTAssertEqual(store.document,model);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.sequenceExportID)
    let all = try ImageSequenceExport.render(model,options:.init());try save(all,"video")
    let frames = try animation(),animated = try ImageSequenceExport.render(frames,options:.init());try save(animated,"animation")
    let delays = try XCTUnwrap(manifest(animated)["frames"] as? [[String:Any]]).compactMap{$0["duration"] as? Double}
    XCTAssertEqual(delays.count,frames.animation!.frames.count);for (a,b) in zip(delays,frames.animation!.frames.map(\.delay)) { XCTAssertEqual(a,b,accuracy:1e-12) };XCTAssertEqual(animated.files.count,5)
    XCTAssertThrowsError(try ImageSequenceExport.render(model,options:.init(firstFrame:2,lastFrame:1)))
    XCTAssertThrowsError(try ImageSequenceExport.render(model,options:.init(prefix:"../bad")))
    XCTAssertThrowsError(try ImageSequenceExport.render(model,options:.init(),maximumBytes:10))
  }
  func testPNGDepthAndHDRDisclosure() throws {
    for depth in [PixelDepth.u16,.f32] {
      var document = try CraftDocument(width:3,height:2,depth:depth);document.animation = FrameAnimation(layers:document.layers)
      let output = try ImageSequenceExport.render(document,options:.init()),meta = try manifest(output)
      XCTAssertEqual(meta["pngBitsPerChannel"] as? Int,16)
      let data = output.files[0].data;XCTAssertEqual(data[24],16)
      let decoded = try DocumentIO.decodeUpload(data,native:false,name:"Exported PNG");XCTAssertEqual(decoded.width,3);XCTAssertEqual(decoded.depth,.u16)
      if depth == .f32 { XCTAssertTrue((meta["colorPolicy"] as? String ?? "").contains("SDR sRGB16")) }
    }
  }
  func testFolderPublicationPreservesExistingAndCancellationCleansStaging() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
    let output = try ImageSequenceExport.render(video(),options:.init()),destination = directory.appendingPathComponent("frames")
    let first = try PreparedSequenceFolder.prepare(output,destination:destination);try first.commit();first.discard()
    let files = try FileManager.default.contentsOfDirectory(atPath:destination.path);XCTAssertEqual(Set(files),Set(output.files.map(\.name)))
    let second = try PreparedSequenceFolder.prepare(output,destination:destination);XCTAssertThrowsError(try second.commit());second.discard()
    for file in output.files { XCTAssertEqual(try Data(contentsOf:destination.appendingPathComponent(file.name)),file.data) }
    let cancelled = Task { try await Task.sleep(for:.milliseconds(10));return try PreparedSequenceFolder.prepare(output,destination:directory.appendingPathComponent("cancelled")) };cancelled.cancel()
    do { _ = try await cancelled.value;XCTFail("Cancelled folder succeeded") } catch is CancellationError {}
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),["frames"])
  }
  @MainActor func testHTTPExportMatchesNativeAndGuards() async throws {
    let helper = AutomationTests(),model = try video()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      document.store.session = EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let id = try XCTUnwrap(service.shares.first?.id),revision = service.revision(document.store),dirty = document.isDocumentEdited
      let response = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"sequence.export","revision":revision,"parameters":["format":"png"]])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1.prefix(120),as:UTF8.self));XCTAssertEqual(response.0.value(forHTTPHeaderField:"Content-Type"),"application/zip")
      XCTAssertEqual(response.1,try ImageSequenceExport.render(model,options:.init()).zip());XCTAssertEqual(document.store.document,model);XCTAssertEqual(service.revision(document.store),revision);XCTAssertEqual(document.isDocumentEdited,dirty);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let bad = try await helper.edit(service,document,"sequence.export",["format":"jpeg"]);XCTAssertEqual(bad,400)
      let stale = try await helper.edit(service,document,"sequence.export",["format":"png"],revision:"old");XCTAssertEqual(stale,409)
      document.store.geometryBusy = true;let busy = try await helper.edit(service,document,"sequence.export",["format":"png"]);XCTAssertEqual(busy,409);document.store.geometryBusy = false
      service.setDocumentTransfersEnabled(false);let denied = try await helper.edit(service,document,"sequence.export",["format":"png"]);XCTAssertEqual(denied,403)
    }
  }
  @MainActor func testActiveHTTPCancellationReleasesBusyState() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      var model = try CraftDocument(width:512,height:512);model.animation = FrameAnimation(layers:model.layers)
      model.animation!.frames = (0..<100).map{_ in AnimationFrame(layers:model.layers)};model.animation!.selectedFrameID = model.animation!.frames[0].id
      document.store.session = EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let job = Task { try await helper.edit(service,document,"sequence.export",["format":"png"]) }
      for _ in 0..<200 where document.store.sequenceExportID == nil { try await Task.sleep(for:.milliseconds(5)) }
      let id = try XCTUnwrap(document.store.sequenceExportID)
      let cancel = try await helper.edit(service,document,"sequence.export.cancel",["operationID":id.uuidString]);XCTAssertEqual(cancel,200)
      let result = try await job.value;XCTAssertEqual(result,409);XCTAssertEqual(document.store.document,model);XCTAssertFalse(document.store.geometryBusy);XCTAssertNil(document.store.sequenceExportID)
      let missing = try await helper.edit(service,document,"sequence.export.cancel",["operationID":id.uuidString]);XCTAssertEqual(missing,409)
    }
  }
  @MainActor func testTransferRevocationDuringExportPreventsDelivery() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,document in
      var model = try CraftDocument(width:512,height:512);model.animation = FrameAnimation(layers:model.layers)
      model.animation!.frames = (0..<100).map{_ in AnimationFrame(layers:model.layers)};model.animation!.selectedFrameID = model.animation!.frames[0].id
      document.store.session = EditorSession(document:model);try service.share(document);service.setDocumentTransfersEnabled(true)
      let job = Task { try await helper.edit(service,document,"sequence.export",["format":"png"]) }
      for _ in 0..<200 where document.store.sequenceExportID == nil { try await Task.sleep(for:.milliseconds(5)) }
      XCTAssertNotNil(document.store.sequenceExportID);let worker=try XCTUnwrap(document.store.sequenceExportWorker)
      service.setDocumentTransfersEnabled(false);XCTAssertTrue(worker.isCancelled)
      let result = try await job.value;XCTAssertEqual(result,409);XCTAssertEqual(document.store.document,model);XCTAssertFalse(document.store.geometryBusy);XCTAssertNil(document.store.sequenceExportID)
      XCTAssertTrue(service.sequenceExportShares.isEmpty)
    }
  }

}
