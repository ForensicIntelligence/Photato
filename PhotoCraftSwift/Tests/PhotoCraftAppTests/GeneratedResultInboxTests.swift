import AppKit
import CryptoKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class GeneratedResultInboxTests:XCTestCase {
  func directory()throws->URL {
    let root=try DocumentPersistenceTests().directory()
    addTeardownBlock{try? FileManager.default.removeItem(at:root)};return root
  }
  func ownedResult(id:UUID=UUID(),prompt:String="Owned recovery fixture")throws->(GenerationRecord,Data) {
    let bytes=try ImageGenerationLifecycleTests().image()
    return(try GeneratedImageStorage.generationRecord(bytes,requestID:id,sourceDocumentID:UUID(),sourceRevision:UUID(),initialPrompt:prompt,startedAt:Date(timeIntervalSince1970:100),acceptedAt:Date(timeIntervalSince1970:101),processing:.unknown,resultStyle:nil),bytes)
  }
  func testAtomicPersistenceSurvivesNewInstanceAndIdempotentQuota()throws {
    let root=try directory(),inbox=GeneratedResultInbox(directory:root,maximumEntries:1),value=try ownedResult()
    try inbox.persist(value.0,original:value.1)
    let originalFile=try Data(contentsOf:root.appendingPathComponent(value.0.requestID.uuidString+".phtgen"))
    XCTAssertEqual(try inbox.persist(value.0,original:value.1),value.0.requestID)
    let reopened=GeneratedResultInbox(directory:root),loaded=try reopened.load(value.0.requestID)
    XCTAssertEqual(loaded.0,value.0);XCTAssertEqual(loaded.1,value.1)
    XCTAssertEqual(try reopened.list().map(\.id),[value.0.requestID]);XCTAssertThrowsError(try inbox.preflight())
    let second=try ownedResult();XCTAssertThrowsError(try inbox.persist(second.0,original:second.1))
    XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(value.0.requestID.uuidString+".phtgen")),originalFile)
  }
  func testConflictingRequestAndFailedAtomicWritePreserveExistingOriginal()throws {
    let root=try directory(),inbox=GeneratedResultInbox(directory:root),first=try ownedResult()
    try inbox.persist(first.0,original:first.1)
    let conflict=try ownedResult(id:first.0.requestID,prompt:"A different record")
    XCTAssertThrowsError(try inbox.persist(conflict.0,original:conflict.1))
    let failing=GeneratedResultInbox(directory:root,write:{url,bytes in
      let writer=try AtomicFileWriter(to:url,maximumBytes:GeneratedResultInbox.archiveLimit,followSymbolicLinks:false)
      defer{writer.discard()};try writer.append(bytes.prefix(31));throw CraftError.invalid("Owned interrupted write")
    }),second=try ownedResult()
    XCTAssertThrowsError(try failing.persist(second.0,original:second.1))
    XCTAssertEqual(try inbox.load(first.0.requestID).1,first.1)
    XCTAssertThrowsError(try inbox.load(second.0.requestID));XCTAssertEqual(try inbox.list().count,1)
  }
  func testCorruptVersionHashAndOversizeRemainVisibleWithoutHidingGoodResults()throws {
    let root=try directory(),inbox=GeneratedResultInbox(directory:root),good=try ownedResult()
    try inbox.persist(good.0,original:good.1)
    for field in ["version","original"] {
      let value=try ownedResult();try inbox.persist(value.0,original:value.1)
      let file=root.appendingPathComponent(value.0.requestID.uuidString+".phtgen")
      var plist=try XCTUnwrap(PropertyListSerialization.propertyList(from:Data(contentsOf:file),format:nil) as? [String:Any])
      plist[field]=field=="version" ? 99 : Data([1,2,3]) as Any
      try PropertyListSerialization.data(fromPropertyList:plist,format:.binary,options:0).write(to:file)
      XCTAssertThrowsError(try inbox.load(value.0.requestID))
    }
    let bigID=UUID(),big=root.appendingPathComponent(bigID.uuidString+".phtgen")
    XCTAssertTrue(FileManager.default.createFile(atPath:big.path,contents:Data()))
    let handle=try FileHandle(forWritingTo:big);try handle.truncate(atOffset:UInt64(GeneratedResultInbox.archiveLimit+1));try handle.close()
    XCTAssertThrowsError(try inbox.load(bigID))
    let rows=try inbox.list();XCTAssertEqual(rows.count,4);XCTAssertEqual(rows.filter{$0.error != nil}.count,3)
    XCTAssertEqual(try inbox.load(good.0.requestID).1,good.1)
  }
  func testSymlinkRootAndItemDoNotReadOutsideInbox()throws {
    let root=try directory(),outside=try directory(),id=UUID(),outsideFile=outside.appendingPathComponent("owned.bin")
    try Data("Outside owned fixture".utf8).write(to:outsideFile)
    let item=root.appendingPathComponent(id.uuidString+".phtgen")
    try FileManager.default.createSymbolicLink(at:item,withDestinationURL:outsideFile)
    let inbox=GeneratedResultInbox(directory:root)
    XCTAssertThrowsError(try inbox.load(id));XCTAssertThrowsError(try inbox.identity(id));XCTAssertNotNil(try inbox.list().first?.error)
    let link=root.appendingPathComponent("linked-root")
    try FileManager.default.createSymbolicLink(at:link,withDestinationURL:outside)
    XCTAssertThrowsError(try GeneratedResultInbox(directory:link).preflight())
    XCTAssertEqual(try Data(contentsOf:outsideFile),Data("Outside owned fixture".utf8))
  }
  func testExplicitTrashIsReversibleAndDoesNotPurgeOtherItems()throws {
    let root=try directory(),trash=try directory()
    let inbox=GeneratedResultInbox(directory:root,trash:{try FileManager.default.moveItem(at:$0,to:trash.appendingPathComponent($0.lastPathComponent))})
    let first=try ownedResult(),second=try ownedResult();try inbox.persist(first.0,original:first.1);try inbox.persist(second.0,original:second.1)
    let stamp=try inbox.identity(first.0.requestID);XCTAssertGreaterThan(stamp.size,0)
    try inbox.moveToTrash(first.0.requestID);XCTAssertThrowsError(try inbox.identity(first.0.requestID))
    XCTAssertEqual(try inbox.list().map(\.id),[second.0.requestID]);XCTAssertEqual(try inbox.load(second.0.requestID).1,second.1)
    let name=first.0.requestID.uuidString+".phtgen"
    try FileManager.default.moveItem(at:trash.appendingPathComponent(name),to:root.appendingPathComponent(name))
    XCTAssertEqual(try inbox.load(first.0.requestID).1,first.1)
  }
  @MainActor func testStorageFailureKeepsSystemRequestAvailableForRetry()throws {
    let h=ImageGenerationLifecycleTests(),s=EditorStore(document:try CraftDocument(width:8,height:6))
    s.generatedResultInbox=GeneratedResultInbox(directory:try directory())
    let before=s.document,job=try h.begin(s),bytes=try h.image()
    defer{s.renderTask?.cancel();s.cancelAIWork()}
    let root=try directory();s.generatedResultInbox=GeneratedResultInbox(directory:root,write:{_,_ in throw CraftError.invalid("Owned disk failure")})
    XCTAssertThrowsError(try s.acceptGeneratedImageData(bytes,requestID:job.id))
    XCTAssertEqual(job.phase,.awaitingSystem);XCTAssertTrue(s.showImagePlayground);XCTAssertTrue(s.aiBusy)
    XCTAssertNil(job.retainedResultID);XCTAssertTrue(s.authorizedGeneratedResults.isEmpty);XCTAssertEqual(s.document,before)
    s.generatedResultInbox=GeneratedResultInbox(directory:root)
    try s.acceptGeneratedImageData(bytes,requestID:job.id)
    XCTAssertEqual(job.retainedResultID,job.id);XCTAssertEqual(try s.generatedResultInbox.load(job.id).1,bytes)
  }
  @MainActor func testPreflightRejectsFullInboxBeforePresentingProvider()throws {
    let s=EditorStore(document:try CraftDocument(width:8,height:6));defer{s.renderTask?.cancel();s.cancelAIWork()}
    s.generatedResultInbox=GeneratedResultInbox(directory:try directory(),maximumBytes:1)
    s.prompt="Owned fixture";s.beginImageCreation(capability:AICapability(available:true,message:"No model"))
    XCTAssertFalse(s.showImagePlayground);XCTAssertFalse(s.aiBusy);XCTAssertNil(s.imageGenerationJob);XCTAssertNotNil(s.aiError)
    XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testPreparationFailureAndCancelledPlacementRetainOriginalAcrossRestart()async throws {
    let h=ImageGenerationLifecycleTests(),s=EditorStore(document:try CraftDocument(width:8,height:6));defer{s.renderTask?.cancel();s.cancelAIWork()}
    let root=try directory();s.generatedResultInbox=GeneratedResultInbox(directory:root)
    let bytes=try h.image(),before=s.document
    s.imageGenerationPreparation={_,_,_,_,_,_,_,_,_ in throw CraftError.invalid("Owned preparation failure")}
    let failed=try h.begin(s);try s.acceptGeneratedImageData(bytes,requestID:failed.id)
    let task=try XCTUnwrap(s.aiTask);await task.value
    XCTAssertEqual(failed.phase,.failed);XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
    let gate=ImageGenerationLifecycleTests.Gate()
    s.imageGenerationPreparation={_,_,_,_,_,_,_,_,_ in await gate.wait();return Layer(name:"Uncommitted",content:.raster(try Surface(width:1,height:1)))}
    let cancelled=try h.begin(s);try s.acceptGeneratedImageData(bytes,requestID:cancelled.id)
    let pending=try XCTUnwrap(s.aiTask);try await h.wait(gate);s.cancelAIWork();await gate.release();await pending.value
    XCTAssertEqual(cancelled.phase,.cancelled);XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
    let reopened=GeneratedResultInbox(directory:root)
    XCTAssertEqual(try reopened.load(failed.id).1,bytes);XCTAssertEqual(try reopened.load(cancelled.id).1,bytes)
  }
  @MainActor func testRecoveredOriginalCreatesSeparateUnsavedNativeDocumentWithoutModel()async throws {
    let root=try directory(),inbox=GeneratedResultInbox(directory:root),value=try ownedResult();try inbox.persist(value.0,original:value.1)
    let controller=CraftDocumentController(workspaces:WorkspaceLibrary()),browser=GeneratedResultsBrowser(inbox:inbox,controller:controller)
    browser.refresh();let refresh=try XCTUnwrap(browser.task);await refresh.value
    XCTAssertEqual(browser.selected,value.0.requestID);XCTAssertFalse(browser.busy)
    let source=try CraftDocument(width:8,height:6),loaded=try GeneratedResultInbox(directory:root).load(value.0.requestID)
    let model=try GeneratedImageStorage.recoveredDocument(loaded.0,original:loaded.1),doc=browser.publish(model,display:false)
    defer{doc.store.renderTask?.cancel();controller.removeDocument(doc);doc.close();browser.cancel()}
    XCTAssertNotEqual(model.id,value.0.sourceDocumentID);XCTAssertNotEqual(model.id,source.id)
    XCTAssertTrue(doc.isDocumentEdited);XCTAssertNil(doc.fileURL);XCTAssertNil(doc.store.imageGenerationJob);XCTAssertFalse(doc.store.aiBusy)
    XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(model.layers.first)).1,value.1)
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(model)),model)
    XCTAssertEqual(source.layers.count,1);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    browser.refresh();browser.cancel();XCTAssertFalse(browser.busy)
  }
  @MainActor func testCloseDuringPreparationKeepsOriginalForOfflineRecovery()async throws {
    // Match application startup: establish the custom AppKit singleton before a
    // registered document is closed. A bare unregistered NSDocument can create
    // a base NSDocumentController first, whose Swift subclass fields do not exist.
    let controller=CraftDocumentController(workspaces:WorkspaceLibrary())
    let h=ImageGenerationLifecycleTests(),root=try directory(),doc=CraftNSDocument(model:try CraftDocument(width:8,height:6))
    controller.addDocument(doc)
    defer{if controller.documents.contains(where:{$0===doc}){controller.removeDocument(doc)}}
    doc.store.renderTask?.cancel();doc.store.generatedResultInbox=GeneratedResultInbox(directory:root)
    let gate=ImageGenerationLifecycleTests.Gate(),bytes=try h.image(),before=doc.store.document
    doc.store.imageGenerationPreparation={_,_,_,_,_,_,_,_,_ in await gate.wait();return Layer(name:"Uncommitted",content:.raster(try Surface(width:1,height:1)))}
    let job=try h.begin(doc.store);try doc.store.acceptGeneratedImageData(bytes,requestID:job.id)
    let pending=try XCTUnwrap(doc.store.aiTask);try await h.wait(gate);doc.close()
    await gate.release();await pending.value;doc.store.renderTask?.cancel()
    XCTAssertEqual(job.phase,.cancelled);XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    XCTAssertEqual(try GeneratedResultInbox(directory:root).load(job.id).1,bytes)
    XCTAssertFalse(doc.store.canStartImageGeneration)
    XCTAssertEqual(AIImageAPI.state(doc.store)["canStart"] as? Bool,false)
  }
  @MainActor func testHTTPRecoveryScopesOriginalOpenTrashAndPermissionsToActualSession()async throws {
    let h=AutomationTests(),ai=ImageGenerationLifecycleTests(),root=try directory(),trash=try directory()
    try await h.withService(pressedMouseButtons:{0}){service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      doc.store.generatedResultInbox=GeneratedResultInbox(directory:root,trash:{try FileManager.default.moveItem(at:$0,to:trash.appendingPathComponent($0.lastPathComponent))})
      try service.share(doc);let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)",bytes=try ai.image(),before=doc.store.document
      let job=try ai.begin(doc.store);try doc.store.executeEditorCommand(.renameLayer(before.layers[0].id,"Source changed"))
      try doc.store.acceptGeneratedImageData(bytes,requestID:job.id);XCTAssertEqual(job.phase,.stale)
      let saved=base+"/ai/saved-results/\(job.id)",record=base+"/ai/saved-records/\(job.id)"
      let metadata=try await h.request(service,path:record);XCTAssertEqual(metadata.0.statusCode,200)
      let object=try XCTUnwrap(JSONSerialization.jsonObject(with:metadata.1) as? [String:Any])
      XCTAssertEqual(Set(object.keys),Set(try XCTUnwrap(AIImageAPI.savedRecordSchema["required"] as? [String])))
      let denied=try await h.request(service,path:saved);XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let original=try await h.request(service,path:saved);XCTAssertEqual(original.0.statusCode,200);XCTAssertEqual(original.1,bytes)
      let stale=try await h.request(service,path:saved,headers:["X-Photato-Revision":"old"]);XCTAssertEqual(stale.0.statusCode,409)
      let forged=CraftNSDocument(model:doc.store.document);forged.store.renderTask?.cancel();forged.store.generatedResultInbox=doc.store.generatedResultInbox
      defer{forged.store.renderTask?.cancel();forged.close()}
      XCTAssertThrowsError(try service.authorizedAIInbox(job.id,store:forged.store))
      let edited=doc.store.document,history=doc.store.session.undoStack.count
      let opened=try await h.request(service,path:base+"/ai",body:["operation":"openSaved","revision":service.revision(doc.store),"resultID":job.id.uuidString])
      XCTAssertEqual(opened.0.statusCode,201,String(decoding:opened.1,as:UTF8.self));XCTAssertEqual(service.shares.count,2)
      if let created=service.shares.first(where:{$0.document !== doc})?.document {
        XCTAssertTrue(created.isDocumentEdited);XCTAssertNotEqual(created.store.document.id,doc.store.document.id)
        XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(created.store.activeLayer)).1,bytes)
        service.controller.removeDocument(created);created.store.renderTask?.cancel();created.close()
      }
      let noTrash=try await h.request(service,path:base+"/ai",body:["operation":"trashSaved","revision":service.revision(doc.store),"resultID":job.id.uuidString]);XCTAssertEqual(noTrash.0.statusCode,403)
      service.setDocumentSavesEnabled(true)
      let trashed=try await h.request(service,path:base+"/ai",body:["operation":"trashSaved","revision":service.revision(doc.store),"resultID":job.id.uuidString]);XCTAssertEqual(trashed.0.statusCode,200)
      let missing=try await h.request(service,path:record);XCTAssertEqual(missing.0.statusCode,404)
      XCTAssertEqual(doc.store.document,edited);XCTAssertEqual(doc.store.session.undoStack.count,history)
      XCTAssertEqual(try GeneratedResultInbox(directory:trash).load(job.id).1,bytes)
    }
  }
}
