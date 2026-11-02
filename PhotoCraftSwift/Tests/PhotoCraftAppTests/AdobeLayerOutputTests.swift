import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class AdobeLayerOutputTests: XCTestCase {
  func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width:8,height:6,name:"Source")
    var red = Layer(name:"Red",content:.raster(try Surface(width:2,height:2,fill:Pixel(1,0,0)))); red.x = 3; red.y = 2
    var blue = Layer(name:"Blue",content:.raster(try Surface(width:1,height:1,fill:Pixel(0,0,1)))); blue.x = 6; blue.y = 4
    d.layers += [red,blue]; return d
  }
  func output(_ layers: [[String:Any]]? = nil,crop: String? = nil,format: String = "image/png") -> [String:Any] {
    var value:[String:Any] = ["mediaType":format,"destination":["validityPeriod":60]]; value["layers"] = layers; value["cropMode"] = crop; return value
  }
  func request(_ outputs: [[String:Any]]) throws -> AdobeActionsRequest {
    try AdobeActionsRequest(data:JSONSerialization.data(withJSONObject:["image":["source":["url":"https://example.test/owned.psd"]],"edits":["layers":[]],"outputs":outputs]),createComposite:true)
  }
  func testSingleMultiDocumentTrimAndNameOutputsUseDistinctCacheEntries() throws {
    let d = try fixture(), before = d
    let request = try request([output([["id":2]]),output([["name":"Blue"]]),output([["id":2]],crop:"document_bounds"),output([["id":2],["id":3]],crop:"trim_to_transparency"),output()])
    let files = try AdobeActionAssets.encode(request,document:d), documents = try files.map { try RasterIO.read($0.data) }
    XCTAssertEqual(documents.map(\.width),[2,1,8,4,8]); XCTAssertEqual(documents.map(\.height),[2,1,6,3,6])
    XCTAssertEqual(try Renderer.composite(documents[0]).pixel(x:0,y:0),Pixel(1,0,0)); XCTAssertEqual(try Renderer.composite(documents[1]).pixel(x:0,y:0),Pixel(0,0,1))
    XCTAssertEqual(try Renderer.composite(documents[2]).pixel(x:0,y:0),.clear); XCTAssertEqual(try Renderer.composite(documents[2]).pixel(x:3,y:2),Pixel(1,0,0)); XCTAssertEqual(d,before)
  }
  func testSingleGroupPSDRemainsEditableAndMixedProfilesStayIndependent() throws {
    var d = try fixture(), group = Layer(name:"Group",content:.group(.init())); d.layers[1].parentID = group.id; d.layers = [d.layers[0], d.layers[1], group, d.layers[2]]
    let request = try request([output([["name":"Group"]],format:"image/vnd.adobe.photoshop"),output([["id":2]],format:"image/tiff")])
    let files = try AdobeActionAssets.encode(request,document:d), psd = try PSDCodec.read(files[0].data)
    XCTAssertEqual([psd.width,psd.height],[2,2]); XCTAssertEqual(psd.layers.count,2); XCTAssertEqual(psd.layers.filter(\.isGroup).count,1); XCTAssertEqual(psd.layers.first?.name,"Red")
    XCTAssertEqual(try Renderer.composite(psd).pixel(x:0,y:0),Pixel(1,0,0)); XCTAssertEqual(try RasterIO.read(files[1].data).width,2)
  }
  func testPublishedValidationRejectsAmbiguousMissingAndInvalidReferencesBeforeOutput() throws {
    let d = try fixture(), before = d
    for output in [output([]),output([["id":2,"name":"Red"]]),output([["visible":true]]),output([["id":true]]),output([["id":2],["id":2]]),output([["id":2],["id":3]],format:"image/vnd.adobe.photoshop"),output(crop:"layer_bounds"),output([["id":2],["id":3]],crop:"layer_bounds"),output(crop:"unknown")] { XCTAssertThrowsError(try request([output])) }
    for value in [output([["id":999]]),output([["name":"Missing"]])] { XCTAssertThrowsError(try AdobeActionAssets.encode(request([output(),value]),document:d)) }
    var ambiguous = d; ambiguous.layers[2].name = "Red"; XCTAssertThrowsError(try AdobeActionAssets.encode(request([output([["name":"Red"]])]),document:ambiguous))
    let noRoute = try JSONSerialization.data(withJSONObject:["image":["source":["url":"https://example.test/input"]],"options":["actions":[]],"outputs":[output([["id":2]])]])
    XCTAssertThrowsError(try AdobeActionsRequest(data:noRoute)); XCTAssertEqual(d,before)
  }
  @MainActor func testPublishedAsyncJobPublishesSelectedAssetAndPreservesHostedLifecycle() async throws {
    let original = try fixture(), input = try PSDCodec.writeRasterLayers(original), request = try request([output([["id":2]])])
    let jobs = AdobeActionJobs(transport:ImageExportAdobeTransport(input)); defer { jobs.revoke() }
    let submitted = try jobs.submit(request,baseURL:URL(string:"http://127.0.0.1:43210")!)
    for _ in 0..<500 {
      if let state = jobs.snapshot(submitted.id), [.succeeded,.failed].contains(state.status) { break }
      try await Task.sleep(for:.milliseconds(5))
    }
    let finished = try XCTUnwrap(jobs.snapshot(submitted.id)); XCTAssertEqual(finished.status,.succeeded,finished.error?.message ?? ""); XCTAssertEqual(finished.outputs.count,1)
    let id = try XCTUnwrap(UUID(uuidString:finished.outputs[0].url.lastPathComponent)), asset = try XCTUnwrap(jobs.asset(id)), read = try RasterIO.read(asset.data)
    XCTAssertEqual([read.width,read.height],[2,2]); XCTAssertEqual(try Renderer.composite(read).pixel(x:0,y:0),Pixel(1,0,0))
  }
}
private actor ImageExportAdobeTransport: AdobeResourceTransport {
  let input: Data
  init(_ input:Data) { self.input = input }
  func fetch(_ url:URL) async throws -> Data { input }
  func upload(_ data:Data,output:AdobeActionsRequest.Output) async throws {}
}
