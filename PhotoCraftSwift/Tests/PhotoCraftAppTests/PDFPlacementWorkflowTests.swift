import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PDFPlacementWorkflowTests: XCTestCase {
  func fixture(_ name: String = "owned-boxes") -> URL {
    URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/pdf/"+name+".pdf")
  }
  @MainActor func select(_ store: EditorStore,image: Int? = nil,page: Int = 1,cancel: Bool = false) {
    store.pdfPlacementPresenter = { model in Task {@MainActor in
      await model.loadTask?.value
      if cancel {model.cancel();return}
      if let image {model.changeContent(.images);await model.loadTask?.value;model.selected = [image]}
      else {model.settings.crop = .media;model.settings.antialias = false;model.selected = [page]}
      model.run()
    }}
  }
  @MainActor func testNativePlacePreviewTransformCancelAndCommitAreAtomic() async throws {
    let original = try CraftDocument(width:432,height:324),store = EditorStore(document:original)
    defer {store.renderTask?.cancel()}
    var changes = 0;store.onChange = {_ in changes += 1}
    select(store);store.placePDF(fixture());await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.transformDraft);XCTAssertEqual(store.document,original)
    XCTAssertEqual(store.layersInPanel().count,original.layers.count+1);XCTAssertEqual(store.session.undoStack.count,0)
    XCTAssertEqual(store.pdfPlacementState["stage"] as? String,"transform")
    var transform = try XCTUnwrap(store.transformDraft);transform.scaleX = 200;transform.scaleY = 200;transform.angle = 90
    store.updateTransform(transform)
    let expected = try Renderer.composite(store.previewDocument).rgbaData(depth:.u8)
    XCTAssertEqual(changes,0);XCTAssertFalse(store.clipboardTargetAvailable)
    store.cancelTransform();XCTAssertEqual(store.document,original);XCTAssertNil(store.embeddedPlacement)
    XCTAssertEqual(store.layersInPanel().count,original.layers.count);XCTAssertEqual(changes,0)
    store.placePDF(fixture());await store.geometryTask?.value
    transform.layerID = try XCTUnwrap(store.transformDraft).layerID;store.updateTransform(transform)
    store.commitTransform();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);XCTAssertEqual(changes,1)
    XCTAssertEqual(try Renderer.composite(store.document).rgbaData(depth:.u8),expected)
    XCTAssertEqual(store.activeLayer?.smartObject?.data,try Data(contentsOf:fixture()))
    XCTAssertTrue(store.canEditSmartObjectContents);XCTAssertTrue(store.canEditSmartObject)
    let placed = store.document
    await store.undo();XCTAssertEqual(store.document,original)
    await store.redo();XCTAssertEqual(store.document,placed)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(placed)),placed)
  }
  @MainActor func testChooserCancelStaleCommitAndClosePublishNothing() async throws {
    let original = try CraftDocument(width:432,height:324),doc = CraftNSDocument(model:original),store = doc.store
    defer {store.renderTask?.cancel()}
    select(store,cancel:true);store.placePDF(fixture());await store.geometryTask?.value
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertNil(store.transformDraft)
    select(store);store.placePDF(fixture());await store.geometryTask?.value
    var newer = original;newer.name = "Changed while placing";store.session = EditorSession(document:newer)
    store.commitTransform();XCTAssertNotNil(store.error);XCTAssertEqual(store.document,newer);XCTAssertNil(store.embeddedPlacement)
    store.error = nil;store.placePDF(fixture());await store.geometryTask?.value
    XCTAssertNotNil(store.embeddedPlacement);doc.close()
    XCTAssertNil(store.embeddedPlacement);XCTAssertNil(store.transformDraft);XCTAssertNil(store.pdfPlacementWorkspace)
    XCTAssertEqual(store.document,newer);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testNativeImagePlacementReplacementAndSourceRetention() async throws {
    let store = EditorStore(document:try CraftDocument(width:32,height:24));defer {store.renderTask?.cancel()}
    select(store,image:1);store.placePDF(fixture("owned-images"));await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.activeLayer?.smartObject?.pdfSource?.image,1)
    store.commitTransform();await store.geometryTask?.value
    let placed = store.document,id = try XCTUnwrap(store.activeLayer?.id)
    select(store,page:2);store.placePDF(fixture(),replacing:id);await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertNil(store.transformDraft);XCTAssertEqual(store.session.undoStack.count,2)
    XCTAssertEqual(store.activeLayer?.smartObject?.pdfSource?.page,2);XCTAssertNil(store.activeLayer?.smartObject?.pdfSource?.image)
    await store.undo();XCTAssertEqual(store.document,placed)
    XCTAssertEqual(store.activeLayer?.smartObject?.data,try Data(contentsOf:fixture("owned-images")))
  }
  @MainActor func testSingleSelectionControlsAndOffscreenPlaceWindow() async throws {
    _ = NSApplication.shared
    let model = PDFImportWorkspace(source:try PreparedPDFSource.read(fixture()),placement:true)
    model.inspect();await model.loadTask?.value
    model.select(1,extend:false,toggle:false);model.select(3,extend:true,toggle:true)
    XCTAssertEqual(model.selected,[3]);model.select(3,extend:false,toggle:true);XCTAssertEqual(model.selected,[3])
    model.select(1,extend:false,toggle:false);model.thumbnailSize = 0
    model.showThumbnail(1);await model.previewTask?.value
    let window = PDFImportWindow(model:model);defer {window.close()}
    XCTAssertEqual(window.window?.title,"Place PDF")
    if let path = ProcessInfo.processInfo.environment["PHOTATO_PDF_SMART_OUTPUT"] {
      let root = URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
      let nativeWindow = try XCTUnwrap(window.window)
      nativeWindow.appearance = NSAppearance(named:.aqua)
      let host = NSHostingView(rootView:PDFImportView(model:model).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light))
      nativeWindow.contentView = host;host.frame = NSRect(x:0,y:0,width:840,height:620)
      host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(100));host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:root.appendingPathComponent("place-pdf-controls.png"))
    }
    var result: PDFSmartObjectOptions?
    model.placementCompletion = {if case .success(let value) = $0 {result = value}}
    model.run();XCTAssertEqual(result?.page,1);XCTAssertTrue(model.finished)
  }
  @MainActor func testHTTPImageInitialTransformMatchesNativeAndRejectsBusyDraft() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,parent in
      try service.share(parent);service.setDocumentTransfersEnabled(true)
      let original = parent.store.document,store = EditorStore(document:original);defer {store.renderTask?.cancel()}
      select(store,image:1);store.placePDF(fixture("owned-images"));await store.geometryTask?.value
      var draft = try XCTUnwrap(store.transformDraft);draft.scaleX = 200;draft.scaleY = 200;draft.centerX += 2;store.updateTransform(draft)
      let matrix = draft.delta;store.commitTransform();await store.geometryTask?.value;XCTAssertNil(store.error)
      let id = try XCTUnwrap(service.shares.first?.id)
      let fields:[String:Any] = ["image":1,"transform":try JSONSerialization.jsonObject(with:JSONEncoder().encode(matrix))]
      let files = DocumentIOWorkflowTests()
      let response = try await files.request(service,path:"/v1/documents/\(id)/smart-objects/pdf",data:Data(contentsOf:fixture("owned-images")),type:"application/pdf",headers:["X-Photato-Revision":service.revision(parent.store),"X-Photato-PDF-Options":String(decoding:try JSONSerialization.data(withJSONObject:fields),as:UTF8.self)])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self))
      XCTAssertEqual(try Renderer.composite(parent.store.document).rgbaData(depth:.u8),try Renderer.composite(store.document).rgbaData(depth:.u8))
      XCTAssertEqual(parent.store.session.undoStack.count,1)
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.pdfSource?.image,1)
      for bad in ["{\"image\":1,\"page\":1}","{\"image\":1,\"crop\":\"media\"}","{\"image\":0}","{\"transform\":{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"tx\":0,\"ty\":0}}"] {XCTAssertThrowsError(try PDFSmartObjectAPI.options(bad),bad)}
      select(parent.store);parent.store.placePDF(fixture());await parent.store.geometryTask?.value
      let denied = try await AutomationTests().edit(service,parent,"history.undo")
      XCTAssertEqual(denied,409);XCTAssertEqual(parent.store.pdfPlacementState["stage"] as? String,"transform")
      parent.store.cancelTransform()
    }
  }
  @MainActor func testFailedTransformRemainsEditableAndCancelDuringCommitIsAtomic() async throws {
    let original = try CraftDocument(width:432,height:324),store = EditorStore(document:original)
    defer {store.renderTask?.cancel()}
    select(store);store.placePDF(fixture());await store.geometryTask?.value
    var draft = try XCTUnwrap(store.transformDraft);draft.scaleX = 100000;draft.scaleY = 100000
    store.updateTransform(draft);store.commitTransform();await store.geometryTask?.value
    XCTAssertNotNil(store.error);XCTAssertNotNil(store.embeddedPlacement);XCTAssertNotNil(store.transformDraft)
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertFalse(store.geometryBusy)
    draft.scaleX = 100;draft.scaleY = 100;store.updateTransform(draft);store.commitTransform()
    let pending = store.geometryTask;store.cancelActiveOperation();await pending?.value
    XCTAssertEqual(store.document,original);XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertNil(store.embeddedPlacement);XCTAssertNil(store.transformDraft);XCTAssertFalse(store.geometryBusy)
    store.placePDF(fixture());await store.geometryTask?.value;store.commitTransform();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
  }
  @MainActor func testPDFImageFramePlacementUsesOneReplacementTransaction() async throws {
    var original = try CraftDocument(width:32,height:24)
    let definition = FrameDefinition(width:16,height:12)
    try Command.frame(.create(name:"Frame",bounds:IntRect(x:4,y:3,width:16,height:12),definition:definition,children:[])).apply(to:&original)
    let frame = try XCTUnwrap(original.activeLayerID),store = EditorStore(document:original)
    defer {store.renderTask?.cancel()}
    select(store,image:1);store.placePDF(fixture("owned-images"),frame:frame);await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertNil(store.transformDraft);XCTAssertEqual(store.session.undoStack.count,1)
    let child = try XCTUnwrap(store.document.children(of:frame).first)
    XCTAssertEqual(child.smartObject?.pdfSource?.image,1);XCTAssertEqual(child.smartObject?.data,try Data(contentsOf:fixture("owned-images")))
    await store.undo();XCTAssertEqual(store.document,original)
  }

}
