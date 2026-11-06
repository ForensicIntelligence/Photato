import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
import PhotoCraftCore
import PhotoCraftImaging

final class LightEditingPreviewWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:128,height:96,depth:depth)
    d.layers[0].content = .raster(try Surface(width:128,height:96,depth:depth,fill:Pixel(0.25,0.5,0.75)))
    var light=ModernAdjustment(.light);light.values["shadows"]=35;d.layers.append(try light.layer(in:d));d.activeLayerID=d.layers[0].id
    return d
  }
  @MainActor func testNativeBrushPencilEraserAndMaskPreviewCancelCommitUndoRestoreLight()async throws {
    for tool in [EditorTool.brush,.pencil,.eraser] {for mask in [false,true] {
      var d=try fixture();if mask{d.layers[0].mask=try Surface(width:d.width,height:d.height,fill:.white)}
      let store=EditorStore(document:d,brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()}
      store.select(d.layers[0].id);store.tool=tool;store.brush.size=10
      if mask{store.maskEditingLayerID=d.layers[0].id}
      store.beginBrush(.init(x:20,y:30,time:0),zoom:1);store.extendBrush(.init(x:70,y:45,time:16))
      let gesture=try XCTUnwrap(store.brushGesture);XCTAssertEqual(store.lightEditingPreview.pausedLayerIDs,[d.layers[1].id])
      await store.brushPreviewTask?.value;await store.renderTask?.value
      XCTAssertNil(store.error);if case .adjustment(.modern(let paused))=try XCTUnwrap(store.renderSnapshot).document.layers[1].content{XCTAssertTrue(paused.isIdentity)}else{XCTFail("Missing paused Light")}
      XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
      var expected=d
      if let request=gesture.paintingRequest{expected=try PaintingPreparation.prepare(request,in:d).result}
      else{try gesture.command.apply(to:&expected)}
      store.finishBrush();await store.geometryTask?.value;await store.renderTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertTrue(store.lightEditingPreview.pausedLayerIDs.isEmpty)
      XCTAssertEqual(store.surface,try Renderer.composite(expected));XCTAssertEqual(store.session.undoStack.count,expected == d ? 0:1)
      await store.undo();await store.renderTask?.value;XCTAssertEqual(store.document,d)
      store.beginBrush(.init(x:30,y:40,time:0),zoom:1);await store.brushPreviewTask?.value;store.cancelBrush();await store.renderTask?.value
      XCTAssertEqual(store.document,d);XCTAssertTrue(store.lightEditingPreview.pausedLayerIDs.isEmpty);XCTAssertEqual(store.surface,try Renderer.composite(d))
    }}
  }
  @MainActor func testNativeRetouchToolsKeepOriginalSamplingFinalPixelsAndCancel()async throws {
    for tool in [EditorTool.cloneStamp,.dodge,.burn,.sponge,.blur,.sharpen,.smudge,.healingBrush,.spotHealing] {
      var d=try fixture();var pixels=try Surface(width:d.width,height:d.height)
      pixels.mapPixels {x,y,_ in Pixel(Float((x/4+y/4)%2)*0.6+0.2,Float(y)/96,Float(x)/128)}
      d.layers[0].content = .raster(pixels)
      let sources=CloneSources();sources.showOverlay=false
      let store=EditorStore(document:d,cloneState:sources,actions:ActionLibrary());defer{store.cancelClone();store.renderTask?.cancel()}
      store.select(d.layers[0].id);store.tool=tool;store.retouchSettings.brush.size=6;store.retouchSettings.focus.protectDetail=false
      store.setCloneSource(at:.init(20,20));await store.renderTask?.value
      store.beginClone(.init(x:60,y:55));await store.clonePrepareTask?.value
      store.extendClone(.init(x:80,y:60));await store.retouchPreviewTask?.value;await store.renderTask?.value
      XCTAssertEqual(store.lightEditingPreview.pausedLayerIDs,[d.layers[1].id],"\(tool)")
      XCTAssertEqual(LightPreviewAPI.state(store)["phase"]as?String,"retouching")
      XCTAssertNil(store.error);if case .adjustment(.modern(let paused))=try XCTUnwrap(store.renderSnapshot).document.layers[1].content{XCTAssertTrue(paused.isIdentity)}else{XCTFail("Missing paused Light")}
      var expected=d;try XCTUnwrap(store.cloneDraft?.command).apply(to:&expected)
      store.finishClone();await store.geometryTask?.value;await store.renderTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.document,expected,"\(tool)");XCTAssertEqual(store.document.layers[1],d.layers[1])
      XCTAssertEqual(store.surface,try Renderer.composite(expected));XCTAssertTrue(store.lightEditingPreview.pausedLayerIDs.isEmpty)
      if expected != d{await store.undo();await store.renderTask?.value;XCTAssertEqual(store.document,d)}
      store.beginClone(.init(x:60,y:55));await store.clonePrepareTask?.value;await store.retouchPreviewTask?.value
      store.cancelClone();await store.renderTask?.value
      XCTAssertEqual(store.document,d);XCTAssertTrue(store.lightEditingPreview.pausedLayerIDs.isEmpty)
    }
  }
  @MainActor func testStaleReplacedAndSelectionGestureNeverSuppressSavedLight()async throws {
    let d=try fixture(),store=EditorStore(document:d,brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()}
    store.select(d.layers[0].id);store.tool = .brush;store.beginBrush(.init(x:20,y:20),zoom:1)
    let worker=store.renderTask;store.session=EditorSession(document:d);await worker?.value;await store.renderTask?.value
    XCTAssertTrue(store.lightEditingPreview.pausedLayerIDs.isEmpty);XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.cancelBrush();store.tool = .selectionBrush;store.beginBrush(.init(x:30,y:30),zoom:1)
    XCTAssertTrue(store.lightEditingPreview.pausedLayerIDs.isEmpty);store.cancelBrush();await store.renderTask?.value
    XCTAssertEqual(store.document.layers[1],d.layers[1])
  }
  @MainActor func testHTTPReadonlyStateSchemaAndBusyCommandsMatchNativePreview()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture();document.store.session=EditorSession(document:d);document.store.select(d.layers[0].id);try service.share(document)
      let share=try XCTUnwrap(service.shares.first?.id),store=document.store
      store.tool = .brush;store.beginBrush(.init(x:20,y:20),zoom:1);defer{store.cancelBrush();store.renderTask?.cancel()}
      await store.brushPreviewTask?.value;await store.renderTask?.value
      let revision=service.revision(store)
      let response=try await h.request(service,path:"/v1/documents/\(share)");XCTAssertEqual(response.0.statusCode,200)
      let json=try XCTUnwrap(try JSONSerialization.jsonObject(with:response.1)as?[String:Any]),state=try XCTUnwrap(json["lightPreview"]as?[String:Any])
      XCTAssertEqual(state["paused"]as?Bool,true);XCTAssertEqual(state["pausedLayerIDs"]as?[String],[d.layers[1].id.uuidString]);XCTAssertEqual(state["phase"]as?String,"painting")
      let busy=try await h.edit(service,document,"adjustment.set",["layerID":d.layers[1].id.uuidString,"adjustment":ModernAdjustment(.light).apiObject]);XCTAssertEqual(busy,409)
      XCTAssertEqual(service.revision(store),revision);XCTAssertEqual(store.document,d);store.cancelBrush();await store.renderTask?.value
      XCTAssertEqual(LightPreviewAPI.state(store)["paused"]as?Bool,false);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LightPreviewAPI.stateSchema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ModernAdjustment.apiCapabilities))
      XCTAssertEqual(AutomationCommand.definitions.count,252);XCTAssertEqual(ActionLibraryFile.maximumVersion,50)
    }
  }
  @MainActor func testNativePauseNoticeFitsTheDocumentTabWithoutHitTesting()throws {
    let view=NSHostingView(rootView:LightPreviewNotice(count:2));view.frame=NSRect(x:0,y:0,width:360,height:24);view.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(view.fittingSize.height,29);XCTAssertLessThan(view.fittingSize.width,360)
  }
}
