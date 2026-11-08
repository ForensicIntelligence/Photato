import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class UntaggedPSDWorkflowTests: XCTestCase {
  @MainActor private static var bootstrap:CraftDocumentController?
  @MainActor private func bootstrapApp() {
    if Self.bootstrap==nil {Self.bootstrap=CraftDocumentController(workspaces:WorkspaceLibrary())}
    _ = NSApplication.shared
  }
  func metadata()throws->Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/PSDShapesInterop/untagged-OCIO.bin"))
  }
  func source()throws->CraftDocument {
    var d=try CraftDocument(width:4,height:3)
    var pixels=try Surface(width:4,height:3)
    pixels.setPixel(x:0,y:0,Pixel(1,0.5,0,0.5));pixels.setPixel(x:1,y:1,Pixel(0.5,1,0.5,1))
    let layer=Layer(name:"Owned untagged",content:.raster(pixels));d.layers=[layer];d.activeLayerID=layer.id
    d.profileIsUntagged=true;d.workingICC=nil;d.sourceICC=nil
    d.sourceMetadata=["psdGlobal_OCIO":try metadata()]
    return d
  }
  func raster(_ document:CraftDocument)throws->Surface {
    guard case .raster(let surface)=document.layers[0].content else{throw CraftError.invalid("Expected raster fixture")}
    return surface
  }
  @MainActor func testNativeOpenSavePSDPSBAndProfileAssignmentRetainNumericSamplesAndHistory()async throws {
    bootstrapApp()
    let model=try source(),folder=try DocumentPersistenceTests().directory()
    defer {try? FileManager.default.removeItem(at:folder)}
    let input=folder.appendingPathComponent("owned-untagged.psd")
    try PSDCodec.writeRasterLayers(model,to:input)
    let document=try PreparedLocalDocument.read(input,format:.psd).makeDocument(url:input)
    defer {document.store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close()}
    XCTAssertEqual(document.store.document.profileIsUntagged,true)
    XCTAssertEqual(document.store.document.sourceMetadata?["psdGlobal_OCIO"],try metadata())
    let samples=try raster(model).rgbaData(depth:.u8)
    for format in [DocumentIO.Format.psd,.psb] {
      let associated=document.fileURL,type=document.fileType,edited=document.isDocumentEdited
      let copy=folder.appendingPathComponent("copy."+(format == .psd ? "psd":"psb"))
      try await document.copyDocument(to:copy,format:format)
      let copied=try DocumentIO.read(copy)
      XCTAssertEqual(copied.profileIsUntagged,true)
      XCTAssertEqual(copied.sourceMetadata?["psdGlobal_OCIO"],try metadata())
      XCTAssertEqual(try raster(copied).rgbaData(depth:.u8),samples)
      XCTAssertEqual(document.fileURL,associated);XCTAssertEqual(document.fileType,type)
      XCTAssertEqual(document.isDocumentEdited,edited)
      XCTAssertNil(document.preparedSaveOutput);XCTAssertFalse(document.fileOperationBusy)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let target=folder.appendingPathComponent("saved."+(format == .psd ? "psd":"psb"))
      try await DocumentSaveWorkflowTests().save(document,to:target,format:format)
      let reopened=try DocumentIO.read(target)
      XCTAssertEqual(reopened.profileIsUntagged,true)
      XCTAssertEqual(reopened.sourceMetadata?["psdGlobal_OCIO"],try metadata())
      XCTAssertEqual(try raster(reopened).rgbaData(depth:.u8),samples)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
    let before=document.store.document
    let profile=try ColorProfileWorkflowTests().profile(CGColorSpace.sRGB,depth:.u8)
    try document.store.session.execute(ColorProfileInput.command(.init(.assign,profile:profile),in:before))
    let tagged=try PSDCodec.read(PSDCodec.writeRasterLayers(document.store.document))
    XCTAssertNotEqual(tagged.profileIsUntagged,true)
    XCTAssertNil(tagged.sourceMetadata?["psdGlobal_OCIO"])
    XCTAssertEqual(try raster(tagged).rgbaData(depth:.u8),samples)
    try document.store.session.undo();XCTAssertEqual(document.store.document,before)
  }
  private actor Transport:AdobeResourceTransport {
    let input:Data
    init(_ input:Data){self.input=input}
    func fetch(_ url:URL)async throws->Data{input}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws {
      throw AdobeAPIError.unsupported("Owned hosted test output only")
    }
  }
  @MainActor func testCopyPublicationFailureKeepsDirtySourceHistoryAndPreparedState()async throws {
    bootstrapApp()
    let model=try source(),folder=try DocumentPersistenceTests().directory()
    defer {try? FileManager.default.removeItem(at:folder)}
    let input=folder.appendingPathComponent("owned-source.psd")
    try PSDCodec.writeRasterLayers(model,to:input)
    let original=try Data(contentsOf:input)
    let document=try PreparedLocalDocument.read(input,format:.psd).makeDocument(url:input)
    defer {document.store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close()}
    try document.store.executeEditorCommand(.opacity(try XCTUnwrap(document.store.document.activeLayerID),0.5))
    let snapshot=document.store.document,type=document.fileType
    XCTAssertTrue(document.isDocumentEdited)
    let destination=folder.appendingPathComponent("missing/owned-copy.psb")
    do {
      try await document.copyDocument(to:destination,format:.psb)
      XCTFail("A missing output folder must not publish a copy")
    }catch{}
    XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
    XCTAssertEqual(try Data(contentsOf:input),original)
    XCTAssertEqual(document.store.document,snapshot)
    XCTAssertEqual(document.fileURL,input);XCTAssertEqual(document.fileType,type)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertEqual(document.store.session.undoStack.count,1)
    XCTAssertTrue(document.store.session.redoStack.isEmpty)
    XCTAssertFalse(document.fileOperationBusy);XCTAssertNil(document.preparedSaveOutput)
  }
  @MainActor func testRealHTTPUploadDownloadAndBothResourceInterfacesKeepUnmanagedPolicy()async throws {
    bootstrapApp()
    let model=try source(),input=try PSDCodec.writeRasterLayers(model),helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)) {service,parent in
      defer {for case let document as CraftNSDocument in service.controller.documents where document !== parent {
        document.store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close()
      }}
      service.setDocumentTransfersEnabled(true)
      let upload=try await AutomationOpeningTests().upload(service,bytes:input,type:"image/vnd.adobe.photoshop",format:"psd")
      XCTAssertEqual(upload.0.statusCode,201,String(decoding:upload.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document)
      XCTAssertEqual(document.store.document.profileIsUntagged,true)
      let before=document.store.document
      let download=try await helper.request(service,path:"/v1/documents/\(share.id)/file.psd")
      XCTAssertEqual(download.0.statusCode,200)
      let decoded=try PSDCodec.read(download.1)
      XCTAssertEqual(decoded.sourceMetadata?["psdGlobal_OCIO"],try self.metadata())
      XCTAssertEqual(try self.raster(decoded).rgbaData(depth:.u8),try self.raster(model).rgbaData(depth:.u8))
      XCTAssertEqual(document.store.document,before);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      service.setResourceJobsEnabled(true)
      let action="[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        let body:[String:Any]=["image":["source":["url":"https://example.test/owned-untagged.psd"]],"options":["actions":[["source":["contentType":"application/json","content":action]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
        let response=try await helper.request(service,path:route,body:body)
        XCTAssertEqual(response.0.statusCode,202)
        let reply=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any])
        let url=try XCTUnwrap(URL(string:try XCTUnwrap(reply["statusUrl"]as?String)))
        var terminal:[String:Any]?
        for _ in 0..<1000 {
          let response=try await helper.request(service,path:url.path)
          let state=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any])
          if ["succeeded","failed"].contains(state["status"]as?String ?? "") {terminal=state;break}
          try await Task.sleep(for:.milliseconds(10))
        }
        let result=try XCTUnwrap(terminal)
        XCTAssertEqual(result["status"]as?String,"succeeded",String(describing:result))
        let outputs=try XCTUnwrap((result["result"]as?[String:Any])?["outputs"]as?[[String:Any]])
        let destination=try XCTUnwrap(outputs.first?["destination"]as?[String:Any])
        let assetURL=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"]as?String)))
        let asset=try await helper.request(service,path:assetURL.path)
        XCTAssertEqual(asset.0.statusCode,200)
        let output=try PSDCodec.read(asset.1)
        XCTAssertEqual(output.profileIsUntagged,true)
        XCTAssertEqual(output.sourceMetadata?["psdGlobal_OCIO"],try self.metadata())
        XCTAssertEqual(try self.raster(output).rgbaData(depth:.u8),try self.raster(model).rgbaData(depth:.u8))
      }
      let capabilities=try await helper.request(service,path:"/v1/capabilities")
      XCTAssertEqual(capabilities.0.statusCode,200)
      XCTAssertTrue(String(decoding:capabilities.1,as:UTF8.self).contains("unmanagedPSDTransport"))
      XCTAssertTrue(String(decoding:capabilities.1,as:UTF8.self).contains("AppKit coordinated Save To"))
      XCTAssertEqual(document.store.document,before)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
