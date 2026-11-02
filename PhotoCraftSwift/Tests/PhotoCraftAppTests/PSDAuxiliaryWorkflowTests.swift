import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PSDAuxiliaryWorkflowTests:XCTestCase {
  @MainActor func cleanup(_ controller:CraftDocumentController) {
    for case let doc as CraftNSDocument in controller.documents {doc.updateChangeCount(.changeCleared);doc.close()}
  }
  func input()throws->Data {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/PSDAuxiliary")
    return try Data(contentsOf:root.appendingPathComponent("m3-d32-v2-c3.psb"))
  }
  @MainActor func testDesktopSavePolicyNativeHistoryAndPSDPSBUseSameData()async throws {
    let d=try PSDCodec.read(input()),store=EditorStore(document:d);defer{store.renderTask?.cancel()}
    for format in [DocumentIO.Format.psd,.psb] {
      XCTAssertNil(DocumentIO.persistenceIssue(d,format:format))
      let bytes=try DocumentIO.encode(d,format:format),restored=try PSDCodec.read(bytes)
      XCTAssertEqual(restored.alphaChannels?.map(\.name),d.alphaChannels?.map(\.name));XCTAssertEqual(restored.quickMask?.name,d.quickMask?.name)
      XCTAssertEqual(restored.alphaChannels?.last?.psdSpotGray,d.alphaChannels?.last?.psdSpotGray)
    }
    let channel=try XCTUnwrap(d.alphaChannels?.last)
    try store.executeEditorCommand(.channel(.configure(channel.id,"Proof",channel.options,SpotInk(color:Pixel(1,0,1),solidity:0.75))))
    XCTAssertEqual(store.document.alphaChannels?.last?.psdSpotGray,channel.psdSpotGray)
    await store.undo();XCTAssertEqual(store.document,d);await store.redo();XCTAssertEqual(store.document.alphaChannels?.last?.name,"Proof")
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(store.document)),store.document)
  }
  @MainActor func testHTTPPSDTransfersPreserveChannelsAndRequireNative77()async throws {
    let helper=AutomationTests(),io=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}){service,_ in
      defer{cleanup(service.controller)};service.setDocumentTransfersEnabled(true)
      let uploaded=try await io.request(service,path:"/v1/documents/import",data:input(),type:"application/x-photoshop")
      XCTAssertEqual(uploaded.0.statusCode,201,String(decoding:uploaded.1,as:UTF8.self))
      let object=try XCTUnwrap(JSONSerialization.jsonObject(with:uploaded.1)as?[String:Any]),id=try XCTUnwrap(object["id"]as?String),doc=try XCTUnwrap(service.shares.first?.document),before=doc.store.document
      XCTAssertEqual(before.minimumArchiveVersion,77);XCTAssertEqual(before.alphaChannels?.count,2);XCTAssertNotNil(before.quickMask)
      for format in ["psd","psb"] {
        let response=try await helper.request(service,path:"/v1/documents/\(id)/file.\(format)");XCTAssertEqual(response.0.statusCode,200)
        let native=try DocumentIO.encode(before,format:format=="psb" ? .psb:.psd);XCTAssertEqual(response.1,native)
        let decoded=try PSDCodec.read(response.1);XCTAssertEqual(decoded.alphaChannels?.last?.psdSpotGray,before.alphaChannels?.last?.psdSpotGray)
      }
      let old=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"76"]);XCTAssertEqual(old.0.statusCode,422)
      let saved=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"77"]);XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(saved.1),before)
      let channels=try XCTUnwrap(service.state(service.shares[0],document:doc)["channels"]as?[[String:Any]])
      XCTAssertEqual((channels[1]["psd"]as?[String:Any])?["retainedFloat32SpotGray"]as?Bool,true)
      XCTAssertEqual(doc.store.document,before);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      XCTAssertNotNil(AutomationService.documentTransferCapabilities["auxiliaryPhotoshop"])
    }
  }
  @MainActor func testStaleAndMalformedTransfersLeaveDocumentAndSourceUntouched()async throws {
    let helper=AutomationTests(),io=DocumentIOWorkflowTests(),bytes=try input()
    try await helper.withService(pressedMouseButtons:{0}){service,shared in
      defer{cleanup(service.controller)};service.setDocumentTransfersEnabled(true);shared.store.session=EditorSession(document:try PSDCodec.read(bytes));try service.share(shared)
      let before=shared.store.document,id=try XCTUnwrap(service.shares.first?.id)
      let stale=try await helper.request(service,path:"/v1/documents/\(id)/file.psb",headers:["X-Photato-Revision":"old"]);XCTAssertEqual(stale.0.statusCode,409)
      let bad=try await io.request(service,path:"/v1/documents/import",data:Data(bytes.dropLast()),type:"application/x-photoshop");XCTAssertEqual(bad.0.statusCode,422)
      XCTAssertEqual(shared.store.document,before);XCTAssertEqual(try input(),bytes)
      shared.store.beginChannelDialog(.options)
      let busy=try await helper.request(service,path:"/v1/documents/\(id)/file.psb");XCTAssertEqual(busy.0.statusCode,409);shared.store.channelDialog=nil
      XCTAssertEqual(shared.store.document,before)
    }
  }
  @MainActor func testLargePSBSaveAdmissionUsesFormatLimitWithoutDenseCanvasCap()throws {
    var d=try CraftDocument(width:300000,height:300000)
    let alpha=AlphaChannel(name:"Sparse",pixels:try Surface(width:d.width,height:d.height,fill:.white));d.alphaChannels=[alpha]
    XCTAssertNil(DocumentIO.persistenceIssue(d,format:.psb))
    XCTAssertNotNil(DocumentIO.persistenceIssue(d,format:.psd))
    XCTAssertNotNil(DocumentIO.persistenceIssue(d,format:.tiff))
    XCTAssertEqual(d.width,PSDFileFormat.psb.maximumDimension)
  }
}
