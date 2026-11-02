import AppKit
import ImageIO
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeCanvasWorkflowTests: XCTestCase {
  @MainActor func testMaximumNewDocumentViewportDisplayAndRecoveryAdmission() async throws {
    let model = try CraftNSDocument.blankModel(width:300_000,height:300_000,mode:.rgb)
    let store = EditorStore(document:model)
    defer { store.renderTask?.cancel() }
    store.updateViewport(size:CGSize(width:1000,height:700),backingScale:2)
    store.render();await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image)
    XCTAssertLessThanOrEqual((store.image?.width ?? 0) * (store.image?.height ?? 0),4_194_304)
    XCTAssertEqual(store.canvasRasterPreview?.documentRegion,.init(x:0,y:0,width:300_000,height:300_000))
    XCTAssertLessThan(store.effectiveZoom,0.01)
    XCTAssertLessThan(RecoveryMemoryPolicy.documentCost(model),200*1024*1024)
    store.setZoom(1,center:true);await store.renderTask?.value
    let before = try XCTUnwrap(store.canvasRasterPreview?.documentRegion)
    XCTAssertLessThan(before.width,3000);XCTAssertGreaterThan(before.x,100_000)
    store.pan.width += 100;await store.renderTask?.value
    XCTAssertNotEqual(store.canvasRasterPreview?.documentRegion,before)
    XCTAssertEqual(CanvasViewport.parsePercentage("0.01%"),0.0001)
    store.channelView.selectPreview(.red);store.render();await store.renderTask?.value
    XCTAssertEqual(store.canvasRasterPreview?.documentRegion,store.viewport.largeCanvasRequest.region)
    // Format admission does not qualify physical maximum-size PSB writing.
    XCTAssertEqual(DocumentIO.Format.allCases.filter { DocumentIO.persistenceIssue(model,format:$0) == nil },[.native,.psb])
  }
  @MainActor func testHTTPMaximumCanvasBrushHistoryPreviewAndStaleness() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service, document in
      let original = try CraftNSDocument.blankModel(width:300_000,height:300_000,mode:.rgb)
      document.store.session = EditorSession(document:original);try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let limits = try XCTUnwrap(AutomationService.capabilities["limits"] as? [String:Any])
      XCTAssertEqual(limits["maxCanvasPixels"] as? Int,90_000_000_000)
      let params:[String:Any] = ["points":[["x":299_994,"y":299_994],["x":299_999,"y":299_999]],"brush":["size":9,"color":["r":1,"g":0,"b":0,"a":1]]]
      let stale = try await helper.edit(service,document,"paint.stroke",params,revision:"stale");XCTAssertEqual(stale,409)
      XCTAssertEqual(document.store.document,original)
      let accepted = try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(accepted,200)
      XCTAssertNotEqual(document.store.document,original);XCTAssertEqual(document.store.session.undoStack.count,1)
      let response = try await helper.request(service,path:"/v1/documents/\(id)/preview.png")
      XCTAssertEqual(response.0.statusCode,200)
      let input = try XCTUnwrap(CGImageSourceCreateWithData(response.1 as CFData,nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(input,0,nil))
      XCTAssertEqual(image.width,2048);XCTAssertEqual(image.height,2048)
      service.setDocumentTransfersEnabled(true)
      let legacy = try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"62"])
      XCTAssertEqual(legacy.0.statusCode,422,"Explicit Background requires native83 or later; an old transfer header must not silently lose its semantics.")
      let download = try await helper.request(service,path:"/v1/documents/\(id)/file.photato",headers:["X-Photato-Archive-Version":"84"])
      XCTAssertEqual(download.0.statusCode,200)
      XCTAssertEqual(try NativeArchive.decode(download.1),document.store.document)
      let undo = try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
    }
  }
}
