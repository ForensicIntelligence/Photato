import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class MultiLUTGate:@unchecked Sendable {
  private let lock=NSCondition();private var started=false,released=false
  func wait()throws {lock.lock();started=true;lock.broadcast();while !released {if Task.isCancelled {lock.unlock();throw CancellationError()};_ = lock.wait(until:Date(timeIntervalSinceNow:0.01))};lock.unlock();try Task.checkCancellation()}
  func release(){lock.lock();released=true;lock.broadcast();lock.unlock()}
  var ready:Bool {lock.lock();defer{lock.unlock()};return started}
}
final class ColorLookupMultiExportTests:XCTestCase {
  func fixture()throws->CraftDocument {var d=try CraftDocument(width:8,height:6);d.layers[0].background=true;d.layers.append(Layer(name:"Invert",content:.adjustment(.invert)));return d}
  @MainActor private func wait(_ gate:MultiLUTGate)async throws {for _ in 0..<1000 {if gate.ready{return};try await Task.sleep(for:.milliseconds(2))};XCTFail("Worker did not start");throw CancellationError()}
  @MainActor func testNativeMultiFormatControlsAndNamedFileWrappersPublishExactFilesWithoutHistory()async throws {
    _ = NSApplication.shared
    let store=EditorStore(document:try fixture());defer{store.cancelColorLookupExport();store.renderTask?.cancel()}
    let original=store.document;store.beginColorLookupExport();let draft=try XCTUnwrap(store.colorLookupExportDraft)
    XCTAssertEqual(draft.formats,[.cube]);draft.formats=ColorLookupFileFormat.allCases;draft.size=3;draft.copyright="FI Test";draft.baseName="Owned grade"
    let files=try await store.encodedColorLookupFiles(draft.request,draft:draft)
    XCTAssertEqual(files.map(\.format),ColorLookupFileFormat.allCases);XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
    let directory=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("photato-owned-lut-set-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:directory)}
    var wrappers:[String:FileWrapper]=[:]
    for file in files {let document=LUTDocument(data:file.data,filename:file.name);let wrapper=document.outputWrapper();XCTAssertEqual(wrapper.preferredFilename,file.name);wrappers[file.name]=wrapper}
    try FileWrapper(directoryWithFileWrappers:wrappers).write(to:directory,options:.atomic,originalContentsURL:nil)
    for file in files {XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(file.name)),file.data)}
    let host=NSHostingView(rootView:ColorLookupExportSheet(store:store,draft:draft));host.frame = .init(x:0,y:0,width:560,height:500);host.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(host.fittingSize.width,560);XCTAssertLessThanOrEqual(host.fittingSize.height,540)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) {
      host.cacheDisplay(in:host.bounds,to:bitmap);try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path).appendingPathComponent("color-lookup-multiple-options.png"))
    }
    store.cancelColorLookupExport();XCTAssertFalse(store.geometryBusy);XCTAssertNil(store.colorLookupFilesWorker)
  }
  @MainActor func testEveryHTTPFormatAndSelectedZIPMatchNativeWithPinnedMetadataAndNoDocumentChanges()async throws {
    let helper=AutomationTests(),original=try fixture()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
      document.store.session=EditorSession(document:original);try service.share(document);service.setDocumentTransfersEnabled(true)
      let share=try XCTUnwrap(service.shares.first),revision=service.revision(document.store)
      let created=Date(timeIntervalSince1970:1793923200),request=ColorLookupExportRequest(size:3,title:"Owned grade",copyright:"FI Test",formats:ColorLookupFileFormat.allCases,baseName:"Owned grade",created:created)
      let native=try await document.store.encodedColorLookupFiles(request)
      let headers=["X-Photato-LUT-Grid-Points":"3","X-Photato-LUT-Description":"Owned%20grade","X-Photato-LUT-Copyright":"FI%20Test","X-Photato-LUT-Filename":"Owned%20grade","X-Photato-LUT-Created":ISO8601DateFormatter().string(from:created),"X-Photato-Revision":revision]
      let prefix="/v1/documents/\(share.id)/color-lookup."
      for file in native {let result=try await helper.request(service,path:prefix+file.format.rawValue,headers:headers);XCTAssertEqual(result.0.statusCode,200);XCTAssertEqual(result.1,file.data)}
      let all=try await helper.request(service,path:prefix+"zip",headers:headers);XCTAssertEqual(all.0.statusCode,200);XCTAssertEqual(all.1,try ColorLookupExport.archive(native))
      var selected=headers;selected["X-Photato-LUT-Formats"]="icc,csp"
      let subset=try await helper.request(service,path:prefix+"zip",headers:selected);XCTAssertEqual(subset.0.statusCode,200);XCTAssertEqual(subset.1,try ColorLookupExport.archive(native.filter{[ColorLookupFileFormat.csp,.icc].contains($0.format)}))
      XCTAssertEqual(document.store.document,original);XCTAssertEqual(service.revision(document.store),revision);XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertFalse(document.isDocumentEdited)
      let state=service.colorLookupExportState(document.store),value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:state));XCTAssertNoThrow(try BrushAPI.merge(value,schema:AutomationService.colorLookupExportStateSchema))
      let cap=try XCTUnwrap(AutomationService.colorLookupCapabilities["stackExport"]as?[String:Any]);XCTAssertEqual(cap["formats"]as?[String],ColorLookupFileFormat.allCases.map(\.rawValue));XCTAssertEqual(AutomationCommand.definitions.count,250)
    }
  }
  @MainActor func testNewMetadataAndFormatGuardsRejectInvalidStaleDisabledAndRevokedTransfers()async throws {
    let helper=AutomationTests(),original=try fixture()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
      document.store.session=EditorSession(document:original);try service.share(document);let share=try XCTUnwrap(service.shares.first),prefix="/v1/documents/\(share.id)/color-lookup."
      let denied=try await helper.request(service,path:prefix+"icc");XCTAssertEqual(denied.0.statusCode,403);service.setDocumentTransfersEnabled(true)
      for extra in [["X-Photato-LUT-Formats":""],["X-Photato-LUT-Formats":"csp,csp"],["X-Photato-LUT-Formats":"unknown"],["X-Photato-LUT-Copyright":"%0A"],["X-Photato-LUT-Filename":"..%2Fescape"],["X-Photato-LUT-Created":"invalid"]] {
        var headers=extra;headers["X-Photato-LUT-Grid-Points"]="2";let result=try await helper.request(service,path:prefix+"zip",headers:headers);XCTAssertEqual(result.0.statusCode,400)
      }
      let bad=try await helper.request(service,path:prefix+"csp",headers:["X-Photato-LUT-Formats":"csp"]);XCTAssertEqual(bad.0.statusCode,400)
      let stale=try await helper.request(service,path:prefix+"icc",headers:["X-Photato-Revision":"stale"]);XCTAssertEqual(stale.0.statusCode,409)
      service.revoke(share.id);let revoked=try await helper.request(service,path:prefix+"zip");XCTAssertEqual(revoked.0.statusCode,404)
      XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNativeSetAndHTTPBundleCancellationAndChangedSourceDiscardEveryFormat()async throws {
    let original=try fixture(),store=EditorStore(document:original),gate=MultiLUTGate()
    defer{gate.release();store.cancelColorLookupExport();store.renderTask?.cancel()}
    store.colorLookupFilesPreparation={d,r in try gate.wait();return try ColorLookupExport.files(d,request:r)};store.beginColorLookupExport();let draft=try XCTUnwrap(store.colorLookupExportDraft);draft.formats=ColorLookupFileFormat.allCases;draft.size=2
    let pending=Task {try await store.encodedColorLookupFiles(draft.request,draft:draft)};try await wait(gate);XCTAssertNotNil(store.colorLookupFilesWorker);store.cancelColorLookupExport();gate.release()
    do {_ = try await pending.value;XCTFail("Cancelled set delivered")}catch is CancellationError {}catch {XCTFail("Unexpected \(error)")}
    XCTAssertEqual(store.document,original);XCTAssertNil(store.colorLookupExportID);XCTAssertFalse(store.geometryBusy)
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let gate=MultiLUTGate();defer{gate.release()};document.store.session=EditorSession(document:original);document.store.colorLookupFilesPreparation={d,r in try gate.wait();return try ColorLookupExport.files(d,request:r)}
      try service.share(document);service.setDocumentTransfersEnabled(true);let share=try XCTUnwrap(service.shares.first)
      let transfer=Task {try await helper.request(service,path:"/v1/documents/\(share.id)/color-lookup.zip",headers:["X-Photato-LUT-Grid-Points":"2"])};try await self.wait(gate)
      XCTAssertEqual(Set(document.store.colorLookupExportActiveFormats),Set(ColorLookupFileFormat.allCases));service.setDocumentTransfersEnabled(false);gate.release()
      let result=try await transfer.value;XCTAssertEqual(result.0.statusCode,409);XCTAssertFalse(result.1.starts(with:[0x50,0x4b]));XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
    let changedGate=MultiLUTGate();defer{changedGate.release()};store.colorLookupFilesPreparation={d,r in try changedGate.wait();return try ColorLookupExport.files(d,request:r)}
    store.beginColorLookupExport();let stale=try XCTUnwrap(store.colorLookupExportDraft);stale.formats=[.icc];stale.size=2;let stalePending=Task {try await store.encodedColorLookupFiles(stale.request,draft:stale)};try await wait(changedGate)
    var changed=original;changed.name="Changed";store.session=EditorSession(document:changed);changedGate.release()
    do {_ = try await stalePending.value;XCTFail("Changed source delivered")}catch is CancellationError {}catch {XCTFail("Unexpected \(error)")};XCTAssertEqual(store.document,changed)
  }
}
