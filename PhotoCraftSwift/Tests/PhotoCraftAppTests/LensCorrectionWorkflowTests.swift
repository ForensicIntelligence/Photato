import AppKit
import XCTest
import SwiftUI
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LensCorrectionWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false) throws -> CraftDocument { try BlurGalleryWorkflowTests().fixture(depth,smart:smart) }
  func filter()->RasterFilter { var f=RasterFilter(.lensCorrection);f.lens?.distortion=40;f.lens?.redCyan=30;f.lens?.vignetteAmount=25;return f }
  func testIndependentRustGeometryAndDocumentedMidpointDirection() throws {
    var s=LensCorrectionSettings();s.distortion=50
    let map=LensCorrectionEngine.Map(s,width:200,height:100),corner=try XCTUnwrap(map.sample(x:0,y:0)),center=try XCTUnwrap(map.sample(x:100,y:50))
    XCTAssertEqual(corner.green.x,12.5,accuracy:1e-10);XCTAssertEqual(corner.green.y,6.25,accuracy:1e-10);XCTAssertEqual(center.green,PathPoint(100,50))
    s = .init();s.redCyan = -100
    let ca=try XCTUnwrap(LensCorrectionEngine.Map(s,width:300,height:200).sample(x:10,y:10));XCTAssertEqual(ca.red.x,9.44,accuracy:1e-10);XCTAssertEqual(ca.green.x,10,accuracy:1e-10)
    s = .init();s.vertical = -50
    let vertical=LensCorrectionEngine.Map(s,width:300,height:200),tl=try XCTUnwrap(vertical.sample(x:0,y:0)),tr=try XCTUnwrap(vertical.sample(x:300,y:0)),bl=try XCTUnwrap(vertical.sample(x:0,y:200)),br=try XCTUnwrap(vertical.sample(x:300,y:200))
    XCTAssertLessThan(tr.green.x-tl.green.x,br.green.x-bl.green.x)
    s = .init();s.vignetteAmount=100;s.vignetteMidpoint=0
    let low=try XCTUnwrap(LensCorrectionEngine.Map(s,width:300,height:200).sample(x:100,y:100));s.vignetteMidpoint=100
    let high=try XCTUnwrap(LensCorrectionEngine.Map(s,width:300,height:200).sample(x:100,y:100));XCTAssertGreaterThan(low.gain,high.gain);XCTAssertEqual(high.gain,1)
    XCTAssertLessThan(LensCorrectionSettings.Profile.generic(focalLength:16).k1,-0.05);XCTAssertGreaterThan(LensCorrectionSettings.Profile.generic(focalLength:135).k1,0)
  }
  func testStraightenAutoScaleIdentityAndEdges() throws {
    let correction=LensCorrectionEngine.straightenAngle(.init(0,0),.init(1,1.5*tan(5 * .pi/180)),width:300,height:200);XCTAssertEqual(correction,-5,accuracy:1e-10)
    var s=LensCorrectionSettings();s.angle=5;s.autoScale=true
    let scale=try LensCorrectionEngine.resolvedScale(s,width:300,height:200);XCTAssertGreaterThan(scale,105);XCTAssertLessThan(scale,130)
    s.angle=45;XCTAssertThrowsError(try LensCorrectionEngine.resolvedScale(s,width:300,height:1))
    let input=[SIMD4<Double>](repeating:.init(0.2,0.4,0.6,1),count:16)
    s = .init();XCTAssertEqual(try LensCorrectionEngine.process(input,width:4,height:4,settings:s),input)
    s.scale=50
    for edge in LensCorrectionSettings.Edge.allCases {
      s.edge=edge;s.edgeColor=[0.3,0.1,0.7,0.5]
      let first=try LensCorrectionEngine.process(input,width:4,height:4,settings:s)[0]
      switch edge {
      case .transparency:XCTAssertEqual(first,.zero)
      case .edgeExtension:XCTAssertEqual(first,input[0])
      case .black:XCTAssertEqual(first,.init(0,0,0,1))
      case .white:XCTAssertEqual(first,.init(1,1,1,1))
      case .color:XCTAssertEqual(first,.init(0.15,0.05,0.35,0.5))
      }
    }
  }
  func testDepthSelectionLocksHistoryAndInvalidAtomicity() throws {
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id;var session=EditorSession(document:d)
      try session.execute(.applyFilter(id,RasterFilter(.lensCorrection)));XCTAssertEqual(session.document,d)
      try session.execute(.applyFilter(id,filter()));XCTAssertNotEqual(session.document.layers[0].content,d.layers[0].content);let after=session.document
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,after)
      var selected=d;selected.selection = .init(x:8,y:8,width:12,height:12);try Command.applyFilter(id,filter()).apply(to:&selected)
      guard case .raster(let original)=d.layers[0].content,case .raster(let result)=selected.layers[0].content else { return XCTFail() };XCTAssertEqual(result.pixel(x:0,y:0),original.pixel(x:0,y:0))
      var locked=d;locked.layers[0].protection=[.transparency];var edgeFilter=filter();edgeFilter.lens?.scale=50
      try Command.applyFilter(id,edgeFilter).apply(to:&locked)
      guard case .raster(let lockedPixels)=locked.layers[0].content else { return XCTFail() }
      for y in 0..<32 { for x in 0..<40 { XCTAssertEqual(lockedPixels.pixel(x:x,y:y).a,original.pixel(x:x,y:y).a) } }
      locked.layers[0].protection=[.image];let protected=locked;XCTAssertThrowsError(try Command.applyFilter(id,edgeFilter).apply(to:&locked));XCTAssertEqual(locked,protected)
      var bad=filter();bad.lens?.scale = .nan;let before=session.document;XCTAssertThrowsError(try session.execute(.applyFilter(id,bad)));XCTAssertEqual(session.document,before)
      var channel=d;try Command.channel(.quickMask(true,.init())).apply(to:&channel);let channelBefore=channel;XCTAssertThrowsError(try Command.channel(.filter(.quickMask,filter())).apply(to:&channel));XCTAssertEqual(channel,channelBefore)
    }
  }
  func testStrictProfileSettingsAndNative30SourceRetention() throws {
    var settings=LensCorrectionSettings();settings.profile = .generic(focalLength:24);settings.straighten=[.init(0.1,0.2),.init(0.8,0.3)];settings.autoScale=true
    XCTAssertEqual(try LensCorrectionSettings.decodeJSON(JSONEncoder().encode(settings)),settings)
    for raw in ["{\"unknown\":1}","{\"scale\":true}","{\"autoScale\":1}","{\"profile\":{\"k3\":1}}","{\"profile\":{\"vignette\":[1,2]}}","{\"edgeColor\":[1,2,3]}","{\"straighten\":[{\"x\":0,\"y\":0},{\"x\":0,\"y\":0}]}"] { XCTAssertThrowsError(try LensCorrectionSettings.decodeJSON(Data(raw.utf8)),raw) }
    var generic=LensCorrectionSettings();generic.genericFocalLength=16;XCTAssertEqual(generic.resolvedProfile,.generic(focalLength:16));XCTAssertEqual(try LensCorrectionSettings.decodeJSON(JSONEncoder().encode(generic)),generic);generic.profile = .init();XCTAssertThrowsError(try generic.validate())
    var d=try fixture(smart:true);let before=d,id=d.layers[0].id;var f=filter();f.lens=settings
    try Command.applyFilter(id,f).apply(to:&d);XCTAssertEqual(d.minimumArchiveVersion,30);XCTAssertEqual(d.layers[0].smartObject,before.layers[0].smartObject);XCTAssertEqual(d.layers[0].content,before.layers[0].content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)),d);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d);XCTAssertThrowsError(try DocumentIO.encode(d,format:.psd))
    XCTAssertNotEqual(try Renderer.composite(d),try Renderer.composite(before))
    var stack=d.layers[0].smartFilters!;stack.filters[0].opacity=0;try Command.smartFilters(id,stack).apply(to:&d);XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(before))
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"lensCorrection\"}]"))
  }
  @MainActor func testNativeWorkspaceGesturePreviewUndoCommitCancelAndLayout() async throws {
    let d=try fixture(smart:true),store=EditorStore(document:d,actions:ActionLibrary());defer { store.renderTask?.cancel() }
    store.beginFilter(.lensCorrection);let model=LensCorrectionWorkspace();await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState))
    model.beginGesture();model.distort(from:.init(1,0.5),to:.init(0.8,0.5));model.endGesture();await model.task?.value;XCTAssertEqual(model.settings.distortion,40,accuracy:1e-9)
    let changed=model.settings;model.undo();await model.task?.value;XCTAssertEqual(model.settings,.init());model.redo();await model.task?.value;XCTAssertEqual(model.settings,changed)
    model.beginGesture();model.straighten(.init(0.1,0.2),.init(0.8,0.3));model.endGesture();await model.task?.value;XCTAssertLessThan(model.settings.angle,0);XCTAssertTrue(model.ready,model.error ?? "Failed")
    let view=NSHostingView(rootView:LensCorrectionSheet(store:store,model:model));view.frame=NSRect(x:0,y:0,width:940,height:720);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,800)
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();let folder=root.appendingPathComponent("artifacts/lens-correction-offscreen");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try png.write(to:folder.appendingPathComponent(UUID().uuidString+".png")) } }
    let committed=model.settings;store.filterDraft?.filter.lens=committed;model.close();store.commitFilter();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1)
    var expected=d,f=RasterFilter(.lensCorrection);f.lens=committed;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=store.document.layers[0].smartFilters!.filters[0].id;XCTAssertEqual(store.document,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,d)
    store.beginFilter(.lensCorrection);let cancel=LensCorrectionWorkspace();await cancel.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));cancel.change(filter().lens!);let task=cancel.task;cancel.close();store.cancelFilter();await task?.value;XCTAssertEqual(store.document,d)
  }
  @MainActor func testHTTPSharedEngineProfilesSmartFilterNative30AndGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) { service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let d=try self.fixture(),id=d.layers[0].id;document.store.session=EditorSession(document:d);var expected=d;try Command.applyFilter(id,self.filter()).apply(to:&expected)
      let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(self.filter().lens!))
      let params:[String:Any]=["layerID":id.uuidString,"filter":["kind":"lensCorrection","lens":encoded]]
      let code=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(code,200);XCTAssertEqual(document.store.document,expected)
      let smart=try self.fixture(smart:true),sid=smart.layers[0].id;document.store.session=EditorSession(document:smart)
      let request:[String:Any]=["layerID":sid.uuidString,"filter":["kind":"lensCorrection","lens":["genericFocalLength":16,"autoScale":true]]]
      let applied=try await helper.edit(service,document,"filter.apply",request);XCTAssertEqual(applied,200);let changed=document.store.document
      let share=try XCTUnwrap(service.shares.first?.id),path="/v1/documents/\(share)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"29"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"30"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),changed)
      var stack=changed.layers[0].smartFilters!;stack.filters[0].filter.lens?.distortion=20;var payload=stack.apiState;payload.removeValue(forKey:"hasMask");payload.removeValue(forKey:"maskTransform")
      let edited=try await helper.edit(service,document,"smartFilter.set",["layerID":sid.uuidString,"stack":payload]);XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document.layers[0].smartFilters,stack)
      _=try await helper.edit(service,document,"history.undo");XCTAssertEqual(document.store.document,changed)
      let stale=try await helper.edit(service,document,"filter.apply",request,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginFilter(.lensCorrection);let busy=try await helper.edit(service,document,"filter.apply",request);XCTAssertEqual(busy,409);document.store.cancelFilter()
      let bad=try await helper.edit(service,document,"filter.apply",["layerID":sid.uuidString,"filter":["kind":"lensCorrection","lens":["distortion":true]]]);XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,changed)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LensCorrectionSettings.apiCapabilities))
    }
  }
  @MainActor func testPlacedSmartObjectCoordinatesAndRecordedBatch() async throws {
    var d=try fixture(smart:true);d.layers[0].affine = .scale(1.5,0.75)
    let projected=try SmartFilterEngine.renderedLayer(d.layers[0],in:d)
    guard case .raster(let pixels)=projected.content else { return XCTFail() }
    let model=LensCorrectionWorkspace();await model.prepare(document:d,draft:FilterDraft(id:d.layers[0].id,filter:filter()))
    XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(model.sourceSize,CGSize(width:pixels.width,height:pixels.height));XCTAssertEqual(model.sourceTransform,projected.coordinateTransform);model.close()
    let root=try ActionBatchTests().folder();defer { try? FileManager.default.removeItem(at:root) }
    let source=try fixture(),f=filter()
    let action=RecordedAction(name:"Lens",steps:[.init(name:"Lens Correction",operation:.filter(.active,f))])
    let portable=try JSONDecoder().decode(RecordedAction.self,from:JSONEncoder().encode(action));let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];XCTAssertEqual(try encoder.encode(portable),try encoder.encode(action))
    var expected=source;try Command.applyFilter(source.layers[0].id,f).apply(to:&expected)
    let results=try await ActionBatch.run(sources:[.init(document:source)],action:portable,destination:root,format:.native)
    let output=try XCTUnwrap(results.first?.output);XCTAssertEqual(try DocumentIO.read(root.appendingPathComponent(output)),expected)
    let helper=AutomationTests(),library=ActionLibrary();try library.save(action)
    try await helper.withService(actions:library,pressedMouseButtons:{0}) { service,document in
      document.store.session=EditorSession(document:source);try service.share(document);service.setDocumentSavesEnabled(true);service.setSaveDirectory(root)
      let share=try XCTUnwrap(service.shares.first?.id)
      let parameters:[String:Any]=["actionID":action.id.uuidString,"sources":[["id":share.uuidString,"revision":service.revision(document.store)]],"format":"photato","suffix":"-api"]
      let response=try await helper.request(service,path:"/v1/documents/\(share)/commands",body:["command":"actions.batch","revision":service.revision(document.store),"parameters":parameters]);XCTAssertEqual(response.0.statusCode,200)
      let body=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any]),item=try XCTUnwrap((body["results"] as? [[String:Any]])?.first),file=try XCTUnwrap(item["output"] as? String)
      XCTAssertEqual(try DocumentIO.read(root.appendingPathComponent(file)),expected);XCTAssertEqual(document.store.document,source)
    }
  }

}
