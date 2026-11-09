import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private struct ColorVibranceBrushDetector:ObjectDetecting {
  var delay:Duration = .zero
  func mask(for image:Surface,at point:PathPoint)async throws->SelectionMask {
    if delay != .zero{try await Task.sleep(for:delay)}
    return try .make(.rectangle(.init(x:Int(point.x),y:0,width:8,height:image.height)),width:image.width,height:image.height,antiAlias:false)
  }
}
final class AdjustmentBrushColorVibranceTests:XCTestCase {
  func document(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:32,height:24,depth:depth)
    d.layers[0].content = .raster(try Surface(width:32,height:24,depth:depth,fill:Pixel(0.42,0.31,0.23)))
    return d
  }
  @MainActor func store(_ depth:PixelDepth = .u8)throws->EditorStore {
    let s=EditorStore(document:try document(depth),actions:ActionLibrary(),brushes:BrushLibrary())
    s.tool = .adjustmentBrush;s.adjustmentBrushKind = .colorVibrance;s.brush.size=8;s.brush.hardness=1;s.brushOptions.pressureSize=false
    s.objectDetector=ColorVibranceBrushDetector();return s
  }
  func value()->ModernAdjustment {
    var v=ModernAdjustment(.colorVibrance);v.values=["temperature":17,"tint":-23,"vibrance":31,"saturation":-19];v.seed=77;return v
  }
  @MainActor func testNativePickerLegacySelectionAndOrdinaryAdjustmentDefaults()throws {
    let s=try store();defer{s.renderTask?.cancel()}
    XCTAssertEqual(s.availableAdjustmentBrushKinds,AdjustmentBrushKind.nativeKinds)
    s.adjustmentBrushKind = .vibrance
    XCTAssertEqual(s.availableAdjustmentBrushKinds.last,.vibrance);XCTAssertEqual(s.currentAdjustmentBrushKind,.vibrance)
    XCTAssertEqual(s.availableAdjustmentBrushKinds.count,17)
    s.adjustmentBrushKind = .colorVibrance
    let view=NSHostingView(rootView:AdjustmentBrushOptionsView(store:s));view.frame = .init(x:0,y:0,width:1700,height:44);view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(view.fittingSize.width,400)
    XCTAssertEqual(AutomationCommand.definitions.count,271)
    let cap=AdjustmentBrushAPI.capabilities
    XCTAssertEqual(cap["nativeTypes"] as? [String],AdjustmentBrushKind.nativeKinds.map(\.rawValue))
    XCTAssertEqual((cap["types"] as? [[String:Any]])?.count,17)
    XCTAssertTrue(ModernAdjustment(.colorVibrance).isIdentity)
  }
  @MainActor func testNativePreviewCancelPropertiesRefineHistoryAndReopenAcrossDepths()async throws {
    for depth in PixelDepth.allCases {
      let s=try store(depth),original=s.document;defer{s.cancelBrush();s.renderTask?.cancel()}
      s.adjustmentBrushOverlay=true;s.beginBrush(.init(x:12,y:12),zoom:1)
      let request=try XCTUnwrap(s.brushGesture?.adjustmentRequest);var expected=original;try request.apply(to:&expected)
      await s.brushPreviewTask?.value;await s.renderTask?.value
      XCTAssertEqual(s.document,original);XCTAssertEqual(s.surface,try Renderer.composite(expected));XCTAssertNotNil(s.displayedMaskImage)
      s.cancelBrush();await s.renderTask?.value;XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
      s.beginBrush(.init(x:12,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value
      let id=try XCTUnwrap(s.adjustmentBrushLayer?.id),first=s.document
      XCTAssertEqual(s.currentAdjustmentBrushKind,.colorVibrance);XCTAssertEqual(s.activeLayer?.name,"Color and vibrance");XCTAssertEqual(s.session.undoStack.count,1)
      s.setModernAdjustment(id,value());await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(s.activeLayer?.content,.adjustment(.modern(value())))
      s.beginBrush(.init(x:23,y:12),zoom:1);XCTAssertEqual(s.brushGesture?.adjustmentRequest?.adjustment,.modern(value()))
      s.finishBrush();await s.geometryTask?.value
      XCTAssertEqual(s.activeLayer?.mask?.pixel(x:23,y:12).r,1)
      s.beginBrush(.init(x:12,y:12),zoom:1,alternate:true);s.finishBrush();await s.geometryTask?.value
      XCTAssertEqual(s.activeLayer?.mask?.pixel(x:12,y:12).r,0);let result=s.document
      XCTAssertEqual(result.layers[0],original.layers[0]);XCTAssertEqual(result.layers[1].content,.adjustment(.modern(value())))
      _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.activeLayer?.mask?.pixel(x:12,y:12).r,1)
      _=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document,result)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)),result)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(result))
      XCTAssertEqual(first.layers[1].content,.adjustment(AdjustmentBrushKind.colorVibrance.initial))
    }
  }
  @MainActor func testNativeObjectRefinementCancelAndRecordedCoverageAreAtomic()async throws {
    let s=try store(),source=s.document;defer{s.renderTask?.cancel()}
    try s.session.startActionRecording(name:"Local colour object")
    s.applyAdjustmentObject(at:.init(4,12));await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.activeLayer?.mask?.pixel(x:6,y:12).r,1);XCTAssertEqual(s.activeLayer?.mask?.pixel(x:20,y:12).r,0)
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot),data=try ActionLibraryFile(actions:[action]).encoded()
    let file=try ActionLibraryFile.decode(data);XCTAssertEqual(file.version,61)
    var replay=source;try file.actions[0].apply(to:&replay)
    XCTAssertEqual(replay.layers.last?.content,s.activeLayer?.content);XCTAssertEqual(replay.layers.last?.mask,s.activeLayer?.mask)
    let before=s.document;s.objectDetector=ColorVibranceBrushDetector(delay:.milliseconds(60));s.newAdjustmentBrush();s.applyAdjustmentObject(at:.init(16,12))
    s.geometryTask?.cancel();await s.geometryTask?.value;XCTAssertEqual(s.document,before)
  }
  @MainActor func testRecordedStrokesRequire61RetainControlsAndOldRecipesRemainReadable()async throws {
    let s=try store(),source=s.document;defer{s.renderTask?.cancel()}
    try s.session.startActionRecording(name:"Local colour strokes")
    s.beginBrush(.init(x:12,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value
    let id=try XCTUnwrap(s.activeLayer?.id);s.setModernAdjustment(id,value());await s.geometryTask?.value
    s.beginBrush(.init(x:23,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot),data=try ActionLibraryFile(actions:[action]).encoded(),file=try ActionLibraryFile.decode(data)
    XCTAssertEqual(file.version,61);XCTAssertEqual(file.actions[0].steps.count,3)
    var old=file;old.version=60;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONEncoder().encode(old)))
    var replay=source;try file.actions[0].apply(to:&replay)
    XCTAssertEqual(replay.layers.last?.mask,s.activeLayer?.mask);XCTAssertEqual(replay.layers.last?.content,s.activeLayer?.content)
    XCTAssertEqual(try Renderer.composite(replay),try Renderer.composite(s.document))
    let legacy=try store();defer{legacy.renderTask?.cancel()};legacy.adjustmentBrushKind = .vibrance
    try legacy.session.startActionRecording(name:"Legacy colour");legacy.beginBrush(.init(x:12,y:12),zoom:1);legacy.finishBrush();await legacy.geometryTask?.value
    let legacyAction=try XCTUnwrap(legacy.session.actionRecording?.snapshot)
    XCTAssertEqual(try ActionLibraryFile.decode(ActionLibraryFile(actions:[legacyAction]).encoded()).version,3)
  }
  func testStrictPartialSettingsRetainAllControlsAndSeed()throws {
    let base=Adjustment.modern(value())
    let next=try AdjustmentBrushAPI.decode(.object(["tint":.number(12)]),kind:.colorVibrance,base:base)
    var expected=value();expected.values["tint"]=12;XCTAssertEqual(next,.modern(expected))
    for bad:[String:AutomationValue] in [["tint":.bool(true)],["tint":.number(101)],["values":.object([:])],["seed":.number(2)],["useLegacy":.bool(true)],["whiteBalance":.string("Auto")]] {
      XCTAssertThrowsError(try AdjustmentBrushAPI.decode(.object(bad),kind:.colorVibrance,base:base))
    }
    let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:AdjustmentBrushAPI.settings(base)))
    XCTAssertNoThrow(try BrushAPI.merge(raw,schema:AdjustmentBrushAPI.settingsSchema(.colorVibrance)))
  }
  @MainActor func testHTTPPaintPartialEditObjectAndArchiveMatchNative()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.document());s.objectDetector=ColorVibranceBrushDetector();try service.share(document)
      let original=s.document,id=UUID(),p:[String:Any]=["kind":"colorVibrance","newLayer":true,"newLayerID":id.uuidString,"settings":["temperature":17,"tint":-23,"vibrance":31,"saturation":-19],"points":[["x":12,"y":12]],"brush":["size":8,"hardness":1,"settings":["pressureSize":false]]]
      let command=try AutomationCommand(data:JSONSerialization.data(withJSONObject:["command":"adjustmentBrush.stroke","revision":"preview","parameters":p]))
      let request=try command.adjustmentBrushRequest(store:s);var expected=original;try request.apply(to:&expected)
      var status=try await helper.edit(service,document,"adjustmentBrush.stroke",p);XCTAssertEqual(status,200);XCTAssertEqual(s.document,expected)
      let mask=s.activeLayer?.mask
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"replace","settings":["tint":12]])
      XCTAssertEqual(status,200);XCTAssertEqual(s.activeLayer?.mask,mask)
      guard case .adjustment(.modern(let value))=s.activeLayer?.content else{return XCTFail()}
      XCTAssertEqual(value.values,["temperature":17,"tint":12,"vibrance":31,"saturation":-19])
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.adjustmentBrushState))
      XCTAssertNoThrow(try BrushAPI.merge(state,schema:AdjustmentBrushLookupAPI.stateSchema))
      status=try await helper.edit(service,document,"adjustmentBrush.object",["kind":"colorVibrance","newLayer":true,"x":4,"y":12])
      XCTAssertEqual(status,200);XCTAssertEqual(s.activeLayer?.mask?.pixel(x:6,y:12).r,1);XCTAssertEqual(s.activeLayer?.content,.adjustment(AdjustmentBrushKind.colorVibrance.initial))
      let result=s.document;XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(result)),result)
      status=try await helper.edit(service,document,"history.undo");XCTAssertEqual(status,200);XCTAssertEqual(s.document.layers.count,2)
      status=try await helper.edit(service,document,"history.redo");XCTAssertEqual(status,200);XCTAssertEqual(s.document,result)
    }
  }
  @MainActor func testHTTPInvalidBusyStaleAndRevokedObjectPreserveDocument()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.document());try service.share(document);let source=s.document
      let p:[String:Any]=["kind":"colorVibrance","newLayer":true,"points":[["x":12,"y":12]]]
      for bad:[String:Any] in [["vibrance":101],["tint":true],["seed":3],["temperature":"hot"]] {
        var invalid=p;invalid["settings"]=bad;let status=try await helper.edit(service,document,"adjustmentBrush.stroke",invalid)
        XCTAssertEqual(status,400);XCTAssertEqual(s.document,source)
      }
      var status=try await helper.edit(service,document,"adjustmentBrush.stroke",p,revision:"stale");XCTAssertEqual(status,409)
      s.geometryBusy=true;status=try await helper.edit(service,document,"adjustmentBrush.stroke",p);XCTAssertEqual(status,409);s.geometryBusy=false
      s.objectDetector=ColorVibranceBrushDetector(delay:.milliseconds(80))
      let task=Task{try await helper.edit(service,document,"adjustmentBrush.object",["kind":"colorVibrance","newLayer":true,"x":4,"y":12])}
      try await Task.sleep(for:.milliseconds(10));service.revoke(try XCTUnwrap(service.shares.first?.id));status=try await task.value
      XCTAssertEqual(status,409);XCTAssertEqual(s.document,source)
    }
  }
}
