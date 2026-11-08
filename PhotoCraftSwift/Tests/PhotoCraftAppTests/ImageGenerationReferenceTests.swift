import AppKit
import CryptoKit
import ImageIO
import ImagePlayground
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers
import XCTest
@testable import PhotoCraft

final class ImageGenerationReferenceTests: XCTestCase {
  let helper = ImageGenerationLifecycleTests()
  let capability = AICapability(available: true, message: "Owned callback; no provider invoked")
  func reference() throws -> ImageGenerationReference { try .prepare(helper.image()) }
  func testInputIdentityThumbnailOrientationAndMalformedFiles() throws {
    let bytes = try helper.image(), reference = try ImageGenerationReference.prepare(bytes)
    XCTAssertEqual(reference.record.sha256, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    XCTAssertEqual(reference.record.byteCount, bytes.count); XCTAssertEqual(reference.record.mediaType, "image/png")
    XCTAssertEqual(reference.image.width, 4); XCTAssertEqual(reference.image.height, 2)
    let output = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, reference.image, [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let oriented = try ImageGenerationReference.prepare(output as Data)
    XCTAssertEqual(oriented.record.width, 4); XCTAssertEqual(oriented.record.height, 2)
    XCTAssertEqual(oriented.image.width, 2); XCTAssertEqual(oriented.image.height, 4)
    var large = try CraftDocument(width: 4096, height: 4)
    large.layers[0].content = .raster(try Surface(width: 4096, height: 4, fill: Pixel(1,0,0)))
    let thumb = try ImageGenerationReference.prepare(DocumentIO.encode(large, format: .png))
    XCTAssertEqual(thumb.record.width, 4096); XCTAssertEqual(thumb.image.width, 2048); XCTAssertEqual(thumb.image.height, 2)
    for bad in [Data(), Data("https://example.invalid/image.png".utf8), Data(repeating: 0, count: ImageGenerationReference.maximumBytes + 1)] {
      XCTAssertThrowsError(try ImageGenerationReference.prepare(bad))
    }
    let multiple = NSMutableData()
    let multi = try XCTUnwrap(CGImageDestinationCreateWithData(multiple, UTType.tiff.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(multi, reference.image, nil); CGImageDestinationAddImage(multi, reference.image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(multi)); XCTAssertThrowsError(try ImageGenerationReference.prepare(multiple as Data))
  }
  func testLocalReaderRejectsRemoteSymlinkAndOversizeAndNeverChangesInput() throws {
    let directory = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("owned.png"), link = directory.appendingPathComponent("link.png")
    let bytes = try helper.image(); try bytes.write(to: file)
    XCTAssertEqual(try ImageGenerationReference.read(file), bytes)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    XCTAssertThrowsError(try ImageGenerationReference.read(link))
    XCTAssertThrowsError(try ImageGenerationReference.read(URL(string: "https://example.invalid/never-read")!))
    let huge = directory.appendingPathComponent("too-large.png")
    FileManager.default.createFile(atPath: huge.path, contents: Data())
    let handle = try FileHandle(forWritingTo: huge); try handle.truncate(atOffset: UInt64(ImageGenerationReference.maximumBytes + 1)); try handle.close()
    XCTAssertThrowsError(try ImageGenerationReference.read(huge)); XCTAssertEqual(try Data(contentsOf: file), bytes)
  }
  @MainActor func testImmutableReferenceMetadataAndOriginalSamplesAllDepthsUndoReopen() async throws {
    let bytes = try helper.image(), originalReference = try reference()
    for depth in PixelDepth.allCases {
      let s = try helper.store(depth); defer { s.cancelAIWork(); s.renderTask?.cancel() }
      s.imageReference = originalReference; let before = s.document
      let job = try helper.begin(s); XCTAssertEqual(job.importedReferenceRecord, originalReference.record)
      XCTAssertEqual(job.referenceWidth, 4); XCTAssertEqual(job.referenceHeight, 2)
      // A later draft cannot change the captured provider input or descriptive result.
      s.imageReference = try reference(); XCTAssertNotEqual(s.imageReference?.id, originalReference.id)
      try s.acceptGeneratedImageData(bytes, requestID: job.id)
      let task = try XCTUnwrap(s.aiTask); await task.value
      XCTAssertEqual(job.phase, .completed, s.aiError ?? ""); XCTAssertNil(job.referenceImage)
      let layer = try XCTUnwrap(s.activeLayer)
      XCTAssertEqual(try ImageGenerationReference.record(in: layer), originalReference.record)
      XCTAssertEqual(try GeneratedImageStorage.original(layer).1, bytes)
      XCTAssertEqual(Array(s.document.layers.dropLast()), before.layers)
      XCTAssertEqual(s.document.selection, before.selection); XCTAssertEqual(s.session.undoStack.count, 1)
      let result = s.document, reopened = try DocumentIO.decode(DocumentIO.encode(result, format: .native), native: true, name: "Owned reference reopen")
      XCTAssertEqual(reopened, result)
      XCTAssertEqual(try ImageGenerationReference.record(in: try XCTUnwrap(reopened.layers.first(where: { $0.id == layer.id }))), originalReference.record)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"], depth == .u8 {
        try DocumentIO.encode(result, format: .native).write(to: URL(fileURLWithPath: path).appendingPathComponent("reference-owned-result.photato"))
        try bytes.write(to: URL(fileURLWithPath: path).appendingPathComponent("owned-reference.png"))
      }
      await s.undo(); XCTAssertEqual(s.document, before); await s.redo(); XCTAssertEqual(s.document, result)
    }
  }
  @MainActor func testCancelOldCallbackDoesNotChangeNewReferenceJob() throws {
    let s = try helper.store(); defer { s.cancelAIWork(); s.renderTask?.cancel() }
    s.imageReference = try reference(); let first = try helper.begin(s), before = s.document
    s.cancelImageGeneration(first.id); s.imageReference = try reference()
    let replacement = try helper.begin(s)
    s.acceptGeneratedImage(URL(string: "https://example.invalid/no-read")!, requestID: first.id)
    s.imageSystemInterfaceDismissed(first.id)
    XCTAssertTrue(s.imageGenerationJob === replacement); XCTAssertEqual(replacement.phase, .awaitingSystem)
    XCTAssertEqual(s.document, before); XCTAssertNil(first.referenceImage); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.removeImageReference(); XCTAssertNotNil(s.imageReference) // Busy removal must not replace the request.
  }
  @MainActor func testBackgroundUsesMaskedSubjectInsteadOfImportedReference() async throws {
    let backgrounds = GeneratedBackgroundTests(), s = try backgrounds.store()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    s.imageReference = try reference()
    let job = try await backgrounds.begin(s)
    XCTAssertNil(job.importedReferenceRecord); XCTAssertEqual(job.referenceWidth, 8); XCTAssertEqual(job.referenceHeight, 6)
    try s.acceptGeneratedImageData(helper.image(), requestID: job.id)
    let task = try XCTUnwrap(s.aiTask); await task.value
    XCTAssertEqual(job.phase, .completed)
    XCTAssertNil(try ImageGenerationReference.record(in: try XCTUnwrap(s.activeLayer)))
  }
  @MainActor func testNativeImportCancellationCannotOverwriteReplacementDraft() async throws {
    let s = try helper.store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    let directory = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("owned.png"); try helper.image().write(to: url)
    s.showAI = true; s.imageReference = try reference(); let before = s.imageReference?.id
    s.imageReferencePreparation = { bytes in await gate.wait(); return try .prepare(bytes) }
    s.loadImageReference(url); let task = try XCTUnwrap(s.aiTask)
    try await helper.wait(gate); XCTAssertNotNil(s.imageReferenceImportID); XCTAssertTrue(s.aiBusy)
    s.cancelAIWork(); let replacement = try reference(); s.imageReference = replacement
    await gate.release(); await task.value
    XCTAssertEqual(s.imageReference?.id, replacement.id); XCTAssertNotEqual(s.imageReference?.id, before)
    XCTAssertNil(s.imageReferenceImportID); XCTAssertFalse(s.aiBusy); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testNativeImportRejectsEditUndoAndKeepsPreviousReferenceOnDecodeFailure() async throws {
    let s = try helper.store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelAIWork(); s.renderTask?.cancel() }
    let directory = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("owned.png"); try helper.image().write(to: url)
    s.showAI = true; s.imageReference = try reference(); let previous = s.imageReference?.id, before = s.document
    s.imageReferencePreparation = { bytes in await gate.wait(); return try .prepare(bytes) }
    s.loadImageReference(url); let task = try XCTUnwrap(s.aiTask); try await helper.wait(gate)
    try s.executeEditorCommand(.renameLayer(before.layers[0].id, "Changed")); await s.undo()
    await gate.release(); await task.value
    XCTAssertEqual(s.document, before); XCTAssertEqual(s.imageReference?.id, previous); XCTAssertNotNil(s.aiError)
    s.imageReferencePreparation = { try .prepare($0) }; try Data("invalid".utf8).write(to: url)
    s.loadImageReference(url); let invalid = try XCTUnwrap(s.aiTask); await invalid.value
    XCTAssertEqual(s.imageReference?.id, previous); XCTAssertFalse(s.aiBusy); XCTAssertNotNil(s.aiError)
    s.removeImageReference(); XCTAssertNil(s.imageReference)
  }
  @MainActor func testHTTPPrepareReferencePermissionsStrictnessAndLegacyClear() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelAIWork(); doc.store.renderTask?.cancel() }
      try service.share(doc); let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/ai"
      let bytes = try self.helper.image()
      @MainActor func body(_ reference: Any = NSNull(), intent: String = "image") -> [String: Any] {
        ["operation": "prepare", "revision": service.revision(doc.store), "prompt": "Owned reference", "intent": intent, "reference": reference]
      }
      let input: [String: Any] = ["dataBase64": bytes.base64EncodedString()]
      var reply = try await h.request(service, path: path, body: body(input)); XCTAssertEqual(reply.0.statusCode, 403)
      service.setWorkspacePanelChangesEnabled(true)
      reply = try await h.request(service, path: path, body: body(input)); XCTAssertEqual(reply.0.statusCode, 409)
      let controller = NSWindowController(window: NSWindow(contentRect: .init(x:0,y:0,width:300,height:200), styleMask:[.titled], backing:.buffered, defer:false))
      doc.addWindowController(controller); defer { doc.store.showAI=false; doc.removeWindowController(controller); controller.close() }
      reply = try await h.request(service, path: path, body: body(input)); XCTAssertEqual(reply.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      for invalid: Any in [true, "file:///private/image.png", ["url": "https://example.invalid"], ["dataBase64": "!"], ["dataBase64": bytes.base64EncodedString(), "path": "/private/never-read"]] {
        reply = try await h.request(service, path: path, body: body(invalid)); XCTAssertEqual(reply.0.statusCode, 400)
      }
      let before = doc.store.document
      reply = try await h.request(service, path: path, body: body(input)); XCTAssertEqual(reply.0.statusCode, 200, String(decoding:reply.1,as:UTF8.self))
      XCTAssertTrue(doc.store.showAI); XCTAssertFalse(doc.store.aiBusy); XCTAssertNil(doc.store.imageGenerationJob)
      XCTAssertNotNil(doc.store.imageReference); XCTAssertEqual(doc.store.document, before); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1) as? [String:Any])
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject:state))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema:AIImageAPI.stateSchema))
      doc.store.showAI=false; var legacy=body(); legacy.removeValue(forKey:"reference")
      reply = try await h.request(service,path:path,body:legacy); XCTAssertEqual(reply.0.statusCode,200)
      XCTAssertNil(doc.store.imageReference); XCTAssertEqual(doc.store.imageGenerationIntent,.image)
    }
  }
  @MainActor func testHTTPReferenceWorkerRejectsPermissionRevocationAndStaleSource() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelAIWork(); doc.store.renderTask?.cancel() }
      try service.share(doc); let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/ai"
      service.setWorkspacePanelChangesEnabled(true); service.setDocumentTransfersEnabled(true)
      let controller=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false))
      doc.addWindowController(controller); defer { doc.store.showAI=false; doc.removeWindowController(controller);controller.close() }
      let bytes=try self.helper.image(),gate=ImageGenerationLifecycleTests.Gate()
      doc.store.imageReferencePreparation = { bytes in await gate.wait(); return try .prepare(bytes) }
      let expected=service.revision(doc.store), original=doc.store.document
      let task=Task { try await h.request(service,path:path,body:["operation":"prepare","revision":expected,"prompt":"Owned reference","reference":["dataBase64":bytes.base64EncodedString()]]) }
      try await self.helper.wait(gate);service.setDocumentTransfersEnabled(false)
      await gate.release();let reply=try await task.value
      XCTAssertEqual(reply.0.statusCode,409);XCTAssertNil(doc.store.imageReference);XCTAssertFalse(doc.store.showAI);XCTAssertEqual(doc.store.document,original)
    }
  }
  @MainActor func testStateSchemasMetadataValidationAndNativeControllerReference() throws {
    let s=try helper.store();defer{s.cancelAIWork();s.renderTask?.cancel()}
    s.imageReference=try reference();let job=try helper.begin(s)
    let state=AIImageAPI.state(s),jobState=try XCTUnwrap(state["job"] as? [String:Any])
    for (object,schema) in [(state,AIImageAPI.stateSchema),(jobState,AIImageAPI.jobSchema)] {
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:object))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:schema))
    }
    #if arch(arm64)
    if #available(macOS 26.0, *) {
      let controller=SystemImagePlayground.makeController(job:job)
      XCTAssertEqual(controller.sourceImage?.cgImage(forProposedRect:nil,context:nil,hints:nil)?.width,4)
      XCTAssertEqual(controller.concepts.count,1)
    }
    #endif
    var layer=s.document.layers[0];layer.sourceTags=[ImageGenerationReference.recordKey:Data(repeating:0,count:4097)]
    XCTAssertThrowsError(try ImageGenerationReference.record(in:layer))
    layer.sourceTags=[ImageGenerationReference.recordKey:Data("{}".utf8)]
    XCTAssertThrowsError(try ImageGenerationReference.record(in:layer))
    s.cancelAIWork();let previous=s.imageReference?.id
    s.prompt="Owned unavailable reference";s.beginImageCreation(capability:.init(available:false,message:"Owned unavailable"))
    XCTAssertEqual(s.imageReference?.id,previous);XCTAssertFalse(s.aiBusy);XCTAssertNotNil(s.aiError)
  }
  @MainActor func testRealHTTPPhotoAboveDefaultFramingLimitAndExactRouteBudget() async throws {
    var source=try CraftDocument(width:256,height:128)
    var pixels=try Surface(width:256,height:128),random:UInt64=0x491
    for y in 0..<128 {for x in 0..<256 {
      random = random &* 6364136223846793005 &+ 1442695040888963407
      pixels.setPixel(x:x,y:y,Pixel(Float((random>>32)&255)/255,Float((random>>40)&255)/255,Float((random>>48)&255)/255))
    }}
    source.layers[0].content = .raster(pixels)
    let bytes=try DocumentIO.encode(source,format:.png)
    XCTAssertGreaterThan(bytes.count,65536)
    let id=UUID(),route="/v1/documents/\(id)/ai",limit=ImageGenerationReference.maximumAPIRequestBytes
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:route),limit)
    for (method,path) in [("GET",route),("POST","/v1/documents/not-a-uuid/ai"),("POST",route+"/other"),("POST","/v1/documents/\(id)/unknown")] {
      XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:method,path:path),65536)
    }
    func header(_ length:Int)->Data {Data("POST \(route) HTTP/1.1\r\nContent-Length: \(length)\r\n\r\n".utf8)}
    XCTAssertNil(try AutomationRequest.parse(header(limit)))
    XCTAssertThrowsError(try AutomationRequest.parse(header(limit+1))) {error in
      XCTAssertEqual((error as? AutomationFailure)?.status,413)
    }
    let h=AutomationTests()
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc);let share=try XCTUnwrap(service.shares.first)
      service.setWorkspacePanelChangesEnabled(true);service.setDocumentTransfersEnabled(true)
      let controller=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false))
      doc.addWindowController(controller);defer{doc.store.showAI=false;doc.removeWindowController(controller);controller.close()}
      let before=doc.store.document
      let response=try await h.request(service,path:"/v1/documents/\(share.id)/ai",body:["operation":"prepare","revision":service.revision(doc.store),"prompt":"Owned photo-size reference","reference":["dataBase64":bytes.base64EncodedString()]])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self))
      XCTAssertEqual(doc.store.imageReference?.record.byteCount,bytes.count)
      XCTAssertEqual(doc.store.imageReference?.record.width,256);XCTAssertEqual(doc.store.imageReference?.record.height,128)
      XCTAssertTrue(doc.store.showAI);XCTAssertFalse(doc.store.aiBusy);XCTAssertNil(doc.store.imageGenerationJob)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
}
