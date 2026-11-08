import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class SmartObjectRefinementWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d=try CraftDocument(width:32,height:24,depth:depth)
    var pixels=try Surface(width:24,height:18,depth:depth)
    for y in 0..<18 {for x in 0..<24 {pixels.setPixel(x:x,y:y,Pixel(Float(x)/24,Float(y)/18,0.3))}}
    d.layers[0].content = .raster(pixels);d.layers[0].x=2;d.layers[0].y=2
    var session=EditorSession(document:d);try session.execute(SmartObjectIO.convert(in:d,selected:[d.layers[0].id]));d=session.document
    d.selection = .init(x:5,y:4,width:12,height:10)
    return d
  }
  @MainActor func ready(_ m:SelectMaskWorkspace) async {
    await m.task?.value
    while m.loading || m.rendering {await m.task?.value}
  }
  @MainActor func testAvailabilityEnablesSmartRefinementButRetainsFocusAndFilterMaskBoundaries() throws {
    let store=EditorStore(document:try fixture());defer{store.cancelSelectMask();store.renderTask?.cancel()}
    XCTAssertTrue(store.canBeginSelectMask);XCTAssertFalse(store.canBeginFocusArea)
    XCTAssertEqual(store.focusAreaState["available"]as?Bool,false)
    store.beginSelectMask(focus:true);XCTAssertNil(store.selectMaskDraft)
    store.smartFilterMaskEditing=true;XCTAssertFalse(store.canBeginSelectMask)
    store.beginSelectMask();XCTAssertNil(store.selectMaskDraft)
    store.smartFilterMaskEditing=false;store.geometryBusy=true;XCTAssertFalse(store.canBeginSelectMask)
    store.geometryBusy=false;var locked=store.document;locked.layers[0].locked=true;store.session = .init(document:locked);XCTAssertTrue(store.canBeginSelectMask)
    XCTAssertNotNil(SelectionRefinement.apiCapabilities["smartObjects"])
  }
  @MainActor func testNativeFourOutputsPreviewOneUndoAndArchiveAtEveryDepth() async throws {
    for depth in PixelDepth.allCases {for output:SelectionRefinementOutput in [.selection,.layerMask,.newLayer,.newLayerWithMask] {
      let original=try fixture(depth),store=EditorStore(document:try fixture(depth));store.session = .init(document:original)
      defer{store.cancelSelectMask();store.renderTask?.cancel()}
      store.beginSelectMask();let m=try XCTUnwrap(store.selectMaskDraft);await ready(m)
      XCTAssertNil(m.error);XCTAssertNotNil(m.image);XCTAssertNotNil(m.input?.materializedLayer)
      var state=m.state;state.output=output;state.settings.feather=1;m.change(state);await ready(m)
      XCTAssertEqual(store.document,original)
      store.commitSelectMask();await m.commitTask?.value
      XCTAssertNil(m.error);XCTAssertNil(store.selectMaskDraft);XCTAssertEqual(store.session.undoStack.count,1)
      let committed=store.document
      XCTAssertEqual(committed.layers[0].smartObject,original.layers[0].smartObject)
      if output == .newLayer || output == .newLayerWithMask {XCTAssertNil(committed.layers[1].smartObject)}
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(committed)),committed)
      await store.undo();XCTAssertEqual(store.document,original)
      await store.redo();XCTAssertEqual(store.document,committed)
    }}
  }
  @MainActor func testExistingSmartMaskLocalHistoryAndCancelLeaveSourceUnchanged() async throws {
    var original=try fixture();original.layers[0].mask=try Surface(width:24,height:18,fill:.white)
    let store=EditorStore(document:original);defer{store.cancelSelectMask();store.renderTask?.cancel()}
    store.beginSelectMask(fromMask:true);let m=try XCTUnwrap(store.selectMaskDraft);await ready(m)
    XCTAssertEqual(m.state.output,.layerMask)
    let before=m.refinedMask;m.size=8;m.tool = .subtract;m.begin(x:10,y:10,alternate:false);m.end();await ready(m)
    let painted=m.refinedMask;XCTAssertNotEqual(before,painted)
    m.undo();await ready(m);XCTAssertEqual(m.refinedMask,before)
    m.redo();await ready(m);XCTAssertEqual(m.refinedMask,painted)
    store.cancelSelectMask();await m.task?.value
    XCTAssertNil(store.selectMaskDraft);XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPAndNativeUseTheSameMaskAndRasterCopyAtAllDepths() async throws {
    let h=AutomationTests()
    for depth in PixelDepth.allCases {
      try await h.withService(pressedMouseButtons:{0}) {service,file in
        for output:SelectionRefinementOutput in [.selection,.layerMask,.newLayer,.newLayerWithMask] {
          let original=try self.fixture(depth);file.store.session = .init(document:original);try service.share(file)
          let native=EditorStore(document:original);defer{native.cancelSelectMask();native.renderTask?.cancel()}
          native.beginSelectMask();let m=try XCTUnwrap(native.selectMaskDraft);await self.ready(m)
          var state=m.state;state.output=output;state.settings.feather=1;m.change(state);await self.ready(m)
          native.commitSelectMask();await m.commitTask?.value;XCTAssertNil(m.error)
          let code=try await h.edit(service,file,"selection.refine",["layerID":original.layers[0].id.uuidString,"settings":["feather":1],"output":output.rawValue])
          XCTAssertEqual(code,200);XCTAssertEqual(file.store.session.undoStack.count,1)
          XCTAssertEqual(try Renderer.composite(file.store.document),try Renderer.composite(native.document))
          XCTAssertEqual(file.store.document.layers.map(\.content),native.document.layers.map(\.content))
          XCTAssertEqual(file.store.document.layers.map(\.mask),native.document.layers.map(\.mask))
          XCTAssertEqual(file.store.document.layers[0].smartObject,original.layers[0].smartObject)
          XCTAssertEqual(file.store.document.layers.map{$0.smartObject != nil},native.document.layers.map{$0.smartObject != nil})
          let undo=try await h.edit(service,file,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(file.store.document,original)
        }
      }
    }
  }
  @MainActor func testNewDocumentHTTPRequiresPermissionAndKeepsOriginalSmartSourceAndHistory() async throws {
    let h=AutomationTests()
    for output:SelectionRefinementOutput in [.newDocument,.newDocumentWithMask] {
      try await h.withService(pressedMouseButtons:{0}) {service,file in
        let original=try self.fixture();file.store.session = .init(document:original);try service.share(file)
        let p:[String:Any]=["layerID":original.layers[0].id.uuidString,"output":output.rawValue,"settings":["feather":1]]
        let denied=try await h.edit(service,file,"selection.refine",p);XCTAssertEqual(denied,403)
        service.setDocumentTransfersEnabled(true)
        let code=try await h.edit(service,file,"selection.refine",p);XCTAssertEqual(code,201)
        let made=try XCTUnwrap(service.shares.first{$0.document !== file}?.document)
        XCTAssertEqual(file.store.document,original);XCTAssertTrue(file.store.session.undoStack.isEmpty)
        XCTAssertNil(made.store.document.layers[0].smartObject)
        XCTAssertEqual(made.store.document.layers[0].mask != nil,output == .newDocumentWithMask)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(made.store.document)),made.store.document)
        made.store.renderTask?.cancel();made.updateChangeCount(.changeCleared);made.close()
      }
    }
  }
  @MainActor func testMalformedStaleBusyAndLockedRequestsCannotModifyTheSmartSource() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,file in
      let original=try self.fixture(),id=original.layers[0].id;file.store.session = .init(document:original);try service.share(file)
      let p:[String:Any]=["layerID":id.uuidString,"output":"layerMask","settings":["feather":1]]
      let stale=try await h.edit(service,file,"selection.refine",p,revision:"stale");XCTAssertEqual(stale,409)
      file.store.beginSelectMask();let busy=try await h.edit(service,file,"selection.refine",p);XCTAssertEqual(busy,409);file.store.cancelSelectMask()
      var bad=p;bad["materialized"]=["pixels":"injected"]
      let invalid=try await h.edit(service,file,"selection.refine",bad);XCTAssertEqual(invalid,400)
      var locked=original;locked.layers[0].locked=true;file.store.session = .init(document:locked)
      let denied=try await h.edit(service,file,"selection.refine",p);XCTAssertEqual(denied,422)
      XCTAssertEqual(file.store.document,locked);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let focus=try await h.edit(service,file,"selection.focus",["layerID":id.uuidString]);XCTAssertEqual(focus,422)
      XCTAssertEqual(file.store.document,locked)
    }
  }
  @MainActor func testNativeCommitRejectsChangedOriginalRatherThanOverwritingIt() async throws {
    let store=EditorStore(document:try fixture());defer{store.cancelSelectMask();store.renderTask?.cancel()}
    store.beginSelectMask();let m=try XCTUnwrap(store.selectMaskDraft);await ready(m)
    m.update(\.feather,1);await ready(m)
    var changed=store.document;changed.name="Changed while open";store.session = .init(document:changed)
    store.commitSelectMask();await m.commitTask?.value
    XCTAssertNotNil(m.error);XCTAssertEqual(store.document,changed);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
