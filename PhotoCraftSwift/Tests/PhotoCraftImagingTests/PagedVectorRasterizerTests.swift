import Foundation
import XCTest
import CryptoKit
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PagedVectorRasterizerTests:XCTestCase {
  func testAll32ActualPriorCoverageVectorsRemainExactAcrossPatchBoundaries() throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/paged-vectors")
    let rows=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("manifest.json")))as?[[String:Any]])
    XCTAssertEqual(rows.count,32)
    for variant in 0..<8 {for aa in [false,true] {for inv in [false,true] {
      let name="\(variant)-\(aa)-\(inv).gray",expected=try Data(contentsOf:folder.appendingPathComponent(name))
      XCTAssertEqual(rows.first{$0["file"]as?String==name}?["sha256"]as?String,SHA256.hash(data:expected).map{String(format:"%02x",$0)}.joined())
      let actual=try VectorRasterizer.pagedCoverage(PagedVectorFixture.path(variant,inverted:inv),width:2113,height:69,
        origin:PathPoint(3.25,-2.5),antiAlias:aa,emptyRevealsAll:true)
      XCTAssertEqual(Data(try SelectionMask(coverage:actual).bytes),expected,name)
    }}}
  }
  func document(side:Int,depth:PixelDepth,inverted:Bool,grouped:Bool)throws->CraftDocument {
    var d=try CraftDocument(width:side,height:side,depth:depth)
    let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
    var base=Layer(name:"Vector base",content:.raster(try Surface(width:side,height:side,depth:depth,fill:Pixel(0.2,0.4,0.6),colorEncoding:encoding)))
    base.vectorMask=VectorMask(path:VectorPath(components:[PagedVectorFixture.rectangle(Double(side-8),Double(side-8),8,8)],inverted:inverted))
    base.vectorMask?.density=0.75
    var upper=Layer(name:"Upper",content:.raster(try Surface(width:side,height:side,depth:depth,fill:Pixel(0.8,0.2,0.1,0.5),colorEncoding:encoding)));upper.opacity=128/255
    let group=Layer(name:"Group",content:.group(GroupContent(passThrough:false)))
    if grouped {base.parentID=group.id;upper.parentID=group.id}
    d.layers=grouped ? [base,upper,group]:[base,upper];d.activeLayerID=base.id;return d
  }
  func testMaximumSparseVectorMasksPreserveGlobalOpacityAtEveryDepthAndInGroups() throws {
    for depth in PixelDepth.allCases {for inverted in [false,true] {for grouped in [false,true] {
      let big=try document(side:300_000,depth:depth,inverted:inverted,grouped:grouped)
      let small=try document(side:129,depth:depth,inverted:inverted,grouped:grouped)
      let output=try Renderer.composite(big),reference=try Renderer.composite(small)
      let region=try Renderer.composite(big,region:.init(x:0,y:0,width:2,height:2))
      XCTAssertTrue(region.linearPixel(x:0,y:0).hasSameBits(as:output.linearPixel(x:0,y:0)))
      XCTAssertLessThanOrEqual(output.tileCount,4);XCTAssertLessThan(output.allocatedBytes,1024*1024)
      for (x,y,sx,sy) in [(0,0,0,0),(299_990,299_990,119,119),(299_995,299_995,124,124),(299_999,299_999,128,128)] {
        let a=depth == .f32 ? output.linearPixel(x:x,y:y):output.pixel(x:x,y:y)
        let b=depth == .f32 ? reference.linearPixel(x:sx,y:sy):reference.pixel(x:sx,y:sy)
        XCTAssertTrue(a.hasSameBits(as:b),"\(depth)/\(inverted)/\(grouped):\(x),\(y)")
      }
    }}}
  }
  func testLargePathSelectionEmptyInverseCancellationAndFeatherBoundary() async throws {
    let path=VectorPath(components:[PagedVectorFixture.rectangle(299_990,299_990,5,5)])
    let selection=try VectorRasterizer.coverage(path,width:300_000,height:300_000,antiAlias:false)
    XCTAssertTrue(selection.isPaged);XCTAssertEqual(selection.bounds,.init(x:299_990,y:299_990,width:5,height:5))
    XCTAssertEqual(selection.coverage(x:299_992,y:299_992),1);XCTAssertEqual(selection.coverage(x:0,y:0),0)
    XCTAssertThrowsError(try VectorRasterizer.pagedCoverage(path,width:300_000,height:300_000,
      maximumScratchPreparedBytes:300_100))
    let full=try VectorRasterizer.coverage(VectorPath(components:[PagedVectorFixture.rectangle(0,0,300_000,300_000)]),width:300_000,height:300_000)
    XCTAssertTrue(try full.isFullCoverage);XCTAssertEqual(try full.coverageSurface().tileCount,0)
    let cross=try VectorRasterizer.coverage(VectorPath(components:[PagedVectorFixture.rectangle(16_380,16_380,8,8)]),width:300_000,height:300_000)
    XCTAssertEqual(cross.bounds,.init(x:16_380,y:16_380,width:8,height:8))
    for y in 16_380..<16_388 {for x in 16_380..<16_388 {XCTAssertEqual(cross.coverage(x:x,y:y),1)}}
    for inverted in [false,true] {
      let empty=try VectorRasterizer.coverage(VectorPath(inverted:inverted),width:300_000,height:300_000,emptyRevealsAll:true)
      XCTAssertEqual(empty.coverage(x:150_000,y:150_000),inverted ? 0:1)
      XCTAssertEqual(try empty.coverageSurface().tileCount,0)
    }
    var unsafe=try document(side:300_000,depth:.u8,inverted:false,grouped:false)
    unsafe.layers[0].vectorMask?.feather=1;XCTAssertThrowsError(try Renderer.composite(unsafe))
    let worker=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return try VectorRasterizer.coverage(path,width:300_000,height:300_000)}
    do {_ = try await worker.value;XCTFail("Cancelled coverage accepted")}catch is CancellationError {}
  }
}
