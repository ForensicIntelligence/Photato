import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeComponentToolsWorkflowTests:XCTestCase {
  func fixture()throws->CraftDocument {
    var d=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.clear,mode:.cmyk)
    var n=try XCTUnwrap(d.layers[0].nativeMode);try n.set(0.25,component:3,index:89_999_999_999);try n.set(1,component:4,index:89_999_999_999)
    d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface());return d
  }
  @MainActor func testMaximumSelectedTargetAvailabilityAPIEquivalencePersistenceAndUndo() async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original)
      try service.share(document);service.setDocumentTransfersEnabled(true);let share=try XCTUnwrap(service.shares.first),id=original.layers[0].id
      try document.store.selectModeComponents([0]);XCTAssertTrue(document.store.canEditModeComponents)
      XCTAssertEqual(document.store.documentModeState["componentEditingAvailable"] as? Bool,true)
      let capabilities=try XCTUnwrap(DocumentModeAPI.capabilities["largeComponentTools"] as? [String:Any])
      XCTAssertEqual(capabilities["maximumPixels"] as? Int,90_000_000_000);XCTAssertEqual(capabilities["maximumPatchPixels"] as? Int,131072)
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:DocumentModeAPI.capabilities))
      var desktop=EditorSession(document:original)
      try desktop.execute(.modeComponents(.init(layerID:id,components:[0],operation:.fill(0.25,1))))
      let status=try await helper.edit(service,document,"mode.channel.edit",["layerID":id.uuidString,"components":[0],"action":"fill","value":0.25,"opacity":1])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,desktop.document)
      let saved=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"86"])
      XCTAssertEqual(saved.0.statusCode,200);XCTAssertEqual(try NativeArchive.decodePaged(saved.1),desktop.document)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
    }
  }
  @MainActor func testMaximumStaleBusyMismatchAndUnsupportedRequestsNeverCommit() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try self.fixture();document.store.session=EditorSession(document:original);try service.share(document)
      let id=original.layers[0].id
      let fields:[String:Any]=["layerID":id.uuidString,"components":[0],"action":"invert"]
      let stale=try await helper.edit(service,document,"mode.channel.edit",fields,revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,original)
      try document.store.selectModeComponents([3])
      let mismatch=try await helper.edit(service,document,"mode.channel.edit",fields);XCTAssertEqual(mismatch,422)
      document.store.coalesce(true)
      XCTAssertFalse(document.store.canEditModeComponents)
      let busy=try await helper.edit(service,document,"mode.channel.edit",fields);XCTAssertEqual(busy,409)
      document.store.coalesce(false);try document.store.selectModeComponents([0])
      var invalid=fields;invalid["action"]="filter";invalid["filter"]=["kind":"cameraRaw"]
      let unsupported=try await helper.edit(service,document,"mode.channel.edit",invalid)
      XCTAssertNotEqual(unsupported,200);XCTAssertEqual(document.store.document,original);XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
}
