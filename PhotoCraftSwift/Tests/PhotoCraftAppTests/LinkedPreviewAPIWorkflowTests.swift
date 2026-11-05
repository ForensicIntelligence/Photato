import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LinkedPreviewAPIWorkflowTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    let bytes=try RasterIO.encoded(Surface(width:4,height:3,fill:Pixel(1,0,0)),type:.png)
    var d=try CraftDocument(width:12,height:12,depth:depth)
    let reference=try LinkedSmartObjectSource(reference:"file:///does-not-exist/Owned.png",contentHash:LinkedSmartObjectSource.fingerprint(bytes),byteLength:UInt64(bytes.count))
    var layer=try LinkedSmartObjectIO.place(bytes,fileName:"Owned.png",reference:reference,in:d,fit:false)
    layer.x=3;layer.y=4;layer.affine = .scale(2,2);layer.mask=try Surface(width:4,height:3,depth:depth,fill:.white)
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
  @MainActor func testHTTPPSDPSBDownloadsEqualDesktopEncodingAndPreserveState()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
      service.setDocumentTransfersEnabled(true);try service.share(doc);let id=try XCTUnwrap(service.shares.first?.id)
      for depth in PixelDepth.allCases {
        let source=try self.fixture(depth);doc.store.session=EditorSession(document:source)
        for ext in ["psd","psb"] {
          let expected=try DocumentIO.encode(source,format:ext == "psd" ? .psd:.psb),response=try await h.request(service,path:"/v1/documents/\(id)/file.\(ext)")
          XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(response.1,expected)
          let read=try PSDCodec.read(response.1);XCTAssertNotNil(read.layers[0].smartObject?.linkedSource);XCTAssertTrue(read.layers[0].smartObject?.data.isEmpty==true)
        }
        XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      }
    }
  }
  @MainActor func testLocalSaveAsAndDownloadUseSameLinkedPreviewSerializer()async throws {
    let h=AutomationTests(),folder=try DocumentPersistenceTests().directory();defer{try? FileManager.default.removeItem(at:folder)}
    try await h.withService(pressedMouseButtons:{0}) {service,doc in
      let source=try self.fixture(.f32);doc.store.session=EditorSession(document:source);service.setDocumentTransfersEnabled(true);service.setDocumentSavesEnabled(true);service.setSaveDirectory(folder);try service.share(doc)
      let id=try XCTUnwrap(service.shares.first?.id)
      XCTAssertNil(DocumentIO.persistenceIssue(source,format:.psd));XCTAssertNil(DocumentIO.persistenceIssue(source,format:.psb))
      var unsupported=source;var mask=MaskProperties();mask.feather=1;unsupported.layers[0].maskProperties=mask
      XCTAssertNotNil(DocumentIO.persistenceIssue(unsupported,format:.psd))
      for ext in ["psd","psb"] {
        let status=try await h.edit(service,doc,"document.saveAs",["name":"OwnedLinked","format":ext,"replace":false]);XCTAssertEqual(status,200)
        let response=try await h.request(service,path:"/v1/documents/\(id)/file.\(ext)")
        XCTAssertEqual(response.0.statusCode,200);XCTAssertEqual(try Data(contentsOf:folder.appendingPathComponent("OwnedLinked.\(ext)")),response.1)
      }
      XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testTransferPermissionAndBadExportOptionsDoNotChangeSource()async throws {
    let h=AutomationTests();try await h.withService(pressedMouseButtons:{0}) {service,doc in
      let source=try self.fixture();doc.store.session=EditorSession(document:source);try service.share(doc);let id=try XCTUnwrap(service.shares.first?.id)
      let denied=try await h.request(service,path:"/v1/documents/\(id)/file.psd");XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let bad=try await h.request(service,path:"/v1/documents/\(id)/file.psb",headers:["X-Photato-Export-Options":"invalid"]);XCTAssertEqual(bad.0.statusCode,400)
      XCTAssertEqual(doc.store.document,source);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let preview=try XCTUnwrap(LinkedArtworkAPI.capabilities["previewExport"] as? [String:Any]);XCTAssertEqual(preview["formats"] as? [String],["psd","psb"])
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount);XCTAssertEqual(ActionLibraryFile.maximumVersion,49)
    }
  }
  @MainActor func testBothResourceJobInterfacesPreserveUnresolvedLinkedCacheOutput()async throws {
    let transport=AutomationActionJobsTests.Transport(),jobs=AutomationActionJobsTests()
    let encoded=try PSDCodec.writeRasterLayers(fixture(.f32));await transport.set(encoded)
    let input=try PSDCodec.read(encoded),expected=try Renderer.composite(input).rgbaData(depth:.f32,colorEncoding:.linearRGB)
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) {service,shared in
      service.setResourceJobsEnabled(true);let original=shared.store.document
      let payload:[String:Any]=["image":["source":["url":"https://example.test/linked.psd"]],"options":["actions":[["source":["content":"[{\"_obj\":\"select\",\"_target\":[{\"_ref\":\"channel\",\"_enum\":\"channel\",\"_value\":\"RGB\"}]}]","contentType":"application/json"]]]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        let output=try await jobs.output(service,submit:route,payload:payload),read=try PSDCodec.read(output.2)
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.f32,colorEncoding:.linearRGB),expected)
        XCTAssertNil(read.layers[0].smartObject?.linkedSource?.authorizationID);XCTAssertTrue(read.layers[0].smartObject?.data.isEmpty==true)
      }
      XCTAssertEqual(shared.store.document,original);XCTAssertTrue(shared.store.session.undoStack.isEmpty)
    }
  }
}
