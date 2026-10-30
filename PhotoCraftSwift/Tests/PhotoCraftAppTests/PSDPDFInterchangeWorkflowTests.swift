import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor PSDPDFTransport: AdobeResourceTransport {
  let files:[URL:Data]
  init(_ files:[URL:Data]) {self.files = files}
  func fetch(_ url: URL) async throws -> Data {guard let d = files[url] else {throw AdobeAPIError.invalid("Missing owned resource")};return d}
  func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws {throw AdobeAPIError.unsupported("No external uploads")}
}

final class PSDPDFInterchangeWorkflowTests: XCTestCase {
  func fixture(_ name: String) throws -> Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/"+name))
  }
  func model() throws -> CraftDocument {
    var d = try CraftDocument(width:144,height:108)
    var settings = PDFImportSettings();settings.pages = [2];settings.crop = .media;settings.resolution = 72
    let layer = try PDFSmartObjectIO.placed(fixture("pdf/owned-boxes.pdf"),fileName:"Owned.pdf",in:d,settings:settings,fit:false)
    d.layers = [layer];d.activeLayerID = layer.id;return d
  }
  @MainActor func testNativePersistenceAndActualHTTPPSDBothFormatsAreEquivalentAndNonmutating() async throws {
    let files = DocumentIOWorkflowTests(),helper = AutomationTests(),model = try model()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      document.store.session = EditorSession(document:model);try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id),before = document.store.document
      let forbidden = try await files.request(service,path:"/v1/documents/\(id)/file.psd");XCTAssertEqual(forbidden.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
      for format in [DocumentIO.Format.psd,.psb] {
        let suffix = format == .psd ? "psd":"psb"
        let result = try await files.request(service,path:"/v1/documents/\(id)/file.\(suffix)")
        XCTAssertEqual(result.0.statusCode,200,String(decoding:result.1.prefix(100),as:UTF8.self))
        let url = folder.appendingPathComponent("Owned.\(suffix)");try await document.copyDocument(to:url,format:format)
        XCTAssertEqual(try Data(contentsOf:url),result.1)
        let reopened = try PSDCodec.read(result.1)
        XCTAssertEqual(reopened.layers[0].smartObject,model.layers[0].smartObject)
        XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth:.u8),try Renderer.composite(model).rgbaData(depth:.u8))
      }
      XCTAssertEqual(document.store.document,before);XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let capabilities = try XCTUnwrap(SmartObject.apiCapabilities["pdfPSDInterchange"] as? [String:Any])
      XCTAssertEqual(capabilities["write"] as? Bool,true);XCTAssertEqual(capabilities["sourceBytesPreserved"] as? Bool,true)
      var invalid = before;invalid.layers[0].smartObject?.pdfSource?.antialias = false;document.store.session = EditorSession(document:invalid)
      let rejected = try await files.request(service,path:"/v1/documents/\(id)/file.psd");XCTAssertEqual(rejected.0.statusCode,422)
      XCTAssertEqual(document.store.document,invalid)
    }
  }
  @MainActor func testPhotoshopFixtureImportAndNativeOpenRetainSameSourceAndState() async throws {
    let bytes = try fixture("pdf-psd/photoshop-page2-media.psd"),files = DocumentIOWorkflowTests()
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,_ in
      service.setDocumentTransfersEnabled(true)
      defer {for document in service.controller.documents.compactMap({$0 as? CraftNSDocument}) {document.store.renderTask?.cancel();service.controller.removeDocument(document)}}
      let uploaded = try await files.request(service,path:"/v1/documents/import",data:bytes,type:"image/vnd.adobe.photoshop")
      XCTAssertEqual(uploaded.0.statusCode,201,String(decoding:uploaded.1,as:UTF8.self))
      let imported = try XCTUnwrap(service.shares.first?.document)
      let native = CraftNSDocument();defer {native.store.renderTask?.cancel()}
      try native.read(from:bytes,ofType:DocumentIO.Format.psd.typeIdentifier)
      XCTAssertEqual(native.store.document.layers.compactMap(\.smartObject),imported.store.document.layers.compactMap(\.smartObject))
      XCTAssertEqual(native.store.document.layers.map(\.content),imported.store.document.layers.map(\.content))
      XCTAssertEqual(native.store.document.layers.map(\.coordinateTransform),imported.store.document.layers.map(\.coordinateTransform))
      let layer = try XCTUnwrap(imported.store.document.layers.first(where:{$0.smartObject != nil})),share = try XCTUnwrap(service.shares.first?.id)
      let source = try await AutomationTests().request(service,path:"/v1/documents/\(share)/smart-objects/\(layer.id)/source")
      XCTAssertEqual(source.1,try self.fixture("pdf-psd/photoshop-page2-source.pdf"))
      XCTAssertEqual((layer.smartObject?.apiState["pdfSource"] as? [String:Any])?["page"] as? Int,1)
    }
  }
  @MainActor func testAdobeResourceJobPreservesEditablePDFInPSDOutput() async throws {
    let input = URL(string:"https://owned.test/input.psd")!,source = URL(string:"https://owned.test/pages.pdf")!
    let original = try CraftDocument(width:144,height:108),pdf = try fixture("pdf/owned-boxes.pdf")
    let transport = PSDPDFTransport([input:try PSDCodec.writeRasterLayers(original),source:pdf])
    let add:[String:Any] = ["name":"PDF","type":"smart_object_layer","operation":["type":"add","placement":["type":"top"]],"smartObject":["smartObjectFile":["source":["url":source.absoluteString]]],"transformMode":"fit"]
    var session = EditorSession(document:original);try AdobeSmartObjectEdit(add,path:"owned").apply(to:&session,resources:[source:pdf])
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) {service,document in
      service.setResourceJobsEnabled(true);let before = document.store.document
      let payload:[String:Any] = ["image":["source":["url":input.absoluteString]],"edits":["layers":[add]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
      let result = try await AutomationActionJobsTests().output(service,submit:"/v2/create-composite",payload:payload)
      let read = try PSDCodec.read(result.2),layer = try XCTUnwrap(read.layers.first(where:{$0.smartObject != nil}))
      XCTAssertEqual(layer.smartObject?.data,pdf);XCTAssertNotNil(layer.smartObject?.pdfSource)
      XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),try Renderer.composite(session.document).rgbaData(depth:.u8))
      XCTAssertEqual(document.store.document,before)
    }
  }
}
