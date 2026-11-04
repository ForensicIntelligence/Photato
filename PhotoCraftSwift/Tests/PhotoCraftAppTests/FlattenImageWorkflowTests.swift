import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private final class FlattenGate: @unchecked Sendable {
  let condition=NSCondition(); var released=false
  func wait() {condition.lock();while !released {condition.wait()};condition.unlock()}
  func release() {condition.lock();released=true;condition.broadcast();condition.unlock()}
}
final class FlattenImageWorkflowTests: XCTestCase {
  func fixture(hidden:Bool=true) throws -> CraftDocument {
    var d=try CraftDocument(width:4,height:3);d.layers[0].background=true
    var layer=Layer(name:"Blue",content:.raster(try Surface(width:4,height:3,fill:Pixel(0,0,1))));layer.visible = !hidden
    d.layers.append(layer);return d
  }
  @MainActor func testNativeConfirmationCancelCommitAndUndoUseOneTransaction() async throws {
    _=NSApplication.shared
    let source=try fixture(),s=EditorStore(document:source);defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
    var prompts=0;s.flattenImageConfirmation={ request in prompts += 1;XCTAssertTrue(s.geometryBusy);XCTAssertEqual(request.hiddenLayerIDs,[source.layers[1].id]);return false}
    s.requestFlattenImage();XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.flattenImageConfirmation={_ in true};s.requestFlattenImage();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,1);XCTAssertTrue(s.document.layers[0].isBackground)
    XCTAssertEqual(s.selectedLayerIDs,[source.layers[0].id]);XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(prompts,1)
    _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)
    let alert=FlattenImageAlert.make(.init(original:source));XCTAssertEqual(alert.messageText,"Discard hidden layers?");XCTAssertEqual(alert.buttons.map(\.title),["OK","Cancel"])
  }
  @MainActor func testNativeConfirmationCancellationAndChangedSourceDoNotCommit() async throws {
    let source=try fixture(),s=EditorStore(document:source);defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
    s.flattenImageConfirmation={_ in s.cancelActiveOperation();return true};s.requestFlattenImage();await s.geometryTask?.value
    XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.flattenImageConfirmation={_ in var changed=source;changed.name="Changed during confirmation";s.session=EditorSession(document:changed);return true}
    s.requestFlattenImage();await s.geometryTask?.value
    XCTAssertEqual(s.document.name,"Changed during confirmation");XCTAssertEqual(s.document.layers.count,2);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertNotNil(s.error)
  }
  @MainActor func testHTTPHiddenApprovalEquivalentResultUndoAndArchive() async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
      let source=try self.fixture();doc.store.session=EditorSession(document:source);try service.share(doc)
      let rejected=try await h.edit(service,doc,"layer.flatten");XCTAssertEqual(rejected,422);XCTAssertEqual(doc.store.document,source)
      let expected=try FlattenPreparation.prepare(source).result
      let accepted=try await h.edit(service,doc,"layer.flatten",["discardHiddenLayers":true]);XCTAssertEqual(accepted,200);XCTAssertEqual(doc.store.document,expected);XCTAssertEqual(doc.store.session.undoStack.count,1)
      XCTAssertFalse(doc.store.canFlattenImage)
      service.setDocumentTransfersEnabled(true);let id=try XCTUnwrap(service.shares.first?.id)
      let file=try await h.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"84"])
      XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),expected)
      let undo=try await h.edit(service,doc,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(doc.store.document,source)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndUnsupportedTargetLeaveHistoryUntouched() async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
      let source=try self.fixture(hidden:false);doc.store.session=EditorSession(document:source);try service.share(doc)
      let invalid=try await h.edit(service,doc,"layer.flatten",["discardHiddenLayers":"yes"]);XCTAssertEqual(invalid,400)
      let stale=try await h.edit(service,doc,"layer.flatten",revision:"old");XCTAssertEqual(stale,409)
      doc.store.geometryBusy=true;let busy=try await h.edit(service,doc,"layer.flatten");XCTAssertEqual(busy,409);doc.store.geometryBusy=false
      XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testInFlightCancelAndRevocationCannotPublishFlatten() async throws {
    for revoke in [false,true] {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
        let source=try self.fixture(hidden:false);doc.store.session=EditorSession(document:source);try service.share(doc)
        let gate=FlattenGate();defer{gate.release()};doc.store.flattenImagePreparation={original in gate.wait();try Task.checkCancellation();return try FlattenPreparation.command(original)}
        let pending=Task{try await h.edit(service,doc,"layer.flatten")};let end=Date().addingTimeInterval(10)
        while !doc.store.geometryBusy && Date()<end {await Task.yield()};XCTAssertTrue(doc.store.geometryBusy)
        if revoke {service.revoke(try XCTUnwrap(service.shares.first?.id))} else {doc.store.cancelActiveOperation()}
        gate.release();let status=try await pending.value;XCTAssertEqual(status,409)
        XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testSemanticActionVersionDiscoverySchemaAndFactoryMenuStayAligned() throws {
    let source=try fixture(hidden:false);var session=EditorSession(document:source)
    try session.startActionRecording(name:"Flatten");try session.execute(FlattenPreparation.command(source))
    let action=try XCTUnwrap(session.actionRecording?.snapshot),file=ActionLibraryFile(actions:[action])
    XCTAssertEqual(file.requiredVersion,43);let data=try file.encoded();XCTAssertEqual(try ActionLibraryFile.decode(data).version,43)
    var downgraded=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]);downgraded["version"]=42
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
    let s=EditorStore(document:source);defer{s.renderTask?.cancel()}
    let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.flattenImageState))
    XCTAssertNoThrow(try BrushAPI.merge(value,schema:FlattenImageAPI.stateSchema))
    func all(_ nodes:[EditorMenuNode])->[EditorMenuNode] {nodes.flatMap{[$0]+all($0.children ?? [])}}
    let menus=all(PhotoshopMenuCatalog.menus);let flatten=try XCTUnwrap(menus.first{$0.title=="Flatten Image"})
    XCTAssertEqual(flatten.key,"");XCTAssertEqual(NSStringFromSelector(#selector(AppDelegate.flattenImage)),"flattenImage")
    XCTAssertEqual(AutomationTests.expectedCommandCount,242);XCTAssertEqual(ActionLibraryFile.maximumVersion,46)
  }
  @MainActor func testOfficialFlattenEventRunsThroughBothHTTPJobInterfaces() async throws {
    let transport=AutomationActionJobsTests.Transport(),jobs=AutomationActionJobsTests()
    let source=try fixture(),encoded=try PSDCodec.writeRasterLayers(source)
    await transport.set(encoded)
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) {service,shared in
      let untouched=shared.store.document;service.setResourceJobsEnabled(true)
      let payload:[String:Any]=["image":["source":["url":"https://example.test/flatten.psd"]],"options":["actions":[["source":["content":"[{\"_obj\":\"flattenImage\"}]","contentType":"application/json"]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
      var bytes:[Data]=[]
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        let output=try await jobs.output(service,submit:route,payload:payload);bytes.append(output.2)
        let read=try PSDCodec.read(output.2);XCTAssertEqual(read.layers.count,1);XCTAssertTrue(read.layers[0].isBackground)
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),Data(repeating:255,count:4*3*4))
      }
      XCTAssertEqual(bytes[0],bytes[1]);XCTAssertEqual(shared.store.document,untouched);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
}
