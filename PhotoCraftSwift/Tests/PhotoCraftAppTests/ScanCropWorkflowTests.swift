import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ScanCropWorkflowTests: XCTestCase {
  func scan(size: Int = 180) throws -> CraftDocument {
    let height = size*2/3
    var document = try CraftDocument(width:size,height:height,name:"Owned scan")
    var pixels = try Surface(width:size,height:height,depth:.u8,fill:.white)
    for y in height/6..<height*5/6 {for x in size/12..<size*11/12 where x<size*5/12 || x>=size*7/12 {pixels.setPixel(x:x,y:y,x<size/2 ? Pixel(0.2,0.4,0.6):Pixel(0.7,0.3,0.1))}}
    document.layers[0].content = .raster(pixels);return document
  }
  @MainActor func setup(_ service: AutomationService,_ document: CraftNSDocument,size: Int = 180) throws {
    document.store.session = EditorSession(document:try scan(size:size));try service.share(document)
  }
  @MainActor func cleanup(_ service: AutomationService,_ document: CraftNSDocument) {HDRMergeWorkflowTests().cleanup(service.controller,except:document)}
  @MainActor func testNativeMenuExtractionAndSourceUnchanged() async throws {
    try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
      try setup(service,first);defer {cleanup(service,first)}
      let snapshot = first.store.document
      let created = try await service.controller.cropAndStraighten(first,display:false)
      XCTAssertEqual(created.count,2);XCTAssertTrue(created.allSatisfy{$0.fileURL == nil && $0.isDocumentEdited})
      XCTAssertEqual(first.store.document,snapshot);XCTAssertTrue(first.store.session.undoStack.isEmpty);XCTAssertFalse(first.store.geometryBusy);XCTAssertNil(service.controller.scanCropOperationID)
      let previous = NSApp.mainMenu;defer {NSApp.mainMenu = previous};AppDelegate().installPhotoshopMenus()
      let menu = NSApp.mainMenu?.items.first{$0.title == "File"}?.submenu?.items.first{$0.title == "Automate"}?.submenu?.items.first{$0.title == "Crop and Straighten Photos"}
      XCTAssertEqual(menu?.action,#selector(AppDelegate.cropAndStraightenPhotos));XCTAssertEqual(menu?.keyEquivalent,"")
    }
  }
  @MainActor func testHTTPDetectionCreationMatchesNativeAndGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,first in
      try setup(service,first);defer {cleanup(service,first)}
      let snapshot = first.store.document,id = try XCTUnwrap(service.shares.first?.id)
      let detect = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"document.cropStraighten.detect","revision":service.revision(first.store),"parameters":[:]])
      XCTAssertEqual(detect.0.statusCode,200,String(decoding:detect.1,as:UTF8.self))
      let data = try XCTUnwrap(JSONSerialization.jsonObject(with:detect.1) as? [String:Any]);XCTAssertEqual((data["photos"] as? [Any])?.count,2);XCTAssertEqual(service.controller.documents.count,1)
      let denied = try await helper.edit(service,first,"document.cropStraighten",[:]);XCTAssertEqual(denied,403)
      service.setDocumentTransfersEnabled(true)
      let bad = try await helper.edit(service,first,"document.cropStraighten",["layerID":"invalid"]);XCTAssertEqual(bad,400)
      first.store.geometryBusy = true;let busy = try await helper.edit(service,first,"document.cropStraighten",[:]);XCTAssertEqual(busy,409);first.store.geometryBusy = false
      let status = try await helper.edit(service,first,"document.cropStraighten",[:]);XCTAssertEqual(status,201)
      let native = try ScanCrop.prepare(snapshot),created = Array(service.shares.dropFirst()).compactMap(\.document)
      XCTAssertEqual(created.count,2)
      for (i,item) in created.enumerated() {XCTAssertEqual(try Renderer.composite(item.store.document),try Renderer.composite(native.documents[i]))}
      XCTAssertEqual(first.store.document,snapshot);XCTAssertTrue(first.store.session.undoStack.isEmpty)
      let stale = try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"document.cropStraighten","revision":"stale","parameters":[:]])
      XCTAssertEqual(stale.0.statusCode,409);XCTAssertEqual(service.controller.documents.count,3)
    }
  }
  @MainActor func testAPICancellationAndRevocationPublishNothing() async throws {
    let helper = AutomationTests()
    for revoke in [false,true] {
      try await helper.withService(pressedMouseButtons:{0}) {service,first in
        try setup(service,first,size:1440);defer {cleanup(service,first)};service.setDocumentTransfersEnabled(true)
        let snapshot = first.store.document,id = try XCTUnwrap(service.shares.first?.id),revision = service.revision(first.store)
        let task = Task {try await helper.request(service,path:"/v1/documents/\(id)/commands",body:["command":"document.cropStraighten","revision":revision,"parameters":[:]])}
        let deadline = Date().addingTimeInterval(10)
        while service.scanCropOperationID == nil && Date()<deadline {try await Task.sleep(for:.milliseconds(5))}
        let operation = try XCTUnwrap(service.scanCropOperationID)
        if revoke {service.revoke(id)} else {
          let cancelled = try await helper.edit(service,first,"document.cropStraighten.cancel",["operationID":operation.uuidString]);XCTAssertEqual(cancelled,200)
        }
        let response = try await task.value;XCTAssertNotEqual(response.0.statusCode,201)
        XCTAssertEqual(service.controller.documents.count,1);XCTAssertEqual(first.store.document,snapshot);XCTAssertFalse(first.store.geometryBusy);XCTAssertNil(service.controller.scanCropOperationID)
      }
    }
  }
  @MainActor func testNativeCancellationAndStaleSourceNeverPublish() async throws {
    for cancel in [false,true] {
      try await AutomationTests().withService(pressedMouseButtons:{0}) {service,first in
        try setup(service,first,size:1440);defer {cleanup(service,first)}
        let task = Task { _ = try await service.controller.cropAndStraighten(first,display:false) }
        let deadline = Date().addingTimeInterval(10)
        while service.controller.scanCropOperationID == nil && Date()<deadline {try await Task.sleep(for:.milliseconds(5))}
        XCTAssertNotNil(service.controller.scanCropOperationID)
        service.controller.beginContactSheet(display:false);XCTAssertNil(service.controller.contactSheetWorkspace)
        if cancel {first.store.geometryTask?.cancel()} else {try first.store.session.execute(.renameLayer(first.store.document.layers[0].id,"Changed"))}
        do {_ = try await task.value;XCTFail("Interrupted extraction published")} catch {}
        XCTAssertEqual(service.controller.documents.count,1);XCTAssertFalse(first.store.geometryBusy)
      }
    }
  }
  @MainActor func testInsufficientSharingCapacityRejectsAllOutputs() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,first in
      try setup(service,first);defer {cleanup(service,first)};service.setDocumentTransfersEnabled(true)
      for _ in 0..<6 {let item = CraftNSDocument(model:try CraftDocument(width:2,height:2));service.controller.addDocument(item);try service.share(item)}
      let snapshot = first.store.document
      let rejected = try await helper.edit(service,first,"document.cropStraighten",[:]);XCTAssertEqual(rejected,429)
      XCTAssertEqual(service.controller.documents.count,7);XCTAssertEqual(service.shares.count,7);XCTAssertEqual(first.store.document,snapshot)
      XCTAssertFalse(first.store.geometryBusy);XCTAssertNil(service.controller.scanCropOperationID)
    }
  }

}
