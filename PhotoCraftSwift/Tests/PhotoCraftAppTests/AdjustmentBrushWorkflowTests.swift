import AppKit
import SwiftUI
import CoreVideo
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore
import PhotoCraftImaging

private struct TestObjectDetector:ObjectDetecting {
  var delay:Duration = .zero
  func mask(for image:Surface,at point:PathPoint)async throws->SelectionMask {
    if delay != .zero {try await Task.sleep(for:delay)}
    return try .make(.rectangle(.init(x:Int(point.x),y:0,width:8,height:image.height)),width:image.width,height:image.height,antiAlias:false)
  }
}
final class AdjustmentBrushWorkflowTests:XCTestCase {
  @MainActor func store()throws->EditorStore {
    var d=try CraftDocument(width:40,height:24);d.layers[0].content = .raster(try Surface(width:40,height:24,fill:Pixel(0.2,0.3,0.4)))
    let s=EditorStore(document:d,patterns:PatternLibrary(),actions:ActionLibrary(),brushes:BrushLibrary());s.tool = .adjustmentBrush;s.brush.size=8;s.brush.hardness=1;s.brushOptions.pressureSize=false;s.objectDetector=TestObjectDetector();return s
  }
  @MainActor func testNativePreviewCancelCommitRefineReplaceNewAndPersistence()async throws {
    let s=try store(),original=s.document;defer{s.cancelBrush();s.renderTask?.cancel()};s.adjustmentBrushOverlay=true
    s.beginBrush(.init(x:12,y:12),zoom:1);let request=try XCTUnwrap(s.brushGesture?.adjustmentRequest);var expected=original;try request.apply(to:&expected)
    await s.brushPreviewTask?.value;await s.renderTask?.value;XCTAssertTrue(s.document==original);XCTAssertTrue(s.surface == (try Renderer.composite(expected)));XCTAssertNotNil(s.displayedMaskImage)
    s.cancelBrush();await s.renderTask?.value;XCTAssertNil(s.displayedMaskImage);XCTAssertTrue(s.document==original)
    s.beginBrush(.init(x:12,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,2);let id=try XCTUnwrap(s.adjustmentBrushLayer?.id)
    XCTAssertTrue(s.editingMask);XCTAssertEqual(s.selectedLayerIDs,[id]);XCTAssertEqual(s.session.undoStack.count,1)
    s.beginBrush(.init(x:12,y:12),zoom:1,alternate:true);s.finishBrush();await s.geometryTask?.value;XCTAssertEqual(s.document.layers.last!.mask!.pixel(x:12,y:12).r,0)
    s.replaceAdjustmentBrush(.photoFilter);await s.geometryTask?.value;XCTAssertEqual(s.currentAdjustmentBrushKind,.photoFilter)
    s.updateMask(id){$0.feather=2;$0.density=0.7};let saved=s.document
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(saved))==saved)
    _=await s.requestHistory(redo:false).value;_=await s.requestHistory(redo:true).value;XCTAssertTrue(s.document==saved)
    s.newAdjustmentBrush();s.beginBrush(.init(x:25,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value;XCTAssertEqual(s.document.layers.count,3);XCTAssertNil(s.error)
    let view=NSHostingView(rootView:AdjustmentBrushOptionsView(store:s));view.frame=NSRect(x:0,y:0,width:1700,height:44);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,400)
    _=s.chooseShortcut("k",cycle:false);XCTAssertEqual(s.tool,.frame);XCTAssertTrue(WorkspaceCatalog.tools.contains{$0.native == .adjustmentBrush && $0.shortcut.isEmpty})
  }
  @MainActor func testNativeObjectCanvasAndCancellation()async throws {
    let s=try store();defer{s.renderTask?.cancel()};s.adjustmentBrushObject=true
    let canvas=CraftCanvas(store:s);canvas.frame=NSRect(x:0,y:0,width:400,height:240)
    let p=canvas.viewPoint(CGPoint(x:10,y:12));let event=try XCTUnwrap(NSEvent.mouseEvent(with:.leftMouseDown,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:1,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
    canvas.mouseDown(with:event);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers.count,2)
    XCTAssertEqual(s.document.layers.last!.mask!.pixel(x:12,y:12).r,1);XCTAssertEqual(s.document.layers.last!.mask!.pixel(x:25,y:12).r,0)
    let original=s.document;s.objectDetector=TestObjectDetector(delay:.milliseconds(60));s.newAdjustmentBrush();s.applyAdjustmentObject(at:.init(25,12));s.geometryTask?.cancel();await s.geometryTask?.value;XCTAssertTrue(s.document==original)
  }
  func testVisionLabelLookupUsesPaddedTopLeftCoordinates()throws {
    var value:CVPixelBuffer?;XCTAssertEqual(CVPixelBufferCreate(nil,3,2,kCVPixelFormatType_OneComponent8,nil,&value),kCVReturnSuccess);let buffer=try XCTUnwrap(value)
    CVPixelBufferLockBaseAddress(buffer,[]);let base=try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to:UInt8.self),stride=CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<2{for x in 0..<3{base[y*stride+x]=UInt8(y*3+x)}};CVPixelBufferUnlockBaseAddress(buffer,[])
    XCTAssertEqual(try VisionForegroundDetector.instance(at:.init(5,5),in:buffer,imageWidth:30,imageHeight:20),0)
    XCTAssertEqual(try VisionForegroundDetector.instance(at:.init(25,15),in:buffer,imageWidth:30,imageHeight:20),5)
    XCTAssertThrowsError(try VisionForegroundDetector.instance(at:.init(30,15),in:buffer,imageWidth:30,imageHeight:20))
  }
  func testTypedSettingsAllKindsAndMalformedTrees()throws {
    for kind in AdjustmentBrushKind.allCases {
      let json=AdjustmentBrushAPI.settings(kind.initial),data=try JSONSerialization.data(withJSONObject:json)
      let value=try JSONDecoder().decode(AutomationValue.self,from:data)
      XCTAssertEqual(try AdjustmentBrushAPI.decode(value,kind:kind,base:kind.initial),kind.initial)
      XCTAssertThrowsError(try AdjustmentBrushAPI.decode(.object(["unknown":.number(1)]),kind:kind,base:kind.initial))
    }
    XCTAssertThrowsError(try AdjustmentBrushAPI.decode(.object(["exposure":.bool(true)]),kind:.exposure,base:.exposure(1)))
    XCTAssertThrowsError(try AdjustmentBrushAPI.decode(.object(["exposure":.number(21)]),kind:.exposure,base:.exposure(1)))
    let curve=try AdjustmentBrushAPI.decode(.object(["rgb":.object(["points":.array([.object(["input":.number(0),"output":.number(0)]),.object(["input":.number(128),"output":.number(160)]),.object(["input":.number(255),"output":.number(255)])])])]),kind:.curves,base:AdjustmentBrushKind.curves.initial)
    guard case .curves(let value)=curve else{return XCTFail()};XCTAssertEqual(value.rgb.points.count,3)
    XCTAssertThrowsError(try AdjustmentBrushAPI.decode(.object(["color":.object(["a":.bool(true)])]),kind:.photoFilter,base:AdjustmentBrushKind.photoFilter.initial))
    let gradient:[String:Any]=["gradient":["colors":[["position":0,"midpoint":0.5,"color":["hsb":["hue":120,"saturation":1,"brightness":1]]],["position":1,"midpoint":0.5,"color":["gray":["ink":0.5]]]]]]
    let input=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:gradient))
    XCTAssertNoThrow(try AdjustmentBrushAPI.decode(input,kind:.gradientMap,base:AdjustmentBrushKind.gradientMap.initial))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AdjustmentBrushAPI.capabilities))
  }
  @MainActor func testHTTPMatchesNativeAndInvalidBusyStaleRequests()async throws {
    let helper=AutomationTests()
    try await helper.withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.store().document);let original=s.document;try service.share(document)
      let newID=UUID();let p:[String:Any]=["kind":"exposure","settings":["exposure":0.7],"newLayer":true,"newLayerID":newID.uuidString,"points":[["x":12,"y":12]],"brush":["size":8,"hardness":1,"settings":["seed":5,"pressureSize":false]]]
      let command=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"adjustmentBrush.stroke","revision":"preview","parameters":p]));let request=try command.adjustmentBrushRequest(store:s);var expected=original;try request.apply(to:&expected)
      var status=try await helper.edit(service,document,"adjustmentBrush.stroke",p);XCTAssertEqual(status,200);XCTAssertTrue(s.document==expected);XCTAssertEqual(s.session.undoStack.count,1)
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"replace","kind":"blackWhite"]);XCTAssertEqual(status,200);XCTAssertEqual(s.currentAdjustmentBrushKind,.blackWhite)
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"invert"]);XCTAssertEqual(status,200)
      let native=EditorStore(document:s.document,actions:ActionLibrary(),brushes:BrushLibrary());defer{native.renderTask?.cancel()}
      native.updateMask(s.document.activeLayerID!){$0.density=0.6;$0.feather=2}
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"mask","density":0.6,"feather":2]);XCTAssertEqual(status,200);XCTAssertTrue(s.document==native.document)
      XCTAssertEqual((s.adjustmentBrushState["mask"] as? [String:Any])?["feather"] as? Double,2)
      let refined=s.document
      for parameters:[String:Any] in [["operation":"mask"],["operation":"mask","density":true],["operation":"mask","feather":101],["operation":"replace","density":0.5],["operation":"invert","kind":"exposure"]] {
        status=try await helper.edit(service,document,"adjustmentBrush.edit",parameters);XCTAssertEqual(status,400);XCTAssertTrue(s.document==refined)
      }
      status=try await helper.edit(service,document,"adjustmentBrush.configure",["overlay":true,"subtract":true]);XCTAssertEqual(status,200);XCTAssertTrue(s.adjustmentBrushOverlay)
      status=try await helper.edit(service,document,"adjustmentBrush.stroke",p,revision:"stale");XCTAssertEqual(status,409)
      let before=s.document
      status=try await helper.edit(service,document,"adjustmentBrush.stroke",["kind":"exposure","settings":["exposure":30],"points":[["x":2,"y":2]]]);XCTAssertEqual(status,400);XCTAssertTrue(s.document==before)
      s.tool = .adjustmentBrush;s.beginBrush(.init(x:12,y:12),zoom:1)
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"new"]);XCTAssertEqual(status,409);s.cancelBrush()
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:s.adjustmentBrushState))
    }
  }
  @MainActor func testHTTPObjectRevocationIsAtomic()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.store().document);s.objectDetector=TestObjectDetector();try service.share(document)
      let original=s.document
      let outside=try await helper.edit(service,document,"adjustmentBrush.object",["x":40,"y":4,"newLayer":true]);XCTAssertEqual(outside,422);XCTAssertTrue(s.document==original)
      var status=try await helper.edit(service,document,"adjustmentBrush.object",["x":4,"y":4,"newLayer":true,"kind":"exposure"]);XCTAssertEqual(status,200)
      let before=s.document;s.objectDetector=TestObjectDetector(delay:.milliseconds(60));let task=Task{try await helper.edit(service,document,"adjustmentBrush.object",["x":8,"y":4,"newLayer":true])}
      try await Task.sleep(for:.milliseconds(10));service.revoke(try XCTUnwrap(service.shares.first?.id));status=try await task.value;XCTAssertEqual(status,409);XCTAssertTrue(s.document==before)
    }
  }
  @MainActor func testRecordedLocalAdjustmentReplaysWithSemanticTargets()async throws {
    let s=try store();defer{s.renderTask?.cancel()};let original=s.document
    try s.session.startActionRecording(name:"Local light");s.beginBrush(.init(x:12,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value
    s.replaceAdjustmentBrush(.exposure);await s.geometryTask?.value
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot);XCTAssertEqual(action.steps.count,2);XCTAssertTrue(action.steps.allSatisfy{$0.operation.unsupportedReason==nil})
    let data=try ActionLibraryFile(actions:[action]).encoded(),decoded=try ActionLibraryFile.decode(data);XCTAssertEqual(decoded.version,3)
    var result=original;try decoded.actions[0].apply(to:&result);XCTAssertEqual(result.layers.count,2);XCTAssertEqual(result.layers.last!.mask,s.document.layers.last!.mask);XCTAssertEqual(result.layers.last!.content,s.document.layers.last!.content)
    var bad=decoded;bad.version=2;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONEncoder().encode(bad)))
  }
  @MainActor func testRecordedObjectCoverageReplaysWithoutDetection()async throws {
    let s=try store();defer{s.renderTask?.cancel()};let original=s.document
    try s.session.startActionRecording(name:"Object light");s.applyAdjustmentObject(at:.init(10,12));await s.geometryTask?.value
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot);XCTAssertEqual(action.steps.count,1)
    let saved=try ActionLibraryFile.decode(ActionLibraryFile(actions:[action]).encoded())
    var replay=original;try saved.actions[0].apply(to:&replay)
    XCTAssertEqual(replay.layers.last!.mask,s.document.layers.last!.mask);XCTAssertEqual(replay.layers.last!.content,s.document.layers.last!.content)
    XCTAssertEqual(try Renderer.composite(replay),try Renderer.composite(s.document))
  }
}
