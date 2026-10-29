import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ContentAwareWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:24,height:24,depth:depth)
    var s = try Surface(width:24,height:24,depth:depth,fill:Pixel(0.2,0.5,0.7),colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 9..<15 { for x in 9..<15 { if depth == .f32 { s.setLinearPixel(x:x,y:y,Pixel(1,0,0)) } else { s.setPixel(x:x,y:y,Pixel(1,0,0)) } } }
    d.layers[0].content = .raster(s); d.selection = .init(x:9,y:9,width:6,height:6); return d
  }
  @MainActor func ready(_ m: ContentAwareWorkspace) async {
    await m.task?.value
    while m.loading || m.rendering { await m.task?.value }
    await m.overlayTask?.value
  }
  @MainActor func testWorkspacePreviewStrokesLocalHistoryCancelCommitAndUndo() async throws {
    let d = try fixture(),store = EditorStore(document:d); defer { store.cancelContentAwareFill(); store.renderTask?.cancel() }
    store.beginContentAwareFill(); let m = try XCTUnwrap(store.contentAwareDraft); await ready(m)
    XCTAssertNil(m.error); XCTAssertTrue(m.canCommit); XCTAssertNotNil(m.previewImage); XCTAssertNotNil(m.samplingImage); XCTAssertNotNil(m.originalImage); XCTAssertEqual(store.document,d)
    m.size = 3; m.begin(x:2,y:2,alternate:false); m.drag(x:4,y:2); m.end(); await ready(m)
    XCTAssertEqual(m.sampled?.bytes[2*24+3],0); let painted = m.sampled
    m.undo(); await ready(m); XCTAssertNotEqual(m.sampled,painted); m.redo(); await ready(m); XCTAssertEqual(m.sampled,painted)
    let expected = try XCTUnwrap(m.edit).applied(to:d)
    store.commitContentAwareFill(); await m.commitTask?.value
    XCTAssertNil(m.error); XCTAssertNil(store.contentAwareDraft); XCTAssertEqual(store.document.layers.count,2)
    XCTAssertEqual(try Renderer.composite(store.document),try Renderer.composite(expected)); XCTAssertEqual(store.document.layers[0],d.layers[0])
    await store.undo(); XCTAssertEqual(store.document,d); await store.redo(); XCTAssertEqual(store.document.layers.count,2)
    let before = store.document; store.beginContentAwareFill(); let cancel = try XCTUnwrap(store.contentAwareDraft); store.cancelContentAwareFill(); await cancel.task?.value; XCTAssertEqual(store.document,before)
  }
  func testOutputsAtAllDepthsAllLayersSamplingAndPSD() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth),input = try ContentAwareInput.prepare(d,layerID:d.layers[0].id)
      var settings = ContentAwareSettings(); settings.colorAdaptation = .none
      for output in ContentAwareOutput.allCases {
        let edit = try input.edit(settings:settings,output:output),result = try edit.applied(to:d)
        let composite = try Renderer.composite(result); XCTAssertEqual(composite.pixel(x:12,y:12).r,try Renderer.composite(d).pixel(x:0,y:0).r,accuracy:0.01)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
        let psd = try PSDCodec.writeRasterLayers(result); XCTAssertFalse(psd.isEmpty)
      }
    }
    var d = try fixture(); var empty = d.layers[0]; empty.id = UUID(); empty.content = .raster(try Surface(width:24,height:24)); d.layers.append(empty); d.activeLayerID = empty.id
    let input = try ContentAwareInput.prepare(d,layerID:empty.id)
    XCTAssertThrowsError(try input.edit(settings:.init()))
    var all = ContentAwareSettings(); all.sampleAllLayers = true
    XCTAssertNotNil(try input.edit(settings:all).applied(to:d).activeLayerID)
  }
  func testCustomSavedSamplingSelectionLassoAndLocks() throws {
    var d = try fixture(); let source = try SelectionMask.make(.rectangle(.init(x:0,y:0,width:8,height:24)),width:24,height:24,antiAlias:false)
    let input = try ContentAwareInput.prepare(d,layerID:d.layers[0].id)
    var settings = ContentAwareSettings(); settings.sampling = .custom; settings.colorAdaptation = .none
    XCTAssertThrowsError(try input.edit(settings:settings))
    var stroke = ContentAwareStroke(); stroke.target = .selection; stroke.kind = .lasso; stroke.add = true; stroke.points = [[15,9],[17,9],[17,15],[15,15]]
    let edit = try input.edit(settings:settings,output:.current,strokes:[stroke],sampling:source)
    XCTAssertGreaterThan(edit.selection.bounds!.width,6)
    d.layers[0].protection = .image; XCTAssertThrowsError(try edit.applied(to:d))
    let new = try input.edit(settings:settings,output:.new,sampling:source); XCTAssertEqual(try new.applied(to:d).layers.count,2)
  }
  func testHDRSourceValuesRemainAboveOne() throws {
    var d = try fixture(.f32);var pixels = try Surface(width:24,height:24,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<24 { for x in 0..<24 { pixels.setLinearPixel(x:x,y:y,Pixel(2,4,0.5)) } }
    for y in 9..<15 { for x in 9..<15 { pixels.setLinearPixel(x:x,y:y,Pixel(0,0,0)) } }
    d.layers[0].content = .raster(pixels)
    let result = try ContentAwareInput.prepare(d,layerID:d.layers[0].id).edit(settings:.init(),output:.current).applied(to:d)
    guard case .raster(let output) = result.layers[0].content else { return XCTFail("Missing raster") }
    XCTAssertEqual(output.linearPixel(x:12,y:12).r,2,accuracy:0.002);XCTAssertEqual(output.linearPixel(x:12,y:12).g,4,accuracy:0.002)
    XCTAssertEqual(output.linearPixel(x:0,y:0),pixels.linearPixel(x:0,y:0))
  }
  @MainActor func testHTTPMatchesDesktopValidationHistoryAndRevocation() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      let d = try fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      let parameters: [String:Any] = ["layerID":d.layers[0].id.uuidString,"output":"current","settings":["colorAdaptation":"none"]]
      var settings = ContentAwareSettings(); settings.colorAdaptation = .none
      let expected = try ContentAwareInput.prepare(d,layerID:d.layers[0].id).edit(settings:settings,output:.current).applied(to:d)
      let status = try await helper.edit(service,shared,"contentAware.fill",parameters); XCTAssertEqual(status,200); XCTAssertEqual(shared.store.document,expected)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(shared.store.document,d)
      let stale = try await helper.edit(service,shared,"contentAware.fill",parameters,revision:"old"); XCTAssertEqual(stale,409)
      shared.store.beginContentAwareFill(); let busy = try await helper.edit(service,shared,"contentAware.fill",parameters); XCTAssertEqual(busy,409); shared.store.cancelContentAwareFill()
      for bad: Any in [["scale":1],["margin":-1],["rotation":"banana"],["unknown":1]] {
        var p = parameters;p["settings"] = bad;let response = try await helper.edit(service,shared,"contentAware.fill",p);XCTAssertEqual(response,400)
      }
      XCTAssertEqual(shared.store.document,d)
      let pending = Task { try await helper.edit(service,shared,"contentAware.fill",parameters) }
      let deadline = Date().addingTimeInterval(5);while !shared.store.geometryBusy && Date() < deadline { await Task.yield() }
      XCTAssertTrue(shared.store.geometryBusy);service.stop();_ = try? await pending.value;XCTAssertEqual(shared.store.document,d)
    }
  }
  @MainActor func testCloseAndReloadCancelWorkspaceAndFactoryMenuBinding() async throws {
    _ = NSApplication.shared
    let controller = CraftDocumentController(workspaces:WorkspaceLibrary())
    let doc = CraftNSDocument(model:try fixture());controller.addDocument(doc);doc.store.beginContentAwareFill();let m = try XCTUnwrap(doc.store.contentAwareDraft)
    doc.close();await m.task?.value;XCTAssertNil(doc.store.contentAwareDraft);XCTAssertFalse(m.ready)
    try PhotoshopMenuTests().withMenus { _,menu in
      let item = PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == "Edit > Content-Aware Fill…" }
      XCTAssertEqual(item?.action,#selector(AppDelegate.contentAwareFill))
    }
  }
  func testVisualTextureRepairEvidence() throws {
    let w = 64,h = 48;var d = try CraftDocument(width:w,height:h);var image = try Surface(width:w,height:h)
    for y in 0..<h { for x in 0..<w { let checker: Float = ((x/4+y/4)%2 == 0) ? 0.3:0.7;image.setPixel(x:x,y:y,Pixel(checker,0.2+Float(y)/120,0.3+Float(x)/160)) } }
    for y in 20..<28 { for x in 28..<36 { image.setPixel(x:x,y:y,Pixel(1,0,0)) } }
    d.layers[0].content = .raster(image);d.selection = .init(x:28,y:20,width:8,height:8)
    var settings = ContentAwareSettings();settings.colorAdaptation = .none
    let edit = try ContentAwareInput.prepare(d,layerID:d.layers[0].id).edit(settings:settings,output:.current),result = try edit.applied(to:d)
    guard case .raster(let after) = result.layers[0].content else { return XCTFail("Missing raster") }
    XCTAssertLessThan(after.pixel(x:32,y:24).r,0.9)
    for y in 0..<h { for x in 0..<w where !(d.selection!.contains(x,y)) { XCTAssertEqual(after.pixel(x:x,y:y),image.pixel(x:x,y:y)) } }
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_CAF_EVIDENCE_DIR"] {
      var sheet = try Surface(width:w*2+4,height:h,fill:.white)
      for y in 0..<h { for x in 0..<w { sheet.setPixel(x:x,y:y,image.pixel(x:x,y:y));sheet.setPixel(x:x+w+4,y:y,after.pixel(x:x,y:y)) } }
      var output = try CraftDocument(width:sheet.width,height:sheet.height);output.layers[0].content = .raster(sheet)
      try RasterIO.encoded(output,type:.png).write(to:URL(fileURLWithPath:folder).appendingPathComponent("texture-before-after01.png"))
    }
  }
}
