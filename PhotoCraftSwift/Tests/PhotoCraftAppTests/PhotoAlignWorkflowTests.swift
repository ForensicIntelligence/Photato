import AppKit
import SwiftUI
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private actor AlignFixtureTransport: AdobeResourceTransport {
  let data: Data
  init(_ data: Data) { self.data = data }
  func fetch(_ url: URL) async throws -> Data { data }
  func upload(_ data: Data,output: AdobeActionsRequest.Output) async throws { throw AdobeAPIError.unsupported("Fixture uses hosted output.") }
}
final class PhotoAlignWorkflowTests: XCTestCase {
  func texture() throws -> [Float] {
    let bytes = try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/PhotoAlign/texture.bin"))
    return stride(from:0,to:bytes.count,by:4).map { i in Float(bitPattern:UInt32(bytes[i]) | UInt32(bytes[i+1])<<8 | UInt32(bytes[i+2])<<16 | UInt32(bytes[i+3])<<24) }
  }
  func fixture(_ depth: PixelDepth = .u8,shift: Bool = true) throws -> CraftDocument {
    let values = try texture();var d = try CraftDocument(width:300,height:230,depth:depth);d.layers = []
    for k in 0..<2 {
      var pixels = try Surface(width:256,height:192,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
      for y in 0..<192 { for x in 0..<256 {
        let sx = x+(k == 1 && shift ? 18:0),sy = y-(k == 1 && shift ? 9:0)
        guard sx < 256,sy >= 0 else { continue };let value = values[sy*256+sx],p = Pixel(value,value,value,1)
        if depth == .f32 { pixels.setLinearPixel(x:x,y:y,p) } else { pixels.setPixel(x:x,y:y,p) }
      } }
      var layer = Layer(name:"Photo \(k+1)",content:.raster(pixels));layer.x = k == 0 ? 10:-25;layer.y = k == 0 ? 12:25;d.layers.append(layer)
    };d.activeLayerID = d.layers[1].id;return d
  }
  func ids(_ d: CraftDocument) -> Set<UUID> { Set(d.layers.map(\.id)) }
  func testFeaturesMatchIndependentRustCornersAndDescriptors() throws {
    let values = try texture(),corners = try PhotoFeatures.harris(256,192,values,spacing:3),desc = try PhotoFeatures.describe(256,192,values,corners)
    let expected = try JSONSerialization.jsonObject(with:Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/PhotoAlign/corners.json"))) as! [[Any]]
    XCTAssertEqual(corners.count,expected.count)
    for i in 0..<min(corners.count,expected.count) {
      XCTAssertEqual(corners[i].x,(expected[i][0] as! NSNumber).floatValue);XCTAssertEqual(corners[i].y,(expected[i][1] as! NSNumber).floatValue)
      XCTAssertEqual(corners[i].score,(expected[i][2] as! NSNumber).floatValue,accuracy:0.000001)
      XCTAssertEqual(desc[i].map{String(format:"%016llx",$0)}.joined(),expected[i][3] as? String)
    }
  }
  func testRobustMotionModelsRecoverKnownTransformsWithOutliers() throws {
    let points = (0..<40).map{PhotoPoint(Double($0%8)*21+7,Double($0/8)*31+11)}
    let models: [(PhotoMotion,PhotoHomography)] = [(.translation,.translation(18,-9)),(.euclidean,PhotoMotion.euclidean.matrix([0.17,8,-13])),(.similarity,PhotoMotion.similarity.matrix([1.1,0.08,8,-13])),(.homography,PhotoHomography([1.03,0.08,17,-0.04,0.98,-6,0.0007,-0.0003,1]))]
    for (motion,expected) in models {
      var destination = points.map{expected.apply($0)};for i in 0..<8 { destination[i] += PhotoPoint(83,-61) }
      let (actual,inliers) = try XCTUnwrap(motion.ransac(points,destination,iterations:600,threshold:0.01,seed:175))
      XCTAssertEqual(inliers.count,32)
      for p in points { let a = actual.apply(p),e = expected.apply(p);XCTAssertEqual(a.x,e.x,accuracy:0.00001);XCTAssertEqual(a.y,e.y,accuracy:0.00001) }
    }
  }
  func testAllProjectionModelsAndCurvedInverseGeometry() throws {
    let d = try fixture(shift:false)
    for projection in PhotoAlignSettings.Projection.allCases {
      var settings = PhotoAlignSettings();settings.projection = projection
      let edit = try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings)
      XCTAssertGreaterThan(edit.matchedPoints,40);XCTAssertLessThan(edit.rmsPixels,0.05)
      XCTAssertEqual(edit.projection,projection == .auto ? .perspective:projection)
      XCTAssertEqual(edit.result.width,d.width);XCTAssertEqual(edit.result.height,d.height)
      if projection == .cylindrical || projection == .spherical {
        XCTAssertFalse(edit.result.layers[0].content == d.layers[0].content)
        let p = PhotoPlacement(projection:projection,focal:210,center:PhotoPoint(128,96)),point = PhotoPoint(37,29)
        let q = try XCTUnwrap(p.unproject(p.project(point)));XCTAssertEqual(q.x,point.x,accuracy:0.000001);XCTAssertEqual(q.y,point.y,accuracy:0.000001)
      } else { XCTAssertTrue(edit.result.layers[0] == d.layers[0]) }
    }
  }
  func testRealImageMatchingRecoversRotationScaleAndPerspective() throws {
    let values = try texture();var source = try Surface(width:256,height:192,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<192 { for x in 0..<256 { let v = values[y*256+x];source.setLinearPixel(x:x,y:y,Pixel(v,v,v,1)) } }
    var a = try PhotoFeatures.detect(width:256,height:192,luma:values,valid:[Bool](repeating:true,count:values.count));a.points = a.points.map{$0+PhotoPoint(repeating:0.5)}
    let examples: [(PhotoAlignSettings.Projection,PhotoHomography)] = [(.collage,PhotoHomography([1.02,-0.045,1,0.045,1.02,-7,0,0,1])),(.perspective,PhotoHomography([1.02,0.035,-4,-0.025,0.99,4,0.00025,-0.00015,1]))]
    for (projection,expected) in examples {
      var image = values,valid = [Bool](repeating:false,count:values.count)
      for y in 0..<192 { for x in 0..<256 {
        let q = expected.apply(PhotoPoint(Double(x)+0.5,Double(y)+0.5)),pixel = CropGeometry.sample(source,x:q.x,y:q.y)
        image[y*256+x] = pixel.r;valid[y*256+x] = pixel.a > 0.99
      } }
      var b = try PhotoFeatures.detect(width:256,height:192,luma:image,valid:valid);b.points = b.points.map{$0+PhotoPoint(repeating:0.5)}
      let result = try PhotoRegistration.align([a,b],projection:projection,reference:0,focal:nil)
      XCTAssertGreaterThan(result.matches,20)
      for point in [PhotoPoint(50,50),PhotoPoint(200,50),PhotoPoint(50,140),PhotoPoint(200,140)] {
        let actual = result.placements[1].forward(point),target = expected.apply(point)
        XCTAssertLessThan(hypot(actual.x-target.x,actual.y-target.y),1.5)
      }
    }
  }
  func testAutoChoosesCurvedProjectionAndGraphConnectsIndirectOverlap() throws {
    let d = try fixture(shift:false);var settings = PhotoAlignSettings();settings.focalLengthPixels = 80
    let edit = try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings);XCTAssertEqual(edit.projection,.cylindrical)
    let features = (0..<3).map{_ in PhotoFeatures(width:256,height:192,points:[],descriptors:[])}
    let points = (0..<30).map{PhotoPoint(Double($0%6)*17+85,Double($0/6)*19+30)}
    let pairs = [PhotoRegistration.Pair(a:0,b:1,pa:points,pb:points.map{$0-PhotoPoint(65,3)},h:.translation(65,3)),PhotoRegistration.Pair(a:1,b:2,pa:points,pb:points.map{$0-PhotoPoint(70,-5)},h:.translation(70,-5))]
    let result = try PhotoRegistration.layout(features,pairs,.reposition,0,256),p = result.placements[2].forward(PhotoPoint(80,80))
    XCTAssertEqual(p.x,215,accuracy:0.00001);XCTAssertEqual(p.y,78,accuracy:0.00001)
  }
  func testShiftedContentMaskDepthSelectionHistoryAndPersistence() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth);d.selection = IntRect(x:2,y:3,width:9,height:8)
      d.layers[1].mask = try Surface(width:256,height:192,depth:depth,fill:.white)
      for y in 90..<100 { for x in 100..<110 { d.layers[1].mask?.setPixel(x:x,y:y,.black) } }
      var settings = PhotoAlignSettings();settings.projection = .reposition
      let edit = try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings),result = edit.result
      XCTAssertTrue(result.layers[0] == d.layers[0]);XCTAssertEqual(result.selection,d.selection)
      XCTAssertEqual(Double(result.layers[1].x),28,accuracy:1);XCTAssertEqual(Double(result.layers[1].y),3,accuracy:1)
      XCTAssertEqual(try MaskSampler(layer:result.layers[1]).coverage(x:133,y:98),0,accuracy:0.02)
      guard case .raster(let output) = result.layers[1].content else { return XCTFail() };XCTAssertEqual(output.depth,depth)
      var session = EditorSession(document:d);try session.execute(.photoAlign(edit));XCTAssertTrue(session.document == result);try session.undo();XCTAssertTrue(session.document == d);try session.redo();XCTAssertTrue(session.document == result)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result)) == result)
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(result));XCTAssertEqual(try Renderer.composite(reopened),try Renderer.composite(result))
      var stale = d;stale.name = "changed";XCTAssertThrowsError(try edit.applied(to:stale))
    }
  }
  func testLocksDisconnectedInputsAndCancellation() async throws {
    var d = try fixture();var settings = PhotoAlignSettings();settings.projection = .reposition
    d.layers[0].locked = true
    let edit = try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings);XCTAssertTrue(edit.result.layers[0] == d.layers[0])
    settings.referenceLayerID = d.layers[1].id;XCTAssertThrowsError(try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings));settings.referenceLayerID = nil
    settings.projection = .cylindrical;XCTAssertThrowsError(try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings))
    d.layers[0].locked = false;d.layers[1].content = .raster(try Surface(width:256,height:192,fill:.white));XCTAssertThrowsError(try PhotoAlign.prepare(d,layerIDs:ids(d),settings:.init()))
    let input = try fixture(),selected = ids(input),task = Task { () throws -> PhotoAlignEdit in try Task.checkCancellation();return try PhotoAlign.prepare(input,layerIDs:selected,settings:.init()) }
    task.cancel();do { _ = try await task.value;XCTFail("Cancellation ignored") } catch is CancellationError {} catch { XCTFail("\(error)") }
  }
  @MainActor func testNativePreviewCancelCommitAndHistory() async throws {
    _ = NSApplication.shared;let d = try fixture(),store = EditorStore(document:d);store.selectedLayerIDs = ids(d)
    defer { store.renderTask?.cancel();store.cancelPhotoAlign() }
    XCTAssertTrue(store.canBeginPhotoAlign);store.beginPhotoAlign();let draft = try XCTUnwrap(store.photoAlignDraft);draft.settings.projection = .reposition
    draft.refresh();await draft.task?.value;XCTAssertTrue(draft.ready,draft.error ?? "No preview");XCTAssertTrue(store.document == d);XCTAssertTrue(store.hasToneDraft)
    let view = NSHostingView(rootView:PhotoAlignSheet(store:store,model:draft));view.frame = NSRect(x:0,y:0,width:760,height:520);view.layoutSubtreeIfNeeded();XCTAssertGreaterThan(view.fittingSize.width,0)
    store.cancelPhotoAlign();XCTAssertTrue(store.document == d)
    store.beginPhotoAlign();let final = try XCTUnwrap(store.photoAlignDraft);final.settings.projection = .reposition;final.refresh();await final.task?.value
    let expected = try XCTUnwrap(final.edit).result;store.commitPhotoAlign();await store.geometryTask?.value
    XCTAssertNil(store.error);XCTAssertTrue(store.document == expected);XCTAssertEqual(store.selectedLayerIDs,ids(d));await store.undo();XCTAssertTrue(store.document == d);await store.redo();XCTAssertTrue(store.document == expected)
  }
  @MainActor func testPhotatoAPIEquivalenceSchemasAndGuards() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons:{0}) { service,shared in
      try service.share(shared);let d = try fixture();shared.store.session = EditorSession(document:d)
      let params: [String:Any] = ["layerIDs":d.layers.map{$0.id.uuidString},"settings":["projection":"reposition"]]
      var settings = PhotoAlignSettings();settings.projection = .reposition
      let expected = try PhotoAlign.prepare(d,layerIDs:ids(d),settings:settings).result
      let status = try await helper.edit(service,shared,"photo.autoAlign",params);XCTAssertEqual(status,200);XCTAssertTrue(shared.store.document == expected)
      let undo = try await helper.edit(service,shared,"history.undo");XCTAssertEqual(undo,200);XCTAssertTrue(shared.store.document == d)
      let stale = try await helper.edit(service,shared,"photo.autoAlign",params,revision:"stale");XCTAssertEqual(stale,409)
      shared.store.selectedLayerIDs = ids(d);shared.store.beginPhotoAlign();let busy = try await helper.edit(service,shared,"photo.autoAlign",params);XCTAssertEqual(busy,409);shared.store.cancelPhotoAlign()
      for settings: [String:Any] in [["projection":"invented"],["focalLengthPixels":true],["focalLengthPixels":-10],["referenceLayerID":UUID().uuidString],["vignette":true]] {
        var bad = params;bad["settings"] = settings;let invalid = try await helper.edit(service,shared,"photo.autoAlign",bad);XCTAssertEqual(invalid,400)
      }
      XCTAssertTrue(shared.store.document == d)
      let definition = try XCTUnwrap(AutomationCommand.definitions.first{$0.name == "photo.autoAlign"})
      let parameters = ((definition.schema["properties"] as! [String:Any])["parameters"] as! [String:Any])["properties"] as! [String:Any]
      XCTAssertEqual(((parameters["settings"] as! [String:Any])["properties"] as! [String:Any]).count,3)
    }
  }
  @MainActor func testInstalledAdobeDescriptorThroughBothAsyncJobInterfaces() async throws {
    let d = try fixture(),input = try PSDCodec.writeRasterLayers(d),decoded = try PSDCodec.read(input)
    let action = #"[{"_obj":"selectAllLayers","_target":[{"_ref":"layer","_enum":"ordinal","_value":"targetEnum"}]},{"_obj":"$Algn","_target":[{"_ref":"$Lyr ","_enum":"$Ordn","_value":"$Trgt"}],"$Usng":{"_enum":"$ADSt","_value":"ADSContent"},"$Aply":{"_enum":"projection","_value":"translation"}}]"#
    let result = try PhotoshopActionProgram(actionJSON:action).applying(to:decoded).session.document
    var settings = PhotoAlignSettings();settings.projection = .reposition
    XCTAssertTrue(result == (try PhotoAlign.prepare(decoded,layerIDs:ids(decoded),settings:settings).result))
    let body: [String:Any] = ["image":["source":["url":"https://example.test/input.psd"]],"options":["actions":[["source":["content":action,"contentType":"application/json"]]]],"outputs":[["mediaType":"image/png","destination":["validityPeriod":60]]]]
    try await AutomationTests().withService(pressedMouseButtons:{0},resourceTransport:AlignFixtureTransport(input)) { service,shared in
      service.setResourceJobsEnabled(true);let before = shared.store.document
      for path in ["/v1/action-jobs","/v2/execute-actions"] {
        let output = try await AutomationActionJobsTests().output(service,submit:path,payload:body,expectedMediaType:"image/png")
        XCTAssertEqual(output.2,try DocumentIO.encode(result,format:.png))
      };XCTAssertTrue(shared.store.document == before)
    }
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:action.replacingOccurrences(of:"ADSContent",with:"ADSCentersH")))
    XCTAssertThrowsError(try PhotoshopActionProgram(actionJSON:action.replacingOccurrences(of:"translation",with:"interactive")))
  }
}
