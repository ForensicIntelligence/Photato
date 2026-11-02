import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PcraftFillWorkflowTests:XCTestCase {
  func fixture(_ bits:String="u8")throws->Data {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/PcraftFills")
    return try Data(contentsOf:root.appendingPathComponent("fills-\(bits).pcraft"))
  }
  @MainActor func testNativeRichFillOpenEditingHistoryAndSaveAsPreserveSource()async throws {
    _ = NSApplication.shared
    let folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    for bits in ["u8","u16","f32"] {
      let bytes=try fixture(bits),url=folder.appendingPathComponent("fills-\(bits).pcraft");try bytes.write(to:url)
      let prepared=try PreparedLocalDocument.read(url,format:.pcraft),doc=prepared.makeDocument(url:url)
      defer{doc.updateChangeCount(.changeCleared);doc.close()}
      XCTAssertNil(doc.fileURL);XCTAssertEqual(doc.importedSourceURL,url)
      let original=doc.store.document
      guard case .gradientFill(var gradient)=original.layers[1].content else{return XCTFail("Editable fill")}
      gradient.placement.angle=123;try doc.store.executeEditorCommand(.setGradientFill(original.layers[1].id,gradient))
      try doc.store.session.undo();XCTAssertEqual(doc.store.document,original);try doc.store.session.redo()
      let edited=doc.store.document,target=folder.appendingPathComponent("migrated-\(bits).photato")
      try await DocumentSaveWorkflowTests().save(doc,to:target,format:.native)
      XCTAssertEqual(try DocumentIO.read(target),edited);XCTAssertEqual(try Data(contentsOf:url),bytes)
    }
  }
  @MainActor func testHTTPRichImportStyleEditNativeEquivalenceDownloadAndStaleGuard()async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}){service,parent in
      defer{for doc in service.controller.documents where doc !== parent{doc.updateChangeCount(.changeCleared);doc.close()}}
      service.setDocumentTransfersEnabled(true);let input=try self.fixture("f32")
      let response=try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),doc=try XCTUnwrap(share.document),model=try PcraftImport.read(input)
      XCTAssertEqual(doc.store.document,model)
      let desktop=EditorStore(document:model);defer{desktop.renderTask?.cancel()}
      var style=try XCTUnwrap(model.layers[0].style);style.fillOpacity=0.3
      try desktop.executeEditorCommand(.layerStyle([model.layers[0].id],style))
      let json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(style))
      let revision=service.revision(doc.store)
      let edited=try await AutomationTests().edit(service,doc,"layer.style",["layerIDs":[model.layers[0].id.uuidString],"style":json])
      XCTAssertEqual(edited,200);XCTAssertEqual(doc.store.document,desktop.document)
      XCTAssertEqual(try Renderer.composite(doc.store.document).rgbaData(depth:.u8),try Renderer.composite(desktop.document).rgbaData(depth:.u8))
      let stale=try await AutomationTests().request(service,path:"/v1/documents/\(share.id)/commands",body:["revision":revision,"command":"layer.opacity","parameters":["layerID":model.layers[0].id.uuidString,"opacity":0.5]])
      XCTAssertEqual(stale.0.statusCode,409);XCTAssertEqual(doc.store.document,desktop.document)
      let file=try await AutomationTests().request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"66"])
      XCTAssertEqual(file.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(file.1),desktop.document)
      try doc.store.session.undo();XCTAssertEqual(doc.store.document,model);try doc.store.session.redo();XCTAssertEqual(doc.store.document,desktop.document)
      let caps=try await AutomationTests().request(service,path:"/v1/capabilities")
      let data=try XCTUnwrap(JSONSerialization.jsonObject(with:caps.1)as?[String:Any]);let opening=try XCTUnwrap(data["documentOpening"]as?[String:Any]);let pcraft=try XCTUnwrap(opening["pcraft"]as?[String:Any]);XCTAssertTrue((pcraft["supported"]as?String)?.contains("fill layers")==true)
    }
  }
  private actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data){self.data=data}
    func fetch(_ url:URL)async throws->Data{data}
    func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("Hosted fixture output only.")}
  }
  @MainActor func testRichFillPhotatoResourceJobAndPublishedAdobeFormatBoundary()async throws {
    let input=try fixture("f32"),helper=AutomationTests()
    let payload:[String:Any]=[
      "image":["source":["url":"https://example.test/owned-fills.pcraft"]],
      "options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],
      "outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
    try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)){service,parent in
      let original=parent.store.document;service.setResourceJobsEnabled(true)
      for (route,type,succeeds) in [("/v1/action-jobs","image/vnd.adobe.photoshop",false),("/v1/action-jobs","image/png",false),("/v1/action-jobs","image/tiff",true),("/v2/execute-actions","image/vnd.adobe.photoshop",false)] {
        var request=payload;request["outputs"]=[["mediaType":type,"destination":["validityPeriod":60]]]
        let response=try await helper.request(service,path:route,body:request)
        XCTAssertEqual(response.0.statusCode,202)
        let result=try XCTUnwrap(JSONSerialization.jsonObject(with:response.1)as?[String:Any])
        let status=try XCTUnwrap(URL(string:try XCTUnwrap(result["statusUrl"]as?String)))
        var terminal:[String:Any]?
        for _ in 0..<1000 {
          let reply=try await helper.request(service,path:status.path)
          let value=try XCTUnwrap(JSONSerialization.jsonObject(with:reply.1)as?[String:Any])
          if ["succeeded","failed"].contains(value["status"]as?String ?? ""){terminal=value;break}
          try await Task.sleep(for:.milliseconds(10))
        }
        let value=try XCTUnwrap(terminal)
        XCTAssertEqual(value["status"]as?String,succeeds ? "succeeded":"failed","\(value)")
        if succeeds {
          let outputs=try XCTUnwrap((value["result"]as?[String:Any])?["outputs"]as?[[String:Any]])
          let destination=try XCTUnwrap(outputs.first?["destination"]as?[String:Any])
          let url=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"]as?String)))
          let asset=try await helper.request(service,path:url.path)
          XCTAssertEqual(asset.0.statusCode,200);XCTAssertEqual(asset.1,try DocumentIO.encode(PcraftImport.read(input),format:.tiff))
        } else if route.hasPrefix("/v1") {
          let details=try XCTUnwrap(value["errorDetails"]as?[[String:Any]])
          XCTAssertTrue((details.first?["message"]as?String)?.contains(type=="image/png" ? "cannot retain RGB32":"solid-color export requires opaque")==true)
        }
      }
      XCTAssertEqual(parent.store.document,original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
    }
  }
}
