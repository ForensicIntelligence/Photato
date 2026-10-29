import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore
import PhotoCraftImaging

final class PaintingWorkflowTests:XCTestCase {
  func document()throws->CraftDocument {
    var d=try CraftDocument(width:80,height:40);var s=try Surface(width:80,height:40,fill:Pixel(0.2,0.6,0.2))
    for y in 0..<40 {for x in 40..<80{s.setPixel(x:x,y:y,Pixel(0.1,0.1,0.5))}};d.layers[0].content = .raster(s);return d
  }
  @MainActor func store(_ d:CraftDocument)throws->EditorStore {
    let s=EditorStore(document:d,patterns:PatternLibrary(),actions:ActionLibrary(),brushes:BrushLibrary());s.brush.color=Pixel(1,0,0);s.brush.size=10;s.brush.hardness=1;s.brushOptions.pressureSize=false;s.brushOptions.seed=9;return s
  }
  @MainActor func testNativeToolsPreviewCancelCommitAndHistory()async throws {
    for tool in [EditorTool.pencil,.colorReplacement,.mixerBrush,.patternStamp,.backgroundEraser,.magicEraser] {
      let d=try document(),s=try store(d);defer{s.cancelBrush();s.renderTask?.cancel()};s.tool=tool
      s.mixerPaint.load(Pixel(1,0,0));let paint=s.mixerPaint
      s.beginBrush(.init(x:16,y:20,time:0),zoom:1)
      if tool != .magicEraser{s.extendBrush(.init(x:62,y:20,time:100))}
      let request=try XCTUnwrap(s.brushGesture?.paintingRequest),expected=try PaintingPreparation.prepare(request,in:d)
      await s.brushPreviewTask?.value;await s.renderTask?.value
      XCTAssertTrue(s.document==d);XCTAssertEqual(s.mixerPaint,paint)
      XCTAssertTrue(s.surface == (try Renderer.composite(expected.result)),"Native preview mismatch: \(tool)")
      s.cancelBrush();await s.renderTask?.value;XCTAssertTrue(s.document==d);XCTAssertEqual(s.session.undoStack.count,0)
      s.beginBrush(.init(x:16,y:20,time:0),zoom:1);if tool != .magicEraser{s.extendBrush(.init(x:62,y:20,time:100))}
      let final=try PaintingPreparation.prepare(XCTUnwrap(s.brushGesture?.paintingRequest),in:d)
      s.finishBrush();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertTrue(s.document==final.result,"Commit mismatch: \(tool)");XCTAssertEqual(s.session.undoStack.count,1)
      if tool == .mixerBrush{XCTAssertEqual(s.mixerPaint,final.session.mixer)}
      _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==d);_=await s.requestHistory(redo:true).value;XCTAssertTrue(s.document==final.result)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(s.document))==s.document)
    }
  }
  @MainActor func testPencilAndBrushCreateEditableLayerAndCanvasMagicClick()async throws {
    var d=try document();d.layers[0].content = .fill(Pixel(0,1,0))
    let s=try store(d);defer{s.renderTask?.cancel()};s.tool = .pencil
    s.beginBrush(.init(x:10,y:10),zoom:1);s.finishBrush();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,2);XCTAssertEqual(s.document.layers[0],d.layers[0]);XCTAssertEqual(s.selectedLayerIDs,[s.document.activeLayerID!])
    _=await s.requestHistory(redo:false).value;s.tool = .brush;s.beginBrush(.init(x:10,y:10),zoom:1);s.finishBrush();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,2)
    s.session=EditorSession(document:try document());s.tool = .magicEraser
    let canvas=CraftCanvas(store:s);canvas.frame=NSRect(x:0,y:0,width:400,height:200)
    let point=canvas.viewPoint(CGPoint(x:16,y:20))
    let e=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:1,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
    canvas.mouseDown(with:e);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.session.undoStack.count,1);XCTAssertNil(s.brushGesture)
  }
  @MainActor func testMixerSamplingLoadCleanAndCancelledGesture()async throws {
    let s=try store(document());defer{s.renderTask?.cancel();s.cancelBrush()};s.tool = .mixerBrush;s.brush.size=30
    s.sampleMixer(at:.init(40,20));await s.geometryTask?.value
    XCTAssertFalse(s.geometryBusy);XCTAssertNil(s.error);XCTAssertNotNil(s.mixerPaint.tip);XCTAssertEqual(s.session.undoStack.count,0)
    let loaded=s.mixerPaint;s.beginBrush(.init(x:10,y:20),zoom:1);s.extendBrush(.init(x:65,y:20));await s.brushPreviewTask?.value;s.cancelBrush();XCTAssertEqual(s.mixerPaint,loaded)
    s.cleanMixer();XCTAssertNil(s.mixerPaint.reservoir);s.loadMixerColor();XCTAssertEqual(s.mixerPaint.reservoir,s.brush.color)
    s.currentPaintOptions.loadSolidColorOnly=true;s.sampleMixer(at:.init(10,20));await s.geometryTask?.value;XCTAssertNil(s.mixerPaint.tip);XCTAssertGreaterThan(s.mixerPaint.reservoir!.g,0.5)
  }
  @MainActor func testHTTPAllSixToolsMatchNativeAndRejectInvalidBusyStale()async throws {
    let helper=AutomationTests()
    try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      for tool in PaintTool.allCases where tool != .brush {
        var d=try self.document();d.patterns=[try RasterPattern(name:"API solid",surface:Surface(width:2,height:2,fill:Pixel(1,0,0)))];let s=document.store;s.session=EditorSession(document:d);s.brush.color=Pixel(1,0,0);s.brush.size=10;s.brush.hardness=1;s.mixerPaint.load(s.brush.color);try service.share(document)
        var p:[String:Any]=["tool":tool.rawValue,"points":[["x":16,"y":20],["x":62,"y":20]],"brush":["settings":["seed":9,"pressureSize":false]]]
        if tool == .magicEraser{p["points"]=[["x":16,"y":20]]}
        if tool == .patternStamp{p["patternID"]=d.patterns![0].id}
        let command=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"paint.tool","revision":"preview","parameters":p]))
        let expected=try PaintingPreparation.prepare(command.paintingRequest(store:s),in:d)
        var status=try await helper.edit(service,document,"paint.tool",p);XCTAssertEqual(status,200,tool.rawValue);XCTAssertTrue(s.document==expected.result,tool.rawValue);XCTAssertEqual(s.session.undoStack.count,1)
        status=try await helper.edit(service,document,"paint.tool",p,revision:"stale");XCTAssertEqual(status,409)
        status=try await helper.edit(service,document,"history.undo");XCTAssertEqual(status,200);XCTAssertTrue(s.document==d)
      }
      let s=document.store,baseline=s.document
      for p:[String:Any] in [["tool":"pencil","options":["wet":0.5]],["tool":"mixerBrush","options":["wet":true]],["tool":"backgroundEraser","options":["tolerance":2]],["tool":"patternStamp","options":["placement":["oops":2]]]] {
        let status=try await helper.edit(service,document,"paint.configure",p);XCTAssertEqual(status,400)
      }
      s.tool = .pencil;s.beginBrush(.init(x:10,y:10),zoom:1)
      let busy=try await helper.edit(service,document,"paint.mixer",["operation":"clean"]);XCTAssertEqual(busy,409);s.cancelBrush();XCTAssertTrue(s.document==baseline)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:s.paintingState));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:PaintingAPI.capabilities))
    }
  }
  @MainActor func testHTTPMixerStateAndRevokedSampling()async throws {
    let helper=AutomationTests()
    try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.document());try service.share(document);let closing=service.documentClosingRevision
      var status=try await helper.edit(service,document,"paint.configure",["tool":"mixerBrush","options":["wet":0.8,"cleanAfterStroke":false]]);XCTAssertEqual(status,200)
      status=try await helper.edit(service,document,"paint.mixer",["operation":"load","color":["r":1,"g":0,"b":0,"a":1]]);XCTAssertEqual(status,200);XCTAssertEqual(s.mixerPaint.reservoir,Pixel(1,0,0));XCTAssertEqual(service.documentClosingRevision,closing)
      status=try await helper.edit(service,document,"paint.mixer",["operation":"sample","x":20,"y":20,"size":12,"solid":true]);XCTAssertEqual(status,200);XCTAssertGreaterThan(s.mixerPaint.reservoir!.g,0.5);XCTAssertEqual(s.session.undoStack.count,0)
      let before=s.mixerPaint,shareID=try XCTUnwrap(service.shares.first?.id)
      let command=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"paint.mixer","revision":service.revision(s),"parameters":["operation":"sample","x":40,"y":20,"size":2048,"allLayers":true,"solid":false]]))
      let task=Task{try await service.configurePainting(command,document:document,shareID:shareID)}
      for _ in 0..<200 where !s.geometryBusy {await Task.yield()}
      XCTAssertTrue(s.geometryBusy);service.revoke(shareID)
      do{try await task.value;XCTFail("Revoked Mixer sample committed")}catch{}
      XCTAssertEqual(s.mixerPaint,before);XCTAssertFalse(s.geometryBusy)
    }
  }
  @MainActor func testHTTPMasksChannelsAndNonrasterTargets()async throws {
    let helper=AutomationTests()
    try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      var d=try self.document();d.layers[0].mask=try Surface(width:80,height:40,fill:.white)
      var alpha=AlphaChannel(name:"Inverse display",pixels:try Surface(width:80,height:40,fill:.white));alpha.options.indicates = .selectedAreas
      try Command.channel(.create(alpha)).apply(to:&d);document.store.session=EditorSession(document:d);try service.share(document)
      for target in ["layerMask","alpha"] {
        var p:[String:Any]=["tool":"pencil","points":[["x":20,"y":20]],"target":target,"brush":["size":8,"color":["r":0,"g":0,"b":0,"a":1]]]
        if target=="alpha"{p["channelID"]=alpha.id.uuidString}
        let command=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"paint.tool","revision":"preview","parameters":p]))
        let expected=try PaintingPreparation.prepare(command.paintingRequest(store:document.store),in:document.store.document)
        let status=try await helper.edit(service,document,"paint.tool",p);XCTAssertEqual(status,200);XCTAssertTrue(document.store.document==expected.result)
      }
      var nonraster=try self.document();nonraster.layers[0].content = .fill(.white);document.store.session=EditorSession(document:nonraster)
      let status=try await helper.edit(service,document,"paint.stroke",["points":[["x":10,"y":10]],"brush":["size":8,"color":["r":0,"g":0,"b":0,"a":1]]]);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document.layers.count,2)
    }
  }
  @MainActor func testToolGroupsShortcutsAndNativeOptionsLayout()throws {
    let s=try store(document());defer{s.renderTask?.cancel()}
    _=s.chooseShortcut("b",cycle:false);XCTAssertEqual(s.tool,.brush)
    for tool in [EditorTool.pencil,.colorReplacement,.mixerBrush,.brush] {_=s.chooseShortcut("b",cycle:true);XCTAssertEqual(s.tool,tool)}
    _=s.chooseShortcut("s",cycle:false);_=s.chooseShortcut("s",cycle:true);XCTAssertEqual(s.tool,.patternStamp)
    _=s.chooseShortcut("e",cycle:false);_=s.chooseShortcut("e",cycle:true);XCTAssertEqual(s.tool,.backgroundEraser);_=s.chooseShortcut("e",cycle:true);XCTAssertEqual(s.tool,.magicEraser)
    for tool in [EditorTool.pencil,.colorReplacement,.mixerBrush,.patternStamp,.backgroundEraser,.magicEraser] {
      s.tool=tool;let view=NSHostingView(rootView:PaintingToolOptionsView(store:s));view.frame=NSRect(x:0,y:0,width:1600,height:44);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,200)
    }
  }
  func testCancelledPaintNeverProducesPreparedDocument()async throws {
    var d=try document();d.layers[0].content = .raster(try Surface(width:80,height:40,fill:.white))
    let original=d;var brush=Brush();brush.settings = .init();brush.size=100
    let request=PaintToolRequest(tool:.colorReplacement,target:.pixels(d.layers[0].id),points:(0..<4096).map{.init(x:Double($0%80),y:Double($0%40))},brush:brush)
    let worker=Task.detached{try PaintingPreparation.prepare(request,in:original)};worker.cancel()
    do{_ = try await worker.value;XCTFail("Cancelled painting produced a commit")}catch is CancellationError{}catch{XCTFail("Unexpected error: \(error)")}
    XCTAssertTrue(d==original)
  }
  func testTransformedSmartFilterMaskRetainsDocumentCoordinates()throws {
    var d=try document();let originalID=d.layers[0].id;try SmartObjectIO.convert(in:d,selected:[originalID]).apply(to:&d);let id=d.layers[0].id
    d.layers[0].x=7;d.layers[0].y=3;d.layers[0].smartFilters = .init();d.layers[0].smartFilters!.mask=try Surface(width:1,height:1,fill:.white)
    d.layers[0].smartFilters!.maskProperties.transform = .translation(12,4)
    var brush=Brush();brush.size=6;brush.color = .black;brush.settings = .init();brush.settings!.pressureSize=false
    let r=PaintToolRequest(tool:.pencil,target:.smartFilterMask(id),points:[.init(x:22,y:12)],brush:brush)
    let result=try PaintingPreparation.prepare(r,in:d).result,stack=try XCTUnwrap(result.layers[0].smartFilters),mask=try XCTUnwrap(stack.mask)
    let p=try stack.maskProperties.transform.inverted().point(22.5,12.5)
    XCTAssertEqual(mask.pixel(x:Int(floor(p.x)),y:Int(floor(p.y))).r,0);XCTAssertEqual(result.layers[0].content,d.layers[0].content);XCTAssertEqual(result.layers[0].x,7)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result))==result)
  }
}
