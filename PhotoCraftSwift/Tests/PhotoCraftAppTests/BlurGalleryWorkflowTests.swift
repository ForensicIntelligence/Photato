import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BlurGalleryWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false) throws -> CraftDocument {
    var d=try CraftDocument(width:40,height:32,depth:depth),pixels=try Surface(width:40,height:32,depth:depth)
    for y in 0..<32 { for x in 0..<40 { let v=Float((x*7+y*3)%23)/22;pixels.setPixel(x:x,y:y,Pixel(v,Float(x%5)/4,1-v,(x+y)%7 == 0 ? 0.4:1)) } }
    d.layers[0].content = .raster(pixels)
    if smart { try SmartObjectIO.convert(in:d,selected:[d.layers[0].id]).apply(to:&d) };return d
  }
  func filter(_ mode:BlurGallerySettings.Mode)->RasterFilter { var f=RasterFilter(.blurGallery);f.gallery?.enabled=[mode];return f }
  func testRustFieldWeightingIrisAndTiltProfiles() throws {
    var s=BlurGallerySettings(),a=BlurGallerySettings.Pin(),b=a;a.x=0;a.y=0;a.blur=10;b.x=1;b.y=0;b.blur=30;s.field=[a,b]
    XCTAssertEqual(BlurGalleryEngine.amount(s,mode:.field,x:5,y:0,width:10,height:10),20,accuracy:1e-12)
    XCTAssertEqual(BlurGalleryEngine.amount(s,mode:.field,x:0,y:0,width:10,height:10),10.19607843137255,accuracy:1e-12)
    XCTAssertEqual(BlurGalleryEngine.amount(s,mode:.iris,x:20,y:16,width:40,height:32),0)
    XCTAssertEqual(BlurGalleryEngine.amount(s,mode:.iris,x:0,y:0,width:40,height:32),15)
    XCTAssertEqual(BlurGalleryEngine.amount(s,mode:.tiltShift,x:0,y:16,width:40,height:32),0)
    XCTAssertEqual(BlurGalleryEngine.amount(s,mode:.tiltShift,x:20,y:0,width:40,height:32),15)
    // The original Rust variable blur uses sigma=blur*0.6 and seven levels.
    let input=(0..<9).map { SIMD4<Double>(Double($0==4 ? 1:0),0,0,1) }
    let actual=try BlurGalleryEngine.variable(input,9,1,[Double](repeating:5,count:9)),expected=try RasterFilterEngine.gaussian(input,9,1,3)
    for i in actual.indices { XCTAssertEqual(actual[i].x,expected[i].x,accuracy:1e-12) }
  }
  func testAllFiveModesDepthsHistorySelectionAndIdentity() throws {
    for depth in PixelDepth.allCases { for mode in BlurGallerySettings.Mode.allCases {
      let d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
      try session.execute(.applyFilter(id,filter(mode)));XCTAssertNotEqual(session.document.layers[0].content,d.layers[0].content,mode.rawValue)
      let after=session.document;try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,after)
      var selected=d;selected.selection = .init(x:10,y:8,width:10,height:8);try Command.applyFilter(id,filter(mode)).apply(to:&selected)
      guard case .raster(let original)=d.layers[0].content,case .raster(let result)=selected.layers[0].content else { return XCTFail() }
      XCTAssertEqual(result.pixel(x:0,y:0),original.pixel(x:0,y:0))
      var empty=filter(mode);empty.gallery?.enabled=[];var same=d;try Command.applyFilter(id,empty).apply(to:&same);XCTAssertEqual(same,d)
    } }
  }
  func testStrictJSONDeterminismAndClosedSharpRegions() throws {
    var s=BlurGallerySettings();s.enabled=[.iris];s.noiseAmount=10;s.noise = .grain;s.lightBokeh=25
    XCTAssertEqual(try BlurGallerySettings.decodeJSON(JSONEncoder().encode(s)),s)
    for raw in ["{\"unknown\":1}","{\"field\":[{\"blur\":-1}]}","{\"paths\":[{\"points\":[{\"x\":0,\"y\":0,\"z\":1}]}]}","{\"enabled\":[\"field\",\"field\"]}","{\"lightMin\":0.9,\"lightMax\":0.1}"] { XCTAssertThrowsError(try BlurGallerySettings.decodeJSON(Data(raw.utf8))) }
    var a=try fixture(.f32),b=a;let original=a;var f=RasterFilter(.blurGallery);f.gallery=s
    try Command.applyFilter(a.layers[0].id,f).apply(to:&a);try Command.applyFilter(b.layers[0].id,f).apply(to:&b);XCTAssertEqual(a,b)
    guard case .raster(let source)=original.layers[0].content,case .raster(let result)=a.layers[0].content else { return XCTFail() }
    XCTAssertEqual(result.linearPixel(x:20,y:16),source.linearPixel(x:20,y:16))
  }
  func testSmartFilterNative29SourceRetentionMaskAndReedit() throws {
    var d=try fixture(smart:true);let before=d,id=d.layers[0].id
    try Command.applyFilter(id,filter(.field)).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,29);XCTAssertEqual(d.layers[0].smartObject,before.layers[0].smartObject);XCTAssertEqual(d.layers[0].content,before.layers[0].content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d)
    XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
    var stack=d.layers[0].smartFilters!;stack.filters[0].filter.gallery?.enabled=[.path];try Command.smartFilters(id,stack).apply(to:&d)
    XCTAssertNotEqual(try Renderer.composite(d),try Renderer.composite(before))
    stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(before))
  }
  @MainActor func testWorkspaceHandlesLocalUndoCommitCancelAndOffscreenLayout() async throws {
    let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary())
    defer { store.renderTask?.cancel() }
    store.beginFilter(.blurGallery);let model=BlurGalleryWorkspace();await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft))
    XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d)
    model.choose(.iris);model.selected=0
    let handle=try XCTUnwrap(model.handles.first{$0.kind == .radiusX});model.beginGesture();model.move(handle,to:.init(0.9,0.5));model.endGesture();await model.task?.value
    XCTAssertTrue(model.ready,model.error ?? "Preview failed");let settings=model.settings
    XCTAssertEqual(settings.iris[0].radiusX,0.5,accuracy:1e-12)
    model.undo();await model.task?.value;XCTAssertEqual(model.settings.iris[0].radiusX,0.35)
    model.redo();await model.task?.value;XCTAssertEqual(model.settings,settings)
    model.choose(.path);model.add(at:.init(0.1,0.2));let pathHandle=try XCTUnwrap(model.handles.first{$0.index == model.selected && $0.pointIndex == 1})
    model.beginGesture();model.move(pathHandle,to:.init(0.7,0.8));model.endGesture();await model.task?.value;XCTAssertEqual(model.path?.points.last,.init(0.7,0.8))
    let view=NSHostingView(rootView:BlurGallerySheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:900,height:680);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();let folder=root.appendingPathComponent("artifacts/blur-gallery-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(UUID().uuidString+".png")) } }
    let committed=model.settings;store.filterDraft?.filter.gallery=committed;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=d,f=RasterFilter(.blurGallery);f.gallery=committed;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters!.filters[0].id;XCTAssertEqual(store.document,expected)
    let undo=await store.requestHistory(redo:false).value;XCTAssertTrue(undo);XCTAssertEqual(store.document,d)
    store.beginFilter(.blurGallery);let cancel=BlurGalleryWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.choose(.spin);let task=cancel.task;cancel.close();store.cancelFilter();await task?.value;XCTAssertEqual(store.document,d)
  }
  @MainActor func testHTTPAllModesSharedEngineSmartFilterReeditNative29AndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for mode in BlurGallerySettings.Mode.allCases {
        let d=try self.fixture();document.store.session=EditorSession(document:d);var expected=d;try Command.applyFilter(d.layers[0].id,self.filter(mode)).apply(to:&expected)
        let code=try await helper.edit(service,document,"filter.apply",["layerID":d.layers[0].id.uuidString,"filter":["kind":"blurGallery","gallery":["enabled":[mode.rawValue]]]])
        XCTAssertEqual(code,200);XCTAssertEqual(document.store.document,expected)
      }
      let d=try self.fixture(smart:true),id=d.layers[0].id;document.store.session=EditorSession(document:d)
      let params:[String:Any]=["layerID":id.uuidString,"filter":["kind":"blurGallery","gallery":["enabled":["iris"],"iris":[["blur":25,"x":0.4]]]]]
      let code=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(code,200)
      let changed=document.store.document;let share=try XCTUnwrap(service.shares.first?.id)
      let path="/v1/documents/\(share)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"28"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"29"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.gallery?.iris[0].blur=35;var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await helper.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":payload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,changed)
      let stale=try await helper.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.blurGallery);let busy=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let bad=try await helper.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"blurGallery","gallery":["enabled":["field"],"field":[["x":true]]]]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,changed)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:BlurGallerySettings.apiSchema))
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"blurGallery\"}]"))
    }
  }

  func testSingleInstantaneousSpinFlashIsIdentityAndExposuresRespond() throws {
    var s=BlurGallerySettings();s.enabled=[.spin];s.strobeStrength=100;s.strobeFlashes=1;s.strobeDuration=0
    let input=(0..<400).map { i in SIMD4<Double>(Double(i%17)/16,Double(i%7)/6,0.2,1) }
    let instant=try BlurGalleryEngine.process(input,width:20,height:20,settings:s).pixels
    for i in input.indices { for c in 0..<4 { XCTAssertEqual(instant[i][c],input[i][c],accuracy:1e-12) } }
    s.strobeFlashes=2;let two=try BlurGalleryEngine.process(input,width:20,height:20,settings:s).pixels;XCTAssertNotEqual(two,instant)
    s.strobeFlashes=1;s.strobeDuration=20;let exposure=try BlurGalleryEngine.process(input,width:20,height:20,settings:s).pixels;XCTAssertNotEqual(exposure,instant)
    var d=try fixture();try Command.channel(.quickMask(true,.init())).apply(to:&d);let before=d
    XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter(.field))).apply(to:&d));XCTAssertEqual(d,before)
  }

}
