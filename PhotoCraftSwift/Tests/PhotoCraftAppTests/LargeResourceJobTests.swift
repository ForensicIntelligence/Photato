import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class LargeResourceJobTests: XCTestCase {
  private let sourceURL = "https://example.test/owned.psb"
  private func body(image: [String:Any]? = nil, photato: Bool = false,
                    action: String = #"[{"_obj":"select","_target":[{"_ref":"channel","_enum":"channel","_value":"RGB"}]}]"#) -> [String:Any] {
    var output: [String:Any] = ["mediaType":"image/vnd.adobe.photoshop", "destination":["validityPeriod":60]]
    if photato { output["encodingOptions"] = ["psdLayerCompression":"zipPrediction", "psdCompositeCompression":"zipPrediction"] }
    return ["image":image ?? ["source":["url":sourceURL]], "options":["actions":[["source":["contentType":"application/json", "content":action]]]], "outputs":[output]]
  }
  @MainActor func testMaximumLogicalAdmissionAndPublishedBlankCreationKeepIndependentLimits() throws {
    let maximum = try DocumentCreation.blank(width:300_000,height:300_000)
    try AdobeActionAssets.check(maximum)
    XCTAssertLessThan(maximum.estimatedBytes, 1_048_576)
    for depth in [8,16,32] {
      let payload = body(image:["width":32_000,"height":32_000,"depth":depth],photato:true)
      let request = try AdobeActionsRequest(data:JSONSerialization.data(withJSONObject:payload),allowPhotatoOptions:true)
      let d = try XCTUnwrap(request.creation).document()
      XCTAssertEqual(d.width,32_000); XCTAssertEqual(d.height,32_000)
      XCTAssertLessThan(d.estimatedBytes,1_048_576)
      try AdobeActionAssets.check(d)
    }
    for (w,h) in [(0,1),(1,0),(-1,1),(300_001,1),(1,300_001),(Int.max,Int.max)] {
      XCTAssertThrowsError(try AdobeActionAssets.checkDimensions(width:w,height:h))
    }
    var layers = maximum
    layers.layers = (0..<65).map { Layer(name:"Layer \($0)",content:maximum.layers[0].content) }
    layers.activeLayerID = layers.layers[0].id
    XCTAssertThrowsError(try AdobeActionAssets.check(layers))
    let metadata = try XCTUnwrap(AutomationService.capabilities["actionJobs"] as? [String:Any])
    let limits = try XCTUnwrap(metadata["largeDocuments"] as? [String:Any])
    XCTAssertEqual(limits["maximumCanvasDimension"] as? Int,300_000)
    XCTAssertEqual(limits["maximumCanvasPixels"] as? Int,90_000_000_000)
    XCTAssertEqual(limits["maximumResidentDocumentBytes"] as? Int,128*1_024*1_024)
    XCTAssertEqual(limits["maximumAnalysisPixels"] as? Int,4_194_304)
    let containers = try XCTUnwrap(AutomationService.documentTransferCapabilities["photoshopContainers"] as? [String:Any])
    let caches = try XCTUnwrap(containers["smartFilterCaches"] as? [String:Any])
    let cacheLimits = try XCTUnwrap(caches["limits"] as? String)
    XCTAssertFalse(cacheLimits.contains("Adobe4MP job canvas"))
    XCTAssertTrue(cacheLimits.contains("local job64MiB resources/128MiB aggregates"))
  }
  func testActualFortyMillionRGB32SamplesDecodeThroughResourcePaging() throws {
    var d = try DocumentCreation.blank(width:8000,height:5000,depth:.f32)
    var pixels = try Surface(width:d.width,height:d.height,depth:.f32,fill:.white,colorEncoding:.linearRGB)
    let changed = Pixel(2.25,-0.125,0.375,0.5)
    pixels.setLinearPixel(x:4097,y:1987,changed)
    d.layers[0].content = .raster(pixels)
    let input = try PSDCodec.writeRasterLayers(d,format:.psb,compositeCompression:.zipPrediction)
    XCTAssertLessThan(input.count,AdobeActionAssets.maximumResourceBytes)
    let result = try AdobeActionAssets.decode(input)
    XCTAssertEqual(result.width,8000); XCTAssertEqual(result.height,5000)
    XCTAssertEqual(result.depth,.f32)
    XCTAssertLessThan(result.estimatedBytes,AdobeActionAssets.maximumDocumentBytes)
    guard case .raster(let actual) = result.layers[0].content else { return XCTFail("Missing paged raster") }
    XCTAssertLessThan(actual.allocatedBytes,1_048_576)
    var mismatches = 0
    for y in 0..<5000 { for x in 0..<8000 {
      if actual.linearPixel(x:x,y:y) != (x == 4097 && y == 1987 ? changed:.white) { mismatches += 1 }
    } }
    XCTAssertEqual(mismatches,0,"Compare every decoded logical RGB32/alpha sample against the authored source.")
    let request = try AdobeActionsRequest(data:JSONSerialization.data(withJSONObject:body(photato:true)),allowPhotatoOptions:true)
    let output = try XCTUnwrap(AdobeActionAssets.execute(request,document:result).first).data
    let native = try PSDCodec.writeRasterLayers(result,compositeCompression:.zipPrediction)
    XCTAssertEqual(output,native)
    XCTAssertEqual(Array(output[4..<6]),[0,1],"The existing Photoshop output contract remains PSD.")
  }
  func testPSDOutputBudgetIsEnforcedDuringWritingAndKeepsDefaultBytes() async throws {
    let d = try DocumentCreation.blank(width:31,height:17,depth:.u16)
    let expected = try PSDCodec.writeRasterLayers(d)
    XCTAssertEqual(try PSDCodec.writeRasterLayers(d,maximumBytes:expected.count),expected)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d,maximumBytes:expected.count-1))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d,maximumBytes:0))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d,maximumBytes:PSDCodec.maximumInputBytes+1))
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try AdobeActionAssets.decode(expected)
    }
    do { _ = try await cancelled.value; XCTFail("Cancelled resource was decoded") }
    catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
  }
  @MainActor func testBothHTTPJobsApplyLargeNativeFilterAndPreserveDesktopHistory() async throws {
    let source = try DocumentCreation.blank(width:6000,height:900)
    let input = try PSDCodec.writeRasterLayers(source,format:.psb,compositeCompression:.zipPrediction)
    let decoded = try AdobeActionAssets.decode(input),id = decoded.layers[0].id
    var native = EditorSession(document:decoded)
    var filter = RasterFilter(.highPass); filter.radius = 0.25
    try native.execute(.applyFilter(id,filter))
    let expected = try DocumentIO.encode(native.document,format:.psd)
    let action = #"[{"_obj":"highPass","radius":{"_unit":"pixelsUnit","_value":0.25}}]"#
    let transport = ResourceTransport(input)
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0},resourceTransport:transport) { service,shared in
      let before = shared.store.document
      for route in ["/v1/action-jobs","/v2/execute-actions"] {
        service.setResourceJobsEnabled(false); service.setResourceJobsEnabled(true)
        let accepted = try await helper.request(service,path:route,body:self.body(action:action))
        XCTAssertEqual(accepted.0.statusCode,202)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:accepted.1) as? [String:Any])
        let statusURL = try XCTUnwrap(URL(string:XCTUnwrap(object["statusUrl"] as? String)))
        let deadline = ContinuousClock.now.advanced(by:.seconds(180))
        var exported: Data?
        while ContinuousClock.now < deadline {
          let response = try await helper.request(service,path:statusURL.path)
          let state = try XCTUnwrap(JSONSerialization.jsonObject(with:response.1) as? [String:Any])
          if state["status"] as? String == "failed" { XCTFail("Large job failed: \(state)"); break }
          if state["status"] as? String == "succeeded" {
            let result = try XCTUnwrap(state["result"] as? [String:Any])
            let outputs = try XCTUnwrap(result["outputs"] as? [[String:Any]])
            let destination = try XCTUnwrap(outputs.first?["destination"] as? [String:Any])
            let assetURL = try XCTUnwrap(URL(string:XCTUnwrap(destination["url"] as? String)))
            let asset = try await helper.request(service,path:assetURL.path)
            XCTAssertEqual(asset.0.statusCode,200)
            exported = asset.1
            break
          }
          try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertEqual(try XCTUnwrap(exported),expected)
        XCTAssertEqual(shared.store.document,before)
        XCTAssertTrue(shared.store.session.undoStack.isEmpty)
        XCTAssertEqual(service.shares.count,0,"Isolated resource jobs must not publish desktop documents.")
      }
    }
  }
}

private actor ResourceTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws {
    throw AdobeAPIError.unsupported("No external uploads in this authored test.")
  }
}
