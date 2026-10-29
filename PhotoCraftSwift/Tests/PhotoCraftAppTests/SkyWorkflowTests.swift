import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
@testable import PhotoCraftCore
import PhotoCraftImaging

final class SkyWorkflowTests:XCTestCase {
  func photo(depth:PixelDepth = .u8,width:Int=64,height:Int=48)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth),s=try Surface(width:width,height:height,depth:depth,fill:Pixel(0.12,0.24,0.1))
    for y in 0..<height/2 {for x in 0..<width {s.setPixel(x:x,y:y,Pixel(0.3,0.6,0.95))}}
    d.layers[0].content = .raster(s);return d
  }
  func sky()throws->CraftDocument {
    var d=try CraftDocument(width:40,height:30),s=try Surface(width:40,height:30,fill:Pixel(0.9,0.2,0.25))
    for y in 0..<30{for x in 20..<40{s.setPixel(x:x,y:y,Pixel(0.75,0.4,0.15))}};d.layers[0].content = .raster(s);d.name="Sunset";return d
  }
  func settings()->SkyReplacementSettings{var p=SkyReplacementSettings();p.fadeEdge=0;p.foregroundLighting=0;p.colorAdjustment=0;return p}
  @MainActor func library()throws->SkyLibrary{let library=SkyLibrary();try library.add(.init(name:"Sunset",data:RasterIO.encoded(sky())));return library}
  @MainActor func store(depth:PixelDepth = .u8)throws->EditorStore{EditorStore(document:try photo(depth:depth),actions:ActionLibrary(),brushes:BrushLibrary(),skies:try library())}
  @MainActor func settle(_ draft:SkyWorkspace)async{await draft.task?.value;await draft.task?.value}
  func testEditableGroupDuplicateDepthArchiveAndStaleResult()throws {
    for depth in PixelDepth.allCases{
      let original=try photo(depth:depth),input=try SkyReplacementInput.prepare(original),sky=try sky(),p=settings()
      let result=try input.edit(sky:sky,name:"Sunset",settings:p),doc=result.edit.result,composite=try Renderer.composite(doc)
      XCTAssertEqual(Array(doc.layers.prefix(original.layers.count)),original.layers);XCTAssertEqual(doc.layers.count,original.layers.count+7)
      XCTAssertGreaterThan(composite.pixel(x:5,y:5).r,0.7);XCTAssertEqual(composite.pixel(x:5,y:40),try Renderer.composite(original).pixel(x:5,y:40))
      let placed=try XCTUnwrap(doc.layers.first{$0.name=="Sunset"});XCTAssertNotNil(placed.mask);XCTAssertFalse(placed.effectiveMaskProperties.linked);XCTAssertNotNil(placed.affine)
      XCTAssertEqual(try MaskSampler(layer:placed).coverage(x:5.5,y:5.5),result.mask.coverage(x:5,y:5),accuracy:0.00001)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc))==doc)
      var duplicate=p;duplicate.output = .duplicate;let flat=try input.edit(sky:sky,name:"Sunset",settings:duplicate).edit.result
      XCTAssertEqual(flat.layers.count,original.layers.count+1)
      let actual=try Renderer.composite(flat);var mismatches=0,maximum:Float=0
      for y in 0..<original.height{for x in 0..<original.width{let a=actual.linearPixel(x:x,y:y),b=composite.linearPixel(x:x,y:y);if a != b{mismatches+=1;maximum=max(maximum,max(abs(a.r-b.r),max(abs(a.g-b.g),max(abs(a.b-b.b),abs(a.a-b.a)))))}}}
      print("Sky duplicate \(depth): differing pixels=\(mismatches), max=\(maximum)");// Flattening/recomposition has a documented Float32 rounding gate; exact Photoshop fidelity is deferred.
      if depth == .f32 { XCTAssertLessThanOrEqual(maximum,0.0000001) } else { XCTAssertEqual(mismatches,0) }
      var changed=original;changed.name="Changed";XCTAssertThrowsError(try result.edit.applied(to:changed))
    }
  }
  @MainActor func testSelectionNoSkyHistoryAndManualFallback()async throws {
    let s=try store();defer{s.renderTask?.cancel()};let original=s.document;s.selectSky();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertGreaterThan(try XCTUnwrap(s.document.selectionMask).coverage(x:5,y:5),0.9);XCTAssertEqual(s.document.layers,original.layers)
    _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
    var noSky=try photo();noSky.layers[0].content = .raster(try Surface(width:64,height:48,fill:Pixel(0.1,0.2,0.1)));noSky.selection = .init(x:0,y:0,width:64,height:20)
    s.session=EditorSession(document:noSky);s.selectSky();await s.geometryTask?.value;XCTAssertTrue(s.document==noSky);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertNotNil(s.error);s.error=nil
    s.beginSkyReplacement();let draft=try XCTUnwrap(s.skyWorkspace);await settle(draft);XCTAssertNotNil(draft.error)
    var state=draft.state;state.useSelection=true;state.settings=settings();draft.change(state);await settle(draft);XCTAssertTrue(draft.canCommit,draft.error ?? "No prepared output")
    s.cancelSkyReplacement();XCTAssertTrue(s.document==noSky)
  }
  @MainActor func testWorkspacePreviewLocalUndoCancelCommitAndHistory()async throws {
    let s=try store();defer{s.cancelSkyReplacement();s.renderTask?.cancel()};let original=s.document;s.beginSkyReplacement();let draft=try XCTUnwrap(s.skyWorkspace)
    await settle(draft);XCTAssertTrue(draft.canCommit,draft.error ?? "Not ready");XCTAssertNotNil(draft.previewImage);XCTAssertTrue(s.document==original);XCTAssertTrue(s.hasToneDraft)
    var next=draft.state;next.settings=settings();next.settings.flip=true;next.settings.scale=120;draft.change(next);await settle(draft);let beforeStroke=draft.state
    draft.size=12;draft.hardness=1;draft.add=false;draft.beginStroke(.init(10,8),alternate:false);draft.endStroke();await settle(draft)
    XCTAssertLessThan(try XCTUnwrap(draft.mask).coverage(x:10,y:8),0.1);draft.undo();await settle(draft);XCTAssertEqual(draft.state,beforeStroke);draft.redo();await settle(draft)
    s.cancelSkyReplacement();XCTAssertNil(s.skyWorkspace);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginSkyReplacement();let final=try XCTUnwrap(s.skyWorkspace);await settle(final);let expected=try XCTUnwrap(final.edit).result
    s.commitSkyReplacement();await final.commitTask?.value;XCTAssertNil(s.skyWorkspace);XCTAssertTrue(s.document==expected);XCTAssertEqual(s.session.undoStack.count,1)
    _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original);_=await s.requestHistory(redo:true).value;XCTAssertTrue(s.document==expected)
  }
  @MainActor func testCanvasGesturesOffscreenControlsAndMenuBindings()async throws {
    let s=try store();defer{s.cancelSkyReplacement();s.renderTask?.cancel()};s.beginSkyReplacement();let draft=try XCTUnwrap(s.skyWorkspace);await settle(draft)
    let canvas=SkyCanvasView(frame:.init(x:0,y:0,width:640,height:480));canvas.model=draft
    func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double)throws->NSEvent{let r=canvas.imageRect,p=CGPoint(x:r.minX+x*r.width/64,y:r.minY+y*r.height/48);return try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(p,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))}
    canvas.mouseDown(with:try event(.leftMouseDown,10,10));canvas.mouseDragged(with:try event(.leftMouseDragged,14,12));canvas.mouseUp(with:try event(.leftMouseUp,14,12));await settle(draft)
    XCTAssertEqual(draft.state.settings.offsetX,4,accuracy:0.001);XCTAssertEqual(draft.undoStates.count,1)
    draft.tool = .brush;draft.add=false;draft.size=10;draft.hardness=1
    canvas.mouseDown(with:try event(.leftMouseDown,8,8));canvas.mouseDragged(with:try event(.leftMouseDragged,12,8));canvas.mouseUp(with:try event(.leftMouseUp,12,8));await settle(draft);XCTAssertEqual(draft.state.strokes.count,1)
    draft.size = .nan;draft.beginStroke(.init(10,10),alternate:false);XCTAssertNil(draft.stroke);draft.size=40;draft.error=nil
    let host=NSHostingView(rootView:SkySheet(store:s,model:draft));let window=NSWindow(contentRect:.init(x:0,y:0,width:1150,height:740),styleMask:[.titled],backing:.buffered,defer:false);window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil};host.frame = .init(x:0,y:0,width:1150,height:740);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.width,950)
    if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);let path=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/sky-workspace-offscreen.png");try bitmap.representation(using:.png,properties:[:])?.write(to:path)}
    try PhotoshopMenuTests().withMenus{_,menu in let items=PhotoshopMenuTests().allItems(menu);XCTAssertTrue(items.contains{$0.title=="Sky" && $0.action==#selector(AppDelegate.selectSky)});XCTAssertTrue(items.contains{$0.title=="Sky Replacement…" && $0.action==#selector(AppDelegate.skyReplacement)})}
  }
  @MainActor func testAPISelectionAndReplacementEqualNative()async throws {
    let helper=AutomationTests(),library=try library()
    try await helper.withService(skies:library,pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.photo());try service.share(document);let original=s.document
      let command=try SkyReplacementInput.selection(original,layerID:original.activeLayerID);var native=EditorSession(document:original);try native.execute(command)
      let responseCode1=try await helper.edit(service,document,"selection.sky");XCTAssertEqual(responseCode1,200);XCTAssertTrue(s.document==native.document)
      _=await s.requestHistory(redo:false).value
      for output in SkyOutput.allCases{
        s.session=EditorSession(document:original);var p=self.settings();p.output=output;p.temperature=20;p.brightness=10;p.flip=true
        let preset=library.skies[0],expected=try SkyReplacementInput.prepare(original).edit(sky:preset.document(),name:preset.name,settings:p).edit.result
        let status=try await helper.edit(service,document,"sky.replace",["skyID":preset.id.uuidString,"settings":BrushAPI.json(p)])
        XCTAssertEqual(status,200);XCTAssertEqual(try Renderer.composite(s.document),try Renderer.composite(expected));XCTAssertEqual(s.document.layers.map(\.name),expected.layers.map(\.name));XCTAssertEqual(s.document.layers.map(\.mask),expected.layers.map(\.mask));XCTAssertEqual(s.document.layers.map(\.affine),expected.layers.map(\.affine));XCTAssertEqual(s.session.undoStack.count,1)
        _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
      }
      let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.skyState));XCTAssertNoThrow(try BrushAPI.merge(raw,schema:SkyAPI.stateSchema))
    }
  }
  @MainActor func testManualMaskLayerSourceAndSelectionModesThroughAPI()async throws {
    let helper=AutomationTests()
    try await helper.withService(skies:try library(),pressedMouseButtons:{0}){service,document in
      var original=try self.photo();var source=try self.sky().layers[0];source.visible=false;source.name="Layer sky";original.layers.append(source)
      original.selection = .init(x:0,y:0,width:64,height:20)
      let s=document.store;s.session=EditorSession(document:original);try service.share(document)
      let stroke=SkyMaskStroke(points:[.init(x:8,y:8)],size:12,hardness:1,opacity:1,add:false),p=self.settings()
      let sourceDocument=try SkyWorkspace.sourceLayer(source.id,in:original)
      let expected=try SkyReplacementInput.prepare(original).edit(sky:sourceDocument,name:sourceDocument.name,settings:p,strokes:[stroke],detected:original.coverageSelection()).edit.result
      let code=try await helper.edit(service,document,"sky.replace",["sourceLayerID":source.id.uuidString,"useSelection":true,"settings":BrushAPI.json(p),"strokes":[["points":[["x":8,"y":8]],"size":12,"hardness":1,"opacity":1,"add":false]]])
      XCTAssertEqual(code,200);XCTAssertEqual(try Renderer.composite(s.document),try Renderer.composite(expected));XCTAssertEqual(s.document.selection,original.selection);XCTAssertEqual(s.document.layers.map(\.mask),expected.layers.map(\.mask))
      _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
      for mode in [SelectionMode.add,.subtract,.intersect] {
        s.session=EditorSession(document:original);var expected=EditorSession(document:original)
        try expected.execute(SkyReplacementInput.selection(original,layerID:original.activeLayerID,allLayers:false,mode:mode))
        let code=try await helper.edit(service,document,"selection.sky",["layerID":original.activeLayerID!.uuidString,"sampleAllLayers":false,"mode":mode.rawValue.lowercased()])
        XCTAssertEqual(code,200);XCTAssertTrue(s.document==expected.document)
      }
    }
  }
  @MainActor func testDocumentReplacementCloseAndRecordedSelection()async throws {
    let document=CraftNSDocument(model:try photo(),actions:ActionLibrary(),brushes:BrushLibrary(),skies:try library()),s=document.store
    defer{document.close();s.renderTask?.cancel()}
    let original=s.document;try s.session.startActionRecording(name:"Sky selection");s.selectSky();await s.geometryTask?.value
    let action=try XCTUnwrap(s.session.actionRecording?.snapshot);var replay=original;try action.apply(to:&replay);XCTAssertTrue(replay==s.document)
    let replacement=try SkyReplacementInput.prepare(original).edit(sky:sky(),name:"Sky",settings:settings()).edit
    if case .unsupported = ActionOperation(recording:.skyReplacement(replacement),in:original) {} else { XCTFail("Replacement recording must remain explicit until supported") }
    s.beginSkyReplacement();let first=try XCTUnwrap(s.skyWorkspace)
    var loaded=try photo();loaded.name="Reopened"
    try document.read(from:NativeArchive.encodeChunked(loaded),ofType:CraftNSDocument.nativeType);await settle(first)
    XCTAssertNil(s.skyWorkspace);XCTAssertFalse(first.ready);XCTAssertTrue(s.document==loaded);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginSkyReplacement();let last=try XCTUnwrap(s.skyWorkspace);document.close();await settle(last)
    XCTAssertNil(s.skyWorkspace);XCTAssertFalse(last.ready);XCTAssertTrue(s.document==loaded)
  }
  @MainActor func testLibraryPersistenceImportExportAndInvalidAPI()async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),url=directory.appendingPathComponent("skies.plist");defer{try? FileManager.default.removeItem(at:directory)}
    let library=SkyLibrary(persistenceURL:url),helper=AutomationTests(),data=try RasterIO.encoded(sky())
    try await helper.withService(skies:library,pressedMouseButtons:{0}){service,document in
      try service.share(document);let original=document.store.document,revision=service.revision(document.store)
      let responseCode2=try await helper.edit(service,document,"sky.library",["operation":"import","name":"Sunset","data":data.base64EncodedString()]);XCTAssertEqual(responseCode2,200)
      XCTAssertNotEqual(service.revision(document.store),revision);XCTAssertTrue(document.store.document==original);XCTAssertEqual(library.skies.count,1);XCTAssertEqual(SkyLibrary(persistenceURL:url).skies,library.skies)
      let id=library.skies[0].id,share=try XCTUnwrap(service.shares.first?.id)
      let response=try await helper.request(service,path:"/v1/documents/\(share)/commands",body:["command":"sky.library","revision":service.revision(document.store),"parameters":["operation":"export","skyID":id.uuidString]])
      let body=try JSONSerialization.jsonObject(with:response.1) as! [String:Any];XCTAssertEqual(body["data"] as? String,data.base64EncodedString())
      let responseCode3=try await helper.edit(service,document,"sky.library",["operation":"rename","skyID":id.uuidString,"name":"Evening"]);XCTAssertEqual(responseCode3,200)
      let responseCode4=try await helper.edit(service,document,"sky.library",["operation":"delete","skyID":id.uuidString]);XCTAssertEqual(responseCode4,200);XCTAssertTrue(library.skies.isEmpty)
      for params:[String:Any] in [["operation":"import","name":"Bad","data":"invalid"],["operation":"list","name":"irrelevant"],["operation":"rename","skyID":id.uuidString,"name":false]]{let status=try await helper.edit(service,document,"sky.library",params);XCTAssertGreaterThanOrEqual(status,400)}
    }
    try Data("invalid".utf8).write(to:url);let bad=SkyLibrary(persistenceURL:url);XCTAssertNotNil(bad.loadError);XCTAssertThrowsError(try bad.add(.init(name:"Sky",data:data)));XCTAssertEqual(try Data(contentsOf:url),Data("invalid".utf8))
  }
  @MainActor func testAPIRejectsInvalidBusyStaleAndRevokedWork()async throws {
    let helper=AutomationTests(),library=try library()
    try await helper.withService(skies:library,pressedMouseButtons:{0}){service,document in
      let s=document.store;s.session=EditorSession(document:try self.photo(width:600,height:400));try service.share(document);let original=s.document,id=library.skies[0].id.uuidString
      for params:[String:Any] in [["skyID":id,"settings":["scale":true]],["skyID":id,"settings":["unknown":1]],["skyID":id,"useSelection":true],["skyID":id,"sourceLayerID":s.activeLayer!.id.uuidString],["skyID":id,"strokes":[["points":[],"size":20]]]]{let status=try await helper.edit(service,document,"sky.replace",params);XCTAssertGreaterThanOrEqual(status,400);XCTAssertTrue(s.document==original)}
      let responseCode5=try await helper.edit(service,document,"sky.replace",["skyID":id],revision:"stale");XCTAssertEqual(responseCode5,409)
      s.beginSkyReplacement();let responseCode6=try await helper.edit(service,document,"selection.sky");XCTAssertEqual(responseCode6,409);s.cancelSkyReplacement()
      let task=Task{try await helper.edit(service,document,"sky.replace",["skyID":id])}
      for _ in 0..<300 where !s.geometryBusy{try await Task.sleep(for:.milliseconds(2))};XCTAssertTrue(s.geometryBusy);service.revoke(try XCTUnwrap(service.shares.first?.id))
      let responseCode7=try await task.value;XCTAssertEqual(responseCode7,409);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
}
