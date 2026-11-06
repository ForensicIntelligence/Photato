import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class PathFillGate:@unchecked Sendable {
  private let lock=NSCondition();private var started=false,released=false
  func wait()throws{lock.lock();started=true;lock.broadcast();while !released{if Task.isCancelled{lock.unlock();throw CancellationError()};_ = lock.wait(until:Date(timeIntervalSinceNow:0.01))};lock.unlock();try Task.checkCancellation()}
  func release(){lock.lock();released=true;lock.broadcast();lock.unlock()}
  var ready:Bool{lock.lock();defer{lock.unlock()};return started}
}
final class PathFillWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:8,height:8,depth:depth);d.layers[0].locked=false;d.layers[0].content = .raster(try Surface(width:8,height:8,depth:depth))
    d.paths=[NamedPath(name:"Square",path:try ShapeGeometry(kind:.rectangle,width:4,height:4).path().transformed(.translation(2,2)))];return d
  }
  @MainActor func store(_ d:CraftDocument)throws->EditorStore{let s=EditorStore(document:d,patterns:PatternLibrary(),actions:ActionLibrary());s.selectPath(.saved(try XCTUnwrap(d.paths?.first?.id)));return s}
  @MainActor func open(_ s:EditorStore)throws->PathFillDraft{s.beginPathFill();return try XCTUnwrap(s.pathFillDraft)}
  @MainActor private func wait(_ gate:PathFillGate)async throws{for _ in 0..<1000{if gate.ready{return};try await Task.sleep(for:.milliseconds(2))};XCTFail("Path Fill worker did not start");throw CancellationError()}
  @MainActor func testContentsAllDepthsNativeUndoArchiveAndExactNativeAPIDocuments()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,shared in
      try service.share(shared)
      for depth in PixelDepth.allCases {
        let d=try fixture(depth);shared.store.session=EditorSession(document:d);shared.store.selectPath(.saved(try XCTUnwrap(d.paths?.first?.id)))
        let native=try store(d);defer{native.cancelPathFill();native.renderTask?.cancel()};let draft=try open(native);draft.choose(.color);draft.options.color=Pixel(1,0,0);draft.options.antiAlias=false;draft.options.opacity=0.5
        native.commitPathFill(draft);await native.geometryTask?.value;XCTAssertNil(native.error);XCTAssertEqual(native.session.undoStack.count,1)
        let status=try await helper.edit(service,shared,"path.paint",["fill":PathFillAPI.settings(draft.options)]);XCTAssertEqual(status,200);XCTAssertEqual(shared.store.document,native.document);XCTAssertEqual(shared.store.lastPathFill,native.lastPathFill)
        XCTAssertEqual(try DocumentIO.encode(shared.store.document,format:.png),try DocumentIO.encode(native.document,format:.png));XCTAssertEqual(shared.store.document.selectionMask,d.selectionMask);XCTAssertEqual(shared.store.document.paths,d.paths)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(native.document)),native.document);await native.undo();XCTAssertEqual(native.document,d)
        let undo=try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(shared.store.document,d)
      }
    }
  }
  @MainActor func testContentsPatternsClearAndActions50KeepOlderVersions()async throws {
    let d=try fixture(),s=try store(d);defer{s.cancelPathFill();s.renderTask?.cancel()};s.brush.color=Pixel(1,0,0);s.backgroundColor=Pixel(0,0,1)
    for (contents,ink)in [(PathFillOptions.Contents.foreground,Pixel(1,0,0)),(.background,Pixel(0,0,1)),(.black,.black),(.gray,Pixel(128.0/255,128.0/255,128.0/255)),(.white,.white)] {
      let draft=try open(s);draft.choose(contents);draft.options.antiAlias=false;s.commitPathFill(draft);await s.geometryTask?.value;XCTAssertNil(s.error)
      guard case .raster(let p)=s.document.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(p.pixel(x:3,y:3),ink);await s.undo();XCTAssertEqual(s.document,d)
    }
    let draft=try open(s);draft.choose(.pattern);let pattern=try XCTUnwrap(draft.context.patterns.first);XCTAssertEqual(draft.options.patternID,pattern.id)
    let command=try PathFill.command(draft.path,document:d,layerID:d.layers[0].id,options:draft.options,context:draft.context),operation=ActionOperation(recording:command,in:d)
    let action=RecordedAction(name:"Pattern path",steps:[.init(name:"Fill",operation:operation)]),file=ActionLibraryFile(actions:[action]);XCTAssertEqual(file.requiredVersion,50);XCTAssertEqual(try ActionLibraryFile.decode(file.encoded()).version,50)
    var direct=d,replay=d;try command.apply(to:&direct);try action.apply(to:&replay);XCTAssertEqual(direct,replay)
    let legacy=RecordedAction(name:"Old fill",steps:[.init(name:"Fill",operation:.pixelPaint(.fill,.layer(.active),.init()))]);XCTAssertEqual(ActionLibraryFile(actions:[legacy]).requiredVersion,41)
    let selection=RecordedAction(name:"Legacy selection",steps:[.init(name:"Deselect",operation:.deselectLayers)]);let older=ActionLibraryFile(actions:[selection]);XCTAssertEqual(older.requiredVersion,49);XCTAssertEqual(try ActionLibraryFile.decode(older.encoded()).version,49)
    var downgraded=try XCTUnwrap(JSONSerialization.jsonObject(with:file.encoded()) as? [String:Any]);downgraded["version"]=49;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
    s.cancelPathFill();let history=try open(s);history.choose(.history);XCTAssertFalse(history.valid);s.cancelPathFill()
    var clear=PathFillOptions();clear.clear=true;let c=try PathFill.command(d.paths![0].path,document:direct,layerID:direct.layers[0].id,options:clear,context:s.pathFillContext);try c.apply(to:&direct)
    guard case .raster(let p)=direct.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(p.pixel(x:3,y:3).a,0)
  }
  @MainActor func testFooterModifierMatrixLegacyOpacityCancelAndOffscreenBounds()async throws {
    _=NSApplication.shared;let d=try fixture(),s=try store(d);defer{s.cancelPathFill();s.renderTask?.cancel()};s.brush.color=Pixel(1,0,0);s.brush.opacity=0.5
    let bits:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift]
    for raw in 0..<16{let flags=bits.enumerated().reduce(NSEvent.ModifierFlags()){raw&(1<<$1.offset)==0 ? $0:$0.union($1.element)};s.fillPathFooter(modifiers:flags)
      if flags.contains(.option){let draft=try XCTUnwrap(s.pathFillDraft);XCTAssertTrue(s.hasToneDraft);XCTAssertEqual(draft.options.opacity,1);s.cancelPathFill();XCTAssertTrue(s.session.undoStack.isEmpty)}
      else{await s.geometryTask?.value;XCTAssertNil(s.error);guard case .raster(let p)=s.document.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(p.pixel(x:3,y:3).a,128.0/255);await s.undo()}
      XCTAssertEqual(s.document,d)
    }
    let draft=try open(s),host=NSHostingView(rootView:PathFillSheet(store:s,draft:draft));host.appearance=NSAppearance(named:.darkAqua);host.frame = .init(x:0,y:0,width:420,height:460);host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.height,460)
    if let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:root).appendingPathComponent("436-fill-path-offscreen.png"))}
    XCTAssertTrue(JSONSerialization.isValidJSONObject(s.pathFillState));XCTAssertTrue(JSONSerialization.isValidJSONObject(PathAPI.capabilities));s.cancelPathFill();XCTAssertEqual(s.document,d)
  }
  @MainActor func testCancellationStaleSessionPathSettingsAndTargetGuards()async throws {
    for variant in ["cancel","session","path","target","settings","lifecycle","epoch","source"] {
      var d=try fixture();d.layers[0].mask=try Surface(width:8,height:8,fill:.white);let s=try store(d),gate=PathFillGate(),settings=ColorSettingsStore(),controller=CraftDocumentController(workspaces:WorkspaceLibrary(),colorSettings:settings);s.documentController=controller;defer{gate.release();s.cancelPathFill();s.renderTask?.cancel();withExtendedLifetime(controller){}}
      let draft=try open(s);s.pathFillPreparation={path,source,id,options,context in try gate.wait();return try PathFill.command(path,document:source,layerID:id,options:options,context:context)};s.commitPathFill(draft);try await wait(gate)
      switch variant{case "cancel":s.geometryTask?.cancel();case "session":s.session=EditorSession(document:d);case "path":s.selectPath(nil);case "target":s.maskEditingLayerID=d.layers[0].id;case "settings":var next=settings.value;next.rgbPolicy = .convertToWorking;try settings.commit(next,revision:settings.revision);case "lifecycle":s.layerPanelGeneration=UUID();case "epoch":s.cancelPathFill();default:var changed=d;changed.name="Changed";s.session=EditorSession(document:changed)}
      let current=s.document;gate.release();await s.geometryTask?.value;XCTAssertEqual(s.document,current);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testAntiAliasFeatherAndClearBackgroundSafeguards()throws {
    let d=try fixture(),context=PathFillContext(foreground:.white,background:.black,patterns:[])
    let path=try ShapeGeometry(kind:.rectangle,width:2.5,height:2.5).path().transformed(.translation(2.25,2.25))
    func filled(_ options:PathFillOptions)throws->Surface{var copy=d;try PathFill.command(path,document:d,layerID:d.layers[0].id,options:options,context:context).apply(to:&copy);guard case .raster(let p)=copy.layers[0].content else{throw CraftError.invalid("Missing raster")};return p}
    var options=PathFillOptions();options.antiAlias=false;let sharp=try filled(options);options.antiAlias=true;let aa=try filled(options);XCTAssertNotEqual(sharp,aa)
    for y in 0..<8{for x in 0..<8{XCTAssertTrue([Float(0),1].contains(sharp.pixel(x:x,y:y).a))}}
    options.feather=2;let soft=try filled(options);XCTAssertGreaterThan(soft.pixel(x:1,y:3).a,0);XCTAssertLessThan(soft.pixel(x:3,y:3).a,1)
    var background=d;try Command.backgroundLayer(.fromLayer(d.layers[0].id,.white)).apply(to:&background);let before=background;options.clear=true
    let command=try PathFill.command(path,document:background,layerID:background.layers[0].id,options:options,context:context);XCTAssertThrowsError(try command.apply(to:&background));XCTAssertEqual(background,before)
    let s=try store(background);defer{s.cancelPathFill();s.renderTask?.cancel()};let draft=try open(s);draft.options.clear=true;XCTAssertFalse(draft.valid)
  }
  @MainActor func testStrictHTTPInvalidHistoryBusyStaleLegacyAndRequestSchema()async throws {
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,doc in
      let d=try fixture();doc.store.session=EditorSession(document:d);doc.store.selectPath(.saved(d.paths![0].id));try service.share(doc)
      for fill:Any in [NSNull(),["typo":true],["opacity":0],["opacity":2],["antiAlias":1],["feather":101],["contents":"color"],["contents":"color","color":[0,0,0,2]],["contents":"foreground","patternID":"bad"]]{let code=try await helper.edit(service,doc,"path.paint",["fill":fill]);XCTAssertEqual(code,400);XCTAssertEqual(doc.store.document,d)}
      let history=try await helper.edit(service,doc,"path.paint",["fill":["contents":"history"]]);XCTAssertEqual(history,422)
      let conflict=try await helper.edit(service,doc,"path.paint",["fill":[:],"stroke":false]);XCTAssertEqual(conflict,400)
      let draft=try open(doc.store);let busy=try await helper.edit(service,doc,"path.paint",["fill":[:]]);XCTAssertEqual(busy,409);XCTAssertTrue(doc.store.pathFillDraft === draft);doc.store.cancelPathFill()
      let stale=try await helper.edit(service,doc,"path.paint",["fill":[:]],revision:"stale");XCTAssertEqual(stale,409)
      doc.store.brush.color=Pixel(1,0,0);doc.store.brush.opacity=0.5
      let old=try await helper.edit(service,doc,"path.paint",[:]);XCTAssertEqual(old,200);guard case .raster(let p)=doc.store.document.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(p.pixel(x:3,y:3).a,128.0/255)
      XCTAssertTrue(JSONSerialization.isValidJSONObject(PathFillAPI.schema));XCTAssertEqual(ActionLibraryFile.maximumVersion,50)
    }
  }
}
