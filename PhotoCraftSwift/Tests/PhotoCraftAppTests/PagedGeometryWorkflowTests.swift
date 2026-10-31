import AppKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class PagedGeometryWorkflowTests:XCTestCase {
  @MainActor func testMaximumSparseGeometryMatchesDesktopAPIAndHistoryWithMasksAndChannels() async throws {
    var original=try CraftDocument(width:300000,height:200000,depth:.f32)
    var pixels=try Surface(width:300000,height:200000,depth:.f32,fill:.white).interpretingSamples(as:.linearRGB)
    pixels.setLinearPixel(x:299999,y:199999,Pixel(-0.0,4,-0.25,0.5))
    pixels.setLinearPixel(x:3,y:3,.clear)
    original.layers[0].content = .raster(pixels)
    original.layers[0].mask=try Surface(width:300000,height:200000,depth:.f32,fill:.white)
    var alpha=try Surface(width:300000,height:200000,depth:.f32,fill:.black)
    alpha.setPixel(x:299999,y:199999,.white)
    original.alphaChannels=[AlphaChannel(name:"Owned alpha",pixels:alpha)]
    original.selection = .init(x:100,y:200,width:30,height:40)
    try original.validate()
    let operations:[(String,[String:Any],Command)]=[
      ("document.rotate",["turn":"clockwise"],.rotateCanvas(.clockwise)),
      ("document.resize",["width":150000,"height":100000,"method":"nearest","resolution":144],.imageSize(150000,100000,144,.nearest)),
      ("document.resolution",["resolution":300],.resolution(300))]
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      try service.share(document)
      for (name,parameters,command) in operations {
        document.store.session=EditorSession(document:original)
        var desktop=EditorSession(document:original);try desktop.execute(command)
        let status=try await helper.edit(service,document,name,parameters);XCTAssertEqual(status,200,name)
        await document.store.renderTask?.value
        XCTAssertNil(document.store.error)
        XCTAssertEqual(document.store.document,desktop.document,name)
        XCTAssertEqual(document.store.session.undoStack.count,1)
        let changed=document.store.document
        let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
        await document.store.renderTask?.value;XCTAssertNil(document.store.error)
        let redo=try await helper.edit(service,document,"history.redo");XCTAssertEqual(redo,200);XCTAssertEqual(document.store.document,changed)
        await document.store.renderTask?.value;XCTAssertNil(document.store.error)
      }
      document.store.session=EditorSession(document:original)
      let stale=try await helper.edit(service,document,"document.rotate",["turn":"clockwise"],revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"document.rotate",["turn":"clockwise"]);XCTAssertEqual(busy,409)
      document.store.geometryBusy=false;XCTAssertEqual(document.store.document,original)
      let metadata=try XCTUnwrap(GeometryAPI.capabilities["largeRGB"]as?[String:Any])
      XCTAssertEqual(metadata["maximumPixels"]as?Int,90_000_000_000)
      XCTAssertEqual(metadata["maximumPatchPixels"]as?Int,131072)
      XCTAssertEqual(metadata["exactGridPermutations"]as?Bool,true)
    }
  }
  @MainActor func testMaximumColouredCanvasGrowthSharesNativePixelsAndAPIPersistence() async throws {
    let original=try CraftDocument(width:2,height:2,depth:.u16),helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      try service.share(document);document.store.session=EditorSession(document:original)
      let parameters:[String:Any]=["width":300000,"height":300000,"anchor":"center","fill":[0.25,0.5,0.75,1]]
      let status=try await helper.edit(service,document,"document.canvasSize",parameters);XCTAssertEqual(status,200)
      await document.store.renderTask?.value;XCTAssertNil(document.store.error)
      XCTAssertEqual(document.store.document.width,300000)
      guard case .raster(let border)=document.store.document.layers[0].content else {return XCTFail("Raster extension")}
      XCTAssertEqual(border.pixel(x:0,y:0),Pixel(0.25,0.5,0.75,1).quantized(.u16))
      XCTAssertEqual(border.pixel(x:149999,y:149999),.clear);XCTAssertLessThan(document.store.document.estimatedBytes,16*1024*1024)
      let data=try NativeArchive.encodeChunked(document.store.document,minimumVersion:63)
      XCTAssertEqual(try NativeArchive.decodePaged(data),document.store.document)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200);XCTAssertEqual(document.store.document,original)
    }
  }
}
