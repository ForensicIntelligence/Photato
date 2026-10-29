import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RegionRetouchWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:40,height:28,depth:depth)
    var pixels = try Surface(width:40,height:28,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<28 { for x in 0..<40 {
      let object = (4..<12).contains(x) && (8..<16).contains(y)
      let p = depth == .f32 ? (object ? Pixel(3,0.3,0.2):Pixel(2,2,2)) : (object ? Pixel(1,0.15,0.1):Pixel(0.5,0.5,0.5))
      if depth == .f32 { pixels.setLinearPixel(x:x,y:y,p) } else { pixels.setPixel(x:x,y:y,p) }
    } }
    d.layers[0].content = .raster(pixels);d.layers[0].locked = false
    d.selection = IntRect(x:4,y:8,width:8,height:8);return d
  }
  func testPatchSourceDestinationDepthStorageAndPersistence() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth),id = try XCTUnwrap(d.activeLayerID)
      var r = RegionRetouchRequest(kind:.patch);r.dx = 18
      let edit = try RegionRetouchPreparation.prepare(r,document:d,layerID:id)
      let before = try Renderer.composite(d),after = try Renderer.composite(edit.result)
      XCTAssertEqual(after.pixel(x:7,y:11).r,after.pixel(x:1,y:1).r,accuracy:0.005)
      XCTAssertEqual(after.pixel(x:1,y:1),before.pixel(x:1,y:1))
      XCTAssertEqual(edit.result.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edit.result)),edit.result)
      var session = EditorSession(document:d);try session.execute(.regionRetouch(edit));try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edit.result)
      r.patchMode = .destination
      let dest = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result
      let output = try Renderer.composite(dest)
      XCTAssertEqual(output.pixel(x:25,y:11),before.pixel(x:7,y:11))
      XCTAssertEqual(output.pixel(x:7,y:11),before.pixel(x:7,y:11))
      XCTAssertEqual(dest.selection?.x,22)
      if depth == .f32 { XCTAssertGreaterThan(output.linearPixel(x:25,y:11).r,1) }
    }
  }
  func testMoveFillsSourceExtendKeepsItAndTransformsSelection() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth),id = try XCTUnwrap(d.activeLayerID),before = try Renderer.composite(d)
      var r = RegionRetouchRequest(kind:.move);r.dx = 18
      let moved = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result,output = try Renderer.composite(moved)
      XCTAssertEqual(output.pixel(x:25,y:11),before.pixel(x:7,y:11))
      XCTAssertEqual(output.pixel(x:7,y:11).r,output.pixel(x:1,y:1).r,accuracy:0.01)
      XCTAssertEqual(output.pixel(x:1,y:1),before.pixel(x:1,y:1));XCTAssertEqual(moved.selection?.x,22)
      r.moveMode = .extend
      let extended = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result
      XCTAssertEqual(try Renderer.composite(extended).pixel(x:7,y:11),before.pixel(x:7,y:11))
      r.scaleX = 75;r.scaleY = 125;r.angle = 15;r.color = 4
      let transformed = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result
      let expected = try XCTUnwrap(d.coverageSelection()).transformed(by:r.transform(bounds:try XCTUnwrap(d.selection)),width:d.width,height:d.height)
      XCTAssertEqual(transformed.selectionMask,expected)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(transformed)),transformed)
    }
  }
  func testContentAwarePatchCoverageLocksAndAllLayers() throws {
    var d = try fixture(),r = RegionRetouchRequest(kind:.patch);r.dx = 18;r.patchType = .contentAware;r.color = 5
    let id = try XCTUnwrap(d.activeLayerID)
    var mask = try XCTUnwrap(d.coverageSelection()).bytes;mask[11*d.width+7] = 128;d.setCoverageSelection(try SelectionMask(width:d.width,height:d.height,bytes:mask))
    let result = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result
    XCTAssertNotEqual(result.layers[0].content,d.layers[0].content)
    let output = try Renderer.composite(result);XCTAssertGreaterThan(output.pixel(x:7,y:11).r,output.pixel(x:6,y:11).r)
    var top = Layer(name:"Guide",content:.raster(try Surface(width:40,height:28,fill:Pixel(0.2,0.4,0.6))));top.visible = true;d.layers.append(top)
    r.sampleAllLayers = true
    let sampled = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result
    XCTAssertNotEqual(sampled.layers[0].content,result.layers[0].content);XCTAssertEqual(sampled.layers[1],d.layers[1])
    d.layers[0].locked = true
    XCTAssertThrowsError(try RegionRetouchPreparation.prepare(r,document:d,layerID:id))
  }
  func testRedEyePreservesHighlightsAlphaAndOutsideSelection() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth),r = RegionRetouchRequest(kind:.redEye);r.region = .init(x:2,y:6,width:12,height:12);r.pupilSize = 100
      guard case .raster(var pixels) = d.layers[0].content else { return XCTFail("Raster missing") }
      pixels.setPixel(x:8,y:11,.white);d.layers[0].content = .raster(pixels)
      let edit = try RegionRetouchPreparation.prepare(r,document:d,layerID:try XCTUnwrap(d.activeLayerID))
      let after = try Renderer.composite(edit.result),before = try Renderer.composite(d)
      XCTAssertLessThan(after.pixel(x:7,y:11).r,before.pixel(x:7,y:11).r)
      XCTAssertEqual(after.pixel(x:8,y:11),before.pixel(x:8,y:11));XCTAssertEqual(after.pixel(x:1,y:1),before.pixel(x:1,y:1))
      XCTAssertEqual(after.pixel(x:7,y:11).a,before.pixel(x:7,y:11).a)
    }
  }
  func testInvalidStaleCancelledAndOversizedEditsAreAtomic() async throws {
    let d = try fixture(),id = try XCTUnwrap(d.activeLayerID)
    var r = RegionRetouchRequest(kind:.patch);r.dx = 100
    XCTAssertThrowsError(try RegionRetouchPreparation.prepare(r,document:d,layerID:id));r.dx = 0.5
    XCTAssertThrowsError(try r.validate());r.dx = 18
    let edit = try RegionRetouchPreparation.prepare(r,document:d,layerID:id)
    var changed = d;changed.name = "Changed";XCTAssertThrowsError(try edit.applied(to:changed))
    let cancelledRequest = r
    let task = Task { try Task.checkCancellation();return try RegionRetouchPreparation.prepare(cancelledRequest,document:d,layerID:id) };task.cancel()
    do { _ = try await task.value;XCTFail("Cancelled edit committed") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    r.kind = .redEye;r.region = .init(x:Int.min,y:0,width:4,height:4);XCTAssertThrowsError(try r.validate())
  }
  @MainActor func testPreviewCommitHistoryCancelAndToolBindings() async throws {
    let d = try fixture(),store = EditorStore(document:d)
    defer { store.cancelRegionRetouch();store.renderTask?.cancel() }
    for id in ["patch","contentAwareMove","redEye"] { XCTAssertNotNil(WorkspaceCatalog.tool(id).native) }
    store.chooseTool(WorkspaceCatalog.tool("contentAwareMove"));store.beginRegionRetouch(kind:.move)
    var draft = try XCTUnwrap(store.regionRetouchDraft);draft.frame.centerX += 18;store.updateRegionRetouch(draft)
    await store.regionRetouchTask?.value;XCTAssertNil(store.regionRetouchError);XCTAssertEqual(store.document,d);XCTAssertNotNil(store.regionRetouchPreview)
    let expected = try XCTUnwrap(store.regionRetouchPrepared).result;XCTAssertTrue(store.commitRegionRetouch());await store.geometryTask?.value
    XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,expected)
    store.beginRegionRetouch(kind:.move);draft = try XCTUnwrap(store.regionRetouchDraft);draft.frame.centerX -= 5;store.updateRegionRetouch(draft)
    let task = store.regionRetouchTask;store.cancelRegionRetouch();await task?.value;XCTAssertEqual(store.document,expected);XCTAssertNil(store.regionRetouchPrepared)
  }
  @MainActor func testActualCanvasPatchDragMoveTransformAndEscape() async throws {
    let d = try fixture(),store = EditorStore(document:d);defer { store.cancelRegionRetouch();store.renderTask?.cancel() }
    let canvas = CraftCanvas(store:store);canvas.frame = NSRect(x:0,y:0,width:600,height:400);store.zoom = 10
    func event(_ type: NSEvent.EventType,_ p: CGPoint) throws -> NSEvent { try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(canvas.viewPoint(p),to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)) }
    store.chooseTool(WorkspaceCatalog.tool("patch"))
    canvas.mouseDown(with:try event(.leftMouseDown,.init(x:7,y:11)));canvas.mouseDragged(with:try event(.leftMouseDragged,.init(x:25,y:11)));canvas.mouseUp(with:try event(.leftMouseUp,.init(x:25,y:11)))
    await store.regionRetouchTask?.value;await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertNil(store.regionRetouchDraft);XCTAssertNotEqual(store.document,d)
    await store.undo();store.chooseTool(WorkspaceCatalog.tool("contentAwareMove"))
    canvas.mouseDown(with:try event(.leftMouseDown,.init(x:7,y:11)));canvas.mouseDragged(with:try event(.leftMouseDragged,.init(x:25,y:11)));canvas.mouseUp(with:try event(.leftMouseUp,.init(x:25,y:11)))
    await store.regionRetouchTask?.value;XCTAssertNotNil(store.regionRetouchDraft);XCTAssertEqual(store.document,d)
    let key = try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53));canvas.keyDown(with:key);XCTAssertNil(store.regionRetouchDraft)
  }
  @MainActor func testThreeAPIsMatchEngineAndRejectBusyStaleInvalid() async throws {
    let helper = AutomationTests();try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture(),id = try XCTUnwrap(d.activeLayerID);shared.store.session = EditorSession(document:d);try service.share(shared)
      for name in RegionRetouchAPI.commands {
        var parameters: [String:Any] = ["layerID":id.uuidString]
        var r = RegionRetouchRequest(kind:name == "retouch.patch" ? .patch:name == "retouch.move" ? .move:.redEye)
        if r.kind == .redEye { r.region = .init(x:2,y:6,width:12,height:12);parameters.merge(["x":2,"y":6,"width":12,"height":12],uniquingKeysWith: { _,new in new }) }
        else { r.dx = 18;parameters["dx"] = 18;parameters["dy"] = 0 }
        let expected = try RegionRetouchPreparation.prepare(r,document:d,layerID:id).result
        let response = try await helper.edit(service,shared,name,parameters);XCTAssertEqual(response,200);XCTAssertEqual(shared.store.document,expected)
        let undo = try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
        let stale = try await helper.edit(service,shared,name,parameters,revision:"old");XCTAssertEqual(stale,409)
        var invalid = parameters;invalid["unknown"] = 1;let rejected = try await helper.edit(service,shared,name,invalid);XCTAssertEqual(rejected,400)
        shared.store.beginRegionRetouch(kind:.patch);let busy = try await helper.edit(service,shared,name,parameters);XCTAssertEqual(busy,409);shared.store.cancelRegionRetouch()
      }
      let invalid = try await helper.edit(service,shared,"retouch.patch",["layerID":id.uuidString,"dx":0.5,"dy":0]);XCTAssertEqual(invalid,400)
      XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testClosingCancelsPendingPreview() async throws {
    _ = NSApplication.shared;let controller = CraftDocumentController(workspaces:WorkspaceLibrary()),doc = CraftNSDocument(model:try fixture());controller.addDocument(doc)
    doc.store.beginRegionRetouch(kind:.move);var draft = try XCTUnwrap(doc.store.regionRetouchDraft);draft.frame.centerX += 18;doc.store.updateRegionRetouch(draft)
    let task = doc.store.regionRetouchTask;doc.close();await task?.value;XCTAssertNil(doc.store.regionRetouchDraft);XCTAssertNil(doc.store.regionRetouchPrepared)
  }
  func testLayerOffsetMaskAndProtectedTransparencySurvivePatch() throws {
    var d = try fixture(.f32),r = RegionRetouchRequest(kind:.patch);r.dx = 18
    d.layers[0].x = 2;d.selection = .init(x:6,y:8,width:8,height:8)
    d.layers[0].mask = try Surface(width:40,height:28,fill:.white)
    d.layers[0].protection = .transparency
    guard case .raster(var source) = d.layers[0].content else { return XCTFail("Raster missing") }
    source.setLinearPixel(x:7,y:11,.clear);d.layers[0].content = .raster(source)
    let result = try RegionRetouchPreparation.prepare(r,document:d,layerID:try XCTUnwrap(d.activeLayerID)).result
    XCTAssertEqual(result.layers[0].mask,d.layers[0].mask)
    XCTAssertEqual(result.layers[0].maskCoordinateTransform,d.layers[0].maskCoordinateTransform)
    XCTAssertEqual(result.layers[0].coordinateTransform,d.layers[0].coordinateTransform)
    XCTAssertEqual(try Renderer.composite(result).pixel(x:9,y:11).a,0)
  }
  @MainActor func testCanvasSelectionLassoAndRedEyeRegion() async throws {
    var d = try fixture();d.selection = nil
    let store = EditorStore(document:d);defer { store.cancelRegionRetouch();store.renderTask?.cancel() }
    let canvas = CraftCanvas(store:store);canvas.frame = NSRect(x:0,y:0,width:600,height:400);store.zoom = 10
    func event(_ type: NSEvent.EventType,_ p: CGPoint) throws -> NSEvent { try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(canvas.viewPoint(p),to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)) }
    store.chooseTool(WorkspaceCatalog.tool("patch"))
    canvas.mouseDown(with:try event(.leftMouseDown,.init(x:3,y:7)))
    for point in [CGPoint(x:13,y:7),CGPoint(x:13,y:17),CGPoint(x:3,y:17)] { canvas.mouseDragged(with:try event(.leftMouseDragged,point)) }
    canvas.mouseUp(with:try event(.leftMouseUp,.init(x:3,y:7)));await store.geometryTask?.value
    XCTAssertNotNil(store.document.selection);XCTAssertNil(store.regionRetouchDraft)
    store.chooseTool(WorkspaceCatalog.tool("redEye"));store.regionRetouchSettings.pupilSize = 100
    let before = store.document
    canvas.mouseDown(with:try event(.leftMouseDown,.init(x:2,y:6)));canvas.mouseDragged(with:try event(.leftMouseDragged,.init(x:14,y:18)));canvas.mouseUp(with:try event(.leftMouseUp,.init(x:14,y:18)))
    await store.regionRetouchTask?.value;await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertNil(store.regionRetouchDraft);XCTAssertNotEqual(store.document,before)
    await store.undo();XCTAssertEqual(store.document,before)
  }
  @MainActor func testRevokedAPIRequestDoesNotCommit() async throws {
    let helper = AutomationTests();try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture();shared.store.session = EditorSession(document:d);try service.share(shared)
      let parameters: [String:Any] = ["layerID":try XCTUnwrap(d.activeLayerID).uuidString,"dx":18,"dy":0]
      let pending = Task { try await helper.edit(service,shared,"retouch.move",parameters) }
      let deadline = Date().addingTimeInterval(5)
      while !shared.store.geometryBusy && Date() < deadline { await Task.yield() }
      XCTAssertTrue(shared.store.geometryBusy);service.stop();_ = try? await pending.value
      XCTAssertEqual(shared.store.document,d);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  func testProceduralRetouchEvidence() throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_RETOUCH_EVIDENCE_DIR"] else { return }
    let d = try fixture(),id = try XCTUnwrap(d.activeLayerID)
    var patch = RegionRetouchRequest(kind:.patch);patch.dx = 18
    var move = RegionRetouchRequest(kind:.move);move.dx = 18
    var extend = move;extend.moveMode = .extend
    var eye = RegionRetouchRequest(kind:.redEye);eye.region = .init(x:2,y:6,width:12,height:12);eye.pupilSize = 100
    let documents = try [d]+[patch,move,extend,eye].map { try RegionRetouchPreparation.prepare($0,document:d,layerID:id).result }
    var panel = try Surface(width:1600,height:224)
    for (index,document) in documents.enumerated() { let image = try Renderer.composite(document)
      for y in 0..<224 { for x in 0..<320 { panel.setPixel(x:index*320+x,y:y,image.pixel(x:x/8,y:y/8)) } }
    }
    var output = try CraftDocument(width:1600,height:224);output.layers[0].content = .raster(panel)
    try RasterIO.encoded(output,type:.png).write(to:URL(fileURLWithPath:path).appendingPathComponent("original-patch-move-extend-red-eye01.png"))
  }
}
