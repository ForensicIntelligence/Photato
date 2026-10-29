import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ProceduralWorkflowTests:XCTestCase {
  let kinds=ProceduralRenderSettings.Kind.allCases
  static var path:VectorPath {VectorPath(components:[PathComponent(knots:[PathKnot(.init(20,80)),PathKnot(.init(40,64)),PathKnot(.init(80,70)),PathKnot(.init(108,25))])])}
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:128,height:96,depth:depth)
    var pixels=try Surface(width:128,height:96,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<96 {for x in 0..<128 {pixels.setPixel(x:x,y:y,Pixel(Float(x)/128,Float(y)/96,0.3,0.65))}}
    d.layers[0].content = .raster(pixels);d.paths=[NamedPath(name:"Flame Path",path:Self.path,isWorkPath:true)]
    return d
  }
  func configured(_ kind:ProceduralRenderSettings.Kind)->ProceduralRenderSettings {
    var s=ProceduralRenderSettings(kind);s.flame.length=55;s.flame.width=16;s.flame.seed=42;s.tree.baseTreeType=14;s.tree.seed=42;s.frame.frame=3;s.frame.seed=42;return s
  }
  func testStrictSchemasDefaultsAndAdobeUnsupportedDescriptors()throws {
    for kind in kinds {
      let definition=try XCTUnwrap(AutomationCommand.definitions.first{$0.name=="render."+kind.rawValue})
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:definition.schema))
      let defaults=ProceduralRenderSettings(kind),data=try JSONSerialization.data(withJSONObject:ProceduralAPI.values(defaults)),input=try JSONDecoder().decode(AutomationValue.self,from:data)
      XCTAssertEqual(try ProceduralAPI.decode(input,kind:kind),defaults)
      XCTAssertThrowsError(try ProceduralAPI.decode(.object(["unknown":.number(3)]),kind:kind))
      XCTAssertThrowsError(try ProceduralAPI.decode(.object(["seed":.number(-1)]),kind:kind))
      XCTAssertThrowsError(try ProceduralAPI.decode(.object(["seed":.number(0.5)]),kind:kind))
      XCTAssertThrowsError(try ProceduralAPI.decode(.object(["seed":.bool(true)]),kind:kind))
      XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"\(kind.rawValue)\"}]"))
    }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ProceduralAPI.capabilities))
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ProceduralAPI.stateSchema))
  }
  func testActions15RecordReplayNativeAndPSDOutput()throws {
    for kind in kinds {
      let d=try fixture(),request=ProceduralRenderRequest(configured(kind),layerID:d.layers[0].id),command=Command.proceduralRender(request)
      var session=EditorSession(document:d);try session.startActionRecording(name:kind.title);try session.execute(command)
      let edited=session.document,action=try XCTUnwrap(session.actionRecording?.snapshot)
      XCTAssertEqual(action.steps.count,1);XCTAssertNil(action.steps.first?.operation.unsupportedReason)
      let bytes=try ActionLibraryFile(actions:[action]).encoded(),library=try ActionLibraryFile.decode(bytes)
      XCTAssertEqual(library.version,15);XCTAssertEqual(try library.encoded(),bytes)
      var replay=d;replay.paths=nil;try library.actions[0].apply(to:&replay)
      var expected=edited;expected.paths=nil;XCTAssertEqual(replay,expected)
      var forged=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];forged["version"]=14
      XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:forged)))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(edited)),edited)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(edited)),edited)
      let psd=try DocumentIO.encode(edited,format:.psd),reopened=try PSDCodec.read(psd);XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:.u8),try Renderer.composite(edited).rgbaData(depth:.u8))
      try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,edited)
    }
    let invalid=RecordedAction(name:"Missing path",steps:[.init(name:"Flame",operation:.proceduralRender(.active,.init(.flame),false,nil))])
    XCTAssertThrowsError(try invalid.validate())
  }
  @MainActor func testPreviewHistoryCancelCommitAndRecordedDesktopRequest()async throws {
    for kind in kinds {
      let d=try fixture(),store=EditorStore(document:d,actions:ActionLibrary());defer{store.cancelProcedural();store.renderTask?.cancel()}
      try store.startRecordingAction(name:kind.title,set:"Render")
      store.beginProcedural(kind);let model=try XCTUnwrap(store.proceduralWorkspace);await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "Not ready");XCTAssertEqual(store.document,d)
      let initial=model.request;model.update{$0.settings=configured(kind)};let changed=model.request
      model.undo();XCTAssertEqual(model.request,initial);model.redo();XCTAssertEqual(model.request,changed)
      await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Not ready")
      var expected=d;try Command.proceduralRender(changed).apply(to:&expected)
      store.commitProcedural();let commit=model.commitTask;await commit?.value
      XCTAssertNil(store.proceduralWorkspace);XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
      let action=try store.stopRecordingAction(save:false);XCTAssertEqual(action.steps.count,1)
      await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document,expected)
      store.beginProcedural(kind);let cancelled=try XCTUnwrap(store.proceduralWorkspace);cancelled.update{$0.newLayer=true};let worker=cancelled.task
      store.cancelProcedural();await worker?.value;XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    }
  }
  @MainActor func testTreeGestureValidationNewLayerAndStaleCommit()async throws {
    let d=try fixture(),store=EditorStore(document:d);defer{store.cancelProcedural();store.renderTask?.cancel()}
    store.beginProcedural(.tree);let model=try XCTUnwrap(store.proceduralWorkspace);await model.task?.value
    model.beginGesture();model.setTreeBase(.init(0.2,0.8));model.setTreeBase(.init(0.3,0.7));model.endGesture();XCTAssertEqual(model.undoStates.count,1)
    let moved=model.request;model.undo();XCTAssertEqual(model.request.settings.tree.x,0.5);model.redo();XCTAssertEqual(model.request,moved)
    model.setTreeBase(.init(.nan,0));XCTAssertEqual(model.request,moved)
    var invalid=moved;invalid.settings.tree.leavesSize=201;model.change(invalid);XCTAssertNotNil(model.error);XCTAssertEqual(model.request,moved)
    model.change(moved);await model.task?.value;XCTAssertTrue(model.ready)
    model.update{$0.newLayer=true};await model.task?.value;XCTAssertTrue(model.ready)
    store.commitProcedural();let task=model.commitTask;await task?.value
    XCTAssertEqual(store.document.layers.count,2);XCTAssertEqual(store.document.layers.first,d.layers.first)
    await store.undo();XCTAssertEqual(store.document,d)
    store.beginProcedural(.tree);let stale=try XCTUnwrap(store.proceduralWorkspace);await stale.task?.value
    var modified=d;modified.name="Changed while previewing";store.session=EditorSession(document:modified)
    store.commitProcedural();let staleTask=stale.commitTask;await staleTask?.value
    XCTAssertNotNil(stale.error);XCTAssertEqual(store.document,modified);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testMenusPathsAndUnsupportedTargets()throws {
    var d=try fixture();d.paths=nil;let store=EditorStore(document:d);defer{store.cancelProcedural();store.renderTask?.cancel()}
    XCTAssertFalse(store.canBeginProcedural(.flame));XCTAssertTrue(store.canBeginProcedural(.tree));XCTAssertTrue(store.canBeginProcedural(.pictureFrame))
    store.session=EditorSession(document:try fixture());let id=try XCTUnwrap(store.document.paths?.first?.id);store.selectPath(.saved(id));XCTAssertTrue(store.canBeginProcedural(.flame))
    store.beginProcedural(.flame);XCTAssertEqual(store.proceduralWorkspace?.request.path,Self.path);store.cancelProcedural()
    for kind in kinds {XCTAssertEqual(AppDelegate.proceduralMenus["Filter > Render > \(kind.title)…"],kind)}
    var locked=try fixture();locked.layers[0].protection=[.image];store.session=EditorSession(document:locked)
    for kind in kinds {XCTAssertFalse(store.canBeginProcedural(kind))}
    var smart=try fixture();try SmartObjectIO.convert(in:smart,selected:[smart.layers[0].id]).apply(to:&smart)
    store.session=EditorSession(document:smart);XCTAssertFalse(store.canBeginProcedural(.tree))
  }
  @MainActor func testHTTPDesktopEquivalenceNewLayerAndInvalidBusyStaleGuards()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for kind in self.kinds {
        let d=try self.fixture(),settings=self.configured(kind);document.store.session=EditorSession(document:d)
        let params:[String:Any]=["settings":ProceduralAPI.values(settings),"layerID":d.layers[0].id.uuidString]
        var expected=d;try Command.proceduralRender(.init(settings,layerID:d.layers[0].id)).apply(to:&expected)
        let status=try await h.edit(service,document,"render."+kind.rawValue,params);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
        var new=params;new["newLayer"]=true
        let created=try await h.edit(service,document,"render."+kind.rawValue,new);XCTAssertEqual(created,200);XCTAssertEqual(document.store.document.layers.count,2);XCTAssertEqual(document.store.document.layers.first,d.layers.first)
        let undoNew=try await h.edit(service,document,"history.undo");XCTAssertEqual(undoNew,200);XCTAssertEqual(document.store.document,d)
        let stale=try await h.edit(service,document,"render."+kind.rawValue,params,revision:"stale");XCTAssertEqual(stale,409)
        document.store.beginProcedural(kind);let busy=try await h.edit(service,document,"render."+kind.rawValue,params);XCTAssertEqual(busy,409);document.store.cancelProcedural()
        let bad=try await h.edit(service,document,"render."+kind.rawValue,["settings":["seed":-1]]);XCTAssertEqual(bad,400)
        let absent=try await h.edit(service,document,"render."+kind.rawValue,["layerID":UUID().uuidString]);XCTAssertEqual(absent,404)
        XCTAssertEqual(document.store.document,d);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      }
      let d=try self.fixture();document.store.session=EditorSession(document:d)
      let path=try XCTUnwrap(d.paths?.first);document.store.selectPath(.saved(path.id))
      let valid=try await h.edit(service,document,"render.flame",["pathID":path.id.uuidString]);XCTAssertEqual(valid,200)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200)
      let missing=try await h.edit(service,document,"render.flame",["pathID":UUID().uuidString]);XCTAssertEqual(missing,404)
      let irrelevant=try await h.edit(service,document,"render.tree",["pathID":path.id.uuidString]);XCTAssertEqual(irrelevant,400)
      let share=try XCTUnwrap(service.shares.first);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
    }
  }
  @MainActor func testHostedPreviewLayoutForEveryGenerator()async throws {
    for kind in kinds {
      let store=EditorStore(document:try fixture());defer{store.cancelProcedural();store.renderTask?.cancel()}
      store.beginProcedural(kind);let model=try XCTUnwrap(store.proceduralWorkspace);model.update{$0.settings=configured(kind)};await model.task?.value
      XCTAssertTrue(model.ready,model.error ?? "Not ready")
      let view=NSHostingView(rootView:ProceduralSheet(store:store,model:model).background(Color(nsColor:.windowBackgroundColor)))
      let window=NSWindow(contentRect:NSRect(x:0,y:0,width:860,height:640),styleMask:[.borderless],backing:.buffered,defer:false)
      view.appearance=NSAppearance(named:.aqua);window.contentView=view;view.frame=NSRect(x:0,y:0,width:860,height:640);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
      XCTAssertGreaterThan(view.fittingSize.width,800)
      if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap)
        if let png=bitmap.representation(using:.png,properties:[:]) {let path=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/procedural-offscreen");try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true);try png.write(to:path.appendingPathComponent(kind.rawValue+"-"+UUID().uuidString+".png"))}
      };window.contentView=nil
    }
  }
}
