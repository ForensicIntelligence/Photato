import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class FooterGate:@unchecked Sendable {
  private let lock=NSCondition();private var started=false,released=false
  func wait()throws {lock.lock();started=true;lock.broadcast();while !released {if Task.isCancelled{lock.unlock();throw CancellationError()};_ = lock.wait(until:Date(timeIntervalSinceNow:0.01))};lock.unlock();try Task.checkCancellation()}
  func release(){lock.lock();released=true;lock.broadcast();lock.unlock()}
  var ready:Bool {lock.lock();defer{lock.unlock()};return started}
}
final class ChannelFooterWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,size:Int=4)throws->CraftDocument {
    var d=try CraftDocument(width:size,height:size,depth:depth)
    d.layers[0].locked=false
    var coverage=try Surface(width:size,height:size,depth:.u8,fill:.black)
    for y in 1...2 {for x in 1...2 {coverage.setPixel(x:x,y:y,.white)}}
    d.setCoverageSelection(try SelectionMask(coverage:coverage))
    return d
  }
  @MainActor private func wait(_ gate:FooterGate)async throws {for _ in 0..<1000{if gate.ready{return};try await Task.sleep(for:.milliseconds(2))};XCTFail("Footer worker did not start");throw CancellationError()}
  @MainActor func testQuickSavePreservesTargetPixelsAndSelectionWithOneUndoAtAllDepthsAndMaximumCanvas()async throws {
    for depth in PixelDepth.allCases {
      for size in [4,300_000] {
        let d=try fixture(depth,size:size),s=EditorStore(document:d);defer{s.geometryTask?.cancel();s.renderTask?.cancel()}
        let target=s.componentTarget,eyes=s.channelVisibilitySnapshot
        XCTAssertTrue(s.canQuickSaveChannel);s.saveChannelFooter();await s.geometryTask?.value
        XCTAssertNil(s.error);XCTAssertNil(s.channelDialog);XCTAssertEqual(s.document.layers,d.layers);XCTAssertEqual(s.document.selectionMask,d.selectionMask)
        XCTAssertEqual(s.componentTarget,target);XCTAssertEqual(s.channelVisibilitySnapshot,eyes)
        let channel=try XCTUnwrap(s.document.alphaChannels?.last);XCTAssertEqual(channel.name,d.suggestedChannelName)
        XCTAssertEqual(try channel.selection(),try d.coverageSelection());XCTAssertEqual(s.session.undoStack.count,1)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(s.document)),s.document)
        if size>4 {XCTAssertLessThan(channel.pixels.allocatedBytes,1_048_576)}
        await s.undo();XCTAssertEqual(s.document,d)
      }
    }
  }
  @MainActor func testSaveModifierMatrixOptionsCancelNamingAndCapacity()async throws {
    let bits:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for raw in 0..<16 {
      let d=try fixture(),s=EditorStore(document:d);defer{s.cancelChannelDialog();s.renderTask?.cancel()}
      let flags=bits.enumerated().reduce(NSEvent.ModifierFlags()){ value,pair in raw&(1<<pair.offset)==0 ? value:value.union(pair.element)}
      s.saveChannelFooter(modifiers:flags)
      if flags.contains(.option){XCTAssertEqual(s.channelDialog?.kind,.save);s.cancelChannelDialog();XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)}
      else {await s.geometryTask?.value;XCTAssertNil(s.channelDialog);XCTAssertEqual(s.document.alphaChannels?.count,1)}
    }
    var d=try fixture();let plane=try Surface(width:4,height:4,fill:.white)
    d.alphaChannels=(0..<CraftDocument.maximumAlphaChannels).map{AlphaChannel(name:"Alpha \($0+1)",pixels:plane)}
    let s=EditorStore(document:d);defer{s.cancelChannelDialog();s.renderTask?.cancel()}
    XCTAssertFalse(s.canQuickSaveChannel);s.saveChannelFooter();XCTAssertEqual(s.document,d);XCTAssertNotNil(s.error)
    s.saveChannelFooter(modifiers:.option);XCTAssertNotNil(s.channelDialog);XCTAssertTrue(try XCTUnwrap(s.channelDialog).canSaveDestination);s.cancelChannelDialog()
  }
  @MainActor func testLoadUsesSelectedAlphaComponentAndBothTemporaryMasksWithoutDialogOrTargetChanges()async throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);let first=AlphaChannel(name:"First",pixels:try Surface(width:4,height:4,depth:depth,fill:.black)),chosen=AlphaChannel(name:"Chosen",pixels:try Surface(width:4,height:4,depth:depth,fill:Pixel(128.0/255,128.0/255,128.0/255)))
      d.alphaChannels=[first,chosen];let s=EditorStore(document:d);defer{s.renderTask?.cancel()};try s.selectAlphaChannel(chosen.id)
      let eyes=s.channelVisibilitySnapshot;s.loadChannelFooter();await s.geometryTask?.value
      XCTAssertNil(s.channelDialog);XCTAssertEqual(try s.document.coverageSelection()?.byte(at:0),128);XCTAssertEqual(s.editingChannel,.alpha(chosen.id));XCTAssertEqual(s.channelVisibilitySnapshot,eyes)
      XCTAssertEqual(s.document.layers,d.layers);XCTAssertEqual(s.document.alphaChannels,d.alphaChannels);await s.undo();XCTAssertEqual(s.document,d)
    }
    let(d,id)=try MaskTargetLifecycleWorkflowTests().fixture();var masks=d
    masks.layers[masks.layers.count-1].mask=try Surface(width:8,height:8,fill:Pixel(64.0/255,64.0/255,64.0/255))
    masks.layers[masks.layers.count-1].smartFilters?.mask=try Surface(width:8,height:8,fill:Pixel(192.0/255,192.0/255,192.0/255))
    let s=EditorStore(document:masks);defer{s.renderTask?.cancel()}
    for smart in [false,true]{let target=MaskPaintTarget(layerID:id,smartFilter:smart);try s.selectTemporaryMaskChannel(target);let eyes=s.channelVisibilitySnapshot
      XCTAssertEqual(s.channelFooterLoadSource,smart ? .smartFilterMask(id):.layerMask(id));s.loadChannelFooter();await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(try s.document.coverageSelection()?.byte(at:0),smart ? 192:64);XCTAssertEqual(s.document.layers,masks.layers);XCTAssertEqual(s.selectedMaskPaintTarget,target);XCTAssertEqual(s.channelVisibilitySnapshot,eyes);await s.undo()
    }
    try s.selectEditingChannel(.red);XCTAssertEqual(s.channelFooterLoadSource,.component(0))
    try s.selectModeComponents([0,1]);XCTAssertNil(s.channelFooterLoadSource);XCTAssertFalse(s.canLoadChannelFooter)
  }
  @MainActor func testNativeAndHTTPExistingCommandsMatchSaveLoadAndNewFilterSourceSchemaState()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let d=try fixture(.f32);shared.store.session=EditorSession(document:d);try service.share(shared)
      let native=EditorStore(document:d);defer{native.renderTask?.cancel()};native.saveChannelFooter();await native.geometryTask?.value
      let saved=try await helper.edit(service,shared,"channel.edit",["action":"saveSelection"]);XCTAssertEqual(saved,200)
      var api=shared.store.document;api.alphaChannels?[0].id=try XCTUnwrap(native.document.alphaChannels?.first?.id);XCTAssertEqual(api,native.document)
      let(model,id)=try MaskTargetLifecycleWorkflowTests().fixture();shared.store.session=EditorSession(document:model)
      let expected=try SelectionChannelSource.smartFilterMask(id).selection(in:model)
      let loaded=try await helper.edit(service,shared,"channel.edit",["action":"loadSelection","source":["kind":"smartFilterMask","id":id.uuidString]])
      XCTAssertEqual(loaded,200);XCTAssertEqual(try shared.store.document.coverageSelection(),expected);XCTAssertEqual(shared.store.document.layers,model.layers)
      let stale=try await helper.edit(service,shared,"channel.edit",["action":"loadSelection","source":["kind":"smartFilterMask","id":id.uuidString]],revision:"stale");XCTAssertEqual(stale,409)
      for source:[String:Any] in [["kind":"smartFilterMask"],["kind":"smartFilterMask","id":false],["kind":"smartFilterMask","id":id.uuidString,"component":0]] {let status=try await helper.edit(service,shared,"channel.edit",["action":"loadSelection","source":source]);XCTAssertEqual(status,400)}
      let share=try XCTUnwrap(service.shares.first),state=service.state(share,document:shared),selection=try XCTUnwrap(state["selectionChannels"]as? [String:Any]);XCTAssertNotNil(selection["footer"])
      XCTAssertNotNil(ChannelAPI.capabilities["nativeFooter"]);XCTAssertTrue(SelectionChannelSourceAPI.kinds.contains("smartFilterMask"));XCTAssertEqual(AutomationCommand.definitions.count,250)
    }
  }
  @MainActor func testCancelledNativeSourceReplacementAndRevokedAPIWorkNeverCommit()async throws {
    let d=try fixture(),s=EditorStore(document:d),gate=FooterGate();defer{gate.release();s.renderTask?.cancel()}
    s.channelFooterPreparation={request,d,settings in try gate.wait();return try ChannelFooterPreparation.prepare(request,document:d,colorSettings:settings)}
    s.saveChannelFooter();try await wait(gate);let pending=s.geometryTask;s.geometryTask?.cancel();gate.release();await pending?.value
    XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertFalse(s.geometryBusy)
    let changedGate=FooterGate();defer{changedGate.release()};s.channelFooterPreparation={request,d,settings in try changedGate.wait();return try ChannelFooterPreparation.prepare(request,document:d,colorSettings:settings)}
    s.saveChannelFooter();try await wait(changedGate);let old=s.geometryTask;var changed=d;changed.name="Replacement";s.session=EditorSession(document:changed);changedGate.release();await old?.value
    XCTAssertEqual(s.document,changed);XCTAssertTrue(s.session.undoStack.isEmpty)
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      shared.store.session=EditorSession(document:d);try service.share(shared);let gate=FooterGate();defer{gate.release()}
      service.selectionChannelPrepare={c,d,o,source,settings in try gate.wait();return try SelectionChannelPreparation.prepare(c,target:d,defaults:o,source:source,colorSettings:settings)}
      let task=Task{try await helper.edit(service,shared,"channel.edit",["action":"saveSelection"])};try await self.wait(gate);service.stop();gate.release();_ = try? await task.value
      XCTAssertEqual(shared.store.document,d);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
}
