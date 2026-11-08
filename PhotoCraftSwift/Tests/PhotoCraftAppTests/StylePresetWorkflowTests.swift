import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class StylePresetWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {try StylePresetTestsProxy.make()}
  @MainActor func testPrivateDraftSavingAndCancelDoNotEditDocumentOrHistory()async throws {
    let d=try fixture(),library=StyleLibrary(),store=EditorStore(document:d,styles:library);defer{store.renderTask?.cancel()}
    store.beginLayerStyle(.dropShadow);let owner=try StylePresetSaveSource(store);let saved=try await store.saveStylePreset(owner,name:"Draft look")
    XCTAssertNotNil(saved);XCTAssertEqual(store.document,d);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(library.state.nodes[0].preset?.style,owner.style)
    store.cancelLayerStyle();XCTAssertEqual(store.document,d);XCTAssertThrowsError(try StylePreset.capture(layerID:UUID(),in:d))
    do {_=try await store.saveStylePreset(owner,name:"Stale");XCTFail("Accepted stale draft")}catch{}
    XCTAssertEqual(library.state.nodes.count,1)
  }
  @MainActor func testAtomicPersistenceReloadDeniedCommitAndCorruptFilePreservation()async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try?FileManager.default.removeItem(at:directory)}
    let url=directory.appendingPathComponent("styles"),library=StyleLibrary(persistenceURL:url),d=try fixture(),preset=try StylePreset.capture(layerID:d.layers[0].id,in:d)
    _=try await library.edit(.save("Saved",preset,parent:nil));let bytes=try Data(contentsOf:url),state=library.state
    do {_=try await library.edit(.group("Denied",parent:nil),authorize:{false});XCTFail("Published denied mutation")}catch{}
    XCTAssertEqual(try Data(contentsOf:url),bytes);XCTAssertEqual(library.state,state)
    let loaded=StyleLibrary(persistenceURL:url);await loaded.loadTask?.value;XCTAssertNil(loaded.error);XCTAssertEqual(loaded.state,state)
    try Data("broken".utf8).write(to:url);let corrupt=StyleLibrary(persistenceURL:url);await corrupt.loadTask?.value;XCTAssertTrue(corrupt.loadFailed)
    do {_=try await corrupt.edit(.group("Overwrite",parent:nil));XCTFail("Overwrote unreadable library")}catch{}
    XCTAssertEqual(try Data(contentsOf:url),Data("broken".utf8))
    let blocked=StyleLibrary(persistenceURL:directory)
    await blocked.loadTask?.value;XCTAssertTrue(blocked.loadFailed)
  }
  @MainActor func testNativePresetApplicationUsesOneUndoAndActions57RetainsResources()async throws {
    let source=try fixture(),library=StyleLibrary(),preset=try StylePreset.capture(layerID:source.layers[0].id,in:source,includesBlending:true)
    let createdID=try await library.edit(.save("Use",preset,parent:nil));let id=try XCTUnwrap(createdID)
    var blank=source;blank.patterns=nil;blank.layers[0].style=nil;blank.layers[0].opacity=1
    let store=EditorStore(document:blank,styles:library);defer{store.renderTask?.cancel()};XCTAssertTrue(store.canApplyStylePreset(id));try store.session.startActionRecording(name:"Apply Style")
    store.applyStylePreset(id);await store.geometryTask?.value;XCTAssertNil(store.error);XCTAssertEqual(store.session.undoStack.count,1);let changed=store.document
    XCTAssertEqual(try Renderer.composite(changed).rgbaData(depth:.f32),try Renderer.composite(source).rgbaData(depth:.f32))
    let action=try XCTUnwrap(store.session.actionRecording?.snapshot);store.session.stopActionRecording();var file=ActionLibraryFile();file.actions=[action];file.version=57;XCTAssertEqual(file.requiredVersion,57);XCTAssertNoThrow(try ActionLibraryFile.decode(file.encoded()));file.version=56;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONEncoder().encode(file)))
    await store.undo();XCTAssertEqual(store.document,blank);await store.redo();XCTAssertEqual(store.document,changed)
    _=try await library.edit(.delete([id]));XCTAssertEqual(store.document,changed)
  }
  @MainActor func call(_ h:AutomationTests,_ service:AutomationService,_ file:CraftNSDocument,_ operation:String,_ fields:[String:Any]=[:],libraryRevision:String?=nil)async throws->(Int,[String:Any]) {
    let share=try XCTUnwrap(service.shares.first{$0.document===file});var parameters:[String:Any]=["operation":operation]
    if operation != "list" {parameters["libraryRevision"]=libraryRevision ?? file.store.styles.revision.uuidString};parameters.merge(fields){_,new in new}
    let response=try await h.request(service,path:"/v1/documents/\(share.id)/commands",body:["command":StyleLibraryAPI.command,"revision":service.revision(file.store),"parameters":parameters])
    let object=(try JSONSerialization.jsonObject(with:response.1)as?[String:Any]) ?? [:]
    if response.0.statusCode>=400,ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] != nil {
      print("STYLE_LIBRARY_HTTP_ERROR",operation,response.0.statusCode,String(describing:object["error"] ?? object["message"] ?? "No error detail").prefix(2000))
    }
    return(response.0.statusCode,object)
  }
  @MainActor func testHTTPCreateApplyAndHistoryAgreeWithNativeAndLibrarySchema()async throws {
    let h=AutomationTests(),library=StyleLibrary()
    try await h.withService(styles:library,pressedMouseButtons:{0}){service,file in
      let source=try self.fixture();file.store.session=EditorSession(document:source);try service.share(file)
      let created=try await self.call(h,service,file,"create",["name":"HTTP style","includesBlending":true]);XCTAssertEqual(created.0,200)
      let id=try XCTUnwrap(library.state.nodes.first?.id);XCTAssertEqual(library.state.nodes[0].preset,try StylePreset.capture(layerID:source.layers[0].id,in:source,includesBlending:true))
      XCTAssertEqual(file.store.document,source);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let inspect=try await self.call(h,service,file,"inspect",["nodeID":id.uuidString]);XCTAssertEqual(inspect.0,200)
      let details=try XCTUnwrap(inspect.1["preset"]as?[String:Any]),raw=try XCTUnwrap(details["style"]as?[String:Any]);XCTAssertEqual(try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject:raw)),source.layers[0].style)
      let detailedValue=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:details));XCTAssertNoThrow(try BrushAPI.merge(detailedValue,schema:StyleLibraryAPI.presetSchema))

      var blank=source;blank.layers[0].style=nil;blank.layers[0].opacity=1;blank.patterns=nil;file.store.session=EditorSession(document:blank)
      let applied=try await self.call(h,service,file,"apply",["nodeID":id.uuidString,"layerIDs":[blank.layers[0].id.uuidString]]);XCTAssertEqual(applied.0,200)
      let native=EditorStore(document:blank,styles:library);defer{native.renderTask?.cancel()};native.applyStylePreset(id);await native.geometryTask?.value;XCTAssertEqual(file.store.document,native.document)
      let state=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:StyleLibraryAPI.state(library)));XCTAssertNoThrow(try BrushAPI.merge(state,schema:StyleLibraryAPI.stateSchema))
      let undoCode=try await h.edit(service,file,"history.undo");XCTAssertEqual(undoCode,200);XCTAssertEqual(file.store.document,blank)
    }
  }
  @MainActor func testHTTPStaleInvalidLockedAndModalRequestsAreAtomic()async throws {
    let h=AutomationTests(),library=StyleLibrary()
    try await h.withService(styles:library,pressedMouseButtons:{0}){service,file in
      let source=try self.fixture();file.store.session=EditorSession(document:source);try service.share(file)
      var response=try await self.call(h,service,file,"group.create",["name":"Group"]);XCTAssertEqual(response.0,200);let before=library.state
      response=try await self.call(h,service,file,"group.create",["name":"Stale"],libraryRevision:UUID().uuidString);XCTAssertEqual(response.0,409)
      response=try await self.call(h,service,file,"group.create",["name":"Bad","nodeIDs":[]]);XCTAssertEqual(response.0,400);XCTAssertEqual(library.state,before)
      response=try await self.call(h,service,file,"create",["name":"Empty","includesEffects":false,"includesBlending":false]);XCTAssertEqual(response.0,422)
      response=try await self.call(h,service,file,"create",["name":"Style"]);XCTAssertEqual(response.0,200);let id=try XCTUnwrap(library.state.nodes.first{!$0.isGroup}?.id)
      var locked=source;locked.layers[0].protection=[.all];file.store.session=EditorSession(document:locked)
      response=try await self.call(h,service,file,"apply",["nodeID":id.uuidString,"layerIDs":[locked.layers[0].id.uuidString]]);XCTAssertEqual(response.0,422);XCTAssertEqual(file.store.document,locked)
      file.store.session=EditorSession(document:source);file.store.beginLayerStyle();response=try await self.call(h,service,file,"list");XCTAssertEqual(response.0,409);file.store.cancelLayerStyle()
    }
  }
  @MainActor func testActualHTTPBusyAndRevokedLibraryMutationCannotCommit()async throws {
    let h=AutomationTests(),gate=StylePresetGate();defer{gate.release()}
    let library=StyleLibrary(preparation:{state,mutation in gate.wait();var next=state;let id=try next.apply(mutation);return(next,id)})
    try await h.withService(styles:library,pressedMouseButtons:{0}){service,file in
      await file.store.renderTask?.value;try service.share(file);let before=library.state
      let task=Task{@MainActor in let result=try await self.call(h,service,file,"group.create",["name":"Rejected after revoke"]);return result.0}
      for _ in 0..<200 where !gate.entered {try await Task.sleep(for:.milliseconds(5))};XCTAssertTrue(gate.entered);XCTAssertTrue(library.busy)
      let busy=try await self.call(h,service,file,"group.create",["name":"Busy"]);XCTAssertEqual(busy.0,409)
      service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release();let result=try await task.value;XCTAssertEqual(result,409);XCTAssertEqual(library.state,before)
    }
  }
  @MainActor func testCancelledAndFailedStoragePreserveMemoryAndExistingFile()async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try?FileManager.default.removeItem(at:directory)}
    let gate=StylePresetGate();defer{gate.release()};let url=directory.appendingPathComponent("library")
    let library=StyleLibrary(persistenceURL:url,preparation:{state,mutation in gate.wait();var next=state;let id=try next.apply(mutation);return(next,id)})
    let task=Task{@MainActor in try await library.edit(.group("Cancelled",parent:nil))}
    for _ in 0..<200 where !gate.entered {try await Task.sleep(for:.milliseconds(5))};XCTAssertTrue(gate.entered);task.cancel();gate.release()
    do {_=try await task.value;XCTFail("Cancelled mutation committed")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertTrue(library.state.nodes.isEmpty);XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
    let blocker=directory.appendingPathComponent("blocker");try Data("retained".utf8).write(to:blocker);let failed=StyleLibrary(persistenceURL:blocker.appendingPathComponent("library"))
    do {_=try await failed.edit(.group("Must fail",parent:nil));XCTFail("Wrote through a regular file")}catch{}
    XCTAssertTrue(failed.state.nodes.isEmpty);XCTAssertEqual(try Data(contentsOf:blocker),Data("retained".utf8))
  }
  @MainActor func testClosedDocumentStillRejectsRetainedRequestOwnerBeforeLibraryCommit()async throws {
    let h=AutomationTests(),gate=StylePresetGate();defer{gate.release()}
    let library=StyleLibrary(preparation:{state,mutation in gate.wait();var next=state;let id=try next.apply(mutation);return(next,id)})
    try await h.withService(styles:library,pressedMouseButtons:{0}){service,file in
      await file.store.renderTask?.value;try service.share(file)
      let task=Task{@MainActor in let result=try await self.call(h,service,file,"group.create",["name":"Must not survive Close"]);return result.0}
      for _ in 0..<200 where !gate.entered {try await Task.sleep(for:.milliseconds(5))}
      XCTAssertTrue(gate.entered);XCTAssertTrue(library.busy)
      service.controller.removeDocument(file)
      gate.release();let code=try await task.value
      XCTAssertEqual(code,409);XCTAssertTrue(library.state.nodes.isEmpty)
    }
  }
  @MainActor func testEveryEffectDescriptorIncludingPatternAndGradientHasExecutableSchema()throws {
    XCTAssertThrowsError(try BrushAPI.merge(.null,schema:StyleLibraryAPI.schema("style")))
    let h=LayerStyleWorkflowTests()
    _=h
    for kind in LayerEffect.Kind.allCases {
      var effect=LayerEffect(kind)
      if kind == .patternOverlay {effect.pattern=PatternFill(patternID:"owned-style")}
      if kind == .gradientOverlay {effect.gradient=GradientFill(gradient:.blackToWhite)}
      let style=LayerStyle(effects:[effect]),value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:style.apiObject))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:LayerStyle.apiSchema),"\(kind)")
    }
  }
  @MainActor func testCatalogThreeMigrationKeepsEveryOldPlacementAndMenuUsesFactoryEntry()throws {
    var old=PanelDock(layout:.init());old.groups.removeAll{$0.panels.contains(.styles)};old.hidden.remove(.styles);old.catalogVersion=3
    let original=old.groups,decoded=try JSONDecoder().decode(PanelDock.self,from:JSONEncoder().encode(old))
    XCTAssertEqual(decoded.catalogVersion,4);XCTAssertEqual(Array(decoded.groups.prefix(original.count)),original);XCTAssertTrue(decoded.hidden.contains(.styles));try decoded.validate()
    var invalid=old;invalid.groups[0].panels.removeLast();XCTAssertThrowsError(try JSONDecoder().decode(PanelDock.self,from:JSONEncoder().encode(invalid)))
    try PhotoshopMenuTests().withMenus {_,menu in
      func find(_ menu:NSMenu)->NSMenuItem? {for item in menu.items {if item.identifier?.rawValue=="Window > Styles"{return item};if let sub=item.submenu,let match=find(sub){return match}};return nil}
      XCTAssertEqual(try XCTUnwrap(find(menu)).action,#selector(AppDelegate.stylesPanel))
    }
    XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(ActionLibraryFile.maximumVersion,60)
    XCTAssertNotNil(AutomationCommand.definitions.first{$0.name==StyleLibraryAPI.command});XCTAssertEqual(StyleLibraryAPI.fields.count,9)
  }
}
private enum StylePresetTestsProxy {
  static func make()throws->CraftDocument {
    var d=try CraftDocument(width:12,height:10);d.layers[0].content = .raster(try Surface(width:12,height:10,fill:Pixel(0.2,0.5,0.8,0.7)))
    d.patterns=[try RasterPattern(name:"Owned tile",surface:Surface(width:2,height:2,fill:Pixel(0.8,0.3,0.1)),id:"owned-style")]
    var e=LayerEffect(.patternOverlay);e.pattern=PatternFill(patternID:"owned-style");d.layers[0].style=LayerStyle(effects:[e]);d.layers[0].opacity=0.6;return d
  }
}

private final class StylePresetGate:@unchecked Sendable {
  private let condition=NSCondition();private var started=false,opened=false
  var entered:Bool {condition.lock();defer{condition.unlock()};return started}
  func wait(){condition.lock();started=true;condition.broadcast();while !opened{condition.wait()};condition.unlock()}
  func release(){condition.lock();opened=true;condition.broadcast();condition.unlock()}
}
