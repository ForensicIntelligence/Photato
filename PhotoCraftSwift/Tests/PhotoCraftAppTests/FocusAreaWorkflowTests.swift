import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
import PhotoCraftCore
import PhotoCraftImaging

final class FocusAreaWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,width:Int=128,height:Int=96)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth),p=try Surface(width:width,height:height,depth:depth)
    for y in 0..<height{for x in 0..<width{let v:Float=x<width/2 ? ((x/4+y/4)%2==0 ? 0.15:0.9):0.4+Float(x)*0.1/Float(width);p.setPixel(x:x,y:y,Pixel(v,v,v))}}
    d.layers[0].content = .raster(p);d.name="Focus test";return d
  }
  @MainActor func store()throws->EditorStore{EditorStore(document:try fixture(),actions:ActionLibrary(),brushes:BrushLibrary(),skies:SkyLibrary())}
  @MainActor func settle(_ model:SelectMaskWorkspace)async{await SelectMaskWorkflowTests().ready(model)}
  @MainActor func testPreviewAutoManualBrushHandoffCancelCommitAndHistory()async throws {
    let s=try store(),original=s.document;defer{s.cancelSelectMask();s.renderTask?.cancel()};s.beginSelectMask(focus:true);let m=try XCTUnwrap(s.selectMaskDraft);await settle(m)
    XCTAssertTrue(m.isFocus);XCTAssertTrue(m.canCommit,m.error ?? "Missing preview");XCTAssertEqual(m.title,"Focus Area");XCTAssertNotNil(m.effectiveFocus);XCTAssertTrue(s.document==original)
    let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.focusAreaState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:FocusAreaAPI.stateSchema))
    let first=try XCTUnwrap(m.refinedMask),automatic=try XCTUnwrap(m.effectiveFocus),controls=FocusAreaControls(model:m)
    controls.flag(\.autoRange).wrappedValue=false;await settle(m);XCTAssertEqual(m.state.focus?.range,automatic.range)
    controls.number(\.range,automatic:\.autoRange).wrappedValue=0;await settle(m);XCTAssertTrue(m.refinedMask!.bytes.allSatisfy{$0==255})
    m.undo();await settle(m);XCTAssertEqual(m.refinedMask,first);m.redo();await settle(m)
    m.tool = .subtract;m.size=20;m.hardness=1;m.begin(x:20,y:20,alternate:false);m.drag(x:30,y:20);m.end();await settle(m);XCTAssertEqual(m.refinedMask?.coverage(x:25,y:20),0)
    let mask=m.refinedMask;m.refineFocusEdges();await settle(m);XCTAssertFalse(m.isFocus);XCTAssertEqual(m.refinedMask,mask);XCTAssertTrue(s.document==original)
    s.cancelSelectMask();XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    s.beginSelectMask(focus:true);let final=try XCTUnwrap(s.selectMaskDraft);await settle(final);let expected=final.refinedMask
    try s.session.startActionRecording(name:"Focus");s.commitSelectMask();await final.commitTask?.value
    XCTAssertNil(final.error);XCTAssertNil(s.selectMaskDraft);XCTAssertEqual(s.document.selectionMask,expected);XCTAssertEqual(s.session.undoStack.last?.label,"Focus Area")
    var replay=original;try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==s.document)
    _=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original);_=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document.selectionMask,expected)
  }
  func testAllOutputsDepthsProfilesAndLocks()throws {
    for depth in PixelDepth.allCases{
      var original=try fixture(depth);original.layers[0].affine = .init(a:1,b:0,c:0,d:1,tx:3,ty:2)
      let input=try FocusAreaInput.prepare(original,layerID:original.layers[0].id)
      for output in SelectionRefinementOutput.allCases{
        let edit=try input.edit(settings:.init(),output:output),result=try edit.applied(to:original)
        XCTAssertEqual(result.depth,depth);XCTAssertEqual(result.workingICC,original.workingICC);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result))==result)
        if output == .selection{XCTAssertEqual(result.layers,original.layers);XCTAssertEqual(try result.coverageSelection(),edit.mask)}
        else if output == .layerMask{XCTAssertEqual(result.layers[0].content,original.layers[0].content);let sampler=try MaskSampler(layer:result.layers[0]);XCTAssertEqual(sampler.coverage(x:20.5,y:20.5),edit.mask.coverage(x:20,y:20),accuracy:0.00001)}
        else{XCTAssertEqual(result.layers.count,output.createsDocument ? 1:2);XCTAssertEqual(result.layers.last?.affine,original.layers[0].affine)}
      }
      original.layers[0].locked=true;let locked=try FocusAreaInput.prepare(original,layerID:original.layers[0].id)
      XCTAssertNoThrow(try locked.edit(settings:.init()).applied(to:original));XCTAssertThrowsError(try locked.edit(settings:.init(),output:.layerMask).applied(to:original))
      XCTAssertThrowsError(try locked.edit(settings:.init(),strokes:[.init(tool:.refine,points:[[20,20]])]))
    }
  }
  @MainActor func testNativeNewDocumentAndReadCloseCancellation()async throws {
    let controller=CraftDocumentController(workspaces:WorkspaceLibrary()),document=CraftNSDocument(model:try fixture(),actions:ActionLibrary(),skies:SkyLibrary());controller.addDocument(document)
    defer{for d in controller.documents{d.updateChangeCount(.changeCleared);d.close()}}
    let s=document.store,original=s.document;s.beginSelectMask(focus:true);let m=try XCTUnwrap(s.selectMaskDraft);await settle(m)
    var next=m.state;next.output = .newDocumentWithMask;m.change(next);await settle(m);s.commitSelectMask();await m.commitTask?.value
    XCTAssertNil(m.error);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let created=try XCTUnwrap(controller.documents.compactMap{$0 as? CraftNSDocument}.first{$0 !== document});XCTAssertNotNil(created.store.document.layers[0].mask);created.store.renderTask?.cancel();created.updateChangeCount(.changeCleared);created.close()
    s.beginSelectMask(focus:true);let reading=try XCTUnwrap(s.selectMaskDraft);var loaded=original;loaded.name="Reloaded"
    try document.read(from:NativeArchive.encodeChunked(loaded),ofType:CraftNSDocument.nativeType);await settle(reading);XCTAssertNil(s.selectMaskDraft);XCTAssertFalse(reading.ready);XCTAssertTrue(s.document==loaded)
    s.beginSelectMask(focus:true);let closing=try XCTUnwrap(s.selectMaskDraft);document.close();await settle(closing);XCTAssertNil(s.selectMaskDraft);XCTAssertFalse(closing.ready);s.renderTask?.cancel()
  }
  @MainActor func testAllAPIOutputsEqualNativeAndPreserveSource()async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}){service,document in
      let original=try self.fixture(),s=document.store;s.session=EditorSession(document:original);try service.share(document)
      var settings=FocusAreaSettings();settings.autoRange=false;settings.range=4;settings.softenEdge=true
      let stroke=SelectionRefinementStroke(tool:.subtract,size:16,hardness:1,points:[[20,20],[30,20]])
      for output in SelectionRefinementOutput.allCases{
        s.session=EditorSession(document:original)
        let params:[String:Any]=["layerID":original.layers[0].id.uuidString,"settings":BrushAPI.json(settings),"output":output.rawValue,"strokes":[["tool":"subtract","size":16,"hardness":1,"points":[[20,20],[30,20]]]]]
        if output.createsDocument && !service.documentTransfersEnabled{let denied=try await h.edit(service,document,"selection.focus",params);XCTAssertEqual(denied,403);service.setDocumentTransfersEnabled(true)}
        let expected=try FocusAreaInput.prepare(original,layerID:original.layers[0].id).edit(settings:settings,output:output,strokes:[stroke]).applied(to:original)
        let status=try await h.edit(service,document,"selection.focus",params);XCTAssertEqual(status,output.createsDocument ? 201:200)
        let target=output.createsDocument ? try XCTUnwrap(service.shares.first{$0.document !== document}?.document):document
        XCTAssertEqual(try Renderer.composite(target.store.document),try Renderer.composite(expected));XCTAssertEqual(target.store.document.layers.map(\.mask),expected.layers.map(\.mask));XCTAssertEqual(target.store.document.selectionMask,expected.selectionMask)
        if output.createsDocument{XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty);target.store.renderTask?.cancel();target.updateChangeCount(.changeCleared);target.close()}
        else{XCTAssertEqual(s.session.undoStack.count,1);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)}
      }
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.focusAreaState));XCTAssertNoThrow(try BrushAPI.merge(state,schema:FocusAreaAPI.stateSchema))
    }
  }
  @MainActor func testCurrentLayerAndCompositeSamplingIgnorePriorSelection()async throws {
    let h=AutomationTests()
    try await h.withService(skies:SkyLibrary(),pressedMouseButtons:{0}){service,document in
      var original=try self.fixture();let target=original.layers[0].id
      original.layers.append(Layer(name:"Flat cover",content:.raster(try Surface(width:128,height:96,fill:Pixel(0.5,0.5,0.5)))))
      original.selection = .init(x:20,y:20,width:2,height:2)
      let s=document.store;s.session=EditorSession(document:original);try service.share(document)
      for all in [false,true]{
        s.session=EditorSession(document:original);let expected=try FocusAreaInput.prepare(original,layerID:target,sampleAllLayers:all).edit(settings:.init()).mask
        let status=try await h.edit(service,document,"selection.focus",["layerID":target.uuidString,"sampleAllLayers":all]);XCTAssertEqual(status,200)
        if all{XCTAssertNil(s.document.selection);XCTAssertNil(expected.bounds)}else{XCTAssertEqual(s.document.selectionMask,expected);XCTAssertGreaterThan(s.document.selection!.width,2)}
        XCTAssertEqual(s.document.layers,original.layers);_=await s.requestHistory(redo:false).value;XCTAssertTrue(s.document==original)
      }
    }
  }
  @MainActor func testInvalidBusyStaleAndRevokedAPI()async throws {
    let h=AutomationTests()
    try await h.withService(skies:SkyLibrary(),pressedMouseButtons:{0}){service,document in
      let original=try self.fixture(width:600,height:400),s=document.store;s.session=EditorSession(document:original);try service.share(document)
      let params:[String:Any]=["layerID":original.layers[0].id.uuidString]
      for extra:[String:Any] in [["settings":["range":true]],["settings":["unknown":1]],["settings":["noise":2]],["output":"invalid"],["sampleAllLayers":1],["strokes":[["tool":"refine","points":[[1,1]]]]]]{let bad=params.merging(extra){_,v in v};let status=try await h.edit(service,document,"selection.focus",bad);XCTAssertEqual(status,400);XCTAssertTrue(s.document==original)}
      let stale=try await h.edit(service,document,"selection.focus",params,revision:"old");XCTAssertEqual(stale,409)
      s.beginSelectMask(focus:true);let busy=try await h.edit(service,document,"selection.focus",params);XCTAssertEqual(busy,409);s.cancelSelectMask()
      service.setDocumentTransfersEnabled(true)
      let task=Task{try await h.edit(service,document,"selection.focus",params.merging(["output":"newDocument"]){_,v in v})}
      let end=Date().addingTimeInterval(5);while !s.geometryBusy && Date()<end{await Task.yield()};XCTAssertTrue(s.geometryBusy);service.setDocumentTransfersEnabled(false)
      let cancelled=try await task.value;XCTAssertEqual(cancelled,409);XCTAssertTrue(s.document==original);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertEqual(service.shares.count,1)
    }
  }
  @MainActor func testCanvasPreviewAndFactoryMenuOffscreen()async throws {
    let s=try store();defer{s.cancelSelectMask();s.renderTask?.cancel()};s.beginSelectMask(focus:true);let m=try XCTUnwrap(s.selectMaskDraft);await settle(m)
    m.showOriginal=true;m.refresh();await settle(m);let original=try ColorManagement.displayImage(try XCTUnwrap(m.input).guide,in:s.document)
    XCTAssertEqual(m.image?.dataProvider?.data as Data?,original.dataProvider?.data as Data?);m.showOriginal=false;m.refresh();await settle(m)
    let canvas=SelectMaskCanvasView(frame:.init(x:0,y:0,width:640,height:480));canvas.model=m;m.tool = .add;m.size=15
    let rect=canvas.imageRect,point=CGPoint(x:rect.minX+100*rect.width/128,y:rect.minY+50*rect.height/96)
    func event(_ type:NSEvent.EventType)throws->NSEvent{try XCTUnwrap(NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1))}
    canvas.mouseDown(with:try event(.leftMouseDown));canvas.mouseUp(with:try event(.leftMouseUp));await settle(m);XCTAssertGreaterThan(m.refinedMask!.coverage(x:100,y:50),0.9)
    let host=NSHostingView(rootView:SelectMaskSheet(store:s,model:m)),window=NSWindow(contentRect:.init(x:0,y:0,width:1040,height:740),styleMask:[.titled],backing:.buffered,defer:false);window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil};host.frame = .init(x:0,y:0,width:1040,height:740);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.width,900)
    if let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds){host.cacheDisplay(in:host.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/focus-workspace-offscreen.png"))}
    try PhotoshopMenuTests().withMenus{_,menu in XCTAssertTrue(PhotoshopMenuTests().allItems(menu).contains{$0.title=="Focus Area…" && $0.action==#selector(AppDelegate.focusArea)})}
  }
}
