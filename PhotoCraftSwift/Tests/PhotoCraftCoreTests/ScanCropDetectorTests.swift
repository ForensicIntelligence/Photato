import Foundation
import XCTest
@testable import PhotoCraftCore

final class ScanCropDetectorTests: XCTestCase {
  struct Oracle: Decodable {let width: Int,height: Int;let truth: [ScannedPhoto],found: [ScannedPhoto]}
  func scan(_ width: Int,_ height: Int,_ photos: [ScannedPhoto]) -> [Pixel] {
    var pixels = [Pixel](repeating:Pixel(0.97,0.97,0.96),count:width*height)
    for (k,p) in photos.enumerated() {
      let theta = p.angle * .pi / 180,s = sin(theta),c = cos(theta)
      for y in 0..<height {for x in 0..<width {
        let dx = Double(x)+0.5-p.centerX,dy = Double(y)+0.5-p.centerY,u = c*dx+s*dy,v = -s*dx+c*dy
        if abs(u)<p.width/2,abs(v)<p.height/2 {
          let t = Float(sin(u*0.05)*cos(v*0.07));pixels[y*width+x] = Pixel(0.3+0.2*t,0.2+0.1*Float(k),0.5-0.2*t)
        }
      }}
    }
    return pixels
  }
  func testMatchesLicensedRustDetectorAtOriginalAndDownsampledSizes() throws {
    let data = try Data(contentsOf:XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/ScanCrop/rust-oracle.json"))
    let cases = try JSONDecoder().decode([Oracle].self,from:data)
    for item in cases {
      let pixels = scan(item.width,item.height,item.truth)
      let result = try ScanCropDetector.find(width:item.width,height:item.height){pixels[$1*item.width+$0]}
      XCTAssertEqual(result.count,item.found.count)
      for (actual,expected) in zip(result,item.found) {
        for (a,e) in [(actual.centerX,expected.centerX),(actual.centerY,expected.centerY),(actual.width,expected.width),(actual.height,expected.height),(actual.angle,expected.angle),(actual.area,expected.area)] {XCTAssertEqual(a,e,accuracy:1e-8)}
        XCTAssertEqual(actual.corners.count,4);XCTAssertEqual((actual.corners[0].x+actual.corners[2].x)/2,actual.centerX,accuracy:1e-10)
      }
    }
  }
  func testSinglePhotoModeCombinesDisconnectedPieces() throws {
    let photos = [ScannedPhoto(centerX:45,centerY:60,width:60,height:80,angle:0),ScannedPhoto(centerX:135,centerY:60,width:60,height:80,angle:0)]
    let pixels = scan(180,120,photos)
    let separate = try ScanCropDetector.find(width:180,height:120){pixels[$1*180+$0]}
    let single = try ScanCropDetector.find(width:180,height:120,forceSingle:true){pixels[$1*180+$0]}
    XCTAssertEqual(separate.count,2);XCTAssertEqual(single.count,1);XCTAssertEqual(single[0].centerX,90,accuracy:0.1);XCTAssertGreaterThan(single[0].width,140)
  }
  func testUniformTransparentDustAndSmallInputs() throws {
    for color in [Pixel.white,.clear,Pixel(0.2,0.3,0.4)] {XCTAssertTrue(try ScanCropDetector.find(width:100,height:100){_,_ in color}.isEmpty)}
    XCTAssertTrue(try ScanCropDetector.find(width:7,height:100){_,_ in .black}.isEmpty)
    XCTAssertTrue(try ScanCropDetector.find(width:100,height:100){x,y in x==50 && y==50 ? .black:.white}.isEmpty)
    XCTAssertThrowsError(try ScanCropDetector.find(width:0,height:1){_,_ in .white})
    XCTAssertThrowsError(try ScanCropDetector.find(width:Int.max,height:10){_,_ in .white})
    XCTAssertThrowsError(try ScanCropDetector.find(width:10,height:10){_,_ in Pixel(.nan,0,0)})
  }
  func testCancellationBeforeSampling() async throws {
    let task = Task {try ScanCropDetector.find(width:800,height:800){_,_ in .white}};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled detector succeeded")} catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
  }
}
