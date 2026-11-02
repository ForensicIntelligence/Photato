import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class DocumentDuplicateWorkflowTests: XCTestCase {
  @MainActor func testNativeCopyHasIndependentFileHistoryAndSourceIsUntouched() async throws {
    let controller=CraftDocumentController(),source=CraftNSDocument(model:try CraftDocument(width:4,height:3,name:"Original"))
    controller.addDocument(source);defer{for d in controller.documents {d.close()}}
    source.makeWindowControllers();source.showWindows()
    let original=source.store.document
    source.store.beginDocumentDuplicate();let draft=try XCTUnwrap(source.store.documentDuplicateDraft)
    XCTAssertEqual(draft.name,"Original copy");XCTAssertFalse(draft.merged);XCTAssertTrue(source.store.hasToneDraft)
    source.store.commitDocumentDuplicate(draft);await source.store.geometryTask?.value
    XCTAssertNil(draft.error);XCTAssertNil(source.store.documentDuplicateDraft)
    let created=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== source})
    let activationDeadline=Date().addingTimeInterval(3)
    while controller.documentWindows.activeDocument !== created && Date()<activationDeadline {try await Task.sleep(for:.milliseconds(20))}
    XCTAssertTrue(controller.documentWindows.activeDocument === created)
    XCTAssertNil(created.fileURL);XCTAssertNil(created.importedSourceURL);XCTAssertNil(created.smartObjectEditLink)
    XCTAssertTrue(created.isDocumentEdited);XCTAssertTrue(created.store.session.undoStack.isEmpty)
    XCTAssertEqual(source.store.document,original);XCTAssertTrue(source.store.session.undoStack.isEmpty)
    created.store.addPixelLayer();XCTAssertEqual(created.store.session.undoStack.count,1)
    _=await created.store.requestHistory(redo:false).value
    XCTAssertEqual(created.store.document.layers,original.layers);XCTAssertEqual(source.store.document,original)
  }
  @MainActor func testDeferredSheetActivationAndClosedCopyCleanup() async throws {
    for closeCopy in [false,true] {
      let controller=CraftDocumentController(),source=CraftNSDocument(model:try CraftDocument(width:2,height:1))
      let copied=CraftNSDocument(model:try DocumentDuplication.copy(source.store.document,name:"Queued"))
      controller.addDocument(source);source.makeWindowControllers();source.showWindows();controller.addDocument(copied)
      let window=try XCTUnwrap(source.windowForSheet),sheet=NSWindow(contentRect:NSRect(x:0,y:0,width:180,height:80),styleMask:[.titled],backing:.buffered,defer:false)
      defer{if window.attachedSheet === sheet {window.endSheet(sheet)};for d in controller.documents {d.close()}}
      window.beginSheet(sheet,completionHandler:{_ in})
      controller.documentWindows.presentAfterCurrentSheet(copied)
      XCTAssertTrue(controller.documentWindows.activeDocument === source)
      if closeCopy {controller.removeDocument(copied)}
      window.endSheet(sheet)
      let deadline=Date().addingTimeInterval(3)
      while window.attachedSheet != nil && Date()<deadline {try await Task.sleep(for:.milliseconds(20))}
      // Deliver the same AppKit lifecycle callback deterministically if a headless
      // host delays the notification; this is not a live Photoshop UI comparison.
      if let host=controller.documentWindows.group(for:source) {controller.documentWindows.sheetStateDidChange(in:host)}
      XCTAssertTrue(controller.documentWindows.activeDocument === (closeCopy ? source:copied))
      XCTAssertEqual(controller.documents.count,closeCopy ? 1:2)
    }
  }
  @MainActor func testCancelInvalidAndStaleDraftCannotCreateDocuments() async throws {
    let controller=CraftDocumentController(),source=CraftNSDocument(model:try CraftDocument(width:2,height:1))
    controller.addDocument(source);defer{for d in controller.documents {d.close()}}
    source.store.beginDocumentDuplicate();var draft=try XCTUnwrap(source.store.documentDuplicateDraft)
    draft.name=" ";source.store.commitDocumentDuplicate(draft);XCTAssertNil(source.store.geometryTask)
    source.store.cancelDocumentDuplicate();draft.name="Cancelled";source.store.commitDocumentDuplicate(draft)
    XCTAssertEqual(controller.documents.count,1)
    source.store.beginDocumentDuplicate();draft=try XCTUnwrap(source.store.documentDuplicateDraft)
    var changed=source.store.document;changed.name="Changed";source.store.session=EditorSession(document:changed)
    source.store.commitDocumentDuplicate(draft);XCTAssertNotNil(draft.error);XCTAssertEqual(controller.documents.count,1)
  }
  @MainActor func testCancellationDuringPreparationCannotPublishLateResult() async throws {
    let controller=CraftDocumentController(),source=CraftNSDocument(model:try CraftDocument(width:2,height:1))
    controller.addDocument(source);defer{for d in controller.documents {d.close()}}
    let gate=DuplicateDocumentGate();defer{gate.release()}
    source.store.documentDuplicatePreparation={d,n,m in gate.wait();try Task.checkCancellation();return try DocumentDuplicatePreparation.copy(d,name:n,merged:m)}
    source.store.beginDocumentDuplicate();let draft=try XCTUnwrap(source.store.documentDuplicateDraft)
    source.store.commitDocumentDuplicate(draft);let task=source.store.geometryTask
    source.store.cancelActiveOperation();gate.release();await task?.value
    XCTAssertEqual(controller.documents.count,1);XCTAssertFalse(source.store.geometryBusy);XCTAssertNil(source.store.documentDuplicateDraft)
  }
  @MainActor func testHTTPPermissionRevisionBusyAndIndependentCopy() async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
      try service.share(source)
      let original=source.store.document,controller=try XCTUnwrap(source.ownerController)
      defer{for d in controller.documents where d !== source {d.close()}}
      let denied=try await h.edit(service,source,"document.duplicate");XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let stale=try await h.edit(service,source,"document.duplicate",revision:"stale");XCTAssertEqual(stale,409)
      let invalid=try await h.edit(service,source,"document.duplicate",["merged":"yes"]);XCTAssertEqual(invalid,400)
      source.store.geometryBusy=true;let busy=try await h.edit(service,source,"document.duplicate");source.store.geometryBusy=false;XCTAssertEqual(busy,409)
      let copied=try await h.edit(service,source,"document.duplicate",["name":"API duplicate"]);XCTAssertEqual(copied,201)
      let new=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== source})
      XCTAssertNotEqual(new.store.document.id,original.id);XCTAssertEqual(new.store.document.layers,original.layers)
      XCTAssertEqual(new.store.document.name,"API duplicate");XCTAssertEqual(service.shares.count,2)
      XCTAssertEqual(source.store.document,original);XCTAssertTrue(source.store.session.undoStack.isEmpty)
      XCTAssertNil(new.fileURL);XCTAssertTrue(new.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPRevocationAndCancellationPreventPublication() async throws {
    for revoke in [false,true] {
      let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
        try service.share(source);service.setDocumentTransfersEnabled(true);let original=source.store.document
        let gate=DuplicateDocumentGate();defer{gate.release()}
        source.store.documentDuplicatePreparation={d,n,m in gate.wait();try Task.checkCancellation();return try DocumentDuplicatePreparation.copy(d,name:n,merged:m)}
        let pending=Task{try await h.edit(service,source,"document.duplicate")};let deadline=Date().addingTimeInterval(10)
        while !source.store.geometryBusy && Date()<deadline {await Task.yield()}
        XCTAssertTrue(source.store.geometryBusy)
        if revoke {service.revoke(try XCTUnwrap(service.shares.first?.id))} else {source.store.cancelActiveOperation()}
        gate.release();let status=try await pending.value;XCTAssertEqual(status,409)
        XCTAssertEqual(source.store.document,original);XCTAssertEqual(source.ownerController?.documents.count,1)
      }
    }
  }
  @MainActor func testSchemaMenuAndNativeAPIMergedEquivalence() async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,source in
      let controller=try XCTUnwrap(source.ownerController);defer{for d in controller.documents where d !== source {d.close()}}
      var model=source.store.document;model.layers[0].content = .raster(try Surface(width:model.width,height:model.height,fill:Pixel(1,0,0,0.5)))
      source.store.session=EditorSession(document:model);try service.share(source);service.setDocumentTransfersEnabled(true)
      let expected=try DocumentDuplicatePreparation.copy(model,name:"Merged",merged:true)
      let status=try await h.edit(service,source,"document.duplicate",["name":"Merged","merged":true]);XCTAssertEqual(status,201)
      var copied=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== source}).store.document
      copied.id=expected.id;copied.layers[0].id=expected.layers[0].id;copied.activeLayerID=expected.activeLayerID
      XCTAssertEqual(copied,expected)
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:source.store.documentDuplicateState))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:DocumentDuplicateAPI.stateSchema))
      func all(_ nodes:[EditorMenuNode])->[EditorMenuNode]{nodes.flatMap{[$0]+all($0.children ?? [])}}
      let menu=try XCTUnwrap(all(PhotoshopMenuCatalog.menus).first{$0.title=="Image"}),item=try XCTUnwrap(menu.children?.first{$0.title=="Duplicate…"})
      XCTAssertEqual(item.key,"");XCTAssertEqual(NSStringFromSelector(#selector(AppDelegate.duplicateDocument)),"duplicateDocument:")
      XCTAssertEqual(AutomationTests.expectedCommandCount,239)
    }
  }
}
private final class DuplicateDocumentGate: @unchecked Sendable {
  private let condition=NSCondition();private var open=false
  func wait(){condition.lock();while !open {condition.wait()};condition.unlock()}
  func release(){condition.lock();open=true;condition.broadcast();condition.unlock()}
}
