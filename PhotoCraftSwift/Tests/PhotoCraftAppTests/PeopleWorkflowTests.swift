import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraft
import PhotoCraftCore
import PhotoCraftImaging

private actor PeopleFixture: PeopleDetecting {
  var calls = 0
  let delay: Duration, empty: Bool, fail: Bool
  init(delay: Duration = .zero, empty: Bool = false, fail: Bool = false) { self.delay=delay;self.empty=empty;self.fail=fail }
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    calls += 1
    if delay > .zero { try await Task.sleep(for:delay) }
    if fail { throw CraftError.unavailable("Fixture people model unavailable") }
    if empty { return [] }
    var a = [UInt8](repeating:0,count:image.width*image.height), b = a
    for y in 4..<12 { for x in 4..<12 { a[y*image.width+x] = x == 4 ? 128:255 } }
    for y in 4..<12 { for x in 20..<28 { b[y*image.width+x] = 255 } }
    return try [.init(instanceID:2,mask:SelectionMask(width:image.width,height:image.height,bytes:a)),.init(instanceID:7,mask:SelectionMask(width:image.width,height:image.height,bytes:b))]
  }
}

final class PeopleWorkflowTests: XCTestCase {
  func fixture() throws -> CraftDocument { try CraftDocument(width:32,height:16) }
  @MainActor private func store(_ detector: PeopleFixture = PeopleFixture()) throws -> EditorStore {
    let s = EditorStore(document:try fixture(),actions:ActionLibrary(),brushes:BrushLibrary(),skies:SkyLibrary())
    s.objectFinderEnabled=false;s.peopleDetector=detector;s.tool = .objectSelection;return s
  }
  @MainActor func stop(_ s: EditorStore) { s.peopleWorkspace.close();s.objectFinder.cancel();s.geometryTask?.cancel();s.renderTask?.cancel();s.cancelSelectMask() }
  @MainActor func testPeoplePickerHoverMultipleSelectionUndoActionsAndRefinement() async throws {
    let detector=PeopleFixture(),s=try store(detector),original=s.document;defer{stop(s)}
    s.openPeoplePicker();await s.peopleWorkspace.task?.value
    XCTAssertTrue(s.peopleWorkspace.presented);XCTAssertEqual(s.peopleWorkspace.scene?.people.count,2)
    for id in [2,7,2] {s.hoverPerson(id);await s.peopleWorkspace.overlayTask?.value;XCTAssertNotNil(s.peopleWorkspace.image)}
    s.requestPeople();let calls=await detector.calls;XCTAssertEqual(calls,1);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let cache=s.peopleWorkspace.cacheID;try s.session.startActionRecording(name:"People")
    await s.selectPeople([2,7])?.value;let selected=s.document;XCTAssertEqual(selected.selectionMask?.bytes[6*32+4],128);XCTAssertEqual(selected.selectionMask?.bytes[6*32+23],255)
    XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(s.peopleWorkspace.cacheID,cache)
    var replay=original;try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,selected)
    _=await s.requestHistory(redo:false).value;XCTAssertEqual(s.document,original);_=await s.requestHistory(redo:true).value;XCTAssertEqual(s.document,selected)
    s.peopleWorkspace.selectedIDs=[2];s.objectFinderHardEdge=true;s.selectPeopleAndRefine();await s.geometryTask?.value;await s.selectMaskDraft?.task?.value
    XCTAssertNotNil(s.selectMaskDraft);XCTAssertEqual(s.document.selectionMask?.bytes[6*32+4],255);XCTAssertFalse(s.peopleWorkspace.presented)
  }
  @MainActor func testSourceSamplingToolEscapeReloadAndCloseInvalidateDetection() async throws {
    let document=CraftNSDocument(model:try fixture(),actions:ActionLibrary(),skies:SkyLibrary()),s=document.store
    defer{stop(s);document.updateChangeCount(.changeCleared);document.close()};s.objectFinderEnabled=false;s.peopleDetector=PeopleFixture(delay:.milliseconds(100));s.tool = .objectSelection
    s.openPeoplePicker();let old=s.peopleWorkspace.task;var changed=s.document;changed.layers[0].x=1;s.session=EditorSession(document:changed);await old?.value;XCTAssertNil(s.peopleWorkspace.scene)
    s.requestPeople();await s.peopleWorkspace.task?.value;let cache=s.peopleWorkspace.cacheID;s.selectionSampleAllLayers=true;XCTAssertNotEqual(s.peopleWorkspace.cacheID,cache)
    s.requestPeople();let cancel=s.peopleWorkspace.task
    let event=try XCTUnwrap(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53));CraftCanvas(store:s).keyDown(with:event);await cancel?.value;XCTAssertNil(s.peopleWorkspace.scene);XCTAssertFalse(s.peopleWorkspace.presented)
    s.openPeoplePicker();let switchTask=s.peopleWorkspace.task;s.tool = .move;await switchTask?.value;XCTAssertNil(s.peopleWorkspace.scene)
    s.tool = .objectSelection;s.requestPeople();let reading=s.peopleWorkspace.task;try document.read(from:NativeArchive.encodeChunked(try fixture()),ofType:CraftNSDocument.nativeType);await reading?.value;XCTAssertNil(s.peopleWorkspace.scene)
    s.requestPeople();let closing=s.peopleWorkspace.task;document.close();await closing?.value;XCTAssertNil(s.peopleWorkspace.scene)
  }
  @MainActor func testEmptyFailureRefreshAndOffscreenPicker() async throws {
    let detector=PeopleFixture(empty:true),s=try store(detector);defer{stop(s)}
    s.openPeoplePicker();await s.peopleWorkspace.task?.value;XCTAssertEqual(s.peopleWorkspace.scene?.people.count,0);XCTAssertNil(s.peopleWorkspace.error)
    s.peopleDetector=PeopleFixture(fail:true);s.requestPeople(force:true);await s.peopleWorkspace.task?.value;XCTAssertNotNil(s.peopleWorkspace.error);XCTAssertNil(s.peopleWorkspace.scene)
    s.peopleDetector=PeopleFixture();s.requestPeople(force:true);await s.peopleWorkspace.task?.value;s.peopleWorkspace.selectedIDs=[2];s.hoverPerson(2);await s.peopleWorkspace.overlayTask?.value;await s.renderTask?.value;s.zoom=12
    let canvas=CraftCanvas(store:s);canvas.frame = .init(x:0,y:0,width:640,height:320)
    capture(canvas,"people-canvas-offscreen")
    let host=NSHostingView(rootView:PeoplePickerView(store:s)),window=NSWindow(contentRect:.init(x:0,y:0,width:412,height:610),styleMask:[.titled],backing:.buffered,defer:false)
    window.appearance=NSAppearance(named:.darkAqua);window.contentView=host;defer{window.contentView=nil};host.frame = .init(x:0,y:0,width:412,height:610);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(80));window.displayIfNeeded();capture(host,"people-picker-offscreen")
  }
  @MainActor func capture(_ view:NSView,_ name:String) {
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {view.cacheDisplay(in:view.bounds,to:bitmap);try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/\(name).png"))}
  }
  @MainActor func testAPIMasksThumbnailsHoverMultiPersonSelectionAndHistory() async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      let s=document.store;s.session=EditorSession(document:try self.fixture());s.peopleDetector=PeopleFixture();let original=s.document;try service.share(document);let share=try XCTUnwrap(service.shares.first?.id)
      let response=try await h.request(service,path:"/v1/documents/\(share)/commands",body:["command":"selection.findPeople","revision":service.revision(s),"parameters":["includeMasks":true,"includeThumbnails":true]])
      XCTAssertEqual(response.0.statusCode,200);let json=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any]);let fields=json.filter{["revision","peopleSelection","peopleMasks","peopleThumbnails"].contains($0.key)}
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:fields));XCTAssertNoThrow(try BrushAPI.merge(value,schema:PeopleAPI.resultSchema))
      let masks=try XCTUnwrap(json["peopleMasks"] as? [[String:Any]]),thumbs=try XCTUnwrap(json["peopleThumbnails"] as? [[String:Any]]);XCTAssertEqual(masks.count,2);XCTAssertEqual(thumbs.count,2)
      XCTAssertEqual(Data(base64Encoded:try XCTUnwrap(masks[0]["coverageBase64"] as? String)),Data(s.peopleWorkspace.scene!.people[0].mask.bytes))
      let png=try XCTUnwrap(Data(base64Encoded:try XCTUnwrap(thumbs[0]["pngBase64"] as? String)));let bitmap=try XCTUnwrap(NSBitmapImageRep(data:png));XCTAssertLessThanOrEqual(bitmap.pixelsWide,96)
      let cache=s.peopleWorkspace.cacheID.uuidString
      let hover=try await h.edit(service,document,"selection.hoverPerson",["cacheID":cache,"instanceID":2]);XCTAssertEqual(hover,200);XCTAssertEqual(s.peopleWorkspace.hoveredID,2)
      let clear=try await h.edit(service,document,"selection.hoverPerson",["cacheID":cache]);XCTAssertEqual(clear,200);XCTAssertNil(s.peopleWorkspace.hoveredID);XCTAssertEqual(s.document,original)
      let select=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":[2,7],"hardEdge":true]);XCTAssertEqual(select,200)
      var expected=original;try s.peopleWorkspace.scene!.command(instanceIDs:[2,7],mode:.replace,hardEdge:true).apply(to:&expected);XCTAssertEqual(s.document,expected);XCTAssertEqual(s.session.undoStack.count,1)
      let undo=try await h.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(s.document,original)
      let redo=try await h.edit(service,document,"history.redo");XCTAssertEqual(redo,200);XCTAssertEqual(s.document,expected)
    }
  }
  @MainActor func testAPIInvalidStaleBusyEmptyRefreshCancellationAndRevocation() async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) { service,document in
      let s=document.store;s.session=EditorSession(document:try self.fixture());let original=s.document;s.peopleDetector=PeopleFixture();try service.share(document)
      let bad=try await h.edit(service,document,"selection.findPeople",["refresh":1]);XCTAssertEqual(bad,400)
      let stale=try await h.edit(service,document,"selection.findPeople",revision:"old");XCTAssertEqual(stale,409)
      s.geometryBusy=true;let busy=try await h.edit(service,document,"selection.findPeople");XCTAssertEqual(busy,409);s.geometryBusy=false
      let ok=try await h.edit(service,document,"selection.findPeople");XCTAssertEqual(ok,200);let cache=s.peopleWorkspace.cacheID.uuidString
      for ids:[Any] in [[],[2,2],[2.5],[true],[256]] {let code=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":ids]);XCTAssertEqual(code,400)}
      let missing=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":[99]]);XCTAssertEqual(missing,404)
      s.peopleDetector=PeopleFixture(empty:true);let empty=try await h.edit(service,document,"selection.findPeople",["refresh":true]);XCTAssertEqual(empty,200);XCTAssertTrue(s.peopleWorkspace.scene!.people.isEmpty)
      let expired=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":[2]]);XCTAssertEqual(expired,409)
      for revoke in [false,true] {
        s.peopleDetector=PeopleFixture(delay:.milliseconds(200))
        let pending=Task{try await h.edit(service,document,"selection.findPeople",["refresh":true])}
        let end=Date().addingTimeInterval(3);while !s.peopleWorkspace.busy && Date()<end{await Task.yield()};XCTAssertTrue(s.peopleWorkspace.busy)
        if revoke{service.revoke(try XCTUnwrap(service.shares.first?.id))}else{s.cancelActiveOperation()}
        let code=try await pending.value;XCTAssertEqual(code,409);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
      }
    }
  }
}

private actor PeopleFeaturesFixture: PeopleFeaturesDetecting {
  let fail:Bool,delay:Duration
  init(fail:Bool=false,delay:Duration = .zero){self.fail=fail;self.delay=delay}
  func features(in image:Surface) async throws -> PeopleFeatureMap {
    if delay > .zero {try await Task.sleep(for:delay)}
    if fail {throw CraftError.unavailable("Fixture feature model failed")}
    return try .init(width:1,height:1,probabilities:[0,0.75,0,0.25,0,0])
  }
}
extension PeopleWorkflowTests {
  @MainActor func testNativeFeatureControlsHoverSelectionActionsAndRefinement() async throws {
    let s=try store();defer{stop(s)};s.peopleFeaturesDetector=PeopleFeaturesFixture();let original=s.document
    s.openPeoplePicker();await s.peopleWorkspace.task?.value
    XCTAssertEqual(s.peopleWorkspace.scene?.availableFeatures,PeopleFeature.allCases)
    s.peopleWorkspace.selectedIDs=[2];s.togglePeopleFeature(.hair);XCTAssertEqual(s.peopleWorkspace.selectedFeatures,[.hair])
    s.hoverPerson(2,feature:.hair);await s.peopleWorkspace.overlayTask?.value;XCTAssertNotNil(s.peopleWorkspace.image);XCTAssertEqual(s.peopleWorkspace.hoveredFeature,.hair)
    try s.session.startActionRecording(name:"Hair");await s.selectPeople([2])?.value
    XCTAssertEqual(s.document.selectionMask?.bytes[6*32+4],96);XCTAssertEqual(s.document.selectionMask?.bytes[6*32+6],191)
    var replay=original;try XCTUnwrap(s.session.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,s.document)
    s.togglePeopleFeature(.faceSkin);s.selectPeopleAndRefine();await s.geometryTask?.value;await s.selectMaskDraft?.task?.value
    XCTAssertNotNil(s.selectMaskDraft);XCTAssertEqual(s.document.selectionMask?.bytes[6*32+4],128)
  }
  @MainActor func testFeatureAPIExportHoverSelectionAndStrictParameters() async throws {
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) {service,document in
      let s=document.store;s.session=EditorSession(document:try self.fixture());s.peopleDetector=PeopleFixture();s.peopleFeaturesDetector=PeopleFeaturesFixture();try service.share(document);let id=try XCTUnwrap(service.shares.first?.id)
      let response=try await h.request(service,path:"/v1/documents/\(id)/commands",body:["command":"selection.findPeople","revision":service.revision(s),"parameters":["includeMasks":true,"features":["hair"]]])
      XCTAssertEqual(response.0.statusCode,200);let json=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any]);let masks=try XCTUnwrap(json["peopleMasks"] as? [[String:Any]])
      let bytes=try XCTUnwrap(Data(base64Encoded:try XCTUnwrap(masks[0]["coverageBase64"] as? String)));XCTAssertEqual(bytes[6*32+4],96)
      let subset=json.filter{["revision","peopleSelection","peopleMasks"].contains($0.key)},decoded=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:subset));XCTAssertNoThrow(try BrushAPI.merge(decoded,schema:PeopleAPI.resultSchema))
      let cache=s.peopleWorkspace.cacheID.uuidString
      let hover=try await h.edit(service,document,"selection.hoverPerson",["cacheID":cache,"instanceID":2,"feature":"hair"]);XCTAssertEqual(hover,200);XCTAssertEqual(s.peopleWorkspace.hoveredFeature,.hair)
      let select=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":[2],"features":["hair"]]);XCTAssertEqual(select,200);XCTAssertEqual(s.document.selectionMask?.bytes[6*32+4],96);XCTAssertEqual(s.peopleWorkspace.selectedFeatures,[.hair])
      for features:[Any] in [[],["hair","hair"],["beard"],[1]] {let code=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":[2],"features":features]);XCTAssertEqual(code,400)}
      let invalid=try await h.edit(service,document,"selection.hoverPerson",["cacheID":cache,"instanceID":2,"feature":"beard"]);XCTAssertEqual(invalid,400)
    }
  }
  @MainActor func testFeatureFailureRetainsWholePeopleAndCancellationDiscardsBothModels() async throws {
    let s=try store();defer{stop(s)};s.peopleFeaturesDetector=PeopleFeaturesFixture(fail:true)
    s.requestPeople();await s.peopleWorkspace.task?.value;XCTAssertNotNil(s.peopleWorkspace.scene?.featureError);XCTAssertEqual(s.peopleWorkspace.scene?.availableFeatures,[.wholePerson])
    await s.selectPeople([2],features:[.wholePerson])?.value;XCTAssertEqual(s.document.selectionMask?.bytes[6*32+6],255)
    s.peopleFeaturesDetector=PeopleFeaturesFixture(delay:.milliseconds(200));s.requestPeople(force:true);let pending=s.peopleWorkspace.task;await Task.yield();s.stopPeopleDetection();await pending?.value;XCTAssertNil(s.peopleWorkspace.scene);XCTAssertFalse(s.peopleWorkspace.busy)
    let h=AutomationTests()
    try await h.withService(actions:ActionLibrary(),skies:SkyLibrary(),pressedMouseButtons:{0}) {service,document in
      let store=document.store;store.session=EditorSession(document:try self.fixture());store.peopleDetector=PeopleFixture();store.peopleFeaturesDetector=PeopleFeaturesFixture(fail:true);try service.share(document)
      let detect=try await h.edit(service,document,"selection.findPeople");XCTAssertEqual(detect,200);let cache=store.peopleWorkspace.cacheID.uuidString
      let unavailable=try await h.edit(service,document,"selection.selectPeople",["cacheID":cache,"instanceIDs":[2],"features":["hair"]]);XCTAssertEqual(unavailable,422)
      let hover=try await h.edit(service,document,"selection.hoverPerson",["cacheID":cache,"instanceID":2,"feature":"hair"]);XCTAssertEqual(hover,422)
    }
  }
}
