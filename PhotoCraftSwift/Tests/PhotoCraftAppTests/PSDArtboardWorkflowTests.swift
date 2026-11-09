import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PSDArtboardWorkflowTests:XCTestCase {
  func fixture(_ name:String="owned-guide-rgb8.psd") throws -> Data {
    let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf:root.appendingPathComponent("PhotoCraftImagingTests/Fixtures/PSDArtboards/"+name))
  }
  @MainActor func testNativeOpenPropertiesHistorySaveAsPSDAndPSBReopenKeepOriginal() async throws {
    _ = NSApplication.shared
    let folder=try DocumentPersistenceTests().directory();defer { try? FileManager.default.removeItem(at:folder) }
    for format in [DocumentIO.Format.psd,.psb] {
      let input=try fixture("owned-guide-rgb16.psb"),source=folder.appendingPathComponent("Original-\(format.rawValue).psb")
      try input.write(to:source)
      let document=try PreparedLocalDocument.read(source,format:.psb).makeDocument(url:source)
      defer { document.store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close() }
      let id=try XCTUnwrap(document.store.document.artboards.last?.id);document.store.session.selectLayer(id)
      let original=document.store.document
      document.store.beginArtboard(edit:true);let draft=try XCTUnwrap(document.store.artboardDraft)
      draft.name="Saved board Ω";draft.width=164;draft.preset="Owned native preset";draft.moveContents=false
      document.store.commitArtboard(draft);XCTAssertNil(document.store.error);XCTAssertNil(document.store.artboardDraft)
      let edited=document.store.document
      let undone=await document.store.requestHistory(redo:false).value;XCTAssertTrue(undone);XCTAssertEqual(document.store.document,original)
      let redone=await document.store.requestHistory(redo:true).value;XCTAssertTrue(redone);XCTAssertEqual(document.store.document,edited)
      let target=folder.appendingPathComponent("Edited.\(format.rawValue)")
      try await DocumentSaveWorkflowTests().save(document,to:target,format:format)
      let reopened=try DocumentIO.read(target),board=try XCTUnwrap(reopened.artboards.last)
      XCTAssertEqual(reopened.artboards.count,2);XCTAssertEqual(board.name,"Saved board Ω")
      XCTAssertEqual(board.artboard?.width,164);XCTAssertEqual(board.artboard?.preset,"Owned native preset")
      XCTAssertEqual(reopened.logicalArtboardBounds(board),IntRect(x:240,y:40,width:164,height:120))
      XCTAssertEqual(board.artboard?.guides.map(\.position),[25]);XCTAssertEqual(try Data(contentsOf:source),input)
    }
  }
  @MainActor func testHTTPImportEditHistoryAndBothPhotoshopDownloadsUseSharedEditableModel() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,parent in
      defer { for doc in service.controller.documents where doc !== parent { (doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close() } }
      let input=try fixture(),denied=try await AutomationOpeningTests().upload(service,bytes:input,type:"image/vnd.adobe.photoshop",format:"psd")
      XCTAssertEqual(denied.0.statusCode,403);XCTAssertTrue(service.shares.isEmpty)
      service.setDocumentTransfersEnabled(true)
      let uploaded=try await AutomationOpeningTests().upload(service,bytes:input,type:"image/vnd.adobe.photoshop",format:"psd")
      XCTAssertEqual(uploaded.0.statusCode,201,String(decoding:uploaded.1,as:UTF8.self))
      let share=try XCTUnwrap(service.shares.first),document=try XCTUnwrap(share.document),original=document.store.document
      XCTAssertEqual(original.artboards.count,2);let target=original.artboards[1]
      let parameters:[String:Any]=["operation":"configure","layerID":target.id.uuidString,"name":"API board Ω","bounds":["x":240,"y":40,"width":180,"height":140],"moveContents":false]
      var expected=original,appearance=try XCTUnwrap(target.artboard);appearance.width=180;appearance.height=140
      try Command.artboard(.configure(target.id,name:"API board Ω",bounds:.init(x:240,y:40,width:180,height:140),appearance:appearance,moveContents:false)).apply(to:&expected)
      let edit=try await helper.edit(service,document,"artboard.edit",parameters)
      XCTAssertEqual(edit,200);XCTAssertEqual(document.store.document,expected)
      for ext in ["psd","psb"] {
        let reply=try await helper.request(service,path:"/v1/documents/\(share.id)/file.\(ext)")
        XCTAssertEqual(reply.0.statusCode,200,String(decoding:reply.1.prefix(300),as:UTF8.self))
        let read=try PSDCodec.read(reply.1),board=try XCTUnwrap(read.artboards.last)
        XCTAssertEqual(read.artboards.count,2);XCTAssertEqual(read.logicalArtboardBounds(board),IntRect(x:240,y:40,width:180,height:140))
        XCTAssertEqual(board.name,"API board Ω");XCTAssertEqual(board.artboard?.guides.map(\.position),[25])
        XCTAssertEqual(document.store.document,expected)
      }
      let stale=try await helper.edit(service,document,"artboard.edit",parameters,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"artboard.edit",parameters);document.store.geometryBusy=false;XCTAssertEqual(busy,409)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
      let native=try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"92"])
      XCTAssertEqual(native.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(native.1),original)
      XCTAssertEqual(try fixture(),input)
      XCTAssertEqual((AutomationService.documentOpeningCapabilities["photoshopArtboards"]as?[String:Any])?["supported"]as?Bool,true)
    }
  }
  private actor Transport:AdobeResourceTransport {
    let data:Data
    init(_ data:Data) { self.data=data }
    func fetch(_ url:URL) async throws -> Data { data }
    func upload(_ data:Data,output:AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("Hosted outputs only.") }
  }
  @MainActor func testBothResourceJobInterfacesRetainArtboardsAndMatchNativePhotoshopOutput() async throws {
    let input=try fixture(),helper=AutomationTests()
    let payload:[String:Any]=["image":["source":["url":"https://example.test/owned-artboards.psd"]],
      "options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],
      "outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
    try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)) { service,parent in
      let original=parent.store.document;service.setResourceJobsEnabled(true)
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        let submitted=try await helper.request(service,path:route,body:payload)
        XCTAssertEqual(submitted.0.statusCode,202)
        let body=try XCTUnwrap(JSONSerialization.jsonObject(with:submitted.1)as?[String:Any])
        let statusURL=try XCTUnwrap(URL(string:try XCTUnwrap(body["statusUrl"]as?String)))
        var terminal:[String:Any]?
        for _ in 0..<1000 {
          let status=try await helper.request(service,path:statusURL.path),value=try XCTUnwrap(JSONSerialization.jsonObject(with:status.1)as?[String:Any])
          if ["succeeded","failed"].contains(value["status"]as?String ?? "") { terminal=value;break }
          try await Task.sleep(for:.milliseconds(10))
        }
        let result=try XCTUnwrap(terminal);XCTAssertEqual(result["status"]as?String,"succeeded","\(result)")
        let outputs=try XCTUnwrap((result["result"]as?[String:Any])?["outputs"]as?[[String:Any]])
        let destination=try XCTUnwrap(outputs.first?["destination"]as?[String:Any]),url=try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"]as?String)))
        let asset=try await helper.request(service,path:url.path)
        XCTAssertEqual(asset.0.statusCode,200)
        XCTAssertEqual(asset.1,try DocumentIO.encode(PSDCodec.read(input),format:.psd))
        XCTAssertEqual(try PSDCodec.read(asset.1).artboards.count,2)
      }
      XCTAssertEqual(parent.store.document,original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testSavePolicyAdmitsMappedPhotoshopBoardsAndKeepsOtherLossGuards() throws {
    _ = NSApplication.shared
    let doc=try PSDCodec.read(fixture())
    for format in [DocumentIO.Format.psd,.psb] {
      XCTAssertNil(DocumentIO.persistenceIssue(doc,format:format))
    }
    XCTAssertNotNil(DocumentIO.persistenceIssue(doc,format:.png))
    XCTAssertNotNil(DocumentIO.persistenceIssue(doc,format:.tiff))
    var changed=doc,index=try XCTUnwrap(changed.layers.firstIndex{$0.artboard != nil}),group=try XCTUnwrap(changed.layers[index].group)
    group.artboard?.background.a=0.5;changed.layers[index].content = .group(group)
    XCTAssertNotNil(DocumentIO.persistenceIssue(changed,format:.psd))
    XCTAssertThrowsError(try DocumentIO.encode(changed,format:.psd))
    XCTAssertFalse(try DocumentIO.encode(changed,format:.native).isEmpty)
  }
}
