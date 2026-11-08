import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class PatternImportGate:@unchecked Sendable {
  private let condition=NSCondition()
  private var started=false,opened=false
  var entered:Bool{condition.lock();defer{condition.unlock()};return started}
  func wait(){condition.lock();started=true;condition.broadcast();while !opened{condition.wait()};condition.unlock()}
  func release(){condition.lock();opened=true;condition.broadcast();condition.unlock()}
}
final class PatternLibraryWorkflowTests:XCTestCase {
  func folder()throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-pattern-library-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
  }
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var document=try CraftDocument(width:16,height:12,depth:depth)
    document.layers[0].content = .raster(try Surface(width:16,height:12,depth:depth,fill:Pixel(0.25,0.5,0.75,0.5)))
    return document
  }
  func imported()throws->PatternLibraryState {
    let tile=try RasterPattern(name:"Owned tile",surface:Surface(width:2,height:2,depth:.f32,fill:Pixel(0.125,0.5,0.875,0.5)),id:"owned-group-tile")
    var state=PatternLibraryState(patterns:[tile]);let leaf=state.nodes[0].id
    let group=try XCTUnwrap(state.apply(.createGroup("Imported textures",parent:nil)))
    try state.apply(.move([leaf],parent:group,before:nil));_=try state.apply(.createGroup("Empty",parent:group));return state
  }
  @MainActor private func started(_ gate:PatternImportGate)async throws {
    for _ in 0..<200 where !gate.entered{try await Task.sleep(for:.milliseconds(5))}
    XCTAssertTrue(gate.entered)
  }
  @MainActor func call(_ h:AutomationTests,_ service:AutomationService,_ doc:CraftNSDocument,_ operation:String,
    _ fields:[String:Any]=[:],revision:String?=nil)async throws->(Int,[String:Any]) {
    let share=try XCTUnwrap(service.shares.first{$0.document===doc})
    var parameters:[String:Any]=["operation":operation]
    if operation != "list"{parameters["libraryRevision"]=doc.store.patterns.revision.uuidString}
    parameters.merge(fields){_,new in new}
    let before=PatternDialogSource(doc.store),beforeRevision=revision ?? service.revision(doc.store),beforeToken=service.token
    let response=try await h.request(service,path:"/v1/documents/\(share.id)/commands",body:["command":PatternLibraryAPI.command,"revision":beforeRevision,"parameters":parameters])
    if response.0.statusCode>=400{print("Pattern library",operation,"HTTP",response.0.statusCode,String(data:response.1,encoding:.utf8) ?? "")}
    if response.0.statusCode>=400{print("Pattern guard predicates",["source":before.matches(doc.store),"view":beforeRevision==service.revision(doc.store),"running":service.isRunning,"token":beforeToken==service.token,"shared":service.shares.contains{$0.id==share.id},"document":before.documentID==doc.store.document.id,"session":before.session==doc.store.sessionGeneration,"generation":before.generation==doc.store.layerPanelGeneration,"library":before.libraryRevision==doc.store.patterns.revision])}
    return(response.0.statusCode,(try JSONSerialization.jsonObject(with:response.1)as? [String:Any]) ?? [:])
  }
  @MainActor func testNativeGroupNameSelectionMoveDuplicateRenameDeleteAndReloadLeaveDocumentUntouched()async throws {
    let path=try folder();defer{try? FileManager.default.removeItem(at:path)}
    let url=path.appendingPathComponent("Patterns.pclibrary"),library=PatternLibrary(persistenceURL:url)
    let d=try fixture(),store=EditorStore(document:d,patterns:library);defer{store.renderTask?.cancel()}
    await store.renderTask?.value;let bytes=try NativeArchive.encode(d)
    var changes=0;store.onChange={_ in changes+=1}
    store.beginPatternGroup();let cancelled=try XCTUnwrap(store.patternNameDraft);store.patternNameDraft=nil
    XCTAssertNil(try? Data(contentsOf:url));XCTAssertTrue(library.state.nodes.allSatisfy{!$0.isGroup})
    store.beginPatternGroup();let draft=try XCTUnwrap(store.patternNameDraft)
    await store.commitPatternName(draft,name:"Textures")?.value
    let group=try XCTUnwrap(library.state.nodes.first{$0.isGroup})
    let leaves=library.state.nodes.filter{!$0.isGroup};XCTAssertGreaterThanOrEqual(leaves.count,3)
    try library.click(leaves[0].id,modifiers:[]);try library.click(leaves[2].id,modifiers:[.shift])
    XCTAssertEqual(library.state.selectedNodes,Set(leaves.prefix(3).map(\.id)))
    await store.mutatePatterns(.move(library.state.selectedNodes,parent:group.id,before:nil)).value
    XCTAssertEqual(library.state.children(of:group.id).map(\.id),leaves.prefix(3).map(\.id))
    store.beginPatternRename(group.id);await store.commitPatternName(try XCTUnwrap(store.patternNameDraft),name:"Materials")?.value
    XCTAssertEqual(library.state.name(group.id),"Materials")
    let before=library.state.patterns
    await store.mutatePatterns(.duplicate([group.id],parent:nil,before:group.id)).value
    let copied=try XCTUnwrap(library.state.nodes.first{$0.isGroup && $0.id != group.id})
    XCTAssertEqual(library.items.count,before.count+3)
    await store.mutatePatterns(.delete([copied.id])).value;XCTAssertEqual(library.items,before)
    try library.collapse(group.id,true)
    // A persisted mutation saves the current disclosure and selection, too.
    _=try await library.mutate(.rename(group.id,"Materials saved"))
    let loaded=PatternLibrary(persistenceURL:url);await loaded.loadTask?.value
    XCTAssertNil(loaded.error);XCTAssertEqual(loaded.state,library.state)
    XCTAssertEqual(store.document,d);XCTAssertEqual(try NativeArchive.encode(store.document),bytes)
    XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(changes,0)
    XCTAssertFalse(cancelled.source?.matches(store) ?? true)
  }
  @MainActor func testActualPrivateDragMovesGroupsAndPreservesFeedbackForAllModifiersAndRejectsStaleForeign()async throws {
    let library=PatternLibrary(),store=EditorStore(document:try fixture(),patterns:library)
    let other=EditorStore(document:try fixture(),patterns:library),foreign=EditorStore(document:try fixture(),patterns:PatternLibrary())
    defer{store.renderTask?.cancel();other.renderTask?.cancel();foreign.renderTask?.cancel()}
    let madeGroup=try await library.mutate(.createGroup("Target",parent:nil))
    let group=try XCTUnwrap(madeGroup),leaf=library.state.nodes.first{$0.patternID != nil}!.id
    let provider=PatternLibraryDrag.provider(store:store,nodeID:leaf)
    for bits in 0..<16 {
      var flags=NSEvent.ModifierFlags();for(i,flag)in [NSEvent.ModifierFlags.control,.command,.option,.shift].enumerated()where bits & (1<<i) != 0{flags.insert(flag)}
      let selection=PatternLibrary(),nodes=selection.state.nodes.filter{!$0.isGroup}
      try selection.select([nodes[0].id],active:nodes[0].id)
      try selection.click(nodes[2].id,modifiers:flags)
      let expected:Set<UUID>=flags.contains(.shift) ? Set(nodes.prefix(3).map(\.id)) : flags.contains(.command) ? [nodes[0].id,nodes[2].id]:[nodes[2].id]
      XCTAssertEqual(selection.state.selectedNodes,expected)
      try selection.select([nodes[0].id],active:nodes[0].id);try selection.click(nodes[0].id,modifiers:[.command]);XCTAssertTrue(selection.state.selectedNodes.isEmpty)
      XCTAssertEqual(PatternLibraryDrag.operation(flags),.move)
      XCTAssertTrue(PatternLibraryDrag.canReceive(store:other,parent:group,before:nil))
    }
    XCTAssertFalse(PatternLibraryDrag.canReceive(store:foreign,parent:nil,before:nil))
    let document=store.document
    let moved=await PatternLibraryDrag.receive(provider,store:other,parent:group,before:nil);XCTAssertTrue(moved)
    XCTAssertEqual(library.state.node(leaf)?.parentID,group);XCTAssertEqual(store.document,document);XCTAssertTrue(store.session.undoStack.isEmpty)
    let stale=PatternLibraryDrag.provider(store:store,nodeID:leaf)
    try library.collapse(group,true)
    XCTAssertFalse(PatternLibraryDrag.canReceive(store:store,parent:nil,before:nil))
    let rejected=await PatternLibraryDrag.receive(stale,store:store,parent:nil,before:nil);XCTAssertFalse(rejected)
    _=PatternLibraryDrag.provider(store:store,nodeID:leaf)
    let forged=NSItemProvider();forged.registerDataRepresentation(forTypeIdentifier:PatternLibraryDrag.identifier,visibility:.ownProcess){completion in completion(Data("foreign".utf8),nil);return nil}
    let bad=await PatternLibraryDrag.receive(forged,store:store,parent:nil,before:nil);XCTAssertFalse(bad)
    let old=PatternLibraryDrag.provider(store:store,nodeID:leaf);_=PatternLibraryDrag.provider(store:store,nodeID:group)
    let superseded=await PatternLibraryDrag.receive(old,store:store,parent:nil,before:nil);XCTAssertFalse(superseded)
    XCTAssertFalse(PatternLibraryDrag.canReceive(store:store,parent:group,before:nil))
  }
  @MainActor func testHTTPOrganizationUsesNativeStateAndSchemasWithNoImageHistoryAndSharedRevision()async throws {
    let h=AutomationTests(),library=PatternLibrary()
    try await h.withService(patterns:library,pressedMouseButtons:{0}){service,doc in
      await doc.store.renderTask?.value;try service.share(doc)
      let controller=try XCTUnwrap(doc.store.documentController),other=CraftNSDocument(model:try self.fixture(),patterns:library)
      controller.addDocument(other);try service.share(other);await other.store.renderTask?.value
      var otherAttached=true
      defer{other.store.renderTask?.cancel();if otherAttached{controller.removeDocument(other)}}
      let otherRevision=service.revision(other.store)
      let d=doc.store.document,bytes=try NativeArchive.encode(d),oldRevision=service.revision(doc.store)
      let list=try await self.call(h,service,doc,"list");XCTAssertEqual(list.0,200)
      let made=try await self.call(h,service,doc,"group.create",["name":"HTTP group"]);XCTAssertEqual(made.0,200)
      let group=try XCTUnwrap((made.1["createdNodeID"]as? String).flatMap(UUID.init(uuidString:)))
      XCTAssertNotEqual(service.revision(doc.store),oldRevision)
      XCTAssertNotEqual(service.revision(other.store),otherRevision)
      let staleOther=try await self.call(h,service,other,"rename",["nodeID":group.uuidString,"name":"Must not apply"],revision:otherRevision)
      XCTAssertEqual(staleOther.0,409);XCTAssertEqual(library.state.name(group),"HTTP group")
      let leaves=library.state.nodes.filter{!$0.isGroup},ids=Set(leaves.prefix(2).map(\.id))
      var expected=library.state;try expected.apply(.move(ids,parent:group,before:nil))
      let moved=try await self.call(h,service,doc,"move",["nodeIDs":ids.map(\.uuidString),"parentID":group.uuidString]);XCTAssertEqual(moved.0,200);XCTAssertEqual(library.state,expected)
      try expected.apply(.rename(group,"Renamed HTTP group"))
      let renamed=try await self.call(h,service,doc,"rename",["nodeID":group.uuidString,"name":"Renamed HTTP group"]);XCTAssertEqual(renamed.0,200);XCTAssertEqual(library.state,expected)
      let selected=try await self.call(h,service,doc,"select",["nodeIDs":[leaves[0].id.uuidString],"activeID":leaves[0].id.uuidString]);XCTAssertEqual(selected.0,200);XCTAssertEqual(library.state.activeNodeID,leaves[0].id)
      let collapsed=try await self.call(h,service,doc,"collapse",["nodeID":group.uuidString,"collapsed":true]);XCTAssertEqual(collapsed.0,200);XCTAssertTrue(library.state.collapsed.contains(group))
      let copy=try await self.call(h,service,doc,"duplicate",["nodeIDs":[group.uuidString]]);XCTAssertEqual(copy.0,200)
      let copied=try XCTUnwrap((copy.1["createdNodeID"]as? String).flatMap(UUID.init(uuidString:)))
      let removed=try await self.call(h,service,doc,"delete",["nodeIDs":[copied.uuidString]]);XCTAssertEqual(removed.0,200);XCTAssertNil(library.state.node(copied))
      let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:PatternLibraryAPI.state(library)))
      XCTAssertNoThrow(try BrushAPI.merge(raw,schema:PatternLibraryAPI.stateSchema))
      let result=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:removed.1))
      XCTAssertNoThrow(try BrushAPI.merge(result,schema:PatternLibraryAPI.resultSchema))
      XCTAssertEqual(AutomationCommand.definitions.count,267)
      XCTAssertEqual(doc.store.document,d);XCTAssertEqual(try NativeArchive.encode(doc.store.document),bytes);XCTAssertTrue(doc.store.session.undoStack.isEmpty);XCTAssertFalse(doc.isDocumentEdited)
      _=PatternLibraryDrag.provider(store:other.store,nodeID:group)
      controller.removeDocument(other);otherAttached=false
      XCTAssertFalse(PatternLibraryDrag.canReceive(store:doc.store,parent:nil,before:nil))
    }
  }
  @MainActor func testHTTPImportSelectedPATExportDefineAllDepthsAndRestorePreserveCapturedSamples()async throws {
    let h=AutomationTests(),library=PatternLibrary(),imported=try imported(),data=try PATCodec.writeLibrary(imported)
    try await h.withService(patterns:library,pressedMouseButtons:{0}){service,doc in
      await doc.store.renderTask?.value;try service.share(doc)
      let response=try await self.call(h,service,doc,"import",["data":data.base64EncodedString()]);XCTAssertEqual(response.0,200)
      let group=try XCTUnwrap(library.state.nodes.first{$0.name=="Imported textures"})
      let exported=try await self.call(h,service,doc,"export",["nodeIDs":[group.id.uuidString]]);XCTAssertEqual(exported.0,200)
      let bytes=try XCTUnwrap((exported.1["data"]as? String).flatMap{Data(base64Encoded:$0)})
      let parsed=try PATCodec.readLibrary(bytes);XCTAssertEqual(parsed.nodes.filter(\.isGroup).map(\.name),["Imported textures","Empty"])
      XCTAssertEqual(parsed.patterns,try PATCodec.read(data))
      for depth in PixelDepth.allCases {
        let d=try self.fixture(depth);doc.store.session=EditorSession(document:d);await doc.store.renderTask?.value
        let expected=try PatternDefinition.make(in:d,name:"Defined \(depth.rawValue)")
        let made=try await self.call(h,service,doc,"define",["name":expected.name]);XCTAssertEqual(made.0,200)
        XCTAssertEqual(library.selected,expected);XCTAssertEqual(doc.store.document,d);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      }
      let selected=try XCTUnwrap(library.selected)
      let restore=try await self.call(h,service,doc,"reset.builtins");XCTAssertEqual(restore.0,200)
      XCTAssertEqual(library.items.first{$0.id==selected.id},selected)
    }
  }
  @MainActor func testHTTPInvalidStaleAndUnknownFieldsAreAtomic()async throws {
    let h=AutomationTests(),library=PatternLibrary()
    try await h.withService(patterns:library,pressedMouseButtons:{0}){service,doc in
      await doc.store.renderTask?.value;try service.share(doc)
      let rev=service.revision(doc.store),oldLibrary=library.revision
      let created=try await self.call(h,service,doc,"group.create",["name":"Group"]);XCTAssertEqual(created.0,200)
      let group=try XCTUnwrap(library.state.nodes.first{$0.isGroup}),before=library.state
      let stale=try await self.call(h,service,doc,"delete",["nodeIDs":[group.id.uuidString]],revision:rev);XCTAssertEqual(stale.0,409)
      let wrong=try await self.call(h,service,doc,"delete",["nodeIDs":[group.id.uuidString],"libraryRevision":oldLibrary.uuidString]);XCTAssertEqual(wrong.0,409)
      let invalid:[[String:Any]] = [["operation":"rename","nodeID":group.id.uuidString,"name":"No","data":"unused"],
        ["operation":"move","nodeIDs":[group.id.uuidString,group.id.uuidString]],
        ["operation":"collapse","nodeID":group.id.uuidString],
        ["operation":"import","data":"not base64"],
        ["operation":"group.create","name":" "]]
      for fields in invalid {
        let operation=fields["operation"]as! String;var extra=fields;extra.removeValue(forKey:"operation")
        let result=try await self.call(h,service,doc,operation,extra);XCTAssertTrue([400,422].contains(result.0))
        XCTAssertEqual(library.state,before)
      }
      let cycle=try await self.call(h,service,doc,"move",["nodeIDs":[group.id.uuidString],"parentID":group.id.uuidString]);XCTAssertEqual(cycle.0,422);XCTAssertEqual(library.state,before)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testActualHTTPBusyAndRevokedImportCannotReplacePersistentLibrary()async throws {
    let path=try folder();defer{try? FileManager.default.removeItem(at:path)}
    let gate=PatternImportGate();defer{gate.release()}
    let url=path.appendingPathComponent("Patterns.pclibrary")
    let library=PatternLibrary(persistenceURL:url,decoder:{data in gate.wait();return try PATCodec.readLibrary(data)})
    _=try await library.mutate(.createGroup("Retained",parent:nil))
    let before=library.state,file=try Data(contentsOf:url),data=try PATCodec.writeLibrary(imported()),h=AutomationTests()
    try await h.withService(patterns:library,pressedMouseButtons:{0}){service,doc in
      await doc.store.renderTask?.value;try service.share(doc)
      let task=Task{@MainActor in let result=try await self.call(h,service,doc,"import",["data":data.base64EncodedString()]);return result.0}
      try await self.started(gate);XCTAssertTrue(library.busy)
      let busy=try await self.call(h,service,doc,"group.create",["name":"Must not commit"]);XCTAssertEqual(busy.0,409)
      service.revoke(try XCTUnwrap(service.shares.first?.id));gate.release()
      let result=try await task.value;XCTAssertEqual(result,409)
      XCTAssertEqual(library.state,before);XCTAssertEqual(try Data(contentsOf:url),file);XCTAssertFalse(library.busy)
    }
  }
  @MainActor func testAcceptedHTTPImportSurvivesDisplayRenderButRejectsActualDocumentChange()async throws {
    let data=try PATCodec.writeLibrary(imported()),h=AutomationTests()
    for changeDocument in [false,true] {
      let gate=PatternImportGate();defer{gate.release()}
      let library=PatternLibrary(decoder:{data in gate.wait();return try PATCodec.readLibrary(data)})
      try await h.withService(patterns:library,pressedMouseButtons:{0}){service,doc in
        await doc.store.renderTask?.value;try service.share(doc)
        let state=library.state,document=doc.store.document,source=PatternDialogSource(doc.store),revision=service.revision(doc.store)
        let task=Task{@MainActor in let result=try await self.call(h,service,doc,"import",["data":data.base64EncodedString()]);return result.0}
        try await self.started(gate)
        if changeDocument {doc.store.perform(.renameLayer(try XCTUnwrap(doc.store.document.activeLayerID),"Changed during import"))}
        else{doc.store.render()}
        await doc.store.renderTask?.value
        XCTAssertNotEqual(revision,service.revision(doc.store))
        XCTAssertEqual(source.matches(doc.store),!changeDocument)
        if !changeDocument{XCTAssertEqual(doc.store.document,document)}
        gate.release();let status=try await task.value
        XCTAssertEqual(status,changeDocument ? 409:200)
        if changeDocument{XCTAssertEqual(library.state,state)}
        else if status==200{XCTAssertTrue(library.state.nodes.contains{$0.name=="Imported textures"});XCTAssertTrue(doc.store.session.undoStack.isEmpty)}
      }
    }
  }
  @MainActor func testReadOnlyMigrationCancellationAndStaleDialogPreserveFileAndPixels()async throws {
    let path=try folder();defer{try? FileManager.default.removeItem(at:path)}
    let url=path.appendingPathComponent("Patterns.pclibrary"),assets=try PatternPresets.make(),old=try PatternArchive.encode(assets,selectedID:assets.last?.id)
    try old.write(to:url);let gate=PatternImportGate();defer{gate.release()}
    let library=PatternLibrary(persistenceURL:url,decoder:{data in gate.wait();return try PATCodec.readLibrary(data)})
    await library.loadTask?.value;XCTAssertEqual(try Data(contentsOf:url),old)
    let before=library.state,data=try PATCodec.writeLibrary(imported())
    let task=Task{@MainActor in try await library.importData(data)};try await started(gate);task.cancel();gate.release()
    do{_=try await task.value;XCTFail("Cancelled import committed")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(library.state,before);XCTAssertEqual(try Data(contentsOf:url),old)
    let store=EditorStore(document:try fixture(),patterns:library);defer{store.renderTask?.cancel()}
    store.beginPatternGroup();let draft=try XCTUnwrap(store.patternNameDraft)
    library.selectedID=assets[0].id
    XCTAssertNil(store.commitPatternName(draft,name:"Stale"));XCTAssertNotNil(store.error);XCTAssertEqual(try Data(contentsOf:url),old)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testNativeHierarchyPanelRendersOffscreenWithGroupsAndUnchangedDocument()async throws {
    _=NSApplication.shared
    let library=PatternLibrary(),incoming=try PATCodec.readLibrary(PATCodec.writeLibrary(imported()));try await library.install(incoming)
    let store=EditorStore(document:try fixture(),patterns:library);defer{store.renderTask?.cancel()}
    let document=store.document,host=NSHostingView(rootView:PatternsPanel(store:store).background(StudioTheme.panel).environment(\.colorScheme,.dark));host.frame = .init(x:0,y:0,width:320,height:600)
    let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=host;defer{window.close()}
    host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(50))
    let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
    let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
    XCTAssertGreaterThan(data.count,1000);XCTAssertEqual(store.document,document)
    if let output=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try data.write(to:URL(fileURLWithPath:output).appendingPathComponent("pattern-library-groups.png"))
    }
  }
}
