import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private struct LookupBrushObjectDetector:ObjectDetecting {
  var delay:Duration = .zero
  func mask(for image:Surface,at point:PathPoint)async throws->SelectionMask {
    if delay != .zero{try await Task.sleep(for:delay)}
    return try .make(.rectangle(.init(x:Int(point.x),y:0,width:8,height:image.height)),width:image.width,height:image.height,antiAlias:false)
  }
}
final class AdjustmentBrushLookupTests:XCTestCase {
  func document(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:32,height:24,depth:depth);d.layers[0].content = .raster(try Surface(width:32,height:24,depth:depth,fill:Pixel(0.25,0.5,0.75)));return d
  }
  func brush()->Brush {
    var b=Brush();b.size=8;b.hardness=1;b.settings = .init();b.settings!.pressureSize=false;return b
  }
  func lookup()throws->(Data,ColorLookupAdjustment){try ColorLookupWorkflowTests().fixture()}
  @MainActor func store(_ document:CraftDocument)throws->EditorStore {
    let s=EditorStore(document:document,actions:ActionLibrary(),brushes:BrushLibrary());s.tool = .adjustmentBrush;s.adjustmentBrushKind = .colorLookup;s.brush=brush();return s
  }
  func testCoreLUTPaintingIsLocalAndPreservesSamplesHistoryAndArchiveAcrossDepths()throws {
    let value=try lookup().1
    for depth in PixelDepth.allCases{
      let original=try document(depth);var session=EditorSession(document:original)
      let request=AdjustmentBrushRequest(adjustment:.colorLookup(value),points:[.init(x:12,y:12)],brush:brush())
      try session.execute(.adjustmentBrush(request));let result=session.document,render=try Renderer.composite(result),base=try Renderer.composite(original)
      XCTAssertEqual(result.layers[0],original.layers[0]);XCTAssertEqual(result.layers[1].content,.adjustment(.colorLookup(value)))
      XCTAssertEqual(result.layers[1].mask?.pixel(x:12,y:12).r,1);XCTAssertEqual(result.layers[1].mask?.pixel(x:0,y:0).r,0)
      XCTAssertNotEqual(render.pixel(x:12,y:12),base.pixel(x:12,y:12));XCTAssertEqual(render.pixel(x:0,y:0),base.pixel(x:0,y:0))
      XCTAssertEqual(result.minimumArchiveVersion,18);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
      try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,result)
    }
  }
  func testExistingLookupMaskSelectionAndInvalidLUTAreAtomic()throws {
    var original=try document();let value=try lookup().1
    var layer=try value.layer(in:original);layer.mask=try Surface(width:32,height:24,fill:.black);layer.maskProperties = .init();layer.maskProperties!.density=0.75;layer.maskProperties!.feather=1
    original.layers.append(layer);original.activeLayerID=layer.id;original.selection = .init(x:10,y:0,width:8,height:24)
    var request=AdjustmentBrushRequest(layerID:layer.id,adjustment:.colorLookup(value),points:[.init(x:8,y:12),.init(x:14,y:12)],brush:brush()),d=original
    try request.apply(to:&d);XCTAssertEqual(d.layers.last?.effectiveMaskProperties,layer.effectiveMaskProperties);XCTAssertEqual(d.layers.last?.mask?.pixel(x:8,y:12).r,0);XCTAssertEqual(d.layers.last?.mask?.pixel(x:14,y:12).r,1)
    let before=d;var bad=value;bad.lut!.values[0] = .nan;request.adjustment = .colorLookup(bad)
    XCTAssertThrowsError(try request.apply(to:&d));XCTAssertEqual(d,before)
    d=original;d.layers[1].locked=true;let locked=d;request.adjustment = .colorLookup(value);XCTAssertThrowsError(try request.apply(to:&d));XCTAssertEqual(d,locked)
  }
  @MainActor func testNativeIdentityCreationPropertiesPreviewCancelAndHistory()async throws {
    for depth in PixelDepth.allCases{
      let original=try document(depth),s=try store(original);defer{s.cancelBrush();s.renderTask?.cancel()}
      s.beginBrush(.init(x:12,y:12),zoom:1);await s.brushPreviewTask?.value;s.cancelBrush();XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
      s.beginBrush(.init(x:12,y:12),zoom:1);s.finishBrush();await s.geometryTask?.value
      let id=try XCTUnwrap(s.adjustmentBrushLayer?.id);XCTAssertEqual(s.currentAdjustmentBrushKind,.colorLookup);XCTAssertEqual(s.activeLayer?.name,"Color Lookup")
      let value=try lookup().1;s.setColorLookup(id,value);await s.geometryTask?.value;XCTAssertNil(s.error);let result=s.document
      s.beginBrush(.init(x:23,y:12),zoom:1);let preview=try XCTUnwrap(s.brushGesture?.adjustmentRequest);XCTAssertEqual(preview.adjustment,.colorLookup(value))
      await s.brushPreviewTask?.value;await s.renderTask?.value;var expected=result;try preview.apply(to:&expected);XCTAssertEqual(s.surface,try Renderer.composite(expected));s.cancelBrush();XCTAssertEqual(s.document,result)
      s.beginBrush(.init(x:12,y:12),zoom:1,alternate:true);s.finishBrush();await s.geometryTask?.value;XCTAssertEqual(s.document.layers.last?.mask?.pixel(x:12,y:12).r,0)
      _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,result);_=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document.layers.last?.content,.adjustment(.colorLookup(value)))
      let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.adjustmentBrushState));XCTAssertNoThrow(try BrushAPI.merge(raw,schema:AdjustmentBrushLookupAPI.stateSchema))
    }
  }
  @MainActor func testNativeLookupObjectMaskAndRetypeRetainEditableData()async throws {
    var original=try document();let value=try lookup().1;var layer=try value.layer(in:original);layer.mask=try Surface(width:32,height:24,fill:.black);original.layers.append(layer);original.activeLayerID=layer.id
    let s=try store(original);defer{s.renderTask?.cancel()};s.adjustmentBrushNewLayer=false;s.objectDetector=LookupBrushObjectDetector()
    s.applyAdjustmentObject(at:.init(4,12));await s.geometryTask?.value;XCTAssertNil(s.error)
    XCTAssertEqual(s.document.layers.last?.mask?.pixel(x:6,y:12).r,1);XCTAssertEqual(s.document.layers.last?.mask?.pixel(x:20,y:12).r,0);XCTAssertEqual(s.document.layers.last?.content,.adjustment(.colorLookup(value)))
    let mask=s.document.layers.last?.mask;s.replaceAdjustmentBrush(.exposure);await s.geometryTask?.value;s.replaceAdjustmentBrush(.colorLookup);await s.geometryTask?.value
    XCTAssertEqual(s.document.layers.last?.mask,mask);XCTAssertEqual(s.document.layers.last?.content,.adjustment(.colorLookup(.photoshopDefault)))
    let host=NSHostingView(rootView:ColorLookupEditor(store:s,layerID:layer.id));host.frame = .init(x:0,y:0,width:300,height:500);host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.width,320)
  }
  @MainActor func testPortableColorLookupBrushRequires59AndReplaysEmbeddedSource()async throws {
    let original=try document(),value=try lookup().1;var session=EditorSession(document:original)
    try session.startActionRecording(name:"Local LUT")
    try session.execute(.adjustmentBrush(.init(adjustment:.colorLookup(value),points:[.init(x:12,y:12)],brush:brush())))
    let action=try XCTUnwrap(session.actionRecording?.snapshot);XCTAssertEqual(action.steps.count,1);let file=try ActionLibraryFile.decode(ActionLibraryFile(actions:[action]).encoded());XCTAssertEqual(file.version,59)
    var result=original;try file.actions[0].apply(to:&result);XCTAssertEqual(result.layers.last?.content,session.document.layers.last?.content);XCTAssertEqual(result.layers.last?.mask,session.document.layers.last?.mask)
    for version in [3,18,58]{var bad=file;bad.version=version;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONEncoder().encode(bad)))}
    var legacy=action
    if case .adjustmentBrush(var recorded)=legacy.steps[0].operation{recorded.request.adjustment = .invert;legacy.steps[0].operation = .adjustmentBrush(recorded)}
    XCTAssertEqual(try ActionLibraryFile.decode(ActionLibraryFile(actions:[legacy]).encoded()).version,3)
  }
  @MainActor func testHTTPUploadedLookupStrokeMatchesNativeAndSurvivesCacheClear()async throws {
    let helper=AutomationTests(),(bytes,value)=try lookup()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.document();document.store.session=EditorSession(document:original);document.store.brush=self.brush();try service.share(document);service.setDocumentTransfersEnabled(true)
      let upload=try await ColorLookupWorkflowTests().raw(service,path:"/v1/luts",data:bytes);XCTAssertEqual(upload.0.statusCode,201);let body=try XCTUnwrap(JSONSerialization.jsonObject(with:upload.1) as? [String:Any]),lutID=try XCTUnwrap(body["lutID"] as? String),newID=UUID()
      let parameters:[String:Any]=["kind":"colorLookup","newLayer":true,"newLayerID":newID.uuidString,"settings":["lutID":lutID,"dither":false],"points":[["x":12,"y":12]]]
      let code=try await helper.edit(service,document,"adjustmentBrush.stroke",parameters);XCTAssertEqual(code,200)
      var expected=original;try AdjustmentBrushRequest(newLayerID:newID,adjustment:.colorLookup(value),points:[.init(x:12,y:12)],brush:self.brush()).apply(to:&expected)
      XCTAssertEqual(document.store.document,expected);let share=try XCTUnwrap(service.shares.first?.id)
      let download=try await helper.request(service,path:"/v1/documents/\(share)/layers/\(newID)/lut");XCTAssertEqual(download.0.statusCode,200);XCTAssertEqual(download.1,bytes)
      service.setDocumentTransfersEnabled(false);XCTAssertTrue(service.luts.isEmpty)
      var status=try await helper.edit(service,document,"adjustmentBrush.stroke",["points":[["x":23,"y":12]]]);XCTAssertEqual(status,200)
      XCTAssertEqual(document.store.document.layers.last?.content,.adjustment(.colorLookup(value)))
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"replace","settings":["interpolation":"tetrahedral"]]);XCTAssertEqual(status,200)
      var changed=value;changed.interpolation = .tetrahedral;XCTAssertEqual(document.store.activeLayer?.content,.adjustment(.colorLookup(changed)))
      status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"replace","settings":["clearLUT":true]]);XCTAssertEqual(status,200)
      if case .adjustment(.colorLookup(let actual))=document.store.activeLayer?.content{XCTAssertNil(actual.lut);XCTAssertEqual(actual.interpolation,.tetrahedral)}else{XCTFail("Missing lookup")}
      _=await document.store.requestHistory(redo:false).value;XCTAssertEqual(document.store.activeLayer?.content,.adjustment(.colorLookup(changed)))
    }
  }
  @MainActor func testHTTPPresetObjectAndReplaceMatchSharedNativePreparation()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.document();let s=document.store;s.session=EditorSession(document:original);s.brush=self.brush();s.objectDetector=LookupBrushObjectDetector();try service.share(document)
      let code=try await helper.edit(service,document,"adjustmentBrush.object",["kind":"colorLookup","newLayer":true,"x":4,"y":12,"settings":["preset":"warm","dither":false]])
      XCTAssertEqual(code,200);let value=ColorLookupAdjustment(lut:try ColorLUTPreset.warm.makeLUT(),dither:false)
      XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(value)));XCTAssertEqual(s.activeLayer?.mask?.pixel(x:6,y:12).r,1);XCTAssertEqual(s.activeLayer?.mask?.pixel(x:20,y:12).r,0)
      let mask=s.activeLayer?.mask
      let status=try await helper.edit(service,document,"adjustmentBrush.edit",["operation":"replace","settings":["preset":"cool"]]);XCTAssertEqual(status,200);XCTAssertEqual(s.activeLayer?.mask,mask)
      XCTAssertEqual(s.activeLayer?.content,.adjustment(.colorLookup(.init(lut:try ColorLUTPreset.cool.makeLUT(),dither:false))))
      let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.adjustmentBrushState));XCTAssertNoThrow(try BrushAPI.merge(raw,schema:AdjustmentBrushLookupAPI.stateSchema));XCTAssertEqual(AutomationCommand.definitions.count,267)
    }
  }
  @MainActor func testHTTPInvalidReferencesStrictSettingsBusyStaleAndRevocationAreAtomic()async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}){service,document in
      let original=try self.document();let s=document.store;s.session=EditorSession(document:original);s.brush=self.brush();try service.share(document)
      for settings:[String:Any] in [["lutID":true],["lutID":NSNull()],["preset":"unknown"],["preset":"warm","lutID":UUID().uuidString],["preset":"warm","clearLUT":true],["data":"injected"],["lut":[]]]{
        let status=try await helper.edit(service,document,"adjustmentBrush.stroke",["kind":"colorLookup","settings":settings,"points":[["x":12,"y":12]]]);XCTAssertEqual(status,400);XCTAssertEqual(s.document,original)
      }
      var status=try await helper.edit(service,document,"adjustmentBrush.stroke",["kind":"colorLookup","settings":["lutID":UUID().uuidString],"points":[["x":12,"y":12]]]);XCTAssertEqual(status,404);XCTAssertEqual(s.document,original)
      let params:[String:Any]=["kind":"colorLookup","settings":["preset":"warm"],"points":[["x":12,"y":12]]]
      status=try await helper.edit(service,document,"adjustmentBrush.stroke",params,revision:"stale");XCTAssertEqual(status,409)
      s.geometryBusy=true;status=try await helper.edit(service,document,"adjustmentBrush.stroke",params);XCTAssertEqual(status,409);s.geometryBusy=false
      s.objectDetector=LookupBrushObjectDetector(delay:.milliseconds(80))
      let task=Task{try await helper.edit(service,document,"adjustmentBrush.object",["kind":"colorLookup","newLayer":true,"x":4,"y":12,"settings":["preset":"warm"]])}
      for _ in 0..<300 where !s.geometryBusy{try await Task.sleep(for:.milliseconds(1))};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id));status=try await task.value;XCTAssertEqual(status,409);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
}
