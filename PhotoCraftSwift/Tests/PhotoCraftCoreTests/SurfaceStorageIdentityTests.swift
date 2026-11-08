import XCTest
@testable import PhotoCraftCore

final class SurfaceStorageIdentityTests:XCTestCase {
  func testDirectSharedTilesAndCopyOnWriteKeepIdentityProofSound()throws {
    let tile=RasterTile(repeating:Pixel(0.25,0.5,0.75),count:4096)
    let a:RasterTileMap=[0:tile,5:tile];var b=a
    XCTAssertTrue(a.sharesRasterStorage(with:b));XCTAssertTrue(b.sharesRasterStorage(with:a))
    var changed=try XCTUnwrap(b[5]);changed[0] = .white;b[5]=changed
    XCTAssertFalse(a.sharesRasterStorage(with:b));XCTAssertEqual(a[5]?[0],Pixel(0.25,0.5,0.75));XCTAssertEqual(b[5]?[0],.white)
    let relocated:RasterTileMap=[1:tile,5:tile];XCTAssertFalse(a.sharesRasterStorage(with:relocated))
    let fewer:RasterTileMap=[0:tile];XCTAssertFalse(a.sharesRasterStorage(with:fewer))
  }
  func testPersistentSharedTreeAndEditedBranchRetainOriginalStorage()throws {
    let tile=RasterTile(repeating:Pixel(0.2,0.4,0.6),count:4096);var a:RasterTileMap=[:]
    for key in 0...RasterTileMap.directLimit{a[key]=tile}
    var b=a;XCTAssertTrue(a.sharesRasterStorage(with:b))
    var changed=try XCTUnwrap(b[RasterTileMap.directLimit]);changed[17] = .white;b[RasterTileMap.directLimit]=changed
    XCTAssertFalse(a.sharesRasterStorage(with:b));XCTAssertEqual(a[RasterTileMap.directLimit]?[17],Pixel(0.2,0.4,0.6));XCTAssertEqual(b[RasterTileMap.directLimit]?[17],.white)
  }
  func testSharedOwnedAndMappedSurfacesKeepSignedZeroHiddenColorAndCOW()throws {
    for depth in PixelDepth.allCases{
      var a=try Surface(width:129,height:65,depth:depth);a.setPixel(x:128,y:64,Pixel(0.25,0.5,0.75,0))
      var b=a;XCTAssertEqual(a,b);b.setPixel(x:128,y:64,Pixel(0.25,0.5,0.8,0));XCTAssertNotEqual(a,b)
      let mapped=try a.spillingTiles(to:RasterTileStore());var copy=mapped;XCTAssertEqual(a,mapped);XCTAssertEqual(mapped,copy)
      copy.setPixel(x:128,y:64,.white);XCTAssertNotEqual(mapped,copy);XCTAssertEqual(a,mapped)
    }
    var positive=try Surface(width:65,height:3,depth:.f32);positive.setPixel(x:0,y:0,Pixel(0,0.5,0.75,0))
    var negative=positive;negative.setPixel(x:0,y:0,Pixel(-0.0,0.5,0.75,0))
    XCTAssertNotEqual(positive,negative);XCTAssertNotEqual(negative,positive)
    XCTAssertEqual(positive.pixel(x:0,y:0).r.bitPattern,Float(0).bitPattern)
    XCTAssertEqual(negative.pixel(x:0,y:0).r.bitPattern,Float(-0.0).bitPattern)
  }
  func testSharedEmptyStorageCannotHideGeometryEncodingDepthOrDefaultChanges()throws {
    let a=try Surface(width:67,height:3,depth:.f32,fill:Pixel(0.25,0.5,0.75,0))
    XCTAssertNotEqual(a,try Surface(width:67,height:3,depth:.f32,fill:Pixel(0.25,0.5,0.8,0)))
    XCTAssertNotEqual(a,try Surface(width:67,height:4,depth:.f32,fill:Pixel(0.25,0.5,0.75,0)))
    XCTAssertNotEqual(a,try Surface(width:67,height:3,depth:.u16,fill:Pixel(0.25,0.5,0.75,0)))
    XCTAssertNotEqual(a,try a.interpretingSamples(as:.linearRGB));XCTAssertEqual(a,a)
  }
}
