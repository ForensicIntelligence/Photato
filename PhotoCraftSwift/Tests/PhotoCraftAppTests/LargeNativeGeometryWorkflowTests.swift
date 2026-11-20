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

  @MainActor func testMultichannelHTTPGeometryPreservesExactPlatesAndUndo() async throws {
    let helper = AutomationTests()
    let files = DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let width = 300_000, height = 31
      let plane = try InkPlane(width: width, height: height, depth: .u16, value: 0.25)
        .replacing(offset: 0, values: [Float(1) / 65535])
        .replacing(offset: width * height - 1, values: [1])
      let plate = InkPlate(name: "Black ink", color: .black, samples: plane)
      let source = try CraftDocument(width: width, height: height, depth: .u16)
        .replacingInkMode(.multichannel(.init(plates: [plate])))
      document.store.session = EditorSession(document: source)
      try service.share(document)
      service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first)
      let stale = try await helper.edit(service, document, "document.rotate", ["turn": "clockwise"], revision: "stale")
      XCTAssertEqual(stale, 409)
      XCTAssertEqual(document.store.document, source)

      let rotated = try await helper.edit(service, document, "document.rotate", ["turn": "clockwise"])
      XCTAssertEqual(rotated, 200)
      var expected = EditorSession(document: source)
      try expected.execute(.rotateCanvas(.clockwise))
      XCTAssertEqual(document.store.document, expected.document)
      XCTAssertEqual(try document.store.document.inkChannel(.plate(plate.id)).rawWord(at: height - 1), 1)
      let data = try await files.request(service, path: "/v1/documents/\(share.id)/file.photato",
        headers: ["X-Photato-Archive-Version": "93"])
      XCTAssertEqual(data.0.statusCode, 200)
      XCTAssertEqual(try NativeArchive.decodePaged(data.1), expected.document)

      let undo = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document, source)
      let resized = try await helper.edit(service, document, "document.resize",
        ["width": width, "height": 29, "method": "bicubic", "resolution": 144])
      XCTAssertEqual(resized, 200)
      try expected.undo()
      try expected.execute(.imageSize(width, 29, 144, .bicubic))
      XCTAssertEqual(document.store.document, expected.document)
      let crop = try await helper.edit(service, document, "document.crop",
        ["x": 1, "y": 0, "width": width - 1, "height": 29])
      XCTAssertEqual(crop, 200)
      let request = CropRequest(x: 1, y: 0, width: width - 1, height: 29)
      XCTAssertEqual(document.store.document, try CropGeometry.applying(request, to: expected.document))
      let undoCrop = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undoCrop, 200)
      XCTAssertEqual(document.store.document, expected.document)

      let capabilities = try XCTUnwrap(GeometryAPI.capabilities["largeMultichannel"] as? [String: Any])
      XCTAssertEqual(capabilities["maximumPixels"] as? Int, 90_000_000_000)
      XCTAssertEqual(capabilities["nativeArchiveVersion"] as? Int, 93)
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
