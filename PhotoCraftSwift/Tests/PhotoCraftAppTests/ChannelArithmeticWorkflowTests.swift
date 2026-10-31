import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ChannelArithmeticWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try CraftDocument(width:8,height:5)
    d.layers[0].content = .raster(try Surface(width:8,height:5,fill:Pixel(0.8,0.4,0.2)))
    return d
  }
  @MainActor func testNativeDialogPreviewCancelAndOneUndoCommit()async throws {
    _ = NSApplication.shared
    let controller=CraftDocumentController(),document=CraftNSDocument(model:try fixture())
    controller.addDocument(document);let store=document.store,original=store.document
    defer {store.cancelChannelArithmetic();store.renderTask?.cancel();controller.removeDocument(document)}
    store.beginChannelArithmetic(.applyImage)
    let draft=try XCTUnwrap(store.channelArithmeticWorkspace)
    await draft.task?.value;XCTAssertTrue(draft.ready);XCTAssertNil(draft.error);XCTAssertEqual(store.document,original)
    store.cancelChannelArithmetic();XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginChannelArithmetic(.applyImage);let active=try XCTUnwrap(store.channelArithmeticWorkspace)
    await active.task?.value;store.commitChannelArithmetic();await active.commitTask?.value
    XCTAssertNil(store.channelArithmeticWorkspace);XCTAssertNil(active.error);XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertNotEqual(store.document,original);await store.undo();XCTAssertEqual(store.document,original)
  }
  @MainActor func testHTTPApplyImageMatchesNativePreservesContextAndRejectsInvalidBusyStale()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original)
      try service.share(document);defer{document.store.renderTask?.cancel()}
      var request=ChannelArithmeticRequest(.applyImage);request.source1.channel = .component(1);request.options.opacity=0.5
      let expected=try ChannelArithmeticPreparation.prepare(request,target:.pixels(original.layers[0].id,[]),document:original)
      var native=original;try XCTUnwrap(expected.command).apply(to:&native)
      let parameters:[String:Any]=["source":["channel":"component","component":1],"opacity":50]
      let result=try await helper.edit(service,document,"image.applyImage",parameters);XCTAssertEqual(result,200);XCTAssertEqual(document.store.document,native)
      let before=document.store.document
      for invalid:[String:Any] in [["opacity":101],["scale":0],["source":["channel":"hue"]],["source":["channel":"gray","component":0]],["target":["kind":"alpha"]],["blending":"unknown"]] {
        let status=try await helper.edit(service,document,"image.applyImage",invalid);XCTAssertEqual(status,400);XCTAssertEqual(document.store.document,before)
      }
      let stale=try await helper.edit(service,document,"image.applyImage",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true;let busy=try await helper.edit(service,document,"image.applyImage",parameters);XCTAssertEqual(busy,409);document.store.geometryBusy=false
      let state=service.state(try XCTUnwrap(service.shares.first),document:document)
      XCTAssertNotNil(state["channelArithmetic"])
      await document.store.undo();XCTAssertEqual(document.store.document,original)
    }
  }
  @MainActor func testHTTPCrossDocumentLeaseAndAllCalculationOutputs()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      let source=CraftNSDocument(model:try self.fixture());service.controller.addDocument(source)
      defer {source.store.renderTask?.cancel();document.store.renderTask?.cancel();service.controller.removeDocument(source)}
      let unshared=try await helper.edit(service,document,"image.applyImage",["source":["documentID":UUID().uuidString]])
      XCTAssertEqual(unshared,404);try service.share(source);let sourceBefore=source.store.document
      let id=try XCTUnwrap(service.shares.first{$0.document === source}).id
      let missing=try await helper.edit(service,document,"image.applyImage",["source":["documentID":id.uuidString]])
      XCTAssertEqual(missing,409)
      let sourceSpec:[String:Any]=["documentID":id.uuidString,"revision":service.revision(source.store),"channel":"component","component":1,"invert":true]
      let applied=try await helper.edit(service,document,"image.applyImage",["source":sourceSpec]);XCTAssertEqual(applied,200);XCTAssertEqual(source.store.document,sourceBefore)
      for result in ["newChannel","selection"] {
        let before=document.store.document
        let status=try await helper.edit(service,document,"image.calculations",["source1":sourceSpec,"result":result,"name":"Channel arithmetic"])
        XCTAssertEqual(status,200);XCTAssertNotEqual(document.store.document,before)
        await document.store.undo();XCTAssertEqual(document.store.document,before)
      }
      let before=document.store.document,count=service.controller.documents.count
      let denied=try await helper.edit(service,document,"image.calculations",["result":"newDocument"]);XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let created=try await helper.edit(service,document,"image.calculations",["result":"newDocument","name":"Calculated"]);XCTAssertEqual(created,201)
      XCTAssertEqual(service.controller.documents.count,count+1);XCTAssertEqual(document.store.document,before)
      let new=try XCTUnwrap(service.shares.last?.document);XCTAssertEqual(new.store.document.colorMode,.grayscale);XCTAssertEqual(new.store.document.name,"Calculated")
      new.store.renderTask?.cancel();service.controller.removeDocument(new)
    }
  }
  @MainActor func testHTTPLayerMaskTargetRetainsEditingContextAndSchemas()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      var source=try self.fixture();source.layers[0].mask=try Surface(width:8,height:5,fill:.white)
      document.store.session=EditorSession(document:source);document.store.maskEditingLayerID=source.layers[0].id
      try service.share(document);defer{document.store.renderTask?.cancel()}
      let result=try await helper.edit(service,document,"image.applyImage",["source":["channel":"component","component":1]])
      XCTAssertEqual(result,200);XCTAssertEqual(document.store.maskEditingLayerID,source.layers[0].id)
      XCTAssertEqual(document.store.document.layers[0].content,source.layers[0].content)
      XCTAssertNotEqual(document.store.document.layers[0].mask,source.layers[0].mask)
      for name in ChannelArithmeticAPI.commands {let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name==name});XCTAssertNotNil(definition.schema["properties"])}
      XCTAssertNotNil(AutomationService.capabilities["channelArithmetic"])
    }
  }
  @MainActor func testHTTPDefaultMaskUsesGrayAndReportsReadyAvailability()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      defer{document.store.renderTask?.cancel()}
      var request=ChannelArithmeticRequest(.applyImage);request.mask = .init(channel:.gray)
      let prepared=try ChannelArithmeticPreparation.prepare(request,target:.pixels(original.layers[0].id,[]),document:original)
      var expected=original;try XCTUnwrap(prepared.command).apply(to:&expected)
      let status=try await helper.edit(service,document,"image.applyImage",["mask":[:]])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
      XCTAssertEqual(document.store.channelArithmeticState["applyImageAvailable"] as? Bool,true)
    }
  }
  @MainActor func testHTTPRevokedSourceCannotCommitAndNativeStalePreviewIsRejected()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      let source=CraftNSDocument(model:try self.fixture());service.controller.addDocument(source);try service.share(source)
      defer{source.store.renderTask?.cancel();document.store.renderTask?.cancel();service.controller.removeDocument(source)}
      let id=try XCTUnwrap(service.shares.first{$0.document === source}).id,expected=service.revision(source.store)
      let gate=ChannelArithmeticTestGate()
      service.channelArithmeticPrepare={request,target,document,sources in
        await gate.pause();return try ChannelArithmeticPreparation.prepare(request,target:target,document:document,sources:sources)
      }
      let task=Task {try await helper.edit(service,document,"image.applyImage",["source":["documentID":id.uuidString,"revision":expected]])}
      for _ in 0..<200 {if await gate.hasPaused(){break};try await Task.sleep(for:.milliseconds(10))}
      let paused=await gate.hasPaused();XCTAssertTrue(paused)
      XCTAssertTrue(document.store.geometryBusy);service.revoke(id);await gate.resume()
      let status=try await task.value;XCTAssertEqual(status,409);XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      document.store.beginChannelArithmetic(.applyImage);let draft=try XCTUnwrap(document.store.channelArithmeticWorkspace)
      await draft.task?.value;XCTAssertTrue(draft.ready)
      var changed=document.store.document;changed.name="Changed while previewing"
      document.store.session=EditorSession(document:changed);document.store.commitChannelArithmetic();await draft.commitTask?.value
      XCTAssertNotNil(draft.error);XCTAssertEqual(document.store.document,changed);document.store.cancelChannelArithmetic()
    }
  }

}

private actor ChannelArithmeticTestGate {
  var continuation:CheckedContinuation<Void,Never>?
  var released=false
  func pause()async {if released{return};await withCheckedContinuation{continuation=$0}}
  func hasPaused()->Bool {continuation != nil}
  func resume(){released=true;continuation?.resume();continuation=nil}
}
