import AppKit
import ImageIO
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeChannelPresentationWorkflowTests: XCTestCase {
  @MainActor func fixture(_ side: Int = 8192) throws -> CraftDocument {
    var doc = try CraftNSDocument.blankModel(width:side,height:side,background:Pixel(0.2,0.4,0.8))
    doc.layers[0].mask = try Surface(width:side,height:side,depth:.f32,fill:Pixel(0.25,1,0,0))
    var properties=MaskProperties();properties.enabled=false;properties.density=0;properties.feather=20
    doc.layers[0].maskProperties=properties
    var options=ChannelDisplayOptions();options.indicates = .selectedAreas;options.color=Pixel(0,1,0)
    doc.alphaChannels=[AlphaChannel(name:"Numeric alpha",pixels:try Surface(width:side,height:side,depth:doc.depth,fill:Pixel(0.25,0,0,0)),options:options)]
    return doc
  }
  func image(_ data: Data) throws -> CGImage {
    let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
  }

  @MainActor func testMaximumNativeAuxiliaryQuickMaskAndRegionalMaskViewsPreservePixels() async throws {
    let initial=try fixture(300_000),store=EditorStore(document:initial)
    defer {store.renderTask?.cancel()}
    store.updateViewport(size:CGSize(width:128,height:96),backingScale:1);store.setZoom(1,center:true)
    let channel=try XCTUnwrap(initial.alphaChannels?.first)
    for overlay in [false,true] {
      try store.selectAlphaChannel(channel.id,overlay:overlay);await store.renderTask?.value
      XCTAssertNil(store.error);XCTAssertNotNil(store.image)
      XCTAssertEqual(store.canvasRasterPreview?.documentRegion,store.viewport.largeCanvasRequest.region)
      XCTAssertLessThanOrEqual(try XCTUnwrap(store.image).width*XCTUnwrap(store.image).height,RasterPreviewRequest.maximumPixels)
      XCTAssertEqual(store.document,initial);XCTAssertTrue(store.session.undoStack.isEmpty)
    }
    try store.selectEditingChannel(.composite)
    store.toggleMaskView(initial.layers[0].id,mode:.gray);await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.displayedMaskImage)
    XCTAssertEqual(store.maskViewRegion,store.viewport.largeCanvasRequest.region)
    let before=store.maskViewRegion
    store.pan.width += 32;await store.renderTask?.value
    XCTAssertNotEqual(store.maskViewRegion,before)
    XCTAssertEqual(try RasterIO.surface(XCTUnwrap(store.displayedMaskImage)).pixel(x:0,y:0).r,64/255)
    store.clearMaskView();try store.selectEditingChannel(.composite)
    store.toggleQuickMask();await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image);XCTAssertNotNil(store.document.quickMask)
    XCTAssertEqual(store.document.layers,initial.layers)
    store.toggleQuickMask();await store.renderTask?.value
    XCTAssertNil(store.document.quickMask);XCTAssertNil(store.error)
    XCTAssertEqual(store.document,initial)
  }

  @MainActor func testHTTPAlphaRGBQuickMaskAndMaskResourcesMatchNativeAndPreserveState() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let initial=try fixture();document.store.session=EditorSession(document:initial)
      document.store.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1)
      document.store.setZoom(0.25,center:true);try service.share(document)
      let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)",channel=try XCTUnwrap(initial.alphaChannels?.first)
      let saved=try NativeArchive.encode(initial)
      for overlay in [false,true] {
        let selected=try await helper.edit(service,document,"channel.view",["target":channel.id.uuidString,"overlay":overlay])
        XCTAssertEqual(selected,200);await document.store.renderTask?.value;XCTAssertNil(document.store.error)
        let response=try await helper.request(service,path:base+"/channel-preview.png")
        XCTAssertEqual(response.0.statusCode,200)
        XCTAssertEqual(try RasterIO.surface(image(response.1)),try RasterIO.surface(XCTUnwrap(document.store.image)))
      }
      let rgb=try await helper.edit(service,document,"channel.view",["target":"RGB"]);XCTAssertEqual(rgb,200)
      let red=try await helper.edit(service,document,"view.channelPreview",["channel":"Red"]);XCTAssertEqual(red,200)
      await document.store.renderTask?.value
      let redResponse=try await helper.request(service,path:base+"/channel-preview.png")
      XCTAssertEqual(redResponse.0.statusCode,200)
      XCTAssertEqual(try RasterIO.surface(image(redResponse.1)),try RasterIO.surface(XCTUnwrap(document.store.image)))
      try document.store.selectEditingChannel(.composite)
      for (path,mode) in [("mask-gray.png",MaskViewMode.gray),("mask-overlay.png",.overlay)] {
        document.store.toggleMaskView(initial.layers[0].id,mode:mode);await document.store.renderTask?.value
        let response=try await helper.request(service,path:base+"/layers/\(initial.layers[0].id)/"+path)
        XCTAssertEqual(response.0.statusCode,200)
        XCTAssertEqual(try RasterIO.surface(image(response.1)),try RasterIO.surface(XCTUnwrap(document.store.displayedMaskImage)))
      }
      document.store.clearMaskView()
      try document.store.selectEditingChannel(.composite)
      XCTAssertEqual(try NativeArchive.encode(document.store.document),saved)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let enter=try await helper.edit(service,document,"channel.edit",["action":"quickMask","enabled":true]);XCTAssertEqual(enter,200)
      await document.store.renderTask?.value
      let quick=try await helper.request(service,path:base+"/channel-preview.png");XCTAssertEqual(quick.0.statusCode,200)
      XCTAssertEqual(try RasterIO.surface(image(quick.1)),try RasterIO.surface(XCTUnwrap(document.store.image)))
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200)
      XCTAssertEqual(document.store.document,initial)
      service.previewBusy=true
      let busy=try await helper.request(service,path:base+"/layers/\(initial.layers[0].id)/mask-gray.png")
      XCTAssertEqual(busy.0.statusCode,429);service.previewBusy=false
      let absent=try await helper.request(service,path:base+"/layers/\(UUID())/mask-gray.png");XCTAssertEqual(absent.0.statusCode,404)
      let unauthorized=try await helper.request(service,path:base+"/layers/\(initial.layers[0].id)/mask-gray.png",authenticate:false)
      XCTAssertEqual(unauthorized.0.statusCode,401)
      XCTAssertEqual(document.store.document,initial)
    }
  }

  @MainActor func testMaskResourceRejectsRevocationAndCancellationDuringWorker() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let initial=try fixture(300_000);document.store.session=EditorSession(document:initial);try service.share(document)
      let share=try XCTUnwrap(service.shares.first),path="/v1/documents/\(share.id)/layers/\(initial.layers[0].id)/mask-gray.png"
      let request=Task {try await helper.request(service,path:path)}
      let deadline=Date().addingTimeInterval(5)
      while !service.previewBusy && Date()<deadline {await Task.yield()}
      XCTAssertTrue(service.previewBusy);service.revoke(share.id)
      let rejected=try await request.value;XCTAssertEqual(rejected.0.statusCode,409)
      XCTAssertFalse(service.previewBusy);XCTAssertEqual(document.store.document,initial)
      try service.share(document);let newShare=try XCTUnwrap(service.shares.first)
      let cancelled=Task {try await service.maskPreview(document,shareID:newShare.id,layerID:initial.layers[0].id,mode:.overlay)}
      let cancellationDeadline=Date().addingTimeInterval(5)
      while !service.previewBusy && Date()<cancellationDeadline {await Task.yield()}
      XCTAssertTrue(service.previewBusy);cancelled.cancel()
      do {_ = try await cancelled.value;XCTFail("Cancelled mask resource accepted")}catch {}
      XCTAssertFalse(service.previewBusy);XCTAssertEqual(document.store.document,initial)
    }
  }
}
