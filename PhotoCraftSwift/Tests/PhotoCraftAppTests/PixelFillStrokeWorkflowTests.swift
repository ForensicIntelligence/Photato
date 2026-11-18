import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class PixelPaintGate:@unchecked Sendable{let condition=NSCondition();var ready=false;func wait(){condition.lock();while !ready{condition.wait()};condition.unlock()};func release(){condition.lock();ready=true;condition.broadcast();condition.unlock()}}
final class PixelFillStrokeWorkflowTests:XCTestCase{
  @MainActor func testNativeEditClearModeDisablesPreserveAndHandlesUnavailableTarget() throws {
    _ = NSApplication.shared
    for kind in PixelPaintKind.allCases {
      var settings = PixelPaintSettings()
      settings.preserveTransparency = true
      let controls = PixelPaintAccessory(kind: kind, settings: settings, scalar: false, allowClear: true)
      XCTAssertEqual(controls.mode.item(withTitle: "Clear")?.isEnabled, true)
      controls.mode.selectItem(withTitle: "Clear")
      controls.modeChanged()
      XCTAssertFalse(controls.preserve.isEnabled)
      XCTAssertEqual(controls.preserve.state, .off)
      XCTAssertEqual(try controls.settings().clearsAlpha, true)
      XCTAssertFalse(try controls.settings().preserveTransparency)
      controls.mode.selectItem(withTitle: "Multiply")
      controls.modeChanged()
      XCTAssertTrue(controls.preserve.isEnabled)
      XCTAssertTrue(try controls.settings().preserveTransparency)
      XCTAssertNil(try controls.settings().clearsAlpha)
      let remembered = try PixelPaintAccessory(kind: kind, settings: controls.settings(), scalar: true, allowClear: true)
      XCTAssertEqual(remembered.mode.item(withTitle: "Clear")?.isEnabled, false)
      let unavailable = PixelPaintAccessory(kind: kind, settings: try {
        var value = try controls.settings()
        value.clearsAlpha = true
        value.preserveTransparency = false
        return value
      }(), scalar: false)
      XCTAssertEqual(unavailable.mode.titleOfSelectedItem, "Normal")
      XCTAssertEqual(unavailable.mode.item(withTitle: "Clear")?.isEnabled, false)
    }
  }

  @MainActor func testNativeEditClearRecordsPortableSolidAndPatternActions66() async throws {
    let source = try fixture(.u16), store = EditorStore(document: source)
    defer { store.renderTask?.cancel(); store.geometryTask?.cancel() }
    var settings = PixelPaintSettings(color: .clear)
    settings.clearsAlpha = true
    settings.location = .outside
    settings.width = 2
    let pattern = try RasterPattern(name: "Quarter alpha",
      surface: Surface(width: 1, height: 1, depth: .u16, fill: Pixel(0, 0, 0, 0.25)), id: "action-clear-pattern")
    try store.session.startActionRecording(name: "Edit Clear")
    store.applyPixelPaint(.fill, settings: settings, pattern: pattern)
    await store.geometryTask?.value
    let filled = store.document
    store.applyPixelPaint(.stroke, settings: settings)
    await store.geometryTask?.value
    XCTAssertNil(store.error)
    XCTAssertEqual(store.session.undoStack.count, 2)
    let edited = store.document
    var file = ActionLibraryFile()
    file.actions = [try XCTUnwrap(store.session.actionRecording?.snapshot)]
    let bytes = try file.encoded(), decoded = try ActionLibraryFile.decode(bytes)
    XCTAssertEqual(decoded.version, 66)
    var downgraded = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    downgraded["version"] = 65
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: downgraded)))
    var replay = try fixture(.u16)
    XCTAssertNotEqual(replay.layers[0].id, source.layers[0].id)
    try decoded.actions[0].apply(to: &replay)
    XCTAssertEqual(replay.layers[0].content, edited.layers[0].content)
    XCTAssertEqual(replay.selection, edited.selection)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, filled)
    _ = await store.requestHistory(redo: false).value
    XCTAssertEqual(store.document, source)
    _ = await store.requestHistory(redo: true).value
    XCTAssertEqual(store.document, filled)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edited)), edited)
  }

  @MainActor func testHTTPEditClearWithoutColorUsesNativeBytesAndRejectsIncompatibleRequests() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, file in
      let source = try self.fixture(), store = file.store, id = source.layers[0].id
      store.session = EditorSession(document: source)
      try service.share(file)
      XCTAssertEqual(store.pixelPaintState["canClear"] as? Bool, true)
      let parameters: [String: Any] = ["layerID": id.uuidString, "mode": "Clear", "width": 2, "location": "Outside"]
      var expected = source, settings = PixelPaintSettings(color: .clear)
      settings.clearsAlpha = true
      settings.width = 2
      settings.location = .outside
      try PixelFillStroke.apply(.init(.stroke, target: .layer(id), settings: settings), to: &expected)
      let strokeStatus = try await helper.edit(service, file, "pixels.stroke", parameters)
      XCTAssertEqual(strokeStatus, 200)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual((store.pixelPaintState["strokeSettings"] as? [String: Any])?["mode"] as? String, "Clear")
      let errors: [([String: Any], Int)] = [
        (["mode": "Normal", "width": 2], 400),
        (["mode": "Clear", "width": 2, "preserveTransparency": true], 400),
        (["mode": "Clear", "width": 2, "mask": true], 422),
      ]
      for (arguments, code) in errors {
        let status = try await helper.edit(service, file, "pixels.stroke", ["layerID": id.uuidString].merging(arguments) { _, new in new })
        XCTAssertEqual(status, code)
        XCTAssertEqual(store.document, expected)
      }
      let fillStatus = try await helper.edit(service, file, "pixels.fill", ["layerID": id.uuidString, "mode": "Clear"])
      XCTAssertEqual(fillStatus, 200)
      try PixelFillStroke.apply(.init(.fill, target: .layer(id), settings: settings), to: &expected)
      XCTAssertEqual(try NativeArchive.encodeChunked(store.document), try NativeArchive.encodeChunked(expected))
    }
  }

  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument{var d=try CraftDocument(width:20,height:16,depth:depth);d.layers[0].content = .raster(try Surface(width:20,height:16,depth:depth,fill:Pixel(0.2,0.4,0.6,0.5)));d.layers[0].mask=try Surface(width:20,height:16,depth:depth,fill:.white);d.alphaChannels=[AlphaChannel(name:"Alpha",pixels:try Surface(width:20,height:16,depth:depth,fill:Pixel(0.4,0.4,0.4)))];d.selection = .init(x:5,y:4,width:7,height:6);return d}
  @MainActor func testNativeControlsOpacitySliderContentsStrokeOptionsAndValidation()throws{
    _=NSApplication.shared;let fill=PixelPaintAccessory(kind:.fill,settings:.init(color:.white),scalar:false,background:.black,allowContentAware:true);XCTAssertEqual(fill.contents.numberOfItems,8);fill.opacitySlider.doubleValue=25;fill.sliderChanged();XCTAssertEqual(try fill.settings().opacity,0.25);fill.opacity.stringValue="37";fill.fieldChanged();XCTAssertEqual(fill.opacitySlider.doubleValue,37);fill.contents.selectItem(withTitle:"Black");fill.contentsChanged();XCTAssertEqual(try fill.settings().color,.black);let stroke=PixelPaintAccessory(kind:.stroke,settings:.init(color:.black),scalar:false);stroke.width.stringValue="12";stroke.location.selectItem(withTitle:"Outside");stroke.mode.selectItem(withTitle:"Multiply");stroke.preserve.state = .on;let value=try stroke.settings();XCTAssertEqual(value.width,12);XCTAssertEqual(value.location,.outside);XCTAssertEqual(value.mode,.multiply);XCTAssertTrue(value.preserveTransparency);stroke.width.stringValue="251";XCTAssertThrowsError(try stroke.settings());let scalar=PixelPaintAccessory(kind:.stroke,settings:.init(),scalar:true);XCTAssertFalse(scalar.preserve.isEnabled)
  }
  @MainActor func testNativeFillStrokeUndoActions41VersionGuardAndArchive()async throws{
    let source=try fixture(),s=EditorStore(document:source);defer{s.renderTask?.cancel();s.geometryTask?.cancel()};try s.session.startActionRecording(name:"Fill and Stroke");var settings=PixelPaintSettings(color:.white);settings.opacity=0.5;s.applyPixelPaint(.fill,settings:settings);await s.geometryTask?.value;XCTAssertNil(s.error);var expected=source;try Command.pixelPaint(.init(.fill,target:.layer(source.layers[0].id),settings:settings)).apply(to:&expected);XCTAssertEqual(s.document,expected);s.applyPixelPaint(.stroke,settings:settings);await s.geometryTask?.value;XCTAssertEqual(s.session.undoStack.count,2);var file=ActionLibraryFile();file.actions=[try XCTUnwrap(s.session.actionRecording?.snapshot)];let bytes=try file.encoded();XCTAssertEqual(try ActionLibraryFile.decode(bytes).version,41);var wrong=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);wrong["version"]=40;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:wrong)));var replay=source;try file.actions[0].apply(to:&replay);XCTAssertEqual(replay,s.document);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(s.document)),s.document);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,expected);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)
  }
  @MainActor func testNativeMaskChannelTargetRetentionAndStateSchema()async throws{
    let source=try fixture(),s=EditorStore(document:source);defer{s.renderTask?.cancel();s.geometryTask?.cancel()};s.selectMask(source.layers[0].id);XCTAssertTrue(s.editingMask);var settings=PixelPaintSettings(color:.black);settings.opacity=0.5;s.applyPixelPaint(.fill,settings:settings);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertTrue(s.editingMask);XCTAssertEqual(s.document.layers[0].content,source.layers[0].content);try s.selectAlphaChannel(try XCTUnwrap(source.alphaChannels?.first?.id));let before=s.document;s.applyPixelPaint(.stroke,settings:settings);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertEqual(s.document.layers,before.layers);XCTAssertNotNil(s.editingChannel);let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.pixelPaintState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:PixelPaintAPI.stateSchema))
  }
  @MainActor func testHTTPBothOperationsThreeDepthsAndTargetsEqualNativeDocumentBytes()async throws{
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in let s=doc.store;for depth in PixelDepth.allCases{for targetKind in ["layer","mask","channel"]{for kind in PixelPaintKind.allCases{let source=try self.fixture(depth);s.session=EditorSession(document:source);s.maskEditingLayerID=nil;s.alphaEditingID=nil;s.componentTarget = .composite;let id=source.layers[0].id,target:PixelPaintTarget;var params:[String:Any]=["color":[0.8,0.3,0.2,1.0],"opacity":0.5,"mode":"Multiply"];switch targetKind{case "mask":s.selectMask(id);target = .mask(id);params["layerID"]=id.uuidString;params["mask"]=true;case "channel":let channel=try XCTUnwrap(source.alphaChannels?.first?.id);try s.selectAlphaChannel(channel);target = .channel(.alpha(channel));params["target"]=channel.uuidString;default:target = .layer(id);params["layerID"]=id.uuidString};try service.share(doc);if kind == .stroke{params["width"]=2;params["location"]="Inside"};let code=try await h.edit(service,doc,"pixels."+kind.rawValue,params);XCTAssertEqual(code,200);var settings=PixelPaintSettings(color:Pixel(0.8,0.3,0.2));settings.opacity=0.5;settings.mode = .multiply;if kind == .stroke{settings.width=2;settings.location = .inside};var expected=source;try Command.pixelPaint(.init(kind,target:target,settings:settings)).apply(to:&expected);XCTAssertEqual(s.document,expected);XCTAssertEqual(try NativeArchive.encodeChunked(s.document),try NativeArchive.encodeChunked(expected));XCTAssertEqual(s.nativePixelPaintTarget,target);_=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,source)}}}}
  }
  @MainActor func testInvalidBusyStaleLockedWrongAndRevokedAPIPaintsNeverPublish()async throws{
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in let source=try self.fixture(),s=doc.store;s.session=EditorSession(document:source);try service.share(doc);let params:[String:Any]=["layerID":source.layers[0].id.uuidString,"color":[1,1,1,1],"width":2];for extra:[String:Any] in [["width":0],["width":251],["width":1.5],["location":"bad"],["mode":"bad"],["opacity":2],["color":[1,1,1]],["mask":"yes"],["unknown":1]]{let code=try await h.edit(service,doc,"pixels.stroke",params.merging(extra){_,b in b});XCTAssertEqual(code,400);XCTAssertEqual(s.document,source)};let stale=try await h.edit(service,doc,"pixels.stroke",params,revision:"old");XCTAssertEqual(stale,409);s.beginTransform();let busy=try await h.edit(service,doc,"pixels.stroke",params);XCTAssertEqual(busy,409);s.cancelTransform();var locked=source;locked.layers[0].protection = .image;s.session=EditorSession(document:locked);let rejected=try await h.edit(service,doc,"pixels.stroke",params);XCTAssertEqual(rejected,422);XCTAssertEqual(s.document,locked);s.session=EditorSession(document:source);let wrong=try await h.edit(service,doc,"pixels.stroke",params.merging(["mask":true]){_,b in b});XCTAssertEqual(wrong,422);let gate=PixelPaintGate();defer{gate.release()};s.pixelPaintPreparation={_,request in gate.wait();try Task.checkCancellation();return .pixelPaint(request)};let task=Task{try await h.edit(service,doc,"pixels.stroke",params)};let until=Date().addingTimeInterval(10);while !s.geometryBusy && Date()<until{await Task.yield()};service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();let code=try await task.value;XCTAssertEqual(code,409);XCTAssertEqual(s.document,source)}
  }
  @MainActor func testNativeCancellationAndChangedTargetCannotCommit()async throws{
    let source=try fixture(),s=EditorStore(document:source);defer{s.renderTask?.cancel();s.geometryTask?.cancel()};let gate=PixelPaintGate();defer{gate.release()};s.pixelPaintPreparation={_,request in gate.wait();try Task.checkCancellation();return .pixelPaint(request)};s.applyPixelPaint(.fill,settings:.init(color:.white));let task=try XCTUnwrap(s.geometryTask);s.geometryTask?.cancel();gate.release();await task.value;XCTAssertEqual(s.document,source);XCTAssertTrue(s.session.undoStack.isEmpty);let changed=PixelPaintGate();defer{changed.release()};s.pixelPaintPreparation={_,request in changed.wait();try Task.checkCancellation();return .pixelPaint(request)};s.applyPixelPaint(.stroke,settings:.init());let worker=try XCTUnwrap(s.geometryTask);s.maskEditingLayerID=source.layers[0].id;changed.release();await worker.value;XCTAssertEqual(s.document,source);XCTAssertNotNil(s.error)
  }
  @MainActor func testLiveSmartObjectAndComponentContextsStayUnavailableWithoutImplicitRasterize()throws{
    var source=try fixture();try SmartObjectIO.convert(in:source,selected:[source.layers[0].id]).apply(to:&source);let s=EditorStore(document:source);defer{s.renderTask?.cancel()};XCTAssertFalse(s.canUsePixelPaint);let before=s.document;s.applyPixelPaint(.stroke,settings:.init());XCTAssertEqual(s.document,before);var shape=try fixture();shape.layers[0].content = .shape(.init(kind:.rectangle,width:5,height:4,color:.white));s.session=EditorSession(document:shape);XCTAssertFalse(s.canUsePixelPaint);s.session=EditorSession(document:try fixture());s.componentTarget = .red;XCTAssertFalse(s.canUsePixelPaint)
  }
  @MainActor func testCatalogueSchemasAndEveryNewDialogKeepsCanvasCursorPolicy()throws{
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount);let s=EditorStore(document:try fixture());defer{s.renderTask?.cancel()};let canvas=CraftCanvas(store:s),flags:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift];for bits in 0..<16{let current=flags.enumerated().reduce(NSEvent.ModifierFlags()){r,p in bits&(1<<p.offset) != 0 ? r.union(p.element):r};canvas.updateCursorModifiers(current);let before=canvas.toolCursor;_ = PixelPaintAccessory(kind:.stroke,settings:.init(),scalar:false);canvas.updateCursorModifiers(current);XCTAssertEqual(canvas.toolCursor,before)};XCTAssertEqual(PixelPaintAPI.commands,["pixels.fill","pixels.stroke"]);XCTAssertEqual(ActionLibraryFile.maximumVersion,AutomationTests.expectedActionVersion)
  }
}
