import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MultichannelQuickMaskWorkflowTests:XCTestCase {
  func input()throws->Data {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/multichannel-quick-mask")
    return try Data(contentsOf:folder.appendingPathComponent("selection8.psd"))
  }
  func capture(_ data:Data,_ name:String)throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else{return}
    let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try data.write(to:folder.appendingPathComponent(name))
  }
  func assertChannels(_ read:CraftDocument,_ original:CraftDocument,file:StaticString=#filePath,line:UInt=#line) {
    XCTAssertEqual(read.quickMask?.pixels,original.quickMask?.pixels,file:file,line:line)
    XCTAssertEqual(read.quickMask?.options,original.quickMask?.options,file:file,line:line)
    XCTAssertEqual(read.quickMask?.psdIdentifier,original.quickMask?.psdIdentifier,file:file,line:line)
    XCTAssertEqual(read.quickMask?.psdQuickMaskInitiallyEmpty,original.quickMask?.psdQuickMaskInitiallyEmpty,file:file,line:line)
    XCTAssertEqual(read.alphaChannels?.map(\.pixels),original.alphaChannels?.map(\.pixels),file:file,line:line)
    XCTAssertEqual(read.alphaChannels?.map(\.psdIdentifier),original.alphaChannels?.map(\.psdIdentifier),file:file,line:line)
  }
  @MainActor func testNativeOpenSelectsQuickMaskAndPaintingUndoSaveReopenPreserveSavedChannels()async throws {
    let model=try PSDCodec.read(input()),store=EditorStore(document:model,quickMaskPreferences:QuickMaskPreferences())
    defer{store.renderTask?.cancel()}
    XCTAssertEqual(store.editingChannel,.quickMask);XCTAssertTrue(store.isQuickMaskVisible)
    var brush=store.brush;brush.size=3;brush.hardness=1;brush.color = .white
    store.stroke([.init(x:4,y:2)],brush:brush);XCTAssertNil(store.error)
    XCTAssertEqual(store.document.alphaChannels,model.alphaChannels);XCTAssertNotEqual(store.document.quickMask?.pixels,model.quickMask?.pixels)
    await store.undo();XCTAssertEqual(store.document,model);await store.redo();XCTAssertNotEqual(store.document.quickMask?.pixels,model.quickMask?.pixels)
    for format in [DocumentIO.Format.psd,.psb] {XCTAssertNil(DocumentIO.persistenceIssue(store.document,format:format));let data=try DocumentIO.encodeForPersistence(store.document,format:format);assertChannels(try PSDCodec.read(data),store.document);try capture(data,"native-quick-\(format).psddata")}
    store.toggleQuickMask();XCTAssertNil(store.document.quickMask);XCTAssertEqual(store.document.alphaChannels,model.alphaChannels)
    await store.undo();XCTAssertNotNil(store.document.quickMask)
  }
  @MainActor func testNativeDocumentSaveAsAndReopenRetainActiveTemporaryPlane()async throws {
    _ = NSApplication.shared;let file=CraftNSDocument(model:try PSDCodec.read(input()))
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer{file.close();try? FileManager.default.removeItem(at:folder)}
    let original=file.store.document,target=folder.appendingPathComponent("selection.psb")
    try await file.persistDocument(to:target,format:.psb,operation:.saveAsOperation)
    XCTAssertEqual(file.fileURL,target);XCTAssertFalse(file.isDocumentEdited);XCTAssertEqual(file.store.document,original)
    let reopened=CraftNSDocument(model:try CraftDocument(width:1,height:1));defer{reopened.close()}
    try reopened.read(from:Data(contentsOf:target),ofType:DocumentIO.Format.psb.contentType.identifier)
    assertChannels(reopened.store.document,original);XCTAssertEqual(reopened.store.editingChannel,.quickMask)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(original)),original)
  }
  @MainActor func testHTTPTransfersShareNativeCodecAndPreserveStaleBusyAndMalformedGuards()async throws {
    let helper=AutomationTests(),io=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,_ in
      defer{PSDAuxiliaryWorkflowTests().cleanup(service.controller)};service.setDocumentTransfersEnabled(true)
      let uploaded=try await io.request(service,path:"/v1/documents/import",data:input(),type:"application/x-photoshop")
      XCTAssertEqual(uploaded.0.statusCode,201,String(decoding:uploaded.1,as:UTF8.self))
      let object=try XCTUnwrap(JSONSerialization.jsonObject(with:uploaded.1)as?[String:Any]),id=try XCTUnwrap(object["id"]as?String)
      let file=try XCTUnwrap(service.shares.first{$0.id.uuidString==id}?.document),before=file.store.document
      for format in [DocumentIO.Format.psd,.psb] {
        let response=try await helper.request(service,path:"/v1/documents/\(id)/file.\(format == .psd ? "psd":"psb")")
        XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(response.1,try DocumentIO.encode(before,format:format));assertChannels(try PSDCodec.read(response.1),before)
        try capture(response.1,"http-quick-\(format).psddata")
      }
      let native=try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"85"])
      XCTAssertEqual(native.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(native.1),before)
      let stale=try await helper.request(service,path:"/v1/documents/\(id)/file.psb",headers:["X-Photato-Revision":"old"]);XCTAssertEqual(stale.0.statusCode,409)
      file.store.beginChannelDialog(.options);let busy=try await helper.request(service,path:"/v1/documents/\(id)/file.psb");XCTAssertEqual(busy.0.statusCode,409);file.store.cancelChannelDialog()
      let count=service.controller.documents.count,bad=try await io.request(service,path:"/v1/documents/import",data:Data(input().dropLast()),type:"application/x-photoshop");XCTAssertEqual(bad.0.statusCode,422);XCTAssertEqual(service.controller.documents.count,count)
      XCTAssertEqual(file.store.document,before);XCTAssertTrue(file.store.session.undoStack.isEmpty)
      let caps=try XCTUnwrap(ChannelAPI.photoshopCapabilities["standaloneSelections"]as?[String:Any]);XCTAssertEqual(caps["quickMask"]as?Bool,true);XCTAssertEqual(AutomationCommand.definitions.count,AutomationTests.expectedCommandCount)
    }
  }
  func testPublishedCompositePreservesQuickMaskThroughSharedInputOutput()throws {
    let data=try input(),source=try PSDCodec.read(data)
    let request=try AdobeActionsRequest(data:JSONSerialization.data(withJSONObject:["image":["source":["url":"https://example.test/owned-mask.psd"]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]),createComposite:true)
    let result=try XCTUnwrap(AdobeActionAssets.execute(request,input:data).first);assertChannels(try PSDCodec.read(result.data),source);try capture(result.data,"adobe-quick.psddata")
  }
}
