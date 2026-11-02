import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LinkedSmartObjectContractTests:XCTestCase {
  func asset()throws->Data {try RasterIO.encoded(Surface(width:4,height:3,fill:Pixel(0.2,0.4,0.6)))}
  func fields(_ linked:Bool,_ adding:Bool=true)->[String:Any] {
    let operation:[String:Any]=adding ? ["type":"add","placement":["type":"top"]]:["type":"edit"]
    return ["type":"smart_object_layer","name":"Linked Logo","operation":operation,"smartObject":["isLinked":linked,"smartObjectFile":["source":["url":"https://example.invalid/logo.png?signature=private"]]]]
  }
  func testPublishedLinkedAddPSDManifestAndCredentialFreeReference()throws {
    let raw=fields(true),edit=try AdobeSmartObjectEdit(raw,path:"edit"),url=try XCTUnwrap(edit.url)
    var session=EditorSession(document:try CraftDocument(width:16,height:12));try edit.apply(to:&session,resources:[url:try asset()])
    let object=try XCTUnwrap(session.document.layers.last?.smartObject)
    XCTAssertEqual(object.linkedSource?.reference,"https://example.invalid/logo.png")
    let output=try PSDCodec.writeRasterLayers(session.document),reopened=try PSDCodec.read(output)
    XCTAssertTrue(reopened.layers.last!.smartObject!.data.isEmpty)
    XCTAssertNotNil(reopened.layers.last!.smartObject!.linkedSource)
    let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:AdobeArtboardRequest.manifest(reopened))as?[String:Any])
    let layers=try XCTUnwrap(manifest["layers"]as?[[String:Any]]),smart=try XCTUnwrap(layers.last?["smartObject"]as?[String:Any])
    XCTAssertEqual(smart["isLinked"]as?Bool,true);XCTAssertEqual(smart["isSmartObject"]as?Bool,true)
    let encoded=try JSONSerialization.data(withJSONObject:manifest);XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("signature=private"))
  }
  func testPublishedLinkedReplacementAndEmbeddedAssetReplacement()throws {
    var session=EditorSession(document:try CraftDocument(width:16,height:12))
    let add=try AdobeSmartObjectEdit(fields(false),path:"edit"),url=try XCTUnwrap(add.url);try add.apply(to:&session,resources:[url:try asset()])
    let original=session.document.layers.last!,linked=try AdobeSmartObjectEdit(fields(true,false),path:"edit")
    try linked.apply(to:&session,resources:[url:try asset()]);XCTAssertNotNil(session.document.layers.last?.smartObject?.linkedSource)
    XCTAssertEqual(session.document.layers.last?.coordinateTransform,original.coordinateTransform)
    let embedded=try AdobeSmartObjectEdit(fields(false,false),path:"edit");try embedded.apply(to:&session,resources:[url:try asset()])
    XCTAssertNil(session.document.layers.last?.smartObject?.linkedSource)
    XCTAssertFalse(session.document.layers.last!.smartObject!.data.isEmpty)
  }
  func testLinkedAutoResizeIsRejectedAndSharedLayerMetadataIsTruthful()throws {
    var raw=fields(true,false);var smart=raw["smartObject"]as![String:Any];smart["autoResize"]=true;raw["smartObject"]=smart
    XCTAssertThrowsError(try AdobeSmartObjectEdit(raw,path:"edit"))
    let edit=try AdobeSmartObjectEdit(fields(true),path:"edit"),url=try XCTUnwrap(edit.url)
    var session=EditorSession(document:try CraftDocument(width:16,height:12));try edit.apply(to:&session,resources:[url:try asset()])
    let state=session.document.layers.last!.smartObject!.apiState
    XCTAssertEqual(state["embedded"]as?Bool,false);XCTAssertEqual(state["linked"]as?Bool,true)
    XCTAssertNil(state["authorizationID"]);XCTAssertNil(state["reference"])
  }
}

private actor LinkedArtworkContractTransport:AdobeResourceTransport {
  var files:[URL:Data]=[:]
  func set(_ bytes:Data,at url:URL){files[url]=bytes}
  func fetch(_ url:URL)async throws->Data {
    guard let bytes=files[url]else{throw AdobeAPIError.invalid("Missing linked contract fixture.")};return bytes
  }
  func upload(_ data:Data,output:AdobeActionsRequest.Output)async throws{throw AdobeAPIError.unsupported("This fixture uses hosted outputs.")}
}
extension LinkedSmartObjectContractTests {
  @MainActor func testPublishedHTTPJobAddsReplacesAndEmbedsLinkedResourcesWithoutChangingSharedDocument()async throws {
    let transport=LinkedArtworkContractTransport(),helper=AutomationActionJobsTests()
    let inputURL=URL(string:"https://example.test/input.psd")!,sourceURL=URL(string:"https://example.test/source.png?signature=private")!
    await transport.set(try PSDCodec.writeRasterLayers(CraftDocument(width:16,height:12)),at:inputURL)
    await transport.set(try asset(),at:sourceURL)
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:transport){service,shared in
      let untouched=shared.store.document;service.setResourceJobsEnabled(true)
      func payload(_ linked:Bool,add:Bool)->[String:Any] {
        let operation:[String:Any]=add ? ["type":"add","placement":["type":"top"]]:["type":"edit"]
        let smart:[String:Any]=["isLinked":linked,"smartObjectFile":["source":["url":sourceURL.absoluteString]]]
        let layer:[String:Any]=["name":"Linked contract logo","type":"smart_object_layer","operation":operation,"smartObject":smart]
        return ["image":["source":["url":inputURL.absoluteString]],"edits":["layers":[layer]],"outputs":[["mediaType":"image/vnd.adobe.photoshop","destination":["validityPeriod":60]]]]
      }
      let first=try await helper.output(service,submit:"/v2/create-composite",payload:payload(true,add:true)),added=try PSDCodec.read(first.2)
      let source=try XCTUnwrap(added.layers.last?.smartObject)
      XCTAssertNotNil(source.linkedSource);XCTAssertTrue(source.data.isEmpty)
      XCTAssertEqual(source.linkedSource?.reference,"https://example.test/source.png")
      let transform=added.layers.last!.coordinateTransform
      await transport.set(first.2,at:inputURL)
      let replacement=try RasterIO.encoded(Surface(width:6,height:2,fill:Pixel(0.1,0.8,0.4)));await transport.set(replacement,at:sourceURL)
      let second=try await helper.output(service,submit:"/v2/create-composite",payload:payload(true,add:false)),updated=try PSDCodec.read(second.2)
      XCTAssertNotNil(updated.layers.last?.smartObject?.linkedSource);XCTAssertEqual(updated.layers.last?.smartObject?.width,6);XCTAssertEqual(updated.layers.last?.smartObject?.height,2)
      XCTAssertEqual(updated.layers.last?.coordinateTransform,transform)
      await transport.set(second.2,at:inputURL)
      let third=try await helper.output(service,submit:"/v2/create-composite",payload:payload(false,add:false)),embedded=try PSDCodec.read(third.2)
      XCTAssertNil(embedded.layers.last?.smartObject?.linkedSource);XCTAssertEqual(embedded.layers.last?.smartObject?.data,replacement)
      XCTAssertEqual(shared.store.document,untouched)
    }
  }
}
