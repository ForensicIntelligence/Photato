import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private final class MaskFilterGate:@unchecked Sendable {
  let condition=NSCondition();private var ready=false
  func wait(){condition.lock();while !ready{condition.wait()};condition.unlock()}
  func release(){condition.lock();ready=true;condition.broadcast();condition.unlock()}
}
final class MaskFilterWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,target:MaskFilterTarget = .layerMask)throws->CraftDocument {
    var d=try CraftDocument(width:12,height:10,depth:depth)
    var pixels=try Surface(width:12,height:10,depth:depth)
    for y in 0..<10 {for x in 0..<12 {pixels.setPixel(x:x,y:y,Pixel(Float(x%3)/2,Float(y%4)/3,0.2,0.8))}}
    d.layers[0].content = .raster(pixels)
    if target == .smartFilterMask {try SmartObjectIO.convert(in:d,selected:[d.layers[0].id]).apply(to:&d)}
    var mask=try Surface(width:8,height:6,depth:depth)
    for y in 0..<6 {for x in 0..<8 {let v=Float((x+y)%5)/4;mask.setPixel(x:x,y:y,Pixel(v,v,v,x%2==0 ? 0:1))}}
    var properties=MaskProperties();properties.transform = .translation(2,1);properties.linked=false;properties.density=0.6;properties.feather=0.7
    if target == .layerMask {d.layers[0].mask=mask;d.layers[0].maskProperties=properties}
    else {var stack=SmartFilterStack();stack.mask=mask;stack.maskProperties=properties;d.layers[0].smartFilters=stack;d.layers[0].mask=try Surface(width:12,height:10,depth:depth,fill:Pixel(0.8,0.8,0.8))}
    return d
  }
  @MainActor func select(_ s:EditorStore,_ target:MaskFilterTarget) {
    if target == .layerMask {s.selectMask(s.document.layers[0].id)}else{s.selectSmartFilterMask(s.document.layers[0].id)}
  }
  @MainActor func stop(_ s:EditorStore){s.renderTask?.cancel();s.geometryTask?.cancel()}
  func filter(_ kind:RasterFilter.Kind)->RasterFilter {var f=RasterFilter(kind);if [.gaussianBlur,.boxBlur,.highPass,.unsharpMask].contains(kind){f.radius=1};if kind == .motionBlur{f.distance=3};if kind == .mosaic{f.cellSize=2};if kind == .addNoise{f.seed=42};return f}

  @MainActor func testNativeEightFiltersPreviewCancelCommitHistoryArchiveAndSourceAtAllDepths() async throws {
    for depth in PixelDepth.allCases {for target in MaskFilterTarget.allCases {for kind in MaskFiltering.kinds {
      let original=try fixture(depth,target:target),s=EditorStore(document:original);defer{stop(s)}
      select(s,target);XCTAssertEqual(s.currentMaskFilterTarget,target);XCTAssertTrue(s.canBeginFilterKind(kind));XCTAssertFalse(s.canBeginFilterKind(.cameraRaw))
      s.beginFilter(kind);s.filterDraft?.filter=filter(kind);s.render();await s.renderTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(s.filterDraft?.maskTarget,target)
      XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertFalse(s.canBeginFilterKind(kind))
      s.cancelFilter();XCTAssertEqual(s.document,original);XCTAssertNil(s.filterDraft)
      s.beginFilter(kind);s.filterDraft?.filter=filter(kind)
      let draft=try XCTUnwrap(s.filterDraft);var expected=original
      try draft.command(in:original).apply(to:&expected)
      s.commitFilter();await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.currentMaskFilterTarget,target)
      XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(s.filterRecall.filter,draft.filter)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(s.document)),s.document)
      await s.undo();XCTAssertEqual(s.document,original);await s.redo();XCTAssertEqual(s.document,expected)
    }}}
  }
  @MainActor func testHTTPExplicitTargetsMatchNativeAndPreserveTheSelectedThumbnail() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      try service.share(doc)
      for depth in PixelDepth.allCases {for target in MaskFilterTarget.allCases {for kind in MaskFiltering.kinds {
        let original=try fixture(depth,target:target),s=doc.store;s.session=EditorSession(document:original);s.select(original.layers[0].id);select(s,target)
        let captured=s.selectedMaskPaintTarget,f=filter(kind);var expected=original
        try Command.maskFilter(.init(layerID:original.layers[0].id,target:target,filter:f)).apply(to:&expected)
        let status=try await h.edit(service,doc,"filter.apply",["layerID":original.layers[0].id.uuidString,"target":target.rawValue,"filter":f.apiState])
        XCTAssertEqual(status,200);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.selectedMaskPaintTarget,captured)
        XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(s.filterRecall.filter,f)
        XCTAssertEqual(try NativeArchive.encodeChunked(s.document),try NativeArchive.encodeChunked(expected))
        let undo=try await h.edit(service,doc,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(s.document,original)
      }}}
    }
  }
  @MainActor func testHTTPDefaultRemainsPixelsAndInvalidMissingLockedStaleBusyTargetsReject() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      let original=try fixture(),s=doc.store;s.session=EditorSession(document:original);s.select(original.layers[0].id);select(s,.layerMask);try service.share(doc)
      let id=original.layers[0].id.uuidString,f=filter(.average),parameters:[String:Any] = ["layerID":id,"target":"layerMask","filter":f.apiState]
      var expected=original;try Command.applyFilter(original.layers[0].id,f).apply(to:&expected)
      let defaultStatus=try await h.edit(service,doc,"filter.apply",["layerID":id,"filter":f.apiState]);XCTAssertEqual(defaultStatus,200);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.document.layers[0].mask,original.layers[0].mask)
      await s.undo();select(s,.layerMask)
      for target:Any in ["unknown",4,NSNull()] {
        var p=parameters;p["target"]=target
        let status=try await h.edit(service,doc,"filter.apply",p);XCTAssertEqual(status,400);XCTAssertEqual(s.document,original)
      }
      var missing=parameters;missing["target"]="smartFilterMask"
      let missingStatus=try await h.edit(service,doc,"filter.apply",missing);XCTAssertEqual(missingStatus,422)
      var advanced=parameters;advanced["filter"]=RasterFilter(.cameraRaw).apiState
      let advancedStatus=try await h.edit(service,doc,"filter.apply",advanced);XCTAssertEqual(advancedStatus,422)
      let stale=try await h.edit(service,doc,"filter.apply",parameters,revision:"stale");XCTAssertEqual(stale,409)
      s.beginFilter(.boxBlur)
      let busy=try await h.edit(service,doc,"filter.apply",parameters);XCTAssertEqual(busy,409);s.cancelFilter()
      var locked=original;locked.layers[0].locked=true;s.session=EditorSession(document:locked)
      let lock=try await h.edit(service,doc,"filter.apply",parameters);XCTAssertEqual(lock,422);XCTAssertEqual(s.document,locked)
    }
  }
  @MainActor func testRepeatUsesCurrentMaskWithCancelAndHTTPHistory() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      try service.share(doc)
      for target in MaskFilterTarget.allCases {
        let original=try fixture(.u16,target:target),s=doc.store;s.session=EditorSession(document:original);s.select(original.layers[0].id);select(s,target)
        let f=filter(.boxBlur);s.filterRecall.remember(f)
        s.repeatLastFilter(showDialog:true);XCTAssertEqual(s.filterDraft?.maskTarget,target);await s.renderTask?.value;s.cancelFilter();XCTAssertEqual(s.document,original)
        var expected=original;try Command.maskFilter(.init(layerID:original.layers[0].id,target:target,filter:f)).apply(to:&expected)
        s.repeatLastFilter();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document,expected)
        await s.undo();let captured=s.selectedMaskPaintTarget
        let status=try await h.edit(service,doc,FilterRecallAPI.name);XCTAssertEqual(status,200);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.selectedMaskPaintTarget,captured)
        XCTAssertEqual(s.session.undoStack.count,1)
      }
    }
  }
  @MainActor func testCancelledAndChangedRepeatTargetCannotPublishAndDraftRejectsRetarget() async throws {
    let original=try fixture(),s=EditorStore(document:original);defer{stop(s)};select(s,.layerMask)
    s.beginFilter(.average);s.maskEditingLayerID=nil;s.commitFilter();XCTAssertNotNil(s.error);XCTAssertEqual(s.document,original);XCTAssertNotNil(s.filterDraft);s.cancelFilter();s.error=nil;select(s,.layerMask)
    s.filterRecall.remember(filter(.boxBlur))
    let gate=MaskFilterGate();defer{gate.release()}
    s.repeatFilterPreparation={source,request in gate.wait();try Task.checkCancellation();return try request.command(in:source)}
    s.repeatLastFilter();s.maskEditingLayerID=nil;gate.release();await s.geometryTask?.value
    XCTAssertNotNil(s.error);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.error=nil;select(s,.layerMask)
    let cancelGate=MaskFilterGate();defer{cancelGate.release()}
    s.repeatFilterPreparation={source,request in cancelGate.wait();try Task.checkCancellation();return try request.command(in:source)}
    s.repeatLastFilter();s.geometryTask?.cancel();cancelGate.release();await s.geometryTask?.value
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testSchemasMenusMaskCapabilitiesAndConflictingDraftsAreExplicit() throws {
    let original=try fixture(),s=EditorStore(document:original);defer{stop(s)};select(s,.layerMask)
    let draft=FilterDraft(id:original.layers[0].id,filter:filter(.boxBlur),channelTarget:.quickMask,maskTarget:.layerMask)
    XCTAssertThrowsError(try draft.command(in:original))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:MaskFilterAPI.capabilities))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiCapabilities))
    try FilterWorkflowTests().testFactoryMenuBindingsAllEight()
    XCTAssertEqual(MaskFiltering.kinds.count,8)
  }
}
