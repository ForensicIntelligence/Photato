import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class ContentAwareApplyWorkflowTests: XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:48,height:32,depth:depth)
    var s=try Surface(width:48,height:32,depth:depth,fill:Pixel(0.2,0.5,0.7))
    for y in 12..<18 {for x in Array(8..<14)+Array(32..<38) {s.setPixel(x:x,y:y,Pixel(1,0,0))}}
    d.layers[0].content = .raster(s);d.selection = .init(x:8,y:12,width:6,height:6);return d
  }
  @MainActor func ready(_ m:ContentAwareWorkspace)async throws {
    let deadline=Date().addingTimeInterval(20)
    repeat {await m.task?.value;if m.loading || m.rendering {await Task.yield()}}while (m.loading || m.rendering) && Date()<deadline
    await m.overlayTask?.value;XCTAssertFalse(m.loading);XCTAssertFalse(m.rendering)
    XCTAssertNil(m.error)
  }
  @MainActor func start(_ store:EditorStore,_ output:ContentAwareOutput)async throws->ContentAwareWorkspace {
    store.beginContentAwareFill();let m=try XCTUnwrap(store.contentAwareDraft);await m.task?.value;try await ready(m)
    var next=m.state;next.settings.sampling = .rectangular;next.settings.margin=4;next.settings.colorAdaptation = .none;next.output=output;m.change(next);try await ready(m);return m
  }
  @MainActor func second(_ m:ContentAwareWorkspace)async throws {
    m.tool = .selection;m.kind = .lasso;m.selectionMode = .replace
    m.begin(x:32,y:12,alternate:false);m.drag(x:38,y:12);m.drag(x:38,y:18);m.drag(x:32,y:18);m.end();try await ready(m)
    XCTAssertEqual(m.selected?.bounds,.init(x:32,y:12,width:6,height:6))
  }
  @MainActor func testTwoAppliesEveryDepthAndOutputKeepWorkspaceAndUndoEachFill()async throws {
    for depth in PixelDepth.allCases {for output in ContentAwareOutput.allCases {
      let d=try fixture(depth),store=EditorStore(document:d);defer{store.cancelContentAwareFill();store.renderTask?.cancel()}
      let m=try await start(store,output);store.applyContentAwareFill();await m.commitTask?.value;try await ready(m)
      XCTAssertTrue(store.contentAwareDraft === m);XCTAssertEqual(m.appliedFillCount,1);XCTAssertFalse(m.canApply);XCTAssertTrue(m.canCommit)
      let first=store.document;XCTAssertEqual(store.session.undoStack.count,1)
      XCTAssertLessThan(try Renderer.composite(first).pixel(x:10,y:14).r,0.5)
      XCTAssertGreaterThan(try Renderer.composite(first).pixel(x:34,y:14).r,0.9)
      if output == .duplicate {XCTAssertEqual(m.input?.layerID,first.activeLayerID)}else{XCTAssertEqual(m.input?.layerID,d.layers[0].id)}
      try await second(m);XCTAssertTrue(m.canApply)
      store.applyContentAwareFill();await m.commitTask?.value;try await ready(m)
      let final=store.document;XCTAssertEqual(m.appliedFillCount,2);XCTAssertEqual(store.session.undoStack.count,2)
      XCTAssertEqual(final.layers.count,output == .current ? 1:3)
      XCTAssertLessThan(try Renderer.composite(final).pixel(x:34,y:14).r,0.5)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(final)),final)
      store.commitContentAwareFill();XCTAssertNil(store.contentAwareDraft);XCTAssertEqual(store.document,final);XCTAssertEqual(store.session.undoStack.count,2)
      await store.undo();XCTAssertEqual(store.document,first);await store.undo();XCTAssertEqual(store.document,d)
      await store.redo();await store.redo();XCTAssertEqual(store.document,final)
    }}
  }
  @MainActor func testCancelPendingFillRetainsAppliedWorkAndNoDuplicateCommit()async throws {
    let d=try fixture(),store=EditorStore(document:d);defer{store.cancelContentAwareFill();store.renderTask?.cancel()}
    let m=try await start(store,.new);store.applyContentAwareFill();await m.commitTask?.value;try await ready(m)
    let applied=store.document;store.applyContentAwareFill();XCTAssertEqual(store.document,applied);XCTAssertEqual(store.session.undoStack.count,1)
    try await second(m);store.cancelContentAwareFill();await m.task?.value
    XCTAssertEqual(store.document,applied);XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();XCTAssertEqual(store.document,d)
  }
  @MainActor func testStaleAndCancelledApplyDoNotPublish()async throws {
    let d=try fixture(),store=EditorStore(document:d);defer{store.cancelContentAwareFill();store.renderTask?.cancel()}
    var m=try await start(store,.current);var changed=d;changed.layers[0].name="External change";store.session=EditorSession(document:changed)
    store.applyContentAwareFill();await m.commitTask?.value;XCTAssertNotNil(m.error);XCTAssertEqual(store.document,changed);XCTAssertEqual(m.appliedFillCount,0)
    store.cancelContentAwareFill();store.session=EditorSession(document:d);m=try await start(store,.current)
    store.applyContentAwareFill();store.cancelContentAwareFill();await m.commitTask?.value
    XCTAssertEqual(store.document,d);XCTAssertEqual(store.session.undoStack.count,0);XCTAssertFalse(m.ready)
  }
  @MainActor func testHTTPRepeatedFillNewSelectionMatchesNativeAndRejectsInvalidModes()async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}){service,shared in
      for depth in PixelDepth.allCases {
        let d=try fixture(depth);shared.store.session=EditorSession(document:d);try service.share(shared)
        let native=EditorStore(document:d);defer{native.cancelContentAwareFill();native.renderTask?.cancel()}
        let m=try await start(native,.current);let settings=BrushAPI.json(m.state.settings)
        var p:[String:Any]=["layerID":d.layers[0].id.uuidString,"output":"current","settings":settings]
        var response=try await h.edit(service,shared,"contentAware.fill",p);XCTAssertEqual(response,200)
        native.applyContentAwareFill();await m.commitTask?.value;try await ready(m);XCTAssertTrue(native.document == shared.store.document,"Native and API documents must match exactly")
        try await second(m);p["strokes"]=m.state.strokes.map{BrushAPI.json($0)}
        response=try await h.edit(service,shared,"contentAware.fill",p);XCTAssertEqual(response,200)
        native.applyContentAwareFill();await m.commitTask?.value;try await ready(m);XCTAssertTrue(native.document == shared.store.document,"Native and API documents must match exactly")
        let final=shared.store.document
        shared.store.beginContentAwareFill();let observed=try XCTUnwrap(shared.store.contentAwareDraft);try await ready(observed)
        let shareID=try XCTUnwrap(service.shares.first?.id)
        let (http,body)=try await h.request(service,path:"/v1/documents/\(shareID)")
        XCTAssertEqual(http.statusCode,200)
        let payload=try XCTUnwrap(JSONSerialization.jsonObject(with:body)as?[String:Any]);let state=try XCTUnwrap(payload["contentAwareFill"]as?[String:Any])
        XCTAssertEqual(state["workspaceOpen"]as?Bool,true);XCTAssertEqual(state["canApply"]as?Bool,true);XCTAssertEqual(state["appliedFillCount"]as?Int,0)
        shared.store.cancelContentAwareFill()
        for bad:[String:Any] in [["target":"sampling","selectionMode":"New","points":[[1,1]]],["target":"selection","selectionMode":"bad","points":[[1,1]]]] {
          p["strokes"]=[bad];response=try await h.edit(service,shared,"contentAware.fill",p);XCTAssertEqual(response,400);XCTAssertEqual(shared.store.document,final)
        }
        native.commitContentAwareFill();XCTAssertNil(native.contentAwareDraft);response=try await h.edit(service,shared,"history.undo");XCTAssertEqual(response,200);await native.undo();XCTAssertTrue(native.document == shared.store.document,"Native and API documents must match exactly")
      }
    }
  }
  @MainActor func testSelectionCursorModifiersCaptureAndNativeApplyMetadata()async throws {
    _=NSApplication.shared
    let store=EditorStore(document:try fixture());defer{store.cancelContentAwareFill();store.renderTask?.cancel()}
    let m=try await start(store,.current),v=ContentAwareCanvasView();v.model=m;m.tool = .selection;m.kind = .lasso
    let flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for base in SelectionMode.allCases {for bits in 0..<16 {
      let modifiers=flags.enumerated().reduce(NSEvent.ModifierFlags()){bits & (1 << $1.offset)==0 ? $0:$0.union($1.element)}
      m.selectionMode=base;v.updateCursorModifiers(modifiers)
      let expected:SelectionMode=modifiers.contains([.shift,.option]) ? .intersect:modifiers.contains(.option) ? .subtract:modifiers.contains(.shift) ? .add:base
      XCTAssertEqual(v.toolCursor,.selection("lasso",expected))
      m.begin(x:4,y:4,alternate:modifiers.contains(.option),selectionMode:m.effectiveSelectionMode(modifiers));m.selectionMode = .subtract;v.updateCursorModifiers([])
      XCTAssertEqual(m.stroke?.selectionMode,expected);XCTAssertEqual(v.toolCursor,.selection("lasso",expected));m.stroke=nil
    }}
    let state=store.contentAwareFillState;XCTAssertEqual(state["canApply"]as?Bool,true);XCTAssertEqual(state["appliedFillCount"]as?Int,0)
    XCTAssertNotNil(ContentAwareSettings.apiCapabilities["workspaceApply"]);XCTAssertNotNil(ContentAwareSettings.workspaceStateSchema["properties"])
    for name in [NSAppearance.Name.aqua,.darkAqua] {
      let view=NSHostingView(rootView:ContentAwareSheet(store:store,model:m));view.appearance=NSAppearance(named:name);view.frame = .init(x:0,y:0,width:1180,height:740);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.bounds.width,0)
    }
  }
}
