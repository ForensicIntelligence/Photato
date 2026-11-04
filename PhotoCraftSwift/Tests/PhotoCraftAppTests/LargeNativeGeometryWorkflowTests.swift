import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeNativeGeometryWorkflowTests:XCTestCase {
  @MainActor func testMaximumHTTPRotateResizeUndoAndNativeExport() async throws {
    let helper=AutomationTests(),files=DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try NativeGeometryFixture.make()
      document.store.session=EditorSession(document:original)
      try service.share(document);service.setDocumentTransfersEnabled(true)
      let share=try XCTUnwrap(service.shares.first)
      let stale=try await helper.edit(service,document,"document.rotate",["turn":"clockwise"],revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,original)
      let status=try await helper.edit(service,document,"document.rotate",["turn":"clockwise"])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document.layers[0].nativeMode?.rawWord(component:3,index:299999*300000),49151)
      let saved=try await files.request(service,path:"/v1/documents/\(share.id)/file.photato",headers:["X-Photato-Archive-Version":"86"])
      XCTAssertEqual(saved.0.statusCode,200)
      XCTAssertEqual(try NativeArchive.decodePaged(saved.1),document.store.document)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200)
      XCTAssertEqual(document.store.document,original)
      let resize=try await helper.edit(service,document,"document.resize",["width":150000,"height":150000,"method":"nearest","resolution":144])
      XCTAssertEqual(resize,200);XCTAssertEqual(document.store.document.width,150000)
      XCTAssertEqual(document.store.document.layers[0].nativeMode?.rawWord(component:3,index:22_500_000_000-1),49151)
      let undoSize=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undoSize,200);XCTAssertEqual(document.store.document,original)
      let caps=try XCTUnwrap(GeometryAPI.capabilities["largeNativeComponents"] as? [String:Any])
      XCTAssertEqual(caps["maximumPixels"] as? Int,90_000_000_000)
      XCTAssertEqual(caps["maximumResidentWriteCacheBlocksPerPlane"] as? Int,64)
    }
  }
  @MainActor func testPreparedMaximumTrimMatchesDesktopAndRejectsStale() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let original=try NativeGeometryFixture.make();document.store.session=EditorSession(document:original);try service.share(document)
      var native=EditorSession(document:original)
      try native.execute(CanvasEdgePreparation.command(original,operation:.trim(.init(basis:.transparent))))
      let stale=try await helper.edit(service,document,"document.trim",["basis":"transparent"],revision:"stale")
      XCTAssertEqual(stale,409);XCTAssertEqual(document.store.document,original)
      let status=try await helper.edit(service,document,"document.trim",["basis":"transparent"])
      XCTAssertEqual(status,200);XCTAssertEqual(document.store.document,native.document)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
    }
  }
}
private enum NativeGeometryFixture {
  static func make() throws -> CraftDocument {
    var d=try DocumentCreation.blank(width:300000,height:300000,depth:.u16,background:.clear,mode:.cmyk)
    var n=try XCTUnwrap(d.layers[0].nativeMode);try n.set(0.75,component:3,index:90_000_000_000-1);try n.set(1,component:4,index:90_000_000_000-1)
    d.layers[0].nativeMode=n;d.layers[0].content = .raster(try n.surface());return d
  }
}
