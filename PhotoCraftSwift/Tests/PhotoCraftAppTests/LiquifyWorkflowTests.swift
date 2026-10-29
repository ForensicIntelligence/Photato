import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct LiquifyFacesStub: LiquifyFaceDetecting {
  var delay = false
  func faces(in image: Surface) async throws -> [LiquifyFaceGeometry] {
    if delay { try await Task.sleep(for:.milliseconds(150)) }
    return [.init(bounds:[0.1,0.1,0.8,0.8],leftEye:[0.2,0.3,0.15,0.08],rightEye:[0.6,0.3,0.15,0.08],nose:[0.4,0.4,0.15,0.2],mouth:[0.3,0.65,0.4,0.12])]
  }
}
final class LiquifyWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width:64,height:48,depth:depth)
    var s = try Surface(width:64,height:48,depth:depth,colorEncoding:depth == .f32 ? .linearRGB : .sRGB)
    for y in 0..<48 { for x in 0..<64 {
      let p = Pixel(x%12<6 ? 0.9:0.1,Float(y)/48,0.2,x<5 ? 0:1)
      if depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) }
    } }
    d.layers[0].content = .raster(s); return d
  }
  var settings: LiquifySettings { .init(width:64,height:48,strokes:[.init(size:24,points:[[24,24,1],[32,24,1]])]) }
  func filter() -> RasterFilter { var f = RasterFilter(.liquify); f.liquify = settings; return f }
  @MainActor func wait(_ model: LiquifyWorkspace) async { while model.rendering { await model.task?.value } }
  @MainActor func testWorkspaceStrokeLocalUndoCancelCommitAndDocumentUndo() async throws {
    let original = try fixture(), store = EditorStore(document:original), model = LiquifyWorkspace()
    defer { model.close(); store.renderTask?.cancel() }
    store.beginFilter(.liquify); await store.renderTask?.value
    model.onChange = { store.filterDraft?.filter.liquify = $0 }
    await model.prepare(document:original,draft:try XCTUnwrap(store.filterDraft)); await wait(model)
    XCTAssertTrue(model.ready); XCTAssertNotNil(model.image)
    model.size = 24; model.begin(x:24,y:24,pressure:1,alternate:false); model.drag(x:32,y:24,pressure:1); model.end(); await wait(model)
    XCTAssertNil(model.error); XCTAssertEqual(store.document,original); XCTAssertEqual(model.settings,settings)
    XCTAssertGreaterThan(try XCTUnwrap(model.field).maximumDisplacement,0)
    let edited = model.settings; model.undo(); await wait(model)
    XCTAssertTrue(try XCTUnwrap(model.field).isIdentity); model.redo(); await wait(model)
    XCTAssertEqual(model.settings,edited)
    var expected = original; try Command.applyFilter(original.layers[0].id,filter()).apply(to:&expected)
    store.commitFilter(); await store.geometryTask?.value
    XCTAssertNil(store.error); XCTAssertEqual(store.document,expected)
    await store.undo(); XCTAssertEqual(store.document,original); await store.redo(); XCTAssertEqual(store.document,expected)
    store.beginFilter(.liquify); store.filterDraft?.filter.liquify = settings; store.cancelFilter(); XCTAssertEqual(store.document,expected)
  }
  @MainActor func testMaskFaceSliderHistoryAndMeshRoundtrip() async throws {
    let original = try fixture(), model = LiquifyWorkspace()
    defer { model.close() }
    await model.prepare(document:original,draft:.init(id:original.layers[0].id,filter:filter())); await wait(model)
    model.detect(using:LiquifyFacesStub()); await model.detectionTask?.value; await wait(model)
    XCTAssertEqual(model.settings.faces.count,1)
    let before = model.settings, count = model.undoStates.count
    model.faceSlider(true); model.setFace(.smile,value:25); model.setFace(.smile,value:60); model.faceSlider(false); await wait(model)
    XCTAssertEqual(model.undoStates.count,count+1); model.undo(); XCTAssertEqual(model.settings,before)
    model.global(.freezeAll); await wait(model); XCTAssertEqual(model.field?.frozen(x:24,y:24),1)
    let saved = try LiquifyMeshFile.encode(model.settings); model.restore(); await wait(model)
    XCTAssertTrue(try XCTUnwrap(model.field).isIdentity)
    model.change(try LiquifyMeshFile.decode(saved)); await wait(model); XCTAssertEqual(model.field?.frozen(x:24,y:24),1)
    model.size = .nan; model.begin(x:1,y:1,pressure:1,alternate:false); XCTAssertNil(model.stroke); XCTAssertNotNil(model.error)
  }
  func testDepthsSelectionNative19AndExplicitPSDMeshRejection() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth); let id = d.layers[0].id
      d.selection = IntRect(x:16,y:12,width:28,height:28)
      let original = d; try Command.applyFilter(id,filter()).apply(to:&d)
      XCTAssertNotEqual(d,original)
      guard case .raster(let a) = original.layers[0].content,case .raster(let b) = d.layers[0].content else { return XCTFail() }
      XCTAssertEqual(a.pixel(x:5,y:5),b.pixel(x:5,y:5))
      var smart = try fixture(depth); try SmartObjectIO.convert(in:smart,selected:[smart.layers[0].id]).apply(to:&smart)
      let source = smart.layers[0].content; try Command.applyFilter(smart.layers[0].id,filter()).apply(to:&smart)
      XCTAssertEqual(smart.layers[0].content,source); XCTAssertEqual(smart.minimumArchiveVersion,19)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(smart)),smart)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(smart)),smart)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(smart))
      let input = try LiquifyInput.prepare(document:smart,layerID:smart.layers[0].id,filterID:smart.layers[0].smartFilters!.filters[0].id)
      XCTAssertEqual(input.width,64); XCTAssertEqual(input.height,48)
    }
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:#"[{"_obj":"liquify"}]"#))
  }
  @MainActor func testHTTPWarpSmartFilterStateArchiveAndErrors() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{ 0 }) { service,shared in
      let d = try fixture(), layerID = d.layers[0].id
      shared.store.session = EditorSession(document:d); try service.share(shared)
      let program = try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
      let parameters: [String:Any] = ["layerID":layerID.uuidString,"filter":["kind":"liquify","liquify":program]]
      var expected = d; try Command.applyFilter(layerID,filter()).apply(to:&expected)
      let code = try await helper.edit(service,shared,"filter.apply",parameters); XCTAssertEqual(code,200); XCTAssertEqual(shared.store.document,expected)
      let undo = try await helper.edit(service,shared,"history.undo"); XCTAssertEqual(undo,200); XCTAssertEqual(shared.store.document,d)
      let bad = try await helper.edit(service,shared,"filter.apply",["layerID":layerID.uuidString,"filter":["kind":"liquify","liquify":["strokes":[["size":true]]]]]); XCTAssertEqual(bad,400); XCTAssertEqual(shared.store.document,d)
      let stale = try await helper.edit(service,shared,"filter.apply",parameters,revision:"stale"); XCTAssertEqual(stale,409)
      shared.store.beginFilter(.liquify); let busy = try await helper.edit(service,shared,"filter.apply",parameters); XCTAssertEqual(busy,409); shared.store.cancelFilter()
      var smart = d; try SmartObjectIO.convert(in:smart,selected:[layerID]).apply(to:&smart)
      shared.store.session = EditorSession(document:smart)
      let applied = try await helper.edit(service,shared,"filter.apply",["layerID":smart.layers[0].id.uuidString,"filter":["kind":"liquify","liquify":program]]); XCTAssertEqual(applied,200)
      service.setDocumentTransfersEnabled(true); let id = try XCTUnwrap(service.shares.first?.id)
      let old = try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"18"]); XCTAssertEqual(old.0.statusCode,422)
      let native = try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"19"]); XCTAssertEqual(native.0.statusCode,200); XCTAssertEqual(try NativeArchive.decode(native.1),shared.store.document)
      var stack = try XCTUnwrap(shared.store.document.layers[0].smartFilters)
      stack.filters[0].filter.liquify?.strokes.append(.init(tool:.reconstructAll))
      var value = stack.apiState; value.removeValue(forKey:"hasMask"); value.removeValue(forKey:"maskTransform")
      let set = try await helper.edit(service,shared,"smartFilter.set",["layerID":smart.layers[0].id.uuidString,"stack":value]); XCTAssertEqual(set,200)
      XCTAssertEqual(shared.store.document.layers[0].smartFilters,stack)
    }
  }
  @MainActor func testReadOnlyFaceDetectionAndStaleCompletion() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{ 0 }) { service,shared in
      let d = try fixture(); shared.store.session = EditorSession(document:d); try service.share(shared)
      service.liquifyFaceDetector = LiquifyFacesStub()
      let shareID = try XCTUnwrap(service.shares.first?.id)
      let body: [String:Any] = ["command":"liquify.faces","revision":service.revision(shared.store),"parameters":["layerID":d.layers[0].id.uuidString]]
      let result = try await helper.request(service,path:"/v1/documents/\(shareID)/commands",body:body)
      XCTAssertEqual(result.0.statusCode,200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with:result.1) as? [String:Any]); XCTAssertEqual((json["faces"] as? [Any])?.count,1)
      XCTAssertEqual(shared.store.document,d); XCTAssertTrue(shared.store.session.undoStack.isEmpty)
      service.liquifyFaceDetector = LiquifyFacesStub(delay:true)
      let pending = Task { try await helper.request(service,path:"/v1/documents/\(shareID)/commands",body:body) }
      try await Task.sleep(for:.milliseconds(50)); shared.store.perform(.selection(IntRect(x:0,y:0,width:2,height:2)))
      let stale = try await pending.value; XCTAssertEqual(stale.0.statusCode,409)
    }
  }
  func testCommandPayloadLimitsAndSchema() throws {
    let path = "/v1/documents/\(UUID())/commands"
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:path), (ICCProfile.maximumBytes + 2) / 3 * 4 + 16_384)
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:"/v1/unknown"),65536)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LiquifySettings.apiCapabilities))
    XCTAssertEqual(Set(LiquifySettings.faceResultSchema["required"] as? [String] ?? []),["revision","width","height","faces"])
  }
  @MainActor func testWorkspaceLayoutAndFactoryShortcut() async throws {
    let store = EditorStore(document:try fixture()); defer { store.renderTask?.cancel() }; store.beginFilter(.liquify)
    let model = LiquifyWorkspace(); defer { model.close() }
    await model.prepare(document:store.document,draft:try XCTUnwrap(store.filterDraft)); model.change(settings); await wait(model)
    let host = NSHostingView(rootView:LiquifySheet(store:store,workspace:model)); host.frame = NSRect(origin:.zero,size:host.fittingSize); host.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(host.fittingSize.width,800)
    if let folder = ProcessInfo.processInfo.environment["PHOTATO_LIQUIFY_CAPTURE"] {
      let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:rep)
      try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:folder).appendingPathComponent("liquify-workspace02.png"))
    }
    XCTAssertEqual(AppDelegate.filterMenus["Filter > Liquify…"],.liquify)
  }
}
