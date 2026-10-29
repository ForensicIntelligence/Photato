import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class CropWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:16,height:12,depth:depth),s = try Surface(width:16,height:12,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<12 { for x in 0..<16 { let p = Pixel(depth == .f32 ? 2:0.3,0.4,0.7,1);if depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) } } };s.setPixel(x:7,y:5,.clear);d.layers[0].content = .raster(s);return d
  }
  @MainActor func testCropPreviewCommitUndoRedoAndCancel() async throws {
    let d = try fixture(),s = EditorStore(document:d);defer { s.cancelCrop();s.renderTask?.cancel() }
    s.chooseTool(WorkspaceCatalog.tool("crop"));var draft = try XCTUnwrap(s.cropDraft);draft.frame.scaleX = 125;draft.frame.scaleY = 125;draft.deletePixels = false;draft.fill = .background;s.updateCrop(draft);await s.cropTask?.value
    XCTAssertNil(s.cropError);XCTAssertEqual(s.cropReadyDraft,draft);XCTAssertNotNil(s.cropPreviewImage);XCTAssertEqual(s.document,d);XCTAssertTrue(s.session.undoStack.isEmpty)
    let expected = try XCTUnwrap(s.cropPrepared).result;XCTAssertTrue(s.commitCrop());await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.session.undoStack.count,1)
    await s.undo();XCTAssertEqual(s.document,d);await s.redo();XCTAssertEqual(s.document,expected)
    s.beginCrop();draft = try XCTUnwrap(s.cropDraft);draft.frame.angle = 10;s.updateCrop(draft);let task = s.cropTask;s.cancelCrop();await task?.value;XCTAssertEqual(s.document,expected);XCTAssertNil(s.cropPrepared)
  }
  @MainActor func testImageCropUsesSharedEngineAndDeletesOutsideSelection() async throws {
    var d = try fixture();d.selection = .init(x:2,y:3,width:8,height:6)
    let store = EditorStore(document:d);defer { store.renderTask?.cancel() }
    let request = CropRequest(x:2,y:3,width:8,height:6),expected = try CropPreparation.prepare(request,document:d).result
    store.cropToSelection();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected)
    guard case .raster(let pixels) = store.document.layers[0].content else { return XCTFail("Missing raster") };XCTAssertEqual(pixels.width,8);XCTAssertEqual(pixels.height,6)
    await store.undo();XCTAssertEqual(store.document,d)
  }
  @MainActor func testActualCanvasHandlesStraightenAndEscape() async throws {
    let store = EditorStore(document:try fixture());defer { store.cancelCrop();store.renderTask?.cancel() };store.chooseTool(WorkspaceCatalog.tool("crop"))
    let canvas = CraftCanvas(store:store);canvas.frame = NSRect(x:0,y:0,width:400,height:300);store.zoom = 10
    func event(_ type: NSEvent.EventType,_ point: CGPoint) throws -> NSEvent { try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)) }
    let initial = try XCTUnwrap(store.cropDraft),a = canvas.viewPoint(initial.frame.handles[4]),b = CGPoint(x:a.x+40,y:a.y+20)
    canvas.mouseDown(with:try event(.leftMouseDown,a));canvas.mouseDragged(with:try event(.leftMouseDragged,b));canvas.mouseUp(with:try event(.leftMouseUp,b))
    XCTAssertGreaterThan(try XCTUnwrap(store.cropDraft).width,initial.width);XCTAssertEqual(store.document.width,16)
    store.cropStraighten = true;let p = canvas.viewPoint(CGPoint(x:1,y:2)),q = canvas.viewPoint(CGPoint(x:11,y:4))
    canvas.mouseDown(with:try event(.leftMouseDown,p));canvas.mouseDragged(with:try event(.leftMouseDragged,q));canvas.mouseUp(with:try event(.leftMouseUp,q))
    XCTAssertEqual(store.cropDraft?.frame.angle ?? 0,atan2(2,10)*180/Double.pi,accuracy:0.001);XCTAssertFalse(store.cropStraighten)
    let key = try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53));canvas.keyDown(with:key);XCTAssertNil(store.cropDraft)
  }
  func testFillOnlyNewGapsPreservesInteriorTransparencyAndHDR() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth);var r = CropRequest(x:-2,y:-2,width:20,height:16);r.deleteCroppedPixels = false;r.fill = .contentAware
      let result = try CropPreparation.prepare(r,document:d).result;XCTAssertEqual(result.layers.count,2);XCTAssertEqual(result.layers[0].content,d.layers[0].content)
      let pixels = try Renderer.composite(result);XCTAssertEqual(pixels.pixel(x:9,y:7).a,0);XCTAssertEqual(pixels.pixel(x:0,y:0).a,1)
      if depth == .f32 { XCTAssertGreaterThan(pixels.linearPixel(x:0,y:0).r,1);XCTAssertEqual(pixels.linearPixel(x:3,y:3).r,2,accuracy:0.001) }
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result);XCTAssertFalse(try PSDCodec.writeRasterLayers(result).isEmpty)
    }
  }
  func testRotationPreviewTransparentBackgroundAndContentAwareEdges() throws {
    let d = try fixture();var r = CropRequest(x:0,y:0,width:16,height:12);r.angle = 15;r.deleteCroppedPixels = false
    let transparent = try CropPreparation.prepare(r,document:d).result;XCTAssertEqual(transparent.layers.count,1)
    r.fill = .background;r.backgroundColor = Pixel(1,0,0);let background = try CropPreparation.prepare(r,document:d).result
    XCTAssertEqual(background.layers.count,2);let a = try Renderer.composite(transparent),b = try Renderer.composite(background)
    var added = 0;for y in 0..<12 { for x in 0..<16 { if b.pixel(x:x,y:y).a > a.pixel(x:x,y:y).a { added += 1 } } };XCTAssertGreaterThan(added,0)
    r.fill = .contentAware;XCTAssertEqual(try CropPreparation.prepare(r,document:d).result.layers.count,2)
  }
  @MainActor func testAPIMatchesDesktopBusyStaleInvalidAndRevocation() async throws {
    let helper = AutomationTests();try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture();shared.store.session = EditorSession(document:d);try service.share(shared)
      let params: [String:Any] = ["x":-2,"y":-1,"width":20,"height":14,"angle":10,"deleteCroppedPixels":false,"fill":"background","backgroundColor":[0.2,0.3,0.4]]
      var r = CropRequest(x:-2,y:-1,width:20,height:14);r.angle = 10;r.deleteCroppedPixels = false;r.fill = .background;r.backgroundColor = Pixel(0.2,0.3,0.4)
      let expected = try CropPreparation.prepare(r,document:d).result
      let code = try await helper.edit(service,shared,"document.crop",params);XCTAssertEqual(code,200);XCTAssertEqual(try Renderer.composite(shared.store.document),try Renderer.composite(expected));XCTAssertEqual(shared.store.document.layers.first,expected.layers.first)
      let undo = try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
      let stale = try await helper.edit(service,shared,"document.crop",params,revision:"old");XCTAssertEqual(stale,409)
      shared.store.beginCrop();let busy = try await helper.edit(service,shared,"document.crop",params);XCTAssertEqual(busy,409);shared.store.cancelCrop()
      for (key,value) in [("width",0 as Any),("x",0.5 as Any),("angle",400 as Any),("deleteCroppedPixels",1 as Any),("fill","invalid" as Any),("backgroundColor",[1,2] as Any),("unknown",1 as Any)] { var p = params;p[key] = value;let error = try await helper.edit(service,shared,"document.crop",p);XCTAssertEqual(error,400) }
      XCTAssertEqual(shared.store.document,d)
      let pending = Task { try await helper.edit(service,shared,"document.crop",params) };let deadline = Date().addingTimeInterval(5);while !shared.store.geometryBusy && Date() < deadline { await Task.yield() };XCTAssertTrue(shared.store.geometryBusy);service.stop();_ = try? await pending.value;XCTAssertEqual(shared.store.document,d)
      XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testLifecycleAndRatioDraft() async throws {
    _ = NSApplication.shared;let controller = CraftDocumentController(workspaces:WorkspaceLibrary());let doc = CraftNSDocument(model:try fixture());controller.addDocument(doc)
    doc.store.beginCrop();var d = try XCTUnwrap(doc.store.cropDraft);d.setRatio("1 : 1",document:doc.store.document);XCTAssertEqual(d.width,d.height);XCTAssertTrue(d.frame.proportional)
    d.setRatio("Free",document:doc.store.document);XCTAssertFalse(d.frame.proportional);doc.store.updateCrop(d);let task = doc.store.cropTask;doc.close();await task?.value;XCTAssertNil(doc.store.cropDraft);XCTAssertNil(doc.store.cropPreviewImage)
  }
  func testCropEvidence() throws {
    guard let folder = ProcessInfo.processInfo.environment["PHOTATO_CROP_EVIDENCE_DIR"] else { return }
    let d = try fixture();var r = CropRequest(x:-3,y:-2,width:22,height:16);r.angle = 8;r.deleteCroppedPixels = false;r.fill = .contentAware
    let result = try CropPreparation.prepare(r,document:d).result
    try RasterIO.encoded(result,type:.png).write(to:URL(fileURLWithPath:folder).appendingPathComponent("crop-expanded-fill01.png"))
  }
}
