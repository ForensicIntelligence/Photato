import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PcraftArtboardWorkflowTests:XCTestCase {
  func fixture(_ name:String) throws -> Data {
    let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf:root.appendingPathComponent("PhotoCraftImagingTests/Fixtures/PcraftArtboards/\(name).pcraft"))
  }
  @MainActor func testNativeOpenPropertiesCancelCommitHistorySaveAndReopenAtEveryDepth() async throws {
    _ = NSApplication.shared
    let folder = try DocumentPersistenceTests().directory();defer { try? FileManager.default.removeItem(at:folder) }
    for bits in ["u8","u16","f32"] {
      let bytes = try fixture("negative-\(bits)"),url = folder.appendingPathComponent("Original-\(bits).pcraft")
      try bytes.write(to:url)
      let document = try PreparedLocalDocument.read(url,format:.pcraft).makeDocument(url:url)
      defer { document.store.renderTask?.cancel();document.updateChangeCount(.changeCleared);document.close() }
      XCTAssertNil(document.fileURL);XCTAssertEqual(document.importedSourceURL,url)
      let original = document.store.document
      document.store.session.selectLayer(original.artboards[0].id)
      let selected = document.store.document
      document.store.beginArtboard(edit:true);XCTAssertNotNil(document.store.artboardDraft)
      document.store.artboardDraft = nil;XCTAssertEqual(document.store.document,selected)
      document.store.beginArtboard(edit:true)
      let draft = try XCTUnwrap(document.store.artboardDraft)
      XCTAssertEqual(draft.preset,"Owned 40 × 48")
      draft.name = "Edited source board";draft.width = 44;draft.moveContents = false
      document.store.commitArtboard(draft)
      XCTAssertNil(document.store.error);XCTAssertNil(document.store.artboardDraft)
      let edited = document.store.document
      XCTAssertEqual(edited.artboards[0].name,"Edited source board")
      XCTAssertEqual(edited.artboards[0].artboard?.width,44)
      XCTAssertEqual(edited.artboards[0].artboard?.preset,"Owned 40 × 48")
      XCTAssertEqual(edited.layers[0],selected.layers[0])
      let undone = await document.store.requestHistory(redo:false).value;XCTAssertTrue(undone)
      XCTAssertEqual(document.store.document,selected)
      let redone = await document.store.requestHistory(redo:true).value;XCTAssertTrue(redone)
      XCTAssertEqual(document.store.document,edited)
      let target = folder.appendingPathComponent("Edited-\(bits).photato")
      try await DocumentSaveWorkflowTests().save(document,to:target,format:.native)
      XCTAssertEqual(try DocumentIO.read(target),edited)
      XCTAssertEqual(try Data(contentsOf:url),bytes)
      for format in [DocumentIO.Format.psd,.psb] {
        let photoshop=try PSDCodec.read(DocumentIO.encode(edited,format:format))
        XCTAssertEqual(photoshop.artboards.count,4)
        XCTAssertEqual(photoshop.artboards[0].artboard?.preset,"Owned 40 × 48")
        XCTAssertEqual(photoshop.artboards.compactMap{photoshop.logicalArtboardBounds($0)},edited.artboards.compactMap{edited.logicalArtboardBounds($0)})
        XCTAssertTrue(photoshop.layers.contains{if case .fill=$0.content{return true};return false})
      }
    }
  }
  @MainActor func testHTTPImportSharesEditableArtboardsHistoryStrictGuardsAndExports() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,parent in
      defer { for doc in service.controller.documents where doc !== parent { (doc as? CraftNSDocument)?.store.renderTask?.cancel();doc.updateChangeCount(.changeCleared);doc.close() } }
      let input = try fixture("negative-u16")
      let denied = try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(denied.0.statusCode,403);XCTAssertTrue(service.shares.isEmpty)
      service.setDocumentTransfersEnabled(true)
      let response = try await AutomationOpeningTests().upload(service,bytes:input,type:PcraftImport.mediaType,format:"pcraft")
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self))
      let share = try XCTUnwrap(service.shares.first),document = try XCTUnwrap(share.document),original = document.store.document
      XCTAssertEqual(original,try PcraftImport.read(input))
      let board = original.artboards[0],bounds = try XCTUnwrap(original.logicalArtboardBounds(board))
      let parameters:[String:Any] = ["operation":"configure","layerID":board.id.uuidString,"name":"API source board",
        "bounds":["x":bounds.x,"y":bounds.y,"width":44,"height":48],"background":["r":0,"g":0,"b":0,"a":1],"moveContents":false]
      var expected = original
      var appearance = try XCTUnwrap(board.artboard);appearance.width = 44;appearance.background = .black
      try Command.artboard(.configure(board.id,name:"API source board",bounds:.init(x:bounds.x,y:bounds.y,width:44,height:48),appearance:appearance,moveContents:false)).apply(to:&expected)
      let edited = try await helper.edit(service,document,"artboard.edit",parameters)
      XCTAssertEqual(edited,200);XCTAssertEqual(document.store.document,expected)
      let undo = try await helper.edit(service,document,"history.undo")
      XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
      let stale = try await helper.edit(service,document,"artboard.edit",parameters,revision:"stale")
      XCTAssertEqual(stale,409)
      document.store.geometryBusy = true
      let busy = try await helper.edit(service,document,"artboard.edit",parameters)
      document.store.geometryBusy = false;XCTAssertEqual(busy,409)
      var invalid = parameters;invalid["moveContents"] = "yes"
      let bad = try await helper.edit(service,document,"artboard.edit",invalid)
      XCTAssertEqual(bad,400);XCTAssertEqual(document.store.document,original)
      let path = "/v1/documents/\(share.id)/commands"
      let export = try await helper.request(service,path:path,body:["command":"artboard.export","revision":service.revision(document.store),
        "parameters":["layerIDs":[board.id.uuidString],"format":"png"]])
      XCTAssertEqual(export.0.statusCode,200)
      let pixels = try Renderer.composite(RasterIO.read(export.1,name:"Export"))
      XCTAssertEqual(export.1,try DocumentIO.encode(original.extractedArtboard(board.id),format:.png))
      XCTAssertEqual(pixels.width,40);XCTAssertEqual(pixels.height,48)
      for y in 0..<48 { for x in 0..<40 {
        let p = pixels.pixel(x:x,y:y)
        XCTAssertEqual([p.r,p.g,p.b,p.a].map { Int(($0*65535).rounded()) },[65535,32768,32768,65535])
      } }
      let native = try await helper.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"92"])
      XCTAssertEqual(native.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(native.1),original)
      XCTAssertEqual(document.store.document,original);XCTAssertEqual(try fixture("negative-u16"),input)
      XCTAssertNotNil((AutomationService.documentOpeningCapabilities["pcraft"] as? [String:Any])?["artboards"])
    }
  }
  private actor Transport:AdobeResourceTransport {
    let bytes:Data
    init(_ bytes:Data) { self.bytes = bytes }
    func fetch(_ url:URL) async throws -> Data { bytes }
    func upload(_ data:Data,output:AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("Hosted test output only.") }
  }
  @MainActor func testResourceJobUsesPhotatoExtensionAndRejectsAdobeSourceType() async throws {
    let input = try fixture("filled-u8"),helper = AutomationTests()
    let payload:[String:Any] = ["image":["source":["url":"https://example.test/owned.pcraft"]],
      "options":["actions":[["source":["contentType":"application/json","content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]"]]]],
      "outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    try await helper.withService(pressedMouseButtons:{0},resourceTransport:Transport(input)) { service,parent in
      service.setResourceJobsEnabled(true);let original = parent.store.document
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        let response = try await helper.request(service,path:route,body:payload)
        XCTAssertEqual(response.0.statusCode,202)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any])
        let url = try XCTUnwrap(URL(string:try XCTUnwrap(body["statusUrl"] as? String)))
        var terminal:[String:Any]?
        for _ in 0..<1000 {
          let status = try await helper.request(service,path:url.path)
          let value = try XCTUnwrap(JSONSerialization.jsonObject(with:status.1) as? [String:Any])
          if ["succeeded","failed"].contains(value["status"] as? String ?? "") { terminal = value;break }
          try await Task.sleep(for:.milliseconds(10))
        }
        let result = try XCTUnwrap(terminal)
        XCTAssertEqual(result["status"] as? String,route.hasPrefix("/v1") ? "succeeded":"failed","\(result)")
        if route.hasPrefix("/v1") {
          let output = try XCTUnwrap((result["result"] as? [String:Any])?["outputs"] as? [[String:Any]])
          let destination = try XCTUnwrap(output.first?["destination"] as? [String:Any])
          let asset = try XCTUnwrap(URL(string:try XCTUnwrap(destination["url"] as? String)))
          let downloaded = try await helper.request(service,path:asset.path)
          XCTAssertEqual(downloaded.0.statusCode,200)
          XCTAssertEqual(downloaded.1,try DocumentIO.encode(PcraftImport.read(input),format:.png))
          let pixels = try Renderer.composite(RasterIO.read(downloaded.1,name:"Output"))
          XCTAssertEqual(pixels.width,220);XCTAssertEqual(pixels.height,100)
          let p = pixels.pixel(x:10,y:20)
          XCTAssertEqual([p.r,p.g,p.b,p.a].map { Int(($0*255).rounded()) },[255,128,128,255])
        }
      }
      XCTAssertEqual(parent.store.document,original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
    }
  }
}
