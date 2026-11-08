import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class BrushTexturePreparationTests: XCTestCase {
  func testLiteralColorAlphaOrientationAndAllDepthHeights() throws {
    for depth in PixelDepth.allCases {
      var s = try Surface(width: 4, height: 2, depth: depth)
      let colors: [Pixel] = [Pixel(1,0,0),Pixel(0,1,0),Pixel(0,0,1),.white,Pixel(0.5,0.5,0.5),Pixel(1,1,1,0.5),Pixel(1,0,0,0),.black]
      for i in colors.indices { s.setPixel(x:i%4,y:i/4,colors[i]) }
      let result = try BrushTexturePreparation.bitmap(RasterPattern(name:"Owned height",surface:s,id:"owned-height"))
      XCTAssertEqual(result.width,4); XCTAssertEqual(result.height,2)
      XCTAssertEqual(Array(result.bytes),[54,182,18,255,128,128,0,0],depth.rawValue)
      try result.validate()
    }
  }
  func testMatchesFrozenABRFormulaWithoutResamplingAndKeepsSamplesIndependent() throws {
    var s = try Surface(width: 13, height: 7, depth: .u16)
    for y in 0..<7 { for x in 0..<13 { s.setPixel(x:x,y:y,Pixel(Float(x)/12,Float(y)/6,Float((x+y)%4)/3,Float(1+(x%3))/3)) } }
    let pattern=try RasterPattern(name:"Owned colored texture",surface:s,id:"owned-colored")
    let actual=try BrushTexturePreparation.bitmap(pattern)
    var prior=Data(count:91)
    for y in 0..<7 { for x in 0..<13 { let p=s.pixel(x:x,y:y);prior[y*13+x]=UInt8((unit((p.r*0.2126+p.g*0.7152+p.b*0.0722)*p.a)*255).rounded()) } }
    XCTAssertEqual(actual.bytes,prior)
    var copy=actual;copy.bytes[0]=255;XCTAssertNotEqual(copy,actual)
    XCTAssertEqual(pattern.surface,s)
  }
  func testDimensionBoundaryExplicitRejectionAndCancellation() async throws {
    let edge=try RasterPattern(name:"Owned edge",surface:Surface(width:2500,height:1,fill:.white),id:"owned-edge")
    XCTAssertEqual(try BrushTexturePreparation.bitmap(edge).bytes,Data(repeating:255,count:2500))
    let tooWide=try RasterPattern(name:"Owned oversized",surface:Surface(width:2501,height:1,fill:.white),id:"owned-oversized")
    XCTAssertThrowsError(try BrushTexturePreparation.bitmap(tooWide))
    let task=Task.detached { while !Task.isCancelled { await Task.yield() };return try BrushTexturePreparation.bitmap(edge) }
    task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled texture conversion published")} catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
  }
}
