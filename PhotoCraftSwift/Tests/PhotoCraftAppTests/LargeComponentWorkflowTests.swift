import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeComponentWorkflowTests: XCTestCase {
  @MainActor func testMaximumModeViewportChannelsAndSaveAvailability() async throws {
    let model=try CraftNSDocument.blankModel(width:300000,height:300000,depth:.u16,mode:.cmyk)
    let store=EditorStore(document:model);defer {store.renderTask?.cancel()}
    store.updateViewport(size:CGSize(width:1000,height:700),backingScale:2)
    store.render();await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image)
    XCTAssertLessThanOrEqual((store.image?.width ?? 0)*(store.image?.height ?? 0),4_194_304)
    XCTAssertTrue(store.canEditModeComponents);XCTAssertTrue(store.canBeginDocumentMode)
    try store.setModeComponentVisibility([0]);await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image)
    XCTAssertNil(DocumentIO.persistenceIssue(model,format:.native))
    for format:DocumentIO.Format in [.psd,.tiff] {XCTAssertNotNil(DocumentIO.persistenceIssue(model,format:format))}
    XCTAssertNil(DocumentIO.persistenceIssue(model,format:.psb),"PSB now streams native components; this does not prove physical maximum-size output.")
    XCTAssertLessThan(RecoveryMemoryPolicy.documentCost(model),200*1024*1024)
    let metadata=RasterStorageAPI.state(model)
    XCTAssertEqual(metadata["nativeComponentLogicalBytes"] as? Int,900_000_000_000)
    XCTAssertEqual(metadata["mappedNativeComponentVirtualBytes"] as? Int,0)
  }
  @MainActor func testMaximumHTTPComponentPagesSaveReopenAndHistory() async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try CraftNSDocument.blankModel(width:300000,height:300000,depth:.u16,mode:.cmyk)
      document.store.session=EditorSession(document:original)
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let id=try XCTUnwrap(original.activeLayerID),share=try XCTUnwrap(service.shares.first)
      let parameters:[String:Any]=["layerID":id.uuidString,"component":3,"offset":89_999_999_999,"values":[0.75]]
      let status1=try await helper.edit(service,document,"mode.channel.write",parameters,revision:"stale");XCTAssertEqual(status1,409)
      XCTAssertEqual(document.store.document,original)
      let status2=try await helper.edit(service,document,"mode.channel.write",parameters);XCTAssertEqual(status2,200)
      let edited=document.store.document
      XCTAssertEqual(edited.layers[0].nativeMode?.rawWord(component:3,index:89_999_999_999),49151)
      XCTAssertLessThan(edited.estimatedBytes,3_000_000)
      let rejected=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"85"])
      XCTAssertEqual(rejected.0.statusCode,422)
      let saved=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"86"])
      XCTAssertEqual(saved.0.statusCode,200,String(decoding:saved.1,as:UTF8.self))
      XCTAssertEqual(try NativeArchive.decodePaged(saved.1),edited)
      let status3=try await helper.edit(service,document,"history.undo");XCTAssertEqual(status3,200)
      XCTAssertEqual(document.store.document,original)
      let status4=try await helper.edit(service,document,"history.redo");XCTAssertEqual(status4,200)
      XCTAssertEqual(document.store.document,edited)
      let paint:[String:Any] = ["points":[["x":299998.5,"y":299998.5]],"brush":["size":2,"color":["r":0,"g":1,"b":0,"a":1]]]
      let painted=try await helper.edit(service,document,"paint.stroke",paint)
      XCTAssertEqual(painted,200);XCTAssertNotEqual(document.store.document,edited)
      XCTAssertEqual(document.store.document.colorMode,.cmyk)
      let undoPaint=try await helper.edit(service,document,"history.undo")
      XCTAssertEqual(undoPaint,200);XCTAssertEqual(document.store.document,edited)
      let bounds=DocumentModeAPI.schema("offset")
      XCTAssertEqual(bounds["maximum"] as? Int,89_999_999_999)
      let capabilities=try XCTUnwrap(DocumentModeAPI.capabilities["storage"] as? [String:Any])
      XCTAssertEqual(capabilities["maximumPixels"] as? Int,90_000_000_000)
      XCTAssertEqual(capabilities["denseOperationMaximumPixels"] as? Int,8_388_608)
      service.setDocumentTransfersEnabled(false)
      let revoked=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"86"])
      XCTAssertEqual(revoked.0.statusCode,403)
    }
  }
}
