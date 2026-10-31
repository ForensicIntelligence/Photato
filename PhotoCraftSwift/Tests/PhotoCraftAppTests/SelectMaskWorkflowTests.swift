import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct RefinementSubject: ForegroundDetecting {
  func mask(for image: Surface) async throws -> SelectionMask {
    try .make(.ellipse(.init(x:12,y:6,width:32,height:38)),width:image.width,height:image.height,antiAlias:true)
  }
}
final class SelectMaskWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width:64,height:48)
    var pixels = try Surface(width:64,height:48)
    for y in 0..<48 { for x in 0..<64 { pixels.setPixel(x:x,y:y,Pixel(Float(x)/64,Float(y)/48,0.3)) } }
    d.layers[0].content = .raster(pixels); d.selection = .init(x:12,y:6,width:32,height:38); return d
  }
  @MainActor func ready(_ m: SelectMaskWorkspace) async { await m.task?.value; while m.loading || m.rendering { await m.task?.value } }
  @MainActor func testDesktopPreviewBrushUndoCancelCommitAndDocumentUndo() async throws {
    let d = try fixture(), store = EditorStore(document:d)
    defer { store.cancelSelectMask(); store.renderTask?.cancel() }
    store.beginSelectMask(); let m = try XCTUnwrap(store.selectMaskDraft); await ready(m)
    XCTAssertNotNil(m.image); XCTAssertTrue(store.hasToneDraft); XCTAssertFalse(store.canBeginFilter)
    m.size = 12; m.begin(x:6,y:24,alternate:false); m.drag(x:12,y:24); m.end(); await ready(m)
    let painted = try XCTUnwrap(m.refinedMask); XCTAssertGreaterThan(painted.byte(at:24*64+6),0); XCTAssertEqual(store.document,d)
    m.undo(); await ready(m); XCTAssertEqual(m.refinedMask,try d.coverageSelection()); m.redo(); await ready(m); XCTAssertEqual(m.refinedMask,painted)
    m.update(\.feather,2); await ready(m); let expected = m.refinedMask
    store.commitSelectMask(); await m.commitTask?.value
    XCTAssertNil(m.error); XCTAssertNil(store.selectMaskDraft); XCTAssertEqual(store.document.selectionMask,expected)
    await store.undo(); XCTAssertEqual(store.document,d); await store.redo(); XCTAssertEqual(store.document.selectionMask,expected)
    let before = store.document; store.beginSelectMask(); let cancelled = try XCTUnwrap(store.selectMaskDraft); await ready(cancelled); cancelled.update(\.shiftEdge,-50); store.cancelSelectMask(); await cancelled.task?.value; XCTAssertEqual(store.document,before)
  }
  @MainActor func testSubjectLassoMaskEditingAndViews() async throws {
    let d = try fixture(), store = EditorStore(document:d); defer { store.cancelSelectMask(); store.renderTask?.cancel() }
    store.beginSelectMask(); let m = try XCTUnwrap(store.selectMaskDraft); await ready(m)
    m.detect(using:RefinementSubject()); await m.detectionTask?.value; await ready(m)
    XCTAssertNotEqual(m.refinedMask,try d.coverageSelection()); XCTAssertEqual(store.document,d)
    m.tool = .lassoAdd; m.begin(x:0,y:0,alternate:false); m.drag(x:10,y:0); m.drag(x:10,y:10); m.drag(x:0,y:10); m.end(); await ready(m)
    XCTAssertEqual(m.refinedMask?.byte(at:4*64+4),255)
    for view in SelectMaskView.allCases { m.view = view; m.refresh(); await ready(m); XCTAssertNil(m.error); XCTAssertEqual(m.image?.width,64) }
    var state = m.state; state.output = .layerMask; m.change(state); store.commitSelectMask(); await m.commitTask?.value
    XCTAssertNotNil(store.document.layers[0].mask); let mask = try XCTUnwrap(store.document.layers[0].mask)
    store.beginSelectMask(fromMask:true); let refine = try XCTUnwrap(store.selectMaskDraft); await ready(refine)
    XCTAssertEqual(refine.state.output,.layerMask); XCTAssertEqual(Float(refine.input!.mask.byte(at:4*64+4))/255,mask.pixel(x:4,y:4).r)
  }
  func testBrushProgramAllDepthsDecontaminationAndGuards() throws {
    var d = try fixture(); d.selection = nil
    let input = try SelectionRefinementInput.prepare(d,layerID:d.layers[0].id)
    let add = SelectionRefinementStroke(size:12,points:[[12,24],[36,24]])
    let mask = try input.refined(settings:.init(),strokes:[add]); XCTAssertEqual(mask.byte(at:24*64+20),255); XCTAssertEqual(mask.byte(at:0),0)
    var subtract = add; subtract.tool = .subtract
    let removed = try input.refined(settings:.init(),strokes:[add,subtract]); XCTAssertEqual(removed.byte(at:24*64+20),0)
    var p = SelectionRefinement(); p.decontaminate = true; p.feather = 2
    let edit = try input.edit(settings:p,output:.selection,strokes:[add]); XCTAssertEqual(edit.output,.newLayerWithMask)
    let previewGuide = try input.previewGuide(mask:edit.mask,settings:p)
    var correctedLayer = d.layers[0]; correctedLayer.content = .raster(try XCTUnwrap(edit.corrected)); correctedLayer.style = nil
    XCTAssertEqual(previewGuide,try Renderer.clippingCoverage(correctedLayer,in:d))
    let result = try edit.applied(to:d); XCTAssertEqual(result.layers.count,2); XCTAssertFalse(result.layers[0].visible); XCTAssertTrue(result.layers[1].visible)
    var bad = add; bad.points = [[.nan,0]]; XCTAssertThrowsError(try input.refined(settings:.init(),strokes:[bad]))
    d.layers[0].locked = true; let locked = try SelectionRefinementInput.prepare(d,layerID:d.layers[0].id)
    XCTAssertThrowsError(try locked.edit(settings:.init(),output:.layerMask).applied(to:d))
  }
  @MainActor func testHTTPMatchesDesktopAndValidatesState() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      var p = SelectionRefinement(); p.radius = 2; p.feather = 1; p.shiftEdge = -10
      let parameters: [String:Any] = ["layerID":d.layers[0].id.uuidString,"settings":["radius":2,"feather":1,"shiftEdge":-10],"output":"layerMask"]
      let expected = try SelectionRefinementInput.prepare(d,layerID:d.layers[0].id).edit(settings:p,output:.layerMask).applied(to:d)
      let status = try await helper.edit(service,shared,"selection.refine",parameters); XCTAssertEqual(status,200); XCTAssertEqual(shared.store.document,expected)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(shared.store.document,d)
      let stale = try await helper.edit(service,shared,"selection.refine",parameters,revision:"old"); XCTAssertEqual(stale,409)
      shared.store.beginSelectMask(); let busy = try await helper.edit(service,shared,"selection.refine",parameters); XCTAssertEqual(busy,409); shared.store.cancelSelectMask()
      for value: Any in [["radius":true],["unknown":0],["feather":-1]] {
        var bad = parameters; bad["settings"] = value
        let status = try await helper.edit(service,shared,"selection.refine",bad); XCTAssertEqual(status,400)
      }
      XCTAssertEqual(shared.store.document,d)
      let share = try XCTUnwrap(service.shares.first); let state = service.state(share,document:shared)
      XCTAssertNotNil(state["selectionRefinement"])
    }
  }
  @MainActor func testNewDocumentAPIRequiresPermissionAndPreservesSource() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      let parameters: [String:Any] = ["layerID":d.layers[0].id.uuidString,"output":"newDocumentWithMask","settings":["feather":2]]
      let denied = try await helper.edit(service,shared,"selection.refine",parameters); XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let status = try await helper.edit(service,shared,"selection.refine",parameters); XCTAssertEqual(status,201)
      XCTAssertEqual(shared.store.document,d); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      let created = try XCTUnwrap(service.shares.first(where:{ $0.document !== shared })?.document)
      XCTAssertNotNil(created.store.document.layers.first?.mask); XCTAssertEqual(created.store.document.width,d.width)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(created.store.document)),created.store.document)
      created.store.renderTask?.cancel(); created.updateChangeCount(.changeCleared); created.close()
    }
  }
  @MainActor func testNewDocumentRevocationDoesNotPublishOrChangeSource() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      var d = try CraftDocument(width:512,height:512); d.selection = .init(x:64,y:64,width:384,height:384)
      shared.store.session = EditorSession(document:d); try service.share(shared); service.setDocumentTransfersEnabled(true)
      let pending = Task { try await helper.edit(service,shared,"selection.refine",["layerID":d.layers[0].id.uuidString,"output":"newDocument","settings":["radius":20,"feather":8]]) }
      let deadline = Date().addingTimeInterval(5)
      while !shared.store.geometryBusy && Date() < deadline { await Task.yield() }
      XCTAssertTrue(shared.store.geometryBusy); service.setDocumentTransfersEnabled(false)
      let status = try await pending.value; XCTAssertEqual(status,409)
      XCTAssertEqual(shared.store.document,d); XCTAssertEqual(service.shares.count,1); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testOffscreenWorkspaceLayout() async throws {
    let store = EditorStore(document:try fixture()); store.beginSelectMask(); let m = try XCTUnwrap(store.selectMaskDraft); await ready(m)
    defer { store.cancelSelectMask(); store.renderTask?.cancel() }
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1040,height:740),styleMask:[.titled],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named:.darkAqua)
    defer { window.close() }
    let host = NSHostingView(rootView:SelectMaskSheet(store:store,model:m).environment(\.colorScheme,.dark)); host.frame = NSRect(x:0,y:0,width:1040,height:740); window.contentView = host
    host.layoutSubtreeIfNeeded(); try await Task.sleep(for:.milliseconds(120)); host.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(host.fittingSize.width,700)
    if let path = ProcessInfo.processInfo.environment["PHOTATO_SELECT_MASK_SNAPSHOT"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:path))
    }
  }
}
