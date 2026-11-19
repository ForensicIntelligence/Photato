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
      let mask = try XCTUnwrap(capabilities["pixelMaskFeather"] as? [String: Any])
      XCTAssertEqual(mask["maximumRadiusPixels"] as? Int, 1000)
      XCTAssertEqual(mask["maximumRetainedSampleBytesPerMask"] as? Int, 1_048_576)
    }
  }
  @MainActor func testLayerMaskFeatherHTTPAndDesktopShareTheWideRangeAndUndo() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      var original = try CraftDocument(width: 9, height: 7)
      var layer = Layer(name: "Editable mask", content: .raster(try Surface(width: 9, height: 7, fill: .white)))
      layer.mask = try Surface(width: 9, height: 7, fill: .white)
      var p = MaskProperties()
      p.outside = 1
      p.density = 0.64
      layer.maskProperties = p
      original.layers.append(layer)
      original.activeLayerID = layer.id
      let native = EditorStore(document: original)
      defer { native.renderTask?.cancel() }
      native.updateMask(layer.id) { $0.feather = 975.25 }
      XCTAssertNil(native.error)
      XCTAssertEqual(native.document.layers.last?.effectiveMaskProperties.feather, 975.25)
      document.store.session = EditorSession(document: original)
      try service.share(document)
      let response = try await helper.edit(service, document, "mask.feather",
        ["layerID": layer.id.uuidString, "radius": 975.25])
      XCTAssertEqual(response, 200)
      XCTAssertEqual(document.store.document, native.document)
      let rejected = try await helper.edit(service, document, "mask.feather",
        ["layerID": layer.id.uuidString, "radius": 1000.1])
      XCTAssertEqual(rejected, 400)
      XCTAssertEqual(document.store.document, native.document)
      let undo = try await helper.edit(service, document, "history.undo")
      XCTAssertEqual(undo, 200)
      XCTAssertEqual(document.store.document, original)
      let missing = try await helper.edit(service, document, "mask.feather",
        ["layerID": original.layers[0].id.uuidString, "radius": 500])
      XCTAssertEqual(missing, 422)
      let schema = MaskManagementAPI.schema("radius")
      XCTAssertEqual(schema["maximum"] as? Double, 1000)
    }
  }

}
