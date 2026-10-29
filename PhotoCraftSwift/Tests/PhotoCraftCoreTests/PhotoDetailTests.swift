import XCTest
@testable import PhotoCraftCore

final class PhotoDetailTests:XCTestCase {
  func noise(_ depth:PixelDepth = .f32)throws->Surface {
    var s=try Surface(width:64,height:48,depth:depth)
    for y in 0..<48 { for x in 0..<64 { let base:Float=x<32 ? 0.25:0.75,n=Float((x*17+y*31)%19-9)/180;s.setLinearPixel(x:x,y:y,Pixel(base+n,base+n*0.7,base-n*0.5,1)) } };return s
  }
  func testNoiseReductionPreservesEdgeAndChannelControls()throws {
    let source=try noise();var f=RasterFilter(.reduceNoise);f.denoise?.strength=10;f.denoise?.preserveDetails=0;f.denoise?.reduceColorNoise=80;f.denoise?.sharpenDetails=0
    let result=try PhotoDetailEngine.render(source,filter:f)
    func variance(_ s:Surface)->Double { var values=[Double]();for y in 6..<42 { for x in 6..<26 { values.append(Double(s.linearPixel(x:x,y:y).r)) } };let m=values.reduce(0,+)/Double(values.count);return values.map{pow($0-m,2)}.reduce(0,+)/Double(values.count) }
    XCTAssertLessThan(variance(result),variance(source)*0.6)
    XCTAssertGreaterThan(result.linearPixel(x:34,y:24).r-result.linearPixel(x:29,y:24).r,0.4)
    f.denoise?.strength=0;f.denoise?.reduceColorNoise=0;f.denoise?.perChannel=["red":.init(strength:10,preserveDetails:0)]
    let red=try PhotoDetailEngine.render(source,filter:f);XCTAssertLessThan(variance(red),variance(source)*0.6)
    XCTAssertEqual(red.linearPixel(x:17,y:12).g,source.linearPixel(x:17,y:12).g,accuracy:1e-6);XCTAssertEqual(red.linearPixel(x:17,y:12).b,source.linearPixel(x:17,y:12).b,accuracy:1e-6)
  }
  func testDeconvolutionDCModesAngleAndTileContinuity()throws {
    let w=273,h=37,constant=[Float](repeating:0.43,count:w*h);var settings=SmartSharpenSettings();settings.radius=3
    for mode in [SmartSharpenSettings.Removal.lens,.motion] { settings.remove=mode;let restored=try DetailDeconvolution.restore([constant],w,h,settings);for x in [0,1,250,255,256,257,272] { XCTAssertEqual(restored[0][15*w+x],0.43,accuracy:2e-5) } }
    let source=try noise();var filter=RasterFilter(.smartSharpen);filter.sharpen?.radius=3;filter.sharpen?.amount=80
    let gaussian=try PhotoDetailEngine.render(source,filter:filter);filter.sharpen?.remove = .lens;let lens=try PhotoDetailEngine.render(source,filter:filter);filter.sharpen?.remove = .motion
    let horizontal=try PhotoDetailEngine.render(source,filter:filter);filter.sharpen?.angle=90;let vertical=try PhotoDetailEngine.render(source,filter:filter)
    XCTAssertNotEqual(gaussian,lens);XCTAssertNotEqual(lens,horizontal);XCTAssertNotEqual(horizontal,vertical)
    // A blurred vertical edge gains contrast in the direction of horizontal blur.
    let input=(0..<64*32).map { i -> Float in let x=Float(i%64);return 0.2+0.6/(1+exp(-(x-32)/2)) }
    settings.remove = .motion;settings.radius=2;settings.angle=0;let restored=try DetailDeconvolution.restore([input],64,32,settings)[0]
    XCTAssertGreaterThan(restored[16*64+33]-restored[16*64+31],input[16*64+33]-input[16*64+31])
  }
  func testTonalFadeNoiseGuardIdentityDepthAndAlpha()throws {
    for depth in PixelDepth.allCases {
      var source=try noise(depth);source.setPixel(x:1,y:1,Pixel(0.9,0.2,0.3,0));source.setPixel(x:2,y:2,Pixel(0.3,0.4,0.5,0.5))
      for kind in [RasterFilter.Kind.smartSharpen,.reduceNoise] {
        var f=RasterFilter(kind);let result=try PhotoDetailEngine.render(source,filter:f);XCTAssertEqual(result.depth,depth);XCTAssertEqual(result.pixel(x:1,y:1),source.pixel(x:1,y:1));XCTAssertEqual(result.pixel(x:2,y:2).a,source.pixel(x:2,y:2).a)
        if kind == .smartSharpen { f.sharpen?.amount=0 } else { f.denoise?.strength=0;f.denoise?.reduceColorNoise=0;f.denoise?.sharpenDetails=0 };XCTAssertEqual(try PhotoDetailEngine.render(source,filter:f),source)
      }
    }
    let source=try noise();var f=RasterFilter(.smartSharpen);f.sharpen?.reduceNoise=0;let full=try PhotoDetailEngine.render(source,filter:f)
    f.sharpen?.shadows.fadeAmount=100;f.sharpen?.shadows.tonalWidth=100;let faded=try PhotoDetailEngine.render(source,filter:f)
    let p=source.linearPixel(x:17,y:12).r;XCTAssertLessThan(abs(faded.linearPixel(x:17,y:12).r-p),abs(full.linearPixel(x:17,y:12).r-p))
    f.sharpen?.shadows.fadeAmount=0;f.sharpen?.reduceNoise=100;let reduced=try PhotoDetailEngine.render(source,filter:f);XCTAssertLessThan(abs(reduced.linearPixel(x:17,y:12).r-p),abs(full.linearPixel(x:17,y:12).r-p))
  }
  func testJpegGridAndStrictSchemas()throws {
    let source=try noise();var f=RasterFilter(.reduceNoise);f.denoise?.strength=0;f.denoise?.reduceColorNoise=0;f.denoise?.sharpenDetails=0;f.denoise?.removeJpegArtifact=true
    let a=try PhotoDetailEngine.render(source,filter:f),b=try PhotoDetailEngine.render(source,filter:f,transform:.translation(3,2));XCTAssertNotEqual(a,b);XCTAssertEqual(a.linearPixel(x:4,y:4).r,source.linearPixel(x:4,y:4).r,accuracy:1e-6)
    for data in ["{\"kind\":\"smartSharpen\",\"sharpen\":{\"remove\":\"fake\"}}","{\"kind\":\"smartSharpen\",\"sharpen\":{\"radius\":true}}","{\"kind\":\"smartSharpen\",\"sharpen\":{\"shadows\":{\"tonalWidth\":0}}}","{\"kind\":\"reduceNoise\",\"denoise\":{\"perChannel\":{\"cyan\":{}}}}","{\"kind\":\"reduceNoise\",\"denoise\":{\"removeJpegArtifact\":1}}"] { XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(data.utf8))) }
    for kind in [RasterFilter.Kind.smartSharpen,.reduceNoise] { let f=RasterFilter(kind);XCTAssertEqual(try RasterFilter.decodeJSON(Data("{\"kind\":\"\(kind.rawValue)\"}".utf8)),f);XCTAssertEqual(try JSONDecoder().decode(RasterFilter.self,from:JSONEncoder().encode(f)),f) }
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:SmartSharpenSettings.apiCapabilities));XCTAssertNoThrow(try JSONSerialization.data(withJSONObject:ReduceNoiseSettings.apiCapabilities))
  }
}
