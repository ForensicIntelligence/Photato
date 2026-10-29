import XCTest
@testable import PhotoCraftCore

final class FocusAreaTests:XCTestCase {
  func source(_ depth:PixelDepth = .u8,width:Int=128,height:Int=96)throws->Surface {
    var image=try Surface(width:width,height:height,depth:depth)
    for y in 0..<height{for x in 0..<width{
      let value:Float=x<width/2 ? ((x/4+y/4)%2==0 ? 0.1:0.9):0.45+Float(x)*0.1/Float(width)
      image.setPixel(x:x,y:y,Pixel(value,value,value))
    }};return image
  }
  func testSharpAndDefocusedRegionsAcrossDepths()throws {
    for depth in PixelDepth.allCases{
      let analysis=try FocusAreaAnalysis.prepare(source(depth)),mask=try analysis.mask(settings:.init())
      XCTAssertGreaterThan(mask.coverage(x:20,y:40),0.9);XCTAssertLessThan(mask.coverage(x:100,y:40),0.1)
      XCTAssertEqual(try analysis.mask(settings:.init()),mask)
    }
  }
  func testManualRangeDirectionZeroAndNoiseFloor()throws {
    let analysis=try FocusAreaAnalysis.prepare(source());var p=FocusAreaSettings();p.autoRange=false;p.autoNoise=false;p.range=0
    XCTAssertTrue(try analysis.mask(settings:p).bytes.allSatisfy{$0==255})
    p.range=2;let broad=try analysis.mask(settings:p);p.range=9;let narrow=try analysis.mask(settings:p)
    XCTAssertGreaterThanOrEqual(broad.bytes.filter{$0>0}.count,narrow.bytes.filter{$0>0}.count)
    p.noise=1;let noisy=try analysis.mask(settings:p);XCTAssertLessThanOrEqual(noisy.bytes.filter{$0>0}.count,narrow.bytes.filter{$0>0}.count)
    let effective=try analysis.effectiveSettings(.init());XCTAssertTrue((0...10).contains(effective.range));XCTAssertTrue((0...1).contains(effective.noise))
  }
  func testFlatSmallAndSoftenedReducedResolution()throws {
    for size in [1,3,64]{let analysis=try FocusAreaAnalysis.prepare(Surface(width:size,height:size,fill:Pixel(0.4,0.4,0.4)));XCTAssertNil(try analysis.mask(settings:.init()).bounds)}
    let analysis=try FocusAreaAnalysis.prepare(source(width:600,height:400),workingPixels:60_000);XCTAssertGreaterThan(analysis.step,1)
    var p=FocusAreaSettings();p.softenEdge=true;let mask=try analysis.mask(settings:p)
    XCTAssertEqual(mask.width,600);XCTAssertGreaterThan(mask.coverage(x:80,y:200),0.9);XCTAssertLessThan(mask.coverage(x:500,y:200),0.1);XCTAssertTrue(mask.bytes.contains{$0>0 && $0<255})
  }
  func testHardMaskRetainsComponentCleanup()throws {
    var image=try Surface(width:160,height:96,fill:Pixel(0.5,0.5,0.5))
    for y in 0..<96{for x in 0..<60{let v:Float=(x/4+y/4)%2==0 ? 0:1;image.setPixel(x:x,y:y,Pixel(v,v,v))}}
    image.setPixel(x:130,y:50,Pixel(1,1,1));image.setPixel(x:131,y:50,Pixel(0,0,0))
    var p=FocusAreaSettings();p.autoRange=false;p.autoNoise=false;p.range=1
    let mask=try FocusAreaAnalysis.prepare(image).mask(settings:p)
    XCTAssertEqual(mask.coverage(x:20,y:40),1);XCTAssertEqual(mask.coverage(x:130,y:50),0)
  }
  func testValidationAndSettingsRoundTrip()throws {
    let analysis=try FocusAreaAnalysis.prepare(source());var p=FocusAreaSettings();p.range = .nan;XCTAssertThrowsError(try analysis.mask(settings:p));p.range=11;XCTAssertThrowsError(try p.validate());p.range=5;p.noise = -1;XCTAssertThrowsError(try p.validate())
    XCTAssertThrowsError(try FocusAreaAnalysis.prepare(source(),workingPixels:0));p = .init();XCTAssertEqual(try JSONDecoder().decode(FocusAreaSettings.self,from:JSONEncoder().encode(p)),p)
  }
  func testCancellation()async throws {
    let surface=try source(width:600,height:400)
    let task=Task.detached{try Task.checkCancellation();return try FocusAreaAnalysis.prepare(surface).mask(settings:.init())};task.cancel()
    do{_=try await task.value;XCTFail("Cancelled detection committed")}catch is CancellationError{}catch{XCTFail("Unexpected \(error)")}
  }
}
