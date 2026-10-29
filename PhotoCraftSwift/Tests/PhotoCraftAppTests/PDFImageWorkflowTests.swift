import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PDFImageWorkflowTests: XCTestCase {
  var fixture: URL {PDFImportWorkflowTests().fixture.deletingLastPathComponent().appendingPathComponent("owned-images.pdf")}
  func settings() -> PDFImageImportSettings {var s = PDFImageImportSettings();s.images = [1,8];return s}
  func header(_ s: PDFImageImportSettings) throws -> String {String(decoding:try JSONEncoder().encode(s),as:UTF8.self)}
  @MainActor func testStrictImageSettingsAndDiscoverySchemas() throws {
    XCTAssertEqual(try PDFImageImportAPI.options("{}"),PDFImageImportSettings())
    for invalid in ["[]","{\"pages\":[1]}","{\"images\":[]}","{\"images\":[1,1]}","{\"images\":[1.5]}","{\"width\":120}","{\"resolution\":0}","{\"mode\":\"cmyk\",\"depth\":\"32 bit\"}"] {XCTAssertThrowsError(try PDFImageImportAPI.options(invalid),invalid)}
    XCTAssertNotNil(PDFImportAPI.capabilities["images"])
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:PDFImageImportAPI.importPath),64*1024*1024)
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:PDFImageImportAPI.inspectPath),64*1024*1024)
  }
  @MainActor func testNativeImagesSelectionThumbnailsAndControls() async throws {
    _ = NSApplication.shared
    let model = PDFImportWorkspace(source:try PreparedPDFSource.read(fixture));model.inspect();await model.loadTask?.value
    XCTAssertEqual(model.content,.pages);model.showThumbnail(1)
    model.changeContent(.images);await model.loadTask?.value
    XCTAssertNil(model.error);XCTAssertEqual(model.items,Array(1...8));XCTAssertEqual(model.selected,[1])
    model.showThumbnail(1);await model.previewTask?.value
    XCTAssertEqual(model.thumbnails[1],try PDFImages.thumbnail(Data(contentsOf:fixture),image:1))
    model.select(2,extend:true,toggle:false);XCTAssertEqual(model.selected,[1,2]);model.select(8,extend:false,toggle:true);XCTAssertEqual(model.selected,[1,2,8])
    model.imageSettings.resolution = 300;model.widthText = "invalid page width";XCTAssertEqual(try model.imageOptions().resolution,300)
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_PDF_OUTPUT"] {
      let root = URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
      for id in model.items {model.showThumbnail(id)};await model.previewTask?.value
      let host = NSHostingView(rootView:PDFImportView(model:model).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light))
      let window = NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.aqua);window.contentView = host
      host.frame = NSRect(x:0,y:0,width:840,height:620);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(100));host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:root.appendingPathComponent("pdf-image-controls.png"));window.close()
    }
    var created:[CraftDocument] = [];model.completion = {if case .success(let docs) = $0 {created = docs}}
    model.run();await model.task?.value;XCTAssertNil(model.error);XCTAssertEqual(created.count,3);XCTAssertEqual(created.map(\.width),[2,2,1]);XCTAssertEqual(created.map(\.resolution),[300,300,300])
  }
  @MainActor func testFileOpenImagesPublishesAtomicallyWithoutSourceAssociation() async throws {
    let controller = DocumentOpeningTests().controller();defer {PDFImportWorkflowTests().cleanup(controller)}
    let original = try DocumentClosingTests().document(controller,dirty:true),before = original.store.document
    controller.documentOpening.pdfPresenter = {model in Task {@MainActor in
      await model.loadTask?.value;model.changeContent(.images);await model.loadTask?.value;model.selected = [1,8];model.run()
    }}
    var failure:Error?;try controller.documentOpening.begin([fixture],display:false,completion:{_,_,error in failure = error});await controller.documentOpening.waitUntilIdle()
    XCTAssertNil(failure);let docs = controller.documents.compactMap{$0 as? CraftNSDocument}.filter{$0 !== original}
    XCTAssertEqual(docs.count,2);XCTAssertEqual(docs.map{$0.store.document.width},[2,1]);XCTAssertEqual(original.store.document,before)
    for doc in docs {XCTAssertTrue(doc.isDocumentEdited);XCTAssertNil(doc.fileURL);XCTAssertNil(doc.revertSourceURL)}
  }
  @MainActor func testHTTPImageInspectionImportAndNativePixelsMatch() async throws {
    let bytes = try Data(contentsOf:fixture),options = settings(),files = DocumentIOWorkflowTests()
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,original in
      defer {PDFImportWorkflowTests().cleanup(service.controller,except:original)}
      let denied = try await files.request(service,path:PDFImageImportAPI.inspectPath,data:bytes,type:"application/pdf");XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true);let before = original.store.document
      let response = try await files.request(service,path:PDFImageImportAPI.inspectPath,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Thumbnails":"[1,8]"])
      XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self));let info = try PDFImportWorkflowTests().object(response.1)
      XCTAssertEqual((info["images"] as? [Any])?.count,8);XCTAssertEqual(service.controller.documents.count,1)
      let thumbnails = try XCTUnwrap(info["thumbnails"] as? [String:[String:String]])
      XCTAssertEqual(Data(base64Encoded:try XCTUnwrap(thumbnails["8"]?["data"])),try PDFImages.thumbnail(bytes,image:8))
      let imported = try await files.request(service,path:PDFImageImportAPI.importPath,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Options":try header(options),"X-Photato-Name":"Images"])
      XCTAssertEqual(imported.0.statusCode,201,String(decoding:imported.1,as:UTF8.self));XCTAssertEqual(service.shares.count,2)
      let expected = try PDFImages.documents(bytes,name:"Images",settings:options)
      for (share,document) in zip(service.shares,expected) {let native = try XCTUnwrap(share.document);XCTAssertEqual(try RasterIO.encoded(native.store.document),try RasterIO.encoded(document));XCTAssertEqual(native.store.document.name,document.name);XCTAssertNil(native.revertSourceURL)}
      XCTAssertEqual(original.store.document,before);XCTAssertEqual(try Data(contentsOf:fixture),bytes)
    }
  }
  @MainActor func testHTTPInvalidImageSettingsAndNoImagesHaveNoPublication() async throws {
    let bytes = try Data(contentsOf:fixture),files = DocumentIOWorkflowTests()
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,original in
      defer {PDFImportWorkflowTests().cleanup(service.controller,except:original)};service.setDocumentTransfersEnabled(true)
      for (path,header,status) in [(PDFImageImportAPI.importPath,"{\"pages\":[1]}",400),(PDFImportAPI.importPath,"{\"images\":[1]}",400),(PDFImageImportAPI.inspectPath,"{}",400),(PDFImageImportAPI.importPath,"{\"images\":[9]}",422),(PDFImageImportAPI.importPath,"{\"images\":[1,2,3,4,5,6,7,8,9]}",429)] {
        let response = try await files.request(service,path:path,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Options":header]);XCTAssertEqual(response.0.statusCode,status,String(decoding:response.1,as:UTF8.self))
      }
      let noImages = try Data(contentsOf:PDFImportWorkflowTests().fixture)
      let inspected = try await files.request(service,path:PDFImageImportAPI.inspectPath,data:noImages,type:"application/pdf");XCTAssertEqual(inspected.0.statusCode,200)
      XCTAssertEqual((try PDFImportWorkflowTests().object(inspected.1)["images"] as? [Any])?.count,0)
      let rejected = try await files.request(service,path:PDFImageImportAPI.importPath,data:noImages,type:"application/pdf");XCTAssertEqual(rejected.0.statusCode,422)
      XCTAssertEqual(service.controller.documents.count,1);XCTAssertTrue(service.shares.isEmpty)
    }
  }
  @MainActor func testHTTPImageCancellationRevocationAndBusyPreserveDocuments() async throws {
    let bytes = try Data(contentsOf:fixture),files = DocumentIOWorkflowTests(),options = settings()
    for revoke in [false,true] {
      let gate = OpeningGate();defer {gate.release()}
      try await AutomationTests().withService(pressedMouseButtons:{0}) {service,original in
        defer {PDFImportWorkflowTests().cleanup(service.controller,except:original)};service.setDocumentTransfersEnabled(true)
        service.pdfImageDecoder = {data,name,settings,password in gate.wait();try Task.checkCancellation();return try PDFImages.documents(data,name:name,settings:settings,password:password)}
        let operation = Task {try await files.request(service,path:PDFImageImportAPI.importPath,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Options":try header(options)])}
        try await DocumentOpeningTests().wait(gate);let id = try XCTUnwrap(service.pdfImportOperationID)
        let busy = try await files.request(service,path:PDFImageImportAPI.inspectPath,data:bytes,type:"application/pdf");XCTAssertEqual(busy.0.statusCode,409)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let cancelled = try await files.request(service,path:PDFImportAPI.cancelPath,data:JSONSerialization.data(withJSONObject:["operationID":id.uuidString]),type:"application/json");XCTAssertEqual(cancelled.0.statusCode,200)
        }
        gate.release();let response = try await operation.value;XCTAssertEqual(response.0.statusCode,409)
        XCTAssertEqual(service.controller.documents.count,1);XCTAssertTrue(service.shares.isEmpty);XCTAssertFalse(service.documentTransferBusy)
      }
    }
  }
}
