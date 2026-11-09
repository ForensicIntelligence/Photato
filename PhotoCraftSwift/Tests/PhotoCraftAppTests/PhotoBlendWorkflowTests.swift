import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor BlendFixtureTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("Fixture uses hosted output.") }
}
final class PhotoBlendWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8,focus: Bool = false) throws -> CraftDocument {
    var d = try CraftDocument(width:64,height:40,depth:depth);d.layers = []
    for k in 0..<2 {
      let w = focus ? 64:40
      var pixels = try Surface(width:w,height:40,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<40 { for x in 0..<w {
        let sharp = focus && (k == 0 ? x < 32:x >= 32)
        let v: Float = focus ? (sharp ? ((x/2+y/2)%2 == 0 ? 0.1:0.9):0.5) : (k == 0 ? 0.2:0.8)
        let p = Pixel(v,v,v,1)
        if depth == .f32 { pixels.setLinearPixel(x:x,y:y,p) } else { pixels.setPixel(x:x,y:y,p) }
      } }
      var layer = Layer(name:"Photo \(k+1)",content:.raster(pixels));layer.x = focus ? 0:k*24;d.layers.append(layer)
    }
    d.activeLayerID = d.layers[1].id;return d
  }
  func ids(_ d: CraftDocument) -> Set<UUID> { Set(d.layers.map(\.id)) }
  func testPyramidTranslationMatchesIndependentOriginalRustFixture() throws {
    let bytes = try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/PhotoBlend/pyramid.bin"))
    let expected = stride(from:0,to:bytes.count,by:4).map { i in
      Float(bitPattern:UInt32(bytes[i]) | UInt32(bytes[i+1])<<8 | UInt32(bytes[i+2])<<16 | UInt32(bytes[i+3])<<24)
    }
    let px = (0..<37*23*3).map { Float($0*37%101)/101 }
    let base = PhotoPyramid.Level(width:37,height:23,pixels:px)
    let g = try PhotoPyramid.gaussian(base,channels:3,levels:5),lp = try PhotoPyramid.laplacian(base,channels:3,levels:5)
    let actual = g[1].pixels+lp[0].pixels+(try PhotoPyramid.collapse(lp,channels:3))
    XCTAssertEqual(actual.count,expected.count)
    XCTAssertLessThan(zip(actual,expected).map { abs($0-$1) }.max()!,0.000001)
  }
  func testFocusStackChoosesSharpPlanesAtEveryDepthAndPreservesOriginalPixels() throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth,focus:true);var settings = PhotoBlendSettings();settings.method = .stack;settings.fillTransparentAreas = false;settings.seamlessTones = false
      let result = try PhotoBlend.prepare(d,layerIDs:ids(d),settings:settings).result
      XCTAssertEqual(result.layers.count,2)
      XCTAssertEqual(result.layers[0].mask?.pixel(x:4,y:20).r,1);XCTAssertEqual(result.layers[1].mask?.pixel(x:60,y:20).r,1)
      XCTAssertEqual(result.layers[0].mask?.pixel(x:60,y:20).r,0)
      for i in d.layers.indices { XCTAssertTrue(result.layers[i].content == d.layers[i].content,"Source pixels changed") }
      let composite = try Renderer.composite(result)
      XCTAssertGreaterThan(abs(composite.linearPixel(x:4,y:20).r-composite.linearPixel(x:6,y:20).r),0.4)
      XCTAssertGreaterThan(abs(composite.linearPixel(x:60,y:20).r-composite.linearPixel(x:62,y:20).r),0.4)
    }
  }
  func testPanoramaSeamsMultibandAndMasksAvoidBlackEdges() throws {
    let d = try fixture();var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
    let result = try PhotoBlend.prepare(d,layerIDs:ids(d),settings:settings).result
    XCTAssertEqual(result.layers.count,2);XCTAssertTrue(result.layers.allSatisfy(\.visible))
    let output = try Renderer.composite(result)
    XCTAssertEqual(output.pixel(x:0,y:20).r,0.2,accuracy:0.015);XCTAssertEqual(output.pixel(x:63,y:20).r,0.8,accuracy:0.015)
    XCTAssertGreaterThan(output.pixel(x:31,y:20).r,0.25);XCTAssertLessThan(output.pixel(x:31,y:20).r,0.75)
    XCTAssertEqual(result.layers.map(\.id),d.layers.map(\.id));XCTAssertEqual(result.layers.map(\.name),d.layers.map(\.name))
    XCTAssertNotEqual(result.layers[0].content,d.layers[0].content)
    let left = try MaskSampler(layer:result.layers[0]),right = try MaskSampler(layer:result.layers[1])
    XCTAssertEqual(left.coverage(x:4.5,y:20.5),1);XCTAssertEqual(right.coverage(x:60.5,y:20.5),1)
  }
  func testHDRAlphaExistingMasksAndSelectionPreserved() throws {
    var d = try fixture(.f32,focus:true)
    for i in d.layers.indices {
      var pixels = try Surface(width:64,height:40,depth:.f32,colorEncoding:.linearRGB)
      for y in 0..<40 { for x in 0..<64 { pixels.setLinearPixel(x:x,y:y,Pixel(1.4,-0.1,0.8,0.5)) } }
      d.layers[i].content = .raster(pixels)
    }
    d.layers[0].mask = try Surface(width:64,height:40,fill:Pixel(0.6,0.6,0.6))
    d.selection = IntRect(x:12,y:8,width:8,height:8)
    var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
    let result = try PhotoBlend.prepare(d,layerIDs:ids(d),settings:settings).result
    XCTAssertEqual(result.selection,d.selection)
    XCTAssertEqual(result.layers.count,2);XCTAssertTrue(result.layers.allSatisfy(\.visible))
    let out = try Renderer.composite(result)
    let p = out.linearPixel(x:20,y:20);XCTAssertEqual(p.r,1.4,accuracy:0.0001);XCTAssertEqual(p.g,-0.1,accuracy:0.0001);XCTAssertEqual(p.a,0.3,accuracy:0.003)
    XCTAssertEqual(try Renderer.composite(result).linearPixel(x:20,y:20).a,p.a,accuracy:0.0001)
  }
  func testTransparentAreaFillAndUndoPersistence() throws {
    var d = try fixture();d.layers[0].mask = try Surface(width:40,height:40,fill:.white)
    for y in 16..<20 { for x in 8..<12 { d.layers[0].mask?.setPixel(x:x,y:y,.black) } }
    let edit = try PhotoBlend.prepare(d,layerIDs:ids(d),settings:.init())
    var session = EditorSession(document:d);try session.execute(.photoBlend(edit))
    XCTAssertEqual(try Renderer.composite(session.document).linearPixel(x:9,y:17).a,1)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)) == session.document)
    let psd = try PSDCodec.writeRasterLayers(session.document),reopened = try PSDCodec.read(psd)
    XCTAssertEqual(reopened.layers.count,3);XCTAssertNotNil(reopened.layers[0].mask)
    try session.undo();XCTAssertTrue(session.document == d);try session.redo();XCTAssertTrue(session.document == edit.result)
    var stale = d;stale.name += " changed";XCTAssertThrowsError(try edit.applied(to:stale))
  }
  func testGuardsAndCancellationDoNotMutate() async throws {
    let d = try fixture()
    XCTAssertThrowsError(try PhotoBlend.prepare(d,layerIDs:[d.layers[0].id],settings:.init()))
    var locked = d;locked.layers[0].protection = [.transparency];XCTAssertThrowsError(try PhotoBlend.prepare(locked,layerIDs:ids(locked),settings:.init()))
    var empty = d;empty.layers[0].x = 1000;XCTAssertThrowsError(try PhotoBlend.prepare(empty,layerIDs:ids(empty),settings:.init()))
    var styled = d;styled.layers[0].opacity = 0.5;XCTAssertThrowsError(try PhotoBlend.prepare(styled,layerIDs:ids(styled),settings:.init()))
    let selected = ids(d),task = Task { () throws -> PhotoBlendEdit in try Task.checkCancellation();return try PhotoBlend.prepare(d,layerIDs:selected,settings:.init()) }
    task.cancel();do { _ = try await task.value;XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
  }
  @MainActor func testNativeDialogPreviewCancelCommitAndHistory() async throws {
    _ = NSApplication.shared
    let d = try fixture(),store = EditorStore(document:d);store.selectedLayerIDs = ids(d)
    defer { store.renderTask?.cancel();store.cancelPhotoBlend() }
    XCTAssertTrue(store.canBeginPhotoBlend);store.beginPhotoBlend();let model = try XCTUnwrap(store.photoBlendDraft)
    XCTAssertTrue(store.hasToneDraft);model.refresh();await model.task?.value;XCTAssertTrue(model.ready,model.error ?? "not ready");XCTAssertTrue(store.document == d)
    let view = NSHostingView(rootView:PhotoBlendSheet(store:store,model:model));view.frame = NSRect(x:0,y:0,width:760,height:460);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,0)
    store.cancelPhotoBlend();XCTAssertTrue(store.document == d)
    store.beginPhotoBlend();let final = try XCTUnwrap(store.photoBlendDraft);final.settings.seamlessTones = false;final.settings.fillTransparentAreas = false;final.refresh();await final.task?.value
    let expected = try XCTUnwrap(final.edit).result;store.commitPhotoBlend();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertEqual(store.selectedLayerIDs,ids(d));XCTAssertTrue(store.document == expected);await store.undo();XCTAssertTrue(store.document == d);await store.redo();XCTAssertTrue(store.document == expected)
  }
  @MainActor func testPhotatoHTTPUsesSameEngineAndRejectsInvalidBusyStale() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      try service.share(shared);let d = try fixture();shared.store.session = EditorSession(document:d)
      let params: [String:Any] = ["layerIDs":d.layers.map{$0.id.uuidString},"settings":["method":"panorama","fillTransparentAreas":false]]
      var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
      let expected = try PhotoBlend.prepare(d,layerIDs:ids(d),settings:settings).result
      let status = try await helper.edit(service,shared,"photo.autoBlend",params);XCTAssertEqual(status,200)
      XCTAssertEqual(try Renderer.composite(shared.store.document),try Renderer.composite(expected))
      XCTAssertEqual(shared.store.document.layers.count,2)
      XCTAssertTrue(shared.store.document.layers.allSatisfy { $0.visible && $0.mask != nil })
      XCTAssertEqual(shared.store.selectedLayerIDs,ids(d))
      let undo = try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(shared.store.document == d)
      let stale = try await helper.edit(service,shared,"photo.autoBlend",params,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.selectedLayerIDs = ids(d);shared.store.beginPhotoBlend()
      let busy = try await helper.edit(service,shared,"photo.autoBlend",params);XCTAssertEqual(busy,409);shared.store.cancelPhotoBlend()
      var bad = params;bad["settings"] = ["seamlessTones":1]
      let invalid = try await helper.edit(service,shared,"photo.autoBlend",bad);XCTAssertEqual(invalid,400);XCTAssertTrue(shared.store.document == d)
      let raw = try XCTUnwrap(AutomationCommand.definitions.first{$0.name == "raw.develop"})
      let properties = (raw.schema["properties"] as! [String:Any])["parameters"] as! [String:Any]
      let fields = properties["properties"] as! [String:Any],schema = fields["settings"] as! [String:Any]
      XCTAssertNotNil((schema["properties"] as? [String:Any])?["decoderVersion"])
    }
  }
  @MainActor func testInstalledPhotoshopPanoramaDescriptorThroughBothJobAPIs() async throws {
    let d = try fixture(),input = try PSDCodec.writeRasterLayers(d)
    let action = #"[{"_obj":"selectAllLayers","_target":[{"_ref":"layer","_enum":"ordinal","_value":"targetEnum"}]},{"_obj":"mergeAlignedLayers","$Aply":{"_enum":"autoBlendType","_value":"panorama"},"$ClrC":true,"autoTransparencyFill":false}]"#
    let decoded = try PSDCodec.read(input)
    let expected = try PhotoshopActionProgram(actionJSON:action).applying(to:decoded).session.document
    var settings = PhotoBlendSettings();settings.fillTransparentAreas = false
    let maskOnly = try PhotoshopActionProgram(actionJSON:action.replacingOccurrences(of:"\"$ClrC\":true",with:"\"$ClrC\":false")).applying(to:decoded)
    XCTAssertEqual(maskOnly.selectedLayerIDs,ids(decoded))
    let desktop = try PhotoBlend.prepare(decoded,layerIDs:ids(decoded),settings:settings).result
    XCTAssertEqual(try Renderer.composite(expected),try Renderer.composite(desktop))
    XCTAssertEqual(expected.layers.count,2);XCTAssertTrue(expected.layers.allSatisfy { $0.visible && $0.mask != nil })
    let body: [String:Any] = ["image":["source":["url":"https://example.test/input.psd"]],"options":["actions":[["source":["content":action,"contentType":"application/json"]]]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:BlendFixtureTransport(input)) { service,shared in
      service.setResourceJobsEnabled(true);let before = shared.store.document
      for path in ["/v1/action-jobs","/v2/execute-actions"] {
        let output = try await AutomationActionJobsTests().output(service,submit:path,payload:body,expectedMediaType:"image/png")
        XCTAssertEqual(output.2,try DocumentIO.encode(expected,format:.png))
      }
      XCTAssertTrue(shared.store.document == before)
    }
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:action.replacingOccurrences(of:"panorama",with:"stackImages")))
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:action.replacingOccurrences(of:"\"$ClrC\":true",with:"\"$ClrC\":1")))
  }
}
