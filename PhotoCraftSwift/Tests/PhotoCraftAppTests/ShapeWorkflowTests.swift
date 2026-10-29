import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class ShapeWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument{var d=try CraftDocument(width:64,height:64);d.layers[0].content = .raster(try Surface(width:64,height:64));return d}
  @MainActor func store(_ d:CraftDocument)throws->EditorStore{EditorStore(document:d,patterns:PatternLibrary(),gradients:GradientLibrary(),actions:ActionLibrary(),shapes:ShapeLibrary())}
  @MainActor func testCanvasSevenToolsCommitEscapeAndGroupedShortcuts()async throws{
    let original=try fixture(),s=try store(original),canvas=CraftCanvas(store:s);canvas.frame=NSRect(x:0,y:0,width:300,height:300)
    defer{s.renderTask?.cancel()}
    func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double,_ flags:NSEvent.ModifierFlags=[])->NSEvent{NSEvent.mouseEvent(with:type,location:.init(x:x,y:y),modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!}
    for tool:EditorTool in [.rectangle,.ellipse,.triangle,.polygon,.star,.line]{
      s.tool=tool;canvas.synchronizeTool();canvas.mouseDown(with:event(.leftMouseDown,90,90));XCTAssertNotNil(s.shapeGesture);canvas.mouseDragged(with:event(.leftMouseDragged,180,170));canvas.mouseUp(with:event(.leftMouseUp,180,170));await s.geometryTask?.value
      XCTAssertNil(s.error);XCTAssertEqual(s.activeLayer?.shape?.definition?.components[0].geometry.kind,tool.shapeKind)
      XCTAssertEqual(s.session.undoStack.count,1);let undone=await s.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(s.document,original)
    }
    s.tool = .rectangle;canvas.mouseDown(with:event(.leftMouseDown,90,90));canvas.mouseDragged(with:event(.leftMouseDragged,180,170))
    canvas.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!)
    XCTAssertNil(s.shapeGesture);XCTAssertEqual(s.document,original)
    for id in ["rectangle","ellipse","triangle","polygon","star","line","customShape"]{XCTAssertEqual(WorkspaceCatalog.tool(id).shortcut,"U");XCTAssertNotNil(WorkspaceCatalog.tool(id).native)}
    let path=try ShapeGeometry(kind:.star,width:1,height:1).path(),preset=ShapePreset(name:"Native Star",path:path);try s.shapes.add(preset);s.selectedShapeID=preset.id;s.tool = .customShape
    canvas.mouseDown(with:event(.leftMouseDown,90,90));canvas.mouseUp(with:event(.leftMouseUp,180,170));await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.activeLayer?.shape?.definition?.components[0].geometry.kind,.custom)
  }
  @MainActor func testPropertiesPreviewCancelCommitPatternsAndLocalGeometry()async throws{
    var original=try fixture();try Command.shape(.create("Star",.init(geometry:.init(kind:.star,width:30,height:30)),.translation(10,10))).apply(to:&original)
    let s=try store(original);defer{s.cancelShapeProperties();s.renderTask?.cancel()}
    s.beginShapeProperties(editLayer:true);let draft=try XCTUnwrap(s.shapeDraft);draft.definition.components[0].geometry.sides=7;draft.definition.stroke.paint = .init(color:Pixel(0,0,1));draft.definition.stroke.width=4;s.refreshShapePreview()
    XCTAssertEqual(s.document,original);XCTAssertNotEqual(s.previewDocument,original);XCTAssertTrue(s.hasToneDraft);XCTAssertFalse(s.canDrawShapes)
    s.cancelShapeProperties();XCTAssertEqual(s.previewDocument,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginShapeProperties(editLayer:true);let committed=try XCTUnwrap(s.shapeDraft),pattern=try XCTUnwrap(s.patterns.selected)
    committed.definition.fill.kind = .pattern;committed.definition.fill.pattern = .init(patternID:pattern.id);s.refreshShapePreview();XCTAssertNil(committed.error)
    s.commitShapeProperties(committed);await s.geometryTask?.value;XCTAssertNil(s.error);XCTAssertNotNil(s.document.pattern(pattern.id));XCTAssertEqual(s.session.undoStack.count,1)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(s.document)),s.document)
    XCTAssertThrowsError(try DocumentIO.encode(s.document,format:.psd))
    let undone=await s.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(s.document,original)
    s.tool = .triangle;s.beginShapeProperties(editLayer:false);let template=try XCTUnwrap(s.shapeDraft);template.definition.components[0].geometry.kind = .star;s.commitShapeProperties(template);XCTAssertEqual(s.tool,.star);XCTAssertEqual(s.document,original)
  }
  @MainActor func testCompoundGestureModesAndResourceActions()async throws{
    var original=try fixture();try Command.shape(.create("Rectangle",.init(geometry:.init(width:40,height:40)),.translation(8,8))).apply(to:&original)
    let s=try store(original);defer{s.renderTask?.cancel()};s.tool = .ellipse
    s.shapeGesture = .init(original:original,start:.init(x:18,y:18),definition:try s.currentShape(),mode:.shape,target:s.activeLayer!.id,operation:.subtract,end:.init(x:38,y:38));s.finishShapeGesture();await s.geometryTask?.value
    XCTAssertNil(s.error);XCTAssertEqual(s.activeLayer?.shape?.definition?.components.count,2);XCTAssertEqual(try Renderer.composite(s.document).pixel(x:28,y:28).a,0)
    let presetID=try s.defineShape(name:"Hole");XCTAssertEqual(try VectorRasterizer.filledPath(s.shapes.preset(presetID).path).contains(.init(x:0.5,y:0.5)),false)
    let definition=ShapeDefinition(geometry:.init(kind:.triangle,width:18,height:20),fill:.init(color:Pixel(1,0,0)))
    for mode in [ShapeOutputMode.path,.pixels]{let native=try store(fixture());defer{native.renderTask?.cancel()};native.shapeGesture = .init(original:native.document,start:.init(x:5,y:5),definition:definition,mode:mode,target:native.activeLayer!.id,operation:nil,end:.init(x:23,y:25));native.finishShapeGesture();await native.geometryTask?.value;XCTAssertNil(native.error);XCTAssertEqual(native.session.undoStack.count,1);if mode == .path{XCTAssertNotNil(native.document.paths?.first)}else{XCTAssertGreaterThan(try Renderer.composite(native.document).pixel(x:14,y:15).a,0)}}
    let pattern=try XCTUnwrap(s.patterns.selected);var painted=definition;painted.fill.kind = .pattern;painted.fill.pattern = .init(patternID:pattern.id)
    let command=Command.shape(.create("Pattern",painted,.identity,patterns:[pattern])),operation=ActionOperation(recording:command,in:try fixture())
    var target=try fixture();let action=RecordedAction(name:"Shape",steps:[.init(name:"Draw",operation:operation)]);try action.apply(to:&target);XCTAssertNotNil(target.pattern(pattern.id));XCTAssertEqual(target.layers.last?.shape?.definition,painted)
  }
  @MainActor func testLibraryRoundTripCorruptPreservationAndMenuBindings()throws{
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("Shapes.photatoshapes"),library=ShapeLibrary(persistenceURL:url),preset=ShapePreset(name:"Triangle",path:try ShapeGeometry(kind:.triangle,width:1,height:1).path())
    try library.add(preset);XCTAssertEqual(ShapeLibrary(persistenceURL:url).shapes,[preset]);try library.importData(library.export());XCTAssertEqual(library.shapes.count,2);XCTAssertNotEqual(library.shapes[0].id,library.shapes[1].id)
    try library.rename(preset.id,"Triangle 1");try library.remove(preset.id);XCTAssertEqual(library.shapes.count,1)
    let bad=Data("not shapes".utf8);try bad.write(to:url);let broken=ShapeLibrary(persistenceURL:url);XCTAssertNotNil(broken.loadError);XCTAssertThrowsError(try broken.add(preset));XCTAssertEqual(try Data(contentsOf:url),bad)
    try PhotoshopMenuTests().withMenus{app,menu in let items=PhotoshopMenuTests().allItems(menu);XCTAssertEqual(items.first{$0.identifier?.rawValue=="Window > Shapes"}?.action,#selector(AppDelegate.showShapes));XCTAssertEqual(items.first{$0.identifier?.rawValue=="Edit > Define Custom Shape…"}?.action,#selector(AppDelegate.defineCustomShape));_ = app}
  }
  @MainActor func testAPIEditingMatchesDesktopRejectsBusyStaleInvalidAndArchiveNegotiation()async throws{
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),shapes:ShapeLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let definition=ShapeDefinition(geometry:.init(kind:.star,width:3,height:3),fill:.init(color:Pixel(1,0,0))),params:[String:Any]=["operation":"create","definition":BrushAPI.json(definition)]
      let initial=document.store.document
      let created=try await helper.edit(service,document,"shape.edit",params);XCTAssertEqual(created,200)
      let before=document.store.document,id=try XCTUnwrap(before.activeLayerID);XCTAssertEqual(before.layers.last?.shape?.definition,definition)
      var modified=definition;modified.stroke.paint = .init(color:Pixel(0,0,1));modified.stroke.width=1
      var expected=before;try Command.shape(.configure(id,modified)).apply(to:&expected)
      let configure:[String:Any]=["operation":"configure","layerID":id.uuidString,"definition":BrushAPI.json(modified)]
      let changed=try await helper.edit(service,document,"shape.edit",configure);XCTAssertEqual(changed,200);XCTAssertEqual(document.store.document,expected)
      let undone=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undone,200);XCTAssertEqual(document.store.document,before)
      let stale=try await helper.edit(service,document,"shape.edit",configure,revision:"stale");XCTAssertEqual(stale,409)
      document.store.beginShapeProperties(editLayer:true);let busy=try await helper.edit(service,document,"shape.edit",configure);XCTAssertEqual(busy,409);document.store.cancelShapeProperties()
      var malformed=configure;var bad=BrushAPI.json(modified) as! [String:Any];bad["typo"]=true;malformed["definition"]=bad
      let invalid=try await helper.edit(service,document,"shape.edit",malformed);XCTAssertEqual(invalid,400);XCTAssertEqual(document.store.document,before)
      let path="/v1/documents/\(service.shares.first!.id)/file.photato"
      let old=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"32"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:path,headers:["X-Photato-Archive-Version":"33"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),before)
      let config=try await helper.edit(service,document,"shape.configure",["definition":BrushAPI.json(definition),"mode":"path","combine":NSNull()]);XCTAssertEqual(config,200);XCTAssertEqual(document.store.tool,.star);XCTAssertEqual(document.store.shapeMode,.path);XCTAssertEqual(document.store.document,before)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,initial)
    }
  }
  @MainActor func testAllPaintSchemasModesAndLibraryAPIWithoutPersistentChanges()async throws{
    for kind in ShapePaint.Kind.allCases{
      var definition=ShapeDefinition(geometry:.init(kind:.ellipse,width:3,height:3));definition.fill.kind=kind
      if kind == .gradient{definition.fill.gradient = .init()};if kind == .pattern{definition.fill.pattern = .init(patternID:"test")}
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONEncoder().encode(definition));XCTAssertEqual(try ShapeAPI.decode(ShapeDefinition.self,value,schema:ShapeAPI.definition,base:.init(geometry:.init())),definition)
    }
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),shapes:ShapeLibrary(),pressedMouseButtons:{0}){service,document in
      try service.share(document)
      let def=ShapeDefinition(geometry:.init(kind:.triangle,width:3,height:3)),before=document.store.document
      for mode in ["path","pixels"]{let status=try await helper.edit(service,document,"shape.edit",["operation":"create","definition":BrushAPI.json(def),"mode":mode]);XCTAssertEqual(status,200);let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,before)}
      let listed=try await helper.edit(service,document,"shape.library",["operation":"list"]);XCTAssertEqual(listed,200)
      let preset=ShapePreset(name:"API Triangle",path:try ShapeGeometry(kind:.triangle,width:1,height:1).path()),payload=try JSONEncoder().encode(ShapeLibrary.File(shapes:[preset])).base64EncodedString()
      let imported=try await helper.edit(service,document,"shape.library",["operation":"import","data":payload]);XCTAssertEqual(imported,200);XCTAssertEqual(document.store.shapes.shapes,[preset])
      let configured=try await helper.edit(service,document,"shape.configure",["presetID":preset.id.uuidString]);XCTAssertEqual(configured,200);XCTAssertEqual(document.store.tool,.customShape)
      let renamed=try await helper.edit(service,document,"shape.library",["operation":"rename","presetID":preset.id.uuidString,"name":"Renamed"]);XCTAssertEqual(renamed,200)
      let exported=try await helper.edit(service,document,"shape.library",["operation":"export","presetID":preset.id.uuidString]);XCTAssertEqual(exported,200)
      let deleted=try await helper.edit(service,document,"shape.library",["operation":"delete","presetID":preset.id.uuidString]);XCTAssertEqual(deleted,200);XCTAssertTrue(document.store.shapes.shapes.isEmpty);XCTAssertNil(document.store.selectedShapeID)
      XCTAssertEqual(document.store.document,before);XCTAssertTrue(document.store.session.undoStack.isEmpty)

      let state=service.state(service.shares.first!,document:document);XCTAssertNotNil(state["shapes"])
      for name in ShapeAPI.commands{XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:AutomationCommand.definitions.first{$0.name==name}!.schema))}
    }
  }
  @MainActor func testOffscreenPropertiesAndPresetPanel()async throws{
    var document=try fixture();var definition=ShapeDefinition(geometry:.init(kind:.star,width:42,height:42),fill:.init(color:Pixel(1,0.55,0.12)));definition.stroke.paint = .init(color:Pixel(0.12,0.38,0.7));definition.stroke.width=3
    try Command.shape(.create("Star",definition,.translation(10,10))).apply(to:&document)
    let s=try store(document);defer{s.cancelShapeProperties();s.renderTask?.cancel()};_=try s.defineShape(name:"Native Star");s.beginShapeProperties(editLayer:true)
    let host=NSHostingView(rootView:ShapeSheet(store:s,draft:try XCTUnwrap(s.shapeDraft))),window=NSWindow(contentRect:.init(x:0,y:0,width:600,height:700),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil};host.frame = .init(x:0,y:0,width:600,height:700);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));window.displayIfNeeded();capture(host,"shapes-properties-offscreen")
    s.cancelShapeProperties();let presets=NSHostingView(rootView:ShapesPanel(store:s));presets.frame = .init(x:0,y:0,width:360,height:460);window.contentView=presets;presets.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));window.displayIfNeeded();capture(presets,"shapes-presets-offscreen")
    await s.renderTask?.value;s.zoom=5;let canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:400,height:400);capture(canvas,"shapes-canvas-offscreen")
    XCTAssertNotNil(s.image)
  }
  @MainActor func capture(_ view:NSView,_ name:String){
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/\(name).png"))}
  }

}
