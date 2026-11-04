import AppKit
import Foundation
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

@MainActor private final class LightingCursorWindow:NSWindow {override var isKeyWindow:Bool{true}}

final class LightingWorkflowTests:XCTestCase {
  actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data){self.data=data}
    func fetch(_ url:URL)async throws->Data{data}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Owned hosted-output test only.")}
  }
  func fixture(_ depth:PixelDepth = .u8,smart:Bool=false)throws->CraftDocument {try BlurGalleryWorkflowTests().fixture(depth,smart:smart)}
  func filter()->RasterFilter {var f=RasterFilter(.lightingEffects);f.lighting?.lights[0].angle = -110;f.lighting?.exposure = -35;f.lighting?.lights[0].intensity=70;return f}
  func source(_ name:String)throws->Data {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/Lighting")
    return try Data(contentsOf:folder.appendingPathComponent(name))
  }
  @MainActor func testNativePreviewLocalHistoryCancelCommitAndReeditAtAllDepths()async throws {
    _ = NSApplication.shared
    for depth in PixelDepth.allCases {
      let d=try fixture(depth,smart:true),id=d.layers[0].id,store=EditorStore(document:d,actions:ActionLibrary())
      defer{store.cancelFilter();store.renderTask?.cancel()}
      store.beginFilter(.lightingEffects);XCTAssertEqual(store.filterDraft?.preview,false)
      let model=LightingWorkspace();store.lightingWorkspace=model;await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft))
      XCTAssertTrue(model.ready,model.error ?? "Preview not ready");XCTAssertTrue(store.document==d);XCTAssertTrue(store.session.undoStack.isEmpty)
      let initial=model.state;model.beginGesture();model.change(try XCTUnwrap(filter().lighting));var settings=model.settings;settings.exposure=20;model.change(settings);model.endGesture()
      XCTAssertEqual(model.undoStates.count,1);let changed=model.state;model.undo();XCTAssertEqual(model.state,initial);model.redo();XCTAssertEqual(model.state,changed);await model.task?.value;XCTAssertTrue(model.ready)
      var invalid=settings;invalid.lights[0].intensity=101;model.change(invalid);XCTAssertNotNil(model.error);XCTAssertEqual(model.state,changed);model.change(settings);await model.task?.value;XCTAssertTrue(model.ready)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:model.apiState))
      store.filterDraft?.filter.lighting=model.settings;store.commitFilter();await store.geometryTask?.value
      XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);let committed=store.document,item=try XCTUnwrap(committed.layers[0].smartFilters?.filters.first)
      var expected=d,f=RasterFilter(.lightingEffects);f.lighting=settings;try Command.applyFilter(id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=item.id
      XCTAssertTrue(committed==expected);XCTAssertEqual(try Renderer.composite(committed),try Renderer.composite(expected))
      store.beginSmartFilter(id,filterID:item.id);let reedit=LightingWorkspace();store.lightingWorkspace=reedit;await reedit.prepare(document:committed,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(reedit.ready);XCTAssertEqual(reedit.settings,settings)
      reedit.beginGesture();reedit.blending(opacity:0.3,mode:.multiply);reedit.blending(opacity:0.4,mode:.screen);reedit.endGesture();let blend=reedit.state;XCTAssertEqual(reedit.undoStates.count,1)
      reedit.undo();XCTAssertEqual(reedit.opacity,1);XCTAssertEqual(reedit.mode,.normal);reedit.redo();XCTAssertEqual(reedit.state,blend)
      reedit.change(.init());XCTAssertEqual(reedit.settings,LightingSettings());reedit.undo();XCTAssertEqual(reedit.state,blend)
      let pending=reedit.task;store.cancelFilter();await pending?.value;XCTAssertTrue(store.document==committed);XCTAssertEqual(store.session.undoStack.count,1)
      await store.undo();XCTAssertTrue(store.document==d);await store.redo();XCTAssertTrue(store.document==committed)
    }
  }
  @MainActor func testScaledPreviewRestartAndCancellationDiscardOldState()async throws {
    var d=try CraftDocument(width:300,height:220);d.layers[0].content = .raster(try Surface(width:300,height:220,fill:Pixel(0.4,0.6,0.2,1)))
    let model=LightingWorkspace(),draft=FilterDraft(id:d.layers[0].id,filter:.init(.lightingEffects));await model.prepare(document:d,draft:draft)
    XCTAssertTrue(model.ready,model.error ?? "Scaled preview not ready");XCTAssertEqual(model.image?.width,192);XCTAssertEqual(model.image?.height,140)
    model.change(try XCTUnwrap(filter().lighting));let pending=model.task;model.close();await pending?.value;XCTAssertFalse(model.rendering)
    let small=try fixture(.f32);await model.prepare(document:small,draft:.init(id:small.layers[0].id,filter:.init(.lightingEffects)))
    XCTAssertTrue(model.ready,model.error ?? "Restart not ready");XCTAssertEqual(model.image?.width,40);XCTAssertEqual(model.image?.height,32);XCTAssertEqual(model.settings,LightingSettings());XCTAssertTrue(model.undoStates.isEmpty);XCTAssertTrue(model.redoStates.isEmpty)
    let oldImage=model.image;for angle in [20.0,40,80]{var s=model.settings;s.lights[0].angle=angle;model.change(s)};await model.task?.value
    XCTAssertTrue(model.ready);XCTAssertEqual(model.settings.lights[0].angle,80);XCTAssertNotNil(oldImage)
    let view=NSHostingView(rootView:LightingSheet(store:EditorStore(document:small,actions:ActionLibrary()),model:model));view.frame=NSRect(x:0,y:0,width:720,height:500);view.layoutSubtreeIfNeeded();XCTAssertGreaterThanOrEqual(view.fittingSize.width,700);model.close()
  }
  @MainActor func testNativeAndHTTPFiltersSmartBlendingHistoryAndAtomicGuards()async throws {
    let helper=AutomationTests()
    try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      for depth in PixelDepth.allCases {for smart in [false,true] {
        let d=try self.fixture(depth,smart:smart),id=d.layers[0].id,f=self.filter();document.store.session=EditorSession(document:d);document.store.selectedLayerIDs=[id]
        let desktop=EditorStore(document:d,actions:ActionLibrary());defer{desktop.cancelFilter();desktop.renderTask?.cancel()}
        desktop.beginFilter(.lightingEffects);desktop.filterDraft?.filter=f;desktop.commitFilter();await desktop.geometryTask?.value;XCTAssertNil(desktop.error)
        let payload:[String:Any]=["kind":"lightingEffects","lighting":BrushAPI.json(try XCTUnwrap(f.lighting))],params:[String:Any]=["layerID":id.uuidString,"filter":payload]
        let status=try await helper.edit(service,document,"filter.apply",params);XCTAssertEqual(status,200)
        var expected=desktop.document;if smart{expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(document.store.document.layers[0].smartFilters?.filters.first?.id)}
        XCTAssertTrue(document.store.document==expected);XCTAssertEqual(try Renderer.composite(document.store.document),try Renderer.composite(desktop.document));XCTAssertEqual(document.store.session.undoStack.count,1)
        var changed=document.store.document
        if smart {
          let item=try XCTUnwrap(changed.layers[0].smartFilters?.filters.first);desktop.session=EditorSession(document:changed);desktop.beginSmartFilter(id,filterID:item.id);desktop.filterDraft?.opacity=0.4;desktop.filterDraft?.blendMode = .multiply;desktop.commitFilter();await desktop.geometryTask?.value
          var stack=try XCTUnwrap(changed.layers[0].smartFilters);stack.filters[0].opacity=0.4;stack.filters[0].blendMode = .multiply
          let status=try await helper.edit(service,document,"smartFilter.set",["layerID":id.uuidString,"stack":["enabled":stack.enabled,"filters":stack.apiState["filters"]!]])
          XCTAssertEqual(status,200);XCTAssertTrue(document.store.document==desktop.document);changed=document.store.document
          let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/file.photato"
          let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"71"]);XCTAssertEqual(old.0.statusCode,422)
          let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"72"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertTrue(try NativeArchive.decode(saved.1)==changed)
        }
        let stale=try await helper.edit(service,document,"filter.apply",params,revision:"stale");XCTAssertEqual(stale,409)
        document.store.beginFilter(.lightingEffects);let busy=try await helper.edit(service,document,"filter.apply",params);document.store.cancelFilter();XCTAssertEqual(busy,409)
        let bad=try await helper.edit(service,document,"filter.apply",["layerID":id.uuidString,"filter":["kind":"lightingEffects","lighting":["gloss":101]]]);XCTAssertEqual(bad,400);XCTAssertTrue(document.store.document==changed)
        let undoCount=document.store.session.undoStack.count;for _ in 0..<undoCount{await document.store.undo()};XCTAssertTrue(document.store.session.undoStack.isEmpty);XCTAssertTrue(document.store.document==d)
        let share=try XCTUnwrap(service.shares.first);XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:service.state(share,document:document)))
      }}
    }
  }
  @MainActor func testActions27Native72SchemasAndPublishedDescriptorBoundaries()throws {
    XCTAssertEqual(AppDelegate.filterMenus["Filter > Photato > Lighting Effects…" ],.lightingEffects)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:RasterFilter.apiSchema));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:LightingSettings.apiCapabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationService.documentTransferCapabilities))
    XCTAssertEqual(LightingSettings.apiCapabilities["maximumLights"] as? Int,64)
    for depth in PixelDepth.allCases {
      let d=try fixture(depth),id=d.layers[0].id,f=filter(),operation=ActionOperation(recording:.applyFilter(id,f),in:d),action=RecordedAction(name:"Owned Lighting",steps:[.init(name:"Lighting",operation:operation)])
      let bytes=try ActionLibraryFile(actions:[action]).encoded(),decoded=try ActionLibraryFile.decode(bytes);XCTAssertEqual(decoded.version,27)
      var downgraded=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);downgraded["version"]=26;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:downgraded)))
      var replayed=d,expected=d;try decoded.actions[0].apply(to:&replayed);try Command.applyFilter(id,f).apply(to:&expected);XCTAssertTrue(replayed==expected)
      var smart=try fixture(depth,smart:true);try Command.applyFilter(smart.layers[0].id,f).apply(to:&smart);XCTAssertEqual(smart.minimumArchiveVersion,72)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encode(smart))==smart);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(smart))==smart)
      let stack=try XCTUnwrap(smart.layers[0].smartFilters),stackAction=RecordedAction(name:"Lighting stack",steps:[.init(name:"Lighting stack",operation:.filters(.active,stack))]);XCTAssertEqual(try ActionLibraryFile.decode(ActionLibraryFile(actions:[stackAction]).encoded()).version,27)
      XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psd));XCTAssertThrowsError(try DocumentIO.encode(smart,format:.psb));XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:"[{\"_obj\":\"lightingEffects\"}]"))
      let store=EditorStore(document:d,actions:ActionLibrary());defer{store.renderTask?.cancel()};XCTAssertTrue(store.canBeginFilterKind(.lightingEffects));XCTAssertEqual(store.actionState["supportedVersions"] as? [Int],Array(1...46))
    }
  }
  @MainActor func testOriginalCachedImportHTTPNoOpReeditAndSourceRetention()async throws {
    let helper=AutomationTests()
    for depth in ["u8","u16","f32"] {
      let input=try source("default-\(depth)-cached.pcraft")
      try await helper.withService(pressedMouseButtons:{0}){service,parent in
        defer{for doc in service.controller.documents where doc !== parent{(doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close()}}
        service.setDocumentTransfersEnabled(true);let upload=try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft");XCTAssertEqual(upload.0.statusCode,201)
        let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),original=document.store.document,layer=try XCTUnwrap(original.layers.first),stack=try XCTUnwrap(layer.smartFilters),item=try XCTUnwrap(stack.filters.first)
        let payload:[String:Any]=["enabled":stack.enabled,"filters":stack.apiState["filters"]!]
        let status=try await helper.edit(service,document,"smartFilter.set",["layerID":layer.id.uuidString,"stack":payload]);XCTAssertEqual(status,200);XCTAssertTrue(document.store.document==original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
        document.store.beginSmartFilter(layer.id,filterID:item.id);let model=LightingWorkspace();document.store.lightingWorkspace=model;await model.prepare(document:original,draft:try XCTUnwrap(document.store.filterDraft));XCTAssertTrue(model.ready,model.error ?? "Source preview failed");XCTAssertEqual(model.settings,item.filter.lighting)
        document.store.cancelFilter();XCTAssertTrue(document.store.document==original)
        let source=try await helper.request(service,path:"/v1/documents/\(share.id)/smart-objects/\(layer.id)/source");XCTAssertEqual(source.0.statusCode,200);XCTAssertEqual(source.1,layer.smartObject?.data);XCTAssertEqual(try self.source("default-\(depth)-cached.pcraft"),input)
      }
    }
  }
  @MainActor func testOriginalLightingResourceOutputsAndAdobeFormatBoundary()async throws {
    let helper=AutomationTests()
    for (depth,media,format) in [("u8","image/png",DocumentIO.Format.png),("f32","image/tiff",DocumentIO.Format.tiff)] {
      let input=try source("three-\(depth)-uncached.pcraft"),payload:[String:Any]=["image":["source":["url":"https://example.test/owned-lighting.pcraft"]],"options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],"outputs":[["mediaType":media,"destination":["validityPeriod":60]]]]
      try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
        service.setResourceJobsEnabled(true);let original=parent.store.document
        for route in ["/v1/action-jobs","/v2/execute-actions"] {
          let reply=try await helper.request(service,path:route,body:payload);XCTAssertEqual(reply.0.statusCode,202)
          let state=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(state["statusUrl"] as? String)))
          var terminal:[String:Any]?
          for _ in 0..<1000{let reply=try await helper.request(service,path:url.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any]);if ["succeeded","failed"].contains(value["status"] as? String ?? ""){terminal=value;break};try await Task.sleep(for:.milliseconds(10))}
          let result=try XCTUnwrap(terminal);XCTAssertEqual(result["status"] as? String,route.hasPrefix("/v1") ? "succeeded":"failed","\(result)")
          if route.hasPrefix("/v1") {
            let outputs=try XCTUnwrap((result["result"] as? [String:Any])?["outputs"] as? [[String:Any]]),destination=try XCTUnwrap(outputs.first?["destination"] as? [String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"] as? String)))
            let output=try await helper.request(service,path:url.path);XCTAssertEqual(output.0.statusCode,200);XCTAssertEqual(output.1,try DocumentIO.encode(PcraftImport.read(input),format:format))
          }
        };XCTAssertTrue(parent.store.document==original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testNamedAlphaPresetFilesLightListAndHTTPReferenceGuards()async throws {
    var d=try fixture(.f32,smart:true),mask=try Surface(width:40,height:32,depth:.f32)
    for y in 0..<32{for x in 0..<40{let v=Float(x)/39;mask.setPixel(x:x,y:y,Pixel(v,v,v,1))}}
    let channel=AlphaChannel(name:"Owned bump",pixels:mask);d.alphaChannels=[channel]
    let store=EditorStore(document:d,actions:ActionLibrary());defer{store.cancelFilter();store.renderTask?.cancel()};store.beginFilter(.lightingEffects)
    let model=LightingWorkspace();store.lightingWorkspace=model;await model.prepare(document:d,draft:try XCTUnwrap(store.filterDraft));XCTAssertTrue(model.ready)
    model.add(.point);model.add(.infinite);XCTAssertEqual(model.settings.lights.count,3);let index=try XCTUnwrap(model.duplicate(0));XCTAssertEqual(index,3);model.toggle(1);XCTAssertFalse(model.settings.lights[1].enabled);model.delete();XCTAssertEqual(model.settings.lights.count,3);model.undo();XCTAssertEqual(model.settings.lights.count,4)
    var settings=model.settings;settings.texture = .alphaChannel;settings.textureChannelID=channel.id;model.change(settings);await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "Named alpha preview")
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)};let file=folder.appendingPathComponent("Owned Lighting.json"),bytes=try settings.presetData();try bytes.write(to:file);XCTAssertEqual(try LightingSettings.decodeJSON(Data(contentsOf:file)),settings)
    let helper=AutomationTests();try await helper.withService(pressedMouseButtons:{0}){service,document in
      document.store.session=EditorSession(document:d);document.store.selectedLayerIDs=[d.layers[0].id];try service.share(document)
      let status=try await helper.edit(service,document,"filter.apply",["layerID":d.layers[0].id.uuidString,"filter":["kind":"lightingEffects","lighting":BrushAPI.json(settings)] ]);XCTAssertEqual(status,200)
      var expected=d;var f=RasterFilter(.lightingEffects);f.lighting=settings;try Command.applyFilter(d.layers[0].id,f).apply(to:&expected);expected.layers[0].smartFilters?.filters[0].id=try XCTUnwrap(document.store.document.layers[0].smartFilters?.filters.first?.id);XCTAssertTrue(document.store.document==expected)
      let before=document.store.document;var bad=settings;bad.textureChannelID=UUID();let code=try await helper.edit(service,document,"filter.apply",["layerID":d.layers[0].id.uuidString,"filter":["kind":"lightingEffects","lighting":BrushAPI.json(bad)]]);XCTAssertEqual(code,422);XCTAssertTrue(document.store.document==before)
      await document.store.undo();XCTAssertTrue(document.store.document==d)
    };XCTAssertTrue(store.document==d);XCTAssertEqual(try Data(contentsOf:file),bytes)
  }
  @MainActor func testPreviewSixteenModifierModesCapturedDragFocusAndCapacity()async throws {
    _ = NSApplication.shared;_ = CraftDocumentController(workspaces:WorkspaceLibrary())
    let document=try fixture(),model=LightingWorkspace();await model.prepare(document:document,draft:.init(id:document.layers[0].id,filter:.init(.lightingEffects)));XCTAssertTrue(model.ready)
    let view=LightingPreviewView(frame:NSRect(x:0,y:0,width:400,height:320));view.model=model
    let window=LightingCursorWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=view
    defer{view.clearCursorInput();model.close();window.contentView=nil;window.close()}
    func mouse(_ type:NSEvent.EventType,_ point:NSPoint,_ flags:NSEvent.ModifierFlags)throws->NSEvent{try XCTUnwrap(NSEvent.mouseEvent(with:type,location:view.convert(point,to:nil),modifierFlags:flags,timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1))}
    let keys:[NSEvent.ModifierFlags]=[.control,.command,.option,.shift];var rows=[[String:Any]]()
    for bits in 0..<16 {
      model.change(.init());await model.task?.value;model.selected=0;model.undoStates=[];model.redoStates=[]
      let flags=keys.enumerated().reduce(NSEvent.ModifierFlags()){$0.union(bits & (1 << $1.offset)==0 ? []:$1.element)},start=view.point(.init(light:0)),end=NSPoint(x:start.x+20,y:start.y+40),original=model.settings
      view.mouseMoved(with:try mouse(.mouseMoved,start,flags))
      let expected:ToolCursor = .symbol(flags.contains(.option) ? "plus.square.on.square":"arrow.up.and.down.and.arrow.left.and.right",flags.contains(.shift) ? .constrain:nil)
      XCTAssertEqual(view.toolCursor,expected);XCTAssertEqual(view.toolCursor,ToolCursor.lighting(modifiers:flags.subtracting([.control,.command]),hasHandle:true,canDuplicate:true))
      view.mouseDown(with:try mouse(.leftMouseDown,start,flags));view.updateCursorModifiers([]);XCTAssertEqual(view.toolCursor,expected,"Gesture keeps its captured action/cursor")
      view.mouseDragged(with:try mouse(.leftMouseDragged,end,[]));XCTAssertEqual(model.settings.lights.count,flags.contains(.option) ? 2:1)
      let light=try XCTUnwrap(model.light);if flags.contains(.shift){XCTAssertEqual(light.x,original.lights[0].x)}else{XCTAssertNotEqual(light.x,original.lights[0].x)};XCTAssertNotEqual(light.y,original.lights[0].y)
      view.mouseUp(with:try mouse(.leftMouseUp,end,[]));XCTAssertNil(view.dragging);XCTAssertNil(view.cursorGestureModifiers);XCTAssertFalse(view.cursorPointerDown);XCTAssertEqual(model.undoStates.count,1)
      model.undo();XCTAssertEqual(model.settings,original);rows.append(["modifierBits":bits,"cursor":String(describing:expected),"duplicate":flags.contains(.option),"constrain":flags.contains(.shift)])
    }
    model.change(LightingSettings.Preset.infinite.settings);await model.task?.value;model.undoStates=[];model.selected=0
    let start=view.point(.init(light:0,direction:true)),end=NSPoint(x:280,y:196);view.mouseMoved(with:try mouse(.mouseMoved,start,[.option,.shift]));view.mouseDown(with:try mouse(.leftMouseDown,start,[.option,.shift]));view.mouseDragged(with:try mouse(.leftMouseDragged,end,[]));XCTAssertEqual(try XCTUnwrap(model.light).angle.truncatingRemainder(dividingBy:15),0,accuracy:1e-9)
    view.clearCursorInput();XCTAssertNil(view.dragging);XCTAssertNil(view.cursorGestureModifiers);XCTAssertFalse(view.cursorPointerDown);XCTAssertEqual(model.undoStates.count,1)
    var full=LightingSettings();full.lights=Array(repeating:.init(),count:64);model.change(full);model.selected=0;let point=view.point(.init(light:0)),before=model.state;view.mouseMoved(with:try mouse(.mouseMoved,point,.option));XCTAssertEqual(view.toolCursor,.unavailable);view.mouseDown(with:try mouse(.leftMouseDown,point,.option));XCTAssertEqual(model.state,before);XCTAssertNil(view.dragging)
    XCTAssertTrue((ToolCursorAPI.capabilities["workspaces"] as? [String])?.contains("lightingEffects") == true)
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("lighting-modifier-matrix.json"))}
  }

}
