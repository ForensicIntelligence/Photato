import XCTest
import CryptoKit
@testable import PhotoCraftCore

final class PagedRasterFilterTests:XCTestCase {
  var folder:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/paged-filters")}
  func testAll48ActualPriorNativeFilterVectorsRemainBitExact() throws {
    let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("manifest.json")))as?[[String:Any]])
    XCTAssertEqual(manifest.count,48)
    for(di,depth)in PixelDepth.allCases.enumerated(){for kind in PagedFilterFixture.kinds{for variant in 0..<2 {
      var d=try PagedFilterFixture.document(depth,variant:variant)
      try PagedRasterFilters.apply(PagedFilterFixture.filter(kind),to:d.layers[0].id,in:&d)
      guard case .raster(let s)=d.layers[0].content else{return XCTFail("Missing filtered pixels")}
      let name="\(di)-\(kind.rawValue)-\(variant).rgba",expected=try Data(contentsOf:folder.appendingPathComponent(name))
      XCTAssertEqual(manifest.first{$0["file"]as?String==name}?["sha256"]as?String,SHA256.hash(data:expected).map{String(format:"%02x",$0)}.joined())
      XCTAssertEqual(try s.rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB),expected,name)
    }}}
  }
  func testMaximumImplicitFiltersKeepLegacyQuantizationWithoutRasterAllocation() throws {
    for depth in PixelDepth.allCases {for kind in PagedFilterFixture.kinds where kind != .motionBlur && kind != .addNoise {
      var large=try CraftDocument(width:300_000,height:300_000,depth:depth)
      large.layers[0].content = .raster(try Surface(width:large.width,height:large.height,depth:depth,fill:.white,colorEncoding:depth == .f32 ? .linearRGB:.sRGB))
      var small=try CraftDocument(width:131,height:69,depth:depth)
      small.layers[0].content = .raster(try Surface(width:small.width,height:small.height,depth:depth,fill:.white,colorEncoding:depth == .f32 ? .linearRGB:.sRGB))
      let filter=PagedFilterFixture.filter(kind)
      try PagedRasterFilters.apply(filter,to:large.layers[0].id,in:&large)
      try RasterFilterEngine.apply(filter,to:small.layers[0].id,in:&small)
      guard case .raster(let a)=large.layers[0].content,case .raster(let b)=small.layers[0].content else{return XCTFail("Missing pixels")}
      XCTAssertEqual(a.tileCount,0);XCTAssertTrue(a.pixel(x:299_999,y:299_999).hasSameBits(as:b.pixel(x:0,y:0)),"\(depth)/\(kind)")
    }}
  }
  func testActual9MPBlurMatchesThirtyPriorNativeWideBandHashes() throws {
    let source=try PagedFilterFixture.wideSurface(height:1500)
    let rows=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("wide-manifest.json")))as?[[String:Any]])
    XCTAssertEqual(rows.count,30)
    for kind in [RasterFilter.Kind.boxBlur,.gaussianBlur] {
      var d=try CraftDocument(width:6000,height:1500,depth:.f32);d.layers[0].content = .raster(source)
      try RasterFilterEngine.apply(PagedFilterFixture.filter(kind),to:d.layers[0].id,in:&d)
      guard case .raster(let s)=d.layers[0].content else{return XCTFail("Missing pixels")}
      XCTAssertGreaterThan(s.mappedBytes,100_000_000);XCTAssertLessThan(s.allocatedBytes,8*1024*1024)
      for row in rows where row["kind"]as?String==kind.rawValue {
        let y=try XCTUnwrap(row["y"]as?Int)
        let data=try s.cropped(to:.init(x:0,y:y,width:6000,height:64)).rgbaData(depth:.f32,colorEncoding:.linearRGB)
        XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),row["sha256"]as?String,"\(kind)/\(y)")
      }
    }
  }
  func testScratchPublicationBudgetCancellationAndNoPartialModelCommit() async throws {
    let writer=try FilterSamplePlane.Writer(width:65,height:2,maximumBytes:65*2*32)
    for y in 0..<2 {try writer.row((0..<64).map{SIMD4<Double>(Double($0),Double(y),-0.0,1)},y:y)}
    for y in 0..<2 {try writer.row([SIMD4<Double>(64,Double(y),-0.0,1)],x:64,y:y)}
    let plane=try writer.finish();XCTAssertEqual(plane.sample(64,1),SIMD4<Double>(64,1,-0.0,1))
    XCTAssertThrowsError(try writer.row([.zero],y:0));XCTAssertEqual(plane.sample(64,1).z.bitPattern,Double(-0.0).bitPattern)
    let invalid=try FilterSamplePlane.Writer(width:1,height:1,maximumBytes:32)
    XCTAssertThrowsError(try invalid.row([SIMD4<Double>(.nan,0,0,1)],y:0));XCTAssertThrowsError(try invalid.finish())
    var d=try PagedFilterFixture.document(.f32,variant:1);let before=d
    XCTAssertThrowsError(try PagedRasterFilters.apply(PagedFilterFixture.filter(.boxBlur),to:d.layers[0].id,in:&d,maximumScratchPlaneBytes:100))
    XCTAssertEqual(d,before)
    let worker=Task.detached {var copy=before;withUnsafeCurrentTask{$0?.cancel()};try PagedRasterFilters.apply(PagedFilterFixture.filter(.gaussianBlur),to:copy.layers[0].id,in:&copy)}
    do {try await worker.value;XCTFail("Cancelled filter accepted")}catch is CancellationError {}
  }
  func testConstantAverageAndMosaicRetainLegacySignedZero() throws {
    for kind in [RasterFilter.Kind.average,.mosaic] {
      var d=try CraftDocument(width:300_000,height:300_000,depth:.f32)
      d.layers[0].content = .raster(try Surface(width:d.width,height:d.height,depth:.f32,fill:Pixel(-0.0,0,1,1),colorEncoding:.linearRGB))
      var small=try CraftDocument(width:131,height:69,depth:.f32)
      small.layers[0].content = .raster(try Surface(width:small.width,height:small.height,depth:.f32,fill:Pixel(-0.0,0,1,1),colorEncoding:.linearRGB))
      let f=PagedFilterFixture.filter(kind)
      try RasterFilterEngine.apply(f,to:d.layers[0].id,in:&d);try RasterFilterEngine.apply(f,to:small.layers[0].id,in:&small)
      guard case .raster(let a)=d.layers[0].content,case .raster(let b)=small.layers[0].content else{return XCTFail("Missing pixels")}
      XCTAssertTrue(a.linearPixel(x:299_999,y:299_999).hasSameBits(as:b.linearPixel(x:0,y:0)))
    }
  }
}
