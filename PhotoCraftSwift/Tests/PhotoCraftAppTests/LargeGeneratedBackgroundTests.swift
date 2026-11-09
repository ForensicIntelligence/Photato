import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeGeneratedBackgroundTests: XCTestCase {
  func document(width: Int, height: Int, depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: width, height: height, depth: depth, name: "Owned large masked subject")
    d.layers[0].background = nil; d.layers[0].locked = false; d.layers[0].protection = []
    d.layers[0].content = .raster(try Surface(width: width, height: height, depth: depth, fill: Pixel(0.25,0.5,0.75)))
    d.layers[0].mask = try Surface(width: width, height: height, depth: depth, fill: .white)
    try d.validate(); return d
  }
  func testLongBackgroundReferenceAndPlacementExceedOldSmallImageLimits() throws {
    let d = try document(width: 8001, height: 2), original = d
    XCTAssertNotNil(GeneratedBackground.foreground(in: d))
    let reference = try GeneratedBackground.reference(d)
    XCTAssertEqual(reference.width,2048); XCTAssertEqual(reference.height,1)
    let bytes = try GeneratedBackgroundTests().image(), now = Date()
    let layer = try GeneratedBackground.prepareLayer(bytes, source:d, requestID:UUID(), sourceRevision:UUID(),
      initialPrompt:"Owned generated background", startedAt:now, acceptedAt:now, processing:.unknown, resultStyle:"owned")
    guard case .raster(let pixels) = layer.content else { return XCTFail("Missing background raster") }
    XCTAssertEqual(pixels.width,8001); XCTAssertEqual(pixels.height,2)
    XCTAssertEqual(pixels.pixel(x:0,y:0),Pixel(0,0,1)); XCTAssertEqual(pixels.pixel(x:8000,y:1),Pixel(0,0,1))
    var session = EditorSession(document:d)
    try session.execute(GeneratedBackground.command(layer,source:d,foregroundID:try XCTUnwrap(d.activeLayerID)))
    XCTAssertEqual(session.undoStack.count,1)
    XCTAssertEqual(Array(session.document.layers.dropFirst()),original.layers)
    try session.undo(); XCTAssertEqual(session.document,original)
    XCTAssertEqual(d,original)
  }

  func testAboveEightMegapixelsUsesBoundedReferenceAndDoesNotChangeSource() throws {
    let d = try document(width:4097,height:2049,depth:.u16), before = d
    XCTAssertGreaterThan(d.width*d.height,8_388_608)
    let image = try GeneratedBackground.reference(d)
    XCTAssertEqual(image.width,2048); XCTAssertEqual(image.height,1024)
    XCTAssertLessThanOrEqual(image.width*image.height,RasterPreviewRequest.maximumPixels)
    XCTAssertEqual(d,before)
    XCTAssertNotNil(GeneratedBackground.foreground(in:d))
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let destination=URL(fileURLWithPath:path).appendingPathComponent("owned-large-background.photato")
      try DocumentIO.encode(d,format:.native).write(to:destination)
    }
  }

  func testMaximumLogicalCanvasReferenceAndRecordStayBoundedWithoutClaimingDenseOutput() throws {
    let d = try document(width:300000,height:300000), before = d
    let image = try GeneratedBackground.reference(d)
    XCTAssertEqual(image.width,2048); XCTAssertEqual(image.height,2048)
    XCTAssertEqual(d,before)
    let record = GeneratedBackgroundRecord(foregroundLayerID:try XCTUnwrap(d.activeLayerID),width:d.width,height:d.height)
    XCTAssertNoThrow(try record.validate())
    XCTAssertEqual(AIImageAPI.backgroundRecord(record)["width"] as? Int,300000)
    // Reference/metadata qualification, not a90Gpixel output allocation or model run.
  }

  func testLargePreviewSamplesOnlySubjectWithLiteralMaskDensityAndIgnoresLayerBlending() throws {
    var d = try document(width:8001,height:2)
    let subject = try XCTUnwrap(d.activeLayerID)
    d.layers[0].mask = try Surface(width:d.width,height:d.height,fill:.black)
    var properties = MaskProperties(); properties.density=0.5
    d.layers[0].maskProperties=properties; d.layers[0].opacity=0.125; d.layers[0].blendMode = .multiply
    var cover = Layer(name:"Unrelated red cover",content:.raster(try Surface(width:d.width,height:d.height,fill:Pixel(1,0,0))))
    cover.visible=true; d.layers.append(cover)
    let before = d, request = try GeneratedBackground.referenceRequest(width:d.width,height:d.height)
    let layer = try XCTUnwrap(d.layers.first(where:{$0.id==subject}))
    let preview = try Renderer.clippingCoveragePreview(layer,in:d,request:request)
    XCTAssertEqual(preview.width,2048); XCTAssertEqual(preview.height,1)
    var bytes = Data()
    for x in 0..<preview.width {
      let pixel=preview.pixel(x:x,y:0)
      let words=[pixel.r,pixel.g,pixel.b,pixel.a].map {UInt8((min(1,max(0,$0))*255).rounded())}
      XCTAssertEqual(words,[64,128,191,128]); bytes.append(contentsOf:words)
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      try bytes.write(to:URL(fileURLWithPath:path).appendingPathComponent("large-background-reference.rgba8"))
    }
    XCTAssertEqual(d,before)
  }

  @MainActor func testLongBackgroundLifecycleAllDepthsKeepsExactSourceAndReopensWithOneUndo() async throws {
    let helper=GeneratedBackgroundTests(), bytes=try helper.image()
    for depth in PixelDepth.allCases {
      let s=try ImageGenerationLifecycleTests().store(depth)
      defer{s.cancelAIWork();s.renderTask?.cancel()}
      s.session=EditorSession(document:try document(width:8001,height:2,depth:depth))
      s.imageGenerationIntent = .background; s.prompt="Owned long background"
      let before=s.document
      let job=try await helper.begin(s)
      XCTAssertEqual(job.sourceWidth,8001); XCTAssertEqual(job.referenceWidth,2048)
      XCTAssertEqual(s.document,before); XCTAssertTrue(s.session.undoStack.isEmpty)
      try s.acceptGeneratedImageData(bytes,requestID:job.id,resultStyle:"owned")
      await (try XCTUnwrap(s.aiTask)).value
      XCTAssertEqual(job.phase,.completed,s.aiError ?? "")
      XCTAssertEqual(s.session.undoStack.count,1)
      XCTAssertEqual(Array(s.document.layers.dropFirst()),before.layers)
      XCTAssertEqual(s.document.selection,before.selection)
      let result=s.document, layer=try XCTUnwrap(s.activeLayer)
      XCTAssertEqual(try GeneratedImageStorage.original(layer).1,bytes)
      XCTAssertEqual(try GeneratedBackground.record(layer)?.width,8001)
      let reopened=try DocumentIO.decode(DocumentIO.encode(result,format:.native),native:true,name:"Offline")
      XCTAssertEqual(reopened.layers,result.layers); XCTAssertEqual(reopened.width,8001)
      let undone=await s.undo();XCTAssertTrue(undone);XCTAssertEqual(s.document,before)
      let redone=await s.redo();XCTAssertTrue(redone);XCTAssertEqual(s.document,result)
    }
  }

  @MainActor func testHTTPLongBackgroundUsesExistingNativeApprovalStateSchemasAndOriginalTransfer() async throws {
    let h=AutomationTests(), helper=GeneratedBackgroundTests()
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      try ImageGenerationLifecycleTests().isolate(doc.store)
      doc.store.session=EditorSession(document:try self.document(width:8001,height:2))
      doc.store.renderTask?.cancel()
      defer{doc.store.cancelAIWork();doc.store.renderTask?.cancel()}
      try service.share(doc)
      let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/ai"
      let controller=NSWindowController(window:NSWindow(contentRect:.init(x:0,y:0,width:300,height:200),styleMask:[.titled],backing:.buffered,defer:false))
      doc.addWindowController(controller)
      defer{doc.store.showAI=false;doc.removeWindowController(controller);controller.close()}
      let before=doc.store.document
      @MainActor func body()->[String:Any] { ["operation":"prepare","intent":"background","prompt":"Owned API long background","revision":service.revision(doc.store)] }
      let denied=try await h.request(service,path:path,body:body());XCTAssertEqual(denied.0.statusCode,403)
      service.setWorkspacePanelChangesEnabled(true)
      let prepared=try await h.request(service,path:path,body:body())
      XCTAssertEqual(prepared.0.statusCode,200,String(decoding:prepared.1,as:UTF8.self))
      XCTAssertTrue(doc.store.showAI);XCTAssertFalse(doc.store.aiBusy);XCTAssertNil(doc.store.imageGenerationJob)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let job=try await helper.begin(doc.store),bytes=try helper.image()
      try doc.store.acceptGeneratedImageData(bytes,requestID:job.id,resultStyle:"owned")
      await (try XCTUnwrap(doc.store.aiTask)).value
      XCTAssertEqual(job.phase,.completed,doc.store.aiError ?? "")
      let response=try await h.request(service,path:path);XCTAssertEqual(response.0.statusCode,200)
      let state=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any])
      let context=try XCTUnwrap(state["selectedBackground"]as?[String:Any])
      XCTAssertEqual(context["width"]as?Int,8001)
      let value=try JSONDecoder().decode(AutomationValue.self,from:JSONSerialization.data(withJSONObject:context))
      XCTAssertNoThrow(try BrushAPI.merge(value,schema:AIImageAPI.backgroundRecordSchema))
      XCTAssertEqual(doc.store.session.undoStack.count,1)
      XCTAssertEqual(Array(doc.store.document.layers.dropFirst()),before.layers)
      service.setDocumentTransfersEnabled(true)
      let downloaded=try await h.request(service,path:"/v1/documents/\(share.id)/ai/results/\(try XCTUnwrap(job.resultLayerID))")
      XCTAssertEqual(downloaded.0.statusCode,200);XCTAssertEqual(downloaded.1,bytes)
      let limits=try XCTUnwrap((AIImageAPI.capabilities["background"]as?[String:Any])?["limits"]as?[String:Any])
      XCTAssertEqual(limits["maximumCanvasDimension"]as?Int,300000)
      XCTAssertEqual(limits["maximumCanvasPixels"]as?Int,90_000_000_000)
      XCTAssertEqual(limits["maximumReferencePixels"]as?Int,4_194_304)
    }
  }

  @MainActor func testLongReferenceCancellationCannotPublishIntoReplacementSource() async throws {
    let s=try ImageGenerationLifecycleTests().store(), gate=ImageGenerationLifecycleTests.Gate()
    defer{s.cancelAIWork();s.renderTask?.cancel()}
    s.session=EditorSession(document:try document(width:8001,height:2))
    s.imageGenerationIntent = .background;s.prompt="Owned cancellation"
    s.backgroundReferencePreparation={source in await gate.wait();return try GeneratedBackground.reference(source)}
    let before=s.document
    try s.startImageGeneration(capability:GeneratedBackgroundTests().capability)
    let job=try XCTUnwrap(s.imageGenerationJob),task=try XCTUnwrap(s.aiTask)
    try await ImageGenerationLifecycleTests().wait(gate)
    s.cancelImageGeneration(job.id)
    s.session=EditorSession(document:try document(width:9001,height:2))
    let replacement=s.document
    await gate.release();await task.value
    XCTAssertEqual(job.phase,.cancelled);XCTAssertNil(job.referenceImage)
    XCTAssertEqual(s.document,replacement);XCTAssertNotEqual(s.document.id,before.id)
    XCTAssertTrue(s.session.undoStack.isEmpty);XCTAssertFalse(s.aiBusy)
  }

  func testPlacementRecordRejectsInvalidGeometryAndBoundedPreviewRejectsForeignLayer() throws {
    let id=UUID()
    for (width,height)in [(0,2),(2,0),(-1,2),(300001,2),(2,300001),(Int.max,Int.max)] {
      XCTAssertThrowsError(try GeneratedBackgroundRecord(foregroundLayerID:id,width:width,height:height).validate())
    }
    let d=try document(width:8001,height:2),request=try GeneratedBackground.referenceRequest(width:d.width,height:d.height)
    let foreign=Layer(name:"Foreign",content:.raster(try Surface(width:1,height:1,fill:.white)))
    XCTAssertThrowsError(try Renderer.clippingCoveragePreview(foreign,in:d,request:request))
    XCTAssertEqual(d.width,8001)
  }
}
