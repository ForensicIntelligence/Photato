import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore
import PhotoCraftImaging

private struct SelectionInstanceFixture:ObjectDetecting {
  var delay:Duration = .zero
  func mask(for image:Surface,at point:PathPoint)async throws->SelectionMask {
    if delay != .zero{try await Task.sleep(for:delay)}
    return try .make(.rectangle(.init(x:Int(point.x),y:6,width:8,height:16)),width:image.width,height:image.height,antiAlias:false)
  }
}
final class SelectionToolWorkflowTests:XCTestCase {
  func document(depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:48,height:40,depth:depth),surface=try Surface(width:48,height:40,depth:depth,fill:Pixel(0.1,0.3,0.8))
    for y in 10..<30 {for x in 12..<36 {surface.setPixel(x:x,y:y,Pixel(0.9,0.2,0.1))}}
    d.layers[0].content = .raster(surface);return d
  }
  @MainActor func store(depth:PixelDepth = .u8)throws->EditorStore {
    let s=EditorStore(document:try document(depth:depth),patterns:PatternLibrary(),actions:ActionLibrary(),brushes:BrushLibrary())
    s.brush.size=8;s.brush.hardness=1;s.brushOptions.pressureSize=false;s.objectDetector=SelectionInstanceFixture();s.objectFinderEnabled=false;return s
  }
  @MainActor func testBrushPreviewCancelOpacityHistoryAndArchive()async throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let s=try store(depth:depth);defer{s.cancelBrush();s.renderTask?.cancel()};let original=s.document
      s.chooseTool(WorkspaceCatalog.tool("selectionBrush"));s.brush.opacity=0.5
      s.beginBrush(.init(x:20,y:20),zoom:1);await s.brushPreviewTask?.value;await s.renderTask?.value
      XCTAssertTrue(s.document==original);XCTAssertNotNil(s.selectionOverlayImage);s.cancelBrush();await s.renderTask?.value;XCTAssertNil(s.selectionOverlayImage)
      s.beginBrush(.init(x:20,y:20),zoom:1);s.finishBrush();await s.geometryTask?.value;await s.renderTask?.value
      XCTAssertNil(s.error);let coverage=s.document.selectionMask!.coverage(x:20,y:20);XCTAssertGreaterThan(coverage,0);XCTAssertLessThan(coverage,1)
      XCTAssertEqual(s.document.layers,original.layers);XCTAssertEqual(s.session.undoStack.count,1)
      let saved=s.document;XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(saved))==saved)
      s.beginBrush(.init(x:20,y:20),zoom:1,alternate:true);s.finishBrush();await s.geometryTask?.value;XCTAssertLessThan(s.document.selectionMask!.coverage(x:20,y:20),coverage)
      _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==saved)
      s.chooseTool(WorkspaceCatalog.tool("move"));await s.renderTask?.value;XCTAssertNil(s.selectionOverlayImage)
      s.chooseTool(WorkspaceCatalog.tool("selectionBrush"));await s.renderTask?.value;XCTAssertNotNil(s.selectionOverlayImage)
    }
  }
  @MainActor func testQuickPreviewCommitAndToolSwitchCancellation()async throws {
    let s=try store();defer{s.cancelBrush();s.renderTask?.cancel()};s.tool = .quickSelection;let original=s.document
    s.beginBrush(.init(x:22,y:20),zoom:1);await s.brushPreviewTask?.value;await s.renderTask?.value
    XCTAssertNotNil(s.selectionPath);XCTAssertTrue(s.document==original)
    s.chooseTool(WorkspaceCatalog.tool("move"));XCTAssertNil(s.brushGesture);XCTAssertTrue(s.document==original)
    s.tool = .quickSelection;s.selectionEnhanceEdge=true;s.beginBrush(.init(x:22,y:20),zoom:1);s.finishBrush();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertGreaterThan(s.document.selectionMask!.coverage(x:25,y:20),0.9);XCTAssertLessThan(s.document.selectionMask!.coverage(x:2,y:2),0.1);XCTAssertEqual(s.document.layers,original.layers)
  }
  @MainActor func testObjectRectangleLassoAndPointThroughCanvas()async throws {
    for mode in ObjectSelectionMode.allCases {
      let s=try store();defer{s.renderTask?.cancel()};s.tool = .objectSelection;s.objectSelectionMode=mode
      let canvas=CraftCanvas(store:s);canvas.frame=NSRect(x:0,y:0,width:480,height:400)
      func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double)throws->NSEvent {
        let p=canvas.viewPoint(CGPoint(x:x,y:y));return try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
      }
      if mode == .point {canvas.mouseDown(with:try event(.leftMouseDown,18,20))}
      else {
        canvas.mouseDown(with:try event(.leftMouseDown,8,6))
        canvas.mouseDragged(with:try event(.leftMouseDragged,40,6));canvas.mouseDragged(with:try event(.leftMouseDragged,40,34))
        canvas.mouseUp(with:try event(.leftMouseUp,mode == .lasso ? 8:40,34))
      }
      await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertNotNil(s.document.selectionMask);XCTAssertEqual(s.session.undoStack.count,1)
      XCTAssertGreaterThan(s.document.selectionMask!.coverage(x:20,y:20),0.9);XCTAssertLessThan(s.document.selectionMask!.coverage(x:2,y:2),0.1)
    }
  }
  func testSamplingRespectsTransformsLockedSourcesAndCompositeChoice()throws {
    var d=try document();let first=d.layers[0].id;d.layers[0].x=4;d.layers[0].locked=true
    var top=Layer(name:"Visible",content:.raster(try Surface(width:48,height:40,fill:Pixel(0,1,0))));top.opacity=0.8;d.layers.append(top)
    let original=d,one=try SelectionToolPreparation.input(d,layerID:first,allLayers:false),all=try SelectionToolPreparation.input(d,layerID:first,allLayers:true)
    XCTAssertGreaterThan(one.pixel(x:20,y:20).r,0.8);XCTAssertGreaterThan(all.pixel(x:20,y:20).g,0.7);XCTAssertNotEqual(one,all);XCTAssertTrue(d==original)
    XCTAssertThrowsError(try SelectionToolPreparation.input(d,layerID:UUID(),allLayers:true))
  }
  @MainActor func testAPIEquivalentToNativeBrushQuickAndObject()async throws {
    let helper=AutomationTests()
    for command in ["selection.brush","selection.quick","selection.object"] {
      try await helper.withService(actions:ActionLibrary(),brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
        let native=try self.store(),s=document.store;defer{native.renderTask?.cancel()};s.session=EditorSession(document:native.document);s.brush=native.brush;try service.share(document)
        let parameters:[String:Any]
        if command == "selection.object" {
          native.tool = .objectSelection;native.selectObject(shape:.rectangle(.init(x:8,y:6,width:32,height:28)),mode:.replace)
          parameters=["mode":"replace","region":["rectangle":["x":8,"y":6,"width":32,"height":28]]]
        }else{
          native.tool = command == "selection.quick" ? .quickSelection:.selectionBrush
          native.beginBrush(.init(x:20,y:20),zoom:1,selectionMode:.replace);native.finishBrush()
          parameters=["mode":"replace","points":[["x":20,"y":20]]]
        }
        await native.geometryTask?.value;XCTAssertNil(native.error)
        let status=try await helper.edit(service,document,command,parameters);XCTAssertEqual(status,200);XCTAssertTrue(s.document==native.document)
        XCTAssertEqual(s.session.undoStack.count,1)
        let after=s.document;_=await s.requestHistory(redo:false).value;_=await s.requestHistory(redo:true).value;XCTAssertTrue(s.document==after)
      }
    }
  }
  @MainActor func testAPIConfigInvalidBusyStaleAndRevocation()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.document());s.objectDetector=SelectionInstanceFixture();try service.share(document)
      var code=try await helper.edit(service,document,"selection.configure",["mode":"subtract","objectMode":"Lasso","sampleAllLayers":true,"enhanceEdge":true,"overlayColor":["r":0.1,"g":0.8,"b":0.2,"a":0.4]])
      XCTAssertEqual(code,200);XCTAssertEqual(s.objectSelectionMode,.lasso);XCTAssertTrue(s.selectionSampleAllLayers);XCTAssertEqual(s.session.undoStack.count,0)
      let configured=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"selection.object","revision":"preview","parameters":["region":["point":["x":20,"y":20]]]]))
      XCTAssertEqual(try configured.selectionToolRequest(store:s).mode,.subtract)
      let original=s.document
      for p:[String:Any] in [["region":["point":["x":true,"y":2]]],["region":["point":["x":2,"y":2],"polygon":[]]],["region":["rectangle":["x":0,"y":0,"width":-1,"height":3]]],["region":["polygon":[["x":0,"y":0]]]]] {
        code=try await helper.edit(service,document,"selection.object",p);XCTAssertEqual(code,400);XCTAssertTrue(s.document==original)
      }
      code=try await helper.edit(service,document,"selection.quick",["points":[["x":20,"y":20]]],revision:"stale");XCTAssertEqual(code,409)
      s.tool = .selectionBrush;s.beginBrush(.init(x:20,y:20),zoom:1)
      code=try await helper.edit(service,document,"selection.configure",["mode":"add"]);XCTAssertEqual(code,409);s.cancelBrush()
      s.selectionEnhanceEdge=false;s.objectDetector=SelectionInstanceFixture(delay:.milliseconds(100))
      let task=Task{try await helper.edit(service,document,"selection.object",["mode":"replace","region":["point":["x":20,"y":20]]])}
      try await Task.sleep(for:.milliseconds(20));service.revoke(try XCTUnwrap(service.shares.first?.id));code=try await task.value;XCTAssertEqual(code,409);XCTAssertTrue(s.document==original)
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.selectionToolsState))
      XCTAssertNoThrow(try BrushAPI.merge(state,schema:SelectionToolAPI.stateSchema))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:SelectionToolAPI.capabilities))
    }
  }
  @MainActor func testRecordedCoverageAndFactoryToolControls()async throws {
    let s=try store();defer{s.renderTask?.cancel()};let original=s.document
    XCTAssertTrue(s.chooseShortcut("w",cycle:false));XCTAssertEqual(s.tool,.objectSelection)
    XCTAssertTrue(s.chooseShortcut("w",cycle:true));XCTAssertEqual(s.tool,.quickSelection)
    try s.session.startActionRecording(name:"Selection");s.beginBrush(.init(x:20,y:20),zoom:1);s.finishBrush();await s.geometryTask?.value
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot),file=try ActionLibraryFile.decode(ActionLibraryFile(actions:[action]).encoded());XCTAssertEqual(file.version,4)
    var replay=original;try file.actions[0].apply(to:&replay);XCTAssertTrue(replay==s.document)
    var bad=file;bad.version=3;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONEncoder().encode(bad)))
    for id in ["objectSelection","quickSelection","selectionBrush"] {
      s.chooseTool(WorkspaceCatalog.tool(id));XCTAssertNil(s.unavailableToolID)
      let view=NSHostingView(rootView:SelectionToolOptionsView(store:s));view.frame=NSRect(x:0,y:0,width:1200,height:44);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,200)
    }
    XCTAssertEqual(WorkspaceCatalog.tool("selectionBrush").shortcut,"")
  }
}
