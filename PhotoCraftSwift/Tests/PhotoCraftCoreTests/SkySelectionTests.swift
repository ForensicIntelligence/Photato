import XCTest
@testable import PhotoCraftCore

final class SkySelectionTests:XCTestCase {
  func landscape(_ w:Int=160,_ h:Int=100,depth:PixelDepth = .u8)throws->Surface {
    var s=try Surface(width:w,height:h,depth:depth)
    for y in 0..<h{for x in 0..<w{
      let horizon=h*3/5,cx=Float(w)*0.7,cy=Float(h)*0.35,r=Float(h)*0.18,dx=Float(x)-cx,dy=Float(y)-cy,n=(Float((x*7919+y*104729)%97)/97-0.5)*0.25
      let p:Pixel
      if dx*dx+dy*dy<r*r {p=Pixel(0.1+n*0.5,0.35+n,0.1+n*0.5)}
      else if abs(dx)<3 && Float(y)>cy && y<horizon {p=Pixel(0.3+n*0.3,0.2,0.1)}
      else if y<horizon {let t=Float(y)/Float(horizon);p=Pixel(0.25+0.4*t,0.5+0.3*t,0.9+0.05*t)}
      else{p=Pixel(0.35+n,0.3+n,0.15+n*0.5)}
      s.setPixel(x:x,y:y,p)
    }};return s
  }
  func testSkyExcludesTreeAndGroundAcrossDepths()throws {
    for depth in PixelDepth.allCases {
      let source=try landscape(depth:depth),copy=source,mask=try XCTUnwrap(SkySelection.mask(source))
      XCTAssertGreaterThan(mask.coverage(x:10,y:5),0.9);XCTAssertGreaterThan(mask.coverage(x:80,y:50),0.9)
      XCTAssertLessThan(mask.coverage(x:10,y:80),0.1);XCTAssertLessThan(mask.coverage(x:112,y:35),0.1);XCTAssertEqual(source,copy)
    }
  }
  func testOvercastNoSkyAndColorPriors()throws {
    var image=try Surface(width:64,height:64,fill:Pixel(0.2,0.3,0.1));XCTAssertNil(try SkySelection.mask(image))
    for y in 0..<30{for x in 0..<64{image.setPixel(x:x,y:y,Pixel(0.85,0.86,0.88))}}
    let mask=try XCTUnwrap(SkySelection.mask(image));XCTAssertGreaterThan(mask.coverage(x:30,y:10),0.9);XCTAssertLessThan(mask.coverage(x:30,y:50),0.1)
    XCTAssertGreaterThan(SkySelection.prior(.init(0.4,0.6,0.95)),0.8);XCTAssertLessThan(SkySelection.prior(.init(0.15,0.4,0.15)),0.1)
  }
  func testReducedResolutionRefinementAndTileSeams()throws {
    let image=try landscape(600,400),mask=try XCTUnwrap(SkySelection.mask(image,workingPixels:4000))
    XCTAssertGreaterThan(mask.coverage(x:100,y:180),0.9);XCTAssertLessThan(mask.coverage(x:100,y:280),0.1)
    for x in [255,256,511,512]{XCTAssertGreaterThan(mask.coverage(x:x,y:20),0.9)}
    XCTAssertTrue(try mask.bytes.contains{$0>0 && $0<255})
  }
  func testManualMaskRefinementPlacementAndValidation()throws {
    let mask=try SelectionMask.make(.rectangle(.init(x:0,y:0,width:40,height:20)),width:40,height:40,antiAlias:false)
    var p=SkyReplacementSettings();p.fadeEdge=0
    let removed=try SkyReplacement.refined(mask,settings:p,strokes:[.init(points:[.init(x:10,y:10)],size:12,hardness:1,add:false)])
    XCTAssertLessThan(removed.coverage(x:10,y:10),0.1);XCTAssertGreaterThan(removed.coverage(x:30,y:10),0.9)
    p.shiftEdge=100;let grown=try SkyReplacement.refined(mask,settings:p,strokes:[]);XCTAssertGreaterThan(grown.coverage(x:30,y:30),0.9)
    let sky=try Surface(width:20,height:10);p.scale=100;p.flip=true
    let t=p.transform(sky:sky,width:40,height:40);XCTAssertEqual(t.point(0,0).x,60);XCTAssertEqual(t.point(20,0).x,-20)
    p.scale = .nan;XCTAssertThrowsError(try p.validate());var settings=SkySelectionSettings();settings.threshold = .infinity;XCTAssertThrowsError(try SkySelection.mask(sky,settings:settings))
  }
  func testCancellation()async throws {
    let image=try landscape(600,400),task=Task.detached{try SkySelection.mask(image)};task.cancel()
    do{_=try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}catch{XCTFail("Unexpected: \(error)")}
  }
}
