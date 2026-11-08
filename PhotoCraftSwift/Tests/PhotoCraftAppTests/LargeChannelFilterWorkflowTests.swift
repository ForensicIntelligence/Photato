import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeChannelFilterWorkflowTests:XCTestCase {
  enum Target:CaseIterable {case alpha,quickMask,spot}
  func fixture(_ depth:PixelDepth = .u8,target:Target = .alpha,standalone:Bool=false)throws->(CraftDocument,ChannelPlaneTarget) {
    var d=try CraftDocument(width:300_000,height:300_000,depth:depth)
    if standalone {d.layers=[];d.activeLayerID=nil;d.channelOnly=true}
    var options=ChannelDisplayOptions();options.indicates = .selectedAreas;options.opacity=0.37
    let value=AlphaChannel(name:"Owned large channel",pixels:try Surface(width:d.width,height:d.height,depth:depth,fill:.black),options:options,spot:target == .spot ? SpotInk(color:Pixel(0.8,0.2,0.6),solidity:0.43):nil)
    if target == .quickMask {d.quickMask=value;return(d,.quickMask)}
    d.alphaChannels=[value];return(d,.alpha(value.id))
  }
  @MainActor func select(_ s:EditorStore,_ target:ChannelPlaneTarget)throws {
    switch target {case .quickMask:try s.selectQuickMaskChannel();case .alpha(let id):try s.selectAlphaChannel(id)}
  }
  func apiTarget(_ target:ChannelPlaneTarget)->String {switch target{case .quickMask:"quickMask";case .alpha(let id):id.uuidString}}
  @MainActor func prepare(_ d:CraftDocument,target:ChannelPlaneTarget)throws->EditorStore {
    let s=EditorStore(document:d);s.updateViewport(size:CGSize(width:240,height:160),backingScale:1);try select(s,target);return s
  }
  @MainActor func stop(_ s:EditorStore){s.renderTask?.cancel();s.geometryTask?.cancel()}
  @MainActor func testMaximumNativePreviewCancelCommitUndoArchiveAndRecallAtEveryDepthTarget() async throws {
    for depth in PixelDepth.allCases {for target in Target.allCases {
      let(original,plane)=try fixture(depth,target:target),s=try prepare(original,target:plane);defer{stop(s)}
      XCTAssertTrue(s.canBeginFilter);for kind in AuxiliaryChannelFiltering.kinds{XCTAssertTrue(s.canBeginFilterKind(kind))}
      XCTAssertFalse(s.canBeginFilterKind(.cameraRaw));XCTAssertFalse(s.canBeginFilterKind(.liquify))
      s.beginFilter(.highPass);s.filterDraft?.filter.radius=1;s.render();await s.renderTask?.value
      XCTAssertNil(s.error);XCTAssertNotNil(s.image);XCTAssertEqual(s.filterDraft?.channelTarget,plane);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
      s.cancelFilter();XCTAssertEqual(s.document,original)
      s.beginFilter(.highPass);s.filterDraft?.filter.radius=1;let f=try XCTUnwrap(s.filterDraft?.filter)
      var expected=original;try Command.channel(.filter(plane,f)).apply(to:&expected)
      s.commitFilter();await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.editingChannel,plane);XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(s.filterRecall.filter,f)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(s.document)),s.document)
      await s.undo();XCTAssertEqual(s.document,original);await s.redo();XCTAssertEqual(s.document,expected)
    }}
  }
  @MainActor func testHTTPMaximumAlphaSpotAndHiddenQuickMaskMatchNativeAndKeepTarget() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      try service.share(doc)
      for depth in PixelDepth.allCases {for target in Target.allCases {
        let(original,plane)=try fixture(depth,target:target),s=doc.store;s.session=EditorSession(document:original);s.updateViewport(size:CGSize(width:240,height:160),backingScale:1);try select(s,plane)
        if target == .quickMask{try s.setQuickMaskVisibility(false)}
        let f=RasterFilter(.highPass);var expected=original;try Command.channel(.filter(plane,f)).apply(to:&expected)
        let status=try await h.edit(service,doc,"channel.edit",["action":"filter","target":apiTarget(plane),"filter":f.apiState])
        XCTAssertEqual(status,200);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.editingChannel,plane);XCTAssertEqual(s.session.undoStack.count,1)
        if target == .quickMask{XCTAssertFalse(s.isQuickMaskVisible)}
        XCTAssertEqual(try NativeArchive.encodeChunked(s.document),try NativeArchive.encodeChunked(expected))
        let undo=try await h.edit(service,doc,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(s.document,original)
      }}
    }
  }
  @MainActor func testStandaloneMaximumChannelRepeatPreviewCancelAndHistoryNeedNoImageLayer() async throws {
    let(original,plane)=try fixture(.u16,standalone:true),s=try prepare(original,target:plane);defer{stop(s)}
    s.filterRecall.remember(RasterFilter(.highPass));XCTAssertTrue(s.canRepeatFilter)
    s.repeatLastFilter(showDialog:true);XCTAssertEqual(s.filterDraft?.channelTarget,plane);await s.renderTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document,original);s.cancelFilter()
    var expected=original;try Command.channel(.filter(plane,RasterFilter(.highPass))).apply(to:&expected)
    s.repeatLastFilter();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document,expected);XCTAssertTrue(s.document.layers.isEmpty);XCTAssertNil(s.document.activeLayerID);XCTAssertEqual(s.session.undoStack.count,1)
    await s.undo();XCTAssertEqual(s.document,original)
    s.beginFilter(.highPass);s.commitFilter();s.geometryTask?.cancel();await s.geometryTask?.value
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPStaleBusyInvalidMissingAndUnsupportedFiltersAreAtomicAndCapabilitiesAreExplicit() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      let(original,plane)=try fixture(),s=doc.store;s.session=EditorSession(document:original);try select(s,plane);try service.share(doc)
      let params:[String:Any] = ["action":"filter","target":apiTarget(plane),"filter":["kind":"highPass","radius":1]]
      let stale=try await h.edit(service,doc,"channel.edit",params,revision:"stale");XCTAssertEqual(stale,409)
      s.beginFilter(.highPass);let busy=try await h.edit(service,doc,"channel.edit",params);XCTAssertEqual(busy,409);s.cancelFilter()
      for kind in [RasterFilter.Kind.cameraRaw,.liquify] {
        var p=params;p["filter"]=RasterFilter(kind).apiState
        let status=try await h.edit(service,doc,"channel.edit",p);XCTAssertEqual(status,422);XCTAssertEqual(s.document,original)
      }
      var p=params;p["target"]=UUID().uuidString
      let missing=try await h.edit(service,doc,"channel.edit",p);XCTAssertEqual(missing,422)
      p=params;p["filter"]=["kind":"highPass","radius":-1]
      let invalid=try await h.edit(service,doc,"channel.edit",p);XCTAssertEqual(invalid,422);XCTAssertEqual(s.document,original)
      XCTAssertEqual((AuxiliaryChannelFilterAPI.capabilities["kinds"]as?[String])?.count,8)
      XCTAssertEqual(AuxiliaryChannelFilterAPI.capabilities["maximumDimension"]as?Int,300_000)
      XCTAssertEqual(AuxiliaryChannelFilterAPI.capabilities["legacyBoundedAPIOnlyKinds"]as?[String],["liquify"])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ChannelAPI.capabilities))
      XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
}
