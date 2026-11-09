import AppKit
import CryptoKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ImageGenerationLifecycleTests:XCTestCase {
  let available=AICapability(available:true,message:"Owned test capability; no provider is invoked")
  @MainActor func store(_ depth:PixelDepth = .u8)throws->EditorStore {
    _ = NSApplication.shared
    let store=EditorStore(document:try CraftDocument(width:8,height:6,depth:depth));store.renderTask?.cancel();try isolate(store);return store
  }
  func image()throws->Data {
    var doc=try CraftDocument(width:4,height:2)
    var pixels=try Surface(width:4,height:2)
    for y in 0..<2 {for x in 0..<4 {pixels.setPixel(x:x,y:y,[Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),Pixel(1,1,1)][x])}}
    doc.layers[0].content = .raster(pixels);return try DocumentIO.encode(doc,format:.png)
  }
  @MainActor func isolate(_ store:EditorStore)throws {
    guard store.generatedResultInbox === GeneratedResultInbox.shared else{return}
    let directory=try DocumentPersistenceTests().directory()
    store.generatedResultInbox=GeneratedResultInbox(directory:directory)
    addTeardownBlock{try? FileManager.default.removeItem(at:directory)}
  }
  @MainActor func begin(_ store:EditorStore,prompt:String="Owned red planet")throws->ImageGenerationJob {
    try isolate(store)
    store.prompt=prompt;store.beginImageCreation(capability:available)
    XCTAssertNil(store.aiError);return try XCTUnwrap(store.imageGenerationJob)
  }
  @MainActor func complete(_ store:EditorStore,data:Data?=nil)throws->Task<Void,Never> {
    let job=try begin(store)
    try store.acceptGeneratedImageData(data ?? image(),requestID:job.id,resultStyle:"illustration")
    return try XCTUnwrap(store.aiTask)
  }
  actor Gate {
    var entered=false
    var continuation:CheckedContinuation<Void,Never>?
    func wait()async {entered=true;await withCheckedContinuation{continuation=$0}}
    func release(){continuation?.resume();continuation=nil}
  }
  @MainActor func wait(_ gate:Gate)async throws {
    for _ in 0..<100 {if await gate.entered{return};try await Task.sleep(for:.milliseconds(10))}
    XCTFail("Preparation did not enter the owned gate")
  }
  @MainActor func testImmutablePromptAcceptedOriginalAllRGBDepthsUndoAndOfflineReopen()async throws {
    let bytes=try image()
    for depth in PixelDepth.allCases {
      let s=try store(depth);defer{s.renderTask?.cancel();s.cancelAIWork()}
      let before=s.document,job=try begin(s),sourceRevision=job.sourceRevision
      s.prompt="This later draft must not label the result"
      try s.acceptGeneratedImageData(bytes,requestID:job.id,resultStyle:"illustration")
      let task=try XCTUnwrap(s.aiTask);await task.value
      XCTAssertEqual(job.phase,.completed,s.aiError ?? "");XCTAssertFalse(s.aiBusy);XCTAssertFalse(s.showImagePlayground)
      XCTAssertEqual(s.document.layers.count,before.layers.count+1);XCTAssertEqual(s.session.undoStack.count,1)
      let layer=try XCTUnwrap(s.activeLayer),r=try XCTUnwrap(GeneratedImageStorage.record(layer))
      XCTAssertEqual(r.initialPrompt,"Owned red planet");XCTAssertEqual(r.sourceRevision,sourceRevision);XCTAssertEqual(r.sourceDocumentID,before.id)
      XCTAssertEqual(r.requestID,job.id);XCTAssertEqual(layer.name,"Generated · Owned red planet");XCTAssertEqual(layer.x,2);XCTAssertEqual(layer.y,2)
      XCTAssertEqual(r.originalSHA256,SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined())
      XCTAssertEqual(try GeneratedImageStorage.original(layer).1,bytes);XCTAssertNil(r.modelIdentifier);XCTAssertNil(r.seed);XCTAssertNil(r.finalPrompt)
      guard case .raster(let surface)=layer.content else{return XCTFail("Not a generated raster")}
      XCTAssertEqual(surface.depth,depth);XCTAssertEqual(surface.linearPixel(x:0,y:0),Pixel(1,0,0));XCTAssertEqual(surface.linearPixel(x:1,y:0),Pixel(0,1,0))
      let result=s.document,archive=try DocumentIO.encode(result,format:.native),reopened=try DocumentIO.decode(archive,native:true,name:"Offline")
      XCTAssertEqual(reopened,result);XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(reopened.layers.first(where:{$0.id==layer.id}))).1,bytes)
      XCTAssertNil(DocumentIO.persistenceIssue(result,format:.native))
      for format in DocumentIO.Format.allCases where format != .native {XCTAssertNotNil(DocumentIO.persistenceIssue(result,format:format))}
      await s.undo();XCTAssertEqual(s.document,before);await s.redo();XCTAssertEqual(s.document,result)
    }
  }
  @MainActor func testSourceEditAndUndoBackToOriginalStillRejectsOldRequest()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let before=s.document,job=try begin(s)
    try s.executeEditorCommand(.renameLayer(before.layers[0].id,"Changed"));await s.undo()
    XCTAssertEqual(s.document,before);XCTAssertNotEqual(s.sessionGeneration,job.sourceRevision)
    let bytes=try image();try s.acceptGeneratedImageData(bytes,requestID:job.id)
    XCTAssertEqual(try s.generatedResultInbox.load(job.id).1,bytes);XCTAssertEqual(job.retainedResultID,job.id)
    XCTAssertEqual(job.phase,.stale);XCTAssertEqual(s.document,before);XCTAssertFalse(s.aiBusy)
    XCTAssertNil(job.original);XCTAssertNotNil(s.aiError)
  }
  @MainActor func testCancelledAndDuplicateCallbacksDoNotReadOrChangeNewJob()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let before=s.document,first=try begin(s);s.cancelImageGeneration(first.id)
    let second=try begin(s,prompt:"Second request")
    s.acceptGeneratedImage(URL(string:"https://example.invalid/never-read")!,requestID:first.id)
    s.imageSystemInterfaceDismissed(first.id)
    XCTAssertTrue(s.imageGenerationJob === second);XCTAssertTrue(s.aiBusy);XCTAssertTrue(s.showImagePlayground)
    try s.acceptGeneratedImageData(image(),requestID:second.id,resultStyle:"sketch")
    XCTAssertThrowsError(try s.acceptGeneratedImageData(image(),requestID:second.id))
    let task=try XCTUnwrap(s.aiTask);await task.value
    XCTAssertEqual(second.phase,.completed,s.aiError ?? "");XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(s.document.layers.count,before.layers.count+1)
    s.acceptGeneratedImage(URL(fileURLWithPath:"/does-not-exist"),requestID:second.id)
    XCTAssertEqual(s.session.undoStack.count,1)
  }
  @MainActor func testCancelDuringPreparationAndOldCompletionCannotClearNewJob()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let original=s.document,gate=Gate(),bytes=try image()
    let fallback=Layer(name:"Ignored result",content:.raster(try Surface(width:1,height:1)))
    s.imageGenerationPreparation={_,_,_,_,_,_,_,_,_ in await gate.wait();return fallback}
    let first=try begin(s);try s.acceptGeneratedImageData(bytes,requestID:first.id);let task=try XCTUnwrap(s.aiTask)
    try await wait(gate);s.cancelImageGeneration(first.id)
    let second=try begin(s,prompt:"New request")
    await gate.release();await task.value
    XCTAssertEqual(first.phase,.cancelled);XCTAssertTrue(s.imageGenerationJob === second);XCTAssertTrue(second.pending);XCTAssertTrue(s.aiBusy)
    XCTAssertEqual(s.document,original);XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testConcurrentEditWhilePreparingRejectsResultWithoutNewHistory()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let gate=Gate(),fallback=Layer(name:"Not committed",content:.raster(try Surface(width:1,height:1)))
    s.imageGenerationPreparation={_,_,_,_,_,_,_,_,_ in await gate.wait();return fallback}
    let job=try begin(s);try s.acceptGeneratedImageData(image(),requestID:job.id);let task=try XCTUnwrap(s.aiTask)
    try await wait(gate);try s.executeEditorCommand(.renameLayer(s.document.layers[0].id,"Changed"));let edited=s.document
    await gate.release();await task.value
    XCTAssertEqual(job.phase,.stale);XCTAssertEqual(s.document,edited);XCTAssertEqual(s.session.undoStack.count,1)
  }
  @MainActor func testCloseCancelsPendingJobAndLateCallbackIsIgnored()throws {
    let doc=CraftNSDocument(model:try CraftDocument(width:8,height:6));doc.store.renderTask?.cancel()
    let before=doc.store.document,job=try begin(doc.store);doc.close()
    XCTAssertEqual(job.phase,.cancelled);XCTAssertFalse(doc.store.aiBusy)
    doc.store.acceptGeneratedImage(URL(fileURLWithPath:"/does-not-exist"),requestID:job.id)
    XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
  }
  @MainActor func testInvalidResultAndFileReadFailuresNeverChangeDocument()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let before=s.document,job=try begin(s)
    XCTAssertThrowsError(try s.acceptGeneratedImageData(Data("invalid image".utf8),requestID:job.id))
    XCTAssertEqual(job.phase,.awaitingSystem);XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertTrue(s.aiBusy)
    XCTAssertNil(job.retainedResultID);s.cancelAIWork()
    let next=try begin(s);s.acceptGeneratedImage(URL(string:"https://example.invalid/never-read")!,requestID:next.id)
    XCTAssertEqual(next.phase,.awaitingSystem);XCTAssertTrue(s.showImagePlayground);XCTAssertNotNil(s.aiError);XCTAssertEqual(s.document,before)
    XCTAssertThrowsError(try GeneratedImageStorage.readLocalResult(URL(string:"https://example.invalid/never-read")!))
  }
  @MainActor func testPromptRefinementDoesNotOverwriteEditedPromptOrSurviveCancel()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let gate=Gate();s.promptRefinement={_ in await gate.wait();return "Refined original"}
    s.prompt="Original";s.refinePrompt();let task=try XCTUnwrap(s.aiTask);try await wait(gate)
    s.prompt="Typed while refining";await gate.release();await task.value
    XCTAssertEqual(s.prompt,"Typed while refining");XCTAssertFalse(s.aiBusy)
    let cancelled=Gate();s.promptRefinement={_ in await cancelled.wait();return "Must not replace"}
    s.refinePrompt();let next=try XCTUnwrap(s.aiTask);try await wait(cancelled);s.cancelAIWork();s.prompt="New draft"
    await cancelled.release();await next.value;XCTAssertEqual(s.prompt,"New draft");XCTAssertFalse(s.aiBusy)
  }
  @MainActor func testMetadataOriginalIntegrityAndSchemasRejectTampering()async throws {
    let s=try store();defer{s.renderTask?.cancel()};let task=try complete(s);await task.value
    let layer=try XCTUnwrap(s.activeLayer),r=try XCTUnwrap(GeneratedImageStorage.record(layer))
    var bad=layer;bad.sourceTags?[GeneratedImageStorage.originalKey]=Data([1]);XCTAssertThrowsError(try GeneratedImageStorage.original(bad))
    bad=layer;bad.sourceTags?[GeneratedImageStorage.recordKey]=Data("{}".utf8);XCTAssertThrowsError(try GeneratedImageStorage.record(bad))
    let json=AIImageAPI.record(r,layerID:layer.id),schema=AIImageAPI.recordSchema
    XCTAssertEqual(Set(json.keys),Set(try XCTUnwrap(schema["required"]as?[String])))
    XCTAssertTrue(json["modelIdentifier"]is NSNull);XCTAssertTrue(json["seed"]is NSNull);XCTAssertTrue(json["finalPrompt"]is NSNull)
    XCTAssertEqual(json["providerAttested"]as?Bool,false);XCTAssertEqual(AutomationCommand.definitions.count,271)
    let state=AIImageAPI.state(s),properties=try XCTUnwrap(AIImageAPI.stateSchema["properties"]as?[String:Any]);XCTAssertTrue(Set(state.keys).isSubset(of:Set(properties.keys)))
  }
  @MainActor func testHTTPStatusRecordsOriginalAndCancelUseSameNativeJob()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc);let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)"
      let job=try self.begin(doc.store)
      let state=try await h.request(service,path:base+"/ai");XCTAssertEqual(state.0.statusCode,200)
      let obj=try XCTUnwrap(JSONSerialization.jsonObject(with:state.1)as?[String:Any]);XCTAssertEqual((obj["job"]as?[String:Any])?["id"]as?String,job.id.uuidString)
      let stale=try await h.request(service,path:base+"/ai",body:["operation":"cancel","revision":"stale","requestID":job.id.uuidString]);XCTAssertEqual(stale.0.statusCode,409)
      let cancelled=try await h.request(service,path:base+"/ai",body:["operation":"cancel","revision":service.revision(doc.store),"requestID":job.id.uuidString]);XCTAssertEqual(cancelled.0.statusCode,200);XCTAssertEqual(job.phase,.cancelled)
      let bytes=try self.image(),task=try self.complete(doc.store,data:bytes);await task.value
      let layer=try XCTUnwrap(doc.store.activeLayer),before=doc.store.document,history=doc.store.session.undoStack.count
      let metadata=try await h.request(service,path:base+"/ai/records/\(layer.id)");XCTAssertEqual(metadata.0.statusCode,200)
      let denied=try await h.request(service,path:base+"/ai/results/\(layer.id)");XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let original=try await h.request(service,path:base+"/ai/results/\(layer.id)");XCTAssertEqual(original.0.statusCode,200);XCTAssertEqual(original.1,bytes)
      XCTAssertEqual(original.0.value(forHTTPHeaderField:"Content-Type"),"image/png")
      let old=try await h.request(service,path:base+"/ai/results/\(layer.id)",headers:["X-Photato-Revision":"stale"]);XCTAssertEqual(old.0.statusCode,409)
      XCTAssertEqual(doc.store.document,before);XCTAssertEqual(doc.store.session.undoStack.count,history)
      XCTAssertFalse(service.revision(doc.store).contains("Owned red planet"))
    }
  }
  @MainActor func testHTTPPrepareRequiresPermissionWindowAndExplicitNativeApproval()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      try service.share(doc);let share=try XCTUnwrap(service.shares.first),url="/v1/documents/\(share.id)/ai"
      @MainActor func body()->[String:Any]{["operation":"prepare","revision":service.revision(doc.store),"prompt":"  Owned prompt  "]}
      let denied=try await h.request(service,path:url,body:body());XCTAssertEqual(denied.0.statusCode,403)
      service.setWorkspacePanelChangesEnabled(true)
      let missing=try await h.request(service,path:url,body:body());XCTAssertEqual(missing.0.statusCode,409)
      let controller=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false));doc.addWindowController(controller)
      defer{doc.store.showAI=false;doc.removeWindowController(controller);controller.close()}
      let before=doc.store.document,prepared=try await h.request(service,path:url,body:body());XCTAssertEqual(prepared.0.statusCode,200,String(decoding:prepared.1,as:UTF8.self))
      XCTAssertEqual(doc.store.prompt,"Owned prompt");XCTAssertTrue(doc.store.showAI);XCTAssertFalse(doc.store.aiBusy);XCTAssertNil(doc.store.imageGenerationJob)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let raw=DocumentIOWorkflowTests()
      let malformed=try await raw.request(service,path:url,data:Data("{".utf8),type:"application/json");XCTAssertEqual(malformed.0.statusCode,400)
      let wrongType=try await raw.request(service,path:url,data:Data("{}".utf8),type:"text/plain");XCTAssertEqual(wrongType.0.statusCode,415)
      let unsupported=try await h.request(service,path:url,body:["operation":"generate","revision":service.revision(doc.store),"prompt":"no headless model"]);XCTAssertEqual(unsupported.0.statusCode,400)
    }
  }
  @MainActor func testSystemDismissDuringPreparationDoesNotCancelAcceptedResult()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    let gate=Gate(),fallback=Layer(name:"Accepted result",content:.raster(try Surface(width:1,height:1)))
    s.imageGenerationPreparation={_,_,_,_,_,_,_,_,_ in await gate.wait();return fallback}
    let job=try begin(s);try s.acceptGeneratedImageData(image(),requestID:job.id);let task=try XCTUnwrap(s.aiTask)
    try await wait(gate);s.imageSystemInterfaceDismissed(job.id)
    XCTAssertEqual(job.phase,.preparing);XCTAssertTrue(s.aiBusy)
    await gate.release();await task.value;XCTAssertEqual(job.phase,.completed,s.aiError ?? "");XCTAssertEqual(s.session.undoStack.count,1)
  }
  @MainActor func testCallbackCopiesSystemResultBeforeTheTemporaryFileDisappears()async throws {
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    let file=folder.appendingPathComponent("system-result.png"),bytes=try image();try bytes.write(to:file)
    let s=try store();defer{s.renderTask?.cancel()};let job=try begin(s)
    s.acceptGeneratedImage(file,requestID:job.id,resultStyle:"illustration");let task=try XCTUnwrap(s.aiTask)
    try FileManager.default.removeItem(at:file);await task.value
    XCTAssertEqual(job.phase,.completed,s.aiError ?? "");XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(s.activeLayer)).1,bytes)
  }
  @MainActor func testCloseWaitingForRecoveryCancelsBeforeItCanAcceptAnImage()throws {
    let doc=CraftNSDocument(model:try CraftDocument(width:8,height:6));doc.store.renderTask?.cancel()
    defer{doc.recoveryWriteBusy=false;doc.close()}
    let before=doc.store.document,job=try begin(doc.store)
    doc.recoveryWriteBusy=true;doc.close()
    XCTAssertEqual(job.phase,.cancelled);XCTAssertFalse(doc.store.aiBusy)
    doc.store.acceptGeneratedImage(URL(fileURLWithPath:"/never-read"),requestID:job.id)
    XCTAssertEqual(doc.store.document,before);XCTAssertFalse(doc.store.canStartImageGeneration)
  }

  @MainActor func testInvalidRefinementResponseReportsErrorAndKeepsTheDraft()async throws {
    let s=try store();defer{s.renderTask?.cancel();s.cancelAIWork()}
    s.prompt="Initial draft";s.promptRefinement={_ in String(repeating:"x",count:1001)}
    s.refinePrompt();let task=try XCTUnwrap(s.aiTask);await task.value
    XCTAssertEqual(s.prompt,"Initial draft");XCTAssertNotNil(s.aiError);XCTAssertFalse(s.aiBusy);XCTAssertNil(s.promptRefinementID)
  }
  @MainActor func testHTTPCancelPromptRefinementUsesItsNativeRequestIdentity()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}){service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc);let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)/ai",gate=Gate()
      doc.store.promptRefinement={_ in await gate.wait();return "Old completion"};doc.store.prompt="Initial"
      doc.store.refinePrompt();let task=try XCTUnwrap(doc.store.aiTask);try await self.wait(gate)
      let id=try XCTUnwrap(doc.store.promptRefinementID),before=doc.store.document
      let response=try await h.request(service,path:base,body:["operation":"cancel","revision":service.revision(doc.store),"requestID":id.uuidString])
      XCTAssertEqual(response.0.statusCode,200);XCTAssertFalse(doc.store.aiBusy);XCTAssertNil(doc.store.promptRefinementID)
      doc.store.prompt="New draft";await gate.release();await task.value
      XCTAssertEqual(doc.store.prompt,"New draft");XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }

  func testPreparedMetadataSatisfiesCoreLayerAndNativeArchiveContracts()throws {
    let source=try CraftDocument(width:8,height:6),id=UUID(),revision=UUID(),bytes=try image()
    let layer=try GeneratedImageStorage.preparedLayer(bytes,source:source,requestID:id,sourceRevision:revision,
      initialPrompt:"Owned direct preparation",startedAt:Date(),acceptedAt:Date(),processing:.unknown,resultStyle:nil)
    XCTAssertTrue(try XCTUnwrap(layer.sourceTags).keys.allSatisfy{$0.utf8.count==4})
    var document=source;try Command.addLayer(layer).apply(to:&document);try document.validate()
    let data=try NativeArchive.encodeChunked(document),reopened=try NativeArchive.decodePaged(data)
    XCTAssertEqual(reopened,document);XCTAssertEqual(try GeneratedImageStorage.original(try XCTUnwrap(reopened.layers.last)).1,bytes)
  }

}
