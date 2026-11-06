import XCTest
@testable import PhotoCraftCore

final class PatternPatchTests: XCTestCase {
  func pattern() throws -> RasterPattern {
    var pixels = try Surface(width:2,height:2,fill:Pixel(0.25,0.25,0.25))
    pixels.setPixel(x:0,y:0,Pixel(0.75,0.75,0.75));pixels.setPixel(x:1,y:1,Pixel(0.75,0.75,0.75))
    return try RasterPattern(name:"Owned checker",surface:pixels,id:"owned-checker")
  }
  func fixture(_ depth:PixelDepth = .u8,size:Int = 16)throws->CraftDocument {
    var d = try CraftDocument(width:size,height:size,depth:depth)
    d.layers[0].content = .raster(try Surface(width:size,height:size,depth:depth,fill:Pixel(0.5,0.5,0.5)))
    d.layers[0].locked = false;d.selection = .init(x:3,y:3,width:1,height:1);return d
  }
  func testAnalyticalSingleUnknownTextureIsHealedRatherThanPlainFill()throws {
    let p = try pattern(),d = try fixture(),id = try XCTUnwrap(d.activeLayerID)
    var request = RegionRetouchRequest(kind:.patch)
    let result = try PatternPatch.prepare(request,pattern:p,document:d,layerID:id).result
    guard case .raster(let pixels) = result.layers[0].content else { return XCTFail("Raster missing") }
    // The four neighbours of the 0.75 texel are0.25. On a0.5 destination,
    // the single unknown membrane correction is +0.25, giving1.0, not0.75.
    XCTAssertEqual(pixels.pixel(x:3,y:3),.white)
    guard case .raster(let before) = d.layers[0].content else { return XCTFail("Raster missing") }
    for y in 0..<16 {for x in 0..<16 where x != 3 || y != 3 {XCTAssertTrue(pixels.pixel(x:x,y:y).hasSameBits(as:before.pixel(x:x,y:y)))}}
    request.diffusion = 1
    let low = try PatternPatch.prepare(request,pattern:p,document:d,layerID:id).result
    guard case .raster(let less) = low.layers[0].content else { return XCTFail("Raster missing") }
    XCTAssertEqual(less.pixel(x:3,y:3).r,0.8,accuracy:0.000001)
    XCTAssertEqual(result.selection,d.selection);XCTAssertEqual(result.patterns,d.patterns)
  }
  func testSoftCoverageTransparentDonorAndProtectedAlphaRetainOutsideWords()throws {
    let p = try pattern()
    for depth in PixelDepth.allCases {
      var d = try fixture(depth);let id = try XCTUnwrap(d.activeLayerID)
      var coverage = try Surface(width:16,height:16,depth:.u8,fill:.black)
      coverage.setPixel(x:3,y:3,Pixel(128.0/255,128.0/255,128.0/255));d.setCoverageSelection(try SelectionMask(coverage:coverage))
      let result = try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:d,layerID:id).result
      XCTAssertEqual(result.selectionMask,d.selectionMask)
      guard case .raster(let before) = d.layers[0].content,case .raster(let after) = result.layers[0].content else {return XCTFail("Raster missing")}
      XCTAssertNotEqual(after,before)
      for y in 0..<16 {for x in 0..<16 where x != 3 || y != 3 {XCTAssertTrue(after.linearPixel(x:x,y:y).hasSameBits(as:before.linearPixel(x:x,y:y)))}}
      var r = RegionRetouchRequest(kind:.patch);r.transparent = true
      let clear = try RasterPattern(name:"Clear",surface:Surface(width:1,height:1,fill:.clear),id:"clear")
      XCTAssertEqual(try PatternPatch.prepare(r,pattern:clear,document:d,layerID:id).result,d)
      d.layers[0].protection = .transparency
      var source = before;source.setPixel(x:3,y:3,.clear);d.layers[0].content = .raster(source)
      XCTAssertEqual(try PatternPatch.prepare(r,pattern:p,document:d,layerID:id).result,d)
    }
  }
  func testMaximumLogicalCanvasAndTransformedLayerUseBoundedStorageAndPreserveMetadata()throws {
    let p = try pattern()
    var d = try fixture(.f32,size:300_000);d.selection = .init(x:299_900,y:299_900,width:2,height:2)
    let id = try XCTUnwrap(d.activeLayerID),original = d
    let result = try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:d,layerID:id).result
    XCTAssertEqual(d,original);XCTAssertNotEqual(result,d);XCTAssertEqual(result.selection,d.selection)
    guard case .raster(let large) = result.layers[0].content else {return XCTFail("Raster missing")}
    XCTAssertLessThan(large.allocatedBytes,1_048_576);XCTAssertEqual(large.width,300_000)
    for depth in PixelDepth.allCases {
      var d = try fixture(depth);d.layers[0].x = 2;d.layers[0].y = -1
      d.layers[0].affine = .rotation(4);d.layers[0].mask = try Surface(width:16,height:16,fill:.white)
      d.layers[0].opacity = 0.7;d.selection = .init(x:5,y:5,width:2,height:2)
      let original = d.layers[0],result = try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:d,layerID:try XCTUnwrap(d.activeLayerID)).result
      XCTAssertEqual(result.layers[0].coordinateTransform,original.coordinateTransform)
      XCTAssertEqual(result.layers[0].mask,original.mask);XCTAssertEqual(result.layers[0].maskCoordinateTransform,original.maskCoordinateTransform)
      XCTAssertEqual(result.layers[0].opacity,original.opacity);XCTAssertEqual(result.selection,d.selection)
    }
  }
  func testValidationCancellationAndOversizedSolveDoNotMutateSource()async throws {
    let p = try pattern();var d = try fixture();let id = try XCTUnwrap(d.activeLayerID),before = d
    let snapshot = d
    let task = Task {try Task.checkCancellation();return try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:snapshot,layerID:id)};task.cancel()
    do{_ = try await task.value;XCTFail("Cancelled repair returned")}catch is CancellationError{}
    XCTAssertEqual(d,before)
    d.selection = nil;XCTAssertThrowsError(try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:d,layerID:id))
    d = before;d.layers[0].locked = true;XCTAssertThrowsError(try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:d,layerID:id))
    d = before;var r = RegionRetouchRequest(kind:.patch);r.patchType = .contentAware
    XCTAssertThrowsError(try PatternPatch.prepare(r,pattern:p,document:d,layerID:id))
    r = .init(kind:.patch);r.dx = 1;XCTAssertThrowsError(try PatternPatch.prepare(r,pattern:p,document:d,layerID:id))
    d = try fixture(size:300_000);d.selection = .init(x:0,y:0,width:3000,height:3000)
    XCTAssertThrowsError(try PatternPatch.prepare(.init(kind:.patch),pattern:p,document:d,layerID:id))
  }
}
