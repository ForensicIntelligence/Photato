import Foundation
import XCTest
@testable import PhotoCraftCore

final class PagedHistogramTests: XCTestCase {
  func testPagedMatchesOriginalEveryCounterAtAllDepthsAndEncodings() throws {
    for depth in PixelDepth.allCases {
      for encoding in SurfaceColorEncoding.allCasesForHistogram(depth) {
        var surface = try Surface(width: 129, height: 67, depth: depth, fill: Pixel(0.23, 0.61, 0.81, 0.4), colorEncoding: encoding)
        for (x,y,p) in [(0,0,Pixel(-0.2,1.3,0.5)),(63,63,Pixel(0.4,0.8,0.7,0)),(128,66,Pixel(1,0,0.5,0.01)),(65,2,Pixel(0.1,0.2,0.3))] { surface.setPixel(x:x,y:y,p) }
        for base: Pixel in [.black, .white] {
          var mask = try Surface(width:129,height:67,fill:base)
          mask.setPixel(x:0,y:0,Pixel(1.0/255,1.0/255,1.0/255));mask.setPixel(x:128,y:66,.black)
          mask.setPixel(x:64,y:30,Pixel(0.5,0.5,0.5))
          for luminance in [false,true] {
            let expected = try RGBHistogram.analyze(surface,depth:depth,luminance:luminance) { mask.pixel(x:$0,y:$1).r>0 }
            XCTAssertEqual(try RGBHistogram.paged(surface,depth:depth,luminance:luminance,mask:mask),expected,"\(depth)/\(encoding)/\(base)/\(luminance)")
          }
        }
        XCTAssertEqual(try RGBHistogram.paged(surface,depth:depth),try RGBHistogram.analyze(surface,depth:depth))
      }
    }
  }
  func testPixelLayerTranslationSelectionHolesAndAffineFallbackMatchOriginal() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width:135,height:72,depth:depth)
      var surface = try Surface(width:130,height:69,depth:depth,fill:Pixel(0.3,0.5,0.8,0.25))
      surface.setPixel(x:0,y:0,Pixel(1,0,0));surface.setPixel(x:128,y:66,.white);d.layers[0].content = .raster(surface)
      var mask = try Surface(width:135,height:72,fill:.white);mask.setPixel(x:63,y:63,.black)
      mask.setPixel(x:10,y:10,Pixel(1.0/255,1.0/255,1.0/255));let selection = try SelectionMask(coverage:mask)
      for transform in [Transform2D.translation(5,3),.translation(-2,-1),.translation(0,0),.translation(0.25,0.5),.init(a:0.9,b:0.1,c:-0.1,d:0.9,tx:2,ty:1)] {
        d.layers[0].affine=transform
        for mode in 0..<3 {
          d.selectionMask=mode==2 ? selection:nil;d.selection=mode==1 ? .init(x:3,y:4,width:65,height:63):mode==2 ? selection.bounds:nil
          for luminance in [false,true] {
            let expected = try RGBHistogram.analyze(surface,depth:depth,luminance:luminance) { x,y in
              let p=d.layers[0].coordinateTransform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(p.x)),dy=Int(floor(p.y))
              return dx>=0 && dy>=0 && dx<d.width && dy<d.height && d.selectionCoverage(x:dx,y:dy)>0
            }
            XCTAssertEqual(try RGBHistogram.pixelLayer(d.layers[0].id,in:d,luminance:luminance),expected)
          }
        }
      }
    }
  }
  func testMaximumUniformAndSparseCountsUse64BitBinsAndExcludePadding() throws {
    let n=300_000,total=UInt64(n)*UInt64(n)
    for depth in PixelDepth.allCases {
      var s=try Surface(width:n,height:n,depth:depth,fill:Pixel(0.5,0.5,0.5,0.2))
      let p=s.pixel(x:0,y:0),sample=depth == .f32 ? SRGBTransfer.linear(p):p,bin=Int(unit(sample.r)*255+0.5)
      var h=try RGBHistogram.paged(s,depth:depth)
      XCTAssertEqual(h.samples,total);XCTAssertEqual(h.channels[0][bin],total);XCTAssertEqual(h.bins(.rgb).reduce(0,+),3*total)
      s.setPixel(x:n-1,y:n-1,.white);s.setPixel(x:64,y:64,.clear)
      h=try RGBHistogram.paged(s,depth:depth)
      XCTAssertEqual(h.samples,total-1);XCTAssertEqual(h.transparent,1);XCTAssertEqual(h.channels[0][bin],total-2);XCTAssertEqual(h.channels[0][255],1)
      XCTAssertLessThan(s.allocatedBytes,500_000);XCTAssertEqual(s.tileCount,2)
      var extreme=try Surface(width:n,height:n,depth:.f32,fill:Pixel(-2,4,0.5))
      extreme.setPixel(x:n-1,y:0,.clear)
      let e=try RGBHistogram.paged(extreme,depth:.f32)
      XCTAssertEqual(e.underflow,[total-1,0,0]);XCTAssertEqual(e.overflow,[0,total-1,0]);XCTAssertEqual(e.shadows,[total-1,0,0]);XCTAssertEqual(e.highlights,[0,total-1,0])
    }
  }
  func testMaximumTranslatedMaskedLayerAndArchiveKeepCountsAndInputs() throws {
    let n=300_000
    for depth in PixelDepth.allCases {
      var d=try CraftDocument(width:n,height:n,depth:depth)
      var source=try Surface(width:n,height:n,depth:depth,fill:.white);source.setPixel(x:64,y:64,Pixel(1,0,0))
      d.layers[0].content = .raster(source);d.layers[0].x = -1;d.layers[0].y = -1
      var coverage=try Surface(width:n,height:n,fill:.white);coverage.setPixel(x:63,y:63,.black)
      d.setCoverageSelection(try SelectionMask(coverage:coverage))
      let before=d,h=try RGBHistogram.pixelLayer(d.layers[0].id,in:d)
      let count=UInt64(n-1)*UInt64(n-1)-1
      XCTAssertEqual(h.samples,count);XCTAssertEqual(h.transparent,0);XCTAssertEqual(h.channels[0][255],count);XCTAssertEqual(h.channels[1][255],count)
      XCTAssertEqual(d,before);XCTAssertLessThan(d.estimatedBytes,2_000_000)
      let bytes=try NativeArchive.encodeChunked(d),loaded=try NativeArchive.decode(bytes)
      XCTAssertEqual(try RGBHistogram.pixelLayer(loaded.layers[0].id,in:loaded),h)
      XCTAssertLessThan(bytes.count,1_000_000)
    }
  }
  func testMaskValidationEmptyBoundsAndCooperativeCancellation() async throws {
    let s=try Surface(width:65,height:67,fill:.white)
    XCTAssertThrowsError(try RGBHistogram.paged(s,depth:.u8,mask:Surface(width:64,height:67)))
    XCTAssertThrowsError(try RGBHistogram.paged(s,depth:.u8,mask:Surface(width:65,height:67,depth:.f32,colorEncoding:.linearRGB)))
    var d=try CraftDocument(width:20,height:20);d.layers[0].x=30
    XCTAssertEqual(try RGBHistogram.pixelLayer(d.layers[0].id,in:d),RGBHistogram())
    let worker=Task.detached { () throws -> RGBHistogram in
      withUnsafeCurrentTask { $0?.cancel() }
      return try RGBHistogram.paged(Surface(width:300_000,height:300_000,fill:.white),depth:.u8)
    }
    do { _=try await worker.value;XCTFail("Cancelled statistics must not publish a result") } catch is CancellationError {} 
  }
}
private extension SurfaceColorEncoding {
  static func allCasesForHistogram(_ depth:PixelDepth)->[Self] {depth == .f32 ? [.sRGB,.linearRGB]:[.sRGB]}
}
