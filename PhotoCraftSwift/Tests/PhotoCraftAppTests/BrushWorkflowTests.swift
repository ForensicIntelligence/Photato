import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BrushWorkflowTests:XCTestCase {
  @MainActor func testNativeGesturePreviewCancelCommitAndRecordedPlayback()async throws {
    let doc=try CraftDocument(width:64,height:48),store=EditorStore(document:doc,actions:ActionLibrary(),brushes:BrushLibrary())
    defer {store.renderTask?.cancel();store.cancelBrush()}
    store.tool = .brush;store.brush.size=10;store.brush.color=Pixel(1,0,0);store.brushOptions.flow=0.5
    try store.startRecordingAction(name:"Paint",set:"Test")
    store.beginBrush(.init(x:12,y:20,time:0),zoom:1);store.extendBrush(.init(x:44,y:25,pressure:0.4,tiltX:30,rotation:45,time:100));await store.brushPreviewTask?.value;await store.renderTask?.value
    XCTAssertTrue(store.hasToneDraft);XCTAssertEqual(store.document,doc);XCTAssertNotNil(store.brushPreviewCommand)
    let draft=try XCTUnwrap(store.brushGesture);var expected=doc;try draft.command.apply(to:&expected)
    XCTAssertTrue(store.surface == (try Renderer.composite(expected)),"Preview must include every queued sample");store.cancelBrush();await store.renderTask?.value;XCTAssertEqual(store.document,doc);XCTAssertFalse(store.hasToneDraft)
    store.beginBrush(.init(x:12,y:20,time:0),zoom:1);store.extendBrush(.init(x:44,y:25,time:100));let command=try XCTUnwrap(store.brushGesture?.command);expected=doc;try command.apply(to:&expected)
    store.finishBrush();await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.document,expected);XCTAssertEqual(store.session.undoStack.count,1)
    let action=try store.stopRecordingAction();let saved=try store.actions.exportFile(action.id);XCTAssertEqual(try ActionLibraryFile.decode(saved).version,2)
    var replay=doc;try action.apply(to:&replay);XCTAssertEqual(replay,expected)
    _=await store.requestHistory(redo:false).value;XCTAssertEqual(store.document,doc);_=await store.requestHistory(redo:true).value;XCTAssertEqual(store.document,expected)
    let legacy=RecordedAction(name:"Legacy",steps:[.init(name:"Select",operation:.select(.active))]);try store.actions.save(legacy)
    XCTAssertEqual(try ActionLibraryFile.decode(store.actions.exportFile(legacy.id)).version,store.actions.file.version)
    var downgraded=try JSONSerialization.jsonObject(with:saved) as! [String:Any];downgraded["version"]=1;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
  }
  @MainActor func testLibraryAtomicPersistenceDefineAndPresetLocks()async throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("Brushes.photatobrushes"),library=BrushLibrary(persistenceURL:url)
    var doc=try CraftDocument(width:8,height:8);var s=try Surface(width:8,height:8,fill:.white);s.setPixel(x:2,y:2,.black);doc.layers[0].content = .raster(s)
    let store=EditorStore(document:doc,brushes:library);defer{store.renderTask?.cancel()}
    let preset=try await store.defineBrush(name:"Ink Tip");XCTAssertEqual(preset.brush.settings?.tip?.bytes[18],255);XCTAssertEqual(store.document,doc)
    XCTAssertEqual(BrushLibrary(persistenceURL:url).file.presets,library.file.presets)
    store.brushOptions.shape.enabled=true;store.brushOptions.shape.size.jitter=0.8;store.brushOptions.lockedSections=["shape"]
    try store.selectBrush(library.file.presets[0].id);XCTAssertEqual(store.brushOptions.shape.size.jitter,0.8)
    let before=try Data(contentsOf:url);var bad=preset;bad.name="";XCTAssertThrowsError(try library.save(bad));XCTAssertEqual(try Data(contentsOf:url),before)
    try library.remove(preset.id);let exported=try library.exportData(library.file.presets[0].id,abr:true);let count=library.file.presets.count;XCTAssertEqual(try library.importData(exported,abr:true),[]);XCTAssertEqual(library.file.presets.count,count+1)
    try Data("invalid".utf8).write(to:url);let damaged=BrushLibrary(persistenceURL:url);XCTAssertNotNil(damaged.loadError);XCTAssertThrowsError(try damaged.save(preset));XCTAssertEqual(try Data(contentsOf:url),Data("invalid".utf8))
  }
  @MainActor func testHTTPBrushSettingsPresetsStrokeEqualityAndGuards()async throws {
    let helper=AutomationTests(),library=BrushLibrary()
    try await helper.withService(actions:ActionLibrary(),brushes:library,pressedMouseButtons:{0}){service,document in
      let doc=try CraftDocument(width:64,height:48);document.store.session=EditorSession(document:doc);try service.share(document)
      let configured:[String:Any]=["size":10,"color":["r":1,"g":0,"b":0,"a":1],"settings":["flow":0.5,"spacing":0.5,"shape":["enabled":true,"size":["control":"penPressure"]],"symmetry":["mode":"vertical","center":["x":32,"y":24]],"seed":21]]
      var status=try await helper.edit(service,document,"brush.configure",["brush":configured]);XCTAssertEqual(status,200)
      status=try await helper.edit(service,document,"brush.presets",["operation":"save","name":"API Brush","includeColor":true]);XCTAssertEqual(status,200);XCTAssertEqual(library.file.presets.last?.name,"API Brush")
      let points:[StrokePoint]=[.init(x:12,y:12,pressure:0.5,tiltX:30,time:0),.init(x:20,y:36,time:150)]
      let params:[String:Any]=["points":BrushAPI.json(points),"target":"pixels"]
      var expected=doc;try Command.stroke(doc.layers[0].id,points,document.store.brush).apply(to:&expected)
      status=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,expected);XCTAssertEqual(document.store.session.undoStack.count,1)
      status=try await helper.edit(service,document,"paint.stroke",params,revision:"stale");XCTAssertEqual(status,409)
      document.store.tool = .brush;document.store.beginBrush(.init(x:1,y:1),zoom:1)
      status=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(status,409);document.store.cancelBrush()
      for patch:[String:Any] in [["settings":["flow":true]],["settings":["shape":["unknown":1]]],["size":0],["settings":["tip":["width":2,"height":2,"bytes":"AA=="]]],["settings":["symmetry":["count":1.5]]],["settings":["mode":"unknown"]]] {
        status=try await helper.edit(service,document,"brush.configure",["brush":patch]);XCTAssertEqual(status,400)
      }
      XCTAssertEqual(document.store.document,expected);status=try await helper.edit(service,document,"history.undo");XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,doc)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:BrushAPI.capabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:document.store.brushState))
    }
  }
  @MainActor func testAPIAllMaskTargetsAndDefinitionRevocation()async throws {
    let helper=AutomationTests(),library=BrushLibrary()
    try await helper.withService(brushes:library,pressedMouseButtons:{0}){service,document in
      var doc=try CraftDocument(width:32,height:24);let layer=doc.layers[0].id
      doc.layers[0].mask=try Surface(width:32,height:24,fill:.white)
      try SmartObjectIO.convert(in:doc,selected:[layer]).apply(to:&doc)
      doc.layers[0].mask=try Surface(width:32,height:24,fill:.white)
      doc.layers[0].smartFilters = .init();doc.layers[0].smartFilters!.mask=try Surface(width:32,height:24,fill:.white)
      let alpha=AlphaChannel(name:"Test",pixels:try Surface(width:32,height:24,fill:.white))
      try Command.channel(.create(alpha)).apply(to:&doc);try Command.channel(.quickMask(true,.init())).apply(to:&doc)
      document.store.session=EditorSession(document:doc);try service.share(document)
      for target in ["layerMask","smartFilterMask","alpha","quickMask"] {
        var p:[String:Any]=["target":target,"points":[["x":10,"y":10]],"brush":["size":8,"color":["r":0,"g":0,"b":0,"a":1],"settings":["flow":0.7]]]
        if target=="alpha"{p["channelID"]=alpha.id.uuidString}
        let input=try JSONSerialization.data(withJSONObject:["command":"paint.stroke","revision":"test","parameters":p])
        let command=try AutomationCommand(data:input)
        var expected=document.store.document;try command.brushStroke(document:expected,current:document.store.brush,library:library.file).apply(to:&expected)
        let status=try await helper.edit(service,document,"paint.stroke",p);XCTAssertEqual(status,200,target);XCTAssertEqual(document.store.document,expected)
      }
    }
    var dark=try CraftDocument(width:16,height:16);dark.layers[0].content = .raster(try Surface(width:16,height:16,fill:.black))
    let store=EditorStore(document:dark,brushes:library);defer{store.renderTask?.cancel()}
    let original=library.file
    do {_ = try await store.defineBrush(name:"Rejected"){throw AutomationFailure(status:409,message:"revoked")};XCTFail("Commit guard ignored")}catch{}
    XCTAssertEqual(library.file,original);XCTAssertFalse(store.geometryBusy)
  }
  func testExpandedMaskSymmetryAndTypedTargets()throws {
    var doc=try CraftDocument(width:64,height:48);let id=doc.layers[0].id;doc.layers[0].mask=try Surface(width:1,height:1,fill:.white)
    var brush=Brush();brush.size=10;brush.color = .black;brush.settings = .init();brush.settings!.symmetry.mode = .vertical;brush.settings!.symmetry.center = .init(32,24)
    try Command.maskStroke(id,[.init(x:10,y:20)],brush).apply(to:&doc)
    XCTAssertGreaterThan(doc.layers[0].mask!.width,45)
    let result=try NativeArchive.decode(NativeArchive.encodeChunked(doc));XCTAssertEqual(result,doc)
  }
  @MainActor func testCanvasPointerStrokeEscapeAndFrozenToolSettings()async throws {
    let store=EditorStore(document:try CraftDocument(width:64,height:48),brushes:BrushLibrary());defer{store.cancelBrush();store.renderTask?.cancel()}
    store.tool = .brush;store.brush.size=8;store.brush.color = .black
    let canvas=CraftCanvas(store:store);canvas.frame=NSRect(x:0,y:0,width:320,height:240)
    func event(_ type:NSEvent.EventType,_ x:Double,_ time:Double)throws->NSEvent {
      let point=canvas.viewPoint(CGPoint(x:x,y:24))
      return try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:time,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))
    }
    canvas.mouseDown(with:try event(.leftMouseDown,10,1));canvas.mouseDragged(with:try event(.leftMouseDragged,25,1.1))
    XCTAssertEqual(store.brushGesture?.points.count,2);store.brush.size=80
    XCTAssertEqual(store.brushGesture?.brush.size,8)
    canvas.mouseUp(with:try event(.leftMouseUp,30,1.2));await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);let before=store.document
    canvas.mouseDown(with:try event(.leftMouseDown,15,2))
    let escape=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:2.1,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53))
    canvas.keyDown(with:escape);canvas.mouseUp(with:try event(.leftMouseUp,20,2.2))
    XCTAssertNil(store.brushGesture);XCTAssertEqual(store.document,before);XCTAssertNil(canvas.airbrushTimer)
  }
  @MainActor func testToolRevisionIgnoresNoopsAndDoesNotInvalidateDocumentClose()async throws {
    try await AutomationTests().withService(brushes:BrushLibrary(),pressedMouseButtons:{0}){service,document in
      let store=document.store,initial=service.revision(document.store),closing=service.documentClosingRevision
      let same=store.brush;store.brush=same;XCTAssertEqual(service.revision(store),initial)
      store.brush.size += 1;XCTAssertNotEqual(service.revision(store),initial);XCTAssertEqual(service.documentClosingRevision,closing)
      try store.executeEditorCommand(.renameLayer(store.document.layers[0].id,"Changed"));XCTAssertNotEqual(service.documentClosingRevision,closing)
    }
  }
  @MainActor func testFactoryBindingsAndOffscreenPanels()throws {
    try PhotoshopMenuTests().withMenus{app,menu in
      let all=PhotoshopMenuTests().allItems(menu)
      for (path,selector) in [("Window > Brush Settings",#selector(AppDelegate.showBrushSettings)),("Window > Brushes",#selector(AppDelegate.showBrushes)),("Edit > Define Brush Preset…",#selector(AppDelegate.defineBrushPreset))] {
        let item=try XCTUnwrap(all.first{$0.identifier?.rawValue==path});XCTAssertEqual(item.action,selector)
        if path=="Window > Brush Settings"{XCTAssertEqual(item.keyEquivalent,"\u{f708}");XCTAssertTrue(app.validateMenuItem(item))}
      }
    }
    let store=EditorStore(document:try CraftDocument(width:64,height:48),brushes:BrushLibrary());defer{store.renderTask?.cancel()}
    let view=NSHostingView(rootView:BrushSettingsPanel(store:store));view.frame=NSRect(x:0,y:0,width:600,height:500);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,500)
    let presets=NSHostingView(rootView:BrushesPanel(store:store));presets.frame=NSRect(x:0,y:0,width:500,height:600);presets.layoutSubtreeIfNeeded();XCTAssertGreaterThan(presets.fittingSize.width,350)
  }
}
