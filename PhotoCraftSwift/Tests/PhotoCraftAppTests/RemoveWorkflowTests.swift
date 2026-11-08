import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class RemoveGate: @unchecked Sendable {
  private let lock = NSCondition()
  private var started = false, released = false
  func wait() throws {
    lock.lock(); started = true; lock.broadcast()
    while !released {
      if Task.isCancelled { lock.unlock(); throw CancellationError() }
      _ = lock.wait(until:Date(timeIntervalSinceNow:0.01))
    }
    lock.unlock(); try Task.checkCancellation()
  }
  func release() { lock.lock(); released = true; lock.broadcast(); lock.unlock() }
  var ready: Bool { lock.lock(); defer { lock.unlock() }; return started }
}

final class RemoveWorkflowTests: XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:24,height:24,depth:depth)
    var surface = try Surface(width:24,height:24,depth:depth,fill:Pixel(0.25,0.25,0.25))
    for y in 10..<14 { for x in 10..<14 { surface.setPixel(x:x,y:y,Pixel(1,0,0)) } }
    d.layers[0].content = .raster(surface); d.layers[0].locked = false
    return d
  }
  @MainActor private func wait(_ gate:RemoveGate) async throws {
    for _ in 0..<1000 { if gate.ready { return }; try await Task.sleep(for:.milliseconds(2)) }
    XCTFail("Remove worker did not start"); throw CancellationError()
  }
  @MainActor func testNativeManualBatchCapturesOptionsAndCommitsOneUndo() async throws {
    _ = NSApplication.shared
    let d = try fixture(), store = EditorStore(document:d)
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    store.chooseTool(WorkspaceCatalog.tool("remove"))
    XCTAssertEqual(store.tool,.remove); XCTAssertNil(store.unavailableToolID)
    var settings = RemoveToolSettings(); settings.removeAfterEachStroke = false; settings.size = 7
    try store.updateRemoveSettings(settings)
    XCTAssertTrue(store.beginRemoveStroke(at:.init(x:12,y:12),alternate:false))
    store.finishRemoveStroke(at:.init(x:12,y:12))
    XCTAssertEqual(store.document,d); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(store.removeDraft?.strokes.count,1); XCTAssertTrue(store.hasToneDraft)
    let request = try XCTUnwrap(store.removeDraft?.request)
    let expected = try RemovePreparation.prepare(request,document:d).result
    settings.sampleAllLayers = true
    XCTAssertThrowsError(try store.updateRemoveSettings(settings))
    let host = NSHostingView(rootView:RemoveToolOptions(store:store)); host.frame = .init(x:0,y:0,width:1500,height:40)
    host.layoutSubtreeIfNeeded(); XCTAssertGreaterThan(host.fittingSize.width,500)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
      let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) {
      host.cacheDisplay(in:host.bounds,to:bitmap)
      try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path).appendingPathComponent("remove-options.png"))
    }
    store.applyRemove(); await store.geometryTask?.value; await store.removeCompletionTask?.value
    XCTAssertNil(store.error); XCTAssertNil(store.removeDraft); XCTAssertNil(store.removeApplying)
    XCTAssertEqual(store.document,expected); XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo(); XCTAssertEqual(store.document,d)
    await store.redo(); XCTAssertEqual(store.document,expected)
  }
  @MainActor func testAfterEachStrokeAndClearAndToolChangeHaveDistinctHistoryEffects() async throws {
    let d = try fixture(), store = EditorStore(document:d)
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    store.tool = .remove; var settings = RemoveToolSettings(); settings.size = 7
    try store.updateRemoveSettings(settings)
    XCTAssertTrue(store.beginRemoveStroke(at:.init(x:12,y:12),alternate:false))
    store.finishRemoveStroke(at:.init(x:12,y:12))
    await store.geometryTask?.value; await store.removeCompletionTask?.value
    XCTAssertNil(store.error); XCTAssertNotEqual(store.document,d); XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo()
    settings.removeAfterEachStroke = false; try store.updateRemoveSettings(settings)
    try store.appendRemoveStroke(.init(size:7,points:[[12,12]]))
    store.cancelRemove(); XCTAssertEqual(store.document,d); XCTAssertTrue(store.session.undoStack.isEmpty)
    try store.appendRemoveStroke(.init(size:7,points:[[12,12]]))
    store.chooseTool(WorkspaceCatalog.tool("brush"))
    XCTAssertNil(store.removeDraft); XCTAssertEqual(store.document,d)
    store.tool = .remove
    XCTAssertTrue(store.beginRemoveStroke(at:.init(x:12,y:12),alternate:false))
    store.cancelRemoveGesture(); XCTAssertNil(store.removeDraft); XCTAssertNil(store.removeStroke)
  }
  @MainActor func testNativeCancellationAndChangedSourceCannotPublishPreparedRemoval() async throws {
    let d = try fixture(), store = EditorStore(document:d)
    defer { store.cancelRemove(); store.renderTask?.cancel() }
    store.tool = .remove; var settings = RemoveToolSettings(); settings.removeAfterEachStroke = false
    try store.updateRemoveSettings(settings)
    for cancel in [true,false] {
      let gate = RemoveGate(); defer { gate.release() }
      store.removePreparation = { request,original in try gate.wait(); return try RemovePreparation.prepare(request,document:original) }
      try store.appendRemoveStroke(.init(size:7,points:[[12,12]])); store.applyRemove()
      let task = store.geometryTask; try await wait(gate)
      XCTAssertTrue(store.geometryBusy); XCTAssertFalse(store.canUseRemove)
      var expected = d
      if cancel { store.cancelRemove() }
      else { expected.name = "Replacement source"; store.session = EditorSession(document:expected) }
      gate.release(); await task?.value; await store.removeCompletionTask?.value
      XCTAssertEqual(store.document,expected); XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertFalse(store.geometryBusy); XCTAssertNil(store.removeApplying)
      store.session = EditorSession(document:d)
    }
  }
  @MainActor func testHTTPExecuteMatchesNativeAllDepthsAndExposesSchemasAndState() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      for depth in PixelDepth.allCases {
        let d = try self.fixture(depth); shared.store.session = EditorSession(document:d); try service.share(shared)
        let stroke = RemoveStroke(size:7,points:[[12,12]])
        let expected = try RemovePreparation.prepare(.init(layerID:d.layers[0].id,settings:.init(),strokes:[stroke]),document:d).result
        let status = try await helper.edit(service,shared,RemoveToolAPI.name,
          ["operation":"execute","strokes":[["size":7,"points":[[12,12]]]]])
        XCTAssertEqual(status,200); XCTAssertEqual(shared.store.document,expected)
        XCTAssertEqual(shared.store.session.undoStack.count,1)
        let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200)
        XCTAssertEqual(shared.store.document,d)
      }
      let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == RemoveToolAPI.name })
      let fields = try XCTUnwrap(definition.schema["properties"] as? [String:Any])
      let parameters = try XCTUnwrap(fields["parameters"] as? [String:Any])
      XCTAssertEqual((parameters["oneOf"] as? [[String:Any]])?.count,7)
      XCTAssertEqual(AutomationCommand.definitions.count,267)
      XCTAssertTrue(JSONSerialization.isValidJSONObject(RemoveToolAPI.capabilities))
      let share = try XCTUnwrap(service.shares.first)
      let response = try await helper.request(service,path:"/v1/documents/\(share.id)")
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any])
      let remove = try XCTUnwrap(state["removeTool"] as? [String:Any])
      XCTAssertEqual(remove["generativeAvailable"] as? Bool,false)
      XCTAssertEqual(remove["resolvedProcessing"] as? String,"traditional")
    }
  }
  @MainActor func testHTTPPendingControlsStaleInvalidBusyAndUnavailableGeneration() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try self.fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      let permission = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"configure","settings":["size":7]])
      XCTAssertEqual(permission,403)
      service.setPreferenceChangesEnabled(true)
      let config = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"configure","settings":["size":7,"removeAfterEachStroke":false]])
      XCTAssertEqual(config,200)
      let stale = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"stroke","stroke":["points":[[12,12]]]],revision:"old")
      XCTAssertEqual(stale,409)
      let marked = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"stroke","stroke":["points":[[12,12]]]])
      XCTAssertEqual(marked,200); XCTAssertEqual(shared.store.removeDraft?.strokes.count,1)
      XCTAssertEqual(shared.store.document,d); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      let blocked = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(blocked,409)
      let applied = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"apply"])
      XCTAssertEqual(applied,200); XCTAssertNil(shared.store.removeDraft)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200)
      let again = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"stroke","stroke":["points":[[12,12]]]])
      XCTAssertEqual(again,200)
      let clear = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"cancel"])
      XCTAssertEqual(clear,200); XCTAssertNil(shared.store.removeDraft); XCTAssertEqual(shared.store.document,d)
      for fields:[String:Any] in [
        ["operation":"execute","strokes":[]],
        ["operation":"execute","strokes":[["points":[[12,12]],"unknown":true]]],
        ["operation":"configure","settings":["size":0]],
        ["operation":"apply","stroke":["points":[[12,12]]]],
        ["operation":"stroke","stroke":["points":[[12]]]]
      ] {
        let result = try await helper.edit(service,shared,RemoveToolAPI.name,fields)
        XCTAssertEqual(result,400); XCTAssertEqual(shared.store.document,d)
      }
      let unavailable = try await helper.edit(service,shared,RemoveToolAPI.name,
        ["operation":"execute","settings":["mode":"generativeOn"],"strokes":[["points":[[12,12]]]]])
      XCTAssertEqual(unavailable,422); XCTAssertEqual(shared.store.document,d)
      XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      var masked = d; masked.layers[0].mask = try Surface(width:24,height:24,fill:.white)
      shared.store.session = EditorSession(document:masked); shared.store.maskEditingLayerID = d.layers[0].id
      let maskTarget = try await helper.edit(service,shared,RemoveToolAPI.name,
        ["operation":"execute","strokes":[["points":[[12,12]]]]])
      XCTAssertEqual(maskTarget,422); XCTAssertEqual(shared.store.document,masked)
      shared.store.maskEditingLayerID = nil
    }
  }
  @MainActor func testHTTPRevocationAndCancellationRetainSourceAndHistory() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try self.fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      let gate = RemoveGate(); defer { gate.release() }
      shared.store.removePreparation = { request,original in try gate.wait(); return try RemovePreparation.prepare(request,document:original) }
      let pending = Task { try await helper.edit(service,shared,RemoveToolAPI.name,
        ["operation":"execute","strokes":[["size":7,"points":[[12,12]]]]]) }
      try await self.wait(gate)
      let cancel = try await helper.edit(service,shared,RemoveToolAPI.name,["operation":"cancel"])
      XCTAssertEqual(cancel,200); gate.release(); _ = try? await pending.value
      XCTAssertEqual(shared.store.document,d); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      XCTAssertNil(shared.store.removeDraft); XCTAssertNil(shared.store.removeApplying)
      let revoked = RemoveGate(); defer { revoked.release() }
      shared.store.removePreparation = { request,original in try revoked.wait(); return try RemovePreparation.prepare(request,document:original) }
      let second = Task { try await helper.edit(service,shared,RemoveToolAPI.name,
        ["operation":"execute","strokes":[["size":7,"points":[[12,12]]]]]) }
      try await self.wait(revoked); service.stop(); revoked.release(); _ = try? await second.value
      XCTAssertEqual(shared.store.document,d); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
}
