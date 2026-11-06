import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class PatternPatchGate:@unchecked Sendable {
  private let lock=NSCondition();private var started=false,released=false
  func wait()throws {lock.lock();started=true;lock.broadcast();while !released {if Task.isCancelled {lock.unlock();throw CancellationError()};_ = lock.wait(until:Date(timeIntervalSinceNow:0.01))};lock.unlock();try Task.checkCancellation()}
  func release(){lock.lock();released=true;lock.broadcast();lock.unlock()}
  var ready:Bool {lock.lock();defer{lock.unlock()};return started}
}
final class PatternPatchWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d = try CraftDocument(width:12,height:12,depth:depth)
    d.layers[0].content = .raster(try Surface(width:12,height:12,depth:depth,fill:Pixel(0.5,0.5,0.5)))
    d.layers[0].locked = false;d.selection = .init(x:3,y:3,width:1,height:1)
    var p = try Surface(width:2,height:2,fill:Pixel(0.25,0.25,0.25))
    p.setPixel(x:0,y:0,Pixel(0.75,0.75,0.75));p.setPixel(x:1,y:1,Pixel(0.75,0.75,0.75))
    d.patterns = [try RasterPattern(name:"Owned Patch Texture",surface:p,id:"owned-patch")];return d
  }
  @MainActor private func wait(_ gate:PatternPatchGate)async throws {for _ in 0..<1000 {if gate.ready{return};try await Task.sleep(for:.milliseconds(2))};XCTFail("Pattern worker did not start");throw CancellationError()}
  func testPatternDonorMatchesExistingNormalPatchAllDepthsAndDiffusionValues()throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth);let pattern=try XCTUnwrap(d.patterns?.first),id=try XCTUnwrap(d.activeLayerID)
      // Place the same periodic texture in a separate donor region. The old drag
      // path reads those document pixels; the new path reads the saved pattern.
      guard case .raster(var pixels)=d.layers[0].content else{return XCTFail("Raster missing")}
      let sampler=try PatternSampler(pattern)
      for y in 1...5 {for x in 7...11 {
        let p=sampler.sample(x:Double(x)+0.5,y:Double(y)+0.5)
        if depth == .f32 {pixels.setLinearPixel(x:x,y:y,SRGBTransfer.linear(p))}else{pixels.setPixel(x:x,y:y,p)}
      }}
      d.layers[0].content = .raster(pixels)
      for diffusion in [1,5,7] {
        var old=RegionRetouchRequest(kind:.patch);old.dx=6;old.diffusion=diffusion
        let previous=try RegionRetouchPreparation.prepare(old,document:d,layerID:id).result
        var request=old;request.dx=0
        let current=try PatternPatch.prepare(request,pattern:pattern,document:d,layerID:id).result
        XCTAssertEqual(try current.coverageSelection(),try previous.coverageSelection())
        // The legacy path materializes rectangle coverage. Preserve the original
        // compact selection representation while comparing all other document data.
        var normalized=previous;normalized.selection=d.selection;normalized.selectionMask=d.selectionMask
        XCTAssertEqual(current,normalized,"depth=\(depth) diffusion=\(diffusion)")
        XCTAssertEqual(current.selection,d.selection);XCTAssertEqual(current.selectionMask,d.selectionMask)
      }
    }
  }
  @MainActor func testNativeUsePatternControlsSharedOutputHistoryAndPersistence()async throws {
    _ = NSApplication.shared
    let d=try fixture(),store=EditorStore(document:d,patterns:PatternLibrary());defer{store.cancelRegionRetouch();store.renderTask?.cancel()}
    store.chooseTool(WorkspaceCatalog.tool("patch"));store.patchPatternID="owned-patch"
    let pattern=try XCTUnwrap(d.patterns?.first),id=try XCTUnwrap(d.activeLayerID)
    let expected=try PatternPatch.prepare(.init(kind:.patch),pattern:pattern,document:d,layerID:id).result
    XCTAssertTrue(store.canUsePatternPatch);XCTAssertEqual(store.selectedPatchPattern?.name,pattern.name)
    let host=NSHostingView(rootView:WorkspaceView(store:store).patchPatternControls.padding(12));host.frame=NSRect(x:0,y:0,width:350,height:60);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.width,120)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path).appendingPathComponent("pattern-patch-controls.png"))}
    store.usePatternPatch();await store.regionRetouchTask?.value;await store.geometryTask?.value
    XCTAssertNil(store.regionRetouchDraft);XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)),expected)
    await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,expected)
  }
  @MainActor func testHTTPPatternPatchMatchesNativeAllDepthsAndExposesStrictAlternateSchema()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      for depth in PixelDepth.allCases {
        let d=try fixture(depth);shared.store.session=EditorSession(document:d);try service.share(shared)
        let id=try XCTUnwrap(d.activeLayerID),pattern=try XCTUnwrap(d.patterns?.first)
        let expected=try PatternPatch.prepare(.init(kind:.patch),pattern:pattern,document:d,layerID:id).result
        let status=try await helper.edit(service,shared,"retouch.patch",["layerID":id.uuidString,"patternID":pattern.id]);XCTAssertEqual(status,200);XCTAssertEqual(shared.store.document,expected)
        let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
        let stale=try await helper.edit(service,shared,"retouch.patch",["layerID":id.uuidString,"patternID":pattern.id],revision:"stale");XCTAssertEqual(stale,409)
      }
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="retouch.patch"}),properties=try XCTUnwrap(definition.schema["properties"] as? [String:Any]),parameters=try XCTUnwrap(properties["parameters"] as? [String:Any])
      XCTAssertEqual((parameters["oneOf"] as? [[String:Any]])?.count,2);XCTAssertEqual(AutomationCommand.definitions.count,255)
      let capability=try XCTUnwrap(RegionRetouchAPI.capabilities["patternPatch"] as? [String:Any]);XCTAssertEqual(capability["maximumCanvasDimension"] as? Int,300_000)
      let share=try XCTUnwrap(service.shares.first);let response=try await helper.request(service,path:"/v1/documents/\(share.id)")
      let json=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as? [String:Any]);XCTAssertNotNil(json["regionRetouch"])
    }
  }
  @MainActor func testNativeCaptureCancellationSourceChangeAndAvailabilityGuards()async throws {
    let d=try fixture(),library=PatternLibrary(),store=EditorStore(document:d,patterns:library),gate=PatternPatchGate()
    defer{gate.release();store.cancelRegionRetouch();store.renderTask?.cancel()}
    store.chooseTool(WorkspaceCatalog.tool("patch"));store.patchPatternID="owned-patch"
    store.patternPatchPreparation={r,p,d,id in try gate.wait();return try PatternPatch.prepare(r,pattern:p,document:d,layerID:id)}
    store.usePatternPatch();let pending=store.regionRetouchTask;try await wait(gate)
    XCTAssertEqual(store.regionRetouchDraft?.pattern?.id,"owned-patch");XCTAssertFalse(store.canUsePatternPatch)
    store.patchPatternID=library.items.first?.id
    XCTAssertEqual(store.regionRetouchDraft?.pattern?.id,"owned-patch")
    store.cancelRegionRetouch();gate.release();await pending?.value
    XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(store.regionRetouchBusy)
    let changedGate=PatternPatchGate();defer{changedGate.release()};store.patchPatternID="owned-patch"
    store.patternPatchPreparation={r,p,d,id in try changedGate.wait();return try PatternPatch.prepare(r,pattern:p,document:d,layerID:id)}
    store.usePatternPatch();let changedPending=store.regionRetouchTask;try await wait(changedGate)
    var changed=d;changed.name="New owner";store.session=EditorSession(document:changed);changedGate.release();await changedPending?.value
    XCTAssertEqual(store.document,changed);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertNil(store.regionRetouchDraft);XCTAssertFalse(store.regionRetouchBusy)
    store.regionRetouchSettings.patchType = .contentAware;XCTAssertFalse(store.canUsePatternPatch)
    store.regionRetouchSettings.patchType = .normal;store.patchPatternID="missing";XCTAssertFalse(store.canUsePatternPatch)
    store.patchPatternID="owned-patch";var locked=changed;locked.layers[0].locked=true;store.session=EditorSession(document:locked);XCTAssertFalse(store.canUsePatternPatch)
  }
  @MainActor func testAPIInvalidMixedMissingPatternsBusyAndRevocationDoNotCommit()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      let d=try fixture();shared.store.session=EditorSession(document:d);try service.share(shared);let id=try XCTUnwrap(d.activeLayerID).uuidString
      for fields:[String:Any] in [["patternID":"missing"],["patternID":"owned-patch","dx":0],["patternID":"owned-patch","type":"normal"],["patternID":"owned-patch","sampleAllLayers":false],["dx":1],["patternID":NSNull()],["patternID":"owned-patch","diffusion":8]] {
        var p=fields;p["layerID"]=id;let status=try await helper.edit(service,shared,"retouch.patch",p)
        XCTAssertEqual(status,fields["patternID"]as? String == "missing" ? 404:400);XCTAssertEqual(shared.store.document,d);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      }
      shared.store.beginRegionRetouch(kind:.patch)
      let busy=try await helper.edit(service,shared,"retouch.patch",["layerID":id,"patternID":"owned-patch"]);XCTAssertEqual(busy,409);shared.store.cancelRegionRetouch()
      let gate=PatternPatchGate();defer{gate.release()};shared.store.patternPatchPreparation={r,p,d,id in try gate.wait();return try PatternPatch.prepare(r,pattern:p,document:d,layerID:id)}
      let pending=Task{try await helper.edit(service,shared,"retouch.patch",["layerID":id,"patternID":"owned-patch"])};try await self.wait(gate)
      service.stop();gate.release();_ = try? await pending.value
      XCTAssertEqual(shared.store.document,d);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
}
