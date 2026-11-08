import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class SkyGroupTests:XCTestCase {
  func directory()throws->URL {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("photato-sky-groups-\(UUID())")
    try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
  }
  func pixels()throws->Data{try RasterIO.encoded(SkyWorkflowTests().sky())}
  @MainActor func settled(_ model:SkyWorkspace)async{await model.task?.value;await model.task?.value}
  @MainActor func testLegacyMigrationGroupsMembershipAndExplicitDeletionPreserveImageBytes()throws {
    let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("skies.plist"),image=try pixels(),id=UUID()
    let legacy:[String:Any]=["version":1,"skies":[["id":id.uuidString,"name":"Legacy sky","data":image]]]
    let data=try PropertyListSerialization.data(fromPropertyList:legacy,format:.binary,options:0);try data.write(to:url)
    let library=SkyLibrary(persistenceURL:url);XCTAssertNil(library.loadError);XCTAssertTrue(library.groups.isEmpty)
    XCTAssertEqual(library.skies[0].id,id);XCTAssertNil(library.skies[0].groupID);XCTAssertEqual(try Data(contentsOf:url),data)
    let group=try library.createGroup("Sunsets"),other=try library.createGroup("Clouds")
    try library.move([id],to:group);try library.renameGroup(group,"夕焼け")
    let reopened=SkyLibrary(persistenceURL:url);XCTAssertNil(reopened.loadError);XCTAssertEqual(reopened.groups,library.groups);XCTAssertEqual(reopened.skies,library.skies)
    XCTAssertEqual(reopened.skies[0].data,image);XCTAssertEqual(reopened.skies[0].id,id)
    let stored=try PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as! [String:Any];XCTAssertEqual(stored["version"] as? Int,2)
    try library.deleteGroup(group,removeSkies:false);XCTAssertNil(library.skies[0].groupID);XCTAssertEqual(library.skies[0].data,image)
    try library.move([id],to:other);try library.deleteGroup(other,removeSkies:true);XCTAssertTrue(library.skies.isEmpty);XCTAssertTrue(library.groups.isEmpty)
    XCTAssertTrue(SkyLibrary(persistenceURL:url).skies.isEmpty)
  }
  @MainActor func testInvalidGroupsCapacityAndStorageFailuresAreAtomic()throws {
    let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
    let parent=folder.appendingPathComponent("library"),url=parent.appendingPathComponent("skies.plist"),library=SkyLibrary(persistenceURL:url)
    let preset=SkyPreset(name:"Original",data:try pixels());try library.add(preset);let group=try library.createGroup("Original group")
    let bytes=try Data(contentsOf:url),skies=library.skies,groups=library.groups,revision=library.revision
    for name in ["","  ",String(repeating:"🙂",count:128)]{XCTAssertThrowsError(try library.createGroup(name));XCTAssertThrowsError(try library.renameGroup(group,name))}
    XCTAssertThrowsError(try library.createGroup("Duplicate UUID",id:group));XCTAssertThrowsError(try library.move([preset.id],to:UUID()))
    XCTAssertThrowsError(try library.move([preset.id,preset.id],to:group));XCTAssertThrowsError(try library.move([UUID()],to:group))
    XCTAssertThrowsError(try library.append([preset],to:group,expectedRevision:revision));XCTAssertThrowsError(try library.append([.init(name:"Stale",data:preset.data)],to:group,expectedRevision:revision-1))
    XCTAssertEqual(library.skies,skies);XCTAssertEqual(library.groups,groups);XCTAssertEqual(library.revision,revision);XCTAssertEqual(try Data(contentsOf:url),bytes)
    let saved=folder.appendingPathComponent("saved");try FileManager.default.moveItem(at:parent,to:saved);try Data("blocked parent".utf8).write(to:parent)
    XCTAssertThrowsError(try library.renameGroup(group,"Unsaved"));XCTAssertEqual(library.groups,groups);XCTAssertEqual(library.revision,revision)
    XCTAssertEqual(try Data(contentsOf:saved.appendingPathComponent("skies.plist")),bytes)
    try FileManager.default.removeItem(at:parent);try FileManager.default.moveItem(at:saved,to:parent)
    for i in 1..<64{try library.createGroup("Group \(i)")};let fullRevision=library.revision;XCTAssertThrowsError(try library.createGroup("Too many"));XCTAssertEqual(library.revision,fullRevision)
    let images=(0..<63).map{SkyPreset(name:"Sky \($0)",data:preset.data)};try library.append(images,to:group,expectedRevision:library.revision)
    let fullSkies=library.skies;XCTAssertThrowsError(try library.append([.init(name:"Too many",data:preset.data)],to:group,expectedRevision:library.revision));XCTAssertEqual(library.skies,fullSkies)
  }
  @MainActor func testMalformedVersionAndDanglingGroupLibrariesArePreserved()throws {
    let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
    let image=try pixels(),id=UUID().uuidString
    let fixtures:[[String:Any]]=[
      ["version":99,"skies":[]],
      ["version":2,"skies":[["id":UUID().uuidString,"name":"Dangling","data":image,"groupID":id]],"groups":[]],
      ["version":2,"skies":[],"groups":[["id":id,"name":"One"],["id":id,"name":"Two"]]],
      ["version":1,"skies":[],"groups":[["id":id,"name":"Unexpected"]]]]
    for (i,fixture) in fixtures.enumerated(){
      let url=folder.appendingPathComponent("invalid\(i).plist"),bytes=try PropertyListSerialization.data(fromPropertyList:fixture,format:.binary,options:0);try bytes.write(to:url)
      let library=SkyLibrary(persistenceURL:url);XCTAssertNotNil(library.loadError);XCTAssertThrowsError(try library.createGroup("No overwrite"));XCTAssertEqual(try Data(contentsOf:url),bytes)
    }
  }
  @MainActor func testNativeGroupControlsCancelMoveFilterAndHistory()async throws {
    let helper=SkyWorkflowTests(),s=try helper.store();defer{s.cancelSkyReplacement();s.renderTask?.cancel()}
    let original=s.document;s.beginSkyReplacement();let model=try XCTUnwrap(s.skyWorkspace);await settled(model)
    let preset=try XCTUnwrap(s.skies.skies.first),revision=s.skies.revision
    model.beginSkyGroup(.create);let cancelled=try XCTUnwrap(model.groupDraft);cancelled.name="Cancelled";XCTAssertFalse(model.canCommit);model.cancelSkyGroup(cancelled)
    XCTAssertEqual(s.skies.revision,revision);XCTAssertTrue(s.skies.groups.isEmpty)
    model.beginSkyGroup(.create);let draft=try XCTUnwrap(model.groupDraft);draft.name="Sunsets";XCTAssertTrue(model.confirmSkyGroup(draft));await settled(model)
    let id=try XCTUnwrap(s.skies.groups.first?.id);XCTAssertEqual(model.groupFilter,.group(id));XCTAssertTrue(model.visibleSkies.isEmpty)
    model.filterSkies(.all);model.chooseSky(preset.id);await settled(model);let before=try Renderer.composite(XCTUnwrap(model.edit).result)
    model.moveSelectedSky(to:id);XCTAssertEqual(s.skies.skies[0].groupID,id);model.filterSkies(.group(id));XCTAssertEqual(model.visibleSkies.map(\.id),[preset.id])
    model.beginSkyGroup(.rename);let rename=try XCTUnwrap(model.groupDraft);rename.name="Evening";XCTAssertTrue(model.confirmSkyGroup(rename));XCTAssertEqual(s.skies.groups[0].name,"Evening")
    model.beginSkyGroup(.delete);let deletion=try XCTUnwrap(model.groupDraft);XCTAssertTrue(model.confirmSkyGroup(deletion));await settled(model)
    XCTAssertTrue(s.skies.groups.isEmpty);XCTAssertEqual(s.skies.skies[0].id,preset.id);XCTAssertEqual(s.skies.skies[0].data,preset.data);XCTAssertNil(s.skies.skies[0].groupID)
    XCTAssertEqual(try Renderer.composite(XCTUnwrap(model.edit).result),before);XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
    let host=NSHostingView(rootView:SkyGroupControls(model:model));host.frame=NSRect(x:0,y:0,width:280,height:140);host.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(host.fittingSize.width,300)
    let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:s.skyState));XCTAssertNoThrow(try BrushAPI.merge(raw,schema:SkyAPI.stateSchema))
  }
  @MainActor func testNativeStaleGroupDialogsAndInvalidNamesCanRetry()async throws {
    let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
    let library=SkyLibrary(persistenceURL:folder.appendingPathComponent("skies.plist"));try library.add(.init(name:"Sky",data:pixels()))
    let original=try SkyWorkflowTests().photo()
    for reason in ["selection","filter","library","closed","superseded"]{
      let model=SkyWorkspace(document:original,library:library);await model.prepare();await settled(model);defer{model.close()}
      model.beginSkyGroup(.create);let draft=try XCTUnwrap(model.groupDraft);draft.name="Must not save"
      switch reason{case "selection":var state=model.state;state.settings.flip.toggle();model.change(state)
      case "filter":model.groupFilter = .ungrouped
      case "library":try library.createGroup("Concurrent")
      case "closed":model.close()
      default:model.cancelSkyGroup(draft);model.beginSkyGroup(.create)}
      let before=library.groups,revision=library.revision;XCTAssertFalse(model.confirmSkyGroup(draft),reason);XCTAssertEqual(library.groups,before);XCTAssertEqual(library.revision,revision)
    }
    let model=SkyWorkspace(document:original,library:library);await model.prepare();await settled(model);defer{model.close()}
    model.beginSkyGroup(.create);let draft=try XCTUnwrap(model.groupDraft);draft.name=" ";XCTAssertFalse(model.confirmSkyGroup(draft));XCTAssertNotNil(draft.error)
    draft.name="Valid";XCTAssertTrue(model.confirmSkyGroup(draft));XCTAssertTrue(library.groups.contains{$0.name=="Valid"})
  }
  @MainActor func testNativeBatchImportAllOrNothingMembershipAndCloseCancellation()async throws {
    let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
    let one=folder.appendingPathComponent("One.png"),two=folder.appendingPathComponent("Two.png"),bad=folder.appendingPathComponent("Bad.png"),image=try pixels()
    try image.write(to:one);try image.write(to:two);try Data("invalid".utf8).write(to:bad)
    let library=SkyLibrary(persistenceURL:folder.appendingPathComponent("skies.plist")),group=try library.createGroup("Imported")
    let model=SkyWorkspace(document:try SkyWorkflowTests().photo(),library:library);await model.prepare();defer{model.close()};model.filterSkies(.group(group))
    let bytes=try Data(contentsOf:library.persistenceURL!),revision=library.revision
    model.loadSkies([one,bad]);await model.importTask?.value;XCTAssertNotNil(model.error);XCTAssertTrue(library.skies.isEmpty);XCTAssertEqual(library.revision,revision);XCTAssertEqual(try Data(contentsOf:library.persistenceURL!),bytes)
    model.loadSkies([one,two]);await model.importTask?.value;await settled(model)
    XCTAssertNil(model.error);XCTAssertEqual(library.skies.map(\.name),["One","Two"]);XCTAssertEqual(library.skies.map(\.groupID),[group,group]);XCTAssertTrue(library.skies.allSatisfy{$0.data==image});XCTAssertEqual(library.revision,revision+1);XCTAssertTrue(model.canCommit)
    let before=library.skies;model.loadSkies([one,two]);model.close();await model.importTask?.value;XCTAssertEqual(library.skies,before)
    XCTAssertThrowsError(try SkyImportPreparation.load([]));XCTAssertThrowsError(try SkyImportPreparation.load([URL(string:"https://example.invalid/sky.png")!]))
  }
  @MainActor func testHTTPGroupsBatchImportsNativeEqualityAndPersistence()async throws {
    let folder=try directory();defer{try? FileManager.default.removeItem(at:folder)}
    let library=SkyLibrary(persistenceURL:folder.appendingPathComponent("skies.plist")),helper=AutomationTests(),image=try pixels()
    try await helper.withService(skies:library,pressedMouseButtons:{0}){service,document in
      let original=document.store.document;try service.share(document)
      var status=try await helper.edit(service,document,"sky.library",["operation":"group.create","name":"Sunsets"]);XCTAssertEqual(status,200)
      let group=try XCTUnwrap(library.groups.first?.id),images=[["name":"One","data":image.base64EncodedString()],["name":"Two","data":image.base64EncodedString()]]
      status=try await helper.edit(service,document,"sky.library",["operation":"importBatch","groupID":group.uuidString,"images":images]);XCTAssertEqual(status,200)
      XCTAssertEqual(library.skies.map(\.name),["One","Two"]);XCTAssertTrue(library.skies.allSatisfy{$0.groupID==group && $0.data==image})
      let ids=library.skies.map(\.id),native=SkyLibrary();try native.createGroup("Sunsets",id:group);try native.append(library.skies,to:group,expectedRevision:native.revision)
      try native.renameGroup(group,"Evening");status=try await helper.edit(service,document,"sky.library",["operation":"group.rename","groupID":group.uuidString,"name":"Evening"]);XCTAssertEqual(status,200)
      XCTAssertEqual(library.groups,native.groups);XCTAssertEqual(library.skies,native.skies)
      status=try await helper.edit(service,document,"sky.library",["operation":"move","skyIDs":[ids[0].uuidString],"groupID":NSNull()]);XCTAssertEqual(status,200);try native.move([ids[0]],to:nil);XCTAssertEqual(library.skies,native.skies)
      status=try await helper.edit(service,document,"sky.library",["operation":"group.delete","groupID":group.uuidString,"removeSkies":false]);XCTAssertEqual(status,200);try native.deleteGroup(group,removeSkies:false)
      XCTAssertEqual(library.skies,native.skies);XCTAssertEqual(library.groups,native.groups);XCTAssertEqual(SkyLibrary(persistenceURL:library.persistenceURL).skies,native.skies)
      status=try await helper.edit(service,document,"sky.library",["operation":"group.create","name":"Remove"]);XCTAssertEqual(status,200);let remove=library.groups[0].id
      status=try await helper.edit(service,document,"sky.library",["operation":"move","skyIDs":ids.map(\.uuidString),"groupID":remove.uuidString]);XCTAssertEqual(status,200)
      status=try await helper.edit(service,document,"sky.library",["operation":"group.delete","groupID":remove.uuidString,"removeSkies":true]);XCTAssertEqual(status,200);XCTAssertTrue(library.skies.isEmpty)
      XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertEqual(AutomationCommand.definitions.count,267);XCTAssertEqual(try JSONSerialization.data(withJSONObject:SkyLibraryAPI.parameterSchema).isEmpty,false)
      let raw=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:document.store.skyState));XCTAssertNoThrow(try BrushAPI.merge(raw,schema:SkyAPI.stateSchema))
    }
  }
  @MainActor func testHTTPStrictStaleBusyAndInvalidBatchLeaveLibraryUntouched()async throws {
    let library=SkyLibrary(),helper=AutomationTests(),image=try pixels(),group=try library.createGroup("Original")
    try await helper.withService(skies:library,pressedMouseButtons:{0}){service,document in
      try service.share(document);let original=document.store.document,revision=library.revision
      let malformed:[[String:Any]]=[
        ["operation":"group.delete","groupID":group.uuidString],
        ["operation":"group.rename","groupID":NSNull(),"name":"Bad"],
        ["operation":"group.create","name":"Bad","data":"irrelevant"],
        ["operation":"move","skyIDs":[],"groupID":NSNull()],
        ["operation":"importBatch","images":[]],
        ["operation":"importBatch","images":[["name":"Bad","data":image.base64EncodedString(),"extra":true]]],
        ["operation":"importBatch","images":[["name":"Bad","data":"invalid"]]]]
      for params in malformed{let status=try await helper.edit(service,document,"sky.library",params);XCTAssertEqual(status,400);XCTAssertEqual(library.revision,revision)}
      let params:[String:Any]=["operation":"importBatch","images":[["name":"Good","data":image.base64EncodedString()],["name":"Invalid image","data":Data("bad pixels".utf8).base64EncodedString()]]]
      var status=try await helper.edit(service,document,"sky.library",params);XCTAssertEqual(status,422);XCTAssertTrue(library.skies.isEmpty);XCTAssertEqual(library.revision,revision)
      status=try await helper.edit(service,document,"sky.library",["operation":"group.rename","groupID":group.uuidString,"name":"Stale"],revision:"stale");XCTAssertEqual(status,409)
      document.store.geometryBusy=true;status=try await helper.edit(service,document,"sky.library",["operation":"group.create","name":"Busy"]);XCTAssertEqual(status,409);document.store.geometryBusy=false
      XCTAssertEqual(library.groups.map(\.name),["Original"]);XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPBatchRevocationOrLibraryChangePreventsPublication()async throws {
    for revoke in [true,false]{
      let library=SkyLibrary(),helper=AutomationTests(),image=try RasterIO.encoded(CraftDocument(width:1024,height:768))
      try await helper.withService(skies:library,pressedMouseButtons:{0}){service,document in
        try service.share(document);let original=document.store.document
        let task=Task{try await helper.edit(service,document,"sky.library",["operation":"importBatch","images":[["name":"One","data":image.base64EncodedString()],["name":"Two","data":image.base64EncodedString()]]])}
        // The request begins on MainActor; observe its actual preparation suspension.
        for _ in 0..<500 where !document.store.geometryBusy{try await Task.sleep(for:.milliseconds(1))}
        XCTAssertTrue(document.store.geometryBusy)
        if revoke{service.revoke(try XCTUnwrap(service.shares.first?.id))}else{try library.createGroup("Concurrent")}
        let status=try await task.value;XCTAssertEqual(status,409);XCTAssertTrue(library.skies.isEmpty);XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      }
    }
  }
}
