import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class SelectionModifyGate:@unchecked Sendable {
  let condition=NSCondition();var released=false
  func wait(){condition.lock();while !released{condition.wait()};condition.unlock()}
  func release(){condition.lock();released=true;condition.broadcast();condition.unlock()}
}
final class SelectionModifyWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try CraftDocument(width:24,height:20,depth:depth);d.layers[0].content = .raster(try Surface(width:24,height:20,depth:depth,fill:Pixel(0.4,0.2,0.7)));d.selection = .init(x:6,y:5,width:12,height:10);return d}
  @MainActor func testNativeDialogsCancelCommitAndHistoryAllOperations()async throws {
    for kind in SelectionModification.Kind.allCases {
      let original=try fixture(),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.cancelSelectionModify();s.renderTask?.cancel()}
      s.beginSelectionModify(kind);let cancelled=try XCTUnwrap(s.selectionModifyDraft);cancelled.settings.amount=2;s.cancelSelectionModify();XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
      s.beginSelectionModify(kind);let draft=try XCTUnwrap(s.selectionModifyDraft);draft.settings.amount=2;let expected=try draft.settings.applied(to:XCTUnwrap(original.coverageSelection()));s.commitSelectionModify();await draft.task?.value
      XCTAssertNil(draft.error);XCTAssertNil(s.selectionModifyDraft);XCTAssertEqual(s.document.selectionMask,expected);XCTAssertEqual(s.document.layers,original.layers);XCTAssertEqual(s.session.undoStack.last?.label,kind.title+" Selection");_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
    }
  }
  @MainActor func testReselectRectSoftCoverageHistoryAndInvalidation()async throws {
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.cancelSelectionModify();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()};let original=s.document
    XCTAssertFalse(s.canReselect);try s.executeEditorCommand(.selection(nil));XCTAssertTrue(s.canReselect);XCTAssertNil(s.selectionRecall?.mask)
    s.reselectPixels();await s.geometryTask?.value;XCTAssertEqual(try s.document.coverageSelection(),try original.coverageSelection());XCTAssertEqual(s.session.undoStack.last?.label,"Reselect")
    _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.canReselect);_=await s.requestHistory(redo:true).value;XCTAssertFalse(s.canReselect)
    var soft=original;soft.setCoverageSelection(try SelectionMask(width:24,height:20,bytes:(0..<480).map{UInt8($0%256)}));s.session=EditorSession(document:soft);try s.executeEditorCommand(.selection(nil));let saved=try XCTUnwrap(s.selectionRecall?.mask);s.reselectPixels();await s.geometryTask?.value;XCTAssertEqual(s.document.selectionMask,saved)
    try s.executeEditorCommand(.selection(nil));try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);XCTAssertNil(s.selectionRecall)
    try s.executeEditorCommand(.selection(nil));s.session=EditorSession(document:try CraftDocument(width:25,height:20));XCTAssertNil(s.selectionRecall)
  }
  @MainActor func testAllDepthsComponentContextAndSourcePixelPreservation()async throws {
    for depth in PixelDepth.allCases {
      let original=try fixture(depth),s=EditorStore(document:original,brushes:BrushLibrary());defer{s.renderTask?.cancel();s.cancelSelectionModify()};s.componentTarget = .red
      s.beginSelectionModify(.expand);let draft=try XCTUnwrap(s.selectionModifyDraft);s.commitSelectionModify();await draft.task?.value;XCTAssertNil(draft.error);XCTAssertEqual(s.document.depth,depth);XCTAssertEqual(s.document.layers,original.layers);XCTAssertEqual(s.componentTarget,.red)
      var masked=original;masked.layers[0].mask=try Surface(width:24,height:20,fill:.white);s.session=EditorSession(document:masked);s.componentTarget = .composite;s.maskEditingLayerID=masked.layers[0].id
      s.beginSelectionModify(.contract);let targetDraft=try XCTUnwrap(s.selectionModifyDraft);s.commitSelectionModify();await targetDraft.task?.value;XCTAssertNil(targetDraft.error);XCTAssertTrue(s.editingMask);XCTAssertEqual(s.maskEditingLayerID,masked.layers[0].id);XCTAssertEqual(s.document.layers,masked.layers)
    }
  }
  @MainActor func testHTTPMatchesNativeModifyAndReselectWithSchemas()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      for kind in SelectionModification.Kind.allCases {for bounds in [false,true] {
        s.session=EditorSession(document:original);s.componentTarget = .red
        let request=SelectionModification(kind,amount:2,atCanvasBounds:bounds),status=try await h.edit(service,doc,"selection.modify",["operation":kind.rawValue,"amount":2,"atCanvasBounds":bounds]);XCTAssertEqual(status,200)
        var expected=original;try request.command(in:original).apply(to:&expected);XCTAssertTrue(s.document==expected);XCTAssertEqual(s.componentTarget,.red);XCTAssertEqual(s.session.undoStack.count,1);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
      }}
      s.componentTarget = .composite;s.session=EditorSession(document:original);let clear=try await h.edit(service,doc,"selection.clear");XCTAssertEqual(clear,200);let reselect=try await h.edit(service,doc,"selection.reselect");XCTAssertEqual(reselect,200);XCTAssertEqual(try s.document.coverageSelection(),try original.coverageSelection());XCTAssertEqual(s.session.undoStack.last?.label,"Reselect")
      var masked=original;masked.layers[0].mask=try Surface(width:24,height:20,fill:Pixel(0.5,0.5,0.5))
      s.session=EditorSession(document:masked);s.componentTarget = .composite;s.maskEditingLayerID=masked.layers[0].id
      let maskTarget=s.maskEditingLayerID,maskModify=try await h.edit(service,doc,"selection.modify",["operation":"expand","amount":2]);XCTAssertEqual(maskModify,200);XCTAssertEqual(s.maskEditingLayerID,maskTarget);XCTAssertTrue(s.editingMask);XCTAssertEqual(s.document.layers,masked.layers)
      try s.executeEditorCommand(.selection(nil));XCTAssertEqual(s.maskEditingLayerID,maskTarget)
      let maskReselect=try await h.edit(service,doc,"selection.reselect");XCTAssertEqual(maskReselect,200);XCTAssertEqual(s.maskEditingLayerID,maskTarget);XCTAssertTrue(s.editingMask);XCTAssertEqual(s.document.layers,masked.layers)
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.selectionModifyState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:SelectionModifyAPI.stateSchema))
    }
  }
  @MainActor func testInvalidBusyStaleRevocationAndSelectionOnlyAdmission()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try self.fixture(),s=doc.store;s.session=EditorSession(document:original);try service.share(doc)
      for params:[String:Any] in [["operation":"bad","amount":1],["operation":"smooth","amount":101],["operation":"expand","amount":1.5],["operation":"border","amount":201],["operation":"expand","amount":1,"atCanvasBounds":1]] {let status=try await h.edit(service,doc,"selection.modify",params);XCTAssertEqual(status,400);XCTAssertTrue(s.document==original)}
      let params:[String:Any]=["operation":"expand","amount":2],stale=try await h.edit(service,doc,"selection.modify",params,revision:"old");XCTAssertEqual(stale,409)
      s.beginSelectionModify(.expand);let busy=try await h.edit(service,doc,"selection.modify",params);XCTAssertEqual(busy,409);s.cancelSelectionModify()
      let id=try XCTUnwrap(service.shares.first?.id),revision=service.revision(s),layer=original.layers[0].id
      do {try await service.executePreparedOperation(document:doc,shareID:id,revision:revision,allowSelection:true){_ in .opacity(layer,0.3)};XCTFail("Nonselection edit admitted")}catch{XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)}
      let gate=SelectionModifyGate();s.selectionModificationPreparation={source,request in gate.wait();try Task.checkCancellation();return try request.command(in:source)}
      let task=Task {try await h.edit(service,doc,"selection.modify",params)};let end=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<end{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.revoke(id);gate.release();let cancelled=try await task.value;XCTAssertEqual(cancelled,409);XCTAssertTrue(s.document==original)
    }
  }
  @MainActor func testFactoryBindingsStaleAndReadCloseCancellation()async throws {
    let menus=PhotoshopMenuTests();try menus.withMenus{_,menu in for action in [#selector(AppDelegate.borderSelection),#selector(AppDelegate.smoothSelection),#selector(AppDelegate.expandSelection),#selector(AppDelegate.contractSelection),#selector(AppDelegate.reselectPixels)] {let item=try XCTUnwrap(menus.allItems(menu).first{$0.action==action});if action == #selector(AppDelegate.reselectPixels){XCTAssertEqual(item.keyEquivalent,"d");XCTAssertEqual(item.keyEquivalentModifierMask,[.command,.shift])}else{XCTAssertEqual(item.keyEquivalent,"")}}}
    let doc=CraftNSDocument(model:try fixture()),s=doc.store;defer{s.cancelSelectionModify();s.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()};let original=s.document
    s.beginSelectionModify(.expand);let stale=try XCTUnwrap(s.selectionModifyDraft);try s.executeEditorCommand(.renameLayer(original.layers[0].id,"Changed"));s.commitSelectionModify();XCTAssertNotNil(stale.error);XCTAssertFalse(stale.busy);s.cancelSelectionModify()
    s.beginSelectionModify(.smooth);let reading=try XCTUnwrap(s.selectionModifyDraft);try doc.read(from:NativeArchive.encodeChunked(original),ofType:CraftNSDocument.nativeType);XCTAssertTrue(reading.closed);XCTAssertNil(s.selectionModifyDraft)
    s.beginSelectionModify(.border);let closing=try XCTUnwrap(s.selectionModifyDraft);doc.close();XCTAssertTrue(closing.closed);XCTAssertNil(s.selectionModifyDraft)
  }
}
