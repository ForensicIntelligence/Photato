import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private actor PDFSmartObjectTransport: AdobeResourceTransport {
  let files: [URL:Data]
  init(_ files: [URL:Data]) {self.files = files}
  func fetch(_ url: URL) async throws -> Data {
    guard let data = files[url] else {throw AdobeAPIError.invalid("Missing owned resource.")};return data
  }
  func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws {throw AdobeAPIError.unsupported("No uploads.")}
}

final class PDFSmartObjectWorkflowTests: XCTestCase {
  func fixture() throws -> Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("PhotoCraftImagingTests/Fixtures/pdf/owned-boxes.pdf"))
  }
  func model() throws -> CraftDocument {
    var d = try CraftDocument(width:432,height:324)
    var settings = PDFImportSettings();settings.resolution = 72;settings.crop = .media;settings.antialias = false
    var layer = try PDFSmartObjectIO.placed(fixture(),fileName:"Original.pdf",in:d,settings:settings,fit:false)
    layer.x = 0;layer.y = 0;layer.affine = .scale(3,3)
    d.layers = [layer];d.activeLayerID = layer.id;return d
  }
  @MainActor func testPDFStateSourceDownloadAndArchiveNegotiationOverHTTP() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,_ in
      let parent = CraftNSDocument(model:try self.model());service.controller.addDocument(parent)
      defer {parent.store.renderTask?.cancel();service.controller.removeDocument(parent)}
      try service.share(parent);service.setDocumentTransfersEnabled(true)
      let shared = try XCTUnwrap(service.shares.first?.id),layer = try XCTUnwrap(parent.store.activeLayer)
      let state = try XCTUnwrap(layer.smartObject).apiState
      let pdf = try XCTUnwrap(state["pdfSource"] as? [String:Any])
      XCTAssertEqual(pdf["page"] as? Int,1);XCTAssertEqual(pdf["crop"] as? String,"media")
      XCTAssertNotNil((SmartObject.apiLayerStateSchema["properties"] as? [String:Any])?["smartObject"])
      let original = try await helper.request(service,path:"/v1/documents/\(shared)/smart-objects/\(layer.id)/source")
      XCTAssertEqual(original.0.statusCode,200);XCTAssertEqual(original.1,try self.fixture())
      let denied = try await helper.request(service,path:"/v1/documents/\(shared)/file.photato",headers:["X-Photato-Archive-Version":"61"])
      XCTAssertEqual(denied.0.statusCode,422)
      let native = try await helper.request(service,path:"/v1/documents/\(shared)/file.photato",headers:["X-Photato-Archive-Version":"62"])
      XCTAssertEqual(native.0.statusCode,200);XCTAssertEqual(try NativeArchive.decode(native.1),parent.store.document)
      let indexed = try await helper.request(service,path:"/v1/documents/\(shared)/file.photato",headers:["X-Photato-Archive-Version":"63"])
      XCTAssertEqual(indexed.0.statusCode,200);XCTAssertEqual(try NativeArchive.decodePaged(indexed.1),parent.store.document)
      for version in ["64","65","75","76","77","78"] {
        let current=try await helper.request(service,path:"/v1/documents/\(shared)/file.photato",headers:["X-Photato-Archive-Version":version])
        XCTAssertEqual(current.0.statusCode,200)
        XCTAssertEqual(try NativeArchive.decodePaged(current.1),parent.store.document)
      }
      let unknown = try await helper.request(service,path:"/v1/documents/\(shared)/file.photato",headers:["X-Photato-Archive-Version":"999999"])
      XCTAssertEqual(unknown.0.statusCode,400)
    }
  }
  @MainActor func testNativeAndHTTPRasterizePreserveEnlargedOutputAndUndo() async throws {
    let helper = AutomationTests(),original = try model(),expected = try Renderer.composite(original).rgbaData(depth:.u8)
    let native = CraftNSDocument(model:original)
    defer {native.store.renderTask?.cancel()}
    native.store.rasterize();await native.store.geometryTask?.value
    XCTAssertNil(native.store.error);XCTAssertNil(native.store.activeLayer?.smartObject)
    XCTAssertEqual(try Renderer.composite(native.store.document).rgbaData(depth:.u8),expected)
    await native.store.undo();XCTAssertEqual(native.store.document,original)
    try await helper.withService(pressedMouseButtons:{0}) {service,_ in
      let parent = CraftNSDocument(model:original);service.controller.addDocument(parent)
      defer {parent.store.renderTask?.cancel();service.controller.removeDocument(parent)}
      try service.share(parent)
      let params:[String:Any] = ["layerID":original.layers[0].id.uuidString]
      let stale = try await helper.edit(service,parent,"layer.rasterize",params,revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(parent.store.document,original)
      let result = try await helper.edit(service,parent,"layer.rasterize",params)
      XCTAssertEqual(result,200);XCTAssertNil(parent.store.activeLayer?.smartObject)
      XCTAssertEqual(try Renderer.composite(parent.store.document).rgbaData(depth:.u8),expected)
      let undo = try await helper.edit(service,parent,"history.undo")
      XCTAssertEqual(undo,200);XCTAssertEqual(parent.store.document,original)
    }
  }
  @MainActor func upload(_ service: AutomationService,_ document: CraftNSDocument,
    options: [String:Any] = [:], revision: String? = nil) async throws -> (HTTPURLResponse,Data) {
    let id = try XCTUnwrap(service.shares.first(where:{$0.document === document})?.id)
    var request = URLRequest(url:URL(string:try XCTUnwrap(service.endpoint)+"/v1/documents/\(id)/smart-objects/pdf")!)
    request.httpMethod = "POST";request.httpBody = try fixture();request.timeoutInterval = 5
    request.setValue("Bearer "+(service.token ?? ""),forHTTPHeaderField:"Authorization")
    request.setValue("application/pdf",forHTTPHeaderField:"Content-Type")
    request.setValue(revision ?? service.revision(document.store),forHTTPHeaderField:"X-Photato-Revision")
    request.setValue(String(decoding:try JSONSerialization.data(withJSONObject:options),as:UTF8.self),forHTTPHeaderField:"X-Photato-PDF-Options")
    let (data,response) = try await URLSession.shared.data(for:request)
    return (try XCTUnwrap(response as? HTTPURLResponse),data)
  }
  @MainActor func testActualPDFPlacementReplacementInvalidAndStaleHTTP() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,parent in
      try service.share(parent);let original = parent.store.document
      let denied = try await self.upload(service,parent);XCTAssertEqual(denied.0.statusCode,403)
      service.setDocumentTransfersEnabled(true)
      let stale = try await self.upload(service,parent,revision:"stale");XCTAssertEqual(stale.0.statusCode,409)
      let invalid = try await self.upload(service,parent,options:["page":4]);XCTAssertEqual(invalid.0.statusCode,422)
      let unknown = try await self.upload(service,parent,options:["invented":true]);XCTAssertEqual(unknown.0.statusCode,400)
      XCTAssertEqual(parent.store.document,original)
      let result = try await self.upload(service,parent,options:["page":1,"crop":"media","resolution":72,"antialias":false])
      XCTAssertEqual(result.0.statusCode,200,String(decoding:result.1,as:UTF8.self))
      let layer = try XCTUnwrap(parent.store.activeLayer)
      XCTAssertEqual(layer.smartObject?.data,try self.fixture());XCTAssertEqual(layer.smartObject?.pdfSource?.page,1)
      let placed = parent.store.document
      let replaced = try await self.upload(service,parent,options:["page":2,"crop":"crop","layerID":layer.id.uuidString])
      XCTAssertEqual(replaced.0.statusCode,200,String(decoding:replaced.1,as:UTF8.self))
      XCTAssertEqual(parent.store.activeLayer?.smartObject?.pdfSource?.page,2)
      let undo = try await helper.edit(service,parent,"history.undo");XCTAssertEqual(undo,200)
      XCTAssertEqual(parent.store.document,placed)
      XCTAssertTrue(service.pdfSmartObjectOperations.isEmpty)
    }
  }
  @MainActor func testAdobePDFResourcesRetainSourceAndRespectAutoResize() async throws {
    let sourceURL = URL(string:"https://example.test/owned.pdf")!,inputURL = URL(string:"https://example.test/input.psd")!
    let data = try fixture(),original = try CraftDocument(width:432,height:324)
    let add: [String:Any] = ["name":"PDF","type":"smart_object_layer","operation":["type":"add","placement":["type":"top"]],
      "smartObject":["smartObjectFile":["source":["url":sourceURL.absoluteString]]],"transformMode":"fit"]
    var session = EditorSession(document:original)
    try AdobeSmartObjectEdit(add,path:"edit").apply(to:&session,resources:[sourceURL:data])
    let object = try XCTUnwrap(session.document.layers.last?.smartObject)
    XCTAssertEqual(object.data,data);XCTAssertEqual(object.pdfSource?.page,1)
    for resize in [false,true] {
      var target = EditorSession(document:try model())
      let prior = try XCTUnwrap(target.document.layers[0].smartObject)
      let edit: [String:Any] = ["name":target.document.layers[0].name,"type":"smart_object_layer","operation":["type":"edit"],
        "smartObject":["autoResize":resize,"smartObjectFile":["source":["url":sourceURL.absoluteString]]]]
      try AdobeSmartObjectEdit(edit,path:"edit").apply(to:&target,resources:[sourceURL:data])
      let updated = try XCTUnwrap(target.document.layers[0].smartObject)
      XCTAssertEqual(updated.data,data);XCTAssertNotNil(updated.pdfSource)
      XCTAssertEqual(updated.width,resize ? prior.width:90);XCTAssertEqual(updated.height,resize ? prior.height:66)
    }
    let expected = try RasterIO.encoded(session.document)
    let transport = PDFSmartObjectTransport([sourceURL:data,inputURL:try PSDCodec.writeRasterLayers(original)])
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport) {service,shared in
      service.setResourceJobsEnabled(true);let before = shared.store.document
      let payload: [String:Any] = ["image":["source":["url":inputURL.absoluteString]],"edits":["layers":[add]],
        "outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
      let result = try await AutomationActionJobsTests().output(service,submit:"/v2/create-composite",payload:payload,expectedMediaType:"image/png")
      let actual = try RasterIO.read(result.2,name:"API"),reference = try RasterIO.read(expected,name:"Native")
      XCTAssertEqual(try Renderer.composite(actual).rgbaData(depth:.u8),try Renderer.composite(reference).rgbaData(depth:.u8))
      XCTAssertEqual(shared.store.document,before)
    }
  }
  @MainActor func testPDFUploadBusyCancellationAndTransferRevocationAreAtomic() async throws {
    let helper = AutomationTests()
    for revoke in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}) {service,parent in
        try service.share(parent);service.setDocumentTransfersEnabled(true)
        service.pdfSmartObjectPreparation = {data,name,original,options in
          try await Task.sleep(for:.milliseconds(200))
          return try PDFSmartObjectAPI.prepare(data,name,original,options)
        }
        let original = parent.store.document,share = try XCTUnwrap(service.shares.first?.id)
        let pending = Task {try await self.upload(service,parent)}
        for _ in 0..<100 where !parent.store.geometryBusy {try await Task.sleep(for:.milliseconds(5))}
        XCTAssertTrue(parent.store.geometryBusy)
        let operation = try XCTUnwrap(service.pdfSmartObjectOperations[share])
        let busy = try await self.upload(service,parent);XCTAssertEqual(busy.0.statusCode,409)
        if revoke {service.setDocumentTransfersEnabled(false)} else {
          let wrong = try await helper.request(service,path:"/v1/documents/\(share)/smart-objects/pdf/cancel",body:["operationID":UUID().uuidString])
          XCTAssertEqual(wrong.0.statusCode,409)
          let cancelled = try await helper.request(service,path:"/v1/documents/\(share)/smart-objects/pdf/cancel",body:["operationID":operation.uuidString])
          XCTAssertEqual(cancelled.0.statusCode,200)
        }
        let result = try await pending.value
        XCTAssertEqual(result.0.statusCode,409,String(decoding:result.1,as:UTF8.self))
        XCTAssertEqual(parent.store.document,original);XCTAssertTrue(parent.store.session.undoStack.isEmpty)
        XCTAssertTrue(service.pdfSmartObjectOperations.isEmpty);XCTAssertFalse(parent.store.geometryBusy)
      }
    }
  }
}
