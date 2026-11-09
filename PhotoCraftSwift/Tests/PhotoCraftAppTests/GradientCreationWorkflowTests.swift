import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class GradientCreationWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:32,height:24,depth:depth)
    var source=try Surface(width:32,height:24,depth:depth,fill:Pixel(0.2,0.4,0.7,0.6))
    source.setPixel(x:8,y:8,.white);d.layers[0].content = .raster(source)
    return d
  }
  func fill()throws->GradientFill {
    var f=GradientFill(gradient:.init(colors:[.init(0,.rgb(Pixel(0.1,0.3,0.7))),.init(1,.rgb(Pixel(0.9,0.2,0.1)))],opacity:[.init(0,1),.init(1,0.25)],method:.classic),aligned:false,dither:false)
    try f.placement.setHandles(start:.init(3,12),end:.init(29,12),in:.init(x:0,y:0,width:32,height:24));return f
  }
  func withFill()throws->CraftDocument {
    var d=try fixture();try Command.addGradientFill(Layer(name:"Existing",content:.gradientFill(try fill())),false).apply(to:&d);return d
  }
  @MainActor func testOptionsAreCreationDefaultsAndFutureCanvasFillUsesThemWithoutEditingExisting()async throws {
    let d=try withFill(),store=EditorStore(document:d,gradients:GradientLibrary());defer{store.cancelGradientGesture();store.renderTask?.cancel()}
    store.tool = .gradient;await store.renderTask?.value;let before=try NativeArchive.encode(d)
    store.changeGradientOption(\.style,.radial);store.changeGradientOption(\.reverse,true);store.changeGradientOption(\.dither,false)
    store.changeGradientOption(\.opacity,Float(0.35));store.changeGradientOption(\.blend,BlendMode.multiply);store.changeGradientMethod(.linear)
    XCTAssertEqual(store.document,d);XCTAssertEqual(try NativeArchive.encode(store.document),before);XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(store.activeGradientWidget?.fill.placement.style,.linear);XCTAssertEqual(store.activeGradientWidget?.fill.gradient.method,.classic)
    let raster=Layer(name:"New target",content:.raster(try Surface(width:32,height:24)))
    store.perform(.addLayer(raster));store.select(raster.id);await store.renderTask?.value
    store.beginGradient(at:.init(4,6),zoom:2);store.dragGradient(to:.init(25,17));store.finishGradient()
    await store.geometryTask?.value;await store.renderTask?.value
    guard let layer=store.activeLayer,case .gradientFill(let made)=layer.content else{return XCTFail("Missing live gradient")}
    XCTAssertEqual(made.placement.style,.radial);XCTAssertTrue(made.placement.reverse);XCTAssertFalse(made.dither)
    XCTAssertEqual(made.gradient.method,.linear);XCTAssertEqual(layer.opacity,0.35);XCTAssertEqual(layer.blendMode,.multiply)
    XCTAssertEqual(store.document.layers.first{$0.id==d.activeLayerID},d.layers.first{$0.id==d.activeLayerID})
    XCTAssertNil(store.error)
  }
  @MainActor func testToolbarPresetChangesOnlyDefaultsAndDropsDelayedToolOrOptionsChanges()async throws {
    let d=try withFill(),library=GradientLibrary(),store=EditorStore(document:d,gradients:library);defer{store.renderTask?.cancel()}
    store.tool = .gradient;let id=try XCTUnwrap(library.state.presetIDs.dropFirst().first)
    store.chooseGradientPreset(id,creationOnly:true);await store.gradientLibraryTask?.value
    XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(store.gradientOptions.gradient,library.state.presets[id]?.gradient)
    try store.setGradientCreationOptions(.init());let original=store.gradientOptions.gradient
    store.chooseGradientPreset(id,creationOnly:true);store.changeGradientOption(\.opacity,Float(0.4));await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradientOptions.gradient,original);XCTAssertEqual(store.gradientOptions.opacity,0.4)
    store.chooseGradientPreset(id,creationOnly:true);store.tool = .move;await store.gradientLibraryTask?.value
    XCTAssertEqual(store.gradientOptions.gradient,original);XCTAssertEqual(store.document,d)
    store.tool = .gradient;store.chooseGradientPreset(id);await store.gradientLibraryTask?.value;await store.geometryTask?.value
    XCTAssertNotEqual(store.document,d);XCTAssertEqual(store.session.undoStack.count,1)
    await store.undo();XCTAssertEqual(store.document,d)
  }
  @MainActor func testGradientAndStopColorCapturedSourcesRejectSessionDocumentAndToolReplacement()async throws {
    for changed in 0..<3 {
      let d=try withFill(),store=EditorStore(document:d);defer{store.cancelGradientGesture();store.renderTask?.cancel()};store.tool = .gradient
      let widget=try XCTUnwrap(store.activeGradientWidget)
      store.beginGradient(at:widget.end,zoom:4);store.dragGradient(to:.init(25,20))
      var expected=d
      if changed==0{store.session=EditorSession(document:d)}
      if changed==1{store.tool = .move}
      if changed==2{try Command.opacity(d.layers[0].id,0.3).apply(to:&expected);store.session=EditorSession(document:expected)}
      store.finishGradient();await store.geometryTask?.value;await store.renderTask?.value
      XCTAssertEqual(store.document,expected);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
    let d=try withFill(),store=EditorStore(document:d);defer{store.renderTask?.cancel()};store.tool = .gradient
    let widget=try XCTUnwrap(store.activeGradientWidget);store.beginGradient(at:widget.start,zoom:4,clickCount:2);store.finishGradient()
    XCTAssertNotNil(store.gradientStopColorDraft);store.gradientStopColorDraft?.fill.gradient.colors[0].color = .rgb(.white)
    store.session=EditorSession(document:d);store.finishGradientStopColor(apply:true);await store.geometryTask?.value;await store.renderTask?.value
    XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPConfigurationMatchesNativeAtomicDefaultsAndReadSchemasWithoutHistory()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.withFill(),store=document.store;store.session=EditorSession(document:d);try service.share(document);await store.renderTask?.value
      let native=EditorStore(document:d);defer{native.renderTask?.cancel()};let revision=service.revision(store)
      native.changeGradientOption(\.style,.diamond);native.changeGradientOption(\.reverse,true);native.changeGradientOption(\.opacity,Float(0.6));native.changeGradientMethod(.linear)
      let status=try await h.edit(service,document,"gradient.tool.configure",["options":["style":"Diamond","reverse":true,"opacity":0.6,"gradient":["method":"Linear"]]])
      XCTAssertEqual(status,200);XCTAssertEqual(store.gradientOptions,native.gradientOptions);XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNotEqual(service.revision(store),revision)
      let stale=try await h.edit(service,document,"gradient.tool.configure",["reset":true],revision:revision);XCTAssertEqual(stale,409)
      let reset=try await h.edit(service,document,"gradient.tool.configure",["reset":true]);XCTAssertEqual(reset,200);XCTAssertEqual(store.gradientOptions,GradientToolOptions())
      let state=try XCTUnwrap(GradientToolAPI.state(store)["options"]as?[String:Any]);XCTAssertNotNil(state["gradient"])
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:GradientToolAPI.capabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:GradientToolAPI.stateSchema))
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,61)
    }
  }
  @MainActor func testHTTPFillCreationParentMaskPlacementArchiveAndUndoAtAllDepths()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for depth in PixelDepth.allCases {
        var d=try self.fixture(depth);let group=Layer(name:"Group",content:.group(.init()));d.layers.append(group);d.activeLayerID=group.id
        var coverage=try Surface(width:d.width,height:d.height,fill:.black);try coverage.mapPixels(in:.init(x:4,y:3,width:22,height:17)){_,_,_ in Pixel(0.5,0.5,0.5)}
        d.setCoverageSelection(try SelectionMask(coverage:coverage));document.store.session=EditorSession(document:d)
        let f=try self.fill(),status=try await h.edit(service,document,"gradient.fill.create",["fill":BrushAPI.json(f),"name":"Created gradient","opacity":0.7,"blend":"Normal"])
        XCTAssertEqual(status,200);let actual=document.store.document,new=try XCTUnwrap(actual.layers.first{!d.layers.map(\.id).contains($0.id)})
        var native=try GradientToolCommands.layer(fill:f,in:d,name:"Created gradient",parentID:group.id,opacity:0.7);native.id=new.id
        var expected=d;try Command.addGradientFill(native,true).apply(to:&expected)
        XCTAssertEqual(actual,expected);XCTAssertEqual(new.parentID,group.id);XCTAssertNotNil(new.mask)
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(actual)),actual);XCTAssertEqual(document.store.session.undoStack.count,1)
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }
    }
  }
  @MainActor func testClassicHTTPMatchesActualNativeGestureAtAllDepthsShapesAndMaskTargets()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      let gradient=try self.fill().gradient
      for depth in PixelDepth.allCases {for style in GradientStyle.allCases {for mask in [false,true] {
        var d=try self.fixture(depth);d.selection = .init(x:2,y:2,width:27,height:19)
        if mask{d.layers[0].mask=try Surface(width:d.width,height:d.height,depth:depth,fill:.white)}
        let store=EditorStore(document:d);defer{store.cancelGradientGesture();store.renderTask?.cancel()};store.tool = .gradient
        store.gradientOptions.mode = .classic;store.gradientOptions.gradient=gradient;store.gradientOptions.style=style
        store.gradientOptions.reverse=true;store.gradientOptions.dither=false;store.gradientOptions.transparency=false;store.gradientOptions.opacity=0.7;store.gradientOptions.blend = .screen
        if mask{store.maskEditingLayerID=d.layers[0].id}
        store.beginGradient(at:.init(3,4),zoom:2);store.dragGradient(to:.init(28,20));store.finishGradient();await store.geometryTask?.value;await store.renderTask?.value
        XCTAssertNil(store.error)
        document.store.session=EditorSession(document:d)
        let status=try await h.edit(service,document,"gradient.paint",["layerID":d.layers[0].id.uuidString,"stroke":["gradient":BrushAPI.json(gradient),"start":["x":3,"y":4],"end":["x":28,"y":20],"style":style.rawValue,"reverse":true,"dither":false,"transparency":false,"opacity":0.7,"mode":"Screen","mask":mask]])
        XCTAssertEqual(status,200,"\(depth)/\(style)/\(mask)");XCTAssertEqual(document.store.document,store.document)
        XCTAssertEqual(try NativeArchive.encode(document.store.document),try NativeArchive.encode(store.document))
        let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,d)
      }}}
    }
  }
  @MainActor func testHTTPGradientCreationAndPaintingRecordPortableActionsWithUndoRedo()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      var d=try self.fixture(.u16);d.selection = .init(x:3,y:2,width:24,height:19)
      let store=document.store;store.session=EditorSession(document:d);try service.share(document)
      try store.startRecordingAction(name:"Owned gradient workflow",set:"Test")
      let fill=try self.fill(),created=try await h.edit(service,document,"gradient.fill.create",["fill":BrushAPI.json(fill),"name":"Recorded gradient","opacity":0.65])
      XCTAssertEqual(created,200)
      let painted=try await h.edit(service,document,"gradient.paint",["layerID":d.layers[0].id.uuidString,"stroke":["gradient":BrushAPI.json(fill.gradient),"start":["x":2,"y":3],"end":["x":29,"y":20],"style":"Diamond","dither":false,"opacity":0.7]])
      XCTAssertEqual(painted,200);let result=store.document,action=try store.stopRecordingAction()
      XCTAssertEqual(action.steps.count,2);XCTAssertTrue(action.steps.allSatisfy{$0.operation.unsupportedReason==nil})
      let bytes=try ActionLibraryFile(actions:[action]).encoded(),loaded=try ActionLibraryFile.decode(bytes)
      XCTAssertEqual(loaded.version,51)
      for version in 1...50 {
        var old=try XCTUnwrap(try JSONSerialization.jsonObject(with:bytes)as?[String:Any]);old["version"]=version
        XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)))
      }
      var replay=d;try loaded.actions[0].apply(to:&replay)
      XCTAssertEqual(try Renderer.composite(replay),try Renderer.composite(result))
      XCTAssertEqual(replay.layers.map(\.name),result.layers.map(\.name))
      XCTAssertEqual(replay.layers[0].content,result.layers[0].content)
      for _ in 0..<2{let status=try await h.edit(service,document,"history.undo");XCTAssertEqual(status,200)}
      XCTAssertEqual(store.document,d)
      for _ in 0..<2{let status=try await h.edit(service,document,"history.redo");XCTAssertEqual(status,200)}
      XCTAssertEqual(store.document,result)
    }
  }
  @MainActor func testInvalidBusyStaleAndRevokedRequestsCannotChangePixelsOrPartialOptions()async throws {
    let h=AutomationTests();try await h.withService(actions:ActionLibrary(),pressedMouseButtons:{0}) {service,document in
      let d=try self.fixture(),store=document.store;store.session=EditorSession(document:d);try service.share(document)
      for params in [[:],["options":[:]], ["options":["opacity":2]],["options":["style":"bad"]],["options":["reverse":1]],["options":["gradient":["colors":[]]]]]as[[String:Any]] {
        let before=store.gradientOptions,status=try await h.edit(service,document,"gradient.tool.configure",params);XCTAssertEqual(status,400);XCTAssertEqual(store.gradientOptions,before)
      }
      let missing=try await h.edit(service,document,"gradient.paint",["layerID":UUID().uuidString,"stroke":["gradient":BrushAPI.json(try self.fill().gradient),"start":["x":0,"y":0],"end":["x":5,"y":5]]]);XCTAssertEqual(missing,404)
      let noMask=try await h.edit(service,document,"gradient.paint",["layerID":d.layers[0].id.uuidString,"stroke":["gradient":BrushAPI.json(try self.fill().gradient),"start":["x":0,"y":0],"end":["x":5,"y":5],"mask":true]]);XCTAssertEqual(noMask,422)
      store.tool = .gradient;store.beginGradient(at:.init(2,2),zoom:2)
      let busy=try await h.edit(service,document,"gradient.tool.configure",["reset":true]);XCTAssertEqual(busy,409);store.cancelGradientGesture();await store.renderTask?.value
      XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty)
      let share=try XCTUnwrap(service.shares.first?.id);service.revoke(share)
      let revoked=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":"gradient.tool.configure","revision":service.revision(store),"parameters":["reset":true]])
      XCTAssertEqual(revoked.0.statusCode,404);XCTAssertEqual(store.document,d)
    }
  }
}
