import XCTest
@testable import PhotoCraftCore

final class ProjectedPreviewTests: XCTestCase {
  func testAreaProjectionIgnoresSourceAlphaAndQuantizesBeforeReduction() throws {
    var source = try Surface(width: 6, height: 4, depth: .f32)
    let values: [Float] = [-0.25, 0.125, 0.5, 1.25]
    for y in 0..<4 { for x in 0..<6 {
      source.setPixel(x: x, y: y, Pixel(values[(x+y)%4],0,0,(x+y)%2 == 0 ? 0 : 1))
    } }
    let before = source
    let preview = try source.reducedPreview(in: .init(x: 0, y: 0, width: 6, height: 4),
      width: 3, height: 2, encoding: .sRGB, projectingStoredSamples: { p in
        Pixel(p.r,p.r,p.r).quantized(.u8)
      })
    for y in 0..<2 { for x in 0..<3 {
      var sum: Double = 0
      for dy in 0..<2 { for dx in 0..<2 {
        let raw = values[(2*x+dx+2*y+dy)%4]
        sum += Double(Float((unit(raw)*255).rounded())/255)
      } }
      let value = Float(sum/4)
      XCTAssertTrue(preview.pixel(x:x,y:y).hasSameBits(as:Pixel(value,value,value)))
    } }
    XCTAssertEqual(source,before)
    let native = try source.reducedPreview(in: .init(x: 1, y: 1, width: 3, height: 2),
      width: 3, height: 2, encoding: .sRGB, projectingStoredSamples: { p in Pixel(p.r,p.r,p.r) })
    for y in 0..<2 { for x in 0..<3 {
      XCTAssertEqual(native.pixel(x:x,y:y).r,source.pixel(x:x+1,y:y+1).r)
      XCTAssertEqual(native.pixel(x:x,y:y).a,1)
    } }
  }

  func testMaximumImplicitProjectionRemainsBoundedAndRejectsInvalidResults() throws {
    var source = try Surface(width:300_000,height:300_000,depth:.f32,fill:Pixel(0.25,0,0,0))
    source.setPixel(x:299_999,y:299_999,Pixel(0.75,0,0,0))
    let preview = try source.reducedPreview(in:.init(x:299_998,y:299_998,width:2,height:2),
      width:1,height:1,encoding:.sRGB,projectingStoredSamples:{Pixel($0.r,$0.r,$0.r)})
    XCTAssertEqual(preview.pixel(x:0,y:0),Pixel(0.375,0.375,0.375))
    XCTAssertLessThan(source.allocatedBytes,1024*1024)
    XCTAssertThrowsError(try source.reducedPreview(in:.init(x:0,y:0,width:2,height:2),
      width:1,height:1,encoding:.sRGB,projectingStoredSamples:{_ in Pixel(.nan,0,0)}))
    XCTAssertThrowsError(try source.reducedPreview(in:.init(x:0,y:0,width:2,height:2),
      width:2,height:2,encoding:.sRGB,projectingStoredSamples:{_ in Pixel(.infinity,0,0)}))
  }

  func testActual40MPPagedCoverageAreaPreviewAgainstAllInputBytes() throws {
    let w=8000,h=5000,bytes=(0..<w*h).map {UInt8(($0%w+3*($0/w))%256)}
    let coverage=try SelectionMask(width:w,height:h,bytes:bytes).coverageSurface()
    XCTAssertGreaterThan(coverage.mappedBytes,36_000_000)
    let result=try coverage.reducedPreview(in:.init(x:0,y:0,width:w,height:h),width:100,height:100,
      encoding:.sRGB,projectingStoredSamples:{p in Pixel(p.r,p.r,p.r)})
    var sums=[Double](repeating:0,count:10_000)
    for y in 0..<h {for x in 0..<w {sums[(y/50)*100+x/80] += Double(Float(bytes[y*w+x])/255)}}
    for y in 0..<100 {for x in 0..<100 {
      XCTAssertEqual(result.pixel(x:x,y:y).r,Float(sums[y*100+x]/4000),accuracy:0.0000002)
      XCTAssertEqual(result.pixel(x:x,y:y).a,1)
    }}
  }
}
