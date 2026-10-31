import AppKit
import ImageIO
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LargeCompositionWorkflowTests:XCTestCase {
  func fixture() throws -> CraftDocument {
    var d=try CraftDocument(width:300_000,height:300_000)
    let group=Layer(name:"Large group",content:.group(GroupContent(passThrough:true)))
    var layer=Layer(name:"Large pixels",content:.raster(try Surface(width:d.width,height:d.height,fill:Pixel(0.2,0.4,0.8))))
    layer.parentID=group.id
    var adjustment=Layer(name:"Invert",content:.adjustment(.invert));adjustment.opacity=0.25
    d.layers=[layer,adjustment,group];adjustment.parentID=group.id;d.layers[1]=adjustment
    d.activeLayerID=layer.id;try d.validate();return d
  }
  func pixels(_ data:Data) throws -> Surface {
    let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
    return try RasterIO.surface(XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil)))
  }
  @MainActor func testNativeMaximumGroupedViewPaintingHistoryAndPersistence() async throws {
    let initial=try fixture(),store=EditorStore(document:initial)
    defer {store.renderTask?.cancel()}
    store.updateViewport(size:CGSize(width:600,height:400),backingScale:1)
    store.render();await store.renderTask?.value
    XCTAssertNil(store.error);XCTAssertNotNil(store.image)
    XCTAssertEqual(store.canvasRasterPreview?.documentRegion,.init(x:0,y:0,width:300_000,height:300_000))
    XCTAssertLessThanOrEqual(try XCTUnwrap(store.image).width*XCTUnwrap(store.image).height,Renderer.maximumCompositionPatchPixels*32)
    let child=try XCTUnwrap(initial.activeLayerID);var brush=Brush();brush.size=5;brush.color = .white
    try store.executeEditorCommand(.stroke(child,[.init(x:299_995,y:299_995)],brush))
    await store.renderTask?.value;XCTAssertNil(store.error);XCTAssertNotEqual(store.document,initial)
    let changed=store.document;XCTAssertEqual(store.session.undoStack.count,1)
    let data=try NativeArchive.encode(changed);XCTAssertEqual(try NativeArchive.decodePaged(data),changed)
    await store.undo();await store.renderTask?.value;XCTAssertEqual(store.document,initial)
    await store.redo();await store.renderTask?.value;XCTAssertEqual(store.document,changed)
  }
  @MainActor func testHTTPGroupedOverviewUsesNativeRendererAndRetainsExistingGuards() async throws {
    let helper=AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) {service,document in
      let initial=try fixture();document.store.session=EditorSession(document:initial)
      document.store.updateViewport(size:CGSize(width:2088,height:2088),backingScale:1)
      document.store.setZoom(2048/300_000,center:true);try service.share(document)
      let share=try XCTUnwrap(service.shares.first),base="/v1/documents/\(share.id)"
      document.store.render();await document.store.renderTask?.value;XCTAssertNil(document.store.error)
      let preview=try await helper.request(service,path:base+"/preview.png")
      XCTAssertEqual(preview.0.statusCode,200)
      let api=try pixels(preview.1),native=try RasterIO.surface(XCTUnwrap(document.store.image))
      XCTAssertEqual(api.width,2048);XCTAssertEqual(api.height,2048);XCTAssertEqual(api,native)
      let params:[String:Any]=["points":[["x":299_995,"y":299_995]],"brush":["size":5,"color":["r":1,"g":0,"b":0,"a":1]]]
      let stale=try await helper.edit(service,document,"paint.stroke",params,revision:"stale");XCTAssertEqual(stale,409)
      document.store.geometryBusy=true
      let busy=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(busy,409)
      document.store.geometryBusy=false
      let edited=try await helper.edit(service,document,"paint.stroke",params);XCTAssertEqual(edited,200)
      XCTAssertNotEqual(document.store.document,initial)
      let undo=try await helper.edit(service,document,"history.undo");XCTAssertEqual(undo,200)
      XCTAssertEqual(document.store.document,initial)
      let capabilities=try XCTUnwrap(RasterStorageAPI.capabilities["pagedComposition"]as?[String:Any])
      XCTAssertEqual(capabilities["maximumPatchPixels"]as?Int,131_072)
      XCTAssertEqual(capabilities["maximumDerivedMaskCacheBytes"]as?Int,512*1024*1024)
    }
  }
}
