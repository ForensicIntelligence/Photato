import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class PDFImportWorkflowTests: XCTestCase {
  var fixture: URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/pdf/owned-boxes.pdf")}
  func options() -> PDFImportSettings {var s = PDFImportSettings();s.pages = [1,2];s.crop = .media;s.resolution = 72;s.antialias = false;return s}
  func header(_ options: PDFImportSettings) throws -> String {String(decoding:try JSONEncoder().encode(options),as:UTF8.self)}
  func object(_ data: Data) throws -> [String:Any] {try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])}
  @MainActor func cleanup(_ controller: CraftDocumentController,except: CraftNSDocument? = nil) {
    controller.documentOpening.pdfWorkspace?.cancel();controller.documentOpening.pdfPresenter = nil
    for document in controller.documents.compactMap({$0 as? CraftNSDocument}) where document !== except {
      document.store.renderTask?.cancel();document.close();controller.removeDocument(document)
    }
  }
  @MainActor func testStrictSettingsDiscoveryAndPDFOpenTypes() throws {
    XCTAssertEqual(DocumentOpenFormat.detect(fixture),.pdf);XCTAssertEqual(DocumentOpenFormat.detect(try Data(contentsOf:fixture)),.pdf)
    XCTAssertTrue(DocumentIO.readableTypes.contains("com.adobe.pdf"));XCTAssertTrue(DocumentIO.readableContentTypes.contains(.pdf))
    XCTAssertThrowsError(try DocumentIO.read(fixture),"Low-level reads must not silently choose the first page")
    XCTAssertEqual(try PDFImportAPI.options("{}"),PDFImportSettings())
    for input in ["[]","{\"unknown\":true}","{\"pages\":[1,1]}","{\"pages\":[0]}","{\"pages\":[1.5]}","{\"width\":1.5}","{\"resolution\":0}","{\"mode\":\"cmyk\",\"depth\":\"32 bit\"}"] {XCTAssertThrowsError(try PDFImportAPI.options(input),input)}
    XCTAssertNil(try PDFImportAPI.options("{\"width\":null}").width)
    XCTAssertThrowsError(try PDFImportAPI.password("%%%"));XCTAssertEqual(try PDFImportAPI.password(Data("pässword".utf8).base64EncodedString()),"pässword")
    for input in ["{}","[true]","[1,1]","[0]","[1.5]"] {XCTAssertThrowsError(try PDFImportAPI.thumbnailPages(input))}
    XCTAssertNotNil(AutomationService.capabilities["pdfImport"])
    XCTAssertNotNil(PDFImportAPI.capabilities["inspectionResultSchema"])
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:PDFImportAPI.importPath),64*1024*1024)
    XCTAssertEqual(AutomationRequest.maximumBodyBytes(method:"POST",path:PDFImportAPI.cancelPath),65_536)
  }
  func testPDFHeaderTextDoesNotOverrideKnownContainers() throws {
    var native = try CraftDocument(width:2,height:2,name:"Metadata %PDF-1.7")
    native.layers[0].name = "%PDF-1.7"
    let archive = try NativeArchive.encode(native)
    XCTAssertEqual(DocumentOpenFormat.detect(archive),.native)
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,UTType.png.identifier as CFString,1,nil))
    let image = try RasterIO.displayImage(Surface(width:2,height:2,fill:.white))
    CGImageDestinationAddImage(destination,image,[kCGImagePropertyPNGDictionary:[kCGImagePropertyPNGDescription:"Metadata %PDF-1.7"]] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    XCTAssertTrue(PDFImport.recognizes(bytes as Data),"Fixture must contain a PDF-like header within its first1024bytes")
    XCTAssertEqual(DocumentOpenFormat.detect(bytes as Data),.png)
    let directory = try DocumentPersistenceTests().directory();defer {try? FileManager.default.removeItem(at:directory)}
    let url = directory.appendingPathComponent("misleading.pdf");try (bytes as Data).write(to:url)
    XCTAssertEqual(DocumentOpenFormat.detect(url),.png);XCTAssertEqual(try PreparedLocalDocument.read(url,format:.png).model.width,2)
    let prefixed = Data("Producer preamble\n".utf8)+(try Data(contentsOf:fixture))
    XCTAssertEqual(DocumentOpenFormat.detect(prefixed),.pdf);try prefixed.write(to:url);XCTAssertEqual(DocumentOpenFormat.detect(url),.pdf)
  }
  @MainActor func testNativeWorkspaceSelectionThumbnailsAndControls() async throws {
    _ = NSApplication.shared
    let source = try PreparedPDFSource.read(fixture),model = PDFImportWorkspace(source:source)
    model.inspect();await model.loadTask?.value;XCTAssertNil(model.error);XCTAssertEqual(model.info?.pages.count,3)
    model.select(1,extend:false,toggle:false);model.select(3,extend:true,toggle:false);XCTAssertEqual(model.selected,[1,2,3])
    model.select(3,extend:false,toggle:true);XCTAssertEqual(model.selected,[1,2])
    for page in [1,2,3] {model.showThumbnail(page)};await model.previewTask?.value
    XCTAssertEqual(model.thumbnails.count,3)
    XCTAssertEqual(model.thumbnails[2],try PDFImport.thumbnail(source.data,page:2))
    model.widthText = "not a width";model.run();XCTAssertNotNil(model.error);XCTAssertFalse(model.busy)
    model.widthText = "";model.error = nil;model.settings = options()
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_PDF_OUTPUT"] {
      let root = URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
      let host = NSHostingView(rootView:PDFImportView(model:model).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.light))
      let window = NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:620),styleMask:[.titled],backing:.buffered,defer:false)
      window.isReleasedWhenClosed = false;window.appearance = NSAppearance(named:.aqua);window.contentView = host
      host.frame = NSRect(x:0,y:0,width:840,height:620);host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(100));host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
      try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:root.appendingPathComponent("pdf-import-controls.png"));window.close()
    }
    var created: [CraftDocument] = []
    model.completion = {if case .success(let models) = $0 {created = models}}
    model.run();await model.task?.value
    XCTAssertNil(model.error);XCTAssertEqual(created.count,2);XCTAssertTrue(model.finished);XCTAssertEqual(model.password,"")
    XCTAssertEqual(try Data(contentsOf:fixture),source.data)
  }
  @MainActor func testNativeFileOpenPublishesSelectedPagesWithoutSourceAssociation() async throws {
    let controller = DocumentOpeningTests().controller();defer {cleanup(controller)}
    let original = try DocumentClosingTests().document(controller,dirty:true),before = original.store.document
    let settings = options()
    controller.documentOpening.pdfPresenter = {model in Task {@MainActor in
      await model.loadTask?.value;model.settings = settings;model.selected = [1,2];model.name = "Opened PDF";model.run()
    }}
    var calls = 0,opened: NSDocument?,failure: Error?
    try controller.documentOpening.begin([fixture],format:.pdf,display:false,completion:{doc,already,error in calls += 1;opened = doc;failure = error;XCTAssertFalse(already)})
    await controller.documentOpening.waitUntilIdle()
    XCTAssertNil(failure);XCTAssertEqual(calls,1);XCTAssertNotNil(opened);XCTAssertEqual(controller.documents.count,3)
    XCTAssertEqual(controller.documentOpening.state?.opened,1);XCTAssertNil(controller.documentOpening.pdfWorkspace)
    let expected = try PDFImport.pages(Data(contentsOf:fixture),name:"Opened PDF",settings:settings)
    let docs = controller.documents.compactMap{$0 as? CraftNSDocument}.filter{$0 !== original}
    for (doc,expected) in zip(docs,expected) {
      XCTAssertEqual(doc.store.document.layers.map(\.content),expected.layers.map(\.content));XCTAssertNil(doc.fileURL);XCTAssertNil(doc.revertSourceURL)
      XCTAssertTrue(doc.isDocumentEdited);XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
    XCTAssertEqual(original.store.document,before);XCTAssertNil(controller.document(for:fixture))
  }
  @MainActor func testNativeCancellationAndPublicationValidationPublishNothing() async throws {
    for cancel in [true,false] {
      let controller = DocumentOpeningTests().controller();defer {cleanup(controller)}
      let original = try DocumentClosingTests().document(controller,dirty:true),before = original.store.document
      controller.documentOpening.pdfPresenter = {model in Task {@MainActor in
        await model.loadTask?.value
        if cancel {model.cancel()} else {model.settings.resolution = 72;model.run()}
      }}
      var validations = 0,calls = 0,error: Error?
      try controller.documentOpening.begin([fixture],display:false,validate:{validations += 1;if !cancel && validations > 2 {throw CraftError.invalid("Permission changed")}},completion:{_,_,failure in calls += 1;error = failure})
      await controller.documentOpening.waitUntilIdle()
      XCTAssertEqual(calls,1);XCTAssertNotNil(error);XCTAssertEqual(controller.documents.count,1);XCTAssertEqual(original.store.document,before)
      XCTAssertNil(controller.documentOpening.pdfWorkspace)
    }
  }
  @MainActor func testEncryptedWorkspaceRequiresPasswordAndClearsIt() async throws {
    let source = try PreparedPDFSource.read(fixture.deletingLastPathComponent().appendingPathComponent("owned-password.pdf")),model = PDFImportWorkspace(source:source)
    model.inspect();await model.loadTask?.value;XCTAssertNil(model.info);XCTAssertNotNil(model.error)
    model.password = "photato-fixture";model.inspect();await model.loadTask?.value;XCTAssertNotNil(model.info);XCTAssertNil(model.error)
    model.cancel();XCTAssertEqual(model.password,"");XCTAssertTrue(model.finished)
  }
  @MainActor func testHTTPInspectionAndMultiPageImportMatchNative() async throws {
    let files = DocumentIOWorkflowTests(),bytes = try Data(contentsOf:fixture),settings = options()
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,original in
      defer {cleanup(service.controller,except:original)}
      let before = original.store.document
      let denied = try await files.request(service,path:PDFImportAPI.inspectPath,data:bytes,type:"application/pdf");XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let inspection = try await files.request(service,path:PDFImportAPI.inspectPath,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Thumbnails":"[1,2]"])
      XCTAssertEqual(inspection.0.statusCode,200,String(decoding:inspection.1,as:UTF8.self))
      let info = try object(inspection.1);XCTAssertEqual((info["pages"] as? [Any])?.count,3);XCTAssertEqual(service.controller.documents.count,1)
      let previews = try XCTUnwrap(info["thumbnails"] as? [String:[String:String]])
      XCTAssertEqual(Data(base64Encoded:try XCTUnwrap(previews["2"]?["data"])),try PDFImport.thumbnail(bytes,page:2))
      let response = try await files.request(service,path:PDFImportAPI.importPath,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Options":try header(settings),"X-Photato-Name":"API PDF"])
      XCTAssertEqual(response.0.statusCode,201,String(decoding:response.1,as:UTF8.self));XCTAssertEqual(try object(response.1)["count"] as? Int,2)
      let expected = try PDFImport.pages(bytes,name:"API PDF",settings:settings)
      XCTAssertEqual(service.shares.count,2)
      for (share,model) in zip(service.shares,expected) {
        let doc = try XCTUnwrap(share.document)
        XCTAssertEqual(doc.store.document.layers.map(\.content),model.layers.map(\.content));XCTAssertEqual(doc.store.document.name,model.name)
        XCTAssertEqual(try RasterIO.encoded(doc.store.document),try RasterIO.encoded(model));XCTAssertTrue(doc.isDocumentEdited);XCTAssertNil(doc.revertSourceURL)
      }
      XCTAssertEqual(original.store.document,before);XCTAssertFalse(service.documentTransferBusy);XCTAssertNil(service.pdfImportTask)
    }
  }
  @MainActor func testHTTPInvalidInputsAndCapacityPreserveExistingDocuments() async throws {
    let files = DocumentIOWorkflowTests(),bytes = try Data(contentsOf:fixture)
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,original in
      defer {cleanup(service.controller,except:original)};service.setDocumentTransfersEnabled(true)
      for (path,type,headers,expected) in [
        ("/v1/documents/import","application/octet-stream",["X-Photato-Open-Format":"pdf"],422),
        (PDFImportAPI.importPath,"image/png",[String:String](),415),
        (PDFImportAPI.importPath,"application/pdf",["X-Photato-PDF-Options":"{\"unknown\":true}"],400),
        (PDFImportAPI.inspectPath,"application/pdf",["X-Photato-PDF-Options":"{}"],400),
        (PDFImportAPI.importPath,"application/pdf",["X-Photato-PDF-Options":"{\"pages\":[4]}"],422),
        (PDFImportAPI.importPath,"application/pdf",["X-Photato-PDF-Options":"{\"pages\":[1,2,3,4,5,6,7,8,9]}"],429)] {
        let response = try await files.request(service,path:path,data:bytes,type:type,headers:headers);XCTAssertEqual(response.0.statusCode,expected,String(decoding:response.1,as:UTF8.self))
      }
      XCTAssertEqual(service.controller.documents.count,1);XCTAssertTrue(service.shares.isEmpty)
      let transfer = try XCTUnwrap(AutomationService.documentTransferCapabilities["import"] as? [String:Any])
      let header = try XCTUnwrap(transfer["formatHeader"] as? [String:Any]),schema = try XCTUnwrap(header["schema"] as? [String:Any])
      XCTAssertFalse((schema["enum"] as? [String] ?? []).contains("pdf"))
    }
  }
  @MainActor func testHTTPActiveCancellationRevocationAndBusyGuardPublishNothing() async throws {
    let files = DocumentIOWorkflowTests(),bytes = try Data(contentsOf:fixture),settings = options()
    for revoke in [false,true] {
      let gate = OpeningGate();defer {gate.release()}
      try await AutomationTests().withService(pressedMouseButtons:{0}) {service,original in
        defer {cleanup(service.controller,except:original)};service.setDocumentTransfersEnabled(true)
        service.pdfPageDecoder = {data,name,settings,password in gate.wait();try Task.checkCancellation();return try PDFImport.pages(data,name:name,settings:settings,password:password)}
        let operation = Task {try await files.request(service,path:PDFImportAPI.importPath,data:bytes,type:"application/pdf",headers:["X-Photato-PDF-Options":try header(settings)])}
        try await DocumentOpeningTests().wait(gate)
        let id = try XCTUnwrap(service.pdfImportOperationID)
        let busy = try await files.request(service,path:PDFImportAPI.inspectPath,data:bytes,type:"application/pdf");XCTAssertEqual(busy.0.statusCode,409)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let reply = try await files.request(service,path:PDFImportAPI.cancelPath,data:JSONSerialization.data(withJSONObject:["operationID":id.uuidString]),type:"application/json");XCTAssertEqual(reply.0.statusCode,200)
        }
        gate.release();let response = try await operation.value;XCTAssertEqual(response.0.statusCode,409)
        XCTAssertEqual(service.controller.documents.count,1);XCTAssertTrue(service.shares.isEmpty);XCTAssertFalse(service.documentTransferBusy);XCTAssertNil(service.pdfImportTask)
      }
    }
  }
}
