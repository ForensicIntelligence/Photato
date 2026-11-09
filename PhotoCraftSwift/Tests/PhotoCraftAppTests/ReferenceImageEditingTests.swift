import AppKit
import Foundation
import ImagePlayground
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest
@testable import PhotoCraft

final class ReferenceImageEditingTests: XCTestCase {
  @MainActor func testHTTPPrepareReferenceEditingRequiresNativeApprovalAndIsReadOnly() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc);let share=try XCTUnwrap(service.shares.first)
      service.setWorkspacePanelChangesEnabled(true);service.setDocumentTransfersEnabled(true)
      let controller=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false))
      doc.addWindowController(controller)
      defer{doc.store.showAI=false;doc.removeWindowController(controller);controller.close()}
      let before=doc.store.document,bytes=try ImageGenerationLifecycleTests().image()
      let response=try await h.request(service,path:"/v1/documents/\(share.id)/ai",body:["operation":"prepare","revision":service.revision(doc.store),"prompt":"Make the reference a night scene","referenceUse":"editExisting","reference":["dataBase64":bytes.base64EncodedString()]])
      let supported=LocalAI.platform.available && ProcessInfo.processInfo.operatingSystemVersion.majorVersion>=27
      XCTAssertEqual(response.0.statusCode,supported ? 200:422,String(decoding:response.1,as:UTF8.self))
      if supported {
        let state=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any])
        XCTAssertEqual(state["referenceUse"]as?String,"editExisting")
        XCTAssertEqual(state["requiresNativeApproval"]as?Bool,true)
        XCTAssertTrue(doc.store.showAI);XCTAssertNotNil(doc.store.imageReference)
      }else{XCTAssertFalse(doc.store.showAI);XCTAssertNil(doc.store.imageReference)}
      XCTAssertFalse(doc.store.aiBusy);XCTAssertNil(doc.store.imageGenerationJob)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }

  func testPlatformPolicyRejectsUnsupportedEditingWithoutChangingLegacyInspiration() throws {
    for major in [14,26,27,28] { for arm in [false,true] {
      let supported=ImageReferenceUse.supportsEditing(majorVersion:major,isAppleSilicon:arm)
      XCTAssertEqual(supported,major>=27 && arm)
      XCTAssertNoThrow(try ImageReferenceUse.inspiration.validate(hasReference:false,editingSupported:supported))
      XCTAssertThrowsError(try ImageReferenceUse.editExisting.validate(hasReference:false,editingSupported:supported))
      if supported { XCTAssertNoThrow(try ImageReferenceUse.editExisting.validate(hasReference:true,editingSupported:supported)) }
      else { XCTAssertThrowsError(try ImageReferenceUse.editExisting.validate(hasReference:true,editingSupported:supported)) }
    }}
  }

  func testDefaultReferenceEncodingStaysLegacyAndRequestedEditIsDescriptive() throws {
    let input=try ImageGenerationReference.prepare(ImageGenerationLifecycleTests().image())
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let original=try encoder.encode(input.record)
    XCTAssertEqual(try encoder.encode(input.record.recording(.inspiration)),original)
    let legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:original)as?[String:Any])
    XCTAssertNil(legacy["requestedUse"])
    let edited=input.record.recording(.editExisting),bytes=try encoder.encode(edited)
    XCTAssertEqual(try JSONDecoder().decode(ImageGenerationReferenceRecord.self,from:bytes),edited)
    XCTAssertEqual(edited.sha256,input.record.sha256);XCTAssertEqual(input.record.requestedUse,nil)
    let state=AIImageAPI.referenceRecord(edited)
    XCTAssertEqual(state["role"]as?String,"imageToEdit");XCTAssertEqual(state["requestedUse"]as?String,"editExisting")
    XCTAssertEqual(state["providerAttested"]as?Bool,false)
    let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:state))
    XCTAssertNoThrow(try BrushAPI.merge(value,schema:AIImageAPI.referenceRecordSchema))
    var malformed=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes)as?[String:Any])
    malformed["requestedUse"]="unimplemented-mask-model"
    XCTAssertThrowsError(try JSONDecoder().decode(ImageGenerationReferenceRecord.self,from:JSONSerialization.data(withJSONObject:malformed)))
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("reference-edit-record.json"))
    }
  }

  func testRequestedEditMetadataAndOriginalSurviveAllDepthsOfflineWithOneTransaction() throws {
    let helper=ImageGenerationLifecycleTests(),bytes=try helper.image(),reference=try ImageGenerationReference.prepare(bytes)
    for depth in PixelDepth.allCases {
      let source=try CraftDocument(width:8,height:6,depth:depth),now=Date()
      let layer=try ImageGenerationReference.attach(reference.record.recording(.editExisting),to:
        GeneratedImageStorage.preparedLayer(bytes,source:source,requestID:UUID(),sourceRevision:UUID(),
          initialPrompt:"Owned accepted edit; no model",startedAt:now,acceptedAt:now,processing:.unknown,resultStyle:"owned"))
      var session=EditorSession(document:source);try session.execute(.addLayer(layer))
      XCTAssertEqual(session.undoStack.count,1);XCTAssertEqual(Array(session.document.layers.dropLast()),source.layers)
      XCTAssertEqual(try GeneratedImageStorage.original(layer).1,bytes)
      XCTAssertEqual(try ImageGenerationReference.record(in:layer)?.requestedUse,.editExisting)
      let result=session.document,reopened=try DocumentIO.decode(DocumentIO.encode(result,format:.native),native:true,name:"Offline")
      XCTAssertEqual(reopened.layers,result.layers)
      XCTAssertEqual(try ImageGenerationReference.record(in:try XCTUnwrap(reopened.layers.last))?.requestedUse,.editExisting)
      try session.undo();XCTAssertEqual(session.document,source)
      try session.redo();XCTAssertEqual(session.document,result)
    }
  }

  @MainActor func testNativeCapturedEditingModeIgnoresLaterDraftChangesAllRGBDepths() async throws {
    let helper=ImageGenerationLifecycleTests(),bytes=try helper.image()
    for depth in PixelDepth.allCases {
      let s=try helper.store(depth);defer{s.cancelAIWork();s.renderTask?.cancel()}
      s.imageReference=try ImageGenerationReference.prepare(bytes);s.imageReferenceUse = .editExisting;s.prompt="Owned captured edit"
      let before=s.document
      if !ImageReferenceUse.editingSupported {
        XCTAssertThrowsError(try s.startImageGeneration(capability:helper.available))
        XCTAssertNil(s.imageGenerationJob);XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
        continue
      }
      try s.startImageGeneration(capability:helper.available)
      let job=try XCTUnwrap(s.imageGenerationJob)
      XCTAssertEqual(job.referenceUse,.editExisting)
      XCTAssertEqual(job.importedReferenceRecord?.requestedUse,.editExisting)
      s.imageReferenceUse = .inspiration;s.imageReference=nil;s.prompt="Later draft"
      try s.acceptGeneratedImageData(bytes,requestID:job.id,resultStyle:"owned")
      await (try XCTUnwrap(s.aiTask)).value
      XCTAssertEqual(job.phase,.completed,s.aiError ?? "")
      XCTAssertEqual(s.session.undoStack.count,1);XCTAssertEqual(Array(s.document.layers.dropLast()),before.layers)
      let layer=try XCTUnwrap(s.activeLayer),record=try XCTUnwrap(ImageGenerationReference.record(in:layer))
      XCTAssertEqual(record.requestedUse,.editExisting)
      XCTAssertEqual(try GeneratedImageStorage.record(layer)?.initialPrompt,"Owned captured edit")
      XCTAssertEqual(AIImageAPI.state(s)["referenceUse"]as?String,"inspiration")
      XCTAssertEqual((AIImageAPI.state(s)["selectedReference"]as?[String:Any])?["requestedUse"]as?String,"editExisting")
      XCTAssertEqual(s.status,"Reference image edited with Image Playground")
      let undone=await s.undo();XCTAssertTrue(undone);XCTAssertEqual(s.document,before)
      let redone=await s.redo();XCTAssertTrue(redone)
    }
  }

  @MainActor func testMissingReferenceCannotStartAndRemovingItRestoresDefaultChoice() throws {
    let helper=ImageGenerationLifecycleTests(),s=try helper.store()
    defer{s.cancelAIWork();s.renderTask?.cancel()}
    let before=s.document
    s.imageReferenceUse = .editExisting;s.prompt="Owned missing input"
    XCTAssertFalse(s.canStartImageGeneration)
    XCTAssertThrowsError(try s.startImageGeneration(capability:helper.available))
    XCTAssertNil(s.imageGenerationJob);XCTAssertFalse(s.aiBusy)
    s.imageReference=try ImageGenerationReference.prepare(helper.image())
    s.removeImageReference();XCTAssertNil(s.imageReference);XCTAssertEqual(s.imageReferenceUse,.inspiration)
    XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testNativePopupDisablesUnsupportedEditingAndGuardsStaleActions() throws {
    let s=try ImageGenerationLifecycleTests().store();defer{s.cancelAIWork();s.renderTask?.cancel()}
    let before=s.document
    let binding=Binding(get:{s.imageReferenceUse},set:{s.imageReferenceUse=$0})
    let coordinator=ReferenceImageUseControl.Coordinator(binding,editAvailable:false)
    let popup=ReferenceImageUseControl.makePopup(coordinator,enabled:true)
    XCTAssertEqual(popup.numberOfItems,2);XCTAssertEqual(popup.selectedTag(),0)
    XCTAssertFalse(try XCTUnwrap(popup.menu).autoenablesItems)
    XCTAssertFalse(try XCTUnwrap(popup.item(at:1)).isEnabled)
    let action=try XCTUnwrap(popup.action)
    popup.selectItem(withTag:1);XCTAssertTrue(popup.sendAction(action,to:coordinator))
    XCTAssertEqual(s.imageReferenceUse,.inspiration);XCTAssertEqual(popup.selectedTag(),0)
    coordinator.editAvailable=true
    ReferenceImageUseControl.synchronize(popup,selection:.inspiration,editAvailable:true,enabled:true)
    popup.selectItem(withTag:1);coordinator.changed(popup)
    XCTAssertEqual(s.imageReferenceUse,.editExisting);XCTAssertEqual(popup.selectedTag(),1)
    ReferenceImageUseControl.synchronize(popup,selection:.editExisting,editAvailable:true,enabled:false)
    popup.selectItem(withTag:0);coordinator.changed(popup)
    XCTAssertEqual(s.imageReferenceUse,.editExisting);XCTAssertEqual(popup.selectedTag(),1);XCTAssertFalse(popup.isEnabled)
    XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  @MainActor func testNativeControllerUsesActualEditingStrategyAndCapturedReferenceAspect() throws {
    guard #available(macOS 27.0,*),LocalAI.platform.available else { XCTAssertFalse(ImageReferenceUse.editingSupported);return }
    let source=try CraftDocument(width:13,height:17),reference=try ImageGenerationReference.prepare(ImageGenerationLifecycleTests().image())
    let job=ImageGenerationJob(source:source,revision:UUID(),lifecycle:UUID(),prompt:"Owned edit",processing:.unknown,
      reference:reference,referenceUse:.editExisting)
    let controller=SystemImagePlayground.makeController(job:job)
    XCTAssertEqual(controller.options.creationStrategy,.editExisting)
    XCTAssertEqual(controller.options.sizeSpecification,ImagePlaygroundOptions.SizeSpecification.closest(to:.init(width:4,height:2)))
    XCTAssertEqual(controller.sourceImage?.size,.init(width:4,height:2))
    XCTAssertFalse(controller.allowedGenerationStyles.contains(.externalProvider))
    let legacy=ImageGenerationJob(source:source,revision:UUID(),lifecycle:UUID(),prompt:"Owned inspiration",processing:.unknown,reference:reference)
    let original=SystemImagePlayground.makeController(job:legacy)
    XCTAssertEqual(original.options.creationStrategy,ImagePlaygroundOptions().creationStrategy)
    XCTAssertEqual(original.options.sizeSpecification,ImagePlaygroundOptions.SizeSpecification.closest(to:.init(width:13,height:17)))
    let background=ImageGenerationJob(source:source,revision:UUID(),lifecycle:UUID(),prompt:"Owned background",processing:.unknown,
      intent:.background,reference:reference,referenceUse:.editExisting)
    XCTAssertEqual(background.referenceUse,.inspiration);XCTAssertNil(background.importedReferenceRecord)
  }

  @MainActor func testHTTPStrictModePermissionsMissingInputAndLegacyDefaultAreAtomic() async throws {
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc);let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/ai"
      let bytes=try ImageGenerationLifecycleTests().image(),input:[String:Any]=["dataBase64":bytes.base64EncodedString()]
      @MainActor func body(_ use:Any,_ reference:Any=NSNull(),intent:String="image")->[String:Any] {
        ["operation":"prepare","revision":service.revision(doc.store),"prompt":"Owned reference edit","intent":intent,"referenceUse":use,"reference":reference]
      }
      let before=doc.store.document
      let denied=try await h.request(service,path:path,body:body("editExisting",input));XCTAssertEqual(denied.0.statusCode,403)
      service.setWorkspacePanelChangesEnabled(true)
      let window=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false))
      doc.addWindowController(window);defer{doc.store.showAI=false;doc.removeWindowController(window);window.close()}
      let transfers=try await h.request(service,path:path,body:body("editExisting",input));XCTAssertEqual(transfers.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      for invalid:Any in [true,7,"","unknown",NSNull()] {
        let reply=try await h.request(service,path:path,body:body(invalid,input));XCTAssertEqual(reply.0.statusCode,400)
        XCTAssertFalse(doc.store.showAI);XCTAssertNil(doc.store.imageReference)
      }
      let missing=try await h.request(service,path:path,body:body("editExisting"));XCTAssertEqual(missing.0.statusCode,400)
      let wrongIntent=try await h.request(service,path:path,body:body("inspiration",intent:"background"));XCTAssertEqual(wrongIntent.0.statusCode,400)
      let editing=try await h.request(service,path:path,body:body("editExisting",input))
      XCTAssertEqual(editing.0.statusCode,ImageReferenceUse.editingSupported ? 200:422)
      if ImageReferenceUse.editingSupported { XCTAssertEqual(doc.store.imageReferenceUse,.editExisting) }
      else { XCTAssertEqual(doc.store.imageReferenceUse,.inspiration);XCTAssertNil(doc.store.imageReference) }
      doc.store.showAI=false
      var legacy=body("inspiration",input);legacy.removeValue(forKey:"referenceUse")
      let oldClient=try await h.request(service,path:path,body:legacy);XCTAssertEqual(oldClient.0.statusCode,200)
      XCTAssertEqual(doc.store.imageReferenceUse,.inspiration)
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:oldClient.1)as?[String:Any])
      XCTAssertEqual((state["reference"]as?[String:Any])?["role"]as?String,"visualInspiration")
      XCTAssertNil((state["reference"]as?[String:Any])?["requestedUse"])
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:state))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:AIImageAPI.stateSchema))
    }
  }

  @MainActor func testHTTPReferencePreparationRejectsChangedModeRevisionAndRevokedTransfers() async throws {
    let h=AutomationTests(),helper=ImageGenerationLifecycleTests()
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc);let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/ai"
      service.setWorkspacePanelChangesEnabled(true);service.setDocumentTransfersEnabled(true)
      let window=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false))
      doc.addWindowController(window);defer{doc.store.showAI=false;doc.removeWindowController(window);window.close()}
      let before=doc.store.document,bytes=try helper.image()
      for revoke in [false,true] {
        doc.store.imageReferenceUse = .inspiration
        let gate=ImageGenerationLifecycleTests.Gate()
        doc.store.imageReferencePreparation={data in await gate.wait();return try .prepare(data)}
        let revision=service.revision(doc.store)
        let use=ImageReferenceUse.editingSupported ? "editExisting":"inspiration"
        let body:[String:Any]=["operation":"prepare","revision":revision,"prompt":"Owned deferred edit","referenceUse":use,"reference":["dataBase64":bytes.base64EncodedString()]]
        let task=Task{try await h.request(service,path:path,body:body)}
        try await helper.wait(gate)
        if revoke { service.setDocumentTransfersEnabled(false) }
        else { doc.store.imageReferenceUse = .editExisting;XCTAssertNotEqual(service.revision(doc.store),revision) }
        await gate.release();let reply=try await task.value
        XCTAssertEqual(reply.0.statusCode,409);XCTAssertFalse(doc.store.showAI);XCTAssertNil(doc.store.imageReference)
        XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
        service.setDocumentTransfersEnabled(true)
      }
    }
  }

  @MainActor func testCancelledEditCallbackCannotModifyReplacementImageRequest() throws {
    let helper=ImageGenerationLifecycleTests(),s=try helper.store(),bytes=try helper.image()
    defer{s.cancelAIWork();s.renderTask?.cancel()}
    s.imageReference=try ImageGenerationReference.prepare(bytes);s.imageReferenceUse = .editExisting;s.prompt="Owned cancelled edit"
    let before=s.document
    if !ImageReferenceUse.editingSupported { XCTAssertThrowsError(try s.startImageGeneration(capability:helper.available));return }
    try s.startImageGeneration(capability:helper.available);let old=try XCTUnwrap(s.imageGenerationJob)
    s.cancelImageGeneration(old.id);s.imageReferenceUse = .inspiration;s.imageReference=nil
    try s.startImageGeneration(capability:helper.available);let replacement=try XCTUnwrap(s.imageGenerationJob)
    XCTAssertThrowsError(try s.acceptGeneratedImageData(bytes,requestID:old.id))
    XCTAssertTrue(s.imageGenerationJob === replacement);XCTAssertEqual(replacement.referenceUse,.inspiration)
    XCTAssertEqual(old.phase,.cancelled);XCTAssertEqual(s.document,before);XCTAssertTrue(s.session.undoStack.isEmpty)
  }

  func testControlSchemasDescribeReferenceDependenciesAndRejectBackgroundMode() throws {
    let data=try ImageGenerationLifecycleTests().image()
    let basic:[String:Any]=["operation":"prepare","revision":"owned","prompt":"Owned schema"]
    func validate(_ body:[String:Any])throws {
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:body))
      _ = try BrushAPI.merge(value,schema:AIImageAPI.controlSchema)
    }
    XCTAssertNoThrow(try validate(basic))
    var edit=basic;edit["referenceUse"]="editExisting";edit["reference"]=["dataBase64":data.base64EncodedString()]
    XCTAssertNoThrow(try validate(edit))
    edit.removeValue(forKey:"reference");XCTAssertThrowsError(try validate(edit))
    edit["reference"]=NSNull();XCTAssertThrowsError(try validate(edit))
    var background=basic;background["intent"]="background";background["reference"]=NSNull()
    XCTAssertNoThrow(try validate(background))
    background["referenceUse"]="inspiration";XCTAssertThrowsError(try validate(background))
  }
}
