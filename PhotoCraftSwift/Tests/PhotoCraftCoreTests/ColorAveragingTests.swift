import Foundation
import XCTest
import PhotoCraftCore

final class ColorAveragingTests:XCTestCase {
  func testSevenSizesClipAtEdgesAndFloorDocumentCoordinates()throws {
    for size in [1,3,5,11,31,51,101] {
      let radius=size/2
      XCTAssertEqual(try ColorAveraging.region(x:100.99,y:120.01,width:300000,height:300000,size:size),.init(x:100-radius,y:120-radius,width:size,height:size))
      XCTAssertEqual(try ColorAveraging.region(x:0,y:299999,width:300000,height:300000,size:size),.init(x:0,y:299999-radius,width:radius+1,height:radius+1))
    }
    for v in [-1.0,Double.nan,Double.infinity,300000.0]{XCTAssertThrowsError(try ColorAveraging.region(x:v,y:1,width:300000,height:300000,size:3))}
    for size in [0,2,4,100,102,Int.max]{XCTAssertThrowsError(try ColorAveraging.region(x:1,y:1,width:3,height:3,size:size))}
  }
  func testLiteralEncodedAverageAndOpaquePointPreserveFloatBits()throws {
    let p=Pixel(Float(bitPattern:0x3eaaaaab),-0.0,2,0.5)
    let point=try ColorAveraging.sample(region:.init(x:0,y:0,width:1,height:1),depth:.f32){_,_ in p}
    XCTAssertEqual(point.color.r.bitPattern,p.r.bitPattern);XCTAssertEqual(point.color.g.bitPattern,p.g.bitPattern);XCTAssertEqual(point.color.b.bitPattern,p.b.bitPattern);XCTAssertEqual(point.color.a,1);XCTAssertEqual(point.coverage,0.5)
    for depth in [PixelDepth.u8,.u16]{
      let q=try ColorAveraging.sample(region:.init(x:0,y:0,width:3,height:1),depth:depth){x,_ in [Pixel(0,0.25,1),Pixel(0.5,0.5,0.5),Pixel(1,0.75,0)][x]}
      XCTAssertEqual(q.color,Pixel(0.5,0.5,0.5));XCTAssertEqual(q.visitedPixels,3);XCTAssertEqual(q.contributingPixels,3);XCTAssertEqual(q.coverage,1)
    }
  }
  func testAlphaWeightedSamplingIgnoresTransparentHiddenColor()throws {
    let q=try ColorAveraging.sample(region:.init(x:0,y:0,width:3,height:1),depth:.u16){x,_ in [Pixel(1,0,0,1),Pixel(0,0,1,0.5),Pixel(0,99,0,0)][x]}
    XCTAssertEqual(q.color,Pixel(Float(2.0/3),0,Float(1.0/3)));XCTAssertEqual(q.coverage,0.5);XCTAssertEqual(q.visitedPixels,3);XCTAssertEqual(q.contributingPixels,2)
    XCTAssertThrowsError(try ColorAveraging.sample(region:.init(x:0,y:0,width:1,height:1),depth:.u8){_,_ in .clear})
    XCTAssertThrowsError(try ColorAveraging.sample(region:.init(x:0,y:0,width:1,height:1),depth:.f32){_,_ in Pixel(.nan,0,0)})
  }
  func testFloat32AveragesLinearLightAndRetainsHDR()throws {
    let q=try ColorAveraging.sample(region:.init(x:0,y:0,width:2,height:1),depth:.f32){x,_ in x==0 ? .black:.white}
    XCTAssertEqual(q.color.r,0.7353569,accuracy:0.0000001);XCTAssertEqual(q.color.r,q.color.g);XCTAssertEqual(q.color.g,q.color.b)
    let hdr=try ColorAveraging.sample(region:.init(x:0,y:0,width:3,height:1),depth:.f32){_,_ in Pixel(2,-0.1,4)}
    XCTAssertGreaterThan(hdr.color.r,1);XCTAssertLessThan(hdr.color.g,0);XCTAssertGreaterThan(hdr.color.b,2)
  }
  func testMaximumRegionCallsOnlyBoundedPixelsAndChecksCancellation()async throws {
    var count=0
    let q=try ColorAveraging.sample(region:.init(x:200000,y:200000,width:101,height:101),depth:.u8){x,y in count += 1;XCTAssertTrue((200000...200100).contains(x));XCTAssertTrue((200000...200100).contains(y));return .white}
    XCTAssertEqual(count,10201);XCTAssertEqual(q.color,.white)
    try await Task.detached {
      withUnsafeCurrentTask{$0?.cancel()}
      do{_ = try ColorAveraging.sample(region:.init(x:0,y:0,width:101,height:101),depth:.u8){_,_ in XCTFail("Cancelled sampler read a pixel");return .black};XCTFail("Expected cancellation")}catch is CancellationError{}
    }.value
  }
}
