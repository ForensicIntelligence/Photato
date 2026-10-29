import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class PhotoshopEncodingOptionsTests: XCTestCase {
  @MainActor func testNativeSaveCopyAndFormatSwitchPreserveIndependentChoices() async throws {
    let (controller,doc,folder) = try DocumentEncodingOptionsTests().fixture()
    defer { doc.close();_ = controller }
    let psd = RasterEncodingOptions(psdLayerCompression:.rle,psdCompositeCompression:.zip)
    let psb = RasterEncodingOptions(psdLayerCompression:.raw,psdCompositeCompression:.zipPrediction)
    doc.rememberedEncodingOptions[.psd] = psd;doc.rememberedEncodingOptions[.psb] = psb
    let panel = NSSavePanel();XCTAssertTrue(doc.prepareSavePanel(panel))
    let accessory = try XCTUnwrap(doc.saveAccessory)
    for (format,options) in [(DocumentIO.Format.psd,psd),(.psb,psb),(.psd,psd)] {
      accessory.formats.selectItem(at:try XCTUnwrap(accessory.availableFormats.firstIndex(of:format)));accessory.updateFormat()
      XCTAssertEqual(accessory.encodingOptions,options)
      XCTAssertFalse(accessory.psdLayerRow.isHidden);XCTAssertFalse(accessory.psdCompositeRow.isHidden)
      XCTAssertTrue(accessory.pngRow.isHidden);XCTAssertTrue(accessory.tiffRow.isHidden)
      let target = folder.appendingPathComponent("native."+format.rawValue), model = doc.store.document
      try await DocumentSaveWorkflowTests().save(doc,to:target,format:format)
      XCTAssertEqual(try Data(contentsOf:target),try DocumentIO.encode(model,format:format,options:options))
      XCTAssertEqual(doc.rememberedEncodingOptions[format],options);XCTAssertFalse(doc.isDocumentEdited)
    }
    let model = doc.store.document, history = doc.store.session.undoStack.count
    let target = folder.appendingPathComponent("independent.psb"), source = doc.fileURL
    let remembered = doc.rememberedEncodingOptions
    let different = RasterEncodingOptions(psdLayerCompression:.zip,psdCompositeCompression:.rle)
    try await doc.copyDocument(to:target,format:.psb,options:different)
    XCTAssertEqual(try Data(contentsOf:target),try DocumentIO.encode(model,format:.psb,options:different))
    XCTAssertEqual(doc.fileURL,source);XCTAssertEqual(doc.rememberedEncodingOptions,remembered)
    XCTAssertEqual(doc.store.document,model);XCTAssertEqual(doc.store.session.undoStack.count,history)
    try doc.store.executeEditorCommand(.renameLayer(model.layers[0].id,"Edited"))
    accessory.psdLayerCompression.selectItem(at:1);accessory.psdCompositeCompression.selectItem(at:1)
    try await DocumentSaveWorkflowTests().save(doc,to:try XCTUnwrap(source),format:.psd,operation:.saveOperation)
    XCTAssertEqual(doc.rememberedEncodingOptions[.psd],psd)
    XCTAssertEqual(try Data(contentsOf:try XCTUnwrap(source)),try DocumentIO.encode(doc.store.document,format:.psd,options:psd))
  }
  @MainActor func testFailedPreparedSaveAndMismatchedOptionsPreserveFileAndSettings() async throws {
    let (controller,doc,folder) = try DocumentEncodingOptionsTests().fixture();defer { doc.close();_ = controller }
    let url = folder.appendingPathComponent("original.psd"), original = Data([9,9,4])
    try original.write(to:url)
    doc.rememberedEncodingOptions[.psd] = .init(psdLayerCompression:.rle)
    for options in [RasterEncodingOptions(psdLayerCompression:.raw,psdCompositeCompression:.zip),.init(tiffCompression:.zip)] {
      do {
        try await doc.persistDocument(to:url,format:.psd,operation:.saveAsOperation,options:options,maximumPreparedBytes:1)
        XCTFail("Invalid/budget save succeeded")
      } catch {}
      XCTAssertEqual(try Data(contentsOf:url),original);XCTAssertNil(doc.fileURL)
      XCTAssertEqual(doc.rememberedEncodingOptions[.psd],.init(psdLayerCompression:.rle))
      XCTAssertNil(doc.preparedSaveOutput);XCTAssertFalse(doc.fileOperationBusy)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path).filter { $0 != "Recovery" },[url.lastPathComponent])
  }
  @MainActor func testActualHTTPPSDPSBDownloadsAndSavingUseSameBytes() async throws {
    let helper = AutomationTests(), folder = try DocumentPersistenceTests().directory();defer { try? FileManager.default.removeItem(at:folder) }
    try await helper.withService(pressedMouseButtons:{0}) { service,doc in
      service.setDocumentTransfersEnabled(true);service.setDocumentSavesEnabled(true);service.setSaveDirectory(folder);try service.share(doc)
      let id = try XCTUnwrap(service.shares.first?.id), before = doc.store.document
      for format in [DocumentIO.Format.psd,.psb] {
        for method in RasterEncodingOptions.PhotoshopCompression.allCases {
          let options = RasterEncodingOptions(psdLayerCompression:method,psdCompositeCompression:method)
          let header = String(decoding:try JSONSerialization.data(withJSONObject:DocumentEncodingOptions.json(options)),as:UTF8.self)
          let result = try await helper.request(service,path:"/v1/documents/\(id)/file.\(format.rawValue)",headers:["X-Photato-Export-Options":header])
          XCTAssertEqual(result.0.statusCode,200)
          XCTAssertEqual(result.1,try DocumentIO.encode(before,format:format,options:options))
          XCTAssertTrue(doc.rememberedEncodingOptions.isEmpty)
        }
      }
      let choices: [String:Any] = ["psdLayerCompression":"rle","psdCompositeCompression":"zipPrediction"]
      let saved = try await helper.edit(service,doc,"document.saveAs",["name":"api","format":"psb","replace":false,"options":choices])
      XCTAssertEqual(saved,200);XCTAssertEqual(doc.rememberedEncodingOptions[.psb],.init(psdLayerCompression:.rle,psdCompositeCompression:.zipPrediction))
      for raw in ["{\"psdLayerCompression\":1}","{\"psdCompositeCompression\":null}","{\"psdLayerCompression\":\"unknown\"}"] {
        let result = try await helper.request(service,path:"/v1/documents/\(id)/file.psb",headers:["X-Photato-Export-Options":raw]);XCTAssertEqual(result.0.statusCode,400)
      }
      let mismatch = try await helper.request(service,path:"/v1/documents/\(id)/file.png",headers:["X-Photato-Export-Options":"{\"psdLayerCompression\":\"raw\"}"])
      XCTAssertEqual(mismatch.0.statusCode,400);XCTAssertEqual(doc.store.document,before)
    }
  }
  private struct Transport: AdobeResourceTransport {
    let bytes: Data
    func fetch(_ url: URL) async throws -> Data { bytes }
    func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws { throw CraftError.invalid("Owned hosted-only probe") }
  }
  @MainActor func testNativeJobCompressionCacheAndAdobeContractBoundary() async throws {
    let fixture = try DocumentSaveWorkflowTests().fixture(depth:.u16)
    let bytes = try PSDCodec.writeRasterLayers(fixture), model = try AdobeActionAssets.decode(bytes)
    let helper = AutomationEncodingOptionsTests()
    let choices = [RasterEncodingOptions(psdLayerCompression:.raw,psdCompositeCompression:.raw),.init(psdLayerCompression:.rle,psdCompositeCompression:.zipPrediction)]
    let payload = helper.body(outputs:choices.map { helper.output("image/vnd.adobe.photoshop",extra:["encodingOptions":DocumentEncodingOptions.json($0)]) })
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:Transport(bytes:bytes)) { service,_ in
      service.setResourceJobsEnabled(true)
      let outputs = try await helper.outputs(service,route:"/v1/action-jobs",payload:payload)
      XCTAssertNotEqual(outputs[0],outputs[1]);XCTAssertEqual(outputs,try choices.map { try DocumentIO.encode(model,format:.psd,options:$0) })
      let rejected = try await AutomationTests().request(service,path:"/v2/execute-actions",body:payload)
      XCTAssertEqual(rejected.0.statusCode,422)
      let unchanged = try await helper.outputs(service,route:"/v2/execute-actions",payload:helper.body(outputs:[helper.output("image/vnd.adobe.photoshop")]))
      XCTAssertEqual(unchanged,[try PSDCodec.writeRasterLayers(model)])
    }
    let bad = helper.body(outputs:[helper.output("image/vnd.adobe.photoshop",extra:["compression":"rle"])])
    XCTAssertThrowsError(try AdobeActionsRequest(data:JSONSerialization.data(withJSONObject:bad)))
  }
}
