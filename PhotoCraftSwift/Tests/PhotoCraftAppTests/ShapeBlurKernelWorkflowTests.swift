import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ShapeBlurKernelWorkflowTests:XCTestCase {
  func preset()->ShapePreset {
    .init(name:"Owned triangle",path:.init(components:[.init(knots:[PathPoint(0,0.17),.init(0.91,0),.init(1,1)].map{PathKnot($0)},closed:true)]))
  }
  func filter()throws->RasterFilter {var f=RasterFilter(.shapeBlur);f.classicDetail?.radius=5;f.classicDetail?.kernel=try ShapeBlurKernel(name:preset().name,path:preset().path);return f}
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func testSmartNative87AndDowngradeRejectionAllDepths()throws {
    for depth in PixelDepth.allCases {
      var d=try fixture(depth,smart:true);let original=d,id=d.layers[0].id
      try Command.applyFilter(id,filter()).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,87)
      XCTAssertEqual(d.layers[0].content,original.layers[0].content);let result=try Renderer.composite(d)
      for data in [try NativeArchive.encode(d),try NativeArchive.encodeChunked(d)] {
        let loaded=try NativeArchive.decode(data);XCTAssertEqual(loaded,d);XCTAssertEqual(try Renderer.composite(loaded),result)
        var older=data;older.replaceSubrange(0..<16,with:NativeIndexedArchive.containerHeader(86))
        XCTAssertThrowsError(try NativeArchive.decode(older))
      }
      var stack=d.layers[0].smartFilters!;stack.filters[0].filter.classicDetail?.radius=8
      try Command.smartFilters(id,stack).apply(to:&d);XCTAssertNotEqual(try Renderer.composite(d),result)
      XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
    }
  }
  @MainActor func testPortableActionSnapshotSurvivesPresetRemovalAndNative52Admission()throws {
    let library=ShapeLibrary(),shape=preset();try library.add(shape)
    let source=try fixture(),f=try filter(),id=source.layers[0].id;var expected=source
    try Command.applyFilter(id,f).apply(to:&expected)
    var stack=SmartFilterStack();stack.filters=[.init(filter:f)]
    for operation in [ActionOperation.filter(.active,f),.filters(.active,stack)] {
      let action=RecordedAction(name:"Custom Shape Blur",steps:[.init(name:"Shape Blur",operation:operation)])
      let bytes=try ActionLibraryFile(actions:[action]).encoded(),loaded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(loaded.version,52)
      if !library.shapes.isEmpty {try library.remove(shape.id)}
      var replay=source
      if case .filters=operation {replay=try fixture(smart:true)}
      let command=try XCTUnwrap(loaded.actions[0].steps[0].operation.command(in:replay));try command.apply(to:&replay)
      if case .filter=operation {XCTAssertEqual(replay,expected)}else{XCTAssertEqual(replay.layers[0].smartFilters?.filters[0].filter,f)}
      var raw=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];raw["version"]=51
      XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:raw)))
    }
  }
  @MainActor func testNativeChooserSnapshotLocalUndoCancelCommitAndReedit()async throws {
    let shapes=ShapeLibrary(),shape=preset();try shapes.add(shape)
    let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary(),shapes:shapes)
    defer{store.renderTask?.cancel();store.cancelFilter()}
    store.beginFilter(.shapeBlur);let model=ClassicDetailWorkspace();store.classicDetailWorkspace=model
    await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "")
    try model.chooseShape(shape);let selected=model.filter;await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "")
    try shapes.rename(shape.id,"Changed later");try shapes.remove(shape.id);XCTAssertEqual(model.filter.classicDetail?.kernel?.name,shape.name)
    model.undo();XCTAssertNil(model.filter.classicDetail?.kernel);model.redo();XCTAssertEqual(model.filter,selected)
    model.chooseBuiltInShape(.heart);XCTAssertNil(model.filter.classicDetail?.kernel);model.undo();XCTAssertEqual(model.filter,selected)
    model.close();store.cancelFilter();XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertThrowsError(try model.chooseShape(shape))
    store.beginFilter(.shapeBlur);let second=ClassicDetailWorkspace();store.classicDetailWorkspace=second
    await second.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));try second.chooseShape(shape);await second.task?.value
    XCTAssertTrue(second.ready,second.error ?? "");store.filterDraft?.filter=second.filter;second.close();store.commitFilter();await store.geometryTask?.value
    XCTAssertNil(store.error);let committed=store.document;XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,committed)
    store.beginSmartFilter(d.layers[0].id,filterID:try XCTUnwrap(committed.layers[0].smartFilters?.filters[0].id))
    XCTAssertEqual(store.filterDraft?.filter.classicDetail?.kernel?.path,shape.path);store.cancelFilter()
  }
  @MainActor func testRealHTTPDesktopEquivalenceArchiveAdmissionInvalidBusyAndStale()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let source=try self.fixture(smart:true),id=source.layers[0].id,f=try self.filter();document.store.session=EditorSession(document:source)
      var expected=source;try Command.applyFilter(id,f).apply(to:&expected)
      let parameters:[String:Any]=["layerID":id.uuidString,"filter":f.apiState]
      let status=try await h.edit(service,document,"filter.apply",parameters);XCTAssertEqual(status,200)
      // Separately executed appends correctly allocate different opaque filter IDs.
      expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(document.store.document.layers[0].smartFilters?.filters[0].id)
      XCTAssertEqual(document.store.document,expected)
      let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
      let denied=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"86"]);XCTAssertEqual(denied.0.statusCode,422)
      let saved=try await h.request(service,path:path,headers:["X-Photato-Archive-Version":"87"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),expected)
      let stale=try await h.edit(service,document,"filter.apply",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.shapeBlur)
      let busy=try await h.edit(service,document,"filter.apply",parameters);XCTAssertEqual(busy,409);document.store.cancelFilter()
      var raw=f.apiState,settings=raw["classicDetail"] as! [String:Any],kernel=settings["kernel"] as! [String:Any]
      kernel["filename"]="forbidden";settings["kernel"]=kernel;raw["classicDetail"]=settings
      let bad=try await h.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":raw]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,expected)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,source)
      let caps=ClassicDetailSettings.apiCapabilities;XCTAssertEqual(caps["customShapeNativeVersion"] as? Int,87);XCTAssertEqual(caps["customShapeActionsVersion"] as? Int,52)
      XCTAssertEqual(AutomationCommand.definitions.count,267)
    }
  }
  @MainActor func testHostedNativeChooserAndAPIExposeSameEmbeddedGeometry()async throws {
    let shapes=ShapeLibrary(),shape=preset();try shapes.add(shape)
    let d=try fixture(),store=EditorStore(document:d,shapes:shapes),model=ClassicDetailWorkspace()
    defer{model.close();store.cancelFilter();store.renderTask?.cancel()}
    store.beginFilter(.shapeBlur);store.classicDetailWorkspace=model
    await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));try model.chooseShape(shape);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "")
    let view=NSHostingView(rootView:ClassicDetailSheet(store:store,model:model)),window=NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false;window.contentView=view;view.frame=NSRect(x:0,y:0,width:840,height:620);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
    defer{window.contentView=nil;window.close()}
    let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
    XCTAssertEqual(bitmap.pixelsWide,840);XCTAssertGreaterThan(try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).count,2000)
    let state=model.apiState["filter"] as! [String:Any]
    XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:state)),model.filter)
    XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
