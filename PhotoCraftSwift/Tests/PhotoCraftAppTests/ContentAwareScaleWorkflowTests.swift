import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ContentAwareScaleWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width:32,height:24),s = try Surface(width:32,height:24)
    for y in 0..<24 { for x in 0..<32 { s.setPixel(x:x,y:y,Pixel(x >= 14 && x < 18 ? 1:0.15,Float(y)/30,0.2)) } };d.layers[0].content = .raster(s);return d
  }
  @MainActor func testPreviewHandlesCommitCancelHistoryAndLatestPreview() async throws {
    let d = try fixture(),store = EditorStore(document:d);defer { store.cancelTransform();store.renderTask?.cancel() }
    store.beginContentAwareScale();var draft = try XCTUnwrap(store.transformDraft);XCTAssertTrue(draft.contentAware)
    let from = draft.handles[3];draft = draft.dragging(handle:3,from:from,to:CGPoint(x:24,y:from.y),shift:false,option:false)
    store.updateTransform(draft);await store.contentAwareScaleTask?.value
    XCTAssertNil(store.contentAwareScaleError);XCTAssertEqual(store.contentAwareScaleReadyDraft,draft);XCTAssertEqual(store.document,d);XCTAssertNotEqual(store.previewDocument,d)
    let expected = store.previewDocument;store.commitTransform();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,expected)
    store.beginContentAwareScale();draft = try XCTUnwrap(store.transformDraft);draft.scaleX = 110;store.updateTransform(draft);draft.scaleX = 70;store.updateTransform(draft);await store.contentAwareScaleTask?.value
    XCTAssertEqual(store.contentAwareScaleReadyDraft,draft);store.cancelTransform();XCTAssertNil(store.contentAwareScalePreview);XCTAssertEqual(store.document,expected)
    store.beginContentAwareScale();store.cancelTransform();await store.contentAwareScaleTask?.value;XCTAssertEqual(store.document,expected)
  }
  @MainActor func testHTTPDesktopEquivalenceInvalidBusyStaleAndRevocation() async throws {
    let helper = AutomationTests();try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture();shared.store.session = EditorSession(document:d);try service.share(shared)
      let parameters: [String:Any] = ["layerID":d.layers[0].id.uuidString,"width":24,"height":18,"amount":75,"protectSkinTones":true]
      var r = ContentAwareScaleRequest(width:24,height:18);r.amount = 75;r.protectSkinTones = true
      let expected = try ContentAwareScaleEdit.prepare(d,layerID:d.layers[0].id,request:r).applied(to:d)
      let code = try await helper.edit(service,shared,"contentAware.scale",parameters);XCTAssertEqual(code,200);XCTAssertEqual(shared.store.document,expected)
      let undo = try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
      let stale = try await helper.edit(service,shared,"contentAware.scale",parameters,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.beginContentAwareScale();let busy = try await helper.edit(service,shared,"contentAware.scale",parameters);XCTAssertEqual(busy,409);shared.store.cancelTransform()
      for (key,value) in [("width",0 as Any),("height",2.5 as Any),("amount",101 as Any),("protectSkinTones",1 as Any),("protectChannelID","invalid" as Any),("unknown",1 as Any)] {
        var p = parameters;p[key] = value;let result = try await helper.edit(service,shared,"contentAware.scale",p);XCTAssertEqual(result,400)
      };XCTAssertEqual(shared.store.document,d)
      let pending = Task { try await helper.edit(service,shared,"contentAware.scale",parameters) };let deadline = Date().addingTimeInterval(5)
      while !shared.store.geometryBusy && Date() < deadline { await Task.yield() };XCTAssertTrue(shared.store.geometryBusy);service.stop();_ = try? await pending.value;XCTAssertEqual(shared.store.document,d)
      XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testCloseCancelsPreviewAndFactoryShortcut() async throws {
    _ = NSApplication.shared;let controller = CraftDocumentController(workspaces:WorkspaceLibrary());let doc = CraftNSDocument(model:try fixture());controller.addDocument(doc)
    doc.store.beginContentAwareScale();let task = doc.store.contentAwareScaleTask;doc.close();await task?.value;XCTAssertNil(doc.store.transformDraft);XCTAssertNil(doc.store.contentAwareScalePreview)
    try PhotoshopMenuTests().withMenus { _,menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == "Edit > Content-Aware Scale" })
      XCTAssertEqual(item.action,#selector(AppDelegate.contentAwareScale));XCTAssertEqual(item.keyEquivalent,"c");XCTAssertEqual(item.keyEquivalentModifierMask,[.option,.shift,.command])
    }
  }
  func testScaleReferenceAndNoRotationNoFlips() throws {
    var d = TransformDraft(layerID:UUID(),bounds:.init(x:10,y:20,width:100,height:50));d.contentAware = true;d.proportional = false;d.referenceAnchor = .topLeft
    XCTAssertEqual(d.referencePoint,CGPoint(x:10,y:20));let same = d.dragging(handle:8,from:CGPoint(x:0,y:0),to:CGPoint(x:100,y:0),shift:false,option:false);XCTAssertEqual(same,d)
    let clamped = d.dragging(handle:3,from:d.handles[3],to:CGPoint(x:-100,y:45),shift:false,option:false);XCTAssertGreaterThan(clamped.scaleX,0);XCTAssertNoThrow(try clamped.scaleRequest())
    let r = try d.scaleRequest();XCTAssertEqual(r.width,100);XCTAssertEqual(r.x,10)
  }
  func testNativePSDOutputAndVisualEvidence() throws {
    let d = try fixture(),r = ContentAwareScaleRequest(width:24,height:24,x:0,y:0)
    let output = try ContentAwareScaleEdit.prepare(d,layerID:d.layers[0].id,request:r).applied(to:d)
    XCTAssertFalse(try PSDCodec.writeRasterLayers(output).isEmpty);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(output)),output)
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_SCALE_EVIDENCE_DIR"] {
      var sheet = try Surface(width:60,height:24,fill:.white);let before = try Renderer.composite(d),after = try Renderer.composite(output)
      for y in 0..<24 { for x in 0..<32 { sheet.setPixel(x:x,y:y,before.pixel(x:x,y:y)) };for x in 0..<24 { sheet.setPixel(x:x+36,y:y,after.pixel(x:x,y:y)) } }
      var doc = try CraftDocument(width:60,height:24);doc.layers[0].content = .raster(sheet);try RasterIO.encoded(doc,type:.png).write(to:URL(fileURLWithPath:folder).appendingPathComponent("scale-before-after01.png"))
    }
  }
}
