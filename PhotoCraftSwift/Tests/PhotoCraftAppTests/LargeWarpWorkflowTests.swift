import AppKit
import XCTest
import PhotoCraftImaging
@testable import PhotoCraftCore
@testable import PhotoCraft

final class LargeWarpWorkflowTests:XCTestCase {
  func source(largeLayer:Bool=false,smart:Bool=false)throws->CraftDocument {
    let width=largeLayer ? 4097:300_000,height=largeLayer ? 2048:300_000
    var document=try CraftDocument(width:width,height:height)
    var pixels=try Surface(width:largeLayer ? width:17,height:largeLayer ? height:13)
    pixels.setPixel(x:1,y:1,Pixel(1,0.2,0.4,1))
    var layer=Layer(name:"Warp workflow",content:.raster(pixels));layer.x=largeLayer ? 0:100;layer.y=largeLayer ? 0:150
    document.layers=[layer];document.activeLayerID=layer.id
    if smart {try SmartObjectIO.convert(in:document,selected:[layer.id]).apply(to:&document)}
    return document
  }
  func warp()->WarpDefinition {var value=WarpDefinition();value.style = .arch;value.bend=20;value.interpolation = .nearest;return value}
  @MainActor func testNativeMaximumCanvasPreviewUsesBoundedImagesAndSharedHistory()async throws {
    let document=try source(smart:true),store=EditorStore(document:document)
    defer{store.cancelWarp();store.renderTask?.cancel()}
    store.beginWarp();let draft=try XCTUnwrap(store.warpDraft);draft.change(warp());await draft.task?.value
    XCTAssertTrue(draft.ready,draft.error ?? "No preview")
    XCTAssertEqual(draft.image?.width,2048);XCTAssertEqual(draft.image?.height,2048)
    XCTAssertEqual(draft.originalImage?.width,2048)
    XCTAssertEqual(store.document,document)
    let expected=try XCTUnwrap(draft.edit).result
    XCTAssertEqual(expected.layers[0].content,document.layers[0].content)
    XCTAssertEqual(expected.layers[0].smartObject,document.layers[0].smartObject)
    store.commitWarp();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    try store.session.undo();XCTAssertEqual(store.document,document)
    try store.session.redo();XCTAssertEqual(store.document,expected)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(store.document)),expected)
  }
  @MainActor func testEditThenUndoCannotCommitEarlierWarpPreview()async throws {
    let document=try WarpWorkflowTests().fixture(smart:true),store=EditorStore(document:document)
    defer{store.cancelWarp();store.renderTask?.cancel()}
    store.beginWarp();let draft=try XCTUnwrap(store.warpDraft);draft.change(warp());await draft.task?.value
    XCTAssertTrue(draft.ready,draft.error ?? "No preview")
    try store.session.execute(.renameLayer(document.layers[0].id,"Temporary"));try store.session.undo()
    XCTAssertEqual(store.document,document)
    store.commitWarp();await store.geometryTask?.value
    XCTAssertEqual(store.document,document);XCTAssertNotNil(draft.error)
    XCTAssertEqual(store.session.undoStack.count,0)
  }
  @MainActor func testCloseAndBothReadPathsRetireWarpPreview()async throws {
    // Match AppDelegate startup: install the custom controller before AppKit
    // creates its shared controller while reading or closing a document.
    _ = NSApplication.shared
    let bootstrap=CraftDocumentController(workspaces:WorkspaceLibrary())
    defer{withExtendedLifetime(bootstrap){}}
    XCTAssertTrue(NSDocumentController.shared === bootstrap)
    let model=try WarpWorkflowTests().fixture(smart:true)
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("owned.photato");try NativeArchive.write(model,to:url)
    for action in ["close","data","url"] {
      let document=CraftNSDocument(model:model),store=document.store
      defer{document.close();store.renderTask?.cancel()}
      store.beginWarp();let draft=try XCTUnwrap(store.warpDraft);draft.change(warp());let task=draft.task
      if action == "close" {document.close()}
      else if action == "data" {try document.read(from:NativeArchive.encodeChunked(model),ofType:CraftNSDocument.nativeType)}
      else {try document.read(from:url,ofType:CraftNSDocument.nativeType)}
      await task?.value
      XCTAssertNil(store.warpDraft);XCTAssertFalse(draft.ready);XCTAssertFalse(draft.rendering)
      draft.refresh();draft.change(warp());XCTAssertFalse(draft.rendering)
      XCTAssertEqual(store.document,model)
    }
  }
  @MainActor func testRealHTTPLargeSourceMatchesNativeAndRetainsUndoAndStaleGuards()async throws {
    let model=try source(largeLayer:true),settings=warp(),id=model.layers[0].id
    let expected=try WarpEdit.prepare(model,layerID:id,warp:settings).result
    let api=AutomationTests()
    try await api.withService(pressedMouseButtons:{0}) {service,document in
      let store=document.store;defer{store.renderTask?.cancel()}
      store.session=EditorSession(document:model);store.selectedLayerIDs=[id];try service.share(document)
      let revision=service.revision(store)
      let params:[String:Any]=["layerID":id.uuidString,"settings":["style":"arch","bend":20,"interpolation":Resampling.nearest.rawValue]]
      let status=try await api.edit(service,document,"layer.warp",params)
      XCTAssertEqual(status,200);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
      let stale=try await api.edit(service,document,"layer.warp",params,revision:revision)
      XCTAssertEqual(stale,409);XCTAssertEqual(store.document,expected)
      let undo=try await api.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(store.document,model)
      let caps=try await api.request(service,path:"/v1/capabilities")
      let values=try XCTUnwrap(JSONSerialization.jsonObject(with:caps.1)as?[String:Any])
      let warp=try XCTUnwrap(values["warp"]as?[String:Any])
      XCTAssertEqual(warp["maximumPixels"]as?Int,Surface.maxPixels)
      XCTAssertEqual(warp["maximumDimension"]as?Int,300_000)
      XCTAssertEqual(warp["legacyDenseMappingMaximumPixels"]as?Int,8_388_608)
      XCTAssertEqual(warp["maximumUVPatchPixels"]as?Int,131_072)
    }
  }
  @MainActor func testNativeComponentTargetsRejectWithoutChangingPixelsOrMetadata()throws {
    let model=try LargeColorProfileWorkflowTests().maximumSource(.cmyk)
    XCTAssertThrowsError(try WarpEdit.prepare(model,layerID:model.layers[0].id,warp:warp()))
    let store=EditorStore(document:model);defer{store.renderTask?.cancel()}
    XCTAssertFalse(store.canBeginWarp);store.beginWarp();XCTAssertNil(store.warpDraft)
    XCTAssertEqual(store.document,model);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
