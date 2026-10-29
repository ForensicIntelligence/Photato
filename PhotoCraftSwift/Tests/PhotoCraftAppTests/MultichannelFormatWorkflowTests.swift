import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class MultichannelFormatWorkflowTests: XCTestCase {
  func source(_ depth: PixelDepth) throws -> CraftDocument {
    var d = try InkChannelWorkflowTests().source(depth)
    d.alphaChannels = [.init(name: "Coverage", pixels: try Surface(width: d.width, height: d.height, depth: depth, fill: Pixel(0.4,0.4,0.4)))]
    return d
  }
  func assertPreserved(_ read: CraftDocument, _ source: CraftDocument, file: StaticString = #filePath, line: UInt = #line) throws {
    let a = try read.multichannelRaster(), b = try source.multichannelRaster()
    XCTAssertEqual(a.plates.map(\.samples), b.plates.map(\.samples),file:file,line:line)
    XCTAssertEqual(a.plates.map(\.name), b.plates.map(\.name),file:file,line:line)
    XCTAssertEqual(a.plates.map(\.solidity), b.plates.map(\.solidity),file:file,line:line)
    XCTAssertEqual(try read.alphaChannels?.map { try $0.pixels.rgbaData(depth: read.depth) },try source.alphaChannels?.map { try $0.pixels.rgbaData(depth: source.depth) },file:file,line:line)
    XCTAssertEqual(read.colorMode,.multichannel); XCTAssertTrue(read.layers.isEmpty)
  }
  @MainActor func testNativeSaveAccessoryAndReopenPreserveInkAndRejectDuotoneLoss() async throws {
    for depth in [PixelDepth.u8,.u16] {
      let (controller, document, folder) = try DocumentEncodingOptionsTests().fixture()
      defer { document.updateChangeCount(.changeCleared); document.close(); _ = controller }
      let original = try source(depth); document.store.session = EditorSession(document: original)
      XCTAssertEqual(Set(document.saveFormats),Set([.native,.psd,.psb]))
      let panel = NSSavePanel(); XCTAssertTrue(document.prepareSavePanel(panel))
      let accessory = try XCTUnwrap(document.saveAccessory)
      accessory.formats.selectItem(at: try XCTUnwrap(accessory.availableFormats.firstIndex(of:.psd))); accessory.updateFormat()
      XCTAssertTrue(accessory.psdLayerRow.isHidden); XCTAssertFalse(accessory.psdCompositeRow.isHidden)
      for format in [DocumentIO.Format.psd,.psb] {
        let url = folder.appendingPathComponent("inks.\(format.rawValue)")
        try await DocumentSaveWorkflowTests().save(document,to:url,format:format)
        try assertPreserved(DocumentIO.read(url),original)
        XCTAssertEqual(document.fileURL,url); XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(document.store.document,original)
      }
      let duo = try InkChannelWorkflowTests().source(duotone:true)
      for format in DocumentIO.Format.allCases where format != .native { XCTAssertNotNil(DocumentIO.persistenceIssue(duo,format:format)) }
    }
  }
  @MainActor func testHTTPImportDownloadAndSaveShareExactPlanesAndStalePermissionChecks() async throws {
    let files = DocumentIOWorkflowTests(), helper = AutomationTests()
    let folder = try DocumentPersistenceTests().directory(); defer { try? FileManager.default.removeItem(at:folder) }
    for depth in [PixelDepth.u8,.u16] {
      let original = try source(depth)
      try await helper.withService(pressedMouseButtons:{0}) { service, document in
        document.store.session = EditorSession(document: original); try service.share(document)
        service.setDocumentTransfersEnabled(true); service.setDocumentSavesEnabled(true); service.setSaveDirectory(folder)
        let id = try XCTUnwrap(service.shares.first?.id)
        for format in [DocumentIO.Format.psd,.psb] {
          let path = "/v1/documents/\(id)/file.\(format.rawValue)"
          let stale = try await files.request(service,path:path,headers:["X-Photato-Revision":"stale"]); XCTAssertEqual(stale.0.statusCode,409)
          let response = try await files.request(service,path:path)
          XCTAssertEqual(response.0.statusCode,200,String(decoding:response.1,as:UTF8.self))
          try assertPreserved(RasterIO.read(response.1),original)
          let uploaded = try await files.request(service,path:"/v1/documents/import",data:response.1,type:format.mediaType)
          XCTAssertEqual(uploaded.0.statusCode,201)
          let json = try XCTUnwrap(JSONSerialization.jsonObject(with:uploaded.1) as? [String:Any])
          let importedID = try XCTUnwrap((json["id"] as? String).flatMap(UUID.init(uuidString:)))
          let reopened = try XCTUnwrap(service.shares.first {$0.id==importedID}?.document)
          try assertPreserved(reopened.store.document,original); reopened.updateChangeCount(.changeCleared); reopened.close()
          let name = "ink\(original.bitsPerChannel)-\(format.rawValue)"
          let saved = try await helper.edit(service,document,"document.saveAs",["name":name,"format":format.rawValue,"replace":false])
          XCTAssertEqual(saved,200)
          try assertPreserved(DocumentIO.read(folder.appendingPathComponent("\(name).\(format.rawValue)")),original)
        }
        XCTAssertEqual(document.store.document,original); XCTAssertTrue(document.store.session.undoStack.isEmpty)
        service.setDocumentTransfersEnabled(false)
        let denied = try await files.request(service,path:"/v1/documents/\(id)/file.psd"); XCTAssertEqual(denied.0.statusCode,403)
        let caps = try XCTUnwrap(AutomationService.documentTransferCapabilities["multichannelPhotoshop"] as? [String:Any])
        XCTAssertEqual(caps["bitsPerChannel"] as? [Int],[8,16]); XCTAssertEqual(caps["maximumChannels"] as? Int,56)
      }
    }
  }
  private struct Transport: AdobeResourceTransport {
    let data: Data
    func fetch(_ url: URL) async throws -> Data { data }
    func upload(_ data: Data, output: AdobeActionsRequest.Output) async throws { throw CraftError.invalid("Owned hosted output expected") }
  }
  @MainActor func testBothExistingActionJobRoutesPreserveMultichannelPSDAndPSBInput() async throws {
    let helper = AutomationEncodingOptionsTests()
    for depth in [PixelDepth.u8,.u16] { for format in [DocumentIO.Format.psd,.psb] {
      let original = try source(depth), input = try DocumentIO.encode(original,format:format)
      try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:Transport(data:input)) { service,shared in
        service.setResourceJobsEnabled(true); let before = shared.store.document
        var body = helper.body(outputs:[helper.output("image/vnd.adobe.photoshop")])
        body["options"] = ["actions":[["source":["content":"[{\"_obj\":\"selectAllLayers\",\"_target\":[{\"_ref\":\"layer\",\"_enum\":\"ordinal\",\"_value\":\"targetEnum\"}]}]","contentType":"application/json"]]]]
        for route in ["/v1/action-jobs","/v2/execute-actions"] {
          let output = try await helper.outputs(service,route:route,payload:body)
          XCTAssertEqual(output.count,1); try assertPreserved(RasterIO.read(try XCTUnwrap(output.first)),original)
        }
        XCTAssertEqual(shared.store.document,before)
      }
    } }
  }
}
