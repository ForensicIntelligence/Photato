import AppKit
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeEqualizeWorkflowTests: XCTestCase {
  func document(_ depth:PixelDepth = .u8,selected:Bool=false,maximum:Bool=true)throws->CraftDocument {
    var d=try CraftDocument(width:maximum ? 300000:11000,height:maximum ? 300000:1000,depth:depth)
    d.layers[0].content = .raster(try Surface(width:d.width,height:d.height,depth:depth,fill:Pixel(0.2,0.5,0.8,0.7)))
    if selected {d.selection = .init(x:d.width-10,y:d.height-5,width:10,height:5)}
    return d
  }
  @MainActor func testNativeMaximumEqualizeMatchesHTTPArchiveActionsAndSingleUndoAtAllDepths() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,shared in
      try service.share(shared)
      for depth in PixelDepth.allCases {
        let original=try self.document(depth),store=EditorStore(document:original,actions:ActionLibrary())
        defer {store.geometryTask?.cancel();store.renderTask?.cancel()}
        XCTAssertTrue(store.canBeginClassicTone(.equalize));XCTAssertFalse(store.canBeginClassicTone(.replaceColor))
        store.beginClassicTone(.equalize);XCTAssertNil(store.classicToneWorkspace);await store.geometryTask?.value
        XCTAssertNil(store.error);XCTAssertNotEqual(store.document,original);XCTAssertEqual(store.session.undoStack.count,1)
        let edited=store.document
        shared.store.session=EditorSession(document:original);shared.store.select(original.layers[0].id)
        let status=try await helper.edit(service,shared,"tone.apply",["kind":"equalize"]);XCTAssertEqual(status,200)
        XCTAssertEqual(shared.store.document,edited)
        let bytes=try NativeArchive.encodeChunked(edited,minimumVersion:86)
        XCTAssertLessThan(bytes.count,100000);XCTAssertEqual(try NativeArchive.decode(bytes),edited)
        let operation=ActionOperation.toneAdjustment(.active,.init(.equalize))
        var replay=original;try XCTUnwrap(operation.command(in:replay)).apply(to:&replay);XCTAssertEqual(replay,edited)
        let undone=await store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(store.document,original)
        let redone=await store.requestHistory(redo:true).value;XCTAssertTrue(redone);XCTAssertEqual(store.document,edited)
        let stale=try await helper.edit(service,shared,"tone.apply",["kind":"equalize"],revision:"stale");XCTAssertEqual(stale,409)
      }
      let caps=ClassicToneAPI.capabilities
      let limits=try XCTUnwrap(caps["maximumPixelsByKind"]as?[String:Int]);XCTAssertEqual(limits["equalize"],90_000_000_000);XCTAssertEqual(limits["shadowsHighlights"],8_388_608)
      XCTAssertEqual(AutomationCommand.definitions.count,256);XCTAssertEqual(ActionLibraryFile.maximumVersion,51)
    }
  }
  @MainActor func testSelectedLargePreviewIsBoundedAndCancelCommitSourceChangeAreAtomic() async throws {
    let original=try document(selected:true,maximum:false),store=EditorStore(document:original,actions:ActionLibrary())
    defer {store.cancelClassicTone();store.renderTask?.cancel()}
    store.beginClassicTone(.equalize)
    let workspace=try XCTUnwrap(store.classicToneWorkspace);await workspace.task?.value
    XCTAssertTrue(workspace.ready,workspace.error ?? "No preview");XCTAssertTrue(workspace.previewIsOverview)
    let image=try XCTUnwrap(workspace.image);XCTAssertLessThanOrEqual(image.width*image.height,4_194_304);XCTAssertLessThanOrEqual(max(image.width,image.height),2048)
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
    workspace.update{$0.settings.equalizeEntireImage=true};await workspace.task?.value
    let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:store.classicToneState))
    XCTAssertNoThrow(try BrushAPI.merge(value,schema:ClassicToneAPI.stateSchema))
    store.cancelClassicTone();XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginClassicTone(.equalize);let next=try XCTUnwrap(store.classicToneWorkspace);await next.task?.value
    store.commitClassicTone();await next.commitTask?.value
    XCTAssertNil(next.error);XCTAssertNil(store.classicToneWorkspace);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=original;try Command.toneAdjustment(.init(.init(.equalize),layerID:original.layers[0].id)).apply(to:&expected)
    XCTAssertEqual(store.document,expected)
    _ = await store.requestHistory(redo:false).value
    store.beginClassicTone(.equalize);let stale=try XCTUnwrap(store.classicToneWorkspace);await stale.task?.value
    var changed=original;changed.name="Changed externally";store.session=EditorSession(document:changed)
    store.commitClassicTone();await stale.commitTask?.value
    XCTAssertNotNil(stale.error);XCTAssertEqual(store.document,changed);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
