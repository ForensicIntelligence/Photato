import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class TextQueryGate:@unchecked Sendable {
  private let lock=NSLock(),semaphore=DispatchSemaphore(value:0)
  private var started=false
  var entered:Bool{lock.lock();defer{lock.unlock()};return started}
  func wait(){lock.lock();started=true;lock.unlock();semaphore.wait()}
  func release(){semaphore.signal()}
}
final class TextFindWorkflowTests:XCTestCase {
  func fixture(_ string:String = "cat cat",depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:400,height:180,depth:depth);var text=TextContent(text:string,size:24,color:.black)
    var type=TextTypography();type.defaultStyle.size=24;type.defaultStyle.color = .black;text.typography=type
    var layer=Layer(name:"Body",content:.text(text));layer.x=18;layer.y=20
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
  func texts(_ document:CraftDocument)->[String]{document.layers.compactMap{if case .text(let text)=$0.content{return text.text};return nil}}
  func capture(_ value:[String:Any],_ name:String)throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_TEXT_FIND_OUTPUT_DIR"]else{return}
    let directory=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent(name+".json"))
  }
  @MainActor func testNativeDialogFindChangeChangeFindAllMenuAndHistory()async throws {
    let source=try fixture(),store=EditorStore(document:source,actions:ActionLibrary());defer{store.closeTextFind();store.renderTask?.cancel()}
    store.beginTextFind();let workspace=try XCTUnwrap(store.textFindWorkspace);XCTAssertFalse(workspace.allLayers)
    workspace.find="cat";workspace.replacement="dog"
    let view=NSHostingView(rootView:TextFindSheet(store:store,workspace:workspace));view.frame=NSRect(x:0,y:0,width:620,height:360);view.layoutSubtreeIfNeeded();XCTAssertLessThanOrEqual(view.fittingSize.width,650)
    try store.session.startActionRecording(name:"Terms")
    store.findNextText(workspace);await workspace.task?.value
    XCTAssertEqual(workspace.current?.location,0);XCTAssertNotNil(workspace.preview);XCTAssertEqual(store.document,source);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.changeFoundText(workspace);await workspace.task?.value
    XCTAssertNil(workspace.error);XCTAssertEqual(texts(store.document),["dog cat"]);XCTAssertEqual(store.session.undoStack.count,1)
    store.findNextText(workspace);await workspace.task?.value;XCTAssertEqual(workspace.current?.location,4)
    store.changeFoundText(workspace,findNext:true);let change=workspace.task;await change?.value;await workspace.task?.value
    XCTAssertNil(workspace.error);XCTAssertEqual(texts(store.document),["dog dog"]);XCTAssertNil(workspace.current)
    workspace.find="dog";workspace.replacement="bird";store.changeFoundText(workspace,all:true);await workspace.task?.value
    XCTAssertNil(workspace.error);XCTAssertEqual(texts(store.document),["bird bird"]);XCTAssertEqual(store.session.undoStack.count,3)
    XCTAssertEqual(store.session.actionRecording?.snapshot.steps.count,3);store.closeTextFind()
    let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(texts(store.document),["dog dog"])
    let redo=await store.redo();XCTAssertTrue(redo);XCTAssertEqual(texts(store.document),["bird bird"])
    try capture(["texts":texts(store.document),"undoStates":store.session.undoStack.count],"native-controls")
    try PhotoshopMenuTests().withMenus{_,menu in
      let item=try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first{$0.identifier?.rawValue=="Edit > Find and Replace Text…"})
      XCTAssertEqual(item.action,#selector(AppDelegate.findReplaceText));XCTAssertEqual(item.keyEquivalent,"")
    }
  }
  @MainActor func testNonTypeLayerSearchAllScopeAdvancesAcrossLayersAndCommitsOneUndo()async throws {
    var source=try fixture("cat");var caption=source.layers[0];caption.id=UUID();caption.name="Caption";source.layers.append(caption)
    let image=Layer(name:"Image",content:.raster(try Surface(width:400,height:180,fill:.white)))
    source.layers.insert(image,at:0);source.activeLayerID=image.id;try source.validate()
    let store=EditorStore(document:source,actions:ActionLibrary());defer{store.closeTextFind();store.renderTask?.cancel()}
    store.beginTextFind();let workspace=try XCTUnwrap(store.textFindWorkspace)
    XCTAssertTrue(workspace.allLayers);XCTAssertTrue(workspace.canChooseAllLayers)
    workspace.find="cat";workspace.replacement="dog";store.findNextText(workspace);await workspace.task?.value
    XCTAssertEqual(workspace.current?.layerID,caption.id)
    store.findNextText(workspace);await workspace.task?.value;XCTAssertEqual(workspace.current?.layerID,source.layers[1].id)
    XCTAssertEqual(store.document,source);XCTAssertTrue(store.session.undoStack.isEmpty)
    store.changeFoundText(workspace,all:true);await workspace.task?.value
    XCTAssertNil(workspace.error);XCTAssertEqual(texts(store.document),["dog","dog"]);XCTAssertEqual(store.document.layers[0],image);XCTAssertEqual(store.session.undoStack.count,1)
    let changed=store.document;store.closeTextFind();let undo=await store.undo();XCTAssertTrue(undo);XCTAssertEqual(store.document,source)
    let redo=await store.redo();XCTAssertTrue(redo);XCTAssertEqual(store.document,changed)
    try capture(["texts":texts(store.document),"undoStates":store.session.undoStack.count,"initialAllLayers":true],"native-all-layers")
  }
  @MainActor func testCaretForwardCloseStaleAndDocumentCloseLifecycle()async throws {
    _ = NSApplication.shared
    let source=try fixture(),document=CraftNSDocument(model:source,actions:ActionLibrary()),store=document.store
    defer{store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close()}
    store.beginType(try XCTUnwrap(store.activeLayer));let draft=try XCTUnwrap(store.typeEditingDraft)
    let editor=try CanvasTypeEditor(store:store,draft:draft);store.typeEditor=editor;editor.setSelectedRange(NSRange(location:4,length:0))
    store.beginTextFind();let forward=try XCTUnwrap(store.textFindWorkspace);let searchBaseline=store.document,searchHistory=store.session.undoStack.count;forward.find="cat";store.findNextText(forward);await forward.task?.value
    XCTAssertEqual(forward.current?.location,4);forward.forward=false;store.findNextText(forward);await forward.task?.value;XCTAssertEqual(forward.current?.location,0)
    XCTAssertEqual(store.document,searchBaseline);store.closeTextFind();XCTAssertEqual(store.session.undoStack.count,searchHistory)
    store.beginTextFind();let stale=try XCTUnwrap(store.textFindWorkspace);stale.find="cat";store.session=EditorSession(document:try fixture("changed"));let before=store.document
    store.changeFoundText(stale,all:true);XCTAssertNotNil(stale.error);XCTAssertEqual(store.document,before);store.closeTextFind()
    store.beginTextFind();let closing=try XCTUnwrap(store.textFindWorkspace);closing.find="changed";store.findNextText(closing);let task=closing.task
    document.close();await task?.value;XCTAssertNil(store.textFindWorkspace);XCTAssertEqual(store.document,before)
  }
  @MainActor func testHTTPPagedReadOnlyQueryNativeReplacementAndStrictGuards()async throws {
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
      let source=try fixture();shared.store.session=EditorSession(document:source);shared.store.renderTask?.cancel();try service.share(shared);service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(service.shares.first?.id),revision=service.revision(shared.store)
      let query=try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"text.find","revision":revision,"parameters":["find":"cat","offset":1,"limit":1]])
      XCTAssertEqual(query.0.statusCode,200);let body=try XCTUnwrap(JSONSerialization.jsonObject(with:query.1)as?[String:Any]);let result=try XCTUnwrap(body["textSearchResult"]as?[String:Any])
      XCTAssertEqual(result["total"]as?Int,2);XCTAssertEqual((result["matches"]as?[[String:Any]])?.first?["location"]as?Int,4)
      XCTAssertEqual(shared.store.document,source);XCTAssertTrue(shared.store.session.undoStack.isEmpty);XCTAssertEqual(service.revision(shared.store),revision)
      try capture(result,"api-query")
      let native=EditorStore(document:source,actions:ActionLibrary());defer{native.closeTextFind();native.renderTask?.cancel()}
      native.beginTextFind();let workspace=try XCTUnwrap(native.textFindWorkspace);workspace.find="cat";workspace.replacement="dog";native.changeFoundText(workspace,all:true);await workspace.task?.value
      let code=try await helper.edit(service,shared,"text.replace",["find":"cat","replacement":"dog"]);XCTAssertEqual(code,200);XCTAssertEqual(shared.store.document,native.document);XCTAssertEqual(shared.store.session.undoStack.count,1)
      let download=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"85"]);XCTAssertEqual(download.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(download.1),native.document)
      let deleted=try await helper.edit(service,shared,"text.replace",["find":"dog","replacement":""]);XCTAssertEqual(deleted,200);XCTAssertEqual(texts(shared.store.document),[" "])
      let stable=shared.store.document
      for parameters:[String:Any]in [["find":"","replacement":"x"],["find":"cat","replacement":1],["find":"cat","replacement":"x","wholeWord":1],["find":"cat","replacement":"x","start":0.5],["find":"cat","replacement":"x","extra":true]] {
        let bad=try await helper.edit(service,shared,"text.replace",parameters);XCTAssertEqual(bad,400);XCTAssertEqual(shared.store.document,stable)
      }
      let stale=try await helper.edit(service,shared,"text.replace",["find":"x","replacement":"y"],revision:"old");XCTAssertEqual(stale,409)
      shared.store.beginTextFind();let busy=try await helper.edit(service,shared,"text.find",["find":"x"]);XCTAssertEqual(busy,409);shared.store.closeTextFind()
      let caps=try await helper.request(service,path:"/v1/capabilities");let values=try XCTUnwrap(JSONSerialization.jsonObject(with:caps.1)as?[String:Any]);XCTAssertNotNil(values["textFind"]);XCTAssertNotNil((values["stateSchemas"]as?[String:Any])?["textFind"])
      XCTAssertEqual(AutomationCommand.definitions.count,242);XCTAssertEqual(ActionLibraryFile.maximumVersion,46)
      try capture(["texts":texts(shared.store.document),"undoStates":shared.store.session.undoStack.count],"api-delete")
    }
  }
  @MainActor func testHTTPInFlightSharingRevocationRejectsQueryWithoutMutation()async throws {
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
      let source=try fixture(),gate=TextQueryGate();defer{gate.release()}
      shared.store.session=EditorSession(document:source);shared.store.renderTask?.cancel();try service.share(shared)
      shared.store.textSearchPreparation={model,settings,id,start,offset,limit in gate.wait();return try NativeTextSearch.scan(model,settings:settings,layerID:id,start:start,offset:offset,limit:limit)}
      let id=try XCTUnwrap(service.shares.first?.id),revision=service.revision(shared.store)
      let task=Task{try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"text.find","revision":revision,"parameters":["find":"cat"]])}
      for _ in 0..<500 where !gate.entered {try await Task.sleep(for:.milliseconds(1))}
      XCTAssertTrue(gate.entered);service.revoke(id);gate.release();let reply=try await task.value
      XCTAssertEqual(reply.0.statusCode,409);XCTAssertEqual(shared.store.document,source);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testActions46SemanticBatchNoOpAndLongMultilineInput()async throws {
    var source=try fixture();source.layers[0].name=String(repeating:"層",count:400)
    let store=EditorStore(document:source,actions:ActionLibrary());defer{store.closeTextFind();store.renderTask?.cancel()}
    try store.session.startActionRecording(name:"Find cats")
    store.beginTextFind();let workspace=try XCTUnwrap(store.textFindWorkspace);workspace.find="absent";workspace.replacement="dog";store.changeFoundText(workspace,all:true);await workspace.task?.value
    XCTAssertEqual(store.document,source);XCTAssertTrue(store.session.undoStack.isEmpty);XCTAssertEqual(store.session.actionRecording?.snapshot.steps.count,1);store.closeTextFind()
    let request=RecordedTextReplacement(settings:.init(find:"cat"),replacement:"dog")
    let action=RecordedAction(name:"Update cats",steps:[.init(name:"Replace All Text",operation:.replaceText(request))]);let data=try ActionLibraryFile(actions:[action]).encoded();XCTAssertEqual(try ActionLibraryFile.decode(data).version,46)
    var old=try XCTUnwrap(JSONSerialization.jsonObject(with:data)as?[String:Any]);old["version"]=45;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)));old["version"]=47;XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject:old)))
    let directory=try ActionBatchTests().folder();defer{try? FileManager.default.removeItem(at:directory)}
    let sources=try [fixture("cat"),fixture("catapult CAT")];let results=try await ActionBatch.run(sources:sources.map(ActionBatchSource.init(document:)),action:action,destination:directory,format:.native)
    var outputTexts:[[String]]=[]
    for (i,result)in results.enumerated(){XCTAssertNil(result.error);let file=try XCTUnwrap(result.output);let reopened=try DocumentIO.read(directory.appendingPathComponent(file));XCTAssertEqual(reopened.id,sources[i].id);outputTexts.append(texts(reopened))}
    XCTAssertEqual(outputTexts,[["dog"],["dogapult dog"]]);try capture(["texts":outputTexts],"batch-action")
    let helper=AutomationTests();try await helper.withService(actions:ActionLibrary(),pressedMouseButtons:{0}){service,shared in
      let long=String(repeating:"x",count:300)+"\ncat";shared.store.session=EditorSession(document:try fixture(long));try service.share(shared)
      let code=try await helper.edit(service,shared,"text.replace",["find":long,"replacement":"two\nlines"]);XCTAssertEqual(code,200);XCTAssertEqual(texts(shared.store.document),["two\nlines"])
    }
  }
}
